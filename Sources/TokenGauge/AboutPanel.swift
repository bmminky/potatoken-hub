import AppKit

/// The standard macOS about panel, filled in from the bundle so the name and
/// version never drift from Info.plist.
enum AboutPanel {
    private static let creator = "bmminky"
    private static let repository = "https://github.com/bmminky/TokenGauge"
    private static let email = "s12m1004@gmail.com"

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "potatoken hub"
    }

    static func show() {
        // Without this the panel opens behind whatever is in front: an
        // LSUIElement app isn't in the foreground when its menu item fires.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .credits: credits,
        ])
    }

    private static var credits: NSAttributedString {
        let body = NSFont.systemFont(ofSize: 11)
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(
            string: "만든 사람  \(creator)\n",
            attributes: [.font: body, .foregroundColor: NSColor.labelColor]
        ))
        result.append(link("GitHub", url: repository, font: body))
        result.append(NSAttributedString(string: "\n", attributes: [.font: body]))
        result.append(link(email, url: "mailto:\(email)", font: body))

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineSpacing = 2
        result.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func link(_ text: String, url: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .link: URL(string: url) as Any,
            .foregroundColor: NSColor.linkColor,
        ])
    }
}
