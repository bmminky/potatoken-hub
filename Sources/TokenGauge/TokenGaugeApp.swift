import AppKit

@main
@MainActor
enum TokenGaugeApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.finishLaunching()
        app.run()
    }
}
