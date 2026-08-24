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

        return provider == Provider.Claude
            ? Burst(size, accent)
            : CodeMark(size, accent);
    }

    /// <summary>Spokes radiating from a common center, like an asterisk.</summary>
    private static UIElement Burst(double size, Brush brush)
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

    private static UIElement CodeMark(double size, Brush brush) => new TextBlock
    {
        Text = "</>",
        FontSize = size * 0.82,
        FontWeight = FontWeights.SemiBold,
        Foreground = brush,
        VerticalAlignment = VerticalAlignment.Center,
    };
}
