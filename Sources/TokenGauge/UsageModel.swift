import Foundation
import Combine
import TokenGaugeCore

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var claude: ProviderSnapshot = .empty(.claude)
    @Published private(set) var codex: ProviderSnapshot = .empty(.codex)
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var menuBarSegments: [StatusItemBadge.Segment] =
        [.init(label: "PH", value: "—", provider: nil, remaining: nil)]

    private var timer: Timer?
    private var lastClaudeMTime: Date?
    private var lastCodexMTime: Date?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        let newClaude = ClaudeUsageReader.readSnapshot()
        let newCodex = CodexUsageReader.readSnapshot()

        if newClaude.lastFileChange != lastClaudeMTime {
            lastClaudeMTime = newClaude.lastFileChange
        }
        if newCodex.lastFileChange != lastCodexMTime {
            lastCodexMTime = newCodex.lastFileChange
        }

        claude = newClaude
        codex = newCodex
        lastUpdated = Date()
        menuBarSegments = computeMenuBarSegments()
    }

    /// Kept as label/value pairs rather than one prebuilt string so the badge
    /// can style the labels differently without having to parse them back out.
    private func computeMenuBarSegments() -> [StatusItemBadge.Segment] {
        var parts: [StatusItemBadge.Segment] = []
        if let r = shortestWindowRemaining(claude) {
            parts.append(.init(label: "Cl", value: "\(Int(r))%", provider: .claude, remaining: r))
        }
        if let r = shortestWindowRemaining(codex) {
            parts.append(.init(label: "Cx", value: "\(Int(r))%", provider: .codex, remaining: r))
        }
        return parts.isEmpty
            ? [.init(label: "PH", value: "—", provider: nil, remaining: nil)]
            : parts
    }

    /// Each menu-bar number represents the provider's shortest reported
    /// allowance window (normally 5 hours), even when weekly is tighter.
    private func shortestWindowRemaining(_ snapshot: ProviderSnapshot) -> Double? {
        guard snapshot.sourceExists else { return nil }
        return snapshot.windows
            .filter { $0.remainingPercent != nil }
            .min { $0.windowMinutes < $1.windowMinutes }?
            .remainingPercent
    }
}
