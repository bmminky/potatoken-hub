import SwiftUI
import TokenGaugeCore

struct ContentView: View {
    @ObservedObject var model: UsageModel
    let largeSize: CGSize
    let onHide: () -> Void

    var body: some View {
        GeometryReader { geo in
            let tolerance = PanelSize.largeRenderTolerance
            let isLarge = geo.size.width >= largeSize.width - tolerance && geo.size.height >= largeSize.height - tolerance

            Group {
                if isLarge {
                    FullContent(model: model, onHide: onHide)
                } else {
                    MinimalContent(model: model)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}

/// The detailed, full-size layout. Also instantiated off-window at launch
/// (see AppDelegate) to measure its natural height for the large snap preset,
/// so the deliberately roomy bottom margin below the footer is exact rather
/// than guessed.
struct FullContent: View {
    @ObservedObject var model: UsageModel
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerSection(title: "Claude", snapshot: model.claude)
            Divider()
            providerSection(title: "Codex", snapshot: model.codex)
            Divider()
            FooterView(model: model, onHide: onHide)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private func providerSection(title: String, snapshot: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if !snapshot.sourceExists {
                    Text("데이터 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if snapshot.freshness == .stale {
                    Text("오래됨")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if snapshot.windows.isEmpty {
                Text("—")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(snapshot.windows) { window in
                    GaugeRow(window: window)
                }
            }
        }
    }
}

/// The small tier: just the two usage rows, no divider or footer at all —
/// refresh/quit aren't reachable here, only via the large size or the status
/// item's right-click menu.
struct MinimalContent: View {
    @ObservedObject var model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompactRow(title: "Claude", snapshot: model.claude)
            CompactRow(title: "Codex", snapshot: model.codex)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

private struct CompactRow: View {
    let title: String
    let snapshot: ProviderSnapshot

    private var remaining: Double? {
        guard snapshot.sourceExists else { return nil }
        return snapshot.windows.compactMap { $0.remainingPercent }.min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                Spacer()
                if let remaining {
                    Text("\(Int(remaining))%")
                        .font(.caption.monospacedDigit())
                    Text(stateWord(for: remaining))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let remaining {
                MiniUsageBar(remainingPercent: remaining, color: usageBarColor(for: remaining))
            }
        }
    }
}

private struct FooterView: View {
    @ObservedObject var model: UsageModel
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let lastUpdated = model.lastUpdated {
                Text("업데이트 \(lastUpdated, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("새로고침") { model.refresh() }
                .font(.caption)
                .lineLimit(1)
            // Hides the panel only; the app keeps running in the menu bar.
            // Quitting is in the status item's right-click menu.
            Button("숨기기") { onHide() }
                .font(.caption)
                .lineLimit(1)
        }
        .controlSize(.small)
    }
}

private struct MiniUsageBar: View {
    let remainingPercent: Double
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.gray.opacity(0.2))
            Capsule()
                .fill(color)
                .scaleEffect(x: CGFloat(remainingPercent / 100), y: 1, anchor: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 5)
    }
}

private func stateWord(for remaining: Double) -> String {
    switch remaining {
    case 50...: return "여유"
    case 15..<50: return "주의"
    default: return "부족"
    }
}

private func usageBarColor(for remaining: Double) -> Color {
    switch remaining {
    case 50...: return .white
    case 15..<50: return .yellow
    default: return .red
    }
}
