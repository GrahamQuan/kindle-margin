import Foundation

public enum ConnectionStatus: String, Codable, Sendable { case disconnected = "Disconnected", connecting = "Connecting", available = "Available", readOnly = "Read-only", busy = "Busy", failed = "Connection failed", unsupported = "Unsupported" }
public struct DeviceInfo: Identifiable, Codable, Sendable {
    public let id: UUID
    public let identity: String
    public let temporaryIdentity: Bool
    public let name: String
    public let model: String
    public let firmware: String
    public let transport: String
    public var status: ConnectionStatus
    public var explanation: String
    public init(id: UUID, identity: String, temporaryIdentity: Bool, name: String, model: String, firmware: String, transport: String, status: ConnectionStatus, explanation: String) {
        self.id = id; self.identity = identity; self.temporaryIdentity = temporaryIdentity; self.name = name; self.model = model; self.firmware = firmware; self.transport = transport; self.status = status; self.explanation = explanation
    }
}
public struct DeviceProfile: Codable, Sendable {
    public let model: String
    public let firmware: String
    public let transport: String
    public let verifiedFormats: Set<String>
    public init(model: String, firmware: String, transport: String, verifiedFormats: Set<String>) { self.model = model; self.firmware = firmware; self.transport = transport; self.verifiedFormats = verifiedFormats }
}
public struct DeviceConnection: Sendable {
    public let info: DeviceInfo
    public let roots: [DeviceEntry]
    public let transport: any DeviceTransport
    public let verifiedFormats: Set<String>
    public var writable: Bool { info.status == .available }
    public init(info: DeviceInfo, roots: [DeviceEntry], transport: any DeviceTransport, verifiedFormats: Set<String>) { self.info = info; self.roots = roots; self.transport = transport; self.verifiedFormats = verifiedFormats }
}
public protocol DeviceProviding: Sendable {
    func refresh() async throws -> [DeviceInfo]
    func connect(_ id: UUID) async throws -> DeviceConnection
    func disconnect(_ id: UUID) async
}
