import Foundation
import CryptoKit
import KindleDomain

public struct TransferPlan: Sendable, Codable {
    public let id: UUID
    public let source: URL
    public let sourceHash: String
    public let sourceSize: Int64
    public let destination: DeviceFileRef
    public let filename: String
    public let verifiedFormat: String
}
public struct DeletionTarget: Sendable, Codable {
    public let file: DeviceFileRef
    public let parent: DeviceFileRef
    public let name: String
    public let hash: String
}
public struct DeletionPlan: Sendable, Codable {
    public let id: UUID
    public let targets: [DeletionTarget]
    public let backupDirectory: URL?
    public func withoutBackup() -> DeletionPlan { .init(id: UUID(), targets: targets, backupDirectory: nil) }
}
/// One service per device. The explicit lease spans suspension points, unlike actor isolation alone.
public actor DeviceLibraryService {
    private let transport: any DeviceTransport
    private let verifiedFormats: Set<String>
    private let writable: Bool
    private var leased = false
    public init(transport: any DeviceTransport, verifiedFormats: Set<String>, writable: Bool = false) {
        self.transport = transport; self.verifiedFormats = verifiedFormats; self.writable = writable
    }
    private func acquire() throws {
        guard !leased else { throw MarginError.unavailable("Device is busy with another operation. Retry when it finishes.") }
        leased = true
    }
    public func planTransfer(source: URL, detectedFormat: String, destination: DeviceFileRef, filename: String) async throws -> TransferPlan {
        try acquire(); defer { leased = false }
        guard writable, verifiedFormats.contains(detectedFormat) else { throw MarginError.unavailable("The target device and file format are not verified for writing.") }
        guard !filename.isEmpty, !filename.contains("/"), !filename.contains("\\"), filename != ".", filename != ".." else { throw MarginError.invalidInput("Unsafe transfer filename.") }
        let entries = try await transport.list(in: destination)
        guard !entries.contains(where: { $0.name.caseInsensitiveCompare(filename) == .orderedSame }) else { throw MarginError.conflict("Destination name already exists. Choose a new name before confirming.") }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw MarginError.invalidInput("Transfer source must be a regular file.") }
        return .init(id: UUID(), source: source, sourceHash: try hash(source), sourceSize: Int64(values.fileSize ?? 0), destination: destination, filename: filename, verifiedFormat: detectedFormat)
    }
    public func executeTransfer(_ plan: TransferPlan, workDirectory: URL, progress: @escaping @Sendable (String) async throws -> Void = { _ in }) async throws -> DeviceFileRef {
        try acquire(); defer { leased = false }
        try Task.checkCancellation()
        guard writable, verifiedFormats.contains(plan.verifiedFormat), try hash(plan.source) == plan.sourceHash else { throw MarginError.conflict("Transfer plan is stale. Replan and confirm again.") }
        let entries = try await transport.list(in: plan.destination)
        guard !entries.contains(where: { $0.name.caseInsensitiveCompare(plan.filename) == .orderedSame }) else { throw MarginError.conflict("A naming conflict appeared after confirmation. Replan before writing.") }
        let working = workDirectory.appendingPathComponent(plan.id.uuidString)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: working) }
        let staged = working.appendingPathComponent("source")
        try FileManager.default.copyItem(at: plan.source, to: staged)
        guard try hash(staged) == plan.sourceHash else { throw MarginError.conflict("Source changed during staging.") }
        try Task.checkCancellation()
        try await progress("Uploading")
        let created = try await transport.upload(staged, into: plan.destination, name: plan.filename)
        try await progress("Verifying")
        let readback = working.appendingPathComponent("readback")
        try await transport.download(created, to: readback)
        guard try hash(readback) == plan.sourceHash else { throw MarginError.verificationFailed }
        return created
    }
    public func planDeletion(files: [(file: DeviceFileRef, parent: DeviceFileRef, name: String)], backupDirectory: URL?, workDirectory: URL) async throws -> DeletionPlan {
        try acquire(); defer { leased = false }
        guard writable, !files.isEmpty else { throw MarginError.unavailable("Select explicitly confirmed device files on a writable device.") }
        let id = UUID(); let working = workDirectory.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: working) }
        var targets: [DeletionTarget] = []
        for (index, item) in files.enumerated() {
            try Task.checkCancellation()
            let local = working.appendingPathComponent(String(index))
            try await transport.download(item.file, to: local)
            targets.append(.init(file: item.file, parent: item.parent, name: item.name, hash: try hash(local)))
        }
        return .init(id: id, targets: targets, backupDirectory: backupDirectory)
    }
    public func executeDeletion(_ plan: DeletionPlan, workDirectory: URL, progress: @escaping @Sendable (String) async throws -> Void = { _ in }) async throws {
        try acquire(); defer { leased = false }
        guard writable else { throw MarginError.unavailable("Device deletion is unavailable.") }
        let working = workDirectory.appendingPathComponent(plan.id.uuidString)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: working) }
        // Validate every target and finish every requested backup before the first deletion.
        for (index, target) in plan.targets.enumerated() {
            try Task.checkCancellation()
            let local = working.appendingPathComponent(String(index))
            try await transport.download(target.file, to: local)
            guard try hash(local) == target.hash else { throw MarginError.conflict("A selected file changed. Create and confirm a new deletion plan.") }
            if let backup = plan.backupDirectory {
                let folder = backup.appendingPathComponent(plan.id.uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let safeName = target.name.map { "/\\".contains($0) ? "_" : $0 }
                let destination = folder.appendingPathComponent("\(index)-" + String(safeName))
                try FileManager.default.copyItem(at: local, to: destination)
                guard try hash(destination) == target.hash else { throw MarginError.verificationFailed }
            }
        }
        for (index, target) in plan.targets.enumerated() {
            try Task.checkCancellation()
            let current = working.appendingPathComponent("current-" + String(index))
            try await transport.download(target.file, to: current)
            guard try hash(current) == target.hash else { throw MarginError.conflict("A target changed after backup. Reconcile before planning another deletion.") }
            try await progress("Deleting file \(index + 1) of \(plan.targets.count)")
            try await transport.delete(target.file)
            try await progress("Verifying deletion \(index + 1) of \(plan.targets.count)")
            let remaining = try await transport.list(in: target.parent)
            guard !remaining.contains(where: { $0.id == target.file || $0.name == target.name }) else { throw MarginError.verificationFailed }
        }
    }
    private func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }; var result = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); result.update(data: data) }
        return result.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
