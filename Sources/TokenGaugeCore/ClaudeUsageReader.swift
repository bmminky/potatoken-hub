import Foundation

struct ClaudeSample: Codable {
    let t: Int64
    let org: String?
    let u: [String: Int]
}

struct ClaudeHistoryFile: Codable {
    let version: Int
    let samples: [ClaudeSample]
}

public enum ClaudeUsageReader {
    static let fiveHourSeconds: TimeInterval = 5 * 3600
    static let weeklySeconds: TimeInterval = 7 * 24 * 3600
    static let staleAfter: TimeInterval = 15 * 60

    public static func defaultPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    public static func readSnapshot(at url: URL = defaultPath(), now: Date = Date()) -> ProviderSnapshot {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        guard exists,
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ClaudeHistoryFile.self, from: data),
              let latest = file.samples.max(by: { $0.t < $1.t })
        else {
            return ProviderSnapshot(provider: .claude, windows: [], sourceExists: exists, lastFileChange: nil, freshness: .stale)
        }

        let freshness: FreshnessState = now.timeIntervalSince(mtime) > staleAfter ? .stale : .fresh
        let sorted = file.samples.sorted { $0.t < $1.t }

        func series(_ key: String) -> [UsageSample] {
            sorted.compactMap { sample in
                guard let v = sample.u[key] else { return nil }
                return UsageSample(time: Date(timeIntervalSince1970: Double(sample.t) / 1000), value: v)
            }
        }

        let fhReset = ResetEstimator.estimateNextReset(samples: series("fh"), windowDuration: fiveHourSeconds, now: now)
        let sdReset = ResetEstimator.estimateNextReset(samples: series("sd"), windowDuration: weeklySeconds, now: now)

        let windows = [
            UsageWindow(
                provider: .claude,
                label: L.t(ko: "5시간", en: "5h", ja: "5時間", zh: "5小时"),
                windowMinutes: 5 * 60,
                usedPercent: latest.u["fh"].map(Double.init),
                resetDate: fhReset,
                resetKind: fhReset != nil ? .estimated : .unknown
            ),
            UsageWindow(
                provider: .claude,
                label: L.t(ko: "주간", en: "Weekly", ja: "週間", zh: "每周"),
                windowMinutes: 7 * 24 * 60,
                usedPercent: latest.u["sd"].map(Double.init),
                resetDate: sdReset,
                resetKind: sdReset != nil ? .estimated : .unknown
            ),
        ]

        return ProviderSnapshot(provider: .claude, windows: windows, sourceExists: true, lastFileChange: mtime, freshness: freshness)
    }
}
