using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PotatokenHub.Core;

public static class ClaudeUsageReader
{
    private static readonly TimeSpan FiveHours = TimeSpan.FromHours(5);
    private static readonly TimeSpan Weekly = TimeSpan.FromDays(7);
    private static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(15);

    private sealed class Sample
    {
        [JsonPropertyName("t")] public long T { get; set; }
        [JsonPropertyName("u")] public Dictionary<string, int>? U { get; set; }
    }

    private sealed class HistoryFile
    {
        [JsonPropertyName("samples")] public List<Sample>? Samples { get; set; }
    }

    /// <summary>
    /// Where the Windows Claude desktop app keeps its usage history.
    ///
    /// %APPDATA%\Claude mirrors ~/Library/Application Support/Claude on macOS
    /// and covers the ordinary installer, but the Store packaged build redirects
    /// roaming data into its own container and some builds install per-machine
    /// instead, so several forms are tried before giving up. Checking only the
    /// first left the app reporting "No data" on installs that were working
    /// fine.
    /// </summary>
    public static IReadOnlyList<string> CandidatePaths()
    {
        var overridePath = Environment.GetEnvironmentVariable("POTATOKEN_CLAUDE_HISTORY");
        if (!string.IsNullOrWhiteSpace(overridePath)) return [overridePath];

        const string fileName = "plan-usage-history.json";
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        var paths = new List<string>
        {
            Path.Combine(roaming, "Claude", fileName),
            Path.Combine(roaming, "Claude-3p", fileName),
            Path.Combine(local, "Claude", fileName),
        };

        // The packaged build's container is named with a publisher hash that
        // varies per install, so it has to be matched rather than spelled out.
        try
        {
            var packages = Path.Combine(local, "Packages");
            if (Directory.Exists(packages))
            {
                paths.AddRange(Directory
                    .EnumerateDirectories(packages, "Claude_*")
                    .Select(dir => Path.Combine(dir, "LocalCache", "Roaming", "Claude", fileName)));
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // Leave the plain candidates to speak for themselves.
        }

        return paths;
    }

    /// <summary>The first candidate that exists, or the primary one if none do.</summary>
    public static string DefaultPath() =>
        CandidatePaths().FirstOrDefault(File.Exists) ?? CandidatePaths()[0];

    public static ProviderSnapshot ReadSnapshot(string? path = null, DateTime? nowOverride = null)
    {
        path ??= DefaultPath();
        var now = nowOverride ?? DateTime.Now;

        if (!File.Exists(path)) return ProviderSnapshot.Empty(Provider.Claude);

        List<Sample> samples;
        DateTime mtime;
        try
        {
            mtime = File.GetLastWriteTime(path);
            var file = JsonSerializer.Deserialize<HistoryFile>(File.ReadAllText(path));
            samples = file?.Samples ?? new List<Sample>();
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            return new ProviderSnapshot(Provider.Claude, Array.Empty<UsageWindow>(), true, null, Freshness.Stale);
        }

        if (samples.Count == 0)
        {
            return new ProviderSnapshot(Provider.Claude, Array.Empty<UsageWindow>(), true, mtime, Freshness.Stale);
        }

        var sorted = samples.OrderBy(s => s.T).ToList();
        var latest = sorted[^1];
        var freshness = now - mtime > StaleAfter ? Freshness.Stale : Freshness.Fresh;

        List<UsageSample> Series(string key) => sorted
            .Where(s => s.U is not null && s.U.ContainsKey(key))
            .Select(s => new UsageSample(DateTimeOffset.FromUnixTimeMilliseconds(s.T).LocalDateTime, s.U![key]))
            .ToList();

        double? Latest(string key) =>
            latest.U is not null && latest.U.TryGetValue(key, out var v) ? v : null;

        var fhReset = ResetEstimator.EstimateNextReset(Series("fh"), FiveHours, now);
        var sdReset = ResetEstimator.EstimateNextReset(Series("sd"), Weekly, now);

        var windows = new List<UsageWindow>
        {
            new(
                Provider.Claude,
                L.T(ko: "5시간", en: "5h", ja: "5時間", zh: "5小时"),
                5 * 60,
                Latest("fh"),
                fhReset,
                fhReset is not null ? ResetKind.Estimated : ResetKind.Unknown),
            new(
                Provider.Claude,
                L.T(ko: "주간", en: "Weekly", ja: "週間", zh: "每周"),
                7 * 24 * 60,
                Latest("sd"),
                sdReset,
                sdReset is not null ? ResetKind.Estimated : ResetKind.Unknown),
        };

        return new ProviderSnapshot(Provider.Claude, windows, true, mtime, freshness);
    }
}
