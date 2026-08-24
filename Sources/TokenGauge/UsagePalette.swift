import SwiftUI
import AppKit

/// The single definition of how much-is-left maps to a color, shared by the
/// large panel, the small panel, and the menu bar readout. Previously each of
/// the three carried its own copy, which is how they drifted apart.
enum UsagePalette {
    enum Level {
        case plenty
        case caution
        case low
        case unknown
    }

    static func level(remaining: Double?) -> Level {
        guard let remaining else { return .unknown }
        switch remaining {
        case 50...: return .plenty
        case 15..<50: return .caution
        default: return .low
        }
    }

    static func word(remaining: Double?) -> String {
        switch level(remaining: remaining) {
        case .plenty: return "여유"
        case .caution: return "주의"
        case .low: return "부족"
        case .unknown: return "—"
        }
    }

    // Caution and low are fixed values so they read identically everywhere.
    // Plenty is not: on the panel it's white against dark material, but in the
    // menu bar it has to follow the menu bar, so each caller supplies its own.
    private static let cautionRGB = (red: 0.96, green: 0.86, blue: 0.55) // pastel yellow #F5DB8C
    // Muted to sit in the same family as the yellow and the Claude orange,
    // but kept saturated enough to still read as a warning — going any deeper
    // makes it hard to pick out from the orange bar it sits on top of.
    private static let lowRGB = (red: 0.867, green: 0.310, blue: 0.271) // #DD4F45

    /// - Parameter plenty: the color to use when there's plenty left.
    static func color(remaining: Double?, plenty: Color) -> Color {
        switch level(remaining: remaining) {
        case .plenty: return plenty
        case .caution: return Color(red: cautionRGB.red, green: cautionRGB.green, blue: cautionRGB.blue)
        case .low: return Color(red: lowRGB.red, green: lowRGB.green, blue: lowRGB.blue)
        case .unknown: return .gray
        }
    }

    static func nsColor(remaining: Double?, plenty: NSColor) -> NSColor {
        switch level(remaining: remaining) {
        case .plenty: return plenty
        case .caution: return NSColor(srgbRed: cautionRGB.red, green: cautionRGB.green, blue: cautionRGB.blue, alpha: 1)
        case .low: return NSColor(srgbRed: lowRGB.red, green: lowRGB.green, blue: lowRGB.blue, alpha: 1)
        case .unknown: return plenty
        }
    }
}
