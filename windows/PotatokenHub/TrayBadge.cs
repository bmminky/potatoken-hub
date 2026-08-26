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

    public static Icon Render(double? claude, double? codex)
    {
        using var bitmap = new Bitmap(Size, Size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);

            DrawRow(g, y: 0, value: claude, color: Color.FromArgb(0xD9, 0x77, 0x57));
            DrawRow(g, y: 8, value: codex, color: Color.FromArgb(0xBD, 0xBD, 0xC4));
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

    /// <summary>
    /// One provider's number, filling its half of the slot.
    ///
    /// The colour is the provider's own — Claude orange, Codex grey — and does
    /// not track usage. With two bare numbers stacked and nothing else to tell
    /// them apart, the colour is carrying the identity, so it has to stay put.
    /// </summary>
    private static void DrawRow(Graphics g, int y, double? value, Color color)
    {
        var text = value is { } v ? ((int)v).ToString() : "—";

        // No accent stripe and no percent sign: at 16px a tray slot has room
        // for the digits or for decoration, not both, and the digits are the
        // part being read. Dropping the stripe also buys the glyphs the full
        // width, so they can be set larger.
        using var valueFont = new Font("Segoe UI", 10f, FontStyle.Bold, GraphicsUnit.Pixel);
        using var valueBrush = new SolidBrush(color);
        using var format = new StringFormat(StringFormat.GenericTypographic)
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center,
            FormatFlags = StringFormatFlags.NoWrap,
        };
        g.DrawString(text, valueFont, valueBrush, new RectangleF(0, y, Size, 8), format);
    }

    public static string Tooltip(ProviderSnapshot claude, ProviderSnapshot codex)
    {
        static string Part(ProviderSnapshot snapshot)
        {
            var name = snapshot.Provider.DisplayName();
            var value = UsageModel.ShortestWindowRemaining(snapshot);
            return value is { } v ? $"{name} {(int)v}%" : $"{name} —";
        }

        return $"{Part(claude)}  ·  {Part(codex)}";
    }
}
