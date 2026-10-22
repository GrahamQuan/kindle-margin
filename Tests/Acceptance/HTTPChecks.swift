import Foundation
import KindleDictionary

private final class HTTPFixtures: @unchecked Sendable {
    let lock = NSLock()
    var redirect: URL?
    var visited: [URL] = []
    func reset(redirect: URL?) { lock.lock(); defer { lock.unlock() }; self.redirect = redirect; visited = [] }
    func request(_ url: URL) -> URL? { lock.lock(); defer { lock.unlock() }; visited.append(url); return url.path == "/start" ? redirect : nil }
    func urls() -> [URL] { lock.lock(); defer { lock.unlock() }; return visited }
}
private final class FixtureHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = HTTPFixtures()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if let destination = Self.fixtures.request(url) {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
        } else {
            let data = Data("Synthetic package".utf8)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(data.count)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
func httpChecks(root: URL) async throws {
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureHTTPProtocol.self]
    let transport = HTTPSPackageTransport(allowedHosts: ["catalog.synthetic.invalid"], configuration: configuration)
    let start = URL(string: "https://catalog.synthetic.invalid/start")!
    FixtureHTTPProtocol.fixtures.reset(redirect: URL(string: "https://catalog.synthetic.invalid/package"))
    let destination = root.appendingPathComponent("http-package")
    try await transport.download(start, expectedSize: 17, to: destination)
    try check(try String(contentsOf: destination) == "Synthetic package" && FixtureHTTPProtocol.fixtures.urls().count == 2, "DICT-03 configured HTTPS redirect follows policy using mock URLSession")
    for redirect in ["https://unconfigured.invalid/package", "http://catalog.synthetic.invalid/package", "https://user:password@catalog.synthetic.invalid/package"] {
        FixtureHTTPProtocol.fixtures.reset(redirect: URL(string: redirect))
        try await rejects("DICT-03 unsafe redirect is not requested") { try await transport.download(start, expectedSize: 17, to: root.appendingPathComponent(UUID().uuidString)) }
        try check(FixtureHTTPProtocol.fixtures.urls().count == 1, "DICT-03 rejected redirect causes no second request")
    }
}
