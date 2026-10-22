import Foundation
import KindleDomain

extension SQLiteLibrary {
    public func snapshots() throws -> [SnapshotInfo] {
        try query("SELECT hash,encoding,parser,(SELECT COUNT(*) FROM sources WHERE snapshot=hash) FROM snapshots ORDER BY rowid DESC").map {
            .init(id: $0[0], encoding: $0[1], parserVersion: Int($0[2]) ?? 0, records: Int($0[3]) ?? 0)
        }
    }
    public func snapshotData(hash: String) throws -> Data {
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit), !(try query("SELECT hash FROM snapshots WHERE hash=?", [hash])).isEmpty else { throw MarginError.invalidInput("Snapshot is not in this library.") }
        let data = try Data(contentsOf: root.appendingPathComponent("snapshots/\(hash).txt"))
        guard digest(data) == hash else { throw MarginError.verificationFailed }
        return data
    }
    public func reparseSnapshot(_ parsed: ParsedSnapshot) throws -> ImportReport {
        _ = try snapshotData(hash: parsed.hash)
        return try transaction {
            var added = 0; var existing = 0
            let count = Int(try query("SELECT COUNT(*) FROM clippings").first?.first ?? "0") ?? 0
            for var clipping in parsed.clippings {
                try Task.checkCancellation()
                let source = try query("SELECT c.id,c.payload FROM sources s JOIN clippings c ON c.id=s.clipping WHERE s.snapshot=? AND s.ordinal=?", [parsed.hash, String(clipping.ordinal)]).first
                // Preserve original structured records and local edits when reparsing the same source ordinal.
                // New parser results are only added for records that were previously unparsed.
                if source != nil { existing += 1; continue }
                let originalOrdinal = clipping.ordinal
                if clipping.reliableIdentity, let id = try query("SELECT id FROM clippings WHERE reliable=1 AND fingerprint=?", [clipping.fingerprint]).first?.first {
                    clipping.id = UUID(uuidString: id)!; existing += 1
                } else {
                    if let id = try query("SELECT id FROM books WHERE description=?", [clipping.description]).first?.first { clipping.bookID = UUID(uuidString: id)! }
                    else { try execute("INSERT INTO books VALUES(?,?)", [clipping.bookID.uuidString, clipping.description]) }
                    clipping.ordinal = count + added
                    try execute("INSERT INTO clippings VALUES(?,?,?,?)", [clipping.id.uuidString, clipping.fingerprint, clipping.reliableIdentity ? "1" : "0", try json(clipping)])
                    added += 1
                }
                try execute("INSERT INTO sources VALUES(?,?,?)", [parsed.hash, String(originalOrdinal), clipping.id.uuidString])
            }
            try execute("INSERT INTO parse_runs VALUES(?,?,?) ON CONFLICT(snapshot,version) DO UPDATE SET diagnostics=excluded.diagnostics", [parsed.hash, String(parsed.parserVersion), try json(parsed.diagnostics)])
            try execute("UPDATE snapshots SET parser=?,diagnostics=? WHERE hash=?", [String(parsed.parserVersion), try json(parsed.diagnostics), parsed.hash])
            return .init(added: added, existing: existing, unparsed: parsed.diagnostics.count)
        }
    }
    public func bookMetadata() throws -> [BookMetadata] {
        var books = try query("SELECT id,description FROM books ORDER BY rowid").map { BookMetadata(id: UUID(uuidString: $0[0])!, title: $0[1], evidence: "Exact source description grouping; device-file association is unconfirmed") }
        for row in try query("SELECT payload FROM book_metadata") {
            let metadata = try decode(BookMetadata.self, row[0]); books.removeAll { $0.id == metadata.id }; books.append(metadata)
        }
        return books
    }
    public func saveBookMetadata(_ metadata: BookMetadata) throws {
        guard !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MarginError.invalidInput("Book title cannot be empty.") }
        try execute("INSERT INTO book_metadata VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [metadata.id.uuidString, try json(metadata)])
    }
    public func preferences() throws -> [String: String] { Dictionary(uniqueKeysWithValues: try query("SELECT key,value FROM preferences").map { ($0[0], $0[1]) }) }
    public func setPreference(_ key: String, value: String) throws { try execute("INSERT INTO preferences VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key,value]) }
    public func inspectEntry(packageID: String, entryID: String) throws -> EntryInspection {
        let base = try query("SELECT payload FROM entries WHERE package=? AND id=?", [packageID, entryID]).first?.first
        let local = try query("SELECT payload,hidden,conflict FROM entry_overrides WHERE package=? AND id=?", [packageID, entryID]).first
        return .init(packageID: packageID, entryID: entryID, original: try base.map { try decode(DictionaryEntry.self, $0) }, local: try local.map { try decode(DictionaryEntry.self, $0[0]) }, hidden: local?[1] == "1", conflicted: local?[2] == "1")
    }
    public func entryChanges(packageID: String) throws -> [EntryInspection] {
        try query("SELECT id FROM entry_overrides WHERE package=? ORDER BY id", [packageID]).map { try inspectEntry(packageID: packageID, entryID: $0[0]) }
    }
    public func resolveEntry(packageID: String, entryID: String, keepLocal: Bool) throws {
        if !keepLocal { try restoreEntry(packageID: packageID, entryID: entryID) }
        else {
            let inspection = try inspectEntry(packageID: packageID, entryID: entryID)
            guard let local = inspection.local else { throw MarginError.invalidInput("Local edit no longer exists.") }
            try transaction {
                if inspection.original == nil || inspection.original?.headword != local.headword {
                    var preserved = local; preserved.id = "local-" + UUID().uuidString
                    try edit(packageID: packageID, entry: preserved, hidden: inspection.hidden)
                    try restoreEntry(packageID: packageID, entryID: entryID)
                } else { try execute("UPDATE entry_overrides SET conflict=0 WHERE package=? AND id=?", [packageID, entryID]) }
            }
        }
    }
    public func removeDictionary(id: String) throws { try execute("INSERT OR IGNORE INTO removed_packages VALUES(?)", [id]) }
    public func restoreDictionary(id: String) throws { try execute("DELETE FROM removed_packages WHERE id=?", [id]) }
    public func removedDictionaries() throws -> [DictionarySummary] {
        try query("SELECT payload FROM packages WHERE id IN (SELECT id FROM removed_packages)").map { row in
            let package = try decode(DictionaryPackage.self, row[0]); return .init(id: package.id, name: package.name, version: package.version, conflicts: 0)
        }
    }
    public func searchEntries(_ text: String) throws -> [LookupResult] {
        let terms = text.split(whereSeparator: { $0.isWhitespace }).prefix(20).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        guard !terms.isEmpty else { return [] }
        let matches = try query("SELECT package,entry FROM entry_search WHERE entry_search MATCH ? LIMIT 200", [terms.joined(separator: " AND ")])
        let names = Dictionary(uniqueKeysWithValues: try installedDictionaries().map { ($0.id, $0.name) })
        var results: [LookupResult] = []; var seen: Set<String> = []
        // Local entries are small and user-authored; search their effective content before indexed base content.
        for row in try query("SELECT package,id,payload,hidden FROM entry_overrides") where row[3] != "1" {
            guard let name = names[row[0]] else { continue }
            let entry = try decode(DictionaryEntry.self, row[2])
            if (entry.headword + " " + entry.definition).localizedCaseInsensitiveContains(text) {
                results.append(.init(packageID: row[0], packageName: name, entry: entry, edited: true)); seen.insert(row[0] + ":" + row[1])
            }
        }
        for row in matches {
            guard let name = names[row[0]], !seen.contains(row[0] + ":" + row[1]) else { continue }
            let inspection = try inspectEntry(packageID: row[0], entryID: row[1])
            guard !inspection.hidden, inspection.local == nil, let entry = inspection.original else { continue }
            results.append(.init(packageID: row[0], packageName: name, entry: entry, edited: false))
        }
        return results
    }
}
