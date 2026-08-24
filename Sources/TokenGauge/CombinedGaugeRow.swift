import SwiftUI
import TokenGaugeCore

/// Two windows of the same provider shown on one track: the longer window
/// (Claude's weekly) as the bar, the shorter one (its 5-hour window) drawn
/// from the same starting edge, but capped at weekly's own extent.
///
/// The 5-hour bar isn't an independent 0–100% bar; 100% of it is scaled to
/// equal 100% of *weekly's current bar*, not 100% of the whole track. At
/// weekly 77%, a freshly-reset (100%) 5-hour window exactly covers the
/// orange bar (0–77%) — it can never reach past what weekly allows. As it's
/// used up, it shrinks from that same starting edge, uncovering orange from
/// the right.
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

            NestedUsageBar(base: base, overlay: overlay, baseColor: baseColor, overlayColor: overlayColor, height: trackHeight)

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

/// The track itself: weekly as the base bar, the short window capped at
/// weekly's own extent and drawn from the same edge. Shared by the large
/// view's combined row and the small view's compact row, at different
/// heights, so both places draw the exact same shape.
struct NestedUsageBar: View {
    let base: UsageWindow
    let overlay: UsageWindow
    let baseColor: Color
    let overlayColor: Color
    let height: CGFloat

    var body: some View {
        // Filled by real width, not by scaling a full-width capsule
        // horizontally: scaling squashes the rounded caps along with the
        // body, so a short bar ends up with flattened, angular ends.
        GeometryReader { geo in
            let baseWidth = geo.size.width * fraction(base)
            // 5-hour's 100% maps to weekly's own bar width, not the full
            // track — it's a fraction of a fraction.
            let overlayWidth = baseWidth * fraction(overlay)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))

                Capsule()
                    .fill(baseColor)
                    .frame(width: baseWidth)

                Capsule()
                    .fill(overlayColor)
                    .frame(width: overlayWidth)
            }
        }
        .frame(height: height)
    }

    private func fraction(_ window: UsageWindow) -> CGFloat {
        CGFloat((window.remainingPercent ?? 0) / 100)
    }
}
