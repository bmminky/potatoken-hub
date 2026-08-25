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
            providerSection(snapshot: model.claude)
            Divider()
            providerSection(snapshot: model.codex)
            Divider()
            FooterView(model: model, onHide: onHide)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 23)
    }

    @ViewBuilder
    private func providerSection(snapshot: ProviderSnapshot) -> some View {
        let provider = snapshot.provider
        VStack(alignment: .leading, spacing: 8) {
            // Exactly two windows collapse onto one track — the long window as
            // the bar, the short one laid over it — so a provider takes a
            // single row however many windows it reports. The provider's name
            // lives inside that row's first line, directly above the track,
            // rather than on a heading line of its own.
            if let (base, overlay) = pairedWindows(snapshot) {
                CombinedGaugeRow(
                    base: base,
                    overlay: overlay,
                    baseColor: provider.accentColor,
                    sourceExists: snapshot.sourceExists
                )
            } else if snapshot.windows.isEmpty {
                HStack(spacing: 8) {
                    ProviderHeading(provider: provider, sourceExists: snapshot.sourceExists)
                    Spacer(minLength: 8)
                    Text("—")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                // Only the first row carries the name, so a provider reporting
                // more than two windows doesn't repeat its own heading.
                ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { index, window in
                    GaugeRow(
                        window: window,
                        showsHeading: index == 0,
                        sourceExists: snapshot.sourceExists
                    )
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
            CompactRow(snapshot: model.claude)
            CompactRow(snapshot: model.codex)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

private struct CompactRow: View {
    let snapshot: ProviderSnapshot

    /// Claude's weekly when there's a pair, otherwise the provider's one
    /// window (Codex) — the number shown next to the provider name.
    private var displayWindow: UsageWindow? {
        guard snapshot.sourceExists else { return nil }
        if let paired = pairedWindows(snapshot) { return paired.base }
        return snapshot.windows.first
    }

    private var paired: (base: UsageWindow, overlay: UsageWindow)? { pairedWindows(snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                // The mark alone stands in for the provider's name here — at
                // this size the accent color already tells the two apart, and
                // dropping the word leaves the width to the gauge. Smaller
                // than the large view's mark so it doesn't crowd the bar.
                ProviderMark(provider: snapshot.provider, size: 10)
                    // The Codex symbol has a wider natural width than the
                    // Claude burst. Give both marks the same layout slot so
                    // the five-hour percentages begin at the exact same x.
                    .frame(width: 14, alignment: .leading)
                    // Nudged in from the panel's own edge padding, which is
                    // tight at this size and left the mark looking stuck to
                    // the side. Everything up to the spacer shifts with it.
                    .padding(.leading, 3)
                // The short window sits on the left and the long one on the
                // right, the same way round as the large view's combined row.
                if let overlay = paired?.overlay, let remaining = overlay.remainingPercent {
                    Text("\(Int(remaining))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(UsagePalette.color(remaining: remaining, plenty: .primary))
                }
                Spacer(minLength: 6)
                if let remaining = displayWindow?.remainingPercent {
                    Text("\(Int(remaining))%")
                        .font(.caption.monospacedDigit())
                        // Only the weekly number (Claude) gets the accent;
                        // Codex's single window keeps the default color, same
                        // as before this row could show a paired provider.
                        .foregroundStyle(paired != nil ? snapshot.provider.accentColor : .primary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Same nested bar shape as the large view.
            if let paired {
                NestedUsageBar(
                    base: paired.base,
                    overlay: paired.overlay,
                    baseColor: snapshot.provider.accentColor,
                    overlayColor: UsagePalette.color(remaining: paired.overlay.remainingPercent, plenty: .white),
                    height: 5
                )
            } else if let remaining = displayWindow?.remainingPercent {
                MiniUsageBar(remainingPercent: remaining, color: usageBarColor(for: remaining))
            }
        }
    }
}

private struct FooterView: View {
    @ObservedObject var model: UsageModel
    let onHide: () -> Void

    private static let updateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            if let lastUpdated = model.lastUpdated {
                let time = Self.updateTimeFormatter.string(from: lastUpdated)
                Text(L.t(
                    ko: "업데이트 \(time)",
                    en: "Updated \(time)",
                    ja: "更新 \(time)",
                    zh: "更新于 \(time)"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L.t(ko: "새로고침", en: "Refresh", ja: "更新", zh: "刷新"))

            // Hides the panel only; the app keeps running in the menu bar.
            // Quitting is in the status item's right-click menu.
            Button { onHide() } label: {
                Image(systemName: "eye.slash")
            }
            .help(L.t(ko: "숨기기", en: "Hide", ja: "隠す", zh: "隐藏"))
        }
        .controlSize(.small)
    }
}

private struct MiniUsageBar: View {
    let remainingPercent: Double
    let color: Color

    var body: some View {
        // Filled by real width rather than a horizontal scale, which would
        // squash the rounded ends flat on a short bar.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(remainingPercent / 100))
            }
        }
        .frame(height: 5)
    }
}

private func usageBarColor(for remaining: Double) -> Color {
    UsagePalette.color(remaining: remaining, plenty: .white)
}

/// The long and short window of a two-window provider, longest first. Picked
/// by span rather than by label so it doesn't depend on the order the reader
/// happens to build them in. Shared by the large view's provider section and
/// the small view's compact row, so both draw the same bar shape.
private func pairedWindows(_ snapshot: ProviderSnapshot) -> (base: UsageWindow, overlay: UsageWindow)? {
    guard snapshot.windows.count == 2 else { return nil }
    let sorted = snapshot.windows.sorted { $0.windowMinutes > $1.windowMinutes }
    return (sorted[0], sorted[1])
}
