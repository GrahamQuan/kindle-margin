import SwiftUI
import AppKit

/// Scene-local scroll memory deliberately does not invalidate a view on every pixel of scrolling.
@MainActor public final class ScrollMemory {
    var offset = NSPoint.zero
    public init() {}
}

struct ScrollRestoration: NSViewRepresentable {
    let memory: ScrollMemory
    func makeCoordinator() -> Coordinator { Coordinator(memory) }
    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.attach = { probe in context.coordinator.attach(probe) }
        return view
    }
    func updateNSView(_ view: Probe, context: Context) { view.scheduleAttachment() }
    static func dismantleNSView(_ view: Probe, coordinator: Coordinator) { coordinator.stop() }
    final class Probe: NSView {
        var attach: ((NSView) -> Bool)?
        private var attachmentScheduled = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleAttachment() }
        override func layout() { super.layout(); scheduleAttachment() }
        func scheduleAttachment(attempt: Int = 0) {
            guard window != nil, !attachmentScheduled else { return }
            attachmentScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.016)) { [weak self] in
                guard let self else { return }
                self.attachmentScheduled = false
                if self.window != nil, self.attach?(self) != true, attempt < 60 { self.scheduleAttachment(attempt: attempt + 1) }
            }
        }
    }
    @MainActor final class Coordinator {
        let memory: ScrollMemory
        weak var scroll: NSScrollView?
        var observer: NSObjectProtocol?
        init(_ memory: ScrollMemory) { self.memory = memory }
        func attach(_ probe: NSView) -> Bool {
            if let scroll, scroll.window === probe.window { return true }
            stop()
            var ancestor = probe.superview
            while let candidate = ancestor {
                if let found = findScroll(candidate), found.frame.width > 280 {
                    scroll = found
                    found.layoutSubtreeIfNeeded()
                    found.contentView.scroll(to: memory.offset)
                    found.reflectScrolledClipView(found.contentView)
                    found.contentView.postsBoundsChangedNotifications = true
                    observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: found.contentView, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { guard let self, let scroll = self.scroll else { return }; self.memory.offset = scroll.contentView.bounds.origin }
                    }
                    return true
                }
                ancestor = candidate.superview
            }
            return false
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.frame.width > 280 { return scroll }
            for child in view.subviews { if let result = findScroll(child) { return result } }
            return nil
        }
        func stop() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil; scroll = nil }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
