namespace PotatokenHub.Core;

/// <summary>
/// Fires a notification the moment a window hits 0% remaining, and again when it
/// resets back up. Each event is keyed by window id so it fires at most once per
/// exhaustion/reset cycle, not once per 15-second poll.
/// </summary>
public sealed class AlertManager
{
    public static readonly AlertManager Shared = new();

    /// <summary>Set by the tray app; takes (title, body).</summary>
    public Action<string, string>? Notify { get; set; }

    private readonly object _lock = new();
    private readonly Dictionary<string, double> _lastRemaining = new();
    private readonly HashSet<string> _exhaustionAlerted = new();

    private AlertManager() { }

    public void Process(UsageWindow window)
    {
        if (window.RemainingPercent is not { } remaining) return;

        double? previous;
        bool alreadyAlerted;
        lock (_lock)
        {
            previous = _lastRemaining.TryGetValue(window.Id, out var p) ? p : null;
            _lastRemaining[window.Id] = remaining;
            alreadyAlerted = _exhaustionAlerted.Contains(window.Id);
        }

        var name = window.Provider.DisplayName();

        if (remaining <= 0.01)
        {
            if (alreadyAlerted) return;
            lock (_lock) _exhaustionAlerted.Add(window.Id);

            Notify?.Invoke(
                L.T(
                    ko: $"{name} {window.Label} 소진",
                    en: $"{name} {window.Label} exhausted",
                    ja: $"{name} {window.Label} 使い切り",
                    zh: $"{name} {window.Label} 已用完"),
                L.T(
                    ko: "사용 가능한 한도가 0%입니다.",
                    en: "You're out of quota for this window.",
                    ja: "この期間の利用可能な割り当てが0%になりました。",
                    zh: "该时间段的可用配额已为0%。"));
        }
        else
        {
            if (previous is { } prev && prev <= 0.01)
            {
                var left = (int)remaining;
                Notify?.Invoke(
                    L.T(
                        ko: $"{name} {window.Label} 리셋",
                        en: $"{name} {window.Label} reset",
                        ja: $"{name} {window.Label} リセット",
                        zh: $"{name} {window.Label} 已重置"),
                    L.T(
                        ko: $"한도가 초기화되었습니다. 남은 한도 {left}%.",
                        en: $"Your quota has reset. {left}% remaining.",
                        ja: $"割り当てがリセットされました。残り{left}%。",
                        zh: $"配额已重置。剩余{left}%。"));
            }
            lock (_lock) _exhaustionAlerted.Remove(window.Id);
        }
    }
}
