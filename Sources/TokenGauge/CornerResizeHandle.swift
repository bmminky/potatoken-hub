import AppKit

/// A small invisible hit-target at a top corner of the panel. Standard AppKit
/// titled windows only let you resize from the side/bottom edges and bottom
/// corners — the top edge is reserved for window-dragging — so diagonal
/// resize from the top corners needs to be implemented by hand here.
final class CornerResizeHandle: NSView {
    enum Corner {
        case topLeft
        case topRight
    }

    private let corner: Corner
    /// Passes the frame size this drag started from, since the snap decision
    /// needs to know which axis was actually dragged.
    var onResizeEnded: ((CGSize) -> Void)?

    private var startFrame: NSRect = .zero
    private var startMouseLocation: NSPoint = .zero

    init(corner: Corner) {
        self.corner = corner
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        // AppKit has no public diagonal-resize cursor; this at least signals
        // "this edge resizes" rather than showing the plain arrow.
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let current = NSEvent.mouseLocation
        let dx = current.x - startMouseLocation.x
        let dy = current.y - startMouseLocation.y

        let minSize = window.minSize
        let maxSize = window.maxSize

        var newWidth = startFrame.width
        var newX = startFrame.origin.x

        switch corner {
        case .topLeft:
            newWidth = min(max(startFrame.width - dx, minSize.width), maxSize.width)
            newX = startFrame.maxX - newWidth
        case .topRight:
            newWidth = min(max(startFrame.width + dx, minSize.width), maxSize.width)
            newX = startFrame.origin.x
        }

        // The bottom edge stays put; only the top edge moves, same as
        // dragging the top edge/corner of any normal resizable window.
        let newHeight = min(max(startFrame.height + dy, minSize.height), maxSize.height)
        let newY = startFrame.origin.y

        window.setFrame(NSRect(x: newX, y: newY, width: newWidth, height: newHeight), display: true)
    }

    override func mouseUp(with event: NSEvent) {
        onResizeEnded?(startFrame.size)
    }
}
