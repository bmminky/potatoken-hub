import Foundation
import Combine
import TokenGaugeCore

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var claude: ProviderSnapshot = .empty(.claude)
    @Published private(set) var codex: ProviderSnapshot = .empty(.codex)
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var menuBarText: String = "TG —"

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
        menuBarText = computeMenuBarText()

        for w in claude.windows { AlertManager.shared.process(window: w) }
        for w in codex.windows { AlertManager.shared.process(window: w) }
    }

    private func computeMenuBarText() -> String {
        var parts: [String] = []
        if let r = mostConstrainedRemaining(claude) {
            parts.append("Cl \(Int(r))%")
        }
        if let r = mostConstrainedRemaining(codex) {
            parts.append("Cx \(Int(r))%")
        }
        return parts.isEmpty ? "TG —" : parts.joined(separator: "  ")
    }

    private func mostConstrainedRemaining(_ snapshot: ProviderSnapshot) -> Double? {
        guard snapshot.sourceExists else { return nil }
        let values = snapshot.windows.compactMap { $0.remainingPercent }
        return values.min()
    }
}
