namespace PotatokenHub.Core;

public enum Provider
{
    Claude,
    Codex,
}

public static class ProviderExtensions
{
    public static string DisplayName(this Provider provider) => provider switch
    {
        Provider.Claude => "Claude",
        _ => "Codex",
    };
}

public enum Freshness
{
    Fresh,
    Stale,
}

public enum ResetKind
{
    Exact,
    Estimated,
    Unknown,
}

public sealed record UsageWindow(
    Provider Provider,
    string Label,
    int WindowMinutes,
    double? UsedPercent,
    DateTime? ResetDate,
    ResetKind ResetKind)
{
    public string Id => $"{Provider.DisplayName()}-{Label}";

    public double? RemainingPercent
    {
        get
        {
            if (UsedPercent is not { } used || double.IsNaN(used) || double.IsInfinity(used)) return null;
            if (used < 0 || used > 100) return null;
            return Math.Clamp(100 - used, 0, 100);
        }
    }
}

public sealed record ProviderSnapshot(
    Provider Provider,
    IReadOnlyList<UsageWindow> Windows,
    bool SourceExists,
    DateTime? LastFileChange,
    Freshness Freshness)
{
    public static ProviderSnapshot Empty(Provider provider) =>
        new(provider, Array.Empty<UsageWindow>(), false, null, Freshness.Stale);

    /// <summary>
    /// The long and short window of a two-window provider, longest first. Picked
    /// by span rather than by label so it doesn't depend on the order the reader
    /// happens to build them in.
    /// </summary>
    public (UsageWindow Base, UsageWindow Overlay)? PairedWindows()
    {
        if (Windows.Count != 2) return null;
        var sorted = Windows.OrderByDescending(w => w.WindowMinutes).ToList();
        return (sorted[0], sorted[1]);
    }
}
