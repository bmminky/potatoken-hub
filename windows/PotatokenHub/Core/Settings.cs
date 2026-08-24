using System.IO;
using System.Text.Json;

namespace PotatokenHub.Core;

/// <summary>
/// A small JSON file next to the app's other roaming data, standing in for the
/// macOS build's UserDefaults.
/// </summary>
public static class Settings
{
    private sealed class Model
    {
        public string? Language { get; set; }
        public bool AlwaysOnTop { get; set; } = true;
        public double? PanelLeft { get; set; }
        public double? PanelTop { get; set; }
        public double PanelWidth { get; set; }
        public double PanelHeight { get; set; }
    }

    private static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "potatoken hub",
        "settings.json");

    private static Model? _cache;

    private static Model Current
    {
        get
        {
            if (_cache is not null) return _cache;
            try
            {
                if (File.Exists(Path))
                {
                    _cache = JsonSerializer.Deserialize<Model>(File.ReadAllText(Path));
                }
            }
            catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
            {
                // A corrupt or unreadable settings file should not stop the app
                // from starting; fall back to defaults.
            }
            return _cache ??= new Model();
        }
    }

    private static void Save()
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            File.WriteAllText(Path, JsonSerializer.Serialize(Current));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
        }
    }

    public static L.Language LanguagePreference
    {
        get => Enum.TryParse<L.Language>(Current.Language, out var value) ? value : L.Language.System;
        set
        {
            Current.Language = value.ToString();
            Save();
        }
    }

    public static bool AlwaysOnTop
    {
        get => Current.AlwaysOnTop;
        set
        {
            Current.AlwaysOnTop = value;
            Save();
        }
    }

    public static (double Left, double Top)? PanelPosition
    {
        get => Current.PanelLeft is { } left && Current.PanelTop is { } top ? (left, top) : null;
        set
        {
            Current.PanelLeft = value?.Left;
            Current.PanelTop = value?.Top;
            Save();
        }
    }

    public static (double Width, double Height)? PanelSize
    {
        get => Current.PanelWidth > 0 && Current.PanelHeight > 0
            ? (Current.PanelWidth, Current.PanelHeight)
            : null;
        set
        {
            Current.PanelWidth = value?.Width ?? 0;
            Current.PanelHeight = value?.Height ?? 0;
            Save();
        }
    }
}
