import Foundation
import CryptoKit
import KindleDomain

public struct DeviceJournal: Codable, Sendable {
    public let identity: String
    public let temporaryIdentity: Bool
    public let operation: String
    public let directory: [String]
    public let names: [String]
    public let hashes: [String]
    public let backupDirectory: URL?
    public init(connection: DeviceConnection, operation: String, directory: [String], names: [String], hashes: [String], backupDirectory: URL?) {
        identity = connection.info.identity; temporaryIdentity = connection.info.temporaryIdentity; self.operation = operation; self.directory = directory; self.names = names; self.hashes = hashes; self.backupDirectory = backupDirectory
    }
}
public struct DeletionSelection: Sendable {
    public let file: DeviceFileRef
    public let parent: DeviceFileRef
    public let name: String
    public let relativeName: String
}
public actor DeviceWorkflow {
    private let coordinator: JobCoordinator
    private let workDirectory: URL
    private var services: [UUID: DeviceLibraryService] = [:]
    public init(coordinator: JobCoordinator, workDirectory: URL) { self.coordinator = coordinator; self.workDirectory = workDirectory }
    private func service(_ connection: DeviceConnection) -> DeviceLibraryService {
        if let service = services[connection.roots.first?.id.sessionID ?? connection.info.id] { return service }
        let service = DeviceLibraryService(transport: connection.transport, verifiedFormats: connection.verifiedFormats, writable: connection.writable)
        services[connection.roots.first?.id.sessionID ?? connection.info.id] = service; return service
    }
    public func planTransfer(connection: DeviceConnection, source: URL, format: String, directory: DeviceFileRef, name: String) async throws -> TransferPlan {
        try await service(connection).planTransfer(source: source, detectedFormat: format, destination: directory, filename: name)
    }
    public func transfer(connection: DeviceConnection, plan: TransferPlan, directoryPath: [String], requestID: UUID) async throws {
        let journal = DeviceJournal(connection: connection, operation: "transfer", directory: directoryPath, names: [plan.filename], hashes: [plan.sourceHash], backupDirectory: nil)
        let service = service(connection); let work = workDirectory; let coordinator = coordinator
        try await coordinator.submit(requestID: requestID, kind: "Transfer book", deviceID: connection.info.id, plan: JSONEncoder().encode(journal)) {
            _ = try await service.executeTransfer(plan, workDirectory: work) { stage in try await coordinator.stage(requestID: requestID, stage: stage) }
        }
    }
    public func deletionScope(connection: DeviceConnection, main: DeviceEntry, parent: DeviceFileRef) async throws -> [DeletionSelection] {
        guard !main.isDirectory else { throw MarginError.invalidInput("Select a main file, not a directory.") }
        var result: [DeletionSelection] = [.init(file: main.id, parent: parent, name: main.name, relativeName: main.name)]
        let name = (main.name as NSString).deletingPathExtension + ".sdr"
        let siblings = try await connection.transport.list(in: parent)
        if let folder = siblings.first(where: { $0.isDirectory && $0.name == name }) {
            var pending: [(DeviceFileRef,String,Int)] = [(folder.id, folder.name, 0)]
            var seen: Set<DeviceFileRef> = []
            while let (directory, prefix, depth) = pending.popLast() {
                guard seen.insert(directory).inserted, depth < 16 else { throw MarginError.invalidInput("Associated scope is too deep or cyclic. Select individual files.") }
                for child in try await connection.transport.list(in: directory) {
                    guard result.count + pending.count < 1000, !child.name.contains("/"), !child.name.contains("\\"), child.name != ".." else { throw MarginError.invalidInput("Associated scope is too large or unsafe. Select individual files.") }
                    if child.isDirectory { pending.append((child.id, prefix + "/" + child.name, depth + 1)) }
                    else { result.append(.init(file: child.id, parent: directory, name: child.name, relativeName: prefix + "/" + child.name)) }
                }
            }
        }
        return result
    }
    public func planDeletion(connection: DeviceConnection, entries: [DeviceEntry], parent: DeviceFileRef, backupDirectory: URL?) async throws -> DeletionPlan {
        try await service(connection).planDeletion(files: entries.map { ($0.id, parent, $0.name) }, backupDirectory: backupDirectory, workDirectory: workDirectory)
    }
    public func planDeletion(connection: DeviceConnection, files: [(file: DeviceFileRef, parent: DeviceFileRef, name: String)], backupDirectory: URL?) async throws -> DeletionPlan {
        try await service(connection).planDeletion(files: files, backupDirectory: backupDirectory, workDirectory: workDirectory)
    }
    public func delete(connection: DeviceConnection, plan: DeletionPlan, directoryPath: [String], requestID: UUID, relativeNames: [String]? = nil) async throws {
        let journal = DeviceJournal(connection: connection, operation: "delete", directory: directoryPath, names: relativeNames ?? plan.targets.map(\.name), hashes: plan.targets.map(\.hash), backupDirectory: plan.backupDirectory)
        let service = service(connection); let work = workDirectory; let coordinator = coordinator
        try await coordinator.submit(requestID: requestID, kind: "Delete device files", deviceID: connection.info.id, plan: JSONEncoder().encode(journal)) {
            try await coordinator.stage(requestID: requestID, stage: "Backing up and verifying deletion targets")
            try await service.executeDeletion(plan, workDirectory: work) { stage in try await coordinator.stage(requestID: requestID, stage: stage) }
        }
    }
    public func backup(connection: DeviceConnection, file: DeviceEntry, destination: URL) async throws {
        guard !file.isDirectory else { throw MarginError.invalidInput("Select an individual file for backup.") }
        let temporary = workDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let local = temporary.appendingPathComponent("backup")
        try await connection.transport.download(file.id, to: local)
        try Task.checkCancellation()
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".kindle-margin-backup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: local, to: staged)
        guard try Self.hash(local) == Self.hash(staged) else { throw MarginError.verificationFailed }
        try Task.checkCancellation()
        // moveItem refuses an existing destination, preserving any independently changed backup.
        try FileManager.default.moveItem(at: staged, to: destination)
    }
    public func reconcile(job: JobRecord, connection: DeviceConnection) async throws -> String {
        guard job.state == .needsReconciliation, let planData = job.plan else { throw MarginError.invalidInput("No persisted device plan is available for reconciliation.") }
        let plan = try JSONDecoder().decode(DeviceJournal.self, from: planData)
        guard !plan.names.isEmpty, plan.names.count == plan.hashes.count, ["transfer", "delete"].contains(plan.operation) else { throw MarginError.invalidInput("Invalid persisted device plan.") }
        guard !plan.temporaryIdentity, plan.identity == connection.info.identity else { throw MarginError.conflict("Reliable device identity is required. This job cannot be automatically matched to this connection.") }
        guard var directory = connection.roots.first?.id else { throw MarginError.staleSession }
        for name in plan.directory {
            let children = try await connection.transport.list(in: directory)
            guard let child = children.first(where: { $0.name == name && $0.isDirectory }) else { throw MarginError.conflict("The planned directory is missing. Inspect the device before taking further action.") }
            directory = child.id
        }
        let temporary = workDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var matching = 0; var absent = 0; var changed = 0
        for (index, name) in plan.names.enumerated() {
            let components = name.split(separator: "/").map(String.init)
            guard !components.isEmpty, !components.contains(".."), !name.hasPrefix("/") else { throw MarginError.invalidInput("Invalid target path in device plan.") }
            var parent = directory; var missingParent = false
            for component in components.dropLast() {
                let children = try await connection.transport.list(in: parent)
                guard let child = children.first(where: { $0.name == component && $0.isDirectory }) else { missingParent = true; break }
                parent = child.id
            }
            if missingParent { absent += 1; continue }
            let files = try await connection.transport.list(in: parent)
            guard let file = files.first(where: { $0.name == components.last && !$0.isDirectory }) else { absent += 1; continue }
            let local = temporary.appendingPathComponent(String(index)); try await connection.transport.download(file.id, to: local)
            if try Self.hash(local) == plan.hashes[index] { matching += 1 } else { changed += 1 }
        }
        guard changed == 0 else { throw MarginError.conflict("A destination has different content. No writes were retried; inspect the device and backup.") }
        let complete = plan.operation == "transfer" ? matching == plan.names.count : absent == plan.names.count
        let untouched = plan.operation == "transfer" ? absent == plan.names.count : matching == plan.names.count
        if !complete && !untouched {
            let evidence = "Rescan confirms a partial outcome: \(matching) original files remain, \(absent) are absent. Backups are retained. Review the remaining files and confirm a new plan; this job will not replay."
            try await coordinator.reconcile(id: job.id, state: .failed, evidence: evidence)
            return evidence
        }
        let evidence = complete ? "Rescan and content verification confirm the requested outcome." : "Rescan confirms the requested write did not complete. A new plan and confirmation are required."
        try await coordinator.reconcile(id: job.id, state: complete ? .completed : .failed, evidence: evidence)
        return evidence
    }
    private static func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }; var value = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); value.update(data: data) }
        return value.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
