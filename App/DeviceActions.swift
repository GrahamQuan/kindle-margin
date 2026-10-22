import AppKit
import Foundation
import KindleDomain
import KindleApplication
import KindleConversion

extension AppDelegate {
    func importDeviceFiles(dictionary: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = !dictionary
        panel.message = dictionary ? "Select an existing Kindle dictionary with language metadata and lookup indexes." : "Select books to inspect and plan before transfer."
        guard panel.runModal() == .OK else { return }; planDeviceFiles(panel.urls, dictionary: dictionary)
    }
    func planDeviceFiles(_ urls: [URL], dictionary: Bool) {
        guard let model, let device = model.device, let connection = device.connection, let directory = device.directory else { return }
        let directoryPath = device.path; let converter = converter; let conversion = conversion; let cache = cacheRoot
        model.run {
            guard connection.writable else { throw MarginError.unavailable(connection.info.explanation) }
            guard directoryPath.first?.lowercased() == "documents" else { throw MarginError.unavailable("Open the Kindle documents folder before importing. System directories and storage roots are not writable destinations.") }
            for source in urls {
                let inspection = try await Task.detached { try BookInspector().inspect(source) }.value
                guard !inspection.protected else { throw MarginError.unavailable("Protected content is unavailable; no DRM removal is performed.") }
                if dictionary, inspection.dictionaryIdentity == nil || inspection.dictionaryLanguages == nil { throw MarginError.invalidInput("Dictionary identity, source/target languages, or lookup indexes could not be confirmed. This file will not be installed as a dictionary.") }
                let decision = ImportPlanner().plan(detectedFormat: inspection.format, structurallyValid: true, protected: inspection.protected, verifiedDeviceFormats: connection.verifiedFormats, converterInputs: converter?.inputFormats ?? [])
                let requiresConversion: Bool
                switch decision { case .directTransfer: requiresConversion = false; case .conversionRequired: requiresConversion = true; case .unavailable(let reason): throw MarginError.unavailable(reason) }
                if dictionary && requiresConversion { throw MarginError.unavailable("Device dictionaries must already be compatible; conversion cannot create dictionary indexes.") }
                let outputName = source.deletingPathExtension().lastPathComponent + "." + (requiresConversion ? "azw3" : inspection.format)
                let listing = try await connection.transport.list(in: directory)
                let name = listing.contains(where: { $0.name.caseInsensitiveCompare(outputName) == .orderedSame }) ? source.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString.prefix(8) + "." + (requiresConversion ? "azw3" : inspection.format) : outputName
                let conversionPlan: ConversionPlan?
                let transferPlan: TransferPlan?
                if requiresConversion {
                    guard let converter else { throw MarginError.unavailable("Select and validate Calibre in Settings.") }
                    conversionPlan = try await Task.detached { try conversion.plan(source: source, converter: converter) }.value
                    transferPlan = nil
                } else {
                    conversionPlan = nil
                    transferPlan = try await device.workflow.planTransfer(connection: connection, source: source, format: inspection.format, directory: directory, name: name)
                }
                let alert = NSAlert(); alert.messageText = dictionary ? "Confirm dictionary installation" : "Confirm book import"
                alert.informativeText = "File: \(source.lastPathComponent)\nDevice: \(connection.info.name)\nDestination: \(name)\nFormat: \(requiresConversion ? "AZW3" : inspection.format.uppercased())\nConversion: \(requiresConversion ? "Local Calibre required" : "None")\nNaming conflicts use a new filename. Existing files are preserved."
                alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { continue }
                let plan: TransferPlan
                if let conversionPlan {
                    let artifact = try await model.coordinator.perform(requestID: UUID(), kind: "Convert book for device") { try await conversion.execute(conversionPlan, cacheDirectory: cache.appendingPathComponent("conversions")) }
                    plan = try await device.workflow.planTransfer(connection: connection, source: artifact.url, format: "azw3", directory: directory, name: name)
                } else if let transferPlan { plan = transferPlan }
                else { throw MarginError.invalidInput("No import plan available.") }
                try await device.workflow.transfer(connection: connection, plan: plan, directoryPath: directoryPath, requestID: plan.id)
                if dictionary { model.message = "Installation job queued. After its verified completion, choose this dictionary as the default for its source language in Kindle Settings. Device lookup still requires physical validation." }
            }
        }
    }
    func backupDeviceFile() {
        guard let model, let device = model.device, let connection = device.connection, let file = device.selected else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = file.name
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let workflow = device.workflow
        model.run {
            try await model.coordinator.perform(requestID: UUID(), kind: "Back up device file") { try await workflow.backup(connection: connection, file: file, destination: destination) }
            model.message = "Backup copied and verified."
        }
    }
    func deleteDeviceFile() {
        guard let model, let device = model.device, let connection = device.connection, let file = device.selected, let parent = device.directory else { return }
        let path = device.path; let backup = dataRoot.appendingPathComponent("backups")
        model.run {
            guard path.first?.lowercased() == "documents" else { throw MarginError.unavailable("Only explicitly selected user files under documents can be deleted. System directories are protected.") }
            guard !file.isDirectory else { throw MarginError.invalidInput("Open folders and select explicit files. Broad recursive deletion is disabled.") }
            let discovered = try await device.workflow.deletionScope(connection: connection, main: file, parent: parent)
            var files = discovered.map { (file: $0.file, parent: $0.parent, name: $0.name) }
            var paths = discovered.map(\.relativeName)
            if files.count > 1 {
                let scope = NSAlert(); scope.messageText = "Review associated files"
                scope.informativeText = "An exact matching .sdr folder was found. Confirm whether to include these files. Empty folders are retained.\n\n" + paths.joined(separator: "\n")
                scope.addButton(withTitle: "Include listed files"); scope.addButton(withTitle: "Main file only"); scope.addButton(withTitle: "Cancel")
                let choice = scope.runModal(); if choice == .alertThirdButtonReturn { return }
                if choice == .alertSecondButtonReturn { files = [files[0]]; paths = [paths[0]] }
            }
            let plan = try await device.workflow.planDeletion(connection: connection, files: files, backupDirectory: backup)
            let alert = NSAlert(); alert.messageText = "Confirm deletion plan"
            alert.informativeText = "Target: \(connection.info.name)\nEvery listed file has been read and hashed. Backup is enabled by default; explicitly disabling it makes deletion unrecoverable from this app.\n\n" + paths.joined(separator: "\n")
            let backupChoice = NSButton(checkboxWithTitle: "Keep a verified local backup (recommended)", target: nil, action: nil); backupChoice.state = .on
            alert.accessoryView = backupChoice
            alert.addButton(withTitle: "Delete listed files"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let confirmed = backupChoice.state == .on ? plan : plan.withoutBackup()
            try await device.workflow.delete(connection: connection, plan: confirmed, directoryPath: path, requestID: confirmed.id, relativeNames: paths)
        }
    }
    func importDeviceClippings() {
        guard let model, let device = model.device, let connection = device.connection else { return }
        let temporary = cacheRoot.appendingPathComponent("jobs/" + UUID().uuidString)
        let service = model.service
        model.run {
            let report = try await model.coordinator.perform(requestID: UUID(), kind: "Import device annotations") {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let root = connection.roots.first?.id else { throw MarginError.staleSession }
            let files = try await connection.transport.list(in: root)
            var clipping = files.first { $0.name.caseInsensitiveCompare("My Clippings.txt") == .orderedSame }
            if clipping == nil, let documents = files.first(where: { $0.isDirectory && $0.name.caseInsensitiveCompare("documents") == .orderedSame }) {
                clipping = try await connection.transport.list(in: documents.id).first { $0.name.caseInsensitiveCompare("My Clippings.txt") == .orderedSame }
            }
            guard let clipping else { throw MarginError.unavailable("My Clippings.txt was not found in accessible storage. Use manual import to select a copy.") }
            let local = temporary.appendingPathComponent("My Clippings.txt"); try await connection.transport.download(clipping.id, to: local)
            return try await service.importClippings(url: local)
            }
            model.message = "Added \(report.added), existing \(report.existing), unparsed \(report.unparsed)."
        }
    }
    func reconcile(_ job: JobRecord) {
        guard let model, let device = model.device, let connection = device.connection else { model?.message = "Connect the original device before reconciliation."; return }
        model.run { model.message = try await device.workflow.reconcile(job: job, connection: connection) }
    }
    func retry(_ job: JobRecord) {
        guard let model else { return }
        if job.deviceID != nil { model.page = .library; model.message = "Rescan the device and confirm a new plan. Previous write confirmations are never replayed." }
        else if job.kind == "Download dictionary" { downloadDictionary() }
        else if job.kind == "Import device annotations" { importDeviceClippings() }
        else if job.kind == "Back up device file" { model.page = .library; model.message = "Select the original device file and choose Backup to confirm a new destination." }
        else if job.kind.contains("dictionary") { importFile(dictionary: true) }
        else if job.kind.contains("annotation") { importFile(dictionary: false) }
        else if job.kind.contains("Convert") { convertLocal() }
    }
}
