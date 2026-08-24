import AppKit

/// A chrome-less but user-resizable panel: the title bar is present (so AppKit
/// installs edge/corner resize handling and drag-to-move) but made fully
/// transparent and button-less, so it still looks like a plain floating card.
final class FloatingPanel: NSWindow {
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    init(contentViewController: NSViewController, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Observes double-clicks without consuming them: the event is still
    /// forwarded, so background-dragging the window and clicking the SwiftUI
    /// buttons keep behaving exactly as before.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           !(contentView?.hitTest(event.locationInWindow) is CornerResizeHandle) {
            onDoubleClick?()
        }

        // Right-clicks are consumed rather than forwarded: the menu is the
        // whole intent, and letting the event through as well would leave the
        // hosted SwiftUI view tracking a press the user never finishes.
        if event.type == .rightMouseDown {
            onRightClick?(event)
            return
        }

        super.sendEvent(event)
    }
}
