import SwiftUI
import KindleDomain

extension WorkspaceView {
    var dictionaryPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle("Search definitions", isOn: $state.definitions)
                Spacer()
                Button("Installed dictionaries") { presentSheet(.dictionaries, returningTo: .dictionaries) }.focused($focus, equals: .dictionaries)
            }
            if let entry = state.entry {
                HStack {
                    Button("Back to results") { state.entry = nil; state.entryEditing = false; focus = .dictionaryResults }.focused($focus, equals: .back)
                    Spacer()
                    if state.entryEditing {
                        Button("Cancel") { cancelEntry(entry) }.keyboardShortcut(.cancelAction)
                        Button("Save definition", action: saveActive).buttonStyle(PrimaryActionStyle()).disabled(!canSave)
                    } else {
                        Button("Edit") { model.entrySources[entry.id] = entry; state.entryEditing = true; focus = .editor }.buttonStyle(PrimaryActionStyle())
                        Menu("More") {
                            Button("Restore original entry…") {
                                confirmation = .init(title: "Restore original entry?", message: "The saved local definition and unsaved draft will be removed.", actionTitle: "Restore original", action: {
                                    model.run { try await model.restoreEntry(entry); state.entry = nil; lookup() }
                                })
                            }
                            Button("Hide entry") { model.run { try await model.service.editEntry(entry, definition: entry.entry.definition, hidden: true); state.entry = nil; lookup() } }
                        }.fixedSize()
                    }
                }
                Text(entry.entry.headword).font(.largeTitle.bold())
                Text(entry.packageName).foregroundStyle(.secondary)
                if state.entryEditing {
                    Text("Changes stay local. The original definition is preserved.").foregroundStyle(.secondary)
                    if (model.entryDrafts[entry.id] ?? entry.entry.definition) != entry.entry.definition { Label("Unsaved changes", systemImage: "pencil.circle") }
                    TextEditor(text: Binding(get: { model.entryDrafts[entry.id] ?? entry.entry.definition }, set: { model.entrySources[entry.id] = entry; model.entryDrafts[entry.id] = $0 }))
                        .font(.title3).focused($focus, equals: .editor).accessibilityLabel("Dictionary definition").disabled(model.saving.contains(entry.id)).onAppear { focus = .editor }
                } else {
                    ScrollView { Text(entry.entry.definition).font(.title3).textSelection(.enabled).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading) }
                }
            } else if model.installedDictionaries.isEmpty {
                ContentUnavailableView { Label("Your offline dictionary", systemImage: "character.book.closed") } description: { Text("Import a JSON or CSV dictionary to start looking up words.") } actions: { Button("Import dictionary…") { presentSheet(.dictionaryImport, returningTo: .emptyDictionaryImport) }.focused($focus, equals: .emptyDictionaryImport) }
            } else if state.lookupState == "loading" {
                ProgressView("Looking up…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = state.lookupError {
                ContentUnavailableView { Label("Lookup failed", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Try again", action: lookup) }
            } else if state.lookupState == "idle" {
                ContentUnavailableView("Find the right words", systemImage: "magnifyingglass", description: Text("Search your installed dictionaries. Lookup works offline."))
            } else if state.results.isEmpty {
                ContentUnavailableView("No matching definitions", systemImage: "magnifyingglass", description: Text("Try a different word or search definitions."))
            } else {
                List(state.results, selection: $state.entrySelection) { result in
                    Button {
                        openEntry(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(result.entry.headword).font(.headline)
                            Text(result.entry.definition).lineLimit(3)
                            Text(result.packageName + (result.edited ? " · Edited locally" : "") + ((model.entryDrafts[result.id] ?? result.entry.definition) != result.entry.definition ? " · Unsaved changes" : "")).foregroundStyle(.secondary)
                        }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).tag(result.id).accessibilityElement(children: .combine)
                }.focused($focus, equals: .dictionaryResults)
                    .onKeyPress(.return) {
                        guard let result = state.results.first(where: { $0.id == state.entrySelection }) else { return .ignored }
                        openEntry(result); return .handled
                    }.scrollContentBackground(.hidden).background(ScrollRestoration(memory: state.dictionaryScroll))
            }
        }.padding(24)
        .onChange(of: model.entrySavedValues, initial: true) { _, values in state.applySavedDefinitions(values, edited: model.entrySavedEdits) }
        .onChange(of: model.entrySavedEdits) { _, values in state.applySavedDefinitions(model.entrySavedValues, edited: values) }
        .onChange(of: state.definitions) { _, _ in lookupTask?.cancel(); state.results = []; state.lookupState = "idle"; state.entry = nil }
        .onChange(of: state.query) { _, _ in guard state.submittedQuery != state.query else { return }; lookupTask?.cancel(); state.results = []; state.lookupState = "idle"; state.lookupError = nil; state.entry = nil }
    }
    func openEntry(_ result: LookupResult) {
        var current = result
        if let text = model.entrySavedValues[result.id] { current.entry.definition = text; current.edited = model.entrySavedEdits[result.id] ?? current.edited }
        let editing = (model.entryDrafts[result.id] ?? current.entry.definition) != current.entry.definition
        state.openEntry(current, editing: editing)
        if editing { model.entrySources[result.id] = current }
        focus = editing ? .editor : .back
    }
    func lookup() {
        lookupTask?.cancel(); let query = state.query; state.submittedQuery = query; let definitions = state.definitions
        state.entry = nil; state.results = []; state.lookupError = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { state.lookupState = "idle"; return }
        state.lookupState = "loading"
        lookupTask = Task {
            do {
                let values = try await definitions ? model.service.searchEntries(query) : model.service.lookup(query)
                guard !Task.isCancelled, state.query == query, state.definitions == definitions else { return }
                state.results = values; state.lookupState = "loaded"
            } catch { if !Task.isCancelled { state.lookupError = error.localizedDescription; state.lookupState = "failed" } }
        }
    }
    func cancelEntry(_ entry: LookupResult) {
        let discard = { model.entryDrafts[entry.id] = nil; model.entrySources[entry.id] = nil; state.entryEditing = false; focus = .back }
        if (model.entryDrafts[entry.id] ?? entry.entry.definition) != entry.entry.definition {
            confirmation = .init(title: "Discard unsaved definition?", message: "The saved definition is preserved.", actionTitle: "Discard changes", action: discard)
        } else { discard() }
    }
    var tasksPage: some View {
        List(selection: $state.job) {
            if model.jobs.isEmpty { ContentUnavailableView("No tasks yet", systemImage: "checklist", description: Text("Import a clippings file or dictionary to get started.")) }
            ForEach(model.jobs.sorted { active($0) && !active($1) }) { job in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(job.kind).font(.headline); Spacer(); Label(job.state.rawValue, systemImage: active(job) ? "clock" : job.state == .failed ? "exclamationmark.triangle" : job.state == .completed ? "checkmark.circle" : "minus.circle") }
                    Text(job.stage).foregroundStyle(.secondary)
                    if let error = job.error { DisclosureGroup("Task could not finish") { Text(error).textSelection(.enabled) } }
                    HStack {
                        if active(job) { Button("Cancel") { Task { await model.coordinator.cancel(job.id) } } }
                        if job.state == .needsReconciliation { Button("Reconcile selected device") { model.reconcileAction?(job) } }
                        if job.state == .failed || job.state == .cancelled { Button("New confirmed attempt…") { model.retryAction?(job) } }
                    }
                }.padding(.vertical, 12).tag(job.id)
            }
        }.listStyle(.inset).scrollContentBackground(.hidden)
    }
    func active(_ job: JobRecord) -> Bool { [.queued, .running, .preparing, .verifying, .cancelling].contains(job.state) }
    var settingsPage: some View {
        Form {
            Section("Markdown export") {
                Toggle("Include local tags", isOn: $model.includeTags).focused($focus, equals: .settingsControl)
                Toggle("Include hidden annotations", isOn: $model.exportHidden)
                Text("Export options do not change which annotations are visible in your library.").foregroundStyle(.secondary)
            }
            Section("Conversion") {
                Text(model.converterStatus)
                Button("Select Calibre ebook-convert…") { model.selectConverterAction?() }
                Button("Convert a local book…") { model.convertLocalAction?() }
                Text("Produces a local AZW3 file. Opening and layout on a physical Kindle require separate validation.").foregroundStyle(.secondary)
            }
            Section("Privacy") { Text("No telemetry, Amazon login, or background synchronization.") }
            Section("Maintenance") {
                Button("Clear rebuildable cache…") { model.clearCacheAction?() }
                DisclosureGroup("Diagnostics") { Button("Preview diagnostic export…") { model.diagnosticsAction?() } }
            }
            Section("About / Compatibility") { Text("Kindle Margin · macOS 14 or later · Apple Silicon"); Text("Intel support is uncommitted.").foregroundStyle(.secondary) }
        }.formStyle(.grouped).scrollContentBackground(.hidden)
        .onChange(of: model.includeTags) { _, _ in model.persistPreferences() }
        .onChange(of: model.exportHidden) { _, _ in model.persistPreferences() }
    }
    var toolsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Contextual tools").font(.headline)
                Spacer()
                Button("Close tools", systemImage: "xmark") {
                    state.collapsed.insert(state.page); model.collapsed = state.collapsed; model.persistPreferences(); sheet = nil; focus = .tools
                }.labelStyle(.iconOnly)
            }
            ScrollView { tools.frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(20)
    }
    @ViewBuilder var tools: some View {
        if state.page == .annotations, let item = selected {
            VStack(alignment: .leading, spacing: 16) {
                BookMetadataForm(model: model, item: item)
                Text("Original annotation").font(.headline)
                Text(item.original.body.isEmpty ? "Bookmark (no text)" : item.original.body).textSelection(.enabled)
                if let location = item.original.location { LabeledContent("Location", value: location) }
                if let page = item.original.page { LabeledContent("Page", value: page) }
                if let time = item.original.timestamp { Text(time); Text("Source timezone is not inferred.").font(.callout).foregroundStyle(.secondary) }
                if !item.original.reliableIdentity { Text("Identity is incomplete; possible duplicates are retained.") }
            }
        } else if state.page == .dictionaries, let entry = state.entry {
            VStack(alignment: .leading, spacing: 16) {
                Text("Entry provenance").font(.headline); Text(entry.packageName); Text(entry.entry.id).textSelection(.enabled)
                Text(entry.edited ? "Edited locally" : "Original package entry")
                Button("Inspect base entry") { model.run { let original = try await model.service.inspectEntry(entry); guard state.page == .dictionaries, state.entry?.id == entry.id else { return }; model.preview = original.original?.definition ?? "Local addition; no upstream entry."; presentSheet(.preview, returningTo: .tools) } }
            }
        } else if state.page == .library, let file = model.device?.selected {
            Text(file.name).font(.headline); Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)); Button("Backup…") { model.device?.backupAction?() }.disabled(file.isDirectory)
        } else if state.page == .tasks, let job = model.jobs.first(where: { $0.id == state.job }) {
            Text("Task stages").font(.headline)
            ForEach(Array((job.events ?? []).enumerated()), id: \.offset) { _, event in Text(event.stage + " — " + event.message) }
            if let outcome = job.outcome { Text(outcome) }
        }
    }
}

struct BookMetadataForm: View {
    @Bindable var model: WorkspaceModel
    let item: AnnotationItem
    @State private var title = ""
    @State private var author = ""
    var body: some View {
        DisclosureGroup("Book metadata") {
            TextField("Title", text: $title)
            TextField("Author (optional)", text: $author)
            Button("Save book metadata") { model.run { try await model.service.saveBook(.init(id: item.bookID, title: title, author: author.isEmpty ? nil : author, evidence: "User confirmed grouping and metadata")) } }
        }.task(id: item.bookID) { let book = model.books.first { $0.id == item.bookID }; title = book?.title ?? item.original.description; author = book?.author ?? "" }
    }
}
