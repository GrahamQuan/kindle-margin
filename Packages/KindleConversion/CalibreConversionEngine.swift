import Foundation
import CryptoKit
import Darwin
import KindleDomain

public struct ConverterIdentity: Codable, Sendable, Equatable {
    public let executable: URL
    public let version: String
    public let executableHash: String
    public let architecture: String?
    public let inputFormats: Set<String>?
}
public struct ConversionPlan: Sendable {
    public let source: URL
    public let inputHash: String
    public let inputFormat: String
    public let converter: ConverterIdentity
    public let outputFormat: String
    public let parameters: [String]
}
public struct BookArtifact: Sendable {
    public let url: URL
    public let contentHash: String
    public let cacheKey: String
}
/// Process execution is serialized on a dedicated queue. No shell or PATH executable discovery.
public final class CalibreConversionEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "KindleMargin.conversion", qos: .utility)
    public init() {}
    public func validate(executable: URL) async throws -> ConverterIdentity {
        guard executable.isFileURL, executable.path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable.path) else { throw MarginError.unavailable("Select an executable local Calibre ebook-convert.") }
        let output = try await process(executable, arguments: ["--version"], directory: executable.deletingLastPathComponent(), timeout: 10)
        guard output.lowercased().contains("calibre"), output.count < 4096 else { throw MarginError.unavailable("The selected executable did not identify itself as Calibre.") }
        var capabilities: Set<String> = []
        for format in ["epub", "txt", "html", "rtf", "docx"] {
            let help = try await process(executable, arguments: ["input." + format, "output.azw3", "--help"], directory: executable.deletingLastPathComponent(), timeout: 15)
            if help.contains("--output-profile") { capabilities.insert(format) }
        }
        guard !capabilities.isEmpty else { throw MarginError.unavailable("Converter did not expose any supported input-to-AZW3 capability.") }
        let architecture = try await process(URL(fileURLWithPath: "/usr/bin/file"), arguments: ["-b", executable.path], directory: executable.deletingLastPathComponent(), timeout: 10)
        return .init(executable: executable, version: output.trimmingCharacters(in: .whitespacesAndNewlines), executableHash: try Self.hash(executable), architecture: architecture.trimmingCharacters(in: .whitespacesAndNewlines), inputFormats: capabilities)
    }
    public func plan(source: URL, converter: ConverterIdentity) throws -> ConversionPlan {
        let inspection = try BookInspector().inspect(source)
        guard !inspection.protected else { throw MarginError.unavailable("Protected content cannot be converted.") }
        guard converter.inputFormats?.contains(inspection.format) == true else { throw MarginError.invalidInput("This input category is not supported by this conversion adapter.") }
        return .init(source: source, inputHash: try Self.hash(source), inputFormat: inspection.format, converter: converter, outputFormat: "azw3", parameters: [])
    }
    public func execute(_ plan: ConversionPlan, cacheDirectory: URL) async throws -> BookArtifact {
        try Task.checkCancellation()
        guard try Self.hash(plan.source) == plan.inputHash, try Self.hash(plan.converter.executable) == plan.converter.executableHash else { throw MarginError.conflict("Source or converter changed. Create a new conversion plan.") }
        let directory = cacheDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var succeeded = false
        defer { if !succeeded { try? FileManager.default.removeItem(at: directory) } }
        let input = directory.appendingPathComponent("input." + plan.inputFormat)
        try FileManager.default.copyItem(at: plan.source, to: input)
        guard try Self.hash(input) == plan.inputHash else { throw MarginError.conflict("Input changed while preparing conversion.") }
        let output = directory.appendingPathComponent("output.azw3")
        _ = try await process(plan.converter.executable, arguments: [input.path, output.path] + plan.parameters, directory: directory, timeout: 1200)
        try Task.checkCancellation()
        try Self.validateAZW3(output)
        let components = [plan.inputHash, plan.converter.version, plan.converter.executableHash, plan.outputFormat] + plan.parameters
        let key = SHA256.hash(data: try JSONEncoder().encode(components)).map { String(format: "%02x", $0) }.joined()
        let result = BookArtifact(url: output, contentHash: try Self.hash(output), cacheKey: key)
        try FileManager.default.removeItem(at: input)
        succeeded = true
        return result
    }
    public static func validateAZW3(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let size = try handle.seekToEnd(); try handle.seek(toOffset: 0)
        guard size >= 100, let data = try handle.read(upToCount: 1024 * 1024), data.count >= 86,
              String(data: data[60..<68], encoding: .ascii) == "BOOKMOBI" else { throw MarginError.verificationFailed }
        func uint16(_ at: Int) -> Int { Int(data[at]) << 8 | Int(data[at + 1]) }
        func uint32(_ at: Int) -> Int { (0..<4).reduce(0) { ($0 << 8) | Int(data[at + $1]) } }
        let count = uint16(76)
        guard count > 0, 78 + count * 8 <= data.count else { throw MarginError.verificationFailed }
        let offset = uint32(78)
        guard offset >= 78 + count * 8, offset + 40 < data.count,
              String(data: data[(offset + 16)..<(offset + 20)], encoding: .ascii) == "MOBI",
              uint16(offset + 12) == 0 else { throw MarginError.verificationFailed }
        var previous = offset
        for index in 0..<count { let next = uint32(78 + index * 8); guard next >= previous, next < size else { throw MarginError.verificationFailed }; previous = next }
        // This checks the container and encryption header, not rendering on a physical Kindle.
    }
    private func process(_ executable: URL, arguments: [String], directory: URL, timeout: TimeInterval) async throws -> String {
        let state = ProcessState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        if state.cancelled { throw CancellationError() }
                        let process = Process(); process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
                        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
                        pipe.fileHandleForReading.readabilityHandler = { handle in
                            let data = handle.availableData
                            if !data.isEmpty { state.append(data) }
                        }
                        defer { pipe.fileHandleForReading.readabilityHandler = nil; try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
                        try process.run()
                        let pid = process.processIdentifier
                        // Foundation creates a separate process group on macOS. Verify ownership before signaling it.
                        let ownedGroup = getpgid(pid) == pid
                        let deadline = Date().addingTimeInterval(timeout)
                        var stopped = false
                        while process.isRunning {
                            if state.cancelled || state.overflow || Date() >= deadline {
                                stopped = true; if ownedGroup { _ = Darwin.kill(-pid, SIGTERM) } else { process.terminate() }
                                let grace = Date().addingTimeInterval(2)
                                while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.05) }
                                // Process still owns this live child; never target unrelated converter processes.
                                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                                break
                            }
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                        process.waitUntilExit()
                        if ownedGroup, Darwin.kill(-pid, 0) == 0 {
                            _ = Darwin.kill(-pid, SIGTERM)
                            let grace = Date().addingTimeInterval(2)
                            while Darwin.kill(-pid, 0) == 0 && Date() < grace { Thread.sleep(forTimeInterval: 0.05) }
                            if Darwin.kill(-pid, 0) == 0 { _ = Darwin.kill(-pid, SIGKILL) }
                        }
                        pipe.fileHandleForReading.readabilityHandler = nil
                        try? pipe.fileHandleForWriting.close()
                        if let remaining = try? pipe.fileHandleForReading.readToEnd(), !remaining.isEmpty { state.append(remaining) }
                        if state.cancelled { throw CancellationError() }
                        guard !stopped else { throw MarginError.unavailable("Converter exceeded its time or output limit and was stopped.") }
                        guard process.terminationStatus == 0 else { throw MarginError.unavailable("Calibre conversion failed. No output was transferred.") }
                        continuation.resume(returning: state.output)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { state.cancel() }
    }
    private static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }; var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock(); private var isCancelled = false; private var data = Data(); private var tooLarge = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return isCancelled }
    var overflow: Bool { lock.lock(); defer { lock.unlock() }; return tooLarge }
    var output: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    func cancel() { lock.lock(); isCancelled = true; lock.unlock() }
    func append(_ chunk: Data) { lock.lock(); defer { lock.unlock() }; if data.count + chunk.count > 1024 * 1024 { tooLarge = true } else { data.append(chunk) } }
}
