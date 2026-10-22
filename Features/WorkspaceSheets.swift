import SwiftUI

extension WorkspaceView {
    @ViewBuilder func sheetContent(_ value: WorkspaceSheet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(sheetTitle(value)).font(.title2.bold()); Spacer(); if value != .dictionaryImport { Button("Close") { sheet = nil }.keyboardShortcut(.cancelAction) } }
            Divider()
            switch value {
            case .tools:
                ScrollView { tools }
                Button("Show in workspace when space permits") { state.collapsed.remove(state.page); model.collapsed = state.collapsed; model.persistPreferences(); sheet = nil }
            case .preview:
                ScrollView { Text(model.preview ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            case .diagnostics:
                ScrollView { LazyVStack(alignment: .leading, spacing: 16) { ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, item in Text("Record \(item.ordinal): \(item.reason)").bold(); Text(item.raw).textSelection(.enabled) } } }
            case .snapshots:
                ScrollView { VStack(alignment: .leading, spacing: 16) { ForEach(model.snapshots) { snapshot in
                    Text(String(snapshot.id.prefix(10)) + " · " + snapshot.encoding + " · Parser \(snapshot.parserVersion)")
                    HStack {
                        Button("Inspect original") { model.run { let text = try await model.service.snapshotText(snapshot.id); guard sheet == .snapshots else { return }; model.preview = text; presentSheet(.preview) } }
                        Button("Reparse") { model.run { let report = try await model.service.reparse(snapshot.id); model.message = "Added \(report.added), existing \(report.existing), unparsed \(report.unparsed). Local edits were retained." } }
                    }
                } } }
            case .export:
                ScrollView { VStack(alignment: .leading, spacing: 16) {
                if let item = selected {
                    Text(model.books.first { $0.id == item.bookID }?.title ?? item.original.description).font(.headline)
                    Text("Export includes all eligible saved annotations in this book, not just the selected excerpt.")
                    Toggle("Include hidden annotations", isOn: $model.exportHidden)
                    Toggle("Include local tags", isOn: $model.includeTags)
                    if model.annotations.contains(where: { $0.bookID == item.bookID && model.isChanged($0) }) {
                        Label("This book has unsaved corrections. Only saved content will be exported.", systemImage: "pencil.circle")
                        Button("Return to editing") { sheet = nil; state.editing = true; focus = .editor }
                    }
                    HStack {
                        Button("Preview Markdown") { model.run { let text = try await model.service.preview(bookID: item.bookID, includeHidden: model.exportHidden, includeTags: model.includeTags); guard sheet == .export, state.page == .annotations, selected?.id == item.id else { return }; model.preview = text; presentSheet(.preview) } }
                        Button("Choose export folder…") { sheet = nil; model.exportAction?(item.bookID) }.buttonStyle(PrimaryActionStyle())
                    }
                }
                } }
            case .dictionaryImport:
                DictionaryImportForm(model: model, dismiss: { sheet = nil })
            case .dictionaries:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Button("Download catalog…") { model.downloadCatalogAction?() }
                        ForEach(model.installedDictionaries) { dictionary in
                            Text(dictionary.name + " · " + dictionary.version).font(.headline)
                            if dictionary.conflicts > 0 { Label("\(dictionary.conflicts) unresolved edit conflicts", systemImage: "exclamationmark.triangle") }
                            HStack {
                                Button("Move first") { model.run { try await model.service.prioritize([dictionary.id] + model.installedDictionaries.map(\.id).filter { $0 != dictionary.id }) } }
                                Button("Manage edits") { model.run { model.managementDictionary = dictionary.id; model.changes = try await model.service.entryChanges(dictionary.id) } }
                                Menu("More") {
                                    Button("Remove (recoverable)") { model.run { try await model.service.removeDictionary(dictionary.id); state.results = []; state.entry = nil } }
                                    Button("Export merged JSON…") { model.exportDictionaryAction?(dictionary.id) }
                                }
                            }
                            Divider()
                        }
                        DictionaryManagementView(model: model)
                    }
                }
            }
        }.padding(24).frame(minWidth: 440, idealWidth: 540, maxWidth: 600, minHeight: 240, idealHeight: 380, maxHeight: 420)
    }
    func sheetTitle(_ value: WorkspaceSheet) -> String {
        switch value {
        case .tools: return "Contextual tools"
        case .preview: return "Content preview"
        case .diagnostics: return "Import diagnostics"
        case .export: return "Export book"
        case .dictionaryImport: return "Import dictionary"
        case .dictionaries: return "Installed dictionaries"
        case .snapshots: return "Original snapshots"
        }
    }
}
struct DictionaryImportForm: View {
    @Bindable var model: WorkspaceModel
    var dismiss: () -> Void
    @State private var name = "My Dictionary"
    @State private var source = "en"
    @State private var target = "en"
    @State private var confirmDiscard = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("JSON uses its own metadata. For CSV, enter the dictionary name and language codes before choosing the file.")
            Form {
                TextField("Dictionary name", text: $name)
                TextField("Source language", text: $source)
                TextField("Target language", text: $target)
            }
            HStack {
                Button("Cancel") { if name != "My Dictionary" || source != "en" || target != "en" { confirmDiscard = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose JSON or CSV…") { model.csvName = name; model.csvSource = source; model.csvTarget = target; dismiss(); model.importDictionaryAction?() }
                    .buttonStyle(PrimaryActionStyle()).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || source.isEmpty || target.isEmpty)
            }
        }.interactiveDismissDisabled()
        .confirmationDialog("Discard import details?", isPresented: $confirmDiscard, titleVisibility: .visible) { Button("Discard", role: .destructive, action: dismiss); Button("Keep editing", role: .cancel) {} }
    }
}
