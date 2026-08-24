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
                    .font(.subheadline)
                Spacer()
                Text(remainingText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(color)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .scaleEffect(x: CGFloat((window.remainingPercent ?? 0) / 100), y: 1, anchor: .leading)
            }
            .frame(maxWidth: .infinity)
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

/// When a window resets, phrased relative to now. Estimated times are marked
/// with 약, since Claude's local history has no reset timestamp to read.
enum ResetText {
    static func of(_ window: UsageWindow) -> String? {
        guard let date = window.resetDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        let prefix = window.resetKind == .estimated ? "약 " : ""
        return "\(prefix)리셋 \(relative)"
    }
}
