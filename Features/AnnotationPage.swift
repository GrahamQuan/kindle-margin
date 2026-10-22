import SwiftUI
import KindleDomain

extension WorkspaceView {
    var annotationPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.opened != nil, let item = selected {
                annotationDetail(item)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack { filters; Spacer(); archiveMenu }
                    VStack(alignment: .leading) { filters; archiveMenu }
                }.padding(16)
                Divider()
                if model.annotations.isEmpty {
                    ContentUnavailableView {
                        Label("Your reading, collected", systemImage: "text.quote")
                    } description: { Text("Import My Clippings.txt to keep highlights, notes, and bookmarks together. A local file works without a Kindle.") }
                    actions: { Button("Import My Clippings…") { model.importClippingsAction?() }.buttonStyle(PrimaryActionStyle()) }
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("No matching annotations", systemImage: "magnifyingglass")
                    } description: { Text("Try another search or reset your book, type, and visibility filters.") }
                    actions: { Button("Clear filters") { state.search = ""; state.kind = nil; state.book = nil; state.showHidden = false } }
                } else {
                    ScrollViewReader { proxy in
                        List(selection: $state.selection) {
                            ForEach(bookGroups, id: \.id) { group in
                                Section {
                                    ForEach(group.items) { item in
                                        Button { open(item) } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(item.body.isEmpty ? "Bookmark" : item.body).font(.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                                HStack(spacing: 10) {
                                                    Text(item.original.kind.rawValue.capitalized)
                                                    if let location = item.original.location { Text("Location \(location)") }
                                                    if item.override.body != nil { Text("Edited locally") }
                                                    if item.override.hidden { Text("Hidden") }
                                                    if model.isChanged(item) { Text("Unsaved changes").bold() }
                                                }.font(.callout).foregroundStyle(.secondary)
                                            }.padding(.vertical, 10).contentShape(Rectangle())
                                        }.buttonStyle(.plain).tag(item.id).id(item.id)
                                        .accessibilityElement(children: .combine)
                                    }
                                } header: { Text(group.title).font(.headline).padding(.vertical, 8) }
                            }
                        }.listStyle(.inset).scrollContentBackground(.hidden).background(ScrollRestoration(memory: state.annotationScroll)).focused($focus, equals: .collection)
                        .onKeyPress(.return) { if let item = model.annotations.first(where: { $0.id == state.selection }) { open(item); return .handled }; return .ignored }
                        .onAppear { if state.annotationScroll.offset == .zero, let id = state.scroll { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
    }
    var filters: some View {
        HStack(spacing: 8) {
            Menu(state.kind?.rawValue.capitalized ?? "All types") {
                Button("All types") { state.kind = nil }
                ForEach(ClippingKind.allCases, id: \.self) { kind in Button(kind.rawValue.capitalized) { state.kind = kind } }
            }.menuStyle(.borderlessButton).fixedSize().padding(8).background(Color.primary.opacity(0.06), in: Capsule())
            Menu(state.book.flatMap { id in model.books.first { $0.id == id }?.title } ?? "All books") {
                Button("All books") { state.book = nil }
                ForEach(model.books) { book in Button(book.title) { state.book = book.id } }
            }.menuStyle(.borderlessButton).frame(maxWidth: 180).padding(8).background(Color.primary.opacity(0.06), in: Capsule())
            Toggle("Show hidden", isOn: $state.showHidden).toggleStyle(.checkbox)
        }
    }
    var archiveMenu: some View {
        Menu("Archive", systemImage: "archivebox") {
            Button("Import diagnostics (\(model.diagnostics.count))") { presentSheet(.diagnostics, returningTo: .archive) }
            Button("Original snapshots (\(model.snapshots.count))") { presentSheet(.snapshots, returningTo: .archive) }
        }.fixedSize().focused($focus, equals: .archive)
    }
    var bookGroups: [AnnotationBookGroup] {
        var groups: [AnnotationBookGroup] = []; var indices: [UUID: Int] = [:]
        for item in filtered {
            if let index = indices[item.bookID] { groups[index].items.append(item) }
            else { indices[item.bookID] = groups.count; groups.append(AnnotationBookGroup(id: item.bookID, title: model.books.first { $0.id == item.bookID }?.title ?? item.original.description, items: [item])) }
        }
        return groups
    }
    func open(_ item: AnnotationItem) {
        state.selectedAnnotationText = ""; state.selection = item.id; state.scroll = item.id; state.opened = item.id
        state.editing = model.isChanged(item); focus = state.editing ? .editor : .back
    }
    func back() { state.opened = nil; state.editing = false; focus = .collection }
    func annotationDetail(_ item: AnnotationItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Back to annotations", systemImage: "chevron.left", action: back).focused($focus, equals: .back)
                Spacer()
                if state.editing {
                    Button("Cancel") { cancelEdit(item) }.keyboardShortcut(.cancelAction)
                    Button("Save correction", action: saveActive).buttonStyle(PrimaryActionStyle()).disabled(!canSave)
                } else {
                    Button("Edit", systemImage: "pencil") { state.editing = true; focus = .editor }.buttonStyle(PrimaryActionStyle())
                    annotationMenu(item)
                }
            }
            Text(model.books.first { $0.id == item.bookID }?.title ?? item.original.description).font(.title2.bold()).textSelection(.enabled)
            Text("\(item.original.kind.rawValue.capitalized) · Location \(item.original.location ?? "unknown")").foregroundStyle(.secondary)
            if state.editing {
                Text("Corrections stay local. The original is preserved.").font(.callout).foregroundStyle(.secondary)
                if model.isChanged(item) { Label("Unsaved changes", systemImage: "pencil.circle").font(.callout) }
                TextField("Tags, separated by commas", text: Binding(get: { model.tagDrafts[item.id] ?? item.override.tags.joined(separator: ", ") }, set: { model.tagDrafts[item.id] = $0 })).textFieldStyle(.roundedBorder)
                TextEditor(text: Binding(get: { model.drafts[item.id] ?? item.body }, set: { model.drafts[item.id] = $0 }))
                    .font(.title3).focused($focus, equals: .editor).accessibilityLabel("Annotation correction")
                    .disabled(model.saving.contains(item.id.uuidString)).onAppear { focus = .editor }
            } else {
                AnnotationEditor(text: .constant(item.body.isEmpty ? "Bookmark (no text)" : item.body), selectedText: $state.selectedAnnotationText, editable: false)
                    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .leading)
                HStack {
                    Button("Look up selected word") { state.query = state.selectedAnnotationText; state.page = .dictionaries; lookup() }.disabled(state.selectedAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                ViewThatFits(in: .horizontal) {
                    HStack { exportActions(item) }
                    VStack(alignment: .leading) { exportActions(item) }
                }
            }
        }.padding(24)
    }
    func exportActions(_ item: AnnotationItem) -> some View {
        Group {
            Button("Preview Markdown") { presentSheet(.export, returningTo: .previewAction) }.focused($focus, equals: .previewAction)
            Button("Export book…") { presentSheet(.export, returningTo: .exportAction) }.focused($focus, equals: .exportAction)
            Text("All eligible annotations in this book").font(.callout).foregroundStyle(.secondary)
        }
    }
    func annotationMenu(_ item: AnnotationItem) -> some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button(item.override.hidden ? "Unhide" : "Hide") {
                model.save(item, hide: !item.override.hidden)
                if !state.showHidden && !item.override.hidden { state.selection = nil; state.scroll = nil; back() }
            }
            Button("Restore original…") {
                confirmation = .init(title: "Restore original annotation?", message: "This removes the local correction, tags, grouping override, and any unsaved draft for this annotation.", actionTitle: "Restore original", action: { model.save(item, restore: true); state.editing = false })
            }
            Menu("Move to book group") {
                ForEach(model.books) { book in Button(book.title) { model.run { var value = item.override; value.bookID = book.id; try await model.service.update(id: item.id, value: value) } } }
                Button("Split into a new group") { model.run { let id = UUID(); try await model.service.saveBook(.init(id: id, title: item.original.description)); var value = item.override; value.bookID = id; try await model.service.update(id: item.id, value: value) } }
            }
        }.fixedSize()
    }
    func cancelEdit(_ item: AnnotationItem) {
        let discard = { model.drafts[item.id] = nil; model.tagDrafts[item.id] = nil; state.editing = false; focus = .back }
        if model.isChanged(item) { confirmation = .init(title: "Discard unsaved correction?", message: "The saved annotation and original remain unchanged.", actionTitle: "Discard changes", action: discard) }
        else { discard() }
    }
    var canSave: Bool {
        if state.page == .annotations, state.editing, let item = selected { return model.isChanged(item) && !model.saving.contains(item.id.uuidString) }
        if state.page == .dictionaries, state.entryEditing, let entry = state.entry { return (model.entryDrafts[entry.id] ?? entry.entry.definition) != entry.entry.definition && !model.saving.contains(entry.id) }
        return false
    }
    func saveActive() {
        guard canSave else { return }
        if state.page == .annotations, let item = selected {
            Task {
                do { try await model.saveDraft(item); if state.opened == item.id { state.editing = model.annotations.first(where: { $0.id == item.id }).map(model.isChanged) ?? false }; notice = "Correction saved." }
                catch { notice = "Could not save correction: \(error.localizedDescription). Your draft is retained; try Save correction again." }
            }
        } else if let item = state.entry {
            let text = model.entryDrafts[item.id] ?? item.entry.definition
            Task {
                do { try await model.saveEntry(item); if state.entry?.id == item.id { state.entry?.entry.definition = text; state.entryEditing = model.entryDrafts[item.id] != nil }; notice = "Definition saved." }
                catch { notice = "Could not save definition: \(error.localizedDescription). Your draft is retained; try Save definition again." }
            }
        }
    }
}
struct AnnotationBookGroup { var id: UUID; var title: String; var items: [AnnotationItem] }
