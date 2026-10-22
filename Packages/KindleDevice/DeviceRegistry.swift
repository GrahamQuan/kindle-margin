import Foundation
import CryptoKit
import DiskArbitration
import IOKit
import KindleDomain

public actor DeviceRegistry: DeviceProviding {
    private enum Source {
        case volume(URL)
        #if canImport(CLibMTP)
        case mtp(MTPCandidate)
        #endif
    }
    private let profiles: [DeviceProfile]
    private var information: [UUID: DeviceInfo] = [:]
    private var sources: [UUID: Source] = [:]
    private var connections: [UUID: DeviceConnection] = [:]
    private var stableIDs: [String: UUID] = [:]
    private var generation = 0
    private let enumerationQueue = DispatchQueue(label: "KindleMargin.disk.enumeration", qos: .utility)
    public init(profiles: [DeviceProfile] = []) { self.profiles = profiles }
    public func refresh() async throws -> [DeviceInfo] {
        let volumes = await mountedCandidates()
        var next: [UUID: DeviceInfo] = [:]; var nextSources: [UUID: Source] = [:]
        for (root, model, revision, serial, vendor) in volumes {
            let key = serial.map { "serial:" + Self.digest($0) } ?? "temporary-volume:" + root.path
            let id = stableIDs[key] ?? UUID(); stableIDs[key] = id
            let unsupported = Self.excluded(model)
            let profile = profiles.first { $0.model == model && $0.firmware == revision && $0.transport == "Mounted volume" }
            let writable = profile != nil && vendor == 0x1949 && !unsupported && FileManager.default.isWritableFile(atPath: root.path)
            next[id] = .init(id: id, identity: serial.map(Self.digest) ?? id.uuidString, temporaryIdentity: serial == nil, name: root.lastPathComponent, model: model, firmware: revision, transport: "Mounted volume", status: unsupported ? .unsupported : writable ? .available : .readOnly, explanation: unsupported ? "This device is not supported in V1." : writable ? "Verified model profile; runtime access available." : "Identity or model/firmware compatibility is unverified. Writes are disabled.")
            nextSources[id] = .volume(root)
        }
        #if canImport(CLibMTP)
        for candidate in try await MTPDiscovery().candidates() {
            let key = "temporary-mtp:" + candidate.id
            let id = stableIDs[key] ?? UUID(); stableIDs[key] = id
            next[id] = connections[id]?.info ?? .init(id: id, identity: id.uuidString, temporaryIdentity: true, name: candidate.label, model: candidate.label, firmware: "Unknown", transport: "MTP", status: Self.excluded(candidate.label) ? .unsupported : .readOnly, explanation: "Connect to read device identity. Writes require a verified model/firmware profile.")
            nextSources[id] = .mtp(candidate)
        }
        #endif
        for id in Array(connections.keys) where next[id] == nil { await disconnect(id) }
        information = next; sources = nextSources
        return next.values.sorted { $0.name < $1.name }
    }
    public func connect(_ id: UUID) async throws -> DeviceConnection {
        if let connection = connections[id] { return connection }
        let connectingGeneration = generation
        guard var info = information[id], let source = sources[id] else { throw MarginError.staleSession }
        guard info.status != .unsupported else { throw MarginError.unavailable("This device is not supported in V1.") }
        let result: DeviceConnection
        switch source {
        case .volume(let root):
            let transport = try MountedVolumeTransport(root: root, deviceID: id, verifiedWritable: info.status == .available)
            let available = (try? FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            result = .init(info: info, roots: [.init(id: transport.rootReference, name: "Device storage", size: available, isDirectory: true)], transport: transport, verifiedFormats: profiles.first { $0.model == info.model && $0.firmware == info.firmware && $0.transport == info.transport }?.verifiedFormats ?? [])
        #if canImport(CLibMTP)
        case .mtp(let candidate):
            let transport = try await MTPTransport.open(candidate, deviceID: id)
            let model = transport.model; let firmware = transport.firmware
            let profile = profiles.first { $0.model == model && $0.firmware == firmware && $0.transport == "MTP" }
            await transport.setVerifiedWritable(profile != nil && !Self.excluded(model))
            info = .init(id: id, identity: transport.identityHash ?? info.identity, temporaryIdentity: transport.identityHash == nil, name: model, model: model, firmware: firmware, transport: "MTP", status: profile == nil ? .readOnly : .available, explanation: profile == nil ? "Model/firmware is not in the verified compatibility table. Writes are disabled." : "Verified model profile. Transfers require read-back verification.")
            result = .init(info: info, roots: transport.roots, transport: transport, verifiedFormats: profile?.verifiedFormats ?? [])
        #endif
        }
        guard connectingGeneration == generation, sources[id] != nil else {
            if let disk = result.transport as? MountedVolumeTransport { await disk.disconnect() }
            #if canImport(CLibMTP)
            if let mtp = result.transport as? MTPTransport { await mtp.disconnect() }
            #endif
            throw MarginError.staleSession
        }
        connections[id] = result; information[id] = result.info
        return result
    }
    public func invalidateConnections() async {
        generation += 1
        for id in Array(connections.keys) { await disconnect(id) }
        stableIDs = stableIDs.filter { !$0.key.hasPrefix("temporary-") }
    }
    public func disconnect(_ id: UUID) async {
        if let transport = connections.removeValue(forKey: id)?.transport {
            if let disk = transport as? MountedVolumeTransport { await disk.disconnect() }
            #if canImport(CLibMTP)
            if let mtp = transport as? MTPTransport { await mtp.disconnect() }
            #endif
        }
    }
    private static func excluded(_ model: String) -> Bool { model.localizedCaseInsensitiveContains("scribe") || model.localizedCaseInsensitiveContains("fire") }
    private static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private func mountedCandidates() async -> [(URL,String,String,String?,Int)] {
        await withCheckedContinuation { continuation in
            enumerationQueue.async {
                guard let session = DASessionCreate(kCFAllocatorDefault) else { continuation.resume(returning: []); return }
                var result: [(URL,String,String,String?,Int)] = []
                for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? [] {
                    guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL), let description = DADiskCopyDescription(disk) as? [String: Any] else { continue }
                    let model = description[kDADiskDescriptionDeviceModelKey as String] as? String ?? "Unknown"
                    let revision = description[kDADiskDescriptionDeviceRevisionKey as String] as? String ?? "Unknown"
                    let media = DADiskCopyIOMedia(disk)
                    var vendor = 0; var serial: String?
                    if media != 0 {
                        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
                        vendor = (IORegistryEntrySearchCFProperty(media, kIOServicePlane, "idVendor" as CFString, kCFAllocatorDefault, options) as? NSNumber)?.intValue ?? 0
                        serial = IORegistryEntrySearchCFProperty(media, kIOServicePlane, "USB Serial Number" as CFString, kCFAllocatorDefault, options) as? String
                        IOObjectRelease(media)
                    }
                    // A name is only a discovery hint and never grants write capabilities.
                    if vendor == 0x1949 || model.localizedCaseInsensitiveContains("kindle") || url.lastPathComponent.localizedCaseInsensitiveContains("kindle") { result.append((url, model.trimmingCharacters(in: .whitespaces), revision, serial, vendor)) }
                }
                continuation.resume(returning: result)
            }
        }
    }
}
