using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using PotatokenHub.Core;

namespace PotatokenHub;

/// <summary>
/// The tray icon is drawn rather than loaded, so it can carry the two live
/// percentages the way the macOS menu bar shows them as text. A Windows tray
/// slot is far narrower than a menu bar, so the two providers stack instead of
/// sitting side by side.
/// </summary>
public static class TrayBadge
{
    // Windows normally displays a tray slot at 16 logical pixels. Drawing a
    // 32px bitmap made Windows shrink the already-small text a second time.
    private const int Size = 16;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);

    public static Icon Render(IReadOnlyList<(Provider Provider, double? Remaining)> segments)
    {
        if (segments.Count == 0)
        {
            var executable = Environment.ProcessPath;
            return executable is not null && Icon.ExtractAssociatedIcon(executable) is { } icon
                ? icon
                : (Icon)SystemIcons.Application.Clone();
        }

        using var bitmap = new Bitmap(Size, Size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);

            if (segments.Count == 1)
            {
                // With one provider enabled, do not leave half the tray slot
                // empty. The percentage gets the entire icon and scales up to
                // the largest bold size that still fits values such as 100.
                DrawValue(g, new Rectangle(0, -1, Size, Size + 2),
                    segments[0].Remaining, ColorFor(segments[0].Provider), 15f);
            }
            else
            {
                // Deliberately overlap each row by one pixel. This gives each
                // number a 9px-tall drawing area rather than two cramped 8px
                // boxes, while keeping the pair visually centred in 16px.
                DrawValue(g, new Rectangle(0, -1, Size, 10),
                    segments[0].Remaining, ColorFor(segments[0].Provider), 11f);
                DrawValue(g, new Rectangle(0, 7, Size, 10),
                    segments[1].Remaining, ColorFor(segments[1].Provider), 11f);
            }
        }

        // Icon.FromHandle does not own the handle, so the GDI icon it wraps has
        // to be cloned and the original destroyed or the app leaks one icon per
        // refresh — that is every 15 seconds, all day.
        var handle = bitmap.GetHicon();
        try
        {
            using var temp = Icon.FromHandle(handle);
            return (Icon)temp.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    private static Color ColorFor(Provider provider) => provider == Provider.Claude
        ? Color.FromArgb(0xD9, 0x77, 0x57)
        : Color.FromArgb(0xBD, 0xBD, 0xC4);

    /// <summary>
    /// Draws one bold value at the largest font size that fits its slot.
    ///
    /// The colour is the provider's own — Claude orange, Codex grey — and does
    /// not track usage. With two bare numbers stacked and nothing else to tell
    /// them apart, the colour is carrying the identity, so it has to stay put.
    /// </summary>
    private static void DrawValue(Graphics g, Rectangle bounds, double? value, Color color, float preferredSize)
    {
        var text = value is { } v ? ((int)v).ToString() : "—";
        const System.Windows.Forms.TextFormatFlags flags =
            System.Windows.Forms.TextFormatFlags.HorizontalCenter |
            System.Windows.Forms.TextFormatFlags.VerticalCenter |
            System.Windows.Forms.TextFormatFlags.SingleLine |
            System.Windows.Forms.TextFormatFlags.NoPadding |
            System.Windows.Forms.TextFormatFlags.NoPrefix;

        // Arial Bold remains visibly heavier than the default Segoe UI at this
        // extremely small size. Fit each value independently so 100 never gets
        // clipped while ordinary one- and two-digit values use all available
        // space.
        for (var size = preferredSize; size >= 6f; size -= 0.5f)
        {
            using var font = new Font("Arial", size, FontStyle.Bold, GraphicsUnit.Pixel);
            var measured = System.Windows.Forms.TextRenderer.MeasureText(text, font, bounds.Size, flags);
            if (measured.Width > bounds.Width || measured.Height > bounds.Height) continue;

            System.Windows.Forms.TextRenderer.DrawText(g, text, font, bounds, color, flags);
            return;
        }

        // Defensive fallback for an unexpected font-metrics environment.
        using var fallback = new Font("Arial", 6f, FontStyle.Bold, GraphicsUnit.Pixel);
        System.Windows.Forms.TextRenderer.DrawText(g, text, fallback, bounds, color, flags);
    }

    public static string Tooltip(IReadOnlyList<ProviderSnapshot> snapshots)
    {
        static string Part(ProviderSnapshot snapshot)
        {
            var name = snapshot.Provider.DisplayName();
            var value = UsageModel.ShortestWindowRemaining(snapshot);
            return value is { } v ? $"{name} {(int)v}%" : $"{name} —";
        }

        return snapshots.Count == 0
            ? "potatoken hub"
            : string.Join("  ·  ", snapshots.Select(Part));
    }
}
