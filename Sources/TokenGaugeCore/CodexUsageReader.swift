import Foundation

struct CodexRateLimitWindow: Decodable {
    let used_percent: Double
    let window_minutes: Int
    let resets_at: Int64?
}

struct CodexRateLimits: Decodable {
    let limit_id: String?
    let limit_name: String?
    let plan_type: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

struct CodexPayload: Decodable {
    let type: String?
    let rate_limits: CodexRateLimits?
}

struct CodexLine: Decodable {
    let timestamp: String?
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
        candidateFileCount: Int = .max
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

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let wholeSecondFormatter = ISO8601DateFormatter()
        wholeSecondFormatter.formatOptions = [.withInternetDateTime]
        let decoder = JSONDecoder()
        var latest: (date: Date, file: (url: URL, mtime: Date), limits: CodexRateLimits)?

        for candidate in files.prefix(max(0, candidateFileCount)) {
            // A record cannot be newer than the file containing it. Once the
            // remaining files predate our best record, they cannot beat it.
            if let latest, candidate.mtime < latest.date { break }
            guard let record = newestRateLimits(
                in: candidate.url,
                noLaterThan: now.addingTimeInterval(60),
                decoder: decoder,
                fractionalFormatter: fractionalFormatter,
                wholeSecondFormatter: wholeSecondFormatter
            ) else { continue }
            if latest == nil || record.date > latest!.date {
                latest = (record.date, candidate, record.limits)
            }
        }

        if let latest {
            let freshness: FreshnessState = now.timeIntervalSince(latest.date) <= staleAfter ? .fresh : .stale
            var windows: [UsageWindow] = []
            if let p = latest.limits.primary {
                windows.append(makeWindow(label: labelFor(minutes: p.window_minutes), window: p))
            }
            if let s = latest.limits.secondary {
                windows.append(makeWindow(label: labelFor(minutes: s.window_minutes), window: s))
            }
            return ProviderSnapshot(
                provider: .codex,
                windows: windows,
                sourceExists: true,
                lastFileChange: latest.file.mtime,
                lastRecordDate: latest.date,
                freshness: freshness,
                codexPlan: plan(from: latest.limits.plan_type)
            )
        }

        return ProviderSnapshot(provider: .codex, windows: [], sourceExists: true, lastFileChange: files.first?.mtime, freshness: .stale)
    }

    private static func plan(from rawValue: String?) -> CodexPlan? {
        guard let value = rawValue?.lowercased() else { return nil }
        if value == "plus" { return .plus }
        // Codex currently reports the Pro 5x tier as "prolite".
        if value == "pro" || value == "prolite" { return .pro }
        return nil
    }

    /// Rollout JSONL is append-ordered. Read backward in chunks so even a
    /// large conversation file costs only its tail, not its entire history.
    private static func newestRateLimits(
        in url: URL,
        noLaterThan latestAllowed: Date,
        decoder: JSONDecoder,
        fractionalFormatter: ISO8601DateFormatter,
        wholeSecondFormatter: ISO8601DateFormatter
    ) -> (date: Date, limits: CodexRateLimits)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard var offset = try? handle.seekToEnd() else { return nil }
        var unfinishedLine = Data()
        let marker = Data("\"rate_limits\"".utf8)

        func decode(_ line: Data) -> (date: Date, limits: CodexRateLimits)? {
            guard line.range(of: marker) != nil,
                  let decoded = try? decoder.decode(CodexLine.self, from: line),
                  let timestamp = decoded.timestamp,
                  let date = fractionalFormatter.date(from: timestamp) ?? wholeSecondFormatter.date(from: timestamp),
                  date <= latestAllowed,
                  let limits = decoded.payload?.rate_limits,
                  limits.limit_id == nil || limits.limit_id?.lowercased() == "codex",
                  !(limits.limit_name?.localizedCaseInsensitiveContains("Codex-Spark") ?? false),
                  limits.primary != nil || limits.secondary != nil
            else { return nil }
            return (date, limits)
        }

        while offset > 0 {
            let count = Int(min(offset, 64 * 1024))
            offset -= UInt64(count)
            do {
                try handle.seek(toOffset: offset)
                guard let chunk = try handle.read(upToCount: count) else { return nil }
                var combined = chunk
                combined.append(unfinishedLine)
                var end = combined.endIndex
                while let newline = combined[..<end].lastIndex(of: 0x0A) {
                    let line = Data(combined[combined.index(after: newline)..<end])
                    if let record = decode(line) { return record }
                    end = newline
                }
                unfinishedLine = Data(combined[..<end])
            } catch {
                return nil
            }
        }
        return decode(unfinishedLine)
    }

    private static func makeWindow(label: String, window: CodexRateLimitWindow) -> UsageWindow {
        let resetDate = window.resets_at.map { Date(timeIntervalSince1970: Double($0)) }
        return UsageWindow(
            provider: .codex,
            label: label,
            windowMinutes: window.window_minutes,
            usedPercent: window.used_percent,
            resetDate: resetDate,
            resetKind: resetDate != nil ? .exact : .unknown
        )
    }

    private static func labelFor(minutes: Int) -> String {
        // A 7-day window is the weekly allowance, and reads better named that
        // way — and matches how Claude's own weekly window is labelled.
        if minutes == 7 * 24 * 60 { return L.t(ko: "주간", en: "Weekly", ja: "週間", zh: "每周") }
        if minutes < 60 { return L.t(ko: "\(minutes)분", en: "\(minutes)m", ja: "\(minutes)分", zh: "\(minutes)分钟") }
        if minutes % 1440 == 0 { return L.t(ko: "\(minutes / 1440)일", en: "\(minutes / 1440)d", ja: "\(minutes / 1440)日", zh: "\(minutes / 1440)天") }
        if minutes % 60 == 0 { return L.t(ko: "\(minutes / 60)시간", en: "\(minutes / 60)h", ja: "\(minutes / 60)時間", zh: "\(minutes / 60)小时") }
        return L.t(ko: "\(minutes)분", en: "\(minutes)m", ja: "\(minutes)分", zh: "\(minutes)分钟")
    }
}
