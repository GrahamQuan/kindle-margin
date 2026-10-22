import Foundation
import CryptoKit
import CSQLite
import KindleDomain

public actor SQLiteLibrary: LibraryRepository, DictionaryRepository {
    private var db: OpaquePointer?
    let root: URL
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("snapshots"), withIntermediateDirectories: true)
        let database = root.appendingPathComponent("library.sqlite")
        guard sqlite3_open(database.path, &db) == SQLITE_OK else { throw MarginError.unavailable("Cannot open the library database. Existing data was preserved.") }
        sqlite3_busy_timeout(db, 5_000)
        var versionStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &versionStatement, nil) == SQLITE_OK {
            let status = sqlite3_step(versionStatement)
            let supported = status == SQLITE_ROW && (1...2).contains(Int(sqlite3_column_int(versionStatement, 0)))
            sqlite3_finalize(versionStatement)
            guard supported else { sqlite3_close(db); db = nil; throw MarginError.unavailable("Unsupported library schema. Existing data was preserved.") }
        } else {
            sqlite3_finalize(versionStatement)
            // Refuse to adopt an unrelated nonempty database as a fresh library.
            var tables: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sqlite_master WHERE type='table'", -1, &tables, nil)
            let hasTables = sqlite3_step(tables) == SQLITE_ROW && sqlite3_column_int(tables, 0) > 0
            sqlite3_finalize(tables)
            guard !hasTables else { sqlite3_close(db); db = nil; throw MarginError.unavailable("Unrecognized database schema. Existing data was preserved.") }
        }
        // Preserve a consistent SQLite copy before any version upgrade.
        var schemaProbe: OpaquePointer?
        var previousVersion = 0
        if sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &schemaProbe, nil) == SQLITE_OK, sqlite3_step(schemaProbe) == SQLITE_ROW {
            previousVersion = Int(sqlite3_column_int(schemaProbe, 0))
        }
        sqlite3_finalize(schemaProbe)
        if previousVersion == 1 {
            let backupURL = root.appendingPathComponent("library-before-v2-" + UUID().uuidString + ".sqlite")
            var backupDB: OpaquePointer?
            guard sqlite3_open(backupURL.path, &backupDB) == SQLITE_OK else { sqlite3_close(backupDB); sqlite3_close(db); db = nil; throw MarginError.unavailable("Cannot create migration backup. Library was not upgraded.") }
            guard let backup = sqlite3_backup_init(backupDB, "main", db, "main") else { sqlite3_close(backupDB); sqlite3_close(db); db = nil; throw MarginError.unavailable("Cannot start migration backup.") }
            let result = sqlite3_backup_step(backup, -1)
            sqlite3_backup_finish(backup); sqlite3_close(backupDB)
            guard result == SQLITE_DONE else { sqlite3_close(db); db = nil; throw MarginError.unavailable("Migration backup failed. Original data was retained.") }
        }
        let schema = """
        PRAGMA foreign_keys=ON;
        BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS schema_version(version INTEGER NOT NULL);
        INSERT INTO schema_version SELECT 1 WHERE NOT EXISTS(SELECT 1 FROM schema_version);
        CREATE TABLE IF NOT EXISTS books(id TEXT PRIMARY KEY, description TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS snapshots(hash TEXT PRIMARY KEY, encoding TEXT, parser INTEGER, diagnostics BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS clippings(id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, reliable INTEGER NOT NULL, payload BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS clipping_fingerprint ON clippings(fingerprint);
        CREATE TABLE IF NOT EXISTS sources(snapshot TEXT REFERENCES snapshots(hash), ordinal INTEGER, clipping TEXT REFERENCES clippings(id), PRIMARY KEY(snapshot, ordinal));
        CREATE TABLE IF NOT EXISTS overrides(clipping TEXT PRIMARY KEY REFERENCES clippings(id), payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS exports(path TEXT PRIMARY KEY, hash TEXT NOT NULL, book TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, request TEXT UNIQUE NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS packages(id TEXT PRIMARY KEY, priority INTEGER NOT NULL, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS entries(package TEXT REFERENCES packages(id), id TEXT, headword TEXT, normalized TEXT, payload BLOB, PRIMARY KEY(package,id));
        CREATE INDEX IF NOT EXISTS exact_headword ON entries(headword);
        CREATE INDEX IF NOT EXISTS normalized_headword ON entries(normalized);
        CREATE TABLE IF NOT EXISTS forms(package TEXT, entry TEXT, form TEXT, FOREIGN KEY(package,entry) REFERENCES entries(package,id) ON DELETE CASCADE);
        CREATE INDEX IF NOT EXISTS inflection_form ON forms(form);
        CREATE TABLE IF NOT EXISTS entry_overrides(package TEXT REFERENCES packages(id), id TEXT, hidden INTEGER, payload BLOB, base_version TEXT, conflict INTEGER DEFAULT 0, PRIMARY KEY(package,id));
        """
        let migration = """
        CREATE TABLE IF NOT EXISTS preferences(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS book_metadata(id TEXT PRIMARY KEY, payload TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS removed_packages(id TEXT PRIMARY KEY REFERENCES packages(id));
        CREATE TABLE IF NOT EXISTS parse_runs(snapshot TEXT REFERENCES snapshots(hash), version INTEGER, diagnostics TEXT, PRIMARY KEY(snapshot,version));
        CREATE VIRTUAL TABLE IF NOT EXISTS entry_search USING fts5(package UNINDEXED, entry UNINDEXED, headword, definition, tokenize='unicode61');
        \(previousVersion < 2 ? "DELETE FROM entry_search; INSERT INTO entry_search(package,entry,headword,definition) SELECT package,id,headword,json_extract(payload,'$.definition') FROM entries;" : "")
        UPDATE schema_version SET version=2;
        COMMIT;
        """
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, schema + migration, nil, nil, &error) == SQLITE_OK else {
            sqlite3_free(error); sqlite3_exec(db, "ROLLBACK", nil, nil, nil); sqlite3_close(db); db = nil
            throw MarginError.unavailable("Library schema could not be opened. Existing data was preserved.")
        }
    }
    deinit { sqlite3_close(db) }
    func execute(_ sql: String, _ values: [String] = []) throws {
        _ = try query(sql, values)
    }
    func query(_ sql: String, _ values: [String] = []) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw MarginError.unavailable("Database statement failed.") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
        var rows: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw MarginError.unavailable("Database operation failed. No empty replacement database was created.") }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                guard let value = sqlite3_column_text(statement, column) else { return "" }
                return String(cString: value)
            })
        }
        return rows
    }
    func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
    func decode<T: Decodable>(_ type: T.Type, _ value: String) throws -> T { try decoder.decode(type, from: Data(value.utf8)) }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try body(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    public func importSnapshot(_ data: Data, parsed: ParsedSnapshot) throws -> ImportReport {
        guard digest(data) == parsed.hash else { throw MarginError.verificationFailed }
        if !((try query("SELECT hash FROM snapshots WHERE hash=?", [parsed.hash])).isEmpty) {
            return .init(added: 0, existing: parsed.clippings.count, unparsed: parsed.diagnostics.count)
        }
        let destination = root.appendingPathComponent("snapshots/\(parsed.hash).txt")
        if !FileManager.default.fileExists(atPath: destination.path) { try data.write(to: destination, options: .withoutOverwriting) }
        return try transaction {
            try execute("INSERT INTO snapshots VALUES(?,?,?,?)", [parsed.hash, parsed.encoding, String(parsed.parserVersion), try json(parsed.diagnostics)])
            var added = 0; var existing = 0
            let previousCount = Int(try query("SELECT COUNT(*) FROM clippings").first?.first ?? "0") ?? 0
            for var clipping in parsed.clippings {
                try Task.checkCancellation()
                let matches = try query("SELECT id FROM clippings WHERE fingerprint=? AND reliable=1", [clipping.fingerprint])
                if clipping.reliableIdentity, let match = matches.first?.first { clipping.id = UUID(uuidString: match)!; existing += 1 }
                else {
                    let books = try query("SELECT id FROM books WHERE description=?", [clipping.description])
                    if let id = books.first?.first { clipping.bookID = UUID(uuidString: id)! }
                    else { try execute("INSERT INTO books VALUES(?,?)", [clipping.bookID.uuidString, clipping.description]) }
                    clipping.ordinal = previousCount + added
                    try execute("INSERT INTO clippings VALUES(?,?,?,?)", [clipping.id.uuidString, clipping.fingerprint, clipping.reliableIdentity ? "1" : "0", try json(clipping)])
                    added += 1
                }
                // Source ordinal belongs to the original snapshot, independent of stable library order.
                let sourceOrdinal = parsed.clippings[added + existing - 1].ordinal
                try execute("INSERT INTO sources VALUES(?,?,?)", [parsed.hash, String(sourceOrdinal), clipping.id.uuidString])
            }
            return .init(added: added, existing: existing, unparsed: parsed.diagnostics.count)
        }
    }
    public func annotations() throws -> [AnnotationItem] {
        try query("SELECT c.payload, o.payload FROM clippings c LEFT JOIN overrides o ON o.clipping=c.id ORDER BY c.rowid").map {
            .init(original: try decode(Clipping.self, $0[0]), override: $0[1].isEmpty ? .init() : try decode(ClippingOverride.self, $0[1]))
        }
    }
    public func updateOverride(id: UUID, value: ClippingOverride) throws {
        try execute("INSERT INTO overrides VALUES(?,?) ON CONFLICT(clipping) DO UPDATE SET payload=excluded.payload", [id.uuidString, try json(value)])
    }
    public func diagnostics() throws -> [ParseDiagnostic] {
        try query("SELECT diagnostics FROM snapshots ORDER BY rowid").flatMap { try decode([ParseDiagnostic].self, $0[0]) }
    }
    public func publishMarkdown(_ text: String, bookID: UUID, directory: URL, title: String) throws -> URL {
        try Task.checkCancellation()
        let safe = String(title.map { "/\\:?*\"<>|\n\r".contains($0) || $0.unicodeScalars.contains(where: { $0.value < 32 }) ? "_" : $0 }.prefix(100))
        let name = (safe.isEmpty ? "Book" : safe) + "-" + bookID.uuidString.prefix(8)
        var destination = directory.appendingPathComponent(name + ".md")
        if FileManager.default.fileExists(atPath: destination.path) {
            let recorded = try query("SELECT hash FROM exports WHERE path=? AND book=?", [destination.path, bookID.uuidString]).first?.first
            if recorded != digest(try Data(contentsOf: destination)) {
                destination = directory.appendingPathComponent(name + "-conflict-" + UUID().uuidString.prefix(8) + ".md")
            }
        }
        let temporary = directory.appendingPathComponent(".kindle-margin-" + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let data = Data(text.utf8)
        try data.write(to: temporary, options: .withoutOverwriting)
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            let recorded = try query("SELECT hash FROM exports WHERE path=?", [destination.path]).first?.first
            guard recorded == digest(try Data(contentsOf: destination)) else { throw MarginError.conflict("Export changed while preparing. Retry to create a conflict copy.") }
            // Retain the replaced inode as a recovery copy, including changes by non-coordinating editors.
            let backupName = name + "-previous-" + UUID().uuidString.prefix(8) + ".md"
            var coordinationError: NSError?
            var publishError: Error?
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinated in
                do {
                    guard recorded == self.digest(try Data(contentsOf: coordinated)) else { throw MarginError.conflict("Export changed while preparing. Retry to create a conflict copy.") }
                    _ = try FileManager.default.replaceItemAt(coordinated, withItemAt: temporary, backupItemName: backupName, options: .withoutDeletingBackupItem)
                } catch { publishError = error }
            }
            if let coordinationError { throw coordinationError }
            if let publishError { throw publishError }
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
        try execute("INSERT INTO exports VALUES(?,?,?) ON CONFLICT(path) DO UPDATE SET hash=excluded.hash,book=excluded.book", [destination.path, digest(data), bookID.uuidString])
        return destination
    }
    public func saveJob(_ job: JobRecord) throws {
        if let payload = try query("SELECT payload FROM jobs WHERE id=?", [job.id.uuidString]).first?.first {
            let original = try decode(JobRecord.self, payload)
            if [.completed,.failed,.cancelled,.needsReconciliation].contains(original.state), [.queued,.preparing,.running,.verifying,.cancelling].contains(job.state) { throw MarginError.conflict("A finished job cannot return to an active state.") }
            guard original.requestID == job.requestID, original.deviceID == job.deviceID, original.plan == job.plan else { throw MarginError.conflict("A confirmed job plan and target cannot be changed.") }
        }
        try execute("INSERT INTO jobs VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [job.id.uuidString, job.requestID.uuidString, try json(job)])
    }
    public func jobs() throws -> [JobRecord] { try query("SELECT payload FROM jobs ORDER BY rowid DESC").map { try decode(JobRecord.self, $0[0]) } }
    public func install(_ package: DictionaryPackage) throws {
        if let payload = try query("SELECT payload FROM packages WHERE id=?", [package.id]).first?.first {
            let previous = try decode(DictionaryPackage.self, payload)
            guard previous.sourceLanguage == package.sourceLanguage, previous.targetLanguage == package.targetLanguage else { throw MarginError.conflict("Dictionary languages changed under the same package identity. Import with a new package ID; the installed version and edits are retained.") }
        }
        let original = try encoder.encode(package)
        let originals = root.appendingPathComponent("dictionaries")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let originalURL = originals.appendingPathComponent(digest(original) + ".json")
        if !FileManager.default.fileExists(atPath: originalURL.path) { try original.write(to: originalURL, options: .withoutOverwriting) }
        var metadata = package; metadata.entries = []
        try transaction {
            // Entries are indexed separately; lookup never decodes the entire package.
            try execute("INSERT INTO packages VALUES(?,(SELECT COUNT(*) FROM packages),?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [package.id, try json(metadata)])
            for entry in package.entries {
                try Task.checkCancellation()
                if let old = try query("SELECT headword FROM entries WHERE package=? AND id=?", [package.id, entry.id]).first?.first, old != entry.headword {
                    try execute("UPDATE entry_overrides SET conflict=1 WHERE package=? AND id=?", [package.id, entry.id])
                }
            }
            try execute("DELETE FROM removed_packages WHERE id=?", [package.id])
            try execute("DELETE FROM entry_search WHERE package=?", [package.id])
            try execute("DELETE FROM entries WHERE package=?", [package.id])
            for entry in package.entries {
                try Task.checkCancellation()
                try execute("INSERT INTO entries VALUES(?,?,?,?,?)", [package.id, entry.id, entry.headword, normalized(entry.headword), try json(entry)])
                try execute("INSERT INTO entry_search(package,entry,headword,definition) VALUES(?,?,?,?)", [package.id, entry.id, entry.headword, entry.definition])
                for form in entry.forms { try execute("INSERT INTO forms VALUES(?,?,?)", [package.id, entry.id, normalized(form)]) }
            }
            try execute("UPDATE entry_overrides SET conflict=1 WHERE package=? AND base_version!='' AND id NOT IN (SELECT id FROM entries WHERE package=?)", [package.id, package.id])
        }
    }
    public func lookup(_ queryText: String) throws -> [LookupResult] {
        let key = normalized(queryText)
        guard !key.isEmpty else { return [] }
        let rows = try query("""
        SELECT p.id,p.payload,e.payload,o.payload,o.hidden FROM entries e
        JOIN packages p ON p.id=e.package LEFT JOIN entry_overrides o ON o.package=e.package AND o.id=e.id
        WHERE p.id NOT IN (SELECT id FROM removed_packages) AND e.rowid IN (
          SELECT rowid FROM entries WHERE headword=?
          UNION SELECT rowid FROM entries WHERE normalized=?
          UNION SELECT e2.rowid FROM forms f JOIN entries e2 ON e2.package=f.package AND e2.id=f.entry WHERE f.form=?
        )
        ORDER BY (o.payload IS NOT NULL) DESC, CASE WHEN e.headword=? THEN 0 WHEN e.normalized=? THEN 1 ELSE 2 END,p.priority,e.rowid
        """, [queryText, key, key, queryText, key])
        var results: [LookupResult] = []
        var seen: Set<String> = []
        let overrides = try query("SELECT o.package,p.payload,o.id,o.hidden,o.payload FROM entry_overrides o JOIN packages p ON p.id=o.package WHERE p.id NOT IN (SELECT id FROM removed_packages) ORDER BY p.priority")
        for row in overrides {
            seen.insert(row[0] + ":" + row[2])
            guard row[3] != "1" else { continue }
            let entry = try decode(DictionaryEntry.self, row[4])
            guard entry.headword == queryText || normalized(entry.headword) == key || entry.forms.contains(where: { normalized($0) == key }) else { continue }
            let package = try decode(DictionaryPackage.self, row[1])
            results.append(.init(packageID: row[0], packageName: package.name, entry: entry, edited: true))
        }
        for row in rows {
            let entry = try decode(DictionaryEntry.self, row[2])
            guard !seen.contains(row[0] + ":" + entry.id) else { continue }
            let package = try decode(DictionaryPackage.self, row[1])
            results.append(.init(packageID: row[0], packageName: package.name, entry: entry, edited: false))
        }
        return results
    }
    public func installedDictionaries() throws -> [DictionarySummary] {
        try query("SELECT p.id,p.payload,(SELECT COUNT(*) FROM entry_overrides o WHERE o.package=p.id AND o.conflict=1) FROM packages p WHERE p.id NOT IN (SELECT id FROM removed_packages) ORDER BY p.priority").map { row in
            let package = try decode(DictionaryPackage.self, row[1])
            return .init(id: row[0], name: package.name, version: package.version, conflicts: Int(row[2]) ?? 0)
        }
    }
    public func restoreEntry(packageID: String, entryID: String) throws {
        try execute("DELETE FROM entry_overrides WHERE package=? AND id=?", [packageID, entryID])
    }
    public func setDictionaryPriority(ids: [String]) throws {
        let existing = Set(try query("SELECT id FROM packages WHERE id NOT IN (SELECT id FROM removed_packages)").compactMap(\.first))
        guard Set(ids) == existing, ids.count == existing.count else { throw MarginError.conflict("Dictionary list changed. Refresh before reordering.") }
        try transaction { for (index, id) in ids.enumerated() { try execute("UPDATE packages SET priority=? WHERE id=?", [String(index), id]) } }
    }

    public func edit(packageID: String, entry: DictionaryEntry, hidden: Bool) throws {
        guard let data = try query("SELECT payload FROM packages WHERE id=?", [packageID]).first?.first else { throw MarginError.invalidInput("Dictionary no longer exists.") }
        let hasBase = !(try query("SELECT id FROM entries WHERE package=? AND id=?", [packageID, entry.id])).isEmpty
        let version = hasBase ? try decode(DictionaryPackage.self, data).version : ""
        try execute("INSERT INTO entry_overrides VALUES(?,?,?,?,?,0) ON CONFLICT(package,id) DO UPDATE SET hidden=excluded.hidden,payload=excluded.payload", [packageID, entry.id, hidden ? "1" : "0", try json(entry), version])
    }
    public func mergedPackage(id: String) throws -> DictionaryPackage {
        guard let data = try query("SELECT payload FROM packages WHERE id=?", [id]).first?.first else { throw MarginError.invalidInput("Dictionary does not exist.") }
        var package = try decode(DictionaryPackage.self, data)
        package.entries = try query("SELECT payload FROM entries WHERE package=? ORDER BY rowid", [id]).map { try decode(DictionaryEntry.self, $0[0]) }
        for row in try query("SELECT id,hidden,payload FROM entry_overrides WHERE package=?", [id]) {
            package.entries.removeAll { $0.id == row[0] }
            if row[1] != "1" { package.entries.append(try decode(DictionaryEntry.self, row[2])) }
        }
        return package
    }
    func normalized(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.lowercased() }
    func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
