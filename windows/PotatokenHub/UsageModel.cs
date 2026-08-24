using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using PotatokenHub.Core;

namespace PotatokenHub;

public sealed class UsageModel : INotifyPropertyChanged
{
    private readonly DispatcherTimer _timer;

    public ProviderSnapshot Claude { get; private set; } = ProviderSnapshot.Empty(Provider.Claude);
    public ProviderSnapshot Codex { get; private set; } = ProviderSnapshot.Empty(Provider.Codex);
    public DateTime? LastUpdated { get; private set; }

    public event PropertyChangedEventHandler? PropertyChanged;

    public UsageModel()
    {
        Refresh();
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
        _timer.Tick += (_, _) => Refresh();
        _timer.Start();
    }

    public void Refresh()
    {
        Claude = ClaudeUsageReader.ReadSnapshot();
        Codex = CodexUsageReader.ReadSnapshot();
        LastUpdated = DateTime.Now;

        Notify(nameof(Claude));
        Notify(nameof(Codex));
        Notify(nameof(LastUpdated));
    }

    /// <summary>The tightest remaining percentage a provider reports, or null.</summary>
    public static double? Tightest(ProviderSnapshot snapshot) => snapshot.Windows
        .Select(w => w.RemainingPercent)
        .Where(r => r is not null)
        .DefaultIfEmpty(null)
        .Min();

    private void Notify([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
