import SwiftUI
import TokenGaugeCore

struct GaugeRow: View {
    let window: UsageWindow

    private var color: Color {
        guard let r = window.remainingPercent else { return .gray }
        switch r {
        case 50...: return .white
        case 15..<50: return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label)
                    .font(.subheadline)
                Spacer()
                Text(window.stateWord)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(remainingText)
                    .font(.subheadline.monospacedDigit())
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

    private var resetText: String? {
        guard let date = window.resetDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        let rel = formatter.localizedString(for: date, relativeTo: Date())
        let prefix = window.resetKind == .estimated ? "약 " : ""
        return "\(prefix)리셋 \(rel)"
    }
}
