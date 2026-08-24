import SwiftUI
import TokenGaugeCore

/// Two windows of the same provider shown on one track: the longer window
/// (Claude's weekly) as the bar, the shorter one (its 5-hour window) drawn
/// over it at the same height.
///
/// Both bars plot *remaining* percent, so the overlay hides the bar beneath
/// whenever it has more left — which happens every time the short window
/// resets to 100%. The percentages above the track stay readable in that case.
struct CombinedGaugeRow: View {
    let base: UsageWindow
    let overlay: UsageWindow
    let baseColor: Color

    private let trackHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                valueLabel(overlay, color: overlayColor, labelColor: Color.primary)
                Spacer(minLength: 8)
                // The long window's name carries the accent too, tying it to
                // the bar it names.
                valueLabel(base, color: baseColor, labelColor: baseColor)
            }

            // Filled by real width, not by scaling a full-width capsule
            // horizontally: scaling squashes the rounded caps along with the
            // body, so a short bar ends up with flattened, angular ends.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))

                    Capsule()
                        .fill(baseColor)
                        .frame(width: geo.size.width * fraction(base))

                    Capsule()
                        .fill(overlayColor)
                        .frame(width: geo.size.width * fraction(overlay))
                }
            }
            .frame(height: trackHeight)

            HStack(spacing: 8) {
                resetLabel(overlay)
                Spacer(minLength: 8)
                resetLabel(base)
            }
        }
    }

    /// The short window carries the usage colors; the long one keeps the
    /// provider accent so the two bars stay distinguishable.
    private var overlayColor: Color {
        UsagePalette.color(remaining: overlay.remainingPercent, plenty: .white)
    }

    private func fraction(_ window: UsageWindow) -> CGFloat {
        CGFloat((window.remainingPercent ?? 0) / 100)
    }

    @ViewBuilder
    private func valueLabel(_ window: UsageWindow, color: Color, labelColor: Color) -> some View {
        HStack(spacing: 4) {
            // Same size and weight as GaugeRow's label, so Claude's windows
            // and Codex's read as one list instead of two treatments.
            Text(window.label)
                .font(window.labelFont)
                .foregroundStyle(labelColor)
            Text(window.remainingPercent.map { "\(Int($0))%" } ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func resetLabel(_ window: UsageWindow) -> some View {
        if let text = ResetText.of(window) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
