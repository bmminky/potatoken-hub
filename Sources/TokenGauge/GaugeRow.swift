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

/// When a window resets, phrased relative to now. Estimated times are marked
/// with 약, since Claude's local history has no reset timestamp to read.
enum ResetText {
    static func of(_ window: UsageWindow) -> String? {
        guard let date = window.resetDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        // 약 qualifies the duration, not the reset itself, so it belongs next
        // to the time: "리셋 약 1시간 후", not "약 리셋 1시간 후".
        let approximately = window.resetKind == .estimated ? "약 " : ""
        return "리셋 \(approximately)\(relative)"
    }
}
