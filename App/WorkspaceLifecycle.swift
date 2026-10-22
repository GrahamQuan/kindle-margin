import SwiftUI
import AppKit
import Features

struct WorkspaceCommandMenu: Commands {
    @FocusedValue(\.workspaceCommands) private var context
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { context?.page.wrappedValue = .settings }.keyboardShortcut(",").disabled(context == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Save correction") { context?.save.wrappedValue = UUID() }.keyboardShortcut("s").disabled(context?.canSave != true)
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { context?.find.wrappedValue = UUID() }.keyboardShortcut("f").disabled(context?.canFind != true)
        }
    }
}

@MainActor func resolveWorkspaceDrafts(_ model: WorkspaceModel) async -> Bool {
    guard model.saving.isEmpty else {
        let alert = NSAlert(); alert.messageText = "A correction is being saved"; alert.informativeText = "Wait for the save to finish before closing."; alert.runModal(); return false
    }
    guard model.hasDrafts else { return true }
    let alert = NSAlert()
    alert.messageText = "Save your unsaved changes?"
    alert.informativeText = "Annotation corrections and dictionary drafts are shared across open windows. Save them, discard them, or keep editing."
    alert.addButton(withTitle: "Save All"); alert.addButton(withTitle: "Discard Changes"); alert.addButton(withTitle: "Cancel")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
        do { try await model.saveAllDrafts(); return !model.hasDrafts }
        catch { let failure = NSAlert(); failure.messageText = "Changes could not be saved"; failure.informativeText = error.localizedDescription + " Your remaining drafts are retained."; failure.runModal(); return false }
    case .alertSecondButtonReturn: model.discardDrafts(); return true
    default: return false
    }
}

/// Wraps, and forwards to, SwiftUI's window delegate rather than discarding its lifecycle behavior.
struct WorkspaceCloseGuard: NSViewRepresentable {
    let model: WorkspaceModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSView { let view = AttachmentView(); view.attach = { window in context.coordinator.attach(window) }; return view }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let window = coordinator.window, window.delegate === coordinator { window.delegate = coordinator.previous }
    }
    final class AttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { attach?(window) } }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let model: WorkspaceModel
        weak var window: NSWindow?
        weak var previous: NSWindowDelegate?
        var approved = false
        var pending = false
        init(model: WorkspaceModel) { self.model = model }
        func attach(_ window: NSWindow) { guard self.window !== window else { return }; self.window = window; previous = window.delegate; window.delegate = self }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || previous?.responds(to: selector) == true }
        override func forwardingTarget(for selector: Selector!) -> Any? { previous?.responds(to: selector) == true ? previous : super.forwardingTarget(for: selector) }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if approved || (!model.hasDrafts && model.saving.isEmpty) { return previous?.windowShouldClose?(sender) ?? true }
            guard !pending else { return false }; pending = true
            Task {
                let result = await resolveWorkspaceDrafts(model); pending = false
                if result { approved = true; sender.performClose(nil); approved = false }
            }
            return false
        }
    }
}
