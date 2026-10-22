import SwiftUI
import KindleDomain

@MainActor struct DictionaryManagementView: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        DisclosureGroup("Add entries, resolve edits, and recover dictionaries") {
            VStack(alignment: .leading) {
                Picker("Dictionary", selection: $model.managementDictionary) {
                    Text("Select dictionary").tag(nil as String?)
                    ForEach(model.installedDictionaries) { Text($0.name).tag(Optional($0.id)) }
                }
                HStack {
                    TextField("Headword", text: $model.newHeadword)
                    TextField("Definition", text: $model.newDefinition)
                    Button("Add sense") {
                        guard let id = model.managementDictionary else { return }
                        model.run {
                            try await model.service.addEntry(packageID: id, entry: .init(id: "local-" + UUID().uuidString, headword: model.newHeadword, definition: model.newDefinition))
                            model.newHeadword = ""; model.newDefinition = ""; model.changes = try await model.service.entryChanges(id)
                        }
                    }.disabled(model.managementDictionary == nil || model.newHeadword.trimmingCharacters(in: .whitespaces).isEmpty || model.newDefinition.trimmingCharacters(in: .whitespaces).isEmpty)
                }.textFieldStyle(.roundedBorder)
                Button("Refresh edits") { guard let id = model.managementDictionary else { return }; model.run { model.changes = try await model.service.entryChanges(id) } }
                ScrollView { ForEach(model.changes) { change in
                    VStack(alignment: .leading) {
                        Text((change.local?.headword ?? change.original?.headword ?? change.entryID) + (change.conflicted ? " · Conflict" : change.hidden ? " · Hidden" : " · Local edit"))
                        HStack {
                            Button("Inspect") { model.preview = "Original:\n" + (change.original?.definition ?? "Missing upstream") + "\n\nLocal:\n" + (change.local?.definition ?? "None") }
                            Button(change.conflicted ? "Keep as local entry" : "Keep local edit") { model.run { try await model.service.resolveEntry(change, keepLocal: true); model.changes = try await model.service.entryChanges(change.packageID) } }
                            Button("Restore upstream / discard edit") { model.run { try await model.service.resolveEntry(change, keepLocal: false); model.changes = try await model.service.entryChanges(change.packageID) } }
                        }
                    }.padding(.bottom, 6)
                } }.frame(maxHeight: 160)
                Text("Removing a dictionary retains its base entries and edits for recovery.").font(.caption)
                ForEach(model.removedDictionaries) { dictionary in Button("Restore " + dictionary.name) { model.run { try await model.service.restoreDictionary(dictionary.id) } } }
            }
        }.padding(.horizontal)
        .onChange(of: model.managementDictionary) { _, id in model.changes = []; if let id { model.run { model.changes = try await model.service.entryChanges(id) } } }
    }
}
