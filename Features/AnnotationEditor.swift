import SwiftUI
import AppKit

struct AnnotationEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedText: String
    var editable = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.isEditable = editable; editor.drawsBackground = false; editor.textContainerInset = NSSize(width: 4, height: 12)
        editor.isRichText = false; editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.font = NSFont.systemFont(ofSize: 18)
        editor.setAccessibilityLabel(editable ? "Annotation correction" : "Annotation text")
        editor.delegate = context.coordinator; editor.string = text
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let editor = view.documentView as? NSTextView, editor.string != text { editor.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnnotationEditor
        init(_ parent: AnnotationEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) { if let editor = notification.object as? NSTextView { parent.text = editor.string } }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            let range = editor.selectedRange()
            parent.selectedText = range.location != NSNotFound && NSMaxRange(range) <= (editor.string as NSString).length ? (editor.string as NSString).substring(with: range) : ""
        }
    }
}
