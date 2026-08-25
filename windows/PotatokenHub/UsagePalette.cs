using System.Windows.Media;

namespace PotatokenHub;

/// <summary>
/// The single definition of how much-is-left maps to a color, shared by the
/// panel and the tray badge — same thresholds and same values as the macOS build.
/// </summary>
public static class UsagePalette
{
    public enum Level
    {
        Plenty,
        Caution,
        Low,
        Unknown,
    }

    public static Level LevelOf(double? remaining) => remaining switch
    {
        null => Level.Unknown,
        >= 50 => Level.Plenty,
        >= 15 => Level.Caution,
        _ => Level.Low,
    };

    // pastel yellow #F5DB8C
    public static readonly Color Caution = Color.FromRgb(0xF5, 0xDB, 0x8C);
    // Muted to sit in the same family as the yellow and the Claude orange, but
    // kept saturated enough to still read as a warning.
    public static readonly Color Low = Color.FromRgb(0xDD, 0x4F, 0x45);

    /// <param name="plenty">The color to use when there's plenty left.</param>
    public static Color ColorFor(double? remaining, Color plenty) => LevelOf(remaining) switch
    {
        Level.Plenty => plenty,
        Level.Caution => Caution,
        Level.Low => Low,
        _ => Colors.Gray,
    };

    // Claude's fixed orange; Codex's neutral gray, picked for a dark tray/panel.
    public static readonly Color ClaudeAccent = Color.FromRgb(0xD9, 0x77, 0x57);
    public static readonly Color CodexAccent = Color.FromRgb(0xBD, 0xBD, 0xC4);
    // A deeper neutral used only for Codex's weekly fill, so the white
    // five-hour fill remains immediately distinguishable where they overlap.
    public static readonly Color CodexWeeklyGauge = Color.FromRgb(0x86, 0x86, 0x90);

    public static Color AccentFor(Core.Provider provider) =>
        provider == Core.Provider.Claude ? ClaudeAccent : CodexAccent;
}
