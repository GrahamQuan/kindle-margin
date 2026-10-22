import Foundation
import KindleDomain

public actor LibraryService {
    private let repository: any LibraryRepository
    private let parser: any ClippingsParser
    private let renderer: any MarkdownRenderer
    private let dictionaryParser: any DictionaryParsing
    private let analyzer: any WordAnalyzing
    private let dictionaries: any DictionaryRepository
    public init(repository: any LibraryRepository, parser: any ClippingsParser, renderer: any MarkdownRenderer, dictionaryParser: any DictionaryParsing, dictionaries: any DictionaryRepository, analyzer: any WordAnalyzing = NoWordAnalysis()) {
        self.repository = repository; self.parser = parser; self.renderer = renderer; self.dictionaryParser = dictionaryParser; self.dictionaries = dictionaries; self.analyzer = analyzer
    }
    public func importClippings(url: URL) async throws -> ImportReport {
        let data = try readBounded(url)
        let parsed = try parser.parse(data)
        try Task.checkCancellation()
        return try await repository.importSnapshot(data, parsed: parsed)
    }
    public func annotations() async throws -> [AnnotationItem] { try await repository.annotations() }
    public func diagnostics() async throws -> [ParseDiagnostic] { try await repository.diagnostics() }
    public func update(id: UUID, value: ClippingOverride) async throws { try await repository.updateOverride(id: id, value: value) }
    public func preview(bookID: UUID, includeHidden: Bool, includeTags: Bool) async throws -> String {
        let book = try await repository.bookMetadata().first { $0.id == bookID }
        return renderer.render(try await repository.annotations().filter { $0.bookID == bookID }, includeHidden: includeHidden, includeTags: includeTags, book: book)
    }
    public func export(bookID: UUID, directory: URL, includeHidden: Bool, includeTags: Bool) async throws -> URL {
        let items = try await repository.annotations().filter { $0.bookID == bookID }
        let book = try await repository.bookMetadata().first { $0.id == bookID }
        guard let title = book?.title ?? items.first?.original.description else { throw MarginError.invalidInput("Select a book to export.") }
        return try await repository.publishMarkdown(renderer.render(items, includeHidden: includeHidden, includeTags: includeTags, book: book), bookID: bookID, directory: directory, title: title)
    }
    public func importDictionary(url: URL, csvName: String, source: String, target: String) async throws {
        let data = try readBounded(url)
        let package = try url.pathExtension.lowercased() == "csv" ? dictionaryParser.parseCSV(data, name: csvName, source: source, target: target) : dictionaryParser.parseJSON(data)
        try Task.checkCancellation()
        try await dictionaries.install(package)
    }
    public func installedDictionaries() async throws -> [DictionarySummary] { try await dictionaries.installedDictionaries() }
    public func restoreEntry(_ result: LookupResult) async throws { try await dictionaries.restoreEntry(packageID: result.packageID, entryID: result.entry.id) }
    public func prioritize(_ ids: [String]) async throws { try await dictionaries.setDictionaryPriority(ids: ids) }
    public func mergedDictionary(id: String) async throws -> Data { try JSONEncoder().encode(await dictionaries.mergedPackage(id: id)) }
    public func lookup(_ word: String) async throws -> [LookupResult] {
        var results = try await dictionaries.lookup(word)
        var seen = Set(results.map(\.id))
        for candidate in analyzer.candidates(for: word) {
            for result in try await dictionaries.lookup(candidate) where seen.insert(result.id).inserted { results.append(result) }
        }
        return results
    }
    public func searchEntries(_ query: String) async throws -> [LookupResult] { try await dictionaries.searchEntries(query) }
    public func entryChanges(_ id: String) async throws -> [EntryInspection] { try await dictionaries.entryChanges(packageID: id) }
    public func inspectEntry(_ result: LookupResult) async throws -> EntryInspection { try await dictionaries.inspectEntry(packageID: result.packageID, entryID: result.entry.id) }
    public func resolveEntry(_ item: EntryInspection, keepLocal: Bool) async throws { try await dictionaries.resolveEntry(packageID: item.packageID, entryID: item.entryID, keepLocal: keepLocal) }
    public func addEntry(packageID: String, entry: DictionaryEntry) async throws {
        guard !entry.headword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !entry.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.headword.count <= 1024, entry.definition.count <= Limits.recordCharacters else { throw MarginError.invalidInput("Headword and definition are required and must fit the import limits.") }
        try await dictionaries.edit(packageID: packageID, entry: entry, hidden: false) }
    public func removeDictionary(_ id: String) async throws { try await dictionaries.removeDictionary(id: id) }
    public func restoreDictionary(_ id: String) async throws { try await dictionaries.restoreDictionary(id: id) }
    public func removedDictionaries() async throws -> [DictionarySummary] { try await dictionaries.removedDictionaries() }
    public func snapshots() async throws -> [SnapshotInfo] { try await repository.snapshots() }
    public func snapshotText(_ id: String) async throws -> String {
        let data = try await repository.snapshotData(hash: id)
        let parsed = try parser.parse(data)
        return String(data: data, encoding: parsed.encoding == "UTF-16LE" ? .utf16LittleEndian : parsed.encoding == "UTF-16BE" ? .utf16BigEndian : .utf8) ?? "Encoding unavailable"
    }
    public func reparse(_ id: String) async throws -> ImportReport { try await repository.reparseSnapshot(parser.parse(await repository.snapshotData(hash: id))) }
    public func books() async throws -> [BookMetadata] { try await repository.bookMetadata() }
    public func saveBook(_ metadata: BookMetadata) async throws { try await repository.saveBookMetadata(metadata) }
    public func preferences() async throws -> [String: String] { try await repository.preferences() }
    public func setPreference(_ key: String, value: String) async throws { try await repository.setPreference(key, value: value) }
    public func editEntry(_ result: LookupResult, definition: String, hidden: Bool = false) async throws {
        var entry = result.entry; entry.definition = definition
        guard !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MarginError.invalidInput("Definition cannot be empty.") }
        try await dictionaries.edit(packageID: result.packageID, entry: entry, hidden: hidden)
    }
    private func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: Limits.importBytes + 1) ?? Data()
        guard data.count <= Limits.importBytes else { throw MarginError.invalidInput("File exceeds the 64 MiB import limit.") }
        return data
    }
}

public actor JobCoordinator {
    private let repository: any LibraryRepository
    private var active: [UUID: Task<Void, Never>] = [:]
    private var requests: Set<UUID> = []
    private var submittingDevices: Set<UUID> = []
    public init(repository: any LibraryRepository) { self.repository = repository }
    public func recover() async throws {
        for var job in try await repository.jobs() {
            requests.insert(job.requestID)
            if [.queued, .preparing, .running, .verifying, .cancelling].contains(job.state) {
                job.state = job.deviceID == nil ? .failed : .needsReconciliation
                job.stage = "Interrupted by app restart"
                job.error = job.deviceID == nil ? "Review and start a new request." : "Rescan the device before any retry."
                try await repository.saveJob(job)
            }
        }
    }
    public func submit(requestID: UUID, kind: String, deviceID: UUID? = nil, plan: Data? = nil, operation: @escaping @Sendable () async throws -> Void) async throws {
        guard !requests.contains(requestID) else { return }
        if let deviceID {
            guard submittingDevices.insert(deviceID).inserted else { throw MarginError.unavailable("A write request is already being prepared for this device.") }
        }
        defer { if let deviceID { submittingDevices.remove(deviceID) } }
        if let deviceID {
            let target = plan.flatMap { try? JSONDecoder().decode(DeviceJournal.self, from: $0) }
            let blocking = try await repository.jobs().contains { job in
                let prior = job.plan.flatMap { try? JSONDecoder().decode(DeviceJournal.self, from: $0) }
                let sameIdentity = target != nil && prior != nil && !target!.temporaryIdentity && !prior!.temporaryIdentity && target!.identity == prior!.identity
                return (job.deviceID == deviceID || sameIdentity) && [.queued, .preparing, .running, .verifying, .cancelling, .needsReconciliation].contains(job.state)
            }
            guard !blocking else { throw MarginError.unavailable("This device has an active or unresolved write. Finish or reconcile that task before confirming another write.") }
        }
        guard requests.insert(requestID).inserted else { return }
        var job = JobRecord(requestID: requestID, kind: kind, deviceID: deviceID)
        job.plan = plan; job.events = [.init(stage: "Queued", message: "Request accepted")]
        do { try await repository.saveJob(job) } catch { requests.remove(requestID); throw error }
        let queued = job
        active[job.id] = Task {
            var record = queued
            do {
                try Task.checkCancellation()
                record.state = .running; record.stage = kind
                try await repository.saveJob(record)
                try await operation()
                record = (try await repository.jobs()).first { $0.id == queued.id } ?? record
                record.state = .completed; record.stage = "Completed"
            } catch is CancellationError { record.state = deviceID == nil ? .cancelled : .needsReconciliation; record.stage = deviceID == nil ? "Cancelled" : "Device outcome requires reconciliation" }
            catch { record.state = deviceID == nil ? .failed : .needsReconciliation; record.stage = deviceID == nil ? "Failed" : "Device outcome requires reconciliation"; record.error = error.localizedDescription }
            if let latest = try? await repository.jobs().first(where: { $0.id == record.id }) { record.events = latest.events }
            record.events = (record.events ?? []) + [.init(stage: record.stage, message: record.error ?? record.stage)]
            do { try await repository.saveJob(record) } catch { /* The last durable running state is recovered on restart. */ }
            self.finished(record.id)
        }
    }
    public func perform<Value: Sendable>(requestID: UUID, kind: String, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let result = JobResult<Value>()
        try await submit(requestID: requestID, kind: kind) { do { let value = try await operation(); await result.set(.success(value)) } catch { await result.set(.failure(error)); throw error } }
        guard let job = try await repository.jobs().first(where: { $0.requestID == requestID }) else { throw MarginError.unavailable("Job was not persisted.") }
        await active[job.id]?.value
        return try await result.value()
    }
    public func stage(requestID: UUID, stage: String) async throws {
        try Task.checkCancellation()
        guard var record = try await repository.jobs().first(where: { $0.requestID == requestID }) else { return }
        record.stage = stage
        if stage == "Verifying" { record.state = .verifying }
        record.events = (record.events ?? []) + [.init(stage: stage, message: stage)]
        try await repository.saveJob(record)
    }
    public func reconcile(id: UUID, state: JobState, evidence: String) async throws {
        guard [.completed,.failed,.cancelled].contains(state), var record = try await repository.jobs().first(where: { $0.id == id }), record.state == .needsReconciliation else { throw MarginError.conflict("Job is not awaiting reconciliation.") }
        record.state = state; record.stage = "Reconciled"; record.outcome = evidence; record.error = nil
        record.events = (record.events ?? []) + [.init(stage: "Reconciled", message: evidence)]
        try await repository.saveJob(record)
    }
    private func finished(_ id: UUID) { active.removeValue(forKey: id) }
    public func cancel(_ id: UUID) async {
        guard let task = active[id] else { return }
        task.cancel()
        if var job = try? await repository.jobs().first(where: { $0.id == id }), [.queued,.preparing,.running,.verifying].contains(job.state) {
            job.state = .cancelling; job.stage = "Waiting for cancellation to finish"; try? await repository.saveJob(job)
        }
    }
    public func jobs() async throws -> [JobRecord] { try await repository.jobs() }
    public func cancelAllAndWait() async { let tasks = Array(active.values); for task in tasks { task.cancel() }; for task in tasks { await task.value } }
}

private actor JobResult<Value: Sendable> {
    private var result: Result<Value, Error>?
    func set(_ result: Result<Value, Error>) { self.result = result }
    func value() throws -> Value { guard let result else { throw CancellationError() }; return try result.get() }
}
