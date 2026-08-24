import AppKit
import SwiftUI
import Combine
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var isPanelVisible = false
    private var cancellables: Set<AnyCancellable> = []
    private var resizeStartSize: CGSize?
    private var sizeAnimation: Timer?

    /// The 2 snap presets. Heights are measured from the real SwiftUI content
    /// at launch (see applicationDidFinishLaunching) instead of guessed, so
    /// each size's margins come out exactly as designed rather than leaving
    /// dead space or clipping text.
    private var smallSize = CGSize(width: PanelSize.smallWidth, height: PanelSize.smallFallbackHeight)
    private var largeSize = CGSize(width: PanelSize.largeWidth, height: PanelSize.largeFallbackHeight)

    private static let savedFrameKey = "TokenGauge.panelFrame"
    private static let hasShownBeforeKey = "TokenGauge.hasShownBefore"

    let model = UsageModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusItemBadge.image(for: model.menuBarSegments)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Measured with the exact same .regularMaterial/clipShape wrapper the
        // real window uses. Now that the hosted view ignores the title bar's
        // safe area, the window frame height and the SwiftUI layout height are
        // the same number, so this only needs slack for rounding.
        let measurementBuffer: CGFloat = 2

        func measuredPresetHeight<V: View>(_ view: V, width: CGFloat) -> CGFloat {
            let wrapped = view
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            return measuredHeight(of: wrapped, width: width) + measurementBuffer
        }

        smallSize = NSSize(
            width: PanelSize.smallWidth,
            height: max(measuredPresetHeight(MinimalContent(model: model), width: PanelSize.smallWidth), 60)
        )
        largeSize = NSSize(
            width: PanelSize.largeWidth,
            height: max(measuredPresetHeight(FullContent(model: model, onHide: {}), width: PanelSize.largeWidth), 200)
        )

        let hosting = NSHostingController(
            rootView: ContentView(model: model, largeSize: largeSize, onHide: { [weak self] in self?.closePanel() })
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                // The hidden-but-present title bar contributes a top safe area
                // inset, which otherwise shrinks the SwiftUI layout (and the
                // GeometryReader size the tier check reads) by ~32pt versus the
                // window frame. This panel draws its own chrome, so take the
                // whole frame.
                .ignoresSafeArea()
        )
        // Without this, NSHostingController tries to size itself to its SwiftUI
        // content's ideal size and fights the window's own frame, so dragging
        // the window edges to resize gets silently reverted.
        hosting.sizingOptions = []
        panel = FloatingPanel(contentViewController: hosting, size: largeSize)
        panel.minSize = smallSize
        panel.maxSize = largeSize
        panel.delegate = self
        panel.onDoubleClick = { [weak self] in self?.toggleSizePreset() }
        addCornerResizeHandles()

        model.$menuBarSegments
            .receive(on: RunLoop.main)
            .sink { [weak self] segments in
                self?.statusItem.button?.image = StatusItemBadge.image(for: segments)
            }
            .store(in: &cancellables)
    }

    private func addCornerResizeHandles() {
        guard let contentView = panel.contentView else { return }
        let size: CGFloat = 14

        let topLeft = CornerResizeHandle(corner: .topLeft)
        topLeft.onResizeEnded = { [weak self] startSize in self?.snapToNearestPresetIfNeeded(draggedFrom: startSize) }
        topLeft.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topLeft)
        NSLayoutConstraint.activate([
            topLeft.topAnchor.constraint(equalTo: contentView.topAnchor),
            topLeft.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            topLeft.widthAnchor.constraint(equalToConstant: size),
            topLeft.heightAnchor.constraint(equalToConstant: size),
        ])

        let topRight = CornerResizeHandle(corner: .topRight)
        topRight.onResizeEnded = { [weak self] startSize in self?.snapToNearestPresetIfNeeded(draggedFrom: startSize) }
        topRight.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topRight)
        NSLayoutConstraint.activate([
            topRight.topAnchor.constraint(equalTo: contentView.topAnchor),
            topRight.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topRight.widthAnchor.constraint(equalToConstant: size),
            topRight.heightAnchor.constraint(equalToConstant: size),
        ])
    }

    private func measuredHeight<V: View>(of view: V, width: CGFloat) -> CGFloat {
        let controller = NSHostingController(rootView: view)
        // Match the real displayed controller's sizingOptions ([]) — leaving
        // this at its default (self-sizing) measures a different, smaller
        // ideal size than what the same content actually needs once it's
        // hosted in a window that isn't letting it self-size.
        controller.sizingOptions = []
        let fitting = controller.sizeThatFits(in: NSSize(width: width, height: 2000))
        return ceil(fitting.height)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isPanelVisible {
            saveFrame(panel.frame)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func togglePanel() {
        if isPanelVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.hasShownBeforeKey) {
            positionTopRight()
            defaults.set(true, forKey: Self.hasShownBeforeKey)
        } else if let saved = loadSavedFrame(), isFrameOnScreen(saved) {
            restoreNearPreset(saved)
        } else {
            positionNearStatusItem()
        }

        PanelAnimator.popIn(panel)
        isPanelVisible = true
    }

    private func positionTopRight() {
        guard let screen = statusItemScreen else { return }
        let visible = screen.visibleFrame
        let size = smallSize
        let margin: CGFloat = 16
        let x = visible.maxX - size.width - margin
        let y = visible.maxY - size.height - margin
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    /// Restores the remembered position but snaps the size back to whichever
    /// of the 2 presets it's closest to, in case it was saved by an older
    /// build that allowed arbitrary sizes. There's no "drag" here, so just
    /// judge by width against its own midpoint.
    private func restoreNearPreset(_ saved: NSRect) {
        let widthBoundary = (smallSize.width + largeSize.width) / 2
        let size = saved.size.width >= widthBoundary ? largeSize : smallSize
        let topY = saved.origin.y + saved.size.height
        let origin = NSPoint(x: saved.origin.x, y: topY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func closePanel() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        saveFrame(panel.frame)
        PanelAnimator.popOut(panel) {}
    }

    private func positionNearStatusItem() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        var x = buttonFrameInScreen.midX - panelSize.width / 2
        let y = buttonFrameInScreen.minY - panelSize.height - 4

        if let visible = statusItemScreen?.visibleFrame {
            x = min(max(x, visible.minX + 4), visible.maxX - panelSize.width - 4)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func loadSavedFrame() -> NSRect? {
        guard let values = UserDefaults.standard.array(forKey: Self.savedFrameKey) as? [Double], values.count == 4 else {
            return nil
        }
        return NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(
            [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
            forKey: Self.savedFrameKey
        )
    }

    private func isFrameOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    /// The display the panel is actually sitting on.
    ///
    /// Everything that keeps the panel on-screen has to measure against this,
    /// never `NSScreen.main`: main is the menu-bar display, so clamping a
    /// panel that lives on a second display to main's bounds drags it back
    /// across to main every time it is resized.
    private var panelScreen: NSScreen? {
        panel.screen ?? statusItemScreen
    }

    /// The display showing the menu bar this app's status item is in.
    private var statusItemScreen: NSScreen? {
        statusItem.button?.window?.screen ?? NSScreen.main
    }

    /// Double-clicking the panel switches to the other preset.
    private func toggleSizePreset() {
        let currentWidth = panel.frame.width
        let isLarge = abs(currentWidth - largeSize.width) <= abs(currentWidth - smallSize.width)
        animatePanel(to: isLarge ? smallSize : largeSize, keepingHorizontalCenter: true, style: .springy)
    }

    enum ResizeStyle {
        /// Short ease-out, for settling a size the user just dragged.
        case crisp
        /// Overshoots and rebounds, for the double-click toggle.
        case springy
    }

    /// Resizes around the top edge, so the panel never walks up or down the
    /// screen as it changes tier.
    private func animatePanel(to target: CGSize, keepingHorizontalCenter: Bool, style: ResizeStyle = .crisp) {
        let current = panel.frame
        guard target != current.size else { return }

        var newX = keepingHorizontalCenter
            ? current.midX - target.width / 2
            : current.origin.x

        if let visible = panelScreen?.visibleFrame {
            newX = min(max(newX, visible.minX + 4), visible.maxX - target.width - 4)
        }

        let targetFrame = NSRect(
            origin: NSPoint(x: newX, y: current.maxY - target.height),
            size: target
        )

        switch style {
        case .crisp:
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        case .springy:
            springResize(to: targetFrame)
        }
    }

    /// Drives the frame frame-by-frame instead of handing it to
    /// NSAnimationContext, because the bounce needs to briefly pass *beyond*
    /// the target size and NSWindow silently constrains any frame it is given
    /// — animated or not — to minSize/maxSize. Those limits are widened for
    /// the duration and restored at the end.
    private func springResize(to targetFrame: NSRect) {
        sizeAnimation?.invalidate()

        let startFrame = panel.frame
        let savedMin = panel.minSize
        let savedMax = panel.maxSize
        let slack: CGFloat = 90
        panel.minSize = NSSize(
            width: max(min(startFrame.width, targetFrame.width) - slack, 1),
            height: max(min(startFrame.height, targetFrame.height) - slack, 1)
        )
        panel.maxSize = NSSize(
            width: max(startFrame.width, targetFrame.width) + slack,
            height: max(startFrame.height, targetFrame.height) + slack
        )

        let duration: CFTimeInterval = 0.5
        let startTime = CACurrentMediaTime()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }

                let progress = min((CACurrentMediaTime() - startTime) / duration, 1)
                let eased = Self.springEase(progress)

                self.panel.setFrame(
                    NSRect(
                        x: startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * eased,
                        y: startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * eased,
                        width: startFrame.width + (targetFrame.width - startFrame.width) * eased,
                        height: startFrame.height + (targetFrame.height - startFrame.height) * eased
                    ),
                    display: true
                )

                if progress >= 1 {
                    timer.invalidate()
                    self.sizeAnimation = nil
                    self.panel.minSize = savedMin
                    self.panel.maxSize = savedMax
                    self.panel.setFrame(targetFrame, display: true)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sizeAnimation = timer
    }

    /// Damped oscillation: rises past 1 about a third of the way in, dips
    /// slightly under, then settles — one clear bounce rather than a long
    /// wobble, which on a whole window reads as lively instead of unsteady.
    private static func springEase(_ t: Double) -> CGFloat {
        guard t < 1 else { return 1 }
        return CGFloat(1 - exp(-6 * t) * cos(9 * t))
    }

    /// Decides by whichever axis was actually dragged this time (the one that
    /// moved further from where this specific drag started), using that
    /// axis's own midpoint. Width's span (120pt) and height's span (~230pt)
    /// are too different for a flat 2D nearest-neighbor to treat fairly — it
    /// either lets height dominate (a pure width-only drag could never reach
    /// large) or lets an untouched axis parked at one preset's exact value
    /// permanently lock the result (a pure height-only drag from large could
    /// never reach small). Looking at which axis this drag moved sidesteps
    /// both: an edge-only drag decides by that edge's axis; a corner drag
    /// (both axes moving together) just picks whichever moved a bit more.
    private func nearestPreset(to size: CGSize, draggedFrom start: CGSize) -> CGSize {
        let widthMoved = abs(size.width - start.width)
        let heightMoved = abs(size.height - start.height)

        if widthMoved >= heightMoved {
            let widthBoundary = (smallSize.width + largeSize.width) / 2
            return size.width >= widthBoundary ? largeSize : smallSize
        } else {
            let heightBoundary = (smallSize.height + largeSize.height) / 2
            return size.height >= heightBoundary ? largeSize : smallSize
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "새로고침", action: #selector(refreshNow), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "앱 종료하기", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshNow() {
        model.refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
    }

    @objc private func quitApp() {
        if isPanelVisible {
            saveFrame(panel.frame)
        }
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    /// The authoritative size clamp: `NSWindow.minSize`/`maxSize` alone don't
    /// reliably hold on a borderless, fullSizeContentView panel, so enforce
    /// the bounds directly on every live-resize callback.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Only police sizes the user is dragging. The springy toggle
        // deliberately overshoots the presets, and clamping here would flatten
        // the bounce.
        guard sender.inLiveResize else { return frameSize }
        return NSSize(
            width: min(max(frameSize.width, smallSize.width), largeSize.width),
            height: min(max(frameSize.height, smallSize.height), largeSize.height)
        )
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        resizeStartSize = panel.frame.size
    }

    /// Once the user lets go of the resize handle, snap to whichever of the
    /// 2 presets (large/small) is closest instead of leaving it at an
    /// arbitrary dragged size.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        let start = resizeStartSize ?? panel.frame.size
        resizeStartSize = nil
        snapToNearestPresetIfNeeded(draggedFrom: start)
    }

    /// Also called manually by the top-corner resize handles, since dragging
    /// those bypasses AppKit's own resize tracking (and so never fires
    /// windowWillStartLiveResize/windowDidEndLiveResize on their own).
    func snapToNearestPresetIfNeeded(draggedFrom start: CGSize) {
        let current = panel.frame.size
        let target = nearestPreset(to: current, draggedFrom: start)

        // A vertical drag never asked the width to change, so growing it off
        // one side looks like the panel lunging sideways. Keep it centered on
        // where it already is instead. A horizontal drag keeps its left edge,
        // which is what dragging a side edge normally does.
        let widthMoved = abs(current.width - start.width)
        let heightMoved = abs(current.height - start.height)

        animatePanel(to: target, keepingHorizontalCenter: heightMoved > widthMoved)
    }

    /// The panel has no zoom button, and a double-click anywhere on it is our
    /// own size toggle — don't also let the system's title-bar double-click
    /// zoom fire on top of it.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
