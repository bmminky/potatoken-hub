import Foundation
import Combine
import TokenGaugeCore

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var claude: ProviderSnapshot = .empty(.claude)
    @Published private(set) var codex: ProviderSnapshot = .empty(.codex)
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var displayedProviders: [Provider] = []
    @Published private(set) var menuBarSegments: [StatusItemBadge.Segment] =
        [.init(label: "PH", value: "—", provider: nil, remaining: nil)]

    private var timer: Timer?
    private var lastClaudeMTime: Date?
    private var lastCodexMTime: Date?
    private var providerVisibility: [Provider: ProviderVisibility]

    init() {
        providerVisibility = Dictionary(
            uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderVisibility.load(for: $0)) }
        )
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
        updateDisplayedProviders()
        menuBarSegments = computeMenuBarSegments()
    }

    var displayedSnapshots: [ProviderSnapshot] {
        displayedProviders.map { provider in
            provider == .claude ? claude : codex
        }
    }

    func visibility(for provider: Provider) -> ProviderVisibility {
        providerVisibility[provider] ?? .automatic
    }

    func setVisibility(_ visibility: ProviderVisibility, for provider: Provider) {
        guard providerVisibility[provider] != visibility else { return }
        providerVisibility[provider] = visibility
        visibility.save(for: provider)
        updateDisplayedProviders()
        menuBarSegments = computeMenuBarSegments()
    }

    private func updateDisplayedProviders() {
        displayedProviders = Provider.allCases.filter { provider in
            let snapshot = provider == .claude ? claude : codex
            switch visibility(for: provider) {
            case .automatic:
                return snapshot.sourceExists
            case .alwaysShow:
                return true
            case .hidden:
                return false
            }
        }
    }

    /// Kept as label/value pairs rather than one prebuilt string so the badge
    /// can style the labels differently without having to parse them back out.
    private func computeMenuBarSegments() -> [StatusItemBadge.Segment] {
        var parts: [StatusItemBadge.Segment] = []
        if displayedProviders.contains(.claude) {
            let remaining = shortestWindowRemaining(claude)
            parts.append(.init(
                label: "Cl",
                value: remaining.map { "\(Int($0))%" } ?? "—",
                provider: .claude,
                remaining: remaining
            ))
        }
        if displayedProviders.contains(.codex) {
            let remaining = shortestWindowRemaining(codex)
            parts.append(.init(
                label: "Cx",
                value: remaining.map { "\(Int($0))%" } ?? "—",
                provider: .codex,
                remaining: remaining
            ))
        }
        return parts
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

enum ProviderVisibility: String, CaseIterable {
    case automatic
    case alwaysShow
    case hidden

    private static func key(for provider: Provider) -> String {
        "TokenGauge.providerVisibility.\(provider.rawValue.lowercased())"
    }

    static func load(for provider: Provider) -> ProviderVisibility {
        UserDefaults.standard.string(forKey: key(for: provider))
            .flatMap(ProviderVisibility.init(rawValue:)) ?? .automatic
    }

    func save(for provider: Provider) {
        UserDefaults.standard.set(rawValue, forKey: Self.key(for: provider))
    }
}
