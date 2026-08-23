import Foundation

public struct UsageSample: Sendable, Equatable {
    public let time: Date
    public let value: Int

    public init(time: Date, value: Int) {
        self.time = time
        self.value = value
    }
}

/// Claude's local history has no reset timestamp, so the next reset is inferred
/// from past drops in usage (a drop means the window rolled over) plus the
/// known window length. Codex reports `resets_at` directly and does not need this.
public enum ResetEstimator {
    public static func estimateNextReset(
        samples: [UsageSample],
        windowDuration: TimeInterval,
        now: Date,
        dropThreshold: Int = 3
    ) -> Date? {
        guard samples.count >= 2 else { return nil }
        let sorted = samples.sorted { $0.time < $1.time }

        var lastResetAnchor: Date?
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let cur = sorted[i]
            if cur.value < prev.value - dropThreshold {
                lastResetAnchor = cur.time
            }
        }

        guard var anchor = lastResetAnchor else { return nil }
        while anchor.addingTimeInterval(windowDuration) < now {
            anchor = anchor.addingTimeInterval(windowDuration)
        }
        return anchor.addingTimeInterval(windowDuration)
    }
}
