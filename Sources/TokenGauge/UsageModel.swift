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
        AlertManager.shared.requestAuthorizationIfNeeded()
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

        for w in claude.windows { AlertManager.shared.process(window: w) }
        for w in codex.windows { AlertManager.shared.process(window: w) }
    }

    /// Kept as label/value pairs rather than one prebuilt string so the badge
    /// can style the labels differently without having to parse them back out.
    private func computeMenuBarSegments() -> [StatusItemBadge.Segment] {
        var parts: [StatusItemBadge.Segment] = []
        if let r = mostConstrainedRemaining(claude) {
            parts.append(.init(label: "Cl", value: "\(Int(r))%", provider: .claude, remaining: r))
        }
        if let r = mostConstrainedRemaining(codex) {
            parts.append(.init(label: "Cx", value: "\(Int(r))%", provider: .codex, remaining: r))
        }
        return parts.isEmpty
            ? [.init(label: "PH", value: "—", provider: nil, remaining: nil)]
            : parts
    }

    private func mostConstrainedRemaining(_ snapshot: ProviderSnapshot) -> Double? {
        guard snapshot.sourceExists else { return nil }
        let values = snapshot.windows.compactMap { $0.remainingPercent }
        return values.min()
    }
}
