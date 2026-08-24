import AppKit

/// A chrome-less floating card. The title bar is present so AppKit gives the
/// window its normal shadow and drag-to-move behaviour, but it's made fully
/// transparent and button-less. The panel is not user-resizable: its size is
/// one of two presets, chosen by double-clicking it.
final class FloatingPanel: NSWindow {
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    /// Fired the moment the user touches the panel, before anything else acts
    /// on the event, so an in-flight animation can get out of the way.
    var onInteractionStart: (() -> Void)?

    /// When the panel isn't key yet, the click that activates it gets
    /// redelivered through sendEvent a second time after activation
    /// completes — same event, same eventNumber. Without deduping this,
    /// onInteractionStart fires again on the replay and cancels the
    /// just-started double-click animation, and onDoubleClick fires twice.
    private var lastHandledMouseDownEventNumber: Int?

    /// Where the panel sat at the previous mouse-down. Dragging the window a
    /// long way — across displays, say — is usually done in short strokes:
    /// grab, pull, release, grab again. Two of those grabs landing inside the
    /// double-click interval is reported as clickCount 2, and acting on it
    /// resized the panel mid-drag. A real double-click leaves the window where
    /// it was between the two clicks; a re-grab doesn't.
    private var originAtLastMouseDown: NSPoint?

    init(contentViewController: NSViewController, size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
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

    /// AppKit's default implementation fits the frame to whichever screen the
    /// window is landing on, and will resize it to do so — which is why
    /// dragging the panel to a second display could change its size out from
    /// under the presets. The panel is small and positions itself against the
    /// right screen already (see AppDelegate.panelScreen), so take the frame
    /// as proposed.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// The size the panel is meant to be, or nil before one has been chosen.
    ///
    /// When a drag ends on a display with a different backing scale, AppKit
    /// runs its own frame adjustment (`_setFrameAfterMove:` →
    /// `_setFrame:fromAdjustmentToScreen:`) and restores whatever size the
    /// window last had on *that* display. For a two-preset panel that reads as
    /// the window spontaneously switching size every time it crosses displays.
    /// Anything that isn't a deliberate resize gets held to this size instead.
    var enforcedSize: NSSize?

    /// Raised while the app is deliberately resizing — the size toggle, its
    /// animation, restoring a saved frame. Those are allowed to disagree with
    /// `enforcedSize`, since they're the ones changing it.
    var isPerformingOwnResize = false

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if let enforcedSize,
           rect.size != enforcedSize,
           !isPerformingOwnResize {
            // Take neither half of the adjustment. Its origin was computed for
            // the size it wanted, so keeping that origin while overriding the
            // size lands the panel off by the difference — which reads as the
            // window jumping the moment a drag is released. Pinning the
            // top-left to where the panel already is leaves it exactly where
            // it was dropped.
            rect = NSRect(
                x: frame.origin.x,
                y: frame.maxY - enforcedSize.height,
                width: enforcedSize.width,
                height: enforcedSize.height
            )
        }
        super.setFrame(rect, display: flag)
    }

    /// Observes double-clicks without consuming them: the event is still
    /// forwarded, so background-dragging the window and clicking the SwiftUI
    /// buttons keep behaving as they otherwise would.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.eventNumber != lastHandledMouseDownEventNumber {
            lastHandledMouseDownEventNumber = event.eventNumber
            onInteractionStart?()

            let previousOrigin = originAtLastMouseDown
            originAtLastMouseDown = frame.origin

            if event.clickCount == 2,
               !panelMoved(since: previousOrigin) {
                onDoubleClick?()
            }
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

    /// Whether the panel has been dragged since the previous mouse-down. The
    /// tolerance absorbs the pixel or so a click can nudge the window without
    /// the user meaning to move it.
    private func panelMoved(since previousOrigin: NSPoint?) -> Bool {
        guard let previousOrigin else { return false }
        let tolerance: CGFloat = 2
        return abs(frame.origin.x - previousOrigin.x) > tolerance
            || abs(frame.origin.y - previousOrigin.y) > tolerance
    }
}
