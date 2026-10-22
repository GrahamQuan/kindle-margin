import Foundation
import Features
import KindleApplication
import KindleDomain
import KindlePersistence
import KindleClippings
import KindleDictionary

@MainActor func dictionaryDraftChecks(store: SQLiteLibrary, coordinator: JobCoordinator, entry: LookupResult) async throws {
    let gate = SuspendedDictionaryRepository(base: store)
    let service = LibraryService(repository: store, parser: SnapshotParser(), renderer: StandardMarkdownRenderer(), dictionaryParser: DictionaryParser(), dictionaries: gate)
    let model = WorkspaceModel(service: service, coordinator: coordinator)
    model.entrySources[entry.id] = entry; model.entryDrafts[entry.id] = "Submitted definition"
    let save = Task { try await model.saveEntry(entry) }
    for _ in 0..<100 where !(await gate.isWaiting) { try await Task.sleep(for: .milliseconds(10)) }
    guard await gate.isWaiting else { save.cancel(); throw CheckFailure(message: "Dictionary save did not reach persistence gate") }
    model.entryDrafts[entry.id] = "Newer text from another window"
    try await model.saveEntry(entry)
    await gate.release()
    try await save.value
    let saved = try await store.lookup(entry.entry.headword).first { $0.id == entry.id }
    try check(saved?.entry.definition == "Submitted definition" && model.entryDrafts[entry.id] == "Newer text from another window" && model.hasDrafts, "RUI-A12 in-flight dictionary save retains newer edits and rejects duplicate submission")
    await gate.failNextEdit()
    do { try await model.saveEntry(entry); throw CheckFailure(message: "Injected dictionary failure unexpectedly succeeded") }
    catch is CheckFailure { throw CheckFailure(message: "Injected dictionary failure unexpectedly succeeded") }
    catch { try check(model.entryDrafts[entry.id] == "Newer text from another window" && model.saving.isEmpty, "RUI-A08 failed dictionary save retains its draft and releases lock") }
    try await store.restoreEntry(packageID: entry.packageID, entryID: entry.entry.id)
}

private actor SuspendedDictionaryRepository: DictionaryRepository {
    let base: SQLiteLibrary
    private var continuation: CheckedContinuation<Void, Never>?
    private var shouldSuspend = true
    private var shouldFail = false
    init(base: SQLiteLibrary) { self.base = base }
    var isWaiting: Bool { continuation != nil }
    func release() { continuation?.resume(); continuation = nil }
    func failNextEdit() { shouldFail = true }
    func edit(packageID: String, entry: DictionaryEntry, hidden: Bool) async throws {
        if shouldFail { shouldFail = false; throw MarginError.unavailable("Synthetic dictionary persistence failure") }
        if shouldSuspend { shouldSuspend = false; await withCheckedContinuation { continuation = $0 } }
        try await base.edit(packageID: packageID, entry: entry, hidden: hidden)
    }
    func searchEntries(_ text: String) async throws -> [LookupResult] { try await base.searchEntries(text) }
    func inspectEntry(packageID: String, entryID: String) async throws -> EntryInspection { try await base.inspectEntry(packageID: packageID, entryID: entryID) }
    func entryChanges(packageID: String) async throws -> [EntryInspection] { try await base.entryChanges(packageID: packageID) }
    func resolveEntry(packageID: String, entryID: String, keepLocal: Bool) async throws { try await base.resolveEntry(packageID: packageID, entryID: entryID, keepLocal: keepLocal) }
    func removeDictionary(id: String) async throws { try await base.removeDictionary(id: id) }
    func restoreDictionary(id: String) async throws { try await base.restoreDictionary(id: id) }
    func removedDictionaries() async throws -> [DictionarySummary] { try await base.removedDictionaries() }
    func installedDictionaries() async throws -> [DictionarySummary] { try await base.installedDictionaries() }
    func restoreEntry(packageID: String, entryID: String) async throws { try await base.restoreEntry(packageID: packageID, entryID: entryID) }
    func setDictionaryPriority(ids: [String]) async throws { try await base.setDictionaryPriority(ids: ids) }
    func install(_ package: DictionaryPackage) async throws { try await base.install(package) }
    func lookup(_ query: String) async throws -> [LookupResult] { try await base.lookup(query) }
    func mergedPackage(id: String) async throws -> DictionaryPackage { try await base.mergedPackage(id: id) }
}
