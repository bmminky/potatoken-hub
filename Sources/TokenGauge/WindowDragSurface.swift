import AppKit
import SwiftUI

/// Explicit drag surface for read-only SwiftUI content (including shapes).
/// Keep this overlay off buttons so their normal click tracking is preserved.
struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView { WindowDragView() }
    func updateNSView(_ nsView: WindowDragView, context: Context) {}
}

final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // FloatingPanel already handles the second click. Starting native
        // dragging here would compete with its size animation.
        guard (window as? FloatingPanel)?.handledSizeToggleForCurrentClick != true else { return }
        window?.performDrag(with: event)
    }
}
