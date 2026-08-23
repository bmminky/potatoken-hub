import AppKit
import QuartzCore

/// Fade + spring scale so the panel pops in like a little puff of cloud,
/// then eases back out on close, instead of the instant popover appear/disappear.
enum PanelAnimator {
    static func popIn(_ panel: NSWindow) {
        guard let layer = panel.contentView?.layer else {
            panel.orderFront(nil)
            return
        }

        centerAnchorPoint(of: layer)

        panel.alphaValue = 0
        layer.transform = CATransform3DMakeScale(0.85, 0.85, 1)
        panel.orderFront(nil)
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = CATransform3DMakeScale(0.85, 0.85, 1)
        spring.toValue = CATransform3DIdentity
        spring.mass = 0.6
        spring.stiffness = 260
        spring.damping = 18
        spring.initialVelocity = 5
        spring.duration = spring.settlingDuration
        spring.fillMode = .forwards
        spring.isRemovedOnCompletion = false
        layer.add(spring, forKey: "popIn")
        layer.transform = CATransform3DIdentity
    }

    static func popOut(_ panel: NSWindow, completion: @escaping () -> Void) {
        guard let layer = panel.contentView?.layer else {
            panel.orderOut(nil)
            completion()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            layer.transform = CATransform3DIdentity
            completion()
        })

        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = CATransform3DIdentity
        scale.toValue = CATransform3DMakeScale(0.9, 0.9, 1)
        scale.duration = 0.15
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false
        layer.add(scale, forKey: "popOut")
    }

    /// Forces the scale transform to originate from dead-center rather than
    /// whatever corner the hosting view's backing layer happened to anchor
    /// at, which is what made the pop-in read as growing from the bottom-right.
    private static func centerAnchorPoint(of layer: CALayer) {
        guard layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else { return }
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = frame
    }
}
