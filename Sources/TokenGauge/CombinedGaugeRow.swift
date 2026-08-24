import SwiftUI
import TokenGaugeCore

/// Two windows of the same provider shown on one track, both measured against
/// the full track and drawn from the same starting edge. Whichever has more
/// left goes underneath, so the shorter one always stays visible on top of it
/// and the longer one shows as a tail past its end.
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

/// The track itself: both windows measured against the full track and drawn
/// from the same edge, the one with more remaining underneath. Shared by the
/// large view's combined row and the small view's compact row, at different
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
            let overlayWidth = geo.size.width * fraction(overlay)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))

                // Longer bar first so the shorter one lands on top of it and
                // neither can be swallowed: whichever window is tighter is the
                // one the user needs to see.
                if fraction(base) >= fraction(overlay) {
                    Capsule().fill(baseColor).frame(width: baseWidth)
                    Capsule().fill(overlayColor).frame(width: overlayWidth)
                } else {
                    Capsule().fill(overlayColor).frame(width: overlayWidth)
                    Capsule().fill(baseColor).frame(width: baseWidth)
                }
            }
        }
        .frame(height: height)
    }

    private func fraction(_ window: UsageWindow) -> CGFloat {
        CGFloat((window.remainingPercent ?? 0) / 100)
    }
}
