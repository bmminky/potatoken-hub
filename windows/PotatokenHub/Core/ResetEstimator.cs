namespace PotatokenHub.Core;

public readonly record struct UsageSample(DateTime Time, int Value);

/// <summary>
/// Claude's local history has no reset timestamp, so the next reset is inferred
/// from past drops in usage (a drop means the window rolled over) plus the known
/// window length. Codex reports resets_at directly and does not need this.
/// </summary>
public static class ResetEstimator
{
    public static DateTime? EstimateNextReset(
        IReadOnlyList<UsageSample> samples,
        TimeSpan windowDuration,
        DateTime now,
        int dropThreshold = 3)
    {
        if (samples.Count < 2) return null;
        var sorted = samples.OrderBy(s => s.Time).ToList();

        DateTime? lastResetAnchor = null;
        for (var i = 1; i < sorted.Count; i++)
        {
            if (sorted[i].Value < sorted[i - 1].Value - dropThreshold)
            {
                lastResetAnchor = sorted[i].Time;
            }
        }

        if (lastResetAnchor is not { } anchor) return null;
        while (anchor + windowDuration < now)
        {
            anchor += windowDuration;
        }
        return anchor + windowDuration;
    }
}
