import AppKit
import CoreGraphics
import SwiftUI
import Features
import KindleApplication
import KindleDomain
import KindlePersistence
import KindleClippings
import KindleDictionary

@MainActor func uiChecks(root: URL) async throws {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    let store = try SQLiteLibrary(root: root.appendingPathComponent("ui-library"))
    let service = LibraryService(repository: store, parser: SnapshotParser(), renderer: StandardMarkdownRenderer(), dictionaryParser: DictionaryParser(), dictionaries: store)
    let coordinator = JobCoordinator(repository: store)
    let model = WorkspaceModel(service: service, coordinator: coordinator)
    let presentation = WorkspacePresentation()
    let fake = FakeMTP(); let provider = UIFixtureProvider(connections: [fake.connection(), FakeMTP().connection()])
    let device = DeviceWorkspaceModel(provider: provider, workflow: DeviceWorkflow(coordinator: coordinator, workDirectory: root.appendingPathComponent("ui-jobs")))
    model.device = device; await device.refreshDevices(); await device.connect()
    let deviceInput = root.appendingPathComponent("ui-device.txt"); try Data("Synthetic device file".utf8).write(to: deviceInput)
    _ = try await fake.upload(deviceInput, into: fake.root, name: "Synthetic Book.txt")
    try await device.list(); device.selection = device.entries.first?.id
    let target = device.connection?.info.id
    device.selectDevice(device.devices.last?.id)
    try check(device.selection == nil && device.connection == nil && target != nil, "UI-06 device selection clears stale actions")
    device.selectDevice(fake.root.deviceID); await device.connect(); device.selection = device.entries.first?.id
    var recoveryJob = JobRecord(requestID: UUID(), kind: "Upload", deviceID: UUID())
    recoveryJob.state = .needsReconciliation
    recoveryJob.plan = try JSONEncoder().encode(DeviceJournal(connection: fake.connection(), operation: "Upload", directory: ["documents"], names: ["Synthetic.txt"], hashes: [], backupDirectory: nil))
    device.jobs = [recoveryJob]
    try check(device.blockedWrites, "UI-06 reliable device identity blocks unresolved writes after session ID changes")
    recoveryJob.state = .completed; device.jobs = [recoveryJob]
    try check(!device.blockedWrites, "UI-06 completed reconciliation releases device write guard")
    device.jobs = []
    let package = DictionaryPackage(id: "ui-dictionary", name: "Synthetic Dictionary", sourceLanguage: "en", targetLanguage: "en", license: "Synthetic", entries: [.init(id: "word", headword: "margin", definition: "A space beside the main text.", forms: ["margins"])])
    try await store.install(package)
    model.results = try await service.lookup("margin"); model.selectedEntry = model.results.first?.id
    let source = (0..<10_000).map { "Synthetic Book\n- Your Highlight at Location \($0) | Added on Thursday, October 22, 2026 09:30:00\n\nSynthetic annotation \($0).\n==========\n" }.joined()
    let file = root.appendingPathComponent("ui-clippings.txt"); try Data(source.utf8).write(to: file)
    _ = try await service.importClippings(url: file); await model.refresh()
    let sample = model.annotations[0]
    model.drafts[sample.id] = sample.body
    try check(!model.hasDrafts, "RUI-A12 unchanged editor is not a dirty draft")
    model.drafts[sample.id] = "A saved local correction"
    model.tagDrafts[sample.id] = "reading, synthetic"
    try check(model.hasDrafts, "RUI-A04 changed text and tags require close protection")
    try await model.saveDraft(sample)
    try check(!model.hasDrafts && model.annotations.first(where: { $0.id == sample.id })?.body == "A saved local correction", "RUI-A12 successful save persists and clears only submitted drafts")
    var missing = sample; missing.original.id = UUID()
    model.drafts[missing.id] = "Retain me after failure"
    do { try await model.saveDraft(missing); throw CheckFailure(message: "Missing annotation save unexpectedly succeeded") }
    catch is CheckFailure { throw CheckFailure(message: "Missing annotation save unexpectedly succeeded") }
    catch { try check(model.drafts[missing.id] == "Retain me after failure" && model.saving.isEmpty, "RUI-A03 failed save retains text and releases save lock") }
    model.drafts[missing.id] = nil
    model.showHidden = true; model.exportHidden = false
    try check(!model.exportHidden, "RUI-A10 browsing hidden items does not enable export inclusion")
    model.exportHidden = true; model.showHidden = false
    try check(!model.showHidden, "RUI-A10 export inclusion does not change collection visibility")
    model.exportHidden = false
    let otherPresentation = WorkspacePresentation()
    presentation.page = .annotations; otherPresentation.page = .dictionaries
    presentation.selection = sample.id; otherPresentation.selection = nil
    try check(presentation.page != otherPresentation.page && otherPresentation.selection == nil, "RUI-A14 per-window navigation and selection are independent")
    if let entry = model.results.first {
        model.entrySources[entry.id] = entry; model.entryDrafts[entry.id] = "Updated synthetic definition"
        try await model.saveEntry(entry)
        let savedEntries = try await service.lookup("margin")
        try check(model.entryDrafts[entry.id] == nil && savedEntries.first?.entry.definition == "Updated synthetic definition", "RUI-A08 dictionary save persists and clears submitted draft")
        let dictionaryWindow = WorkspacePresentation()
        dictionaryWindow.results = [entry]
        dictionaryWindow.entrySelection = entry.id
        try check(dictionaryWindow.entry == nil, "RUI-A11 selecting a dictionary result does not open it")
        dictionaryWindow.openEntry(entry, editing: false)
        dictionaryWindow.applySavedDefinitions(model.entrySavedValues, edited: model.entrySavedEdits)
        try check(dictionaryWindow.entry?.entry.definition == "Updated synthetic definition" && dictionaryWindow.results.first?.entry.definition == "Updated synthetic definition", "RUI-A14 saved dictionary text updates detail and cached results")
        try await model.restoreEntry(entry)
        dictionaryWindow.applySavedDefinitions(model.entrySavedValues, edited: model.entrySavedEdits)
        try check(dictionaryWindow.entry?.entry.definition == entry.entry.definition && dictionaryWindow.entry?.edited == false, "RUI-A08 restore replaces cached correction with original definition")
        try await dictionaryDraftChecks(store: store, coordinator: coordinator, entry: entry)

    }
    let first = model.annotations[0]; model.selection = first.id; model.drafts[first.id] = "Unsaved correction"
    let filterStart = ContinuousClock.now; model.search = "9999"; let filtered = model.filtered
    try check(filtered.count == 1 && filterStart.duration(to: .now) < .milliseconds(100), "UI-05 10,000 annotation filter remains under 100 ms")
    model.search = ""; model.page = .settings
    try check(!model.hasTools, "UI-02 settings has no stale annotation tools")
    model.page = .annotations
    try check(model.hasTools && model.drafts[first.id] == "Unsaved correction", "UI-03 page changes preserve selected annotation and draft")
    model.collapsed.insert(.annotations); model.persistPreferences()
    try await Task.sleep(for: .milliseconds(150))
    let second = WorkspaceModel(service: service, coordinator: coordinator); await second.loadPreferences()
    try check(second.collapsed.contains(.annotations), "UI-03 contextual collapse survives model recreation")
    model.collapsed = []
    let window = NSWindow(contentRect: NSRect(x: 40,y: 40,width: 1280,height: 800), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.title = "Kindle Margin — Synthetic UI checks"
    let hosting = NSHostingView(rootView: AnyView(WorkspaceView(model: model, presentation: presentation))); window.contentView = hosting
    window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
    defer { window.orderOut(nil); window.close() }
    try await Task.sleep(for: .milliseconds(300))
    model.collapsed = []
    let scrollViews = descendants(hosting).compactMap { $0 as? NSScrollView }
    guard let list = scrollViews.first(where: { ($0.documentView?.frame.height ?? 0) > 10_000 }), let document = list.documentView else { throw CheckFailure(message: "Native 10,000-row scroll target missing") }
    do {
        hosting.layoutSubtreeIfNeeded()
        list.contentView.scroll(to: NSPoint(x: 0,y: 400)); list.reflectScrolledClipView(list.contentView); hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let start = ContinuousClock.now
        list.contentView.scroll(to: NSPoint(x: 0,y: max(0,document.frame.height - 800))); list.reflectScrolledClipView(list.contentView); hosting.layoutSubtreeIfNeeded()
        let elapsed = start.duration(to: .now)
        print("PERFORMANCE: native 10,000-row scroll layout \(elapsed)")
        try check(elapsed < .milliseconds(200), "UI-05 native 10,000-row list scroll layout under 200 ms")
        list.contentView.scroll(to: NSPoint(x: 0, y: 400)); list.reflectScrolledClipView(list.contentView)
        try await Task.sleep(for: .milliseconds(200))
        let rememberedOffset = list.contentView.bounds.origin.y
        presentation.page = .settings
        try await Task.sleep(for: .milliseconds(200))
        presentation.page = .annotations
        try await Task.sleep(for: .milliseconds(300))
        guard let restoredList = descendants(hosting).compactMap({ $0 as? NSScrollView }).first(where: { ($0.documentView?.frame.height ?? 0) > 10_000 }) else { throw CheckFailure(message: "Restored annotation list missing") }
        for _ in 0..<40 {
            if abs(restoredList.contentView.bounds.origin.y - rememberedOffset) < 2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try check(rememberedOffset > 0 && abs(restoredList.contentView.bounds.origin.y - rememberedOffset) < 2, "RUI-A03 native scroll position survives page changes")
        restoredList.contentView.scroll(to: .zero); restoredList.reflectScrolledClipView(restoredList.contentView)
    }
    let screenshots = URL(fileURLWithPath: ProcessInfo.processInfo.environment["KINDLE_MARGIN_UI_OUTPUT"] ?? "/tmp/kindle-margin-ui-evidence")
    try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
    presentation.collapsed = Set(WorkspacePage.allCases)
    for dark in [false,true] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        for width in [1440,900,660] {
            window.setContentSize(NSSize(width: width,height: width == 660 ? 480 : width == 900 ? 640 : 900))
            for page in WorkspacePage.allCases {
                presentation.page = page
                try await Task.sleep(for: .milliseconds(200))
                hosting.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                guard let capture = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { throw CheckFailure(message: "Cannot capture native window") }
                let rep = NSBitmapImageRep(cgImage: capture)
                guard let png = rep.representation(using: .png, properties: [:]) else { throw CheckFailure(message: "No UI image") }
                try png.write(to: screenshots.appendingPathComponent("\(page.rawValue)-\(width)-\(dark ? "dark" : "light").png"))
                window.selectNextKeyView(nil)
                try check(window.firstResponder is NSView, "UI-05 native key-view navigation: \(page.rawValue), \(width), \(dark ? "dark" : "light")")
            }
        }
    }
    window.setContentSize(NSSize(width: 1120, height: 760))
    for dark in [false, true] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        presentation.page = .annotations; presentation.selection = first.id; presentation.opened = first.id
        for editing in [false, true] {
            presentation.editing = editing
            try await Task.sleep(for: .milliseconds(250))
            try captureNative(window, to: screenshots.appendingPathComponent("Annotation-\(editing ? "editing" : "reading")-\(dark ? "dark" : "light").png"))
        }
        presentation.opened = nil; presentation.search = "No such synthetic sentence"
        try await Task.sleep(for: .milliseconds(250))
        try captureNative(window, to: screenshots.appendingPathComponent("Annotation-no-results-\(dark ? "dark" : "light").png"))
        presentation.search = ""
        presentation.page = .dictionaries; presentation.query = "margin"; presentation.submittedQuery = "margin"; presentation.results = try await service.lookup("margin"); presentation.lookupState = "loaded"
        try await Task.sleep(for: .milliseconds(250))
        try captureNative(window, to: screenshots.appendingPathComponent("Dictionary-results-\(dark ? "dark" : "light").png"))
        presentation.entry = presentation.results.first
        try await Task.sleep(for: .milliseconds(250))
        try captureNative(window, to: screenshots.appendingPathComponent("Dictionary-reading-\(dark ? "dark" : "light").png"))
        presentation.entry = nil
    }
    let originalItems = model.annotations
    presentation.page = .annotations; presentation.opened = nil; presentation.selection = nil; presentation.search = ""
    model.annotations = []
    window.appearance = NSAppearance(named: .aqua)
    window.setContentSize(NSSize(width: 900, height: 640))
    try await Task.sleep(for: .milliseconds(250))
    try captureNative(window, to: screenshots.appendingPathComponent("Annotation-empty-light.png"))
    model.annotations = originalItems
    var longItem = originalItems[0]
    longItem.original.description = "A long mixed-script reading passage — 阅读笔记与原文保留 — Synthetic fixture"
    longItem.override.body = String(repeating: "Reading slowly leaves room for thought. 原文中的标点、语言和段落应该被完整保留。\n\n", count: 30)
    model.annotations[0] = longItem
    presentation.opened = longItem.id; presentation.selection = longItem.id; presentation.editing = false
    for dark in [false, true] {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 660, height: 480))
        try await Task.sleep(for: .milliseconds(250))
        try captureNative(window, to: screenshots.appendingPathComponent("Annotation-long-compact-\(dark ? "dark" : "light").png"))
    }
    window.setContentSize(NSSize(width: 1440, height: 900)); presentation.collapsed.remove(.annotations)
    try await Task.sleep(for: .milliseconds(250))
    try captureNative(window, to: screenshots.appendingPathComponent("Annotation-tools-dark.png"))
    window.appearance = NSAppearance(named: .accessibilityHighContrastDarkAqua)
    window.setContentSize(NSSize(width: 900, height: 640))
    try await Task.sleep(for: .milliseconds(300))
    try captureNative(window, to: screenshots.appendingPathComponent("Annotation-accessibility-dark.png"))
    model.annotations = originalItems
    model.selection = nil; model.page = .annotations
    try check(!model.hasTools, "UI-02 clearing selection removes tools")
    print("UI evidence: \(screenshots.path); 10,000 synthetic annotations; \(ProcessInfo.processInfo.operatingSystemVersionString)")
}

@MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
actor UIFixtureProvider: DeviceProviding {
    let connections: [DeviceConnection]
    init(connections: [DeviceConnection]) { self.connections = connections }
    func refresh() -> [DeviceInfo] { connections.map(\.info) }
    func connect(_ id: UUID) throws -> DeviceConnection { guard let value = connections.first(where: { $0.info.id == id }) else { throw MarginError.staleSession }; return value }
    func disconnect(_ id: UUID) {}
}

@MainActor private func captureNative(_ window: NSWindow, to url: URL) throws {
    window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
    guard let capture = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]), let png = NSBitmapImageRep(cgImage: capture).representation(using: .png, properties: [:]) else { throw CheckFailure(message: "Native capture failed") }
    try png.write(to: url)
}
