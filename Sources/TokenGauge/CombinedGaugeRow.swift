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
    var sourceExists: Bool = true

    private let trackHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ProviderHeading(provider: base.provider, sourceExists: sourceExists)
                Spacer(minLength: 8)
                // The long window's name carries the accent too, tying it to
                // the bar it names.
                WindowValueLabel(window: base, labelColor: baseColor, valueColor: baseColor)
            }

            NestedUsageBar(base: base, overlay: overlay, baseColor: baseColor, overlayColor: overlayColor, height: trackHeight)

            // The short window reads as one line under the bar — name, value
            // and reset together — since its old slot above now holds the
            // provider's name.
            HStack(spacing: 6) {
                WindowValueLabel(window: overlay, size: 10, labelColor: .primary, valueColor: overlayColor)
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
    private func resetLabel(_ window: UsageWindow) -> some View {
        if let text = ResetText.of(window) {
            Text(text)
                .font(.system(size: GaugeText.resetSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Text sizes for the gauge rows, kept in one place so both providers stay in
/// step. The provider's name is deliberately not here — it's set larger, in
/// ProviderHeading, and shouldn't follow these.
enum GaugeText {
    /// The reset lines, quietest of the three.
    static let resetSize: CGFloat = 9
}

/// A window's name and value kept together, the name set bold. Shared by the
/// paired row and the single-window row so Claude's weekly and Codex's get one
/// treatment rather than drifting apart.
struct WindowValueLabel: View {
    let window: UsageWindow
    /// Point size for both halves. The short window sits on the reset line
    /// under the bar, so it's set a little smaller than the long window's
    /// value above it.
    var size: CGFloat = 11
    /// The name takes the provider accent on the long window; the value keeps
    /// whatever meaning it already carried — fixed accent for Claude's weekly,
    /// usage colors for Codex's and for short windows.
    let labelColor: Color
    let valueColor: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(window.label)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(labelColor)
            Text(window.remainingPercent.map { "\(Int($0))%" } ?? "—")
                .font(.system(size: size).monospacedDigit())
                .foregroundStyle(valueColor)
        }
        .lineLimit(1)
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
        // The outer capsule owns the leading round cap for both fills. Giving
        // each nested bar its own leading capsule cap lets their anti-aliased
        // pixels mix, which produces a visible coloured sliver at x = 0.
        // Each fill starts flat just outside the track and is clipped once by
        // that shared outer capsule instead.
        GeometryReader { geo in
            let baseWidth = geo.size.width * fraction(base)
            let overlayWidth = geo.size.width * fraction(overlay)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2))

                // Longer bar first so the shorter one lands on top of it and
                // neither can be swallowed: whichever window is tighter is the
                // one the user needs to see.
                if fraction(base) >= fraction(overlay) {
                    leadingFill(width: baseWidth, color: baseColor)
                    leadingFill(width: overlayWidth, color: overlayColor)
                } else {
                    leadingFill(width: overlayWidth, color: overlayColor)
                    leadingFill(width: baseWidth, color: baseColor)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func leadingFill(width: CGFloat, color: Color) -> some View {
        if width > 0 {
            // Extending by half a height lets the trailing capsule cap finish
            // at exactly `width`, while the leading cap stays outside the
            // shared clip and therefore cannot overlap another fill.
            Capsule()
                .fill(color)
                .frame(width: width + height / 2)
                .offset(x: -height / 2)
        }
    }

    private func fraction(_ window: UsageWindow) -> CGFloat {
        CGFloat((window.remainingPercent ?? 0) / 100)
    }
}
