import AppKit
import SwiftUI
import Combine
import QuartzCore
import TokenGaugeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var isPanelVisible = false
    private var cancellables: Set<AnyCancellable> = []
    private var sizeAnimation: Timer?
    private var pendingSizeAnimation: (target: CGSize, minSize: NSSize, maxSize: NSSize)?
    private var appearanceObservation: NSKeyValueObservation?

    /// The 2 snap presets. Heights are measured from the real SwiftUI content
    /// at launch (see applicationDidFinishLaunching) instead of guessed, so
    /// each size's margins come out exactly as designed rather than leaving
    /// dead space or clipping text.
    private var smallSize = CGSize(width: PanelSize.smallWidth, height: PanelSize.smallFallbackHeight)
    private var largeSize = CGSize(width: PanelSize.largeWidth, height: PanelSize.largeFallbackHeight)

    enum SizePreset {
        case small
        case large
    }

    /// Which preset the user last chose. Held as state rather than read back
    /// off the window, because the whole point of tracking it is to recover
    /// when something else has already changed the window's size — inferring
    /// the preset from a size that's wrong just ratifies the wrong size.
    private var activePreset: SizePreset = .small {
        didSet { panel?.enforcedSize = size(of: activePreset) }
    }

    /// Runs a deliberate resize, so the panel lets it through instead of
    /// holding the frame to the current preset.
    private func performingOwnResize(_ body: () -> Void) {
        panel.isPerformingOwnResize = true
        body()
        panel.isPerformingOwnResize = false
    }

    private func size(of preset: SizePreset) -> CGSize {
        preset == .large ? largeSize : smallSize
    }

    /// Used only where there's genuinely no recorded intent to consult: a
    /// frame saved by an older build, or a size the user just dragged.
    private func preset(nearestTo size: CGSize) -> SizePreset {
        size.width >= (smallSize.width + largeSize.width) / 2 ? .large : .small
    }

    private static let savedFrameKey = "TokenGauge.panelFrame"
    private static let hasShownBeforeKey = "TokenGauge.hasShownBefore"
    private static let alwaysOnTopKey = "TokenGauge.alwaysOnTop"

    /// When off, the panel still jumps to the front the moment it's opened
    /// (popIn already orders it front), but afterwards behaves like a normal
    /// window: clicking another app's window can cover it. When on, it stays
    /// above everything regardless of what's focused.
    private var isAlwaysOnTop: Bool {
        get {
            // Default true: matches the panel's behavior before this setting
            // existed, so upgrading doesn't change anyone's experience.
            UserDefaults.standard.object(forKey: Self.alwaysOnTopKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.alwaysOnTopKey)
            panel.level = newValue ? .floating : .normal
        }
    }

    let model = UsageModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // The badge bakes its colors in, so it has to be redrawn whenever
            // the menu bar switches between light and dark.
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.renderBadge() }
            }
        }
        renderBadge()

        updateMeasuredPresetSizes()

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
        panel.enforcedSize = size(of: activePreset)
        panel.level = isAlwaysOnTop ? .floating : .normal
        panel.delegate = self
        panel.onDoubleClick = { [weak self] in self?.toggleSizePreset() }
        panel.onRightClick = { [weak self] event in self?.showPanelMenu(for: event) }
        panel.onInteractionStart = { [weak self] in self?.finishSizeAnimation() }

        // Overriding constrainFrameRect also gave up AppKit's one useful part:
        // hauling a window back when its display disappears. Watch for the
        // display set changing and do that rescue ourselves.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recoverPanelIfOffScreen() }
        }

        model.$menuBarSegments
            .receive(on: RunLoop.main)
            .sink { [weak self] segments in
                self?.renderBadge(segments)
            }
            .store(in: &cancellables)

        model.$displayedProviders
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.displayedProvidersDidChange()
            }
            .store(in: &cancellables)
    }

    /// Moves to a preset, doing nothing if the panel is already there — so a
    /// pull outwards on an already-large panel doesn't replay the animation.
    private func applyPreset(_ preset: SizePreset) {
        guard preset != activePreset else { return }
        activePreset = preset
        animatePanel(to: size(of: preset), keepingHorizontalCenter: true, style: .springy)
    }

    /// Size picker, shared by the panel's and the status item's menus. The
    /// double-click toggle stays the quick way to switch; this is the explicit
    /// one, and it also shows which preset is currently active.
    private func sizeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: L.t(ko: "창 크기", en: "Window Size", ja: "ウインドウサイズ", zh: "窗口大小"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        let options: [(SizePreset, String)] = [
            (.small, L.t(ko: "소형", en: "Small", ja: "小", zh: "小")),
            (.large, L.t(ko: "대형", en: "Large", ja: "大", zh: "大")),
        ]
        for (preset, title) in options {
            let option = NSMenuItem(title: title, action: #selector(selectSize(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = preset
            option.state = activePreset == preset ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? SizePreset else { return }
        // Opening the panel first, so picking a size from the status item also
        // brings it back when it's hidden.
        if !isPanelVisible {
            openPanel()
        }
        applyPreset(preset)
    }

    /// Brings the panel back beside the status item if the display it was on
    /// went away. Without this it would sit at coordinates no screen covers —
    /// invisible, and not clickable to get back.
    private func recoverPanelIfOffScreen() {
        guard isPanelVisible, !isFrameOnScreen(panel.frame) else { return }
        performingOwnResize {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size(of: activePreset)), display: false)
        }
        positionNearStatusItem()
    }

    private func renderBadge(_ segments: [StatusItemBadge.Segment]? = nil) {
        guard let button = statusItem.button else { return }
        let segments = segments ?? model.menuBarSegments
        if segments.isEmpty {
            let icon = NSApplication.shared.applicationIconImage.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
            return
        }
        let isDark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        button.image = StatusItemBadge.image(
            for: segments,
            isDarkMenuBar: isDark
        )
    }

    private func updateMeasuredPresetSizes() {
        let measurementBuffer: CGFloat = 2
        let showsOneProvider = model.displayedProviders.count == 1
        let smallMinimumHeight: CGFloat = showsOneProvider ? 50 : 60
        let largeMinimumHeight: CGFloat = showsOneProvider ? 130 : 150

        func measuredPresetHeight<V: View>(_ view: V, width: CGFloat) -> CGFloat {
            let wrapped = view
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            return measuredHeight(of: wrapped, width: width) + measurementBuffer
        }

        smallSize = NSSize(
            width: PanelSize.smallWidth,
            height: max(
                measuredPresetHeight(MinimalContent(model: model), width: PanelSize.smallWidth),
                smallMinimumHeight
            )
        )
        largeSize = NSSize(
            width: PanelSize.largeWidth,
            height: max(
                measuredPresetHeight(FullContent(model: model, onHide: {}), width: PanelSize.largeWidth),
                largeMinimumHeight
            )
        )
    }

    private func displayedProvidersDidChange() {
        updateMeasuredPresetSizes()
        let target = size(of: activePreset)
        panel.enforcedSize = target

        if isPanelVisible {
            animatePanel(to: target, keepingHorizontalCenter: true, style: .crisp)
        } else {
            performingOwnResize {
                panel.setContentSize(target)
            }
        }
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
        activePreset = .small
        let size = smallSize
        let margin: CGFloat = 16
        let x = visible.maxX - size.width - margin
        let y = visible.maxY - size.height - margin
        performingOwnResize {
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
        }
    }

    /// Restores the remembered position but snaps the size back to whichever
    /// of the 2 presets it's closest to, in case it was saved by an older
    /// build that allowed arbitrary sizes. There's no "drag" here, so just
    /// judge by width against its own midpoint.
    private func restoreNearPreset(_ saved: NSRect) {
        activePreset = preset(nearestTo: saved.size)
        let size = size(of: activePreset)
        let topY = saved.origin.y + saved.size.height
        let origin = NSPoint(x: saved.origin.x, y: topY - size.height)
        performingOwnResize {
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        }
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
        applyPreset(activePreset == .large ? .small : .large)
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
            panel.isPerformingOwnResize = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.panel.isPerformingOwnResize = false }
            }
        case .springy:
            springResize(to: targetFrame)
        }
    }

    /// Ends a running size animation early and settles on its target size.
    ///
    /// The animation drives the frame on a timer, so anything else moving the
    /// window at the same time — dragging it right after a double-click —
    /// gets overwritten every tick and stutters. Any interaction cancels it
    /// instead. The size still lands on the preset, since stopping mid-flight
    /// would strand the panel at an in-between (or overshot) size; the origin
    /// is left alone so the window doesn't jump out from under the cursor.
    private func finishSizeAnimation() {
        guard let animation = sizeAnimation else { return }
        animation.invalidate()
        sizeAnimation = nil

        guard let pending = pendingSizeAnimation else { return }
        pendingSizeAnimation = nil
        panel.minSize = pending.minSize
        panel.maxSize = pending.maxSize

        let current = panel.frame
        performingOwnResize {
            panel.setFrame(
                NSRect(
                    x: current.origin.x,
                    y: current.maxY - pending.target.height,
                    width: pending.target.width,
                    height: pending.target.height
                ),
                display: true
            )
        }
    }

    /// Drives the frame frame-by-frame instead of handing it to
    /// NSAnimationContext, because the bounce needs to briefly pass *beyond*
    /// the target size and NSWindow silently constrains any frame it is given
    /// — animated or not — to minSize/maxSize. Those limits are widened for
    /// the duration and restored at the end.
    private func springResize(to targetFrame: NSRect) {
        finishSizeAnimation()

        let startFrame = panel.frame
        let savedMin = panel.minSize
        let savedMax = panel.maxSize
        pendingSizeAnimation = (target: targetFrame.size, minSize: savedMin, maxSize: savedMax)
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
        panel.isPerformingOwnResize = true

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
                    self.pendingSizeAnimation = nil
                    self.panel.minSize = savedMin
                    self.panel.maxSize = savedMax
                    self.panel.setFrame(targetFrame, display: true)
                    self.panel.isPerformingOwnResize = false
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

    /// The menu on the panel itself, for the actions that are also in its
    /// footer — reachable at the small size, where the footer isn't shown.
    private func showPanelMenu(for event: NSEvent) {
        guard let contentView = panel.contentView else { return }

        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: L.t(ko: "새로고침", en: "Refresh", ja: "更新", zh: "刷新"), action: #selector(refreshFromPanelMenu), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(sizeMenuItem())
        menu.addItem(providerVisibilityMenuItem())
        menu.addItem(alwaysOnTopMenuItem())

        let hideItem = NSMenuItem(title: L.t(ko: "숨기기", en: "Hide", ja: "隠す", zh: "隐藏"), action: #selector(hidePanel), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        NSMenu.popUpContextMenu(menu, with: event, for: contentView)
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: L.t(ko: "새로고침", en: "Refresh", ja: "更新", zh: "刷新"), action: #selector(refreshFromTrayMenu), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(sizeMenuItem())
        menu.addItem(providerVisibilityMenuItem())
        menu.addItem(alwaysOnTopMenuItem())

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: L.t(ko: "로그인 시 자동 실행", en: "Launch at Login", ja: "ログイン時に自動起動", zh: "登录时启动"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(languageMenuItem())

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: L.t(
                ko: "\(AboutPanel.appName) 정보",
                en: "About \(AboutPanel.appName)",
                ja: "\(AboutPanel.appName) について",
                zh: "关于\(AboutPanel.appName)"
            ),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: L.t(ko: "앱 종료하기", en: "Quit", ja: "終了", zh: "退出"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Titled in both languages at once ("언어 / Language") rather than just
    /// the current one — this is the one control that changes what language
    /// everything else is in, so it needs to stay findable even if someone
    /// ends up in a language they don't read.
    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "언어 / Language / 言語 / 语言", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let options: [(L.Language, String)] = [
            (.system, L.t(ko: "시스템 언어 따름", en: "Follow System", ja: "システム言語に従う", zh: "跟随系统语言")),
            (.korean, "한국어"),
            (.english, "English"),
            (.japanese, "日本語"),
            (.chinese, "中文"),
        ]
        for (language, title) in options {
            let option = NSMenuItem(title: title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = language
            option.state = L.languagePreference == language ? .on : .off
            submenu.addItem(option)
        }

        item.submenu = submenu
        return item
    }

    private func providerVisibilityMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: L.t(ko: "표시할 서비스", en: "Displayed Services", ja: "表示するサービス", zh: "显示的服务"),
            action: nil,
            keyEquivalent: ""
        )
        let providersMenu = NSMenu()

        for provider in Provider.allCases {
            let providerItem = NSMenuItem(
                title: provider.rawValue,
                action: #selector(toggleProviderDisplayed(_:)),
                keyEquivalent: ""
            )
            providerItem.target = self
            providerItem.representedObject = provider
            providerItem.state = model.isDisplayed(provider) ? .on : .off
            providersMenu.addItem(providerItem)
        }

        item.submenu = providersMenu
        return item
    }

    @objc private func toggleProviderDisplayed(_ sender: NSMenuItem) {
        guard let provider = sender.representedObject as? Provider else { return }
        model.toggleDisplayed(provider)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? L.Language else { return }
        L.languagePreference = language
        // Menus are rebuilt fresh each time they're opened, so they'll pick
        // this up on their own; the already-open panel needs to be told,
        // since its text only changes when something re-renders it.
        model.refresh()
    }

    /// Shared by both menus (the panel's own and the status item's) so the
    /// checkbox always reflects the same one underlying setting.
    private func alwaysOnTopMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: L.t(ko: "항상 위", en: "Always on Top", ja: "常に最前面", zh: "始终置顶"),
            action: #selector(toggleAlwaysOnTop),
            keyEquivalent: ""
        )
        item.target = self
        item.state = isAlwaysOnTop ? .on : .off
        return item
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
    }

    @objc private func showAbout() {
        AboutPanel.show()
    }

    @objc private func refreshFromPanelMenu() {
        model.refresh()
    }

    @objc private func refreshFromTrayMenu() {
        model.refresh()
    }

    @objc private func hidePanel() {
        closePanel()
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



    /// Puts the panel back on its preset if anything resized it while it moved
    /// between displays. Its size is chosen by the user's double-click, not by
    /// which screen it happens to be on, so a screen change should never be
    /// able to change it.
    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        // Don't fight the toggle's own animation, which is deliberately
        // mid-flight between presets.
        guard sizeAnimation == nil else { return }

        let target = size(of: activePreset)
        guard panel.frame.size != target else { return }

        // Anchored at the top-left, so restoring the size doesn't also shift
        // the panel away from where the user just dropped it.
        let frame = panel.frame
        panel.setFrame(
            NSRect(
                x: frame.origin.x,
                y: frame.maxY - target.height,
                width: target.width,
                height: target.height
            ),
            display: true
        )
    }


    /// The panel has no zoom button, and a double-click anywhere on it is our
    /// own size toggle — don't also let the system's title-bar double-click
    /// zoom fire on top of it.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        false
    }
}
