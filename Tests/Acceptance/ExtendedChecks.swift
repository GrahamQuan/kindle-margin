import Foundation
import CryptoKit
import KindleDomain
import KindleApplication
import KindlePersistence
import KindleClippings
import KindleDictionary
import KindleDevice
import KindleConversion

actor FakeMTP: DeviceTransport {
    nonisolated let root: DeviceFileRef
    private var objects: [DeviceFileRef: (String, Data)] = [:]
    private var connected = true
    private var deletionLimit: Int?
    private var deletedCount = 0
    private var failAfterUpload = false
    private var failDownload = false
    init() { root = .init(deviceID: UUID(), sessionID: UUID(), token: UUID()) }
    func faultAfterUpload(_ value: Bool) { failAfterUpload = value; failDownload = false }
    func disconnect() { connected = false }
    func failDeletion(after count: Int?) { deletionLimit = count; deletedCount = 0 }
    private func validate(_ ref: DeviceFileRef) throws { guard connected, ref.sessionID == root.sessionID, ref.deviceID == root.deviceID else { throw MarginError.staleSession } }
    func list(in directory: DeviceFileRef) throws -> [DeviceEntry] { try validate(directory); return objects.map { .init(id: $0.key, name: $0.value.0, size: Int64($0.value.1.count), isDirectory: false) } }
    func download(_ file: DeviceFileRef, to destination: URL) throws { try validate(file); guard !failDownload, let object = objects[file] else { throw MarginError.unavailable("Synthetic disconnected read") }; try object.1.write(to: destination, options: .withoutOverwriting) }
    func upload(_ source: URL, into directory: DeviceFileRef, name: String) throws -> DeviceFileRef {
        try validate(directory); guard !objects.values.contains(where: { $0.0 == name }) else { throw MarginError.conflict("Synthetic naming conflict") }
        let ref = DeviceFileRef(deviceID: root.deviceID, sessionID: root.sessionID, token: UUID()); objects[ref] = (name, try Data(contentsOf: source)); failDownload = failAfterUpload; return ref
    }
    func delete(_ file: DeviceFileRef) throws { try validate(file); if let limit = deletionLimit, deletedCount >= limit { throw MarginError.unavailable("Synthetic partial deletion") }; deletedCount += 1; guard objects.removeValue(forKey: file) != nil else { throw MarginError.staleSession } }
    nonisolated func connection() -> DeviceConnection {
        .init(info: .init(id: root.deviceID, identity: "synthetic-reliable-identity", temporaryIdentity: false, name: "Synthetic MTP", model: "Test", firmware: "Test", transport: "Fake MTP", status: .available, explanation: "Synthetic test capability"), roots: [.init(id: root, name: "Storage", size: 0, isDirectory: true)], transport: self, verifiedFormats: ["txt"])
    }
}
struct BrokenDownload: PackageDownloadTransport {
    let cancellation: Bool
    func download(_ url: URL, expectedSize: Int64, to destination: URL) async throws {
        try Data("partial".utf8).write(to: destination)
        if cancellation { throw CancellationError() }; throw URLError(.networkConnectionLost)
    }
}
func extendedChecks(root: URL) async throws {
    let storeRoot = root.appendingPathComponent("extended")
    let store = try SQLiteLibrary(root: storeRoot)
    let parser = SnapshotParser()
    let text = "Title (Subtitle) (Author)\n- Your Highlight at Location 1 | Added on Thursday, October 22, 2026 09:30:00\n\nOriginal\n==========\n"
    let data = Data(text.utf8); let parsed = try parser.parse(data)
    _ = try await store.importSnapshot(data, parsed: parsed)
    let first = try await store.annotations()[0]
    try await store.updateOverride(id: first.id, value: .init(body: "Corrected", tags: ["tag"]))
    _ = try await store.reparseSnapshot(parsed)
    let reparsed = try await store.annotations(); let original = try await store.snapshotData(hash: parsed.hash)
    try check(reparsed.count == 1 && reparsed[0].body == "Corrected" && original == data, "CLP-03 snapshot inspection and reparse preserve original and override")
    try check(parsed.clippings[0].sourceTimestamp?.status == .localDateTime && parsed.clippings[0].sourceTimestamp?.components?.timeZone == nil, "CLP-01 timestamp components do not invent a timezone")
    try check(SourceMetadata.timestamp(nil).status == .missing && SourceMetadata.timestamp("unknown").status == .unparsed, "CLP-01 missing and unparsed timestamps distinct")
    try check(SourceMetadata.book("Title (Subtitle) (Author)").title == "Title (Subtitle) (Author)", "CLP-01 ambiguous parentheses preserve full description")
    let service = LibraryService(repository: store, parser: parser, renderer: StandardMarkdownRenderer(), dictionaryParser: DictionaryParser(), dictionaries: store, analyzer: EnglishAnalyzer())
    try await service.saveBook(.init(id: first.bookID, title: "Confirmed title", author: "Confirmed author"))
    let preview = try await service.preview(bookID: first.bookID, includeHidden: false, includeTags: true)
    try check(preview.contains("# Confirmed title") && preview.contains("Author: Confirmed author"), "MD-01 explicit book metadata appears in shared renderer")
    try await service.setPreference("includeTags", value: "false")
    let reopened = try SQLiteLibrary(root: storeRoot); let preferences = try await reopened.preferences()
    try check(preferences["includeTags"] == "false", "UI-03 export and layout preferences survive reopening")
    var package = DictionaryPackage(id: "extended", name: "Test", sourceLanguage: "en", targetLanguage: "en", license: "Synthetic", entries: [.init(id: "a", headword: "walk", definition: "Travel on foot", forms: ["walked"])])
    try await store.install(package)
    let found = try await store.searchEntries("Travel foot")
    try check(found.count == 1, "DICT-01 FTS searches definitions using indexed terms")
    var local = package.entries[0]; local.definition = "Local correction"
    try await store.edit(packageID: package.id, entry: local, hidden: false)
    package.version = "2"; package.entries[0].headword = "different"
    try await store.install(package)
    let conflict = try await store.inspectEntry(packageID: package.id, entryID: "a")
    try check(conflict.conflicted && conflict.original?.headword == "different" && conflict.local?.headword == "walk", "DICT-02 identity change exposes original and local conflict")
    try await store.resolveEntry(packageID: package.id, entryID: "a", keepLocal: true)
    let preserved = try await store.lookup("walk"); let upstream = try await store.lookup("different")
    try check(preserved.count == 1 && upstream.count == 1, "DICT-02 keep-local resolution separates conflicting identities")
    try await store.removeDictionary(id: package.id)
    let removedLookup = try await store.lookup("walk"); let removed = try await store.removedDictionaries()
    try check(removedLookup.isEmpty && removed.count == 1, "DICT-02 removed dictionary remains recoverable")
    try await store.restoreDictionary(id: package.id)
    let restored = try await store.lookup("walk")
    try check(restored.count == 1, "DICT-02 dictionary restoration retains corrections")
    let packageData = try JSONEncoder().encode(package)
    let digest = SHA256.hash(data: packageData).map { String(format: "%02x", $0) }.joined()
    let catalog = CatalogPackage(id: package.id, version: package.version, sourceLanguage: "en", targetLanguage: "en", size: Int64(packageData.count), sha256: digest, url: URL(string: "https://synthetic.invalid/dictionary.json")!, source: "Synthetic", license: "Synthetic")
    for cancellation in [false, true] {
        let downloads = try DictionaryDownloadService(catalog: [catalog], transport: BrokenDownload(cancellation: cancellation), parser: DictionaryParser(), repository: store)
        try await rejects("DICT-03 \(cancellation ? "cancellation" : "disconnection") preserves installed package") { try await downloads.download(id: package.id, workDirectory: root.appendingPathComponent("download-failures")) }
    }
    let retry = try DictionaryDownloadService(catalog: [catalog], transport: SyntheticDownload(data: packageData), parser: DictionaryParser(), repository: store)
    try await retry.download(id: package.id, workDirectory: root.appendingPathComponent("download-failures"))
    let afterUpdate = try await store.installedDictionaries()
    try check(afterUpdate.first?.conflicts == 0, "DICT-02 user-created entries are not mistaken for upstream deletions")
    var changedLanguage = package; changedLanguage.sourceLanguage = "fr"
    try await rejects("DICT-02 package language identity changes preserve installed version") { try await store.install(changedLanguage) }
    try check(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("download-failures").path).isEmpty, "DICT-03 retry installs verified package and clears owned temporary files")
    try await rejects("DICT-03 HTTP and unconfigured hosts rejected before networking") { try await HTTPSPackageTransport(allowedHosts: ["synthetic.invalid"]).download(URL(string: "http://other.invalid/a")!, expectedSize: 20, to: root.appendingPathComponent("forbidden")) }
    let input = root.appendingPathComponent("object-test.txt"); try Data("Synthetic object book".utf8).write(to: input)
    let fake = FakeMTP(); let connection = fake.connection()
    let coordinator = JobCoordinator(repository: store); let workflow = DeviceWorkflow(coordinator: coordinator, workDirectory: root.appendingPathComponent("object-jobs"))
    let plan = try await workflow.planTransfer(connection: connection, source: input, format: "txt", directory: fake.root, name: "test.txt")
    await fake.faultAfterUpload(true)
    try await workflow.transfer(connection: connection, plan: plan, directoryPath: [], requestID: plan.id)
    var job: JobRecord?
    for _ in 0..<200 {
        job = try await coordinator.jobs().first { $0.requestID == plan.id }
        if job?.state == .needsReconciliation { break }; try await Task.sleep(for: .milliseconds(10))
    }
    try check(job?.state == .needsReconciliation && job?.plan != nil && job?.events?.contains(where: { $0.stage == "Verifying" }) == true, "JOB-01 upload followed by read failure preserves immutable plan and verification stage")
    guard let job else { throw CheckFailure(message: "Missing journal") }
    try await rejects("JOB-01 unresolved device outcomes block new writes") { try await workflow.transfer(connection: connection, plan: plan, directoryPath: [], requestID: UUID()) }
    try await rejects("JOB-01 reliable identity blocks unresolved writes across new discovery IDs") { try await coordinator.submit(requestID: UUID(), kind: "Transfer", deviceID: UUID(), plan: job.plan) {} }
    var altered = job; altered.deviceID = UUID()
    try await rejects("JOB-01 persisted target cannot be changed") { try await store.saveJob(altered) }
    let recovered = JobCoordinator(repository: store); try await recovered.recover()
    await fake.faultAfterUpload(false)
    let recovery = DeviceWorkflow(coordinator: recovered, workDirectory: root.appendingPathComponent("reconcile"))
    _ = try await recovery.reconcile(job: job, connection: connection)
    let complete = try await recovered.jobs().first { $0.id == job.id }; let objects = try await fake.list(in: fake.root)
    try check(complete?.state == .completed && objects.count == 1, "JOB-01 restart reconciliation reads object hashes without duplicate upload")
    let backupURL = root.appendingPathComponent("standalone-backup.txt")
    try await recovery.backup(connection: connection, file: objects[0], destination: backupURL)
    try check(try Data(contentsOf: backupURL) == Data(contentsOf: input), "BOOK-01 standalone backup publishes verified content")
    try await rejects("BOOK-04 standalone backup preserves an existing destination") { try await recovery.backup(connection: connection, file: objects[0], destination: backupURL) }

    let deletion = try await recovery.planDeletion(connection: connection, entries: objects, parent: fake.root, backupDirectory: root.appendingPathComponent("object-backups"))
    try await recovery.delete(connection: connection, plan: deletion, directoryPath: [], requestID: deletion.id)
    for _ in 0..<200 { if try await recovered.jobs().first(where: { $0.requestID == deletion.id })?.state == .completed { break }; try await Task.sleep(for: .milliseconds(10)) }
    let empty = try await fake.list(in: fake.root)
    try check(empty.isEmpty && FileManager.default.fileExists(atPath: root.appendingPathComponent("object-backups/" + deletion.id.uuidString + "/0-test.txt").path), "BOOK-05 fake MTP deletion retains verified backup")
    _ = try await fake.upload(input, into: fake.root, name: "one.txt")
    _ = try await fake.upload(input, into: fake.root, name: "two.txt")
    let two = try await fake.list(in: fake.root)
    let partialPlan = try await recovery.planDeletion(connection: connection, entries: two, parent: fake.root, backupDirectory: root.appendingPathComponent("partial-backups"))
    await fake.failDeletion(after: 1)
    try await recovery.delete(connection: connection, plan: partialPlan, directoryPath: [], requestID: partialPlan.id)
    var partialJob: JobRecord?
    for _ in 0..<200 { partialJob = try await recovered.jobs().first { $0.requestID == partialPlan.id }; if partialJob?.state == .needsReconciliation { break }; try await Task.sleep(for: .milliseconds(10)) }
    guard let partialJob else { throw CheckFailure(message: "Missing partial deletion job") }
    let evidence = try await recovery.reconcile(job: partialJob, connection: connection)
    let partialObjects = try await fake.list(in: fake.root)
    try check(evidence.contains("partial") && partialObjects.count == 1, "BOOK-05 partial deletion is reconciled without replaying remaining deletes")
    let diskRoot = root.appendingPathComponent("association-device")
    try FileManager.default.createDirectory(at: diskRoot.appendingPathComponent("Book.sdr"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: diskRoot.appendingPathComponent("Book-other.sdr"), withIntermediateDirectories: true)
    for name in ["Book.txt", "Book.sdr/notes", "Book-other.sdr/notes"] { try Data("Synthetic".utf8).write(to: diskRoot.appendingPathComponent(name)) }
    let disk = try MountedVolumeTransport(root: diskRoot, deviceID: UUID(), verifiedWritable: true)
    let diskConnection = DeviceConnection(info: connection.info, roots: [.init(id: disk.rootReference, name: "Storage", size: 0, isDirectory: true)], transport: disk, verifiedFormats: ["txt"])
    let diskFiles = try await disk.list(in: disk.rootReference)
    let scope = try await recovery.deletionScope(connection: diskConnection, main: diskFiles.first { $0.name == "Book.txt" }!, parent: disk.rootReference)
    try check(scope.map(\.relativeName).sorted() == ["Book.sdr/notes", "Book.txt"], "BOOK-05 association discovery includes only exact .sdr scope")
    await fake.disconnect()
    try await rejects("DEV-04 fake MTP session invalidates opaque references") { _ = try await fake.list(in: fake.root) }
    let disguised = root.appendingPathComponent("disguised.epub"); try Data("Actually plain text".utf8).write(to: disguised)
    try check(try BookInspector().inspect(disguised).format == "txt", "BOOK-01 inspection uses content rather than filename extension")
    let protected = root.appendingPathComponent("protected.pdf"); try Data("%PDF-1.7\n/Encrypt 1 0 R\n%%EOF".utf8).write(to: protected)
    try check(try BookInspector().inspect(protected).protected, "BOOK-01 protected PDF is excluded")
    var mobi = Data(count: 512)
    func put(_ value: Int, at offset: Int, length: Int) { for index in 0..<length { mobi[offset + index] = UInt8((value >> (8 * (length - index - 1))) & 255) } }
    mobi.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8)); put(2, at: 76, length: 2); put(94, at: 78, length: 4); put(400, at: 86, length: 4)
    mobi.replaceSubrange(110..<114, with: Data("MOBI".utf8)); put(112, at: 114, length: 4); put(42, at: 126, length: 4); put(1, at: 134, length: 4)
    put(1033, at: 190, length: 4); put(2052, at: 194, length: 4); put(6, at: 198, length: 4); mobi.replaceSubrange(400..<404, with: Data("INDX".utf8))
    let dictionaryFile = root.appendingPathComponent("synthetic-dictionary.mobi"); try mobi.write(to: dictionaryFile)
    let dictionaryInspection = try BookInspector().inspect(dictionaryFile)
    try check(dictionaryInspection.dictionaryIdentity == 42 && dictionaryInspection.dictionaryLanguages?.0 == 1033 && dictionaryInspection.dictionaryLanguages?.1 == 2052, "DICT-04 structural dictionary identity, languages, and index record recognized")
    put(0, at: 190, length: 4); try mobi.write(to: dictionaryFile)
    try check(try BookInspector().inspect(dictionaryFile).dictionaryIdentity == nil, "DICT-04 ordinary MOBI is not treated as an installable dictionary")
    let damaged = root.appendingPathComponent("damaged.epub"); try Data([0x50,0x4b,3,4,0,0]).write(to: damaged)
    try await rejects("BOOK-01 malformed ZIP rejected") { _ = try BookInspector().inspect(damaged) }
}
