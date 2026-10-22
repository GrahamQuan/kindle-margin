import SwiftUI
import AppKit

/// Announces new operation feedback only from the window the user is working in.
struct StatusAnnouncement: NSViewRepresentable {
    let message: String?
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.lastMessage != message else { return }
        context.coordinator.lastMessage = message
        guard let message, !message.isEmpty else { return }
        DispatchQueue.main.async { [weak view] in
            guard view?.window?.isKeyWindow == true else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
    final class Coordinator { var lastMessage: String? }
}
