import Foundation

public enum TimestampStatus: String, Codable, Sendable { case missing, unparsed, localDateTime }
public struct SourceTimestamp: Codable, Sendable, Equatable {
    public let original: String?
    public let status: TimestampStatus
    public let components: DateComponents?
    public init(original: String?, status: TimestampStatus, components: DateComponents? = nil) { self.original = original; self.status = status; self.components = components }
}
public struct SnapshotInfo: Identifiable, Sendable {
    public let id: String
    public let encoding: String
    public let parserVersion: Int
    public let records: Int
    public init(id: String, encoding: String, parserVersion: Int, records: Int) { self.id = id; self.encoding = encoding; self.parserVersion = parserVersion; self.records = records }
}
public struct BookMetadata: Codable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var author: String?
    public var evidence: String
    public init(id: UUID, title: String, author: String? = nil, evidence: String = "User-confirmed metadata") { self.id = id; self.title = title; self.author = author; self.evidence = evidence }
}
public struct EntryInspection: Identifiable, Sendable {
    public var id: String { entryID }
    public let packageID: String
    public let entryID: String
    public let original: DictionaryEntry?
    public let local: DictionaryEntry?
    public let hidden: Bool
    public let conflicted: Bool
    public init(packageID: String, entryID: String, original: DictionaryEntry?, local: DictionaryEntry?, hidden: Bool, conflicted: Bool) {
        self.packageID = packageID; self.entryID = entryID; self.original = original; self.local = local; self.hidden = hidden; self.conflicted = conflicted
    }
}
public protocol WordAnalyzing: Sendable { func candidates(for word: String) -> [String] }
public struct NoWordAnalysis: WordAnalyzing { public init() {}; public func candidates(for word: String) -> [String] { [] } }
public struct JobEvent: Codable, Sendable {
    public let time: Date
    public let stage: String
    public let message: String
    public init(stage: String, message: String) { time = Date(); self.stage = stage; self.message = message }
}
