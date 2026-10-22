import Foundation
import CryptoKit
import KindleDomain
import KindleClippings
import KindlePersistence
import KindleDictionary
import KindleDevice
import KindleConversion
import KindleApplication

struct CheckFailure: Error { let message: String }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw CheckFailure(message: message) }
    print("PASS: \(message)")
}
func rejects(_ label: String, _ operation: () async throws -> Void) async throws {
    do { try await operation() } catch { print("PASS: \(label)"); return }
    throw CheckFailure(message: label)
}
struct SyntheticDownload: PackageDownloadTransport {
    let data: Data
    func download(_ url: URL, expectedSize: Int64, to destination: URL) async throws { try data.write(to: destination, options: .withoutOverwriting) }
}
@main struct AcceptanceChecks {
    static func main() async {
        setbuf(stdout, nil)
        do { try await run() } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kindle-margin-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        if ProcessInfo.processInfo.environment["KINDLE_MARGIN_UI_ONLY"] == "1" { try await uiChecks(root: root); return }
        let parser = SnapshotParser()
        let source = """
        Book (An Author)
        - Your Highlight on page 10 | Location 100-102 | Added on Thursday, October 22, 2026 09:30:00

        A *special* <line> & text.
        Another line.
        ==========
        中文书名（作者）
        - 您在第 5 页（位置 20-21）的笔记 | 添加于 2026年10月22日 09:31:00

        原文笔记。
        ==========
        Book (An Author)
        - Your Bookmark at Location 200 | Added on Thursday, October 22, 2026 09:32:00

        ==========
        Broken
        missing metadata
        ==========
        Incomplete
        """
        let parsed = try parser.parse(Data(source.utf8))
        try check(parsed.clippings.count == 3, "CLP-01 English and Chinese records and empty bookmark")
        try check(parsed.clippings[1].location == "20-21" && parsed.clippings[1].page == "5", "CLP-01 location and page remain separate")
        try check(parsed.diagnostics.count == 2, "CLP-03 damaged and incomplete records retained")
        let utf16 = Data([0xff, 0xfe]) + source.data(using: .utf16LittleEndian)!
        try check(try parser.parse(utf16).clippings.count == 3, "CLP-01 BOM UTF-16")
        try await rejects("Uncertain encoding rejected") { _ = try parser.parse(Data([0xff, 0x00, 0x90])) }
        let store = try SQLiteLibrary(root: root.appendingPathComponent("library"))
        let report = try await store.importSnapshot(Data(source.utf8), parsed: parsed)
        try check(report.added == 3 && report.unparsed == 2, "CLP-03 report counts")
        let repeated = try await store.importSnapshot(Data(source.utf8), parsed: parsed)
        try check(repeated.added == 0 && repeated.existing == 3, "CLP-02 identical snapshot reused")
        var items = try await store.annotations()
        let first = items[0]
        try await store.updateOverride(id: first.id, value: .init(body: "Local correction", tags: ["reading"]))
        let incremental = source.replacingOccurrences(of: "Incomplete", with: "") + "\nBook (An Author)\n- Your Highlight at Location 300 | Added on Friday\n\nA *special* <line> & text.\n==========\n"
        let incrementalReport = try await store.importSnapshot(Data(incremental.utf8), parsed: parser.parse(Data(incremental.utf8)))
        try check(incrementalReport.added == 1 && incrementalReport.existing == 3, "CLP-02 incremental deduplication preserves different location")
        items = try await store.annotations()
        try check(items[0].body == "Local correction" && items[0].original.body.contains("special"), "CLP-04 overrides survive reimport; original immutable")
        let renderer = StandardMarkdownRenderer()
        let rendered = renderer.render([first], includeHidden: false, includeTags: true)
        try check(rendered.contains("> A \\*special\\* &lt;line\\> &amp; text\\.") && rendered.contains("\n> Another line\\."), "MD-01 Markdown escaping and multiline quotations")
        let exportRoot = root.appendingPathComponent("exports"); try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        let exported = try await store.publishMarkdown(rendered, bookID: first.bookID, directory: exportRoot, title: "A/B: Book")
        let updated = try await store.publishMarkdown("New generated text", bookID: first.bookID, directory: exportRoot, title: "A/B: Book")
        try check(exported == updated, "MD-01 unmodified export updated in place")
        try Data("User edits".utf8).write(to: exported)
        let conflict = try await store.publishMarkdown(rendered, bookID: first.bookID, directory: exportRoot, title: "A/B: Book")
        try check(conflict != exported && (try String(contentsOf: exported)) == "User edits", "MD-01 edited export preserved with conflict copy")
        let dp = DictionaryParser()
        let csv = "headword,definition,partOfSpeech,example,forms\nrun,\"Move, quickly\",verb,\"Line one\nLine two\",runs|ran\nrun,Operate,verb,,running\n"
        let package = try dp.parseCSV(Data(csv.utf8), name: "Test", source: "en", target: "en")
        try check(package.entries.count == 2 && package.entries[0].example?.contains("\n") == true, "DICT-01 CSV quoting and multiline fields")
        try await store.install(package)
        let senses = try await store.lookup("RUN"); let forms = try await store.lookup("ran")
        try check(senses.count == 2 && forms.count == 1, "DICT-01 normalized multiple senses and inflection lookup")
        var entry = package.entries[0]; entry.definition = "Edited definition"
        try await store.edit(packageID: package.id, entry: entry, hidden: false)
        var newer = package; newer.version = "2"; newer.entries[0].definition = "Upstream update"
        try await store.install(newer)
        let edited = try await store.lookup("ran")
        try check(edited.first?.entry.definition == "Edited definition", "DICT-02 override survives stable-ID update")
        try await rejects("DICT-01 malformed CSV fails with no installation") { _ = try dp.parseCSV(Data("headword,definition\nword,\"unclosed".utf8), name: "Test", source: "en", target: "en") }
        newer.entries.removeAll { $0.id == entry.id }
        try await store.install(newer)
        let orphaned = try await store.lookup("ran")
        let summaries = try await store.installedDictionaries()
        try check(orphaned.first?.entry.definition == "Edited definition" && summaries.first?.conflicts == 1, "DICT-02 upstream deletion preserves local edit as explicit conflict")
        let merged = try await store.mergedPackage(id: package.id)
        try check(merged.entries.contains(where: { $0.id == entry.id && $0.definition == "Edited definition" }), "DICT-02 merged export retains orphaned local edits")
        let cancelledExport = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await store.publishMarkdown("Cancelled replacement", bookID: first.bookID, directory: exportRoot, title: "A/B: Book")
        }
        cancelledExport.cancel()
        try await rejects("MD-02 cancelled export preserves existing Markdown") { _ = try await cancelledExport.value }
        try check((try String(contentsOf: exported)) == "User edits", "MD-02 cancellation leaves user content intact")
        let downloadData = try JSONEncoder().encode(newer)
        let catalogItem = CatalogPackage(id: newer.id, version: newer.version, sourceLanguage: "en", targetLanguage: "en", size: Int64(downloadData.count), sha256: String(repeating: "0", count: 64), url: URL(string: "https://catalog.invalid/package.json")!, source: "Synthetic tests", license: "User-provided content")
        let downloader = try DictionaryDownloadService(catalog: [catalogItem], transport: SyntheticDownload(data: downloadData), parser: dp, repository: store)
        let downloads = root.appendingPathComponent("downloads")
        try await rejects("DICT-03 hash failure does not install package") { try await downloader.download(id: newer.id, workDirectory: downloads) }
        let remainingDownloads = try FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil)
        let stillInstalled = try await store.lookup("ran")
        try check(remainingDownloads.isEmpty && stillInstalled.first?.entry.definition == "Edited definition", "DICT-03 failed download removes only owned temporary data and keeps installed edits")
        let deviceRoot = root.appendingPathComponent("device"); try FileManager.default.createDirectory(at: deviceRoot, withIntermediateDirectories: true)
        let device = try MountedVolumeTransport(root: deviceRoot, deviceID: UUID(), verifiedWritable: true)
        let input = root.appendingPathComponent("input.txt"); try Data("Synthetic test book".utf8).write(to: input)
        let uploaded = try await device.upload(input, into: device.rootReference, name: "test.txt")
        let files = try await device.list(in: device.rootReference)
        try check(files.count == 1 && files[0].size == 19, "BOOK-01 virtual mounted transfer and verification")
        try await rejects("BOOK-04 no silent overwrite") { _ = try await device.upload(input, into: device.rootReference, name: "test.txt") }
        try await rejects("Device path traversal rejected") { _ = try await device.upload(input, into: device.rootReference, name: "../escape") }
        try FileManager.default.createSymbolicLink(at: deviceRoot.appendingPathComponent("unsafe"), withDestinationURL: root)
        let safeFiles = try await device.list(in: device.rootReference)
        try check(safeFiles.count == 1, "Unsafe symbolic links excluded")
        let library = DeviceLibraryService(transport: device, verifiedFormats: ["txt"], writable: true)
        let transferPlan = try await library.planTransfer(source: input, detectedFormat: "txt", destination: device.rootReference, filename: "planned.txt")
        let plannedFile = try await library.executeTransfer(transferPlan, workDirectory: root.appendingPathComponent("jobs"))
        let plannedList = try await device.list(in: device.rootReference)
        try check(plannedList.contains(where: { $0.id == plannedFile }), "BOOK-01 planned transfer returns actual verified object")
        try await rejects("BOOK-04 execution rechecks conflicts") { _ = try await library.executeTransfer(transferPlan, workDirectory: root.appendingPathComponent("jobs")) }
        let deletion = try await library.planDeletion(files: [(plannedFile, device.rootReference, "planned.txt")], backupDirectory: root.appendingPathComponent("backups"), workDirectory: root.appendingPathComponent("jobs"))
        try await library.executeDeletion(deletion, workDirectory: root.appendingPathComponent("jobs"))
        let afterDeletion = try await device.list(in: device.rootReference)
        let backup = root.appendingPathComponent("backups/" + deletion.id.uuidString + "/0-planned.txt")
        try check(afterDeletion.contains(where: { $0.name == "test.txt" }) && !afterDeletion.contains(where: { $0.name == "planned.txt" }) && (try Data(contentsOf: backup)) == (try Data(contentsOf: input)), "BOOK-05 explicit deletion preserves unrelated file and verified backup")
        let staleDeletion = try await library.planDeletion(files: [(uploaded, device.rootReference, "test.txt")], backupDirectory: root.appendingPathComponent("backups"), workDirectory: root.appendingPathComponent("jobs"))
        try Data("Changed device file".utf8).write(to: deviceRoot.appendingPathComponent("test.txt"))
        try await rejects("BOOK-05 deletion refuses changed file") { try await library.executeDeletion(staleDeletion, workDirectory: root.appendingPathComponent("jobs")) }
        await device.disconnect()
        try await rejects("DEV-04 old references expire after disconnect") { try await device.delete(uploaded) }
        let readOnly = try MountedVolumeTransport(root: deviceRoot, deviceID: UUID())
        try await rejects("DEV-03 writes disabled by default") { _ = try await readOnly.upload(input, into: readOnly.rootReference, name: "blocked.txt") }
        let planner = ImportPlanner()
        try check(planner.plan(detectedFormat: "epub", structurallyValid: true, protected: false, verifiedDeviceFormats: ["azw3"], converterInputs: ["epub"]) == .conversionRequired(input: "epub", output: "azw3"), "BOOK-02 conversion plan requires verified target")
        try check(planner.plan(detectedFormat: "txt", structurallyValid: true, protected: false, verifiedDeviceFormats: ["txt"], converterInputs: []) == .directTransfer(format: "txt"), "BOOK-03 direct transfer planning independent of converter")
        let coordinator = JobCoordinator(repository: store)
        let request = UUID()
        try await coordinator.submit(requestID: request, kind: "Synthetic job") {}
        try await coordinator.submit(requestID: request, kind: "Duplicate job") {}
        await coordinator.cancelAllAndWait()
        let jobs = try await store.jobs()
        try check(jobs.count == 1, "JOB-01 repeated request creates one durable job")
        var interrupted = JobRecord(requestID: UUID(), kind: "Interrupted write", deviceID: UUID()); interrupted.state = .running
        try await store.saveJob(interrupted)
        let restarted = JobCoordinator(repository: store); try await restarted.recover()
        let recovered = try await store.jobs()
        try check(recovered.first(where: { $0.id == interrupted.id })?.state == .needsReconciliation, "JOB-01 interrupted device write is not replayed")
        if ProcessInfo.processInfo.environment["KINDLE_MARGIN_PERFORMANCE"] == "1" {
            let benchmarkStore = try SQLiteLibrary(root: root.appendingPathComponent("benchmark"))
            let large = DictionaryPackage(id: "synthetic-performance", name: "Synthetic performance dictionary", sourceLanguage: "en", targetLanguage: "en", license: "Synthetic test data", entries: (0..<100_000).map { .init(id: "entry-\($0)", headword: "word\($0)", definition: "Synthetic definition \($0)") })
            try await benchmarkStore.install(large)
            let start = ContinuousClock.now
            let result = try await benchmarkStore.lookup("word99999")
            let duration = start.duration(to: .now)
            try check(result.count == 1, "100,000-entry dictionary indexed exact lookup")
            print("PERFORMANCE: 100,000 entries; exact lookup \(duration); \(ProcessInfo.processInfo.operatingSystemVersionString); arm64")
        }
        if let executable = ProcessInfo.processInfo.environment["KINDLE_MARGIN_TEST_CONVERTER"] {
            let engine = CalibreConversionEngine()
            let identity = try await engine.validate(executable: URL(fileURLWithPath: executable))
            let synthetic = root.appendingPathComponent("synthetic.txt")
            try Data("Synthetic acceptance book.\n\nThis text was written only for the conversion test.".utf8).write(to: synthetic)
            let plan = try engine.plan(source: synthetic, converter: identity)
            let artifact = try await engine.execute(plan, cacheDirectory: root.appendingPathComponent("conversions"))
            try check(FileManager.default.fileExists(atPath: artifact.url.path), "BOOK-02 real local Calibre output passes AZW3 structural checks")
            try Data("Changed source".utf8).write(to: synthetic)
            try await rejects("BOOK-04 frozen conversion input detects source changes") { _ = try await engine.execute(plan, cacheDirectory: root.appendingPathComponent("conversions")) }
            if let epub = ProcessInfo.processInfo.environment["KINDLE_MARGIN_TEST_EPUB"] {
                let epubPlan = try engine.plan(source: URL(fileURLWithPath: epub), converter: identity)
                let epubArtifact = try await engine.execute(epubPlan, cacheDirectory: root.appendingPathComponent("conversions"))
                try check(FileManager.default.fileExists(atPath: epubArtifact.url.path), "BOOK-02 synthetic EPUB to AZW3 with local Calibre")
            }
        }
        try await extendedChecks(root: root)
        try await failureChecks(root: root)
        try await httpChecks(root: root)
        if ProcessInfo.processInfo.environment["KINDLE_MARGIN_UI_CHECKS"] == "1" { try await uiChecks(root: root) }
        print("All local acceptance checks passed. Physical-device and UI acceptance remain separate.")
    }
}
