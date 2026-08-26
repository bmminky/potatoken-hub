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
    public IReadOnlyList<Provider> DisplayedProviders => _displayedProviders;

    private List<Provider> _displayedProviders = [];

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
        UpdateDisplayedProviders();
    }

    public ProviderVisibility VisibilityFor(Provider provider) => Settings.VisibilityFor(provider);

    public void SetVisibility(Provider provider, ProviderVisibility visibility)
    {
        if (VisibilityFor(provider) == visibility) return;
        Settings.SetVisibility(provider, visibility);
        UpdateDisplayedProviders();
    }

    public bool IsDisplayed(Provider provider) => _displayedProviders.Contains(provider);

    public ProviderSnapshot SnapshotFor(Provider provider) =>
        provider == Provider.Claude ? Claude : Codex;

    private void UpdateDisplayedProviders()
    {
        var next = Enum.GetValues<Provider>()
            .Where(provider =>
            {
                var snapshot = SnapshotFor(provider);
                return VisibilityFor(provider) switch
                {
                    ProviderVisibility.Automatic => snapshot.SourceExists,
                    ProviderVisibility.AlwaysShow => true,
                    ProviderVisibility.Hidden => false,
                    _ => false,
                };
            })
            .ToList();

        if (_displayedProviders.SequenceEqual(next)) return;
        _displayedProviders = next;
        Notify(nameof(DisplayedProviders));
    }

    /// <summary>
    /// Remaining percentage for the shortest reported window, normally the
    /// five-hour allowance. Used only by the tray icon and tooltip.
    /// </summary>
    public static double? ShortestWindowRemaining(ProviderSnapshot snapshot) => snapshot.Windows
        .Where(w => w.RemainingPercent is not null)
        .OrderBy(w => w.WindowMinutes)
        .FirstOrDefault()?.RemainingPercent;

    private void Notify([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
