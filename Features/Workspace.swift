import SwiftUI
import KindleDomain

@MainActor @Observable public final class WorkspacePresentation {
    public var page: WorkspacePage = .annotations
    public var selection: UUID?
    public var opened: UUID?
    public var editing = false
    public var search = ""
    public var kind: ClippingKind?
    public var book: UUID?
    public var showHidden = false
    public var scroll: UUID?
    public let annotationScroll = ScrollMemory()
    public let dictionaryScroll = ScrollMemory()
    public var query = ""
    public var entrySelection: String?
    public var selectedAnnotationText = ""
    public var entry: LookupResult?
    public var entryEditing = false
    public var definitions = false
    public var results: [LookupResult] = []
    public var submittedQuery: String?
    public var lookupState = "idle"
    public var lookupError: String?
    public var collapsed: Set<WorkspacePage> = []
    public var findRequest = UUID()
    public var saveRequest = UUID()
    public var job: UUID?
    public init() {}
    public func openEntry(_ result: LookupResult, editing: Bool) {
        entrySelection = result.id; entry = result; entryEditing = editing
    }
    public func applySavedDefinitions(_ values: [String: String], edited: [String: Bool] = [:]) {
        for index in results.indices {
            if let text = values[results[index].id] { results[index].entry.definition = text; results[index].edited = edited[results[index].id] ?? results[index].edited }
        }
        if let id = entry?.id, let text = values[id] { entry?.entry.definition = text; entry?.edited = edited[id] ?? entry?.edited ?? false }
    }
}

@MainActor public struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State var state: WorkspacePresentation
    @State var navigationVisibility: NavigationSplitViewVisibility = .all
    @State var sheet: WorkspaceSheet?
    @State var confirmation: WorkspaceConfirmation?
    @State var notice: String?
    @State private var sheetReturnFocus: WorkspaceFocus?
    @State private var sheetPage: WorkspacePage?
    @State var lookupTask: Task<Void, Never>?
    @FocusState var focus: WorkspaceFocus?
    @Environment(\.colorScheme) var appearance
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorSchemeContrast) var contrast
    public init(model: WorkspaceModel, presentation: WorkspacePresentation? = nil) {
        self.model = model
        _state = State(initialValue: presentation ?? WorkspacePresentation())
    }
    var selected: AnnotationItem? { model.annotations.first { $0.id == (state.opened ?? state.selection) } }
    var hasTools: Bool {
        switch state.page {
        case .annotations: return selected != nil && (state.opened != nil || filtered.contains { $0.id == state.selection })
        case .dictionaries: return state.entry != nil
        case .library: return model.device?.selected != nil
        case .tasks: return model.jobs.contains { $0.id == state.job }
        case .settings: return false
        }
    }
    var filtered: [AnnotationItem] {
        model.annotations.filter { (state.book == nil || $0.bookID == state.book) && (state.showHidden || !$0.override.hidden) && (state.kind == nil || $0.original.kind == state.kind) && (state.search.isEmpty || $0.body.localizedCaseInsensitiveContains(state.search) || $0.original.description.localizedCaseInsensitiveContains(state.search)) }
    }
    var surface: Color { Color(nsColor: .textBackgroundColor) }
    public var body: some View {
        NavigationSplitView(columnVisibility: $navigationVisibility) {
            VStack(alignment: .leading, spacing: 20) {
                Label("Kindle Margin", systemImage: "book.closed.fill").font(.headline).padding(.horizontal, 16).padding(.top, 18)
                List(selection: $state.page) {
                    ForEach(WorkspacePage.allCases.filter { $0 != .settings }) { page in
                        HStack(spacing: 10) { Image(systemName: page.icon).frame(width: 20); Text(page.rawValue).fixedSize(horizontal: true, vertical: false); Spacer(minLength: 0) }.padding(.vertical, 7).tag(page)
                    }
                }.scrollContentBackground(.hidden).listStyle(.sidebar)
                Button { state.page = .settings } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                    .buttonStyle(.plain).background(state.page == .settings ? surface.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 8)).padding(12)
            }.background(shellBackground).navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let message = notice ?? model.message {
                            HStack(alignment: .top) {
                                Text(message).font(.callout).textSelection(.enabled)
                                Spacer()
                                if !model.diagnostics.isEmpty { Button("Review skipped records") { presentSheet(.diagnostics, returningTo: .reviewDiagnostics) }.focused($focus, equals: .reviewDiagnostics) }
                                Button("Dismiss", systemImage: "xmark") { notice = nil; model.message = nil }.labelStyle(.iconOnly)
                            }.padding(12).background(surface, in: RoundedRectangle(cornerRadius: 10))
                        }
                        pageContent(state.page).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(surface, in: RoundedRectangle(cornerRadius: 16))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(contrast == .increased ? Color.primary : Color.primary.opacity(0.07), lineWidth: 1) }
                    }
                    if hasTools && !state.collapsed.contains(state.page) && geometry.size.width >= 1000 {
                        toolsPanel.frame(width: 280).background(surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(geometry.size.width < 700 ? 16 : 24)
                    .onChange(of: geometry.size.width) { _, width in
                        if width >= 1000 && sheet == .tools { sheet = nil }
                    }
            }.background(shellBackground)
        }
        .background(StatusAnnouncement(message: notice ?? model.message))
        .frame(minWidth: 660, minHeight: 480)
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.size.width, initial: true) { oldWidth, width in
                    if width < 800 { navigationVisibility = .detailOnly }
                    else if oldWidth < 800 { navigationVisibility = .all }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Text(model.device?.status ?? "Disconnected")
                    if let device = model.device {
                        ForEach(device.devices) { candidate in
                            Button(candidate.name) { device.selectDevice(candidate.id) }
                        }
                        Button("Device Library") { state.page = .library }
                    }
                } label: { Text(model.device?.status ?? "Disconnected").font(.callout) }
                .help("Active Kindle and connection status")
            }
            ToolbarItem {
                if hasTools {
                    Button("Contextual tools", systemImage: "sidebar.right") {
                        // The sheet is also available on large windows; the panel preference remains independent.
                        presentSheet(.tools, returningTo: .tools)
                    }.focused($focus, equals: .tools).help("Show contextual tools")
                }
            }
        }
        .sheet(item: $sheet, onDismiss: {
            focus = sheetPage == state.page ? (defaultFocus == .editor ? .editor : sheetReturnFocus ?? defaultFocus) : defaultFocus
            sheetReturnFocus = nil; sheetPage = nil
        }) { value in sheetContent(value) }
        .confirmationDialog(confirmation?.title ?? "Confirm", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if let value = confirmation { Button(value.actionTitle, role: .destructive) { perform(value); confirmation = nil } }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: { Text(confirmation?.message ?? "") }
        .onChange(of: state.page) { _, _ in sheet = nil; focus = defaultFocus }
        .onChange(of: state.selection) { _, _ in if sheet == .tools || sheet == .export { sheet = nil } }
        .onChange(of: hasTools) { _, available in if !available && sheet == .tools { sheet = nil } }
        .task {
            await model.loadPreferences(); state.collapsed = model.collapsed; await model.refresh()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { model.jobs = (try? await model.coordinator.jobs()) ?? model.jobs } }
        }
        .onChange(of: state.findRequest) { _, _ in if state.page == .annotations { state.opened = nil }; focus = .search }
        .onChange(of: state.saveRequest) { _, _ in saveActive() }
        .focusedSceneValue(\.workspaceCommands, WorkspaceCommandsContext(find: Binding(get: { state.findRequest }, set: { state.findRequest = $0 }), save: Binding(get: { state.saveRequest }, set: { state.saveRequest = $0 }), page: Binding(get: { state.page }, set: { state.page = $0 }), canSave: canSave, canFind: state.page == .annotations || state.page == .dictionaries))
    }
    func presentSheet(_ value: WorkspaceSheet, returningTo target: WorkspaceFocus? = nil) {
        if sheet == nil { sheetReturnFocus = target ?? focus ?? defaultFocus; sheetPage = state.page }
        sheet = value
    }
    var defaultFocus: WorkspaceFocus {
        switch state.page {
        case .annotations: return state.opened == nil ? .search : state.editing ? .editor : .back
        case .dictionaries: return state.entry == nil ? .search : state.entryEditing ? .editor : .back
        case .library: return .importLocal
        case .tasks: return .refreshTasks
        case .settings: return .settingsControl
        }
    }
    var shellBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency {
                LinearGradient(colors: appearance == .dark ? [Color.blue.opacity(0.12), Color.purple.opacity(0.08), Color.orange.opacity(0.07)] : [Color(red: 0.85, green: 0.89, blue: 0.97), Color(red: 0.91, green: 0.89, blue: 0.95), Color(red: 0.97, green: 0.88, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
    var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { heading; Spacer(minLength: 12); headerActions }
            VStack(alignment: .leading, spacing: 12) { heading; headerActions }
        }
    }
    var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(state.page.rawValue).font(.largeTitle.bold())
            if state.page == .annotations { Text("\(filtered.count) entries").foregroundStyle(.secondary) }
        }.fixedSize(horizontal: true, vertical: false)
    }
    @ViewBuilder var headerActions: some View {
        switch state.page {
        case .annotations:
            HStack {
                TextField("Search annotations or books", text: $state.search).textFieldStyle(.roundedBorder).frame(minWidth: 160, idealWidth: 240, maxWidth: 320).focused($focus, equals: .search)
                if state.opened == nil {
                    Button("Import My Clippings…", systemImage: "plus") { model.importClippingsAction?() }.buttonStyle(PrimaryActionStyle())
                } else { Button("Import…") { model.importClippingsAction?() } }
            }
        case .dictionaries:
            HStack {
                TextField("Look up a word", text: $state.query).textFieldStyle(.roundedBorder).frame(minWidth: 120, idealWidth: 200, maxWidth: 300).focused($focus, equals: .search).onSubmit(lookup)
                Button("Look up", action: lookup).buttonStyle(PrimaryActionStyle())
                Button("Import dictionary…") { presentSheet(.dictionaryImport, returningTo: .dictionaryImport) }.focused($focus, equals: .dictionaryImport)
            }
        case .tasks: Button("Refresh tasks") { Task { await model.refresh() } }.focused($focus, equals: .refreshTasks)
        case .library: Button("Import local clippings…") { model.importClippingsAction?() }.focused($focus, equals: .importLocal)
        case .settings: EmptyView()
        }
    }
    @ViewBuilder func pageContent(_ page: WorkspacePage) -> some View {
        switch page {
        case .annotations: annotationPage
        case .dictionaries: dictionaryPage
        case .library: if let device = model.device { DeviceLibraryView(model: device) }
        case .tasks: tasksPage
        case .settings: settingsPage
        }
    }
}

enum WorkspaceFocus: Hashable { case search, collection, dictionaryResults, editor, tools, back, previewAction, exportAction, archive, reviewDiagnostics, emptyDictionaryImport, dictionaryImport, dictionaries, importLocal, refreshTasks, settingsControl }
enum WorkspaceSheet: String, Identifiable { case tools, diagnostics, preview, export, dictionaryImport, dictionaries, snapshots; var id: String { rawValue } }
struct WorkspaceConfirmation {
    var title: String
    var message: String
    var actionTitle: String
    var action: () -> Void
}
extension WorkspaceView { func perform(_ value: WorkspaceConfirmation) { value.action() } }
struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) var appearance
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(isEnabled ? (appearance == .dark ? Color.black : Color.white) : Color.secondary)
            .background((isEnabled ? (appearance == .dark ? Color.white : Color(white: 0.12)) : Color.primary.opacity(0.08)).opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 9))
    }
}
public struct WorkspaceCommandsContext {
    public var find: Binding<UUID>
    public var save: Binding<UUID>
    public var page: Binding<WorkspacePage>
    public var canSave: Bool
    public var canFind: Bool
}
struct WorkspaceCommandsKey: FocusedValueKey { typealias Value = WorkspaceCommandsContext }
public extension FocusedValues {
    var workspaceCommands: WorkspaceCommandsContext? {
        get { self[WorkspaceCommandsKey.self] }
        set { self[WorkspaceCommandsKey.self] = newValue }
    }
}
