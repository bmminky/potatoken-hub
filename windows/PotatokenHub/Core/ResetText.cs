namespace PotatokenHub.Core;

/// <summary>
/// When a window resets, phrased relative to now. Estimated times carry an
/// "approximately" qualifier, since Claude's local history has no reset
/// timestamp to read.
/// </summary>
public static class ResetText
{
    public static string? Of(UsageWindow window, DateTime? nowOverride = null)
    {
        if (window.ResetDate is not { } date) return null;
        var now = nowOverride ?? DateTime.Now;
        var relative = Relative(date - now);
        // Only short windows carry the qualifier. Over a week the estimate's
        // error is small next to the span, so it's noise rather than useful
        // precision.
        var estimated = window.ResetKind == ResetKind.Estimated && window.WindowMinutes < 24 * 60;

        return L.Resolved switch
        {
            // 약 qualifies the duration, not the reset itself, so it belongs next
            // to the time: "리셋 약 1시간 후", not "약 리셋 1시간 후".
            L.Language.Korean => $"리셋 {(estimated ? "약 " : "")}{relative}",
            L.Language.Japanese => $"リセット {(estimated ? "約" : "")}{relative}",
            L.Language.Chinese => $"重置 {(estimated ? "大约" : "")}{relative}",
            _ => $"Resets {relative}{(estimated ? " (est.)" : "")}",
        };
    }

    private static string Relative(TimeSpan delta)
    {
        var past = delta < TimeSpan.Zero;
        var abs = delta.Duration();

        var (value, unit) = abs.TotalMinutes < 60
            ? ((int)Math.Max(1, abs.TotalMinutes), Unit.Minute)
            : abs.TotalHours < 24
                ? ((int)abs.TotalHours, Unit.Hour)
                : ((int)abs.TotalDays, Unit.Day);

        return L.Resolved switch
        {
            L.Language.Korean => $"{value}{KoUnit(unit)} {(past ? "전" : "후")}",
            L.Language.Japanese => $"{value}{JaUnit(unit)}{(past ? "前" : "後")}",
            L.Language.Chinese => $"{value}{ZhUnit(unit)}{(past ? "前" : "后")}",
            _ => past ? $"{value} {EnUnit(unit, value)} ago" : $"in {value} {EnUnit(unit, value)}",
        };
    }

    private enum Unit { Minute, Hour, Day }

    private static string KoUnit(Unit u) => u switch { Unit.Minute => "분", Unit.Hour => "시간", _ => "일" };
    private static string JaUnit(Unit u) => u switch { Unit.Minute => "分", Unit.Hour => "時間", _ => "日" };
    private static string ZhUnit(Unit u) => u switch { Unit.Minute => "分钟", Unit.Hour => "小时", _ => "天" };

    private static string EnUnit(Unit u, int value)
    {
        var name = u switch { Unit.Minute => "min", Unit.Hour => "hr", _ => "day" };
        return value == 1 ? name : name + "s";
    }
}
