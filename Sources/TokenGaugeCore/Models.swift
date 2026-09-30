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

public enum CodexPlan: Sendable, Equatable {
    case plus
    case pro
}

public struct UsageWindow: Identifiable, Sendable, Equatable {
    public var id: String { "\(provider.rawValue)-\(label)" }
    public let provider: Provider
    public let label: String
    /// How long this window spans. Lets callers tell a short window from a
    /// long one without matching on the display label.
    public let windowMinutes: Int
    public let usedPercent: Double?
    public let resetDate: Date?
    public let resetKind: ResetKind

    public init(provider: Provider, label: String, windowMinutes: Int, usedPercent: Double?, resetDate: Date?, resetKind: ResetKind) {
        self.provider = provider
        self.label = label
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.resetDate = resetDate
        self.resetKind = resetKind
    }

    public var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite, usedPercent >= 0, usedPercent <= 100 else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
}

public struct ProviderSnapshot: Sendable {
    public let provider: Provider
    public let windows: [UsageWindow]
    public let sourceExists: Bool
    public let lastFileChange: Date?
    /// Timestamp of the usage record itself, which may predate the file mtime.
    public let lastRecordDate: Date?
    public let freshness: FreshnessState
    public let codexPlan: CodexPlan?

    public init(provider: Provider, windows: [UsageWindow], sourceExists: Bool, lastFileChange: Date?, lastRecordDate: Date? = nil, freshness: FreshnessState, codexPlan: CodexPlan? = nil) {
        self.provider = provider
        self.windows = windows
        self.sourceExists = sourceExists
        self.lastFileChange = lastFileChange
        self.lastRecordDate = lastRecordDate
        self.freshness = freshness
        self.codexPlan = codexPlan
    }

    /// Keep source metadata but never present an old allowance as current.
    public var hidingStaleUsage: ProviderSnapshot {
        guard freshness == .stale else { return self }
        return ProviderSnapshot(
            provider: provider,
            windows: [],
            sourceExists: sourceExists,
            lastFileChange: lastFileChange,
            lastRecordDate: lastRecordDate,
            freshness: freshness,
            codexPlan: codexPlan
        )
    }

    /// The menu bar promises the five-hour value; a weekly-only record is not a substitute.
    public var fiveHourRemainingPercent: Double? {
        guard freshness == .fresh else { return nil }
        return windows.first { $0.windowMinutes == 300 }?.remainingPercent
    }

    /// The status item follows the plan reported by the same usage record.
    /// Unknown plans use an explicitly labelled available window, never a
    /// fabricated percentage.
    public var menuBarWindow: UsageWindow? {
        guard freshness == .fresh else { return nil }
        let fiveHour = windows.first { $0.windowMinutes == 300 }
        guard provider == .codex else { return fiveHour }
        let weekly = windows.first { $0.windowMinutes == 10080 }
        switch codexPlan {
        case .plus: return fiveHour
        case .pro: return weekly
        case nil: return fiveHour ?? weekly
        }
    }

    public static func empty(_ provider: Provider) -> ProviderSnapshot {
        ProviderSnapshot(provider: provider, windows: [], sourceExists: false, lastFileChange: nil, freshness: .stale)
    }
}
