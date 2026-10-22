import Foundation

public enum MarginError: Error, LocalizedError, Sendable {
    case invalidInput(String), unavailable(String), conflict(String), staleSession, cancelled, verificationFailed
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message), .unavailable(let message), .conflict(let message): return message
        case .staleSession: return "The device connection changed. Rescan and confirm a new plan."
        case .cancelled: return "The operation was cancelled."
        case .verificationFailed: return "Content verification failed. Inspect the outcome before retrying."
        }
    }
}
public enum Limits {
    public static let importBytes = 64 * 1024 * 1024
    public static let recordCharacters = 1_000_000
}
public enum ClippingKind: String, Codable, CaseIterable, Sendable { case highlight, note, bookmark }
public struct Clipping: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var bookID: UUID
    public var description: String
    public var kind: ClippingKind
    public var body: String
    public var location: String?
    public var page: String?
    public var timestamp: String?
    public var ordinal: Int
    public var fingerprint: String
    public var sourceTimestamp: SourceTimestamp?
    public var reliableIdentity: Bool
    public init(id: UUID = UUID(), bookID: UUID = UUID(), description: String, kind: ClippingKind, body: String, location: String?, page: String?, timestamp: String?, ordinal: Int, fingerprint: String, reliableIdentity: Bool) {
        self.id = id; self.bookID = bookID; self.description = description; self.kind = kind; self.body = body
        self.location = location; self.page = page; self.timestamp = timestamp; self.ordinal = ordinal
        self.fingerprint = fingerprint; self.reliableIdentity = reliableIdentity
    }
}
public struct ClippingOverride: Codable, Sendable, Equatable {
    public var body: String?
    public var tags: [String]
    public var hidden: Bool
    public var bookID: UUID?
    public init(body: String? = nil, tags: [String] = [], hidden: Bool = false, bookID: UUID? = nil) {
        self.body = body; self.tags = tags; self.hidden = hidden; self.bookID = bookID
    }
}
public struct ParseDiagnostic: Codable, Identifiable, Sendable {
    public var id: Int { ordinal }
    public var ordinal: Int
    public var reason: String
    public var raw: String
    public init(ordinal: Int, reason: String, raw: String) { self.ordinal = ordinal; self.reason = reason; self.raw = raw }
}
public struct ParsedSnapshot: Sendable {
    public var hash: String
    public var encoding: String
    public var parserVersion: Int
    public var clippings: [Clipping]
    public var diagnostics: [ParseDiagnostic]
    public init(hash: String, encoding: String, parserVersion: Int, clippings: [Clipping], diagnostics: [ParseDiagnostic]) {
        self.hash = hash; self.encoding = encoding; self.parserVersion = parserVersion; self.clippings = clippings; self.diagnostics = diagnostics
    }
}
public struct ImportReport: Sendable {
    public var added: Int; public var existing: Int; public var unparsed: Int
    public init(added: Int, existing: Int, unparsed: Int) { self.added = added; self.existing = existing; self.unparsed = unparsed }
}
public struct AnnotationItem: Identifiable, Sendable {
    public var id: UUID { original.id }
    public var original: Clipping
    public var override: ClippingOverride
    public var body: String { override.body ?? original.body }
    public var bookID: UUID { override.bookID ?? original.bookID }
    public init(original: Clipping, override: ClippingOverride = .init()) { self.original = original; self.override = override }
}
public protocol ClippingsParser: Sendable { func parse(_ data: Data) throws -> ParsedSnapshot }
public protocol MarkdownRenderer: Sendable { func render(_ items: [AnnotationItem], includeHidden: Bool, includeTags: Bool, book: BookMetadata?) -> String }
public protocol LibraryRepository: Sendable {
    func importSnapshot(_ data: Data, parsed: ParsedSnapshot) async throws -> ImportReport
    func snapshots() async throws -> [SnapshotInfo]
    func snapshotData(hash: String) async throws -> Data
    func reparseSnapshot(_ parsed: ParsedSnapshot) async throws -> ImportReport
    func bookMetadata() async throws -> [BookMetadata]
    func saveBookMetadata(_ metadata: BookMetadata) async throws
    func preferences() async throws -> [String: String]
    func setPreference(_ key: String, value: String) async throws
    func annotations() async throws -> [AnnotationItem]
    func updateOverride(id: UUID, value: ClippingOverride) async throws
    func diagnostics() async throws -> [ParseDiagnostic]
    func publishMarkdown(_ text: String, bookID: UUID, directory: URL, title: String) async throws -> URL
    func saveJob(_ job: JobRecord) async throws
    func jobs() async throws -> [JobRecord]
}
public enum JobState: String, Codable, Sendable { case queued, preparing, running, verifying, completed, cancelling, cancelled, failed, needsReconciliation }
public struct JobRecord: Codable, Identifiable, Sendable {
    public var id: UUID; public var requestID: UUID; public var kind: String; public var state: JobState
    public var stage: String; public var error: String?; public var deviceID: UUID?
    public var plan: Data?
    public var events: [JobEvent]?
    public var outcome: String?
    public init(requestID: UUID, kind: String, deviceID: UUID? = nil) {
        id = UUID(); self.requestID = requestID; self.kind = kind; self.deviceID = deviceID; state = .queued; stage = "Queued"
    }
}
public struct DictionaryEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: String; public var headword: String; public var definition: String
    public var partOfSpeech: String?; public var example: String?; public var forms: [String]
    public init(id: String, headword: String, definition: String, partOfSpeech: String? = nil, example: String? = nil, forms: [String] = []) {
        self.id = id; self.headword = headword; self.definition = definition; self.partOfSpeech = partOfSpeech; self.example = example; self.forms = forms
    }
}
extension DictionaryEntry {
    private enum CodingKeys: String, CodingKey { case id, headword, definition, partOfSpeech, example, forms }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        headword = try values.decode(String.self, forKey: .headword)
        definition = try values.decode(String.self, forKey: .definition)
        partOfSpeech = try values.decodeIfPresent(String.self, forKey: .partOfSpeech)
        example = try values.decodeIfPresent(String.self, forKey: .example)
        forms = try values.decodeIfPresent([String].self, forKey: .forms) ?? []
    }
}
public struct DictionaryPackage: Codable, Sendable {
    public var schemaVersion: Int; public var id: String; public var version: String; public var name: String
    public var sourceLanguage: String; public var targetLanguage: String; public var license: String; public var entries: [DictionaryEntry]
    public init(id: String, version: String = "1.0.0", name: String, sourceLanguage: String, targetLanguage: String, license: String, entries: [DictionaryEntry]) {
        schemaVersion = 1; self.id = id; self.version = version; self.name = name; self.sourceLanguage = sourceLanguage; self.targetLanguage = targetLanguage; self.license = license; self.entries = entries
    }
}
public struct LookupResult: Identifiable, Sendable {
    public var id: String { packageID + ":" + entry.id }
    public var packageID: String; public var packageName: String; public var entry: DictionaryEntry; public var edited: Bool
    public init(packageID: String, packageName: String, entry: DictionaryEntry, edited: Bool) { self.packageID = packageID; self.packageName = packageName; self.entry = entry; self.edited = edited }
}
public protocol DictionaryParsing: Sendable {
    func parseJSON(_ data: Data) throws -> DictionaryPackage
    func parseCSV(_ data: Data, name: String, source: String, target: String) throws -> DictionaryPackage
}
public struct DictionarySummary: Identifiable, Sendable {
    public var id: String; public var name: String; public var version: String; public var conflicts: Int
    public init(id: String, name: String, version: String, conflicts: Int) { self.id = id; self.name = name; self.version = version; self.conflicts = conflicts }
}
public protocol DictionaryRepository: Sendable {
    func searchEntries(_ text: String) async throws -> [LookupResult]
    func inspectEntry(packageID: String, entryID: String) async throws -> EntryInspection
    func entryChanges(packageID: String) async throws -> [EntryInspection]
    func resolveEntry(packageID: String, entryID: String, keepLocal: Bool) async throws
    func removeDictionary(id: String) async throws
    func restoreDictionary(id: String) async throws
    func removedDictionaries() async throws -> [DictionarySummary]
    func installedDictionaries() async throws -> [DictionarySummary]
    func restoreEntry(packageID: String, entryID: String) async throws
    func setDictionaryPriority(ids: [String]) async throws
    func install(_ package: DictionaryPackage) async throws
    func lookup(_ query: String) async throws -> [LookupResult]
    func edit(packageID: String, entry: DictionaryEntry, hidden: Bool) async throws
    func mergedPackage(id: String) async throws -> DictionaryPackage
}
public struct DeviceFileRef: Hashable, Codable, Sendable {
    public let deviceID: UUID; public let sessionID: UUID; public let token: UUID
    public init(deviceID: UUID, sessionID: UUID, token: UUID) { self.deviceID = deviceID; self.sessionID = sessionID; self.token = token }
}
public struct DeviceEntry: Sendable, Identifiable {
    public var id: DeviceFileRef; public var name: String; public var size: Int64; public var isDirectory: Bool
    public init(id: DeviceFileRef, name: String, size: Int64, isDirectory: Bool) { self.id = id; self.name = name; self.size = size; self.isDirectory = isDirectory }
}
public protocol DeviceTransport: Sendable {
    func list(in directory: DeviceFileRef) async throws -> [DeviceEntry]
    func download(_ file: DeviceFileRef, to destination: URL) async throws
    func upload(_ source: URL, into directory: DeviceFileRef, name: String) async throws -> DeviceFileRef
    func delete(_ file: DeviceFileRef) async throws
}
