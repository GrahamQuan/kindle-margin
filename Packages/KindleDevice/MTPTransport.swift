import Foundation
import CryptoKit
import KindleDomain
#if canImport(CLibMTP)
import CLibMTP

public struct MTPCandidate: Sendable, Identifiable {
    public var id: String { "\(bus):\(number)" }
    public let bus: UInt32
    public let number: UInt8
    public let productID: UInt16
    public let label: String
}
/// libmtp calls, handle lifecycle, and complete operations share a dedicated queue.
public final class MTPDiscovery: @unchecked Sendable {
    fileprivate static let queue = DispatchQueue(label: "KindleMargin.libmtp", qos: .utility)
    private static var initialized = false
    public init() {}
    public func candidates() async throws -> [MTPCandidate] {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                if !Self.initialized { LIBMTP_Init(); Self.initialized = true }
                var devices: UnsafeMutablePointer<LIBMTP_raw_device_t>?
                var count: Int32 = 0
                let result = LIBMTP_Detect_Raw_Devices(&devices, &count)
                defer { free(devices) }
                if result == LIBMTP_ERROR_NO_DEVICE_ATTACHED { continuation.resume(returning: []); return }
                guard result == LIBMTP_ERROR_NONE else { continuation.resume(throwing: MarginError.unavailable("USB discovery failed. Check device access and retry.")); return }
                var candidates: [MTPCandidate] = []
                if let devices {
                    for index in 0..<Int(count) {
                        let device = devices[index]
                        guard device.device_entry.vendor_id == 0x1949 else { continue }
                        candidates.append(.init(bus: device.bus_location, number: device.devnum, productID: device.device_entry.product_id, label: device.device_entry.product.map { String(cString: $0) } ?? "Unidentified Amazon USB device"))
                    }
                }
                continuation.resume(returning: candidates)
            }
        }
    }
}

/// A transport that defaults to read-only until a model/firmware capability record is verified.
/// Writes intentionally fail closed; callers cannot infer Kindle support from a USB vendor ID.
public final class MTPTransport: DeviceTransport, @unchecked Sendable {
    private var handle: UnsafeMutablePointer<LIBMTP_mtpdevice_t>?
    private let deviceID: UUID
    private let sessionID = UUID()
    private var objects: [UUID: (UInt32, UInt32)] = [:]
    private var writable = false
    public private(set) var model = "Unknown"
    public private(set) var firmware = "Unknown"
    public private(set) var identityHash: String?
    public private(set) var roots: [DeviceEntry] = []
    private init(deviceID: UUID) { self.deviceID = deviceID }
    public static func open(_ candidate: MTPCandidate, verifiedWritable: Bool = false, deviceID: UUID = UUID()) async throws -> MTPTransport {
        try await withCheckedThrowingContinuation { continuation in
            MTPDiscovery.queue.async {
                var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
                var count: Int32 = 0
                let status = LIBMTP_Detect_Raw_Devices(&raw, &count)
                defer { free(raw) }
                guard status == LIBMTP_ERROR_NONE, let raw else { continuation.resume(throwing: MarginError.staleSession); return }
                for index in 0..<Int(count) where raw[index].bus_location == candidate.bus && raw[index].devnum == candidate.number && raw[index].device_entry.product_id == candidate.productID {
                    guard raw[index].device_entry.vendor_id == 0x1949, let handle = LIBMTP_Open_Raw_Device_Uncached(raw.advanced(by: index)) else {
                        continuation.resume(throwing: MarginError.unavailable("Device is busy or unavailable. Close other transfer applications and retry.")); return
                    }
                    let transport = MTPTransport(deviceID: deviceID); transport.handle = handle; transport.writable = verifiedWritable
                    if let model = LIBMTP_Get_Modelname(handle) {
                        let name = String(cString: model); free(model); transport.model = name
                        if name.localizedCaseInsensitiveContains("scribe") || name.localizedCaseInsensitiveContains("fire") {
                            LIBMTP_Release_Device(handle); transport.handle = nil
                            continuation.resume(throwing: MarginError.unavailable("This device is not supported in V1.")); return
                        }
                    }
                    if let firmware = LIBMTP_Get_Deviceversion(handle) { transport.firmware = String(cString: firmware); free(firmware) }
                    if let serial = LIBMTP_Get_Serialnumber(handle) { transport.identityHash = SHA256.hash(data: Data(String(cString: serial).utf8)).map { String(format: "%02x", $0) }.joined(); free(serial) }
                    guard LIBMTP_Get_Storage(handle, 0) == 0 else { LIBMTP_Release_Device(handle); transport.handle = nil; continuation.resume(throwing: MarginError.unavailable("Cannot read device storage.")); return }
                    var storage = handle.pointee.storage
                    while let current = storage {
                        let entry = current.pointee
                        let reference = transport.reference(storage: entry.id, object: UInt32.max)
                        transport.roots.append(.init(id: reference, name: entry.StorageDescription.map { String(cString: $0) } ?? "Storage", size: Int64(clamping: entry.FreeSpaceInBytes), isDirectory: true))
                        storage = entry.next
                    }
                    continuation.resume(returning: transport); return
                }
                continuation.resume(throwing: MarginError.staleSession)
            }
        }
    }
    private func reference(storage: UInt32, object: UInt32) -> DeviceFileRef {
        if let token = objects.first(where: { $0.value.0 == storage && $0.value.1 == object })?.key { return .init(deviceID: deviceID, sessionID: sessionID, token: token) }
        let token = UUID(); objects[token] = (storage, object)
        return .init(deviceID: deviceID, sessionID: sessionID, token: token)
    }
    private func resolve(_ ref: DeviceFileRef) throws -> (UnsafeMutablePointer<LIBMTP_mtpdevice_t>, UInt32, UInt32) {
        guard let handle, ref.sessionID == sessionID, ref.deviceID == deviceID, let ids = objects[ref.token] else { throw MarginError.staleSession }
        return (handle, ids.0, ids.1)
    }
    public func list(in directory: DeviceFileRef) async throws -> [DeviceEntry] {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            MTPDiscovery.queue.async {
                do {
                    let (handle, storage, parent) = try self.resolve(directory)
                    LIBMTP_Clear_Errorstack(handle)
                    var file = LIBMTP_Get_Files_And_Folders(handle, storage, parent)
                    var entries: [DeviceEntry] = []
                    while let current = file {
                        let value = current.pointee; file = value.next
                        entries.append(.init(id: self.reference(storage: value.storage_id, object: value.item_id), name: value.filename.map { String(cString: $0) } ?? "Unnamed object", size: Int64(clamping: value.filesize), isDirectory: value.filetype == LIBMTP_FILETYPE_FOLDER))
                        current.pointee.next = nil; LIBMTP_destroy_file_t(current)
                    }
                    guard LIBMTP_Get_Errorstack(handle) == nil else { throw MarginError.unavailable("Device listing failed. Reconnect and retry.") }
                    continuation.resume(returning: entries)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    public func download(_ file: DeviceFileRef, to destination: URL) async throws {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw MarginError.conflict("Download destination already exists.") }
        let cancellation = MTPCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                MTPDiscovery.queue.async {
                    do {
                        let (handle, _, object) = try self.resolve(file)
                        let context = Unmanaged.passUnretained(cancellation).toOpaque()
                        let status = LIBMTP_Get_File_To_File(handle, object, destination.path, { _, _, context in
                            guard let context else { return 0 }
                            return Unmanaged<MTPCancellation>.fromOpaque(context).takeUnretainedValue().cancelled ? 1 : 0
                        }, context)
                        if cancellation.cancelled { throw CancellationError() }
                        guard status == 0 else { throw MarginError.unavailable("MTP download failed; the connection may be busy or disconnected.") }
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
    public func upload(_ source: URL, into directory: DeviceFileRef, name: String) async throws -> DeviceFileRef {
        try Task.checkCancellation()
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains("\0"), name != ".", name != ".." else { throw MarginError.invalidInput("Unsafe MTP filename.") }
        let cancellation = MTPCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                MTPDiscovery.queue.async {
                    do {
                        guard self.writable else { throw MarginError.unavailable("MTP writes require a verified model and firmware capability record.") }
                        let (handle, storageID, parent) = try self.resolve(directory)
                        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                        guard values.isRegularFile == true, let size = values.fileSize else { throw MarginError.invalidInput("Transfer source is not a readable regular file.") }
                        guard LIBMTP_Get_Storage(handle, 0) == 0 else { throw MarginError.unavailable("Cannot verify available MTP storage.") }
                        var storage = handle.pointee.storage; var freeBytes: UInt64?
                        while let current = storage { if current.pointee.id == storageID { freeBytes = current.pointee.FreeSpaceInBytes }; storage = current.pointee.next }
                        guard let freeBytes, freeBytes >= size else { throw MarginError.unavailable("Insufficient available MTP storage.") }
                        LIBMTP_Clear_Errorstack(handle)
                        var existing = LIBMTP_Get_Files_And_Folders(handle, storageID, parent)
                        var conflict = false
                        while let item = existing {
                            existing = item.pointee.next
                            if let filename = item.pointee.filename, String(cString: filename).caseInsensitiveCompare(name) == .orderedSame { conflict = true }
                            item.pointee.next = nil; LIBMTP_destroy_file_t(item)
                        }
                        guard LIBMTP_Get_Errorstack(handle) == nil else { throw MarginError.unavailable("Cannot check MTP naming conflicts.") }
                        guard !conflict else { throw MarginError.conflict("Destination already exists. Replan using a new filename.") }
                        guard let file = LIBMTP_new_file_t() else { throw MarginError.unavailable("Cannot allocate MTP metadata.") }
                        defer { LIBMTP_destroy_file_t(file) }
                        file.pointee.filename = strdup(name); file.pointee.filesize = UInt64(size)
                        file.pointee.storage_id = storageID; file.pointee.parent_id = parent == UInt32.max ? 0 : parent
                        file.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
                        let context = Unmanaged.passUnretained(cancellation).toOpaque()
                        let status = LIBMTP_Send_File_From_File(handle, source.path, file, { _, _, context in
                            guard let context else { return 0 }
                            return Unmanaged<MTPCancellation>.fromOpaque(context).takeUnretainedValue().cancelled ? 1 : 0
                        }, context)
                        // A failed/cancelled upload may have created an object. Do not delete or retry blindly.
                        guard status == 0, !cancellation.cancelled else { throw MarginError.unavailable("MTP upload outcome needs reconciliation before retrying.") }
                        guard let actual = LIBMTP_Get_Filemetadata(handle, file.pointee.item_id) else { throw MarginError.verificationFailed }
                        defer { LIBMTP_destroy_file_t(actual) }
                        guard actual.pointee.filesize == UInt64(size) else { throw MarginError.verificationFailed }
                        continuation.resume(returning: self.reference(storage: actual.pointee.storage_id, object: actual.pointee.item_id))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
    public func delete(_ file: DeviceFileRef) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            MTPDiscovery.queue.async {
                do {
                    guard self.writable else { throw MarginError.unavailable("MTP deletion requires verified compatibility and a confirmed deletion plan.") }
                    let (handle, _, object) = try self.resolve(file)
                    guard object != UInt32.max, let metadata = LIBMTP_Get_Filemetadata(handle, object) else { throw MarginError.staleSession }
                    defer { LIBMTP_destroy_file_t(metadata) }
                    guard metadata.pointee.filetype != LIBMTP_FILETYPE_FOLDER else { throw MarginError.invalidInput("Recursive MTP directory deletion is disabled.") }
                    guard LIBMTP_Delete_Object(handle, object) == 0 else { throw MarginError.unavailable("MTP deletion outcome needs reconciliation before retrying.") }
                    self.objects.removeValue(forKey: file.token)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    public func setVerifiedWritable(_ value: Bool) async {
        await withCheckedContinuation { continuation in MTPDiscovery.queue.async { self.writable = value; continuation.resume() } }
    }
    public func disconnect() async {
        await withCheckedContinuation { continuation in
            MTPDiscovery.queue.async { if let handle = self.handle { LIBMTP_Release_Device(handle) }; self.handle = nil; self.objects.removeAll(); continuation.resume() }
        }
    }
    deinit {
        if let handle { MTPDiscovery.queue.async { LIBMTP_Release_Device(handle) } }
    }
}
private final class MTPCancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}
#endif
