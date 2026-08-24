using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PotatokenHub.Core;

public static class CodexUsageReader
{
    private static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(15);

    private sealed class RateLimitWindow
    {
        [JsonPropertyName("used_percent")] public double UsedPercent { get; set; }
        [JsonPropertyName("window_minutes")] public int WindowMinutes { get; set; }
        [JsonPropertyName("resets_at")] public long? ResetsAt { get; set; }
    }

    private sealed class RateLimits
    {
        [JsonPropertyName("primary")] public RateLimitWindow? Primary { get; set; }
        [JsonPropertyName("secondary")] public RateLimitWindow? Secondary { get; set; }
    }

    private sealed class Payload
    {
        [JsonPropertyName("rate_limits")] public RateLimits? RateLimits { get; set; }
    }

    private sealed class Line
    {
        [JsonPropertyName("payload")] public Payload? Payload { get; set; }
    }

    /// <summary>
    /// Where to look for session logs, most likely first.
    ///
    /// CODEX_HOME wins when set, since that's how the CLI itself is relocated;
    /// it may list several roots separated by ';' or ','. Otherwise the usual
    /// ~/.codex layout, which is the same on Windows as on macOS.
    ///
    /// Both the live and the archived directory are searched: the CLI moves
    /// finished sessions into archived_sessions, so looking only at sessions/
    /// can leave the newest record behind and report a days-old snapshot as
    /// though it were current.
    /// </summary>
    public static IReadOnlyList<string> DefaultSessionsDirs()
    {
        var roots = new List<string>();

        var codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
        if (!string.IsNullOrWhiteSpace(codexHome))
        {
            roots.AddRange(codexHome
                .Split([';', ','], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
        }
        else
        {
            roots.Add(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".codex"));
        }

        return roots
            .SelectMany(root => new[]
            {
                Path.Combine(root, "sessions"),
                Path.Combine(root, "archived_sessions"),
            })
            .ToList();
    }

    public static ProviderSnapshot ReadSnapshot(
        IReadOnlyList<string>? sessionsDirs = null,
        DateTime? nowOverride = null,
        int candidateFileCount = 8)
    {
        sessionsDirs ??= DefaultSessionsDirs();
        var now = nowOverride ?? DateTime.Now;

        var present = sessionsDirs.Where(Directory.Exists).ToList();
        if (present.Count == 0) return ProviderSnapshot.Empty(Provider.Codex);

        // Pooled across every directory before sorting, so the newest record
        // wins wherever it happens to live.
        var files = new List<FileInfo>();
        foreach (var dir in present)
        {
            try
            {
                files.AddRange(new DirectoryInfo(dir)
                    .EnumerateFiles("*.jsonl", SearchOption.AllDirectories));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                continue;
            }
        }
        files = files.OrderByDescending(f => f.LastWriteTime).ToList();

        if (files.Count == 0) return ProviderSnapshot.Empty(Provider.Codex);

        foreach (var candidate in files.Take(candidateFileCount))
        {
            string[] lines;
            try
            {
                lines = File.ReadAllLines(candidate.FullName);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                continue;
            }

            for (var i = lines.Length - 1; i >= 0; i--)
            {
                var raw = lines[i];
                if (!raw.Contains("rate_limits", StringComparison.Ordinal)) continue;

                RateLimits? limits;
                try
                {
                    limits = JsonSerializer.Deserialize<Line>(raw)?.Payload?.RateLimits;
                }
                catch (JsonException)
                {
                    continue;
                }
                if (limits is null || (limits.Primary is null && limits.Secondary is null)) continue;

                var freshness = now - candidate.LastWriteTime > StaleAfter ? Freshness.Stale : Freshness.Fresh;
                var windows = new List<UsageWindow>();
                if (limits.Primary is { } p) windows.Add(MakeWindow(p));
                if (limits.Secondary is { } s) windows.Add(MakeWindow(s));

                return new ProviderSnapshot(Provider.Codex, windows, true, candidate.LastWriteTime, freshness);
            }
        }

        return new ProviderSnapshot(Provider.Codex, Array.Empty<UsageWindow>(), true, files[0].LastWriteTime, Freshness.Stale);
    }

    private static UsageWindow MakeWindow(RateLimitWindow window)
    {
        var resetDate = window.ResetsAt is { } epoch
            ? DateTimeOffset.FromUnixTimeSeconds(epoch).LocalDateTime
            : (DateTime?)null;

        return new UsageWindow(
            Provider.Codex,
            LabelFor(window.WindowMinutes),
            window.WindowMinutes,
            window.UsedPercent,
            resetDate,
            resetDate is not null ? ResetKind.Exact : ResetKind.Unknown);
    }

    private static string LabelFor(int minutes)
    {
        // A 7-day window is the weekly allowance, and reads better named that
        // way — and matches how Claude's own weekly window is labelled.
        if (minutes == 7 * 24 * 60) return L.T(ko: "주간", en: "Weekly", ja: "週間", zh: "每周");
        if (minutes < 60) return L.T($"{minutes}분", $"{minutes}m", $"{minutes}分", $"{minutes}分钟");
        if (minutes % 1440 == 0)
        {
            var d = minutes / 1440;
            return L.T($"{d}일", $"{d}d", $"{d}日", $"{d}天");
        }
        if (minutes % 60 == 0)
        {
            var h = minutes / 60;
            return L.T($"{h}시간", $"{h}h", $"{h}時間", $"{h}小时");
        }
        return L.T($"{minutes}분", $"{minutes}m", $"{minutes}分", $"{minutes}分钟");
    }
}
