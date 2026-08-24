import SwiftUI
import TokenGaugeCore

struct GaugeRow: View {
    let window: UsageWindow
    var showsHeading: Bool = true
    var sourceExists: Bool = true

    private var color: Color {
        UsagePalette.color(remaining: window.remainingPercent, plenty: .white)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Name and value together at the trailing edge, reading the same
            // way as the paired row's long window ("주간 72%") so a
            // single-window provider lines up with Claude's weekly above it.
            HStack(spacing: 8) {
                if showsHeading {
                    ProviderHeading(provider: window.provider, sourceExists: sourceExists)
                }
                Spacer(minLength: 8)
                WindowValueLabel(
                    window: window,
                    labelColor: window.provider.accentColor,
                    valueColor: color
                )
            }
            // Filled by real width rather than a horizontal scale, which would
            // squash the rounded ends flat on a short bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat((window.remainingPercent ?? 0) / 100))
                }
            }
            .frame(height: 8)
            // Trailing edge as well, sitting under the value it belongs to —
            // the same place the paired row puts its long window's reset line.
            if let resetText {
                HStack {
                    Spacer()
                    Text(resetText)
                        .font(.system(size: GaugeText.resetSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resetText: String? { ResetText.of(window) }
}

/// When a window resets, phrased relative to now. Estimated times carry an
/// "approximately" qualifier, since Claude's local history has no reset
/// timestamp to read.
enum ResetText {
    static func of(_ window: UsageWindow) -> String? {
        guard let date = window.resetDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        // Matches the display language rather than the system's exact
        // region, so a Portuguese system showing our English text also gets
        // an English relative phrase, not a Portuguese one mixed into it.
        formatter.locale = L.formattingLocale
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        // Only short windows carry the qualifier. Over a week the estimate's
        // error is small next to the span, so "약" there is noise rather than
        // useful precision.
        let isEstimated = window.resetKind == .estimated && window.windowMinutes < 24 * 60

        switch L.resolved {
        case .korean:
            // 약 qualifies the duration, not the reset itself, so it belongs
            // next to the time: "리셋 약 1시간 후", not "약 리셋 1시간 후".
            return "리셋 \(isEstimated ? "약 " : "")\(relative)"
        case .japanese:
            // Same reasoning as Korean: 約 sits with the duration, and the
            // formatter's Japanese output already ends in 後 ("6日後"), so it
            // reads naturally as "約6日後".
            return "リセット \(isEstimated ? "約" : "")\(relative)"
        case .chinese:
            // Chinese "about" (大约) also reads naturally right before the
            // quantity: "大约6天后".
            return "重置 \(isEstimated ? "大约" : "")\(relative)"
        case .english, .system:
            // RelativeDateTimeFormatter's English output already starts with
            // "in"/"ago" ("in 6 days"), so "about" can't be inserted before it
            // without reading like "about in 6 days". A trailing qualifier
            // avoids that.
            return "Resets \(relative)\(isEstimated ? " (est.)" : "")"
        }
    }
}
