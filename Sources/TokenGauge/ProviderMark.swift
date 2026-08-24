import SwiftUI
import TokenGaugeCore

extension Provider {
    /// Brand-ish accent for the section heading. Claude gets its orange;
    /// Codex gets a neutral gray.
    var accentColor: Color {
        switch self {
        case .claude:
            return Color(red: 0.85, green: 0.47, blue: 0.34) // ~#D97757
        case .codex:
            return Color(red: 0.58, green: 0.58, blue: 0.60) // ~#949499
        }
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
