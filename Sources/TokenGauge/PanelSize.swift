import CoreGraphics

enum PanelSize {
    static let smallWidth: CGFloat = 200
    static let largeWidth: CGFloat = 320

    /// Fallback heights used only until AppDelegate measures each preset's
    /// real content at launch (see AppDelegate.measuredHeight).
    static let smallFallbackHeight: CGFloat = 100
    static let largeFallbackHeight: CGFloat = 320

    /// How close to the large preset's exact size the window has to be,
    /// while live-dragging, before the full detailed view takes over from
    /// the small 2-row summary. Keeping this tight means the detailed view
    /// only ever appears once there's actually room for it, instead of
    /// showing up early and clipping.
    static let largeRenderTolerance: CGFloat = 24
}
