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
        switch provider {
        case .claude:
            BurstShape(spokes: 11)
                .stroke(
                    provider.accentColor,
                    style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round)
                )
                .frame(width: size, height: size)
        case .codex:
            // Height only. This glyph is wider than it is tall, so boxing it
            // into the same square as the burst let it spill past both sides —
            // which read as Codex's mark starting further left than Claude's.
            // Taking its natural width puts the two leading edges together.
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size * 0.78, weight: .semibold))
                .foregroundStyle(provider.accentColor)
                .frame(height: size)
        }
    }
}

/// The provider's mark and name, drawn as the leading half of a gauge row's
/// first line so it sits directly above the track it labels, rather than on a
/// heading line of its own.
struct ProviderHeading: View {
    let provider: Provider
    var sourceExists: Bool = true

    private let markSize: CGFloat = 14
    private let nameSize: CGFloat = 14

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            ProviderMark(provider: provider, size: markSize)
                // The mark is a shape, so it has no baseline of its own and
                // would fall back to centering on the text's full line box —
                // which includes descender space and leaves it sitting low.
                // Give it a baseline that puts its center level with the
                // middle of the capitals beside it instead.
                .alignmentGuide(.firstTextBaseline) { d in
                    d.height / 2 + capHalfHeight + opticalLift
                }
            Text(provider.rawValue)
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundStyle(provider.accentColor)
            if !sourceExists {
                Text(L.t(ko: "데이터 없음", en: "No data", ja: "データなし", zh: "无数据"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    /// Half the cap height of the name's font, measured up from its baseline.
    private var capHalfHeight: CGFloat {
        NSFont.systemFont(ofSize: nameSize, weight: .semibold).capHeight / 2
    }

    /// Geometric centering still reads a touch low against the letters, since
    /// both marks carry more weight in their lower half than capitals do.
    private let opticalLift: CGFloat = 0.5
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
