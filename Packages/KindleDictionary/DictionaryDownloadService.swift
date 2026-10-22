import Foundation
import CryptoKit
import KindleDomain

public struct CatalogPackage: Codable, Sendable {
    public let id: String
    public let version: String
    public let type: String
    public let sourceLanguage: String
    public let targetLanguage: String
    public let size: Int64
    public let sha256: String
    public let url: URL
    public let source: String
    public let license: String
    public init(id: String, version: String, type: String = "appDictionary", sourceLanguage: String, targetLanguage: String, size: Int64, sha256: String, url: URL, source: String, license: String) {
        self.id = id; self.version = version; self.type = type; self.sourceLanguage = sourceLanguage; self.targetLanguage = targetLanguage
        self.size = size; self.sha256 = sha256; self.url = url; self.source = source; self.license = license
    }
}
public protocol PackageDownloadTransport: Sendable {
    func download(_ url: URL, expectedSize: Int64, to destination: URL) async throws
}
public final class HTTPSPackageTransport: PackageDownloadTransport, @unchecked Sendable {
    private let allowedHosts: Set<String>
    private let configuration: URLSessionConfiguration
    public init(allowedHosts: Set<String>, configuration: URLSessionConfiguration = .ephemeral) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        self.configuration = configuration.copy() as! URLSessionConfiguration
    }
    public func download(_ url: URL, expectedSize: Int64, to destination: URL) async throws {
        guard url.scheme == "https", let host = url.host?.lowercased(), allowedHosts.contains(host), url.user == nil, url.password == nil else { throw MarginError.invalidInput("Download URL is outside the configured HTTPS catalog hosts.") }
        let policy = DownloadPolicy(hosts: allowedHosts, limit: expectedSize)
        let configuration = self.configuration.copy() as! URLSessionConfiguration
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw MarginError.unavailable("Dictionary server did not return a successful package response.") }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
private final class DownloadPolicy: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let hosts: Set<String>; let limit: Int64
    init(hosts: Set<String>, limit: Int64) { self.hosts = hosts; self.limit = limit }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", let host = url.host?.lowercased(), hosts.contains(host), url.user == nil, url.password == nil else { completionHandler(nil); task.cancel(); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
public actor DictionaryDownloadService {
    private let transport: any PackageDownloadTransport
    private let parser: any DictionaryParsing
    private let repository: any DictionaryRepository
    private let configuredPackages: [String: CatalogPackage]
    private var activeDownloads = 0
    public init(catalog: [CatalogPackage], transport: any PackageDownloadTransport, parser: any DictionaryParsing, repository: any DictionaryRepository) throws {
        guard Set(catalog.map(\.id)).count == catalog.count else { throw MarginError.invalidInput("Catalog package IDs must be unique.") }
        self.configuredPackages = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) }); self.transport = transport; self.parser = parser; self.repository = repository
    }
    public func download(id: String, workDirectory: URL) async throws {
        guard activeDownloads < 2 else { throw MarginError.unavailable("Two dictionary downloads are already active. Retry when one finishes.") }
        activeDownloads += 1
        defer { activeDownloads -= 1 }
        guard let item = configuredPackages[id], item.type == "appDictionary", item.url.scheme == "https", item.size > 0, item.size <= Limits.importBytes,
              item.sha256.count == 64, item.sha256.allSatisfy(\.isHexDigit), !item.license.isEmpty, !item.source.isEmpty else { throw MarginError.invalidInput("Catalog entry is missing required identity, size, integrity, source, or license fields.") }
        let directory = workDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let free = attributes[.systemFreeSize] as? NSNumber, free.int64Value >= item.size * 2 else { throw MarginError.unavailable("Insufficient space to download and install dictionary.") }
        let local = directory.appendingPathComponent("package.json")
        try await transport.download(item.url, expectedSize: item.size, to: local)
        try Task.checkCancellation()
        let values = try local.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, values.fileSize == Int(item.size) else { throw MarginError.verificationFailed }
        let data = try Data(contentsOf: local)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == item.sha256.lowercased() else { throw MarginError.verificationFailed }
        let package = try parser.parseJSON(data)
        guard package.id == item.id, package.version == item.version, package.sourceLanguage == item.sourceLanguage, package.targetLanguage == item.targetLanguage else { throw MarginError.verificationFailed }
        try Task.checkCancellation()
        try await repository.install(package)
    }
}
