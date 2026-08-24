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
                valueLabel(overlay, color: overlayColor)
                Spacer(minLength: 8)
                valueLabel(base, color: baseColor)
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(baseColor)
                    .frame(height: trackHeight)
                    .scaleEffect(x: fraction(base), y: 1, anchor: .leading)

                Capsule()
                    .fill(overlayColor)
                    .frame(height: trackHeight)
                    .scaleEffect(x: fraction(overlay), y: 1, anchor: .leading)
            }
            .frame(maxWidth: .infinity)
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
    private func valueLabel(_ window: UsageWindow, color: Color) -> some View {
        HStack(spacing: 4) {
            // Same size and weight as GaugeRow's label, and the same primary
            // color rather than a dimmed one, so Claude's windows and Codex's
            // read as one list instead of two different treatments.
            Text(window.label)
                .font(.subheadline)
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
