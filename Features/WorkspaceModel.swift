import SwiftUI
import KindleDomain
import KindleApplication

public enum WorkspacePage: String, CaseIterable, Identifiable {
    case annotations = "Annotations", library = "Device Library", dictionaries = "Dictionaries", tasks = "Tasks", settings = "Settings"
    public var id: String { rawValue }
    var icon: String {
        switch self { case .annotations: return "text.quote"; case .library: return "books.vertical"; case .dictionaries: return "character.book.closed"; case .tasks: return "list.bullet.clipboard"; case .settings: return "gearshape" }
    }
}
@MainActor @Observable public final class WorkspaceModel {
    public let service: LibraryService
    public let coordinator: JobCoordinator
    public var device: DeviceWorkspaceModel?
    public var snapshots: [SnapshotInfo] = []
    public var books: [BookMetadata] = []
    public var bookTitleDraft = ""
    public var bookAuthorDraft = ""
    public var bookFilter: UUID?
    public var selectedAnnotationText = ""
    public var tagDrafts: [UUID: String] = [:]
    public var changes: [EntryInspection] = []
    public var removedDictionaries: [DictionarySummary] = []
    public var managementDictionary: String?
    public var newHeadword = ""
    public var newDefinition = ""
    public var searchDefinitions = false
    public var selectedJob: UUID?
    public var clearCacheAction: (() -> Void)?
    public var diagnosticsAction: (() -> Void)?
    public var downloadCatalogAction: (() -> Void)?
    public var reconcileAction: ((JobRecord) -> Void)?
    public var retryAction: ((JobRecord) -> Void)?
    public var page: WorkspacePage = .annotations
    public var annotations: [AnnotationItem] = []
    public var selection: UUID?
    public var search = ""
    public var kind: ClippingKind?
    public var showHidden = false
    public var exportHidden = false
    public var saving: Set<String> = []
    public var entrySources: [String: LookupResult] = [:]
    public var entrySavedValues: [String: String] = [:]
    public var entrySavedEdits: [String: Bool] = [:]
    public var lookupState = "idle"
    public var lookupError: String?
    private var lookupGeneration = 0
    public var includeTags = true
    public var drafts: [UUID: String] = [:]
    public var collapsed: Set<WorkspacePage> = []
    public var preview: String?
    public var diagnostics: [ParseDiagnostic] = []
    public var dictionaryQuery = ""
    public var results: [LookupResult] = []
    public var installedDictionaries: [DictionarySummary] = []
    public var converterStatus = "No converter configured"
    public var selectConverterAction: (() -> Void)?
    public var convertLocalAction: (() -> Void)?
    public var exportDictionaryAction: ((String) -> Void)?
    public var selectedEntry: String?
    public var entryDrafts: [String: String] = [:]
    public var jobs: [JobRecord] = [] { didSet { device?.jobs = jobs } }
    public var message: String?
    public var busy = false
    private var runningActions = 0
    public var csvName = "My Dictionary"
    public var csvSource = "en"
    public var csvTarget = "en"
    public var importClippingsAction: (() -> Void)?
    public var importDictionaryAction: (() -> Void)?
    public var exportAction: ((UUID) -> Void)?
    public init(service: LibraryService, coordinator: JobCoordinator) { self.service = service; self.coordinator = coordinator }
    public var selected: AnnotationItem? { annotations.first { $0.id == selection } }
    public var entry: LookupResult? { results.first { $0.id == selectedEntry } }
    public var hasTools: Bool { (page == .annotations && selected != nil) || (page == .dictionaries && entry != nil) || (page == .library && device?.selected != nil) || (page == .tasks && jobs.contains(where: { $0.id == selectedJob })) }
    public var filtered: [AnnotationItem] {
        annotations.filter { (bookFilter == nil || $0.bookID == bookFilter) && (showHidden || !$0.override.hidden) && (kind == nil || $0.original.kind == kind) && (search.isEmpty || $0.body.localizedCaseInsensitiveContains(search) || $0.original.description.localizedCaseInsensitiveContains(search)) }
    }
    public func refresh() async {
        do {
            snapshots = try await service.snapshots(); books = try await service.books(); removedDictionaries = try await service.removedDictionaries()
            installedDictionaries = try await service.installedDictionaries(); annotations = try await service.annotations(); jobs = try await coordinator.jobs(); diagnostics = try await service.diagnostics()
            if !annotations.contains(where: { $0.id == selection }) { selection = nil }
        } catch { message = error.localizedDescription }
    }
    public func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task { runningActions += 1; busy = true; defer { runningActions -= 1; busy = runningActions > 0 }; do { try await action(); await refresh() } catch { message = error.localizedDescription } }
    }
    public func isChanged(_ item: AnnotationItem) -> Bool {
        (drafts[item.id] ?? item.body) != item.body || (tagDrafts[item.id] ?? item.override.tags.joined(separator: ", ")) != item.override.tags.joined(separator: ", ")
    }
    public var hasDrafts: Bool {
        annotations.contains(where: isChanged) || drafts.keys.contains { id in !annotations.contains { $0.id == id } } || tagDrafts.keys.contains { id in !annotations.contains { $0.id == id } } || entryDrafts.contains { key, value in value != entrySources[key]?.entry.definition }
    }
    public func discardDrafts() { drafts = [:]; tagDrafts = [:]; entryDrafts = [:]; entrySources = [:] }
    public func saveDraft(_ item: AnnotationItem) async throws {
        let key = item.id.uuidString
        guard !saving.contains(key) else { return }
        saving.insert(key); defer { saving.remove(key) }
        let text = drafts[item.id]; let tags = tagDrafts[item.id]
        var value = item.override
        value.body = text ?? item.body
        value.tags = (tags ?? item.override.tags.joined(separator: ", ")).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try await service.update(id: item.id, value: value)
        if drafts[item.id] == text { drafts.removeValue(forKey: item.id) }
        if tagDrafts[item.id] == tags { tagDrafts.removeValue(forKey: item.id) }
        await refresh()
    }
    public func saveEntry(_ item: LookupResult) async throws {
        guard !saving.contains(item.id) else { return }
        saving.insert(item.id); defer { saving.remove(item.id) }
        let text = entryDrafts[item.id] ?? item.entry.definition
        try await service.editEntry(item, definition: text)
        entrySavedValues[item.id] = text; entrySavedEdits[item.id] = true
        if entryDrafts[item.id] == text { entryDrafts.removeValue(forKey: item.id); entrySources.removeValue(forKey: item.id) }
        if var source = entrySources[item.id] { source.entry.definition = text; entrySources[item.id] = source }
        if let index = results.firstIndex(where: { $0.id == item.id }) { results[index].entry.definition = text }
    }
    public func restoreEntry(_ item: LookupResult) async throws {
        guard !saving.contains(item.id) else { return }
        saving.insert(item.id); defer { saving.remove(item.id) }
        let submittedDraft = entryDrafts[item.id]
        try await service.restoreEntry(item)
        let restored = try await service.lookup(item.entry.headword).first { $0.id == item.id }
        if entryDrafts[item.id] == submittedDraft { entryDrafts[item.id] = nil; entrySources[item.id] = nil }
        else if let restored { entrySources[item.id] = restored }
        entrySavedValues[item.id] = restored?.entry.definition; entrySavedEdits[item.id] = restored?.edited
        if let index = results.firstIndex(where: { $0.id == item.id }) {
            if let restored { results[index] = restored } else { results.remove(at: index) }
        }
    }
    public func saveAllDrafts() async throws {
        for item in annotations where isChanged(item) { try await saveDraft(item) }
        for (id, _) in entryDrafts { if let item = entrySources[id] { try await saveEntry(item) } }
        if hasDrafts { throw MarginError.invalidInput("Some edits changed while saving. Review them before closing.") }
    }
    public func save(_ item: AnnotationItem, restore: Bool = false, hide: Bool? = nil) {
        run {
            if restore { try await self.service.update(id: item.id, value: ClippingOverride()); self.drafts[item.id] = nil; self.tagDrafts[item.id] = nil }
            else if let hide { var value = item.override; value.hidden = hide; try await self.service.update(id: item.id, value: value) }
            else { try await self.saveDraft(item) }
        }
    }
    public func loadPreferences() async {
        do {
            let values = try await service.preferences()
            collapsed = Set(WorkspacePage.allCases.filter { values["collapsed." + $0.rawValue] == "true" })
            includeTags = values["includeTags"] != "false"; exportHidden = values["includeHidden"] == "true"
        } catch { message = error.localizedDescription }
    }
    public func persistPreferences() {
        run { for page in WorkspacePage.allCases { try await self.service.setPreference("collapsed." + page.rawValue, value: String(self.collapsed.contains(page))) }; try await self.service.setPreference("includeTags", value: String(self.includeTags)); try await self.service.setPreference("includeHidden", value: String(self.exportHidden)) }
    }
    public func lookup() {
        lookupGeneration += 1
        let generation = lookupGeneration; let query = dictionaryQuery; let definitions = searchDefinitions
        results = []; selectedEntry = nil; lookupError = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { lookupState = "idle"; return }
        lookupState = "loading"
        Task {
            do {
                let values = try await definitions ? service.searchEntries(query) : service.lookup(query)
                guard generation == lookupGeneration, query == dictionaryQuery, definitions == searchDefinitions else { return }
                results = values; lookupState = "loaded"
            } catch { guard generation == lookupGeneration else { return }; lookupError = error.localizedDescription; lookupState = "failed" }
        }
    }
}
