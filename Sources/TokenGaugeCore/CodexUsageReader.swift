import Foundation

struct CodexRateLimitWindow: Decodable {
    let used_percent: Double
    let window_minutes: Int
    let resets_at: Int64?
}

struct CodexRateLimits: Decodable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

struct CodexPayload: Decodable {
    let type: String?
    let rate_limits: CodexRateLimits?
}

struct CodexLine: Decodable {
    let payload: CodexPayload?
}

public enum CodexUsageReader {
    static let staleAfter: TimeInterval = 15 * 60

    public static func defaultSessionsDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    public static func readSnapshot(
        sessionsDir: URL = defaultSessionsDir(),
        now: Date = Date(),
        candidateFileCount: Int = 8
    ) -> ProviderSnapshot {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sessionsDir.path, isDirectory: &isDir), isDir.boolValue,
              let enumerator = fm.enumerator(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else {
            return ProviderSnapshot(provider: .codex, windows: [], sourceExists: false, lastFileChange: nil, freshness: .stale)
        }

        var files: [(url: URL, mtime: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]), let m = values.contentModificationDate {
                files.append((url, m))
            }
        }
        guard !files.isEmpty else {
            return ProviderSnapshot(provider: .codex, windows: [], sourceExists: false, lastFileChange: nil, freshness: .stale)
        }
        files.sort { $0.mtime > $1.mtime }

        for candidate in files.prefix(candidateFileCount) {
            guard let content = try? String(contentsOf: candidate.url, encoding: .utf8) else { continue }
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
            for rawLine in lines.reversed() {
                guard rawLine.contains("rate_limits"),
                      let data = rawLine.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(CodexLine.self, from: data),
                      let rl = decoded.payload?.rate_limits,
                      rl.primary != nil || rl.secondary != nil
                else { continue }

                let freshness: FreshnessState = now.timeIntervalSince(candidate.mtime) > staleAfter ? .stale : .fresh
                var windows: [UsageWindow] = []
                if let p = rl.primary {
                    windows.append(makeWindow(label: labelFor(minutes: p.window_minutes), window: p))
                }
                if let s = rl.secondary {
                    windows.append(makeWindow(label: labelFor(minutes: s.window_minutes), window: s))
                }
                return ProviderSnapshot(provider: .codex, windows: windows, sourceExists: true, lastFileChange: candidate.mtime, freshness: freshness)
            }
        }

        return ProviderSnapshot(provider: .codex, windows: [], sourceExists: true, lastFileChange: files.first?.mtime, freshness: .stale)
    }

    private static func makeWindow(label: String, window: CodexRateLimitWindow) -> UsageWindow {
        let resetDate = window.resets_at.map { Date(timeIntervalSince1970: Double($0)) }
        return UsageWindow(
            provider: .codex,
            label: label,
            usedPercent: window.used_percent,
            resetDate: resetDate,
            resetKind: resetDate != nil ? .exact : .unknown
        )
    }

    private static func labelFor(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)분" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)일" }
        if minutes % 60 == 0 { return "\(minutes / 60)시간" }
        return "\(minutes)분"
    }
}
