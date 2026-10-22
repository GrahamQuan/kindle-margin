import AppKit
import Foundation
import KindleDomain

extension AppDelegate {
    func downloadDictionary() {
        guard let model, let downloads else { return }
        guard !catalog.isEmpty else { model.message = "No licensed download catalog is configured in this development build. Import a JSON or CSV dictionary locally. Catalog publication remains a release gate."; return }
        let alert = NSAlert(); alert.messageText = "Download dictionary"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 28))
        picker.addItems(withTitles: catalog.map { "\($0.id) · \($0.sourceLanguage) → \($0.targetLanguage) · \($0.size) bytes" })
        alert.accessoryView = picker; alert.addButton(withTitle: "Review"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let item = catalog[picker.indexOfSelectedItem]
        let confirmation = NSAlert(); confirmation.messageText = "Confirm download"
        confirmation.informativeText = "\(item.id) \(item.version)\nSource: \(item.source)\nLicense: \(item.license)\nSize: \(item.size) bytes\nInstalled entries retain local corrections during upgrades."
        confirmation.addButton(withTitle: "Download"); confirmation.addButton(withTitle: "Cancel")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }
        let directory = cacheRoot.appendingPathComponent("downloads")
        model.run { try await model.coordinator.submit(requestID: UUID(), kind: "Download dictionary") { try await downloads.download(id: item.id, workDirectory: directory) } }
    }
    func clearCache() {
        guard let model else { return }
        model.run {
            let jobs = try await model.coordinator.jobs()
            guard !jobs.contains(where: { [.queued, .preparing, .running, .verifying, .cancelling].contains($0.state) }) else { throw MarginError.unavailable("Wait for active tasks to finish before clearing the cache.") }
            for name in ["conversions", "downloads"] {
                let directory = self.cacheRoot.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            }
            model.message = "Conversion and download caches cleared. Library originals and backups are retained."
        }
    }
    func diagnostics() {
        guard let model else { return }
        model.run {
            let jobs = try await model.coordinator.jobs()
            let report = "Kindle Margin local diagnostics\nOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nArchitecture: arm64 initial target\nJobs: \(jobs.count)\nReconciliation required: \(jobs.filter { $0.state == .needsReconciliation }.count)\nDevices: \(model.device?.devices.count ?? 0)\nConverter configured: \(self.converter != nil)\nPhysical compatibility: unverified\n\nBook content, paths, USB serials, dictionary entries, and annotation text are excluded.\n"
            let alert = NSAlert(); alert.messageText = "Review diagnostics before export"; alert.informativeText = report
            alert.addButton(withTitle: "Save report"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let panel = NSSavePanel(); panel.nameFieldStringValue = "kindle-margin-diagnostics.txt"
            if panel.runModal() == .OK, let url = panel.url { try Data(report.utf8).write(to: url, options: .atomic) }
        }
    }
}
