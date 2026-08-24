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
    private const int Size = 32;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);

    public static Icon Render(double? claude, double? codex)
    {
        using var bitmap = new Bitmap(Size, Size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.Clear(Color.Transparent);

            DrawRow(g, y: 0, label: "C", value: claude, accent: Color.FromArgb(0xD9, 0x77, 0x57));
            DrawRow(g, y: 16, label: "X", value: codex, accent: Color.FromArgb(0xBD, 0xBD, 0xC4));
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

    private static void DrawRow(Graphics g, int y, string label, double? value, Color accent)
    {
        using var labelFont = new Font("Segoe UI", 8.5f, FontStyle.Bold, GraphicsUnit.Pixel);
        using var valueFont = new Font("Segoe UI", 12f, FontStyle.Bold, GraphicsUnit.Pixel);

        using var labelBrush = new SolidBrush(accent);
        g.DrawString(label, labelFont, labelBrush, new PointF(-1, y + 3));

        var text = value is { } v ? ((int)v).ToString() : "—";
        using var valueBrush = new SolidBrush(ToDrawingColor(UsagePalette.ColorFor(value, System.Windows.Media.Colors.White)));
        g.DrawString(text, valueFont, valueBrush, new PointF(7, y + 1));
    }

    private static Color ToDrawingColor(System.Windows.Media.Color c) =>
        Color.FromArgb(c.A, c.R, c.G, c.B);

    public static string Tooltip(ProviderSnapshot claude, ProviderSnapshot codex)
    {
        static string Part(ProviderSnapshot snapshot)
        {
            var name = snapshot.Provider.DisplayName();
            var value = UsageModel.Tightest(snapshot);
            return value is { } v ? $"{name} {(int)v}%" : $"{name} —";
        }

        return $"{Part(claude)}  ·  {Part(codex)}";
    }
}
