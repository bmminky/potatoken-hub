import SwiftUI
import TokenGaugeCore

struct GaugeRow: View {
    let window: UsageWindow
    var showsHeading: Bool = true
    var sourceExists: Bool = true

    private var color: Color {
        UsagePalette.color(remaining: window.remainingPercent, plenty: .white)
    }

    private var trackColor: Color {
        window.provider == .codex ? Color.gray.opacity(0.32) : Color.gray.opacity(0.2)
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
                        .fill(trackColor)
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

/// When a window resets, phrased relative to now.
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
        switch L.resolved {
        case .korean:
            return "리셋 \(relative)"
        case .japanese:
            return "リセット \(relative)"
        case .chinese:
            return "重置 \(relative)"
        case .english, .system:
            return "Resets \(relative)"
        }
    }
}
