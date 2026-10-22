import Foundation
import CryptoKit
import Darwin
import KindleDomain

/// Every filesystem operation runs on one dedicated serial queue, including complete copies.
/// Construct only after identity/capability validation; tests use isolated temporary roots.
public final class MountedVolumeTransport: DeviceTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "KindleMargin.device.io", qos: .utility)
    private let root: URL
    private let deviceID: UUID
    private let sessionID = UUID()
    private var references: [UUID: URL] = [:]
    private var connected = true
    private let writable: Bool
    public let rootReference: DeviceFileRef
    public init(root: URL, deviceID: UUID, verifiedWritable: Bool = false) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath(); self.deviceID = deviceID; self.writable = verifiedWritable
        let token = UUID()
        rootReference = .init(deviceID: deviceID, sessionID: sessionID, token: token)
        references[token] = self.root
        guard try self.root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw MarginError.invalidInput("Device root is not a directory.") }
    }
    public func disconnect() async { await withCheckedContinuation { continuation in queue.async { self.connected = false; self.references.removeAll(); continuation.resume() } } }
    private func perform<T: Sendable>(_ body: @escaping @Sendable (CopyCancellation) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let cancellation = CopyCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { do { try cancellation.check(); continuation.resume(returning: try body(cancellation)) } catch { continuation.resume(throwing: error) } }
            }
        } onCancel: { cancellation.cancel() }
    }
    private func copy(_ source: URL, to destination: URL, cancellation: CopyCancellation) throws {
        guard try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true else { throw MarginError.invalidInput("Only regular files can be copied.") }
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let descriptor = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw MarginError.conflict("Cannot create destination exclusively; it may already exist or be inaccessible.") }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var complete = false
        defer { try? output.close(); if !complete { try? FileManager.default.removeItem(at: destination) } }
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try cancellation.check(); try output.write(contentsOf: data) }
        try cancellation.check(); try output.synchronize(); complete = true
    }
    private func resolve(_ reference: DeviceFileRef) throws -> URL {
        guard connected, reference.deviceID == deviceID, reference.sessionID == sessionID, let url = references[reference.token] else { throw MarginError.staleSession }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved == root || resolved.path.hasPrefix(root.path + "/"), resolved == url.standardizedFileURL else { throw MarginError.invalidInput("Unsafe device path or symbolic link.") }
        return resolved
    }
    private func reference(_ url: URL) -> DeviceFileRef {
        if let token = references.first(where: { $0.value.standardizedFileURL.path == url.standardizedFileURL.path })?.key { return .init(deviceID: deviceID, sessionID: sessionID, token: token) }
        let token = UUID(); references[token] = url
        return .init(deviceID: deviceID, sessionID: sessionID, token: token)
    }
    public func list(in directory: DeviceFileRef) async throws -> [DeviceEntry] {
        try await perform { cancellation in
            let url = try self.resolve(directory)
            return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]).compactMap { item in
                let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true else { return nil }
                return .init(id: self.reference(item), name: item.lastPathComponent, size: Int64(values.fileSize ?? 0), isDirectory: values.isDirectory == true)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    public func download(_ file: DeviceFileRef, to destination: URL) async throws {
        try await perform { cancellation in try self.copy(self.resolve(file), to: destination, cancellation: cancellation) }
    }
    public func upload(_ source: URL, into directory: DeviceFileRef, name: String) async throws -> DeviceFileRef {
        try await perform { cancellation in
            guard self.writable else { throw MarginError.unavailable("Device writes are unavailable until identity and compatibility are verified.") }
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw MarginError.invalidInput("Invalid destination name.") }
            let destination = try self.resolve(directory).appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw MarginError.conflict("A file with this name already exists. Choose another name.") }
            let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard sourceValues.isRegularFile == true else { throw MarginError.invalidInput("Only regular files can be transferred.") }
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: self.root.path)
            guard let free = attributes[.systemFreeSize] as? NSNumber, free.int64Value >= Int64(sourceValues.fileSize ?? 0) else { throw MarginError.unavailable("Insufficient available device space.") }
            try self.copy(source, to: destination, cancellation: cancellation)
            let actual = self.reference(destination)
            guard try self.hash(source, cancellation: cancellation) == self.hash(destination, cancellation: cancellation) else { throw MarginError.verificationFailed }
            return actual
        }
    }
    public func delete(_ file: DeviceFileRef) async throws {
        try await perform { cancellation in
            guard self.writable else { throw MarginError.unavailable("Device deletion is unavailable until compatibility is verified.") }
            let url = try self.resolve(file)
            guard url != self.root, try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw MarginError.invalidInput("Only explicitly selected regular files may be deleted.") }
            try FileManager.default.removeItem(at: url); self.references.removeValue(forKey: file.token)
        }
    }
    private func hash(_ url: URL, cancellation: CopyCancellation) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }; var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { try cancellation.check(); hash.update(data: chunk) }
        return hash.finalize()
    }
}

private final class CopyCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func check() throws { lock.lock(); let cancelled = value; lock.unlock(); if cancelled { throw CancellationError() } }
}
