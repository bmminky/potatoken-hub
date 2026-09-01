using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using PotatokenHub.Core;

namespace PotatokenHub;

/// <summary>
/// Small mark drawn in place of a provider's name. Hand-drawn approximations,
/// not official brand assets — no logo files are bundled.
/// </summary>
public static class ProviderMark
{
    public static UIElement Create(Provider provider, double size)
    {
        var accent = new SolidColorBrush(UsagePalette.AccentFor(provider));
        var mark = provider == Provider.Claude ? Burst(size, accent) : CodeMark(size, accent);
        mark.HorizontalAlignment = HorizontalAlignment.Center;
        mark.VerticalAlignment = VerticalAlignment.Center;

        // Burst is drawn to an exact size x size box, but CodeMark's "</>"
        // text measures wider than that at the same font size — left as-is,
        // whatever follows the mark (a provider name, a percentage) started
        // further right on Codex's row than on Claude's. Pad both into a
        // shared box sized to the wider of the two so they start at the
        // same x regardless of provider.
        var width = Math.Max(size, MeasureWidth("</>", size * 0.82, FontWeights.SemiBold));
        return new Grid { Width = width, Height = size, Children = { mark } };
    }

    private static double MeasureWidth(string text, double fontSize, FontWeight weight)
    {
        var typeface = new Typeface(
            new FontFamily("Segoe UI"), FontStyles.Normal, weight, FontStretches.Normal);
        var formatted = new FormattedText(
            text,
            System.Globalization.CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            typeface,
            fontSize,
            Brushes.Black,
            1.0);
        return formatted.Width;
    }

    /// <summary>Spokes radiating from a common center, like an asterisk.</summary>
    private static FrameworkElement Burst(double size, Brush brush)
    {
        const int spokes = 11;
        var outer = size / 2;
        var inner = outer * 0.16;
        var center = new Point(outer, outer);

        var geometry = new GeometryGroup();
        for (var i = 0; i < spokes; i++)
        {
            var angle = (double)i / spokes * 2 * Math.PI - Math.PI / 2;
            geometry.Children.Add(new LineGeometry(
                new Point(center.X + Math.Cos(angle) * inner, center.Y + Math.Sin(angle) * inner),
                new Point(center.X + Math.Cos(angle) * outer, center.Y + Math.Sin(angle) * outer)));
        }

        return new System.Windows.Shapes.Path
        {
            Data = geometry,
            Stroke = brush,
            StrokeThickness = size * 0.13,
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
            Width = size,
            Height = size,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    private static FrameworkElement CodeMark(double size, Brush brush) => new TextBlock
    {
        Text = "</>",
        FontSize = size * 0.82,
        FontWeight = FontWeights.SemiBold,
        Foreground = brush,
        VerticalAlignment = VerticalAlignment.Center,
    };
}
