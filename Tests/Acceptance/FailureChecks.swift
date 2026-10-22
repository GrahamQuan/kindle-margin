import Foundation
import Darwin
import KindleDomain
import KindlePersistence
import KindleConversion
import KindleDictionary

func failureChecks(root: URL) async throws {
    let libraryRoot = root.appendingPathComponent("migration")
    var original: SQLiteLibrary? = try SQLiteLibrary(root: libraryRoot)
    try await original?.setPreference("migration-proof", value: "retained")
    original = nil
    let sqlite = Process(); sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    sqlite.arguments = [libraryRoot.appendingPathComponent("library.sqlite").path, "UPDATE schema_version SET version=1;"]
    try sqlite.run(); sqlite.waitUntilExit()
    try check(sqlite.terminationStatus == 0, "Migration fixture prepared")
    let migrated = try SQLiteLibrary(root: libraryRoot)
    let preference = try await migrated.preferences()
    let files = try FileManager.default.contentsOfDirectory(atPath: libraryRoot.path)
    try check(preference["migration-proof"] == "retained" && files.contains(where: { $0.hasPrefix("library-before-v2-") }), "SQLite v1 migration retains data and creates consistent backup")
    let package = DictionaryPackage(id: "cancel-install", name: "Synthetic", sourceLanguage: "en", targetLanguage: "en", license: "Synthetic", entries: [.init(id: "one", headword: "stable", definition: "Original")])
    try await migrated.install(package)
    var replacement = package; replacement.version = "2"; replacement.entries[0].definition = "Replacement"
    let cancelledInstall = Task { [value = replacement] in withUnsafeCurrentTask { $0?.cancel() }; try await migrated.install(value) }
    try await rejects("DICT-03 cancelled dictionary transaction rolls back") { try await cancelledInstall.value }
    let retained = try await migrated.lookup("stable")
    try check(retained.first?.entry.definition == "Original", "DICT-03 cancelled upgrade retains prior searchable package")
    let slow = HeldDownload()
    let item = CatalogPackage(id: package.id, version: package.version, sourceLanguage: "en", targetLanguage: "en", size: 10, sha256: String(repeating: "a", count: 64), url: URL(string: "https://synthetic.invalid/package")!, source: "Synthetic", license: "Synthetic")
    let downloads = try DictionaryDownloadService(catalog: [item], transport: slow, parser: DictionaryParser(), repository: migrated)
    let downloadRoot = root.appendingPathComponent("bounded-downloads")
    let firstDownload = Task { try await downloads.download(id: item.id, workDirectory: downloadRoot) }
    let secondDownload = Task { try await downloads.download(id: item.id, workDirectory: downloadRoot) }
    for _ in 0..<200 { if await slow.started == 2 { break }; try await Task.sleep(for: .milliseconds(10)) }
    let started = await slow.started
    try check(started == 2, "DICT-03 two downloads may run concurrently")
    try await rejects("DICT-03 additional downloads are bounded before transport starts") { try await downloads.download(id: item.id, workDirectory: downloadRoot) }
    firstDownload.cancel(); secondDownload.cancel()
    _ = try? await firstDownload.value; _ = try? await secondDownload.value
    try check(try FileManager.default.contentsOfDirectory(atPath: downloadRoot.path).isEmpty, "DICT-03 cancellation clears both download work directories")
    let destination = root.appendingPathComponent("missing-parent/export")
    try await rejects("MD-02 filesystem failure does not create partial export") { _ = try await migrated.publishMarkdown("test", bookID: UUID(), directory: destination, title: "Test") }
    let input = root.appendingPathComponent("failure-source.txt"); let bytes = Data("Synthetic original".utf8); try bytes.write(to: input)
    let executable = root.appendingPathComponent("synthetic-converter")
    let childFile = root.appendingPathComponent("owned-child.pid")
    let script = """
    #!/bin/sh
    if [ "$1" = "--version" ]; then echo 'Calibre synthetic test'; exit 0; fi
    if [ "$3" = "--help" ]; then echo '--output-profile'; exit 0; fi
    /bin/sleep 45 &
    child=$!
    echo "$child" > '\(childFile.path)'
    wait "$child"
    exit 17
    """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let engine = CalibreConversionEngine(); let identity = try await engine.validate(executable: executable)
    try check(identity.architecture != nil && identity.inputFormats?.contains("epub") == true, "BOOK-03 converter architecture and probed capabilities recorded")
    let plan = try engine.plan(source: input, converter: identity)
    let cache = root.appendingPathComponent("failed-conversions")
    let task = Task { try await engine.execute(plan, cacheDirectory: cache) }
    for _ in 0..<200 { if FileManager.default.fileExists(atPath: childFile.path) { break }; try await Task.sleep(for: .milliseconds(10)) }
    task.cancel()
    try await rejects("BOOK-03 cancellation waits for converter termination") { _ = try await task.value }
    if let text = try? String(contentsOf: childFile), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
        for _ in 0..<100 { if Darwin.kill(pid, 0) != 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
        try check(Darwin.kill(pid, 0) != 0, "BOOK-03 task-owned converter child process exited")
    } else { throw CheckFailure(message: "Converter child did not start") }
    try check(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty && Data(contentsOf: input) == bytes, "BOOK-03 cancelled conversion cleans partial cache and preserves original")
    let failing = script.replacingOccurrences(of: "/bin/sleep 45 &\nchild=$!\necho \"$child\" > '\(childFile.path)'\nwait \"$child\"", with: "echo 'Synthetic failure' >&2")
    try Data(failing.utf8).write(to: executable)
    let failedIdentity = try await engine.validate(executable: executable)
    let failedPlan = try engine.plan(source: input, converter: failedIdentity)
    try await rejects("BOOK-03 failed converter returns no artifact") { _ = try await engine.execute(failedPlan, cacheDirectory: cache) }
    try check(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty, "BOOK-03 failed conversion removes its temporary output")
}

private actor HeldDownload: PackageDownloadTransport {
    private(set) var started = 0
    func download(_ url: URL, expectedSize: Int64, to destination: URL) async throws {
        started += 1
        try await Task.sleep(for: .seconds(30))
        throw URLError(.timedOut)
    }
}
