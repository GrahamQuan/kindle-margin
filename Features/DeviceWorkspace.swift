import SwiftUI
import KindleDomain
import KindleApplication

@MainActor @Observable public final class DeviceWorkspaceModel {
    public let provider: any DeviceProviding
    public let workflow: DeviceWorkflow
    public var devices: [DeviceInfo] = []
    public var activeID: UUID?
    public var connection: DeviceConnection?
    public var directory: DeviceFileRef?
    public var path: [String] = []
    public var parents: [DeviceFileRef] = []
    public var entries: [DeviceEntry] = []
    public var selection: DeviceFileRef?
    public var error: String?
    public var loading = false
    public var jobs: [JobRecord] = []
    public var blockedWrites: Bool {
        guard let activeID else { return false }
        return jobs.contains { job in
            guard [.queued, .preparing, .running, .verifying, .cancelling, .needsReconciliation].contains(job.state) else { return false }
            if job.deviceID == activeID { return true }
            guard let info = connection?.info, !info.temporaryIdentity, let plan = job.plan,
                  let journal = try? JSONDecoder().decode(DeviceJournal.self, from: plan), !journal.temporaryIdentity else { return false }
            return journal.identity == info.identity
        }
    }

    public var importAction: ((Bool) -> Void)?
    public var droppedFilesAction: (([URL]) -> Void)?
    public var backupAction: (() -> Void)?
    public var deleteAction: (() -> Void)?
    public var importClippingsAction: (() -> Void)?
    public init(provider: any DeviceProviding, workflow: DeviceWorkflow) { self.provider = provider; self.workflow = workflow }
    public var selected: DeviceEntry? { entries.first { $0.id == selection } }
    public var status: String { loading ? "Connecting" : error != nil ? "Connection failed" : connection?.info.status.rawValue ?? devices.first(where: { $0.id == activeID })?.status.rawValue ?? "Disconnected" }
    public var canWrite: Bool { connection?.writable == true && directory != nil && path.first?.lowercased() == "documents" && !loading && !blockedWrites }
    public func refreshDevices() async {
        do {
            devices = try await provider.refresh()
            if let activeID, !devices.contains(where: { $0.id == activeID }) { self.activeID = nil; connection = nil; directory = nil; entries = []; selection = nil; parents = []; path = [] }
            if activeID == nil, let first = devices.first { activeID = first.id }
        } catch { self.error = error.localizedDescription }
    }
    public func connect() async {
        guard let id = activeID else { return }
        error = nil; loading = true; defer { loading = false }
        connection = nil; directory = nil; entries = []; selection = nil; path = []; parents = []
        do {
            let result = try await provider.connect(id)
            guard activeID == id else { return }
            connection = result; entries = result.roots
            if let first = result.roots.first {
                directory = first.id; try await list()
                if let documents = entries.first(where: { $0.isDirectory && $0.name.lowercased() == "documents" }) { await open(documents) }
            }
        } catch { self.error = error.localizedDescription }
    }
    public func selectDevice(_ id: UUID?) { activeID = id; connection = nil; directory = nil; entries = []; selection = nil; path = []; parents = [] }
    public func list() async throws {
        guard let connection, let directory else { return }
        let result = try await connection.transport.list(in: directory)
        guard self.directory == directory else { return }
        entries = result
        if !result.contains(where: { $0.id == selection }) { selection = nil }
    }
    public func open(_ item: DeviceEntry) async {
        guard item.isDirectory, let previous = directory else { return }
        parents.append(previous); path.append(item.name); directory = item.id; selection = nil
        do { try await list() } catch { self.error = error.localizedDescription }
    }
    public func back() async {
        guard let parent = parents.popLast() else { return }; _ = path.popLast(); directory = parent; selection = nil
        do { try await list() } catch { self.error = error.localizedDescription }
    }
}
@MainActor public struct DeviceLibraryView: View {
    @Bindable var model: DeviceWorkspaceModel
    public init(model: DeviceWorkspaceModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Device", selection: Binding(get: { model.activeID }, set: { model.selectDevice($0) })) {
                    Text("Select a device").tag(nil as UUID?)
                    ForEach(model.devices) { Text($0.name + " · " + $0.transport).tag(Optional($0.id)) }
                }
                Button("Redetect") { Task { await model.refreshDevices() } }
                Button("Connect") { Task { await model.connect() } }.disabled(model.activeID == nil || model.loading)
            }
            if let candidate = model.devices.first(where: { $0.id == model.activeID }) {
                Text(candidate.explanation).font(.callout).foregroundStyle(.secondary)
                Text("\(candidate.model) · Firmware \(candidate.firmware) · \(candidate.temporaryIdentity ? "Temporary identity" : "Reliable device identity")").font(.caption)
            }
            if model.connection != nil {
                actions
                if let capacity = model.connection?.roots.first?.size, capacity > 0 { Text("Available at connection: " + ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)).font(.caption) }
                HStack { Button("Back") { Task { await model.back() } }.disabled(model.parents.isEmpty); Text("Storage / " + model.path.joined(separator: " / ")).lineLimit(1) }
                Table(model.entries, selection: $model.selection) {
                    TableColumn("File") { item in HStack { Image(systemName: item.isDirectory ? "folder" : "doc"); Text(item.name); if item.isDirectory { Button("Open") { Task { await model.open(item) } } } } }
                    TableColumn("Filename type") { item in Text(item.isDirectory ? "Folder" : (item.name as NSString).pathExtension.uppercased()) }
                    TableColumn("Size") { item in Text(item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) }
                }
                .dropDestination(for: URL.self) { urls, _ in guard model.canWrite else { return false }; model.droppedFilesAction?(urls); return true }
                if model.blockedWrites { Text("Writes are paused while this device has active tasks or an outcome requiring reconciliation. Review Tasks; browsing and backup remain available.").font(.callout) }
                else if !model.canWrite { Text("Writes require a verified writable device and its documents folder. Open documents to import or delete books.").font(.caption) }
            } else {
                ContentUnavailableView("Connect a standard Kindle", systemImage: "externaldrive", description: Text("Devices are discovered at launch and when USB or mounted volumes change. Unknown models remain read-only; Kindle Scribe and Fire are excluded."))
            }
        }.padding()
        .alert("Device operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var actions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading) {
            Button("Refresh files") { Task { do { try await model.list() } catch { model.error = error.localizedDescription } } }
            Button("Import books…") { model.importAction?(false) }.disabled(!model.canWrite)
            Button("Install dictionary…") { model.importAction?(true) }.disabled(!model.canWrite)
            Button("Import My Clippings") { model.importClippingsAction?() }
            Button("Backup…") { model.backupAction?() }.disabled(model.selected == nil || model.selected?.isDirectory == true)
            Button("Delete…") { model.deleteAction?() }.disabled(!model.canWrite || model.selected == nil)
        }
    }
}
