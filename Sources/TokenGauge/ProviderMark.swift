import SwiftUI
import AppKit
import TokenGaugeCore

extension Provider {
    /// Brand-ish accent, defined once so the panel and the menu bar can't
    /// drift apart.
    ///
    /// Claude's orange sits mid-tone and reads against either background, so
    /// it's fixed. Codex's neutral gray can't be: one gray is either too dim
    /// on a dark background or too faint on a light one, so it flips.
    func accentNSColor(isDark: Bool) -> NSColor {
        switch self {
        case .claude:
            return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1) // ~#D97757
        case .codex:
            return isDark
                ? NSColor(srgbRed: 0.74, green: 0.74, blue: 0.77, alpha: 1)  // ~#BDBDC4
                : NSColor(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1)  // ~#73737A
        }
    }

    /// Resolves against whatever appearance it's drawn in, so the panel
    /// follows light/dark on its own.
    var accentColor: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            accentNSColor(isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        })
    }
}

/// Small mark drawn next to a provider's name. These are hand-drawn
/// approximations, not official brand assets — no logo files are bundled.
struct ProviderMark: View {
    let provider: Provider
    var size: CGFloat = 13

    var body: some View {
        Group {
            switch provider {
            case .claude:
                BurstShape(spokes: 11)
                    .stroke(
                        provider.accentColor,
                        style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round)
                    )
            case .codex:
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: size * 0.78, weight: .semibold))
                    .foregroundStyle(provider.accentColor)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Spokes radiating from a common center, like an asterisk — the shape of
/// Claude's mark.
private struct BurstShape: Shape {
    let spokes: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.16

        for i in 0..<spokes {
            let angle = (Double(i) / Double(spokes)) * 2 * .pi - .pi / 2
            path.move(to: CGPoint(
                x: center.x + cos(angle) * inner,
                y: center.y + sin(angle) * inner
            ))
            path.addLine(to: CGPoint(
                x: center.x + cos(angle) * outer,
                y: center.y + sin(angle) * outer
            ))
        }
        return path
    }
}
