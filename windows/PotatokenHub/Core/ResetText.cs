namespace PotatokenHub.Core;

/// <summary>
/// When a window resets, phrased relative to now.
/// </summary>
public static class ResetText
{
    public static string? Of(UsageWindow window, DateTime? nowOverride = null)
    {
        if (window.ResetDate is not { } date) return null;
        var now = nowOverride ?? DateTime.Now;
        var relative = Relative(date - now);
        return L.Resolved switch
        {
            L.Language.Korean => $"리셋 {relative}",
            L.Language.Japanese => $"リセット {relative}",
            L.Language.Chinese => $"重置 {relative}",
            _ => $"Resets {relative}",
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
