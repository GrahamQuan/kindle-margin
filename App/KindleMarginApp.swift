import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Features
import KindleApplication
import KindlePersistence
import KindleClippings
import KindleDictionary
import KindleConversion
import KindleDevice
import KindleDomain

@main struct KindleMarginApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup {
            if let model = delegate.model { WorkspaceView(model: model).background(WorkspaceCloseGuard(model: model)) }
            else if let error = delegate.startupError { ContentUnavailableView("Library could not be opened", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ProgressView("Opening library…").frame(minWidth: 660, minHeight: 480) }
        }.defaultSize(width: 1120, height: 760)
        .commands { WorkspaceCommandMenu() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var model: WorkspaceModel?
    @Published var startupError: String?
    let conversion = CalibreConversionEngine()
    var converter: ConverterIdentity?
    var monitor: DeviceMonitor?
    var cacheRoot = FileManager.default.temporaryDirectory
    var dataRoot = FileManager.default.temporaryDirectory
    var catalog: [CatalogPackage] = []
    var downloads: DictionaryDownloadService?
    override init() {
        super.init()
        Task { await initializeLibrary() }
    }
    func initializeLibrary() async {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Kindle Margin")
            let arguments = CommandLine.arguments
            let temporaryRoot: URL?
            if let index = arguments.firstIndex(of: "--temporary-library"), arguments.indices.contains(index + 1) {
                temporaryRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            } else { temporaryRoot = nil }
            dataRoot = temporaryRoot ?? root
            cacheRoot = try temporaryRoot?.appendingPathComponent("test-cache") ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Kindle Margin")
            let libraryRoot = dataRoot
            let repository = try await Task.detached(priority: .userInitiated) { try SQLiteLibrary(root: libraryRoot) }.value
            let service = LibraryService(repository: repository, parser: SnapshotParser(), renderer: StandardMarkdownRenderer(), dictionaryParser: DictionaryParser(), dictionaries: repository, analyzer: EnglishAnalyzer())
            let coordinator = JobCoordinator(repository: repository)
            try await coordinator.recover()
            let workspace = WorkspaceModel(service: service, coordinator: coordinator)
            let profileURL = Bundle.module.url(forResource: "device-profiles", withExtension: "json")
            let profiles = profileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([DeviceProfile].self, from: $0) } ?? []
            let registry = DeviceRegistry(profiles: profiles)
            workspace.device = DeviceWorkspaceModel(provider: registry, workflow: DeviceWorkflow(coordinator: coordinator, workDirectory: cacheRoot.appendingPathComponent("jobs")))
            if let catalogURL = Bundle.module.url(forResource: "catalog", withExtension: "json"), let entries = try? JSONDecoder().decode([CatalogPackage].self, from: Data(contentsOf: catalogURL)) {
                catalog = entries
                downloads = try DictionaryDownloadService(catalog: entries, transport: HTTPSPackageTransport(allowedHosts: Set(entries.compactMap { $0.url.host })), parser: DictionaryParser(), repository: repository)
            }
            model = workspace; startupError = nil
            workspace.importClippingsAction = { [weak self] in self?.importFile(dictionary: false) }
            workspace.importDictionaryAction = { [weak self] in self?.importFile(dictionary: true) }
            workspace.exportAction = { [weak self] book in self?.export(book) }
            workspace.selectConverterAction = { [weak self] in self?.selectConverter() }
            workspace.convertLocalAction = { [weak self] in self?.convertLocal() }
            workspace.exportDictionaryAction = { [weak self] id in self?.exportDictionary(id) }
            workspace.device?.importAction = { [weak self] dictionary in self?.importDeviceFiles(dictionary: dictionary) }
            workspace.device?.droppedFilesAction = { [weak self] urls in self?.planDeviceFiles(urls, dictionary: false) }
            workspace.device?.backupAction = { [weak self] in self?.backupDeviceFile() }
            workspace.device?.deleteAction = { [weak self] in self?.deleteDeviceFile() }
            workspace.device?.importClippingsAction = { [weak self] in self?.importDeviceClippings() }
            workspace.reconcileAction = { [weak self] job in self?.reconcile(job) }
            workspace.retryAction = { [weak self] job in self?.retry(job) }
            workspace.downloadCatalogAction = { [weak self] in self?.downloadDictionary() }
            workspace.clearCacheAction = { [weak self] in self?.clearCache() }
            workspace.diagnosticsAction = { [weak self] in self?.diagnostics() }
            monitor = DeviceMonitor { invalidate in Task { if invalidate { await registry.invalidateConnections(); await MainActor.run { workspace.device?.selectDevice(nil) } }; await workspace.device?.refreshDevices() } }
            monitor?.start()
            Task {
                do {
                    await workspace.refresh()
                    let preferences = try await service.preferences()
                    if let value = preferences["converter"], let identity = try? JSONDecoder().decode(ConverterIdentity.self, from: Data(value.utf8)) { self.converter = identity; workspace.converterStatus = identity.version }
                    await workspace.device?.refreshDevices()
                } catch { workspace.message = error.localizedDescription }
            }
        } catch { model = nil; startupError = error.localizedDescription }
    }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); monitor?.start() }
    func importFile(dictionary: Bool) {
        guard let model else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = dictionary ? [.json, .commaSeparatedText] : [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let request = UUID(); let name = model.csvName; let source = model.csvSource; let target = model.csvTarget
        model.run {
            if dictionary {
                try await model.coordinator.perform(requestID: request, kind: "Import dictionary") { try await model.service.importDictionary(url: url, csvName: name, source: source, target: target) }
                model.message = "Dictionary imported. Local entries are available offline."
            } else {
                let report = try await model.coordinator.perform(requestID: request, kind: "Import annotations") { try await model.service.importClippings(url: url) }
                model.message = "Added \(report.added), existing \(report.existing), unparsed \(report.unparsed)."
            }
        }
    }
    func export(_ book: UUID) {
        guard let model else { return }
        let includeHidden = model.exportHidden, includeTags = model.includeTags
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        model.run { let url = try await model.service.export(bookID: book, directory: directory, includeHidden: includeHidden, includeTags: includeTags); model.message = "Exported \(url.lastPathComponent)." }
    }
    func selectConverter() {
        guard let model else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.message = "Select your trusted local Calibre ebook-convert executable."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.run {
            let identity = try await self.conversion.validate(executable: url)
            self.converter = identity; model.converterStatus = identity.version
            try await model.service.setPreference("converter", value: String(decoding: JSONEncoder().encode(identity), as: UTF8.self))
        }
    }
    func convertLocal() {
        guard let model else { return }
        guard let converter else { model.message = "Select and validate a local Calibre ebook-convert first."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.message = "Select an unprotected EPUB, TXT, HTML, RTF, or DOCX file."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let destination = NSSavePanel(); destination.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".azw3"
        guard destination.runModal() == .OK, let output = destination.url else { return }
        guard !FileManager.default.fileExists(atPath: output.path) else { model.message = "Choose a new filename. Local conversion does not replace existing files."; return }
        model.run {
            let plan = try await Task.detached { try self.conversion.plan(source: source, converter: converter) }.value
            let alert = NSAlert(); alert.messageText = "Confirm local conversion"; alert.informativeText = "\(source.lastPathComponent) → AZW3\nConverter: \(converter.version)\nNo device transfer will start."
            alert.addButton(withTitle: "Convert"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let cache = self.cacheRoot.appendingPathComponent("conversions")
            try await model.coordinator.submit(requestID: UUID(), kind: "Convert local book") {
                let artifact = try await self.conversion.execute(plan, cacheDirectory: cache)
                try FileManager.default.copyItem(at: artifact.url, to: output)
            }
        }
    }
    func exportDictionary(_ id: String) {
        guard let model else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "dictionary.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.run { let data = try await model.service.mergedDictionary(id: id); try data.write(to: url, options: .atomic) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task {
            guard await resolveWorkspaceDrafts(model) else { sender.reply(toApplicationShouldTerminate: false); return }
            let jobs = (try? await model.coordinator.jobs()) ?? []
            if jobs.contains(where: { [.running, .queued, .preparing, .verifying, .cancelling].contains($0.state) }) {
                let alert = NSAlert(); alert.messageText = "Tasks are still running"; alert.informativeText = "Wait in the app, or cancel tasks and quit after they stop."
                alert.addButton(withTitle: "Wait"); alert.addButton(withTitle: "Cancel tasks and quit")
                if alert.runModal() == .alertFirstButtonReturn { sender.reply(toApplicationShouldTerminate: false); return }
                await model.coordinator.cancelAllAndWait()
            }
            self.monitor?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
