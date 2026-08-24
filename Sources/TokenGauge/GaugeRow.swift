import SwiftUI
import TokenGaugeCore

struct GaugeRow: View {
    let window: UsageWindow

    private var color: Color {
        UsagePalette.color(remaining: window.remainingPercent, plenty: .white)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label)
                    .font(window.labelFont)
                Spacer()
                Text(remainingText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(color)
                    .frame(minWidth: 40, alignment: .trailing)
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
            if let resetText {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var remainingText: String {
        guard let r = window.remainingPercent else { return "—" }
        return "\(Int(r))%"
    }

    private var resetText: String? { ResetText.of(window) }
}

extension UsageWindow {
    /// Windows shorter than a day are set semibold, longer ones regular, so
    /// that where two sit side by side the short one reads as the distinct
    /// entry. Keyed off the actual span rather than the label text, and
    /// applied in both rows so Claude's and Codex's lines follow one rule.
    var labelFont: Font {
        windowMinutes < 24 * 60
            ? Font.subheadline.weight(.semibold)
            : Font.subheadline
    }
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
        let isEstimated = window.resetKind == .estimated

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
