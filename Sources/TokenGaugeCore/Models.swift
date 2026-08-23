import Foundation

public enum Provider: String, CaseIterable, Codable, Sendable {
    case claude = "Claude"
    case codex = "Codex"
}

public enum FreshnessState: Sendable, Equatable {
    case fresh
    case stale
}

public enum ResetKind: Sendable, Equatable {
    case exact
    case estimated
    case unknown
}

public struct UsageWindow: Identifiable, Sendable, Equatable {
    public var id: String { "\(provider.rawValue)-\(label)" }
    public let provider: Provider
    public let label: String
    public let usedPercent: Double?
    public let resetDate: Date?
    public let resetKind: ResetKind

    public init(provider: Provider, label: String, usedPercent: Double?, resetDate: Date?, resetKind: ResetKind) {
        self.provider = provider
        self.label = label
        self.usedPercent = usedPercent
        self.resetDate = resetDate
        self.resetKind = resetKind
    }

    public var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite, usedPercent >= 0, usedPercent <= 100 else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }

    public var stateWord: String {
        guard let remainingPercent else { return "—" }
        switch remainingPercent {
        case 50...: return "여유"
        case 15..<50: return "주의"
        default: return "부족"
        }
    }
}

public struct ProviderSnapshot: Sendable {
    public let provider: Provider
    public let windows: [UsageWindow]
    public let sourceExists: Bool
    public let lastFileChange: Date?
    public let freshness: FreshnessState

    public init(provider: Provider, windows: [UsageWindow], sourceExists: Bool, lastFileChange: Date?, freshness: FreshnessState) {
        self.provider = provider
        self.windows = windows
        self.sourceExists = sourceExists
        self.lastFileChange = lastFileChange
        self.freshness = freshness
    }

    public static func empty(_ provider: Provider) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, windows: [], sourceExists: false, lastFileChange: nil, freshness: .stale)
    }
}
