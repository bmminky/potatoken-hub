using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using PotatokenHub.Core;

namespace PotatokenHub;

public partial class PanelWindow : Window
{
    // Includes 16pt transparent shadow space on every edge. Card itself stays
    // exactly 220x96 or 320x210; only the transparent window bounds grow.
    private static readonly Size SmallSize = new(252, 128);
    private static readonly Size LargeSize = new(352, 242);
    /// <summary>How far below the large preset still renders the large layout.</summary>
    private const double LargeTolerance = 24;

    private readonly UsageModel _model;

    public enum SizePreset
    {
        Small,
        Large,
    }

    public SizePreset ActivePreset => _activePreset;

    /// <summary>
    /// Moves to a preset, doing nothing if the panel is already there — so
    /// picking the current size from a menu doesn't replay the animation.
    /// </summary>
    public void ApplyPreset(SizePreset preset)
    {
        if (preset == _activePreset) return;
        _activePreset = preset;
        AnimateTo(SizeOf(_activePreset));
    }

    /// <summary>
    /// Which preset the user last chose. Held as state rather than read back off
    /// the window, because the point of tracking it is to recover when something
    /// else has already changed the size — inferring it from a size that's wrong
    /// just ratifies the wrong size.
    /// </summary>
    private SizePreset _activePreset = SizePreset.Small;

    /// <summary>Raised while the app is deliberately resizing.</summary>
    private bool _isPerformingOwnResize;

    /// <summary>Where the window sat at the previous mouse-down.</summary>
    private Point? _positionAtLastMouseDown;

    private Size SizeOf(SizePreset preset)
    {
        var count = _model.DisplayedProviders.Count;
        if (preset == SizePreset.Small)
        {
            return new Size(SmallSize.Width, count switch { 0 => 80, 1 => 88, _ => SmallSize.Height });
        }
        return new Size(LargeSize.Width, count switch { 0 => 142, 1 => 154, _ => LargeSize.Height });
    }

    private SizePreset PresetNearest(double width) =>
        width >= (SmallSize.Width + LargeSize.Width) / 2 ? SizePreset.Large : SizePreset.Small;

    public event Action? RightClicked;

    public PanelWindow(UsageModel model)
    {
        InitializeComponent();
        _model = model;
        _model.PropertyChanged += (_, e) => Dispatcher.Invoke(() =>
        {
            Render();
            if (e.PropertyName == nameof(UsageModel.DisplayedProviders))
            {
                AnimateTo(SizeOf(_activePreset));
            }
        });

        Width = SmallSize.Width;
        Height = SmallSize.Height;
        if (Settings.PanelSize is { } size)
        {
            Width = size.Width;
            Height = size.Height;
        }
        // A frame saved by an older build is the one place with no recorded
        // intent to consult, so snap it to whichever preset it's nearest.
        _activePreset = PresetNearest(Width);
        var preset = SizeOf(_activePreset);
        Width = preset.Width;
        Height = preset.Height;

        Topmost = Settings.AlwaysOnTop;
        SourceInitialized += (_, _) => RestorePosition();
        SizeChanged += (_, _) => Render();
        MouseRightButtonUp += (_, e) => { e.Handled = true; RightClicked?.Invoke(); };
        MouseLeftButtonDown += OnLeftButtonDown;
        Closing += (_, e) => { e.Cancel = true; Hide(); };

        Render();
    }

    private void RestorePosition()
    {
        var area = SystemParameters.WorkArea;
        if (Settings.PanelPosition is { } position)
        {
            Left = Math.Clamp(position.Left, area.Left, Math.Max(area.Left, area.Right - Width));
            Top = Math.Clamp(position.Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
        }
        else
        {
            Left = area.Right - Width - 16;
            Top = area.Top + 16;
        }
    }

    public void PersistPlacement()
    {
        Settings.PanelPosition = (Left, Top);
        Settings.PanelSize = (Width, Height);
    }

    private void OnLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        var previousPosition = _positionAtLastMouseDown;
        _positionAtLastMouseDown = new Point(Left, Top);

        // Dragging a window a long way is done in short grab-pull-release
        // strokes, and two grabs inside the double-click interval arrive as
        // ClickCount 2 — which resized the panel mid-drag. A real double-click
        // leaves the window where it was between the two clicks.
        if (e.ClickCount == 2 && !MovedSince(previousPosition))
        {
            ToggleSizePreset();
            return;
        }

        // Drag anywhere on the card, since the window has no title bar. The
        // resize grip handles its own hit-testing before this runs.
        try { DragMove(); }
        catch (InvalidOperationException) { }
    }

    public void ToggleSizePreset() =>
        ApplyPreset(_activePreset == SizePreset.Large ? SizePreset.Small : SizePreset.Large);

    private bool MovedSince(Point? previous)
    {
        if (previous is not { } p) return false;
        const double tolerance = 2;
        return Math.Abs(Left - p.X) > tolerance || Math.Abs(Top - p.Y) > tolerance;
    }

    /// <summary>
    /// Puts the panel back on its preset if a DPI change resized it.
    /// Its size is chosen by the user's double-click, not by which display it
    /// happens to be on.
    /// </summary>
    private void RestorePresetSizeIfDrifted()
    {
        if (_isPerformingOwnResize) return;

        var target = SizeOf(_activePreset);
        if (Math.Abs(Width - target.Width) < 0.5 && Math.Abs(Height - target.Height) < 0.5) return;

        Width = target.Width;
        Height = target.Height;
    }

    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        RestorePresetSizeIfDrifted();
    }

    /// <summary>
    /// BackEase gives the overshoot-and-settle the macOS build hand-rolls with a
    /// damped oscillation; WPF drives it on the compositor rather than a timer.
    /// </summary>
    private void AnimateTo(Size target)
    {
        var ease = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.35 };
        var duration = new Duration(TimeSpan.FromMilliseconds(340));

        // Width alone grows from the left edge, which throws the card to the
        // right as it expands. Move the left edge by half the difference so the
        // panel changes tier around its own centre, the way the macOS build
        // does. The top edge stays put, so it grows downward.
        var targetLeft = Left + (Width - target.Width) / 2;
        var area = SystemParameters.WorkArea;
        targetLeft = Math.Clamp(targetLeft, area.Left, Math.Max(area.Left, area.Right - target.Width));

        _isPerformingOwnResize = true;
        Animate(LeftProperty, targetLeft, ease, duration);
        Animate(HeightProperty, target.Height, ease, duration);
        Animate(WidthProperty, target.Width, ease, duration, onCompleted: () => _isPerformingOwnResize = false);
    }

    /// <summary>
    /// Animates one property and then hands it back.
    ///
    /// A finished animation normally keeps hold of its property, and anything
    /// that assigns to it afterwards is silently ignored. That matters here
    /// because DragMove writes Left and the DPI guard writes Width and Height —
    /// left held, the panel would animate once and then refuse to be moved or
    /// corrected. Stopping the animation and writing the final value by hand
    /// releases the property while landing on the same number.
    /// </summary>
    private void Animate(
        DependencyProperty property,
        double to,
        IEasingFunction ease,
        Duration duration,
        Action? onCompleted = null)
    {
        var animation = new DoubleAnimation(to, duration)
        {
            EasingFunction = ease,
            FillBehavior = FillBehavior.Stop,
        };
        animation.Completed += (_, _) =>
        {
            BeginAnimation(property, null);
            SetValue(property, to);
            onCompleted?.Invoke();
        };
        BeginAnimation(property, animation);
    }

    private void OnRefreshClick(object sender, RoutedEventArgs e) => _model.Refresh();

    private void OnHideClick(object sender, RoutedEventArgs e)
    {
        PersistPlacement();
        Hide();
    }

    private void Render()
    {
        var isLarge = Width >= LargeSize.Width - LargeTolerance;
        LargeView.Visibility = isLarge ? Visibility.Visible : Visibility.Collapsed;
        SmallView.Visibility = isLarge ? Visibility.Collapsed : Visibility.Visible;

        var showClaude = _model.IsDisplayed(Provider.Claude);
        var showCodex = _model.IsDisplayed(Provider.Codex);
        LargeClaude.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        LargeCodex.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        LargeProviderSeparator.Visibility = showClaude && showCodex ? Visibility.Visible : Visibility.Collapsed;
        LargeEmpty.Visibility = !showClaude && !showCodex ? Visibility.Visible : Visibility.Collapsed;
        SmallClaude.Visibility = showClaude ? Visibility.Visible : Visibility.Collapsed;
        SmallCodex.Visibility = showCodex ? Visibility.Visible : Visibility.Collapsed;
        SmallClaude.Margin = showClaude && showCodex ? new Thickness(0, 0, 0, 7) : new Thickness(0);
        SmallEmpty.Visibility = !showClaude && !showCodex ? Visibility.Visible : Visibility.Collapsed;

        if (isLarge)
        {
            if (showClaude) BuildLargeSection(LargeClaude, _model.Claude);
            if (showCodex) BuildLargeSection(LargeCodex, _model.Codex);
            // Formatted with the display language's culture, not the machine's
            // regional one. Windows keeps those separate, so an English display
            // language on a Korean region was printing "Updated 오전 12:44".
            UpdatedText.Text = _model.LastUpdated is { } updated
                ? L.T(
                    ko: $"업데이트 {updated:HH:mm:ss}",
                    en: $"Updated {updated:HH:mm:ss}",
                    ja: $"更新 {updated:HH:mm:ss}",
                    zh: $"更新于 {updated:HH:mm:ss}")
                : "";
        }
        else
        {
            if (showClaude) BuildSmallRow(SmallClaude, _model.Claude);
            if (showCodex) BuildSmallRow(SmallCodex, _model.Codex);
        }
    }

    private static void BuildLargeSection(Panel host, ProviderSnapshot snapshot)
    {
        host.Children.Clear();
        var accent = UsagePalette.AccentFor(snapshot.Provider);

        // The provider's name lives on the row's first line, directly above
        // the track it labels, rather than on a heading line of its own.
        if (snapshot.PairedWindows() is { } paired)
        {
            host.Children.Add(BuildPairedRow(snapshot, paired.Base, paired.Overlay, accent));
        }
        else if (snapshot.Windows.Count == 0)
        {
            var empty = new Grid();
            empty.Children.Add(ProviderHeading(snapshot, accent));
            empty.Children.Add(new TextBlock
            {
                Text = "—",
                Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
                FontSize = 11,
                HorizontalAlignment = HorizontalAlignment.Right,
            });
            host.Children.Add(empty);
        }
        else
        {
            // Only the first row carries the name, so a provider reporting more
            // than two windows doesn't repeat its own heading.
            for (var i = 0; i < snapshot.Windows.Count; i++)
            {
                host.Children.Add(BuildSingleRow(snapshot, snapshot.Windows[i], accent, showsHeading: i == 0));
            }
        }
    }

    /// <summary>The provider's mark and name, as a row's leading half.</summary>
    private static UIElement ProviderHeading(ProviderSnapshot snapshot, Color accent)
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        row.Children.Add(ProviderMark.Create(snapshot.Provider, 14));
        row.Children.Add(new TextBlock
        {
            Text = snapshot.Provider.DisplayName(),
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(accent),
            Margin = new Thickness(5, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        });
        if (!snapshot.SourceExists)
        {
            row.Children.Add(new TextBlock
            {
                Text = L.T(ko: "데이터 없음", en: "No data", ja: "データなし", zh: "无数据"),
                FontSize = 10,
                Margin = new Thickness(6, 0, 0, 0),
                Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
                VerticalAlignment = VerticalAlignment.Center,
            });
        }
        return row;
    }

    /// <summary>
    /// A window's name and value kept together, the name set bold. Shared so
    /// Claude's weekly and Codex's get one treatment rather than drifting.
    /// </summary>
    private static UIElement ValueLabel(
        UsageWindow window, double size, Brush labelBrush, Brush valueBrush, HorizontalAlignment align)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = align };
        row.Children.Add(new TextBlock
        {
            Text = window.Label,
            FontSize = size,
            FontWeight = FontWeights.SemiBold,
            Foreground = labelBrush,
        });
        row.Children.Add(new TextBlock
        {
            Text = Percent(window),
            FontSize = size,
            Foreground = valueBrush,
            Margin = new Thickness(4, 0, 0, 0),
        });
        return row;
    }

    private static UIElement BuildPairedRow(
        ProviderSnapshot snapshot, UsageWindow baseWindow, UsageWindow overlay, Color accent)
    {
        var stack = new StackPanel();
        var accentBrush = new SolidColorBrush(accent);

        var line = new Grid();
        line.Children.Add(ProviderHeading(snapshot, accent));
        // The long window's name carries the accent too, tying it to the bar
        // it names.
        line.Children.Add(ValueLabel(baseWindow, 11, accentBrush, accentBrush, HorizontalAlignment.Right));
        stack.Children.Add(line);

        stack.Children.Add(NestedBar(baseWindow, overlay, accent));

        // The short window reads as one line under the bar — name, value and
        // reset together — since its old slot above now holds the name.
        var below = new Grid { Margin = new Thickness(0, 5, 0, 0) };
        var shortSide = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        shortSide.Children.Add(ValueLabel(
            overlay,
            10,
            new SolidColorBrush(Colors.White),
            new SolidColorBrush(UsagePalette.ColorFor(overlay.RemainingPercent, Colors.White)),
            HorizontalAlignment.Left));
        if (ResetText.Of(overlay) is { } overlayReset)
        {
            var caption = Caption(overlayReset, HorizontalAlignment.Left);
            caption.Margin = new Thickness(6, 0, 0, 0);
            shortSide.Children.Add(caption);
        }
        below.Children.Add(shortSide);

        if (ResetText.Of(baseWindow) is { } baseReset)
        {
            below.Children.Add(Caption(baseReset, HorizontalAlignment.Right));
        }
        stack.Children.Add(below);

        return stack;
    }

    private static UIElement BuildSingleRow(
        ProviderSnapshot snapshot, UsageWindow window, Color accent, bool showsHeading)
    {
        var stack = new StackPanel { Margin = new Thickness(0, 0, 0, 4) };

        // Name on the left and the window's value on the right, laid out the
        // same way as the paired row so both providers line up.
        var line = new Grid();
        if (showsHeading)
        {
            line.Children.Add(ProviderHeading(snapshot, accent));
        }
        line.Children.Add(ValueLabel(
            window,
            11,
            new SolidColorBrush(accent),
            new SolidColorBrush(UsagePalette.ColorFor(window.RemainingPercent, Colors.White)),
            HorizontalAlignment.Right));
        stack.Children.Add(line);

        stack.Children.Add(SimpleBar(window.RemainingPercent, 8));

        // Trailing edge as well, sitting under the value it belongs to — the
        // same place the paired row puts its long window's reset line.
        if (ResetText.Of(window) is { } reset)
        {
            var caption = Caption(reset, HorizontalAlignment.Right);
            caption.Margin = new Thickness(0, 5, 0, 0);
            stack.Children.Add(caption);
        }

        return stack;
    }

    private static void BuildSmallRow(Panel host, ProviderSnapshot snapshot)
    {
        host.Children.Clear();
        var accent = UsagePalette.AccentFor(snapshot.Provider);
        var paired = snapshot.PairedWindows();
        var display = paired?.Base ?? snapshot.Windows.FirstOrDefault();

        var line = new Grid { Margin = new Thickness(0, 0, 0, 5) };

        // The mark alone stands in for the provider's name at this size, with
        // the short window's percentage beside it — the same left-to-right
        // order as the large view.
        var left = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        // Nudged in from the panel's own edge padding, which is tight at this
        // size and left the mark looking stuck to the side.
        var mark = ProviderMark.Create(snapshot.Provider, 10);
        if (mark is FrameworkElement markElement)
        {
            markElement.Margin = new Thickness(3, 0, 0, 0);
        }
        left.Children.Add(mark);
        if (paired?.Overlay.RemainingPercent is { } overlayRemaining)
        {
            left.Children.Add(new TextBlock
            {
                Text = $"{(int)overlayRemaining}%",
                FontSize = 11,
                Margin = new Thickness(5, 0, 0, 0),
                Foreground = new SolidColorBrush(UsagePalette.ColorFor(overlayRemaining, Colors.White)),
                VerticalAlignment = VerticalAlignment.Center,
            });
        }
        line.Children.Add(left);

        line.Children.Add(new TextBlock
        {
            Text = display is null ? "—" : Percent(display),
            FontSize = 11,
            // Only the paired provider's weekly number takes the accent; a
            // single-window provider keeps the plain foreground.
            Foreground = new SolidColorBrush(paired is not null ? accent : Colors.White),
            HorizontalAlignment = HorizontalAlignment.Right,
        });
        host.Children.Add(line);

        host.Children.Add(paired is { } p
            ? NestedBar(p.Base, p.Overlay, accent, height: 5)
            : SimpleBar(display?.RemainingPercent, 5));
    }

    /// <summary>
    /// Both windows are drawn directly in one control, measured against the
    /// full track and starting at the same edge. This avoids relying on a
    /// post-layout SizeChanged event, which could leave stale widths after a
    /// DPI or visibility change.
    /// </summary>
    private static UIElement NestedBar(UsageWindow baseWindow, UsageWindow overlay, Color accent, double height = 8)
    {
        var baseColor = baseWindow.Provider == Provider.Codex
            ? UsagePalette.CodexWeeklyGauge
            : accent;
        return new NestedGaugeBar(
            baseWindow.RemainingPercent,
            overlay.RemainingPercent,
            baseColor,
            UsagePalette.ColorFor(overlay.RemainingPercent, Colors.White),
            height)
        {
            Margin = new Thickness(0, 2, 0, 0),
        };
    }

    private static UIElement SimpleBar(double? remaining, double height)
    {
        var track = new Border
        {
            Height = height,
            CornerRadius = new CornerRadius(height / 2),
            Background = new SolidColorBrush(Color.FromArgb(0x33, 0x99, 0x99, 0x99)),
            Margin = new Thickness(0, 2, 0, 0),
        };

        var fill = new Border
        {
            CornerRadius = new CornerRadius(height / 2),
            Background = new SolidColorBrush(UsagePalette.ColorFor(remaining, Colors.White)),
            HorizontalAlignment = HorizontalAlignment.Left,
        };

        var grid = new Grid();
        grid.Children.Add(fill);
        track.Child = grid;

        var fraction = (remaining ?? 0) / 100.0;
        grid.SizeChanged += (_, e) => fill.Width = e.NewSize.Width * fraction;

        return track;
    }

    private static TextBlock Caption(string text, HorizontalAlignment alignment) => new()
    {
        Text = text,
        FontSize = 9,
        Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
        HorizontalAlignment = alignment,
    };

    private static string Percent(UsageWindow window) =>
        window.RemainingPercent is { } r ? $"{(int)r}%" : "—";
}

/// <summary>
/// Draws the weekly and short-window fills in the same coordinate system.
/// The longer fill is painted first and the shorter fill second, matching the
/// macOS NestedUsageBar even when the weekly allowance is the tighter one.
/// </summary>
internal sealed class NestedGaugeBar : FrameworkElement
{
    private readonly double _baseFraction;
    private readonly double _overlayFraction;
    private readonly Brush _baseBrush;
    private readonly Brush _overlayBrush;
    private static readonly Brush TrackBrush =
        new SolidColorBrush(Color.FromArgb(0x33, 0x99, 0x99, 0x99));

    public NestedGaugeBar(double? baseRemaining, double? overlayRemaining, Color baseColor, Color overlayColor, double height)
    {
        _baseFraction = Fraction(baseRemaining);
        _overlayFraction = Fraction(overlayRemaining);
        _baseBrush = new SolidColorBrush(baseColor);
        _overlayBrush = new SolidColorBrush(overlayColor);
        Height = height;
        SnapsToDevicePixels = true;
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        var radius = ActualHeight / 2;
        DrawFill(drawingContext, TrackBrush, ActualWidth, radius);

        if (_baseFraction >= _overlayFraction)
        {
            DrawFill(drawingContext, _baseBrush, ActualWidth * _baseFraction, radius);
            DrawFill(drawingContext, _overlayBrush, ActualWidth * _overlayFraction, radius);
        }
        else
        {
            DrawFill(drawingContext, _overlayBrush, ActualWidth * _overlayFraction, radius);
            DrawFill(drawingContext, _baseBrush, ActualWidth * _baseFraction, radius);
        }
    }

    private void DrawFill(DrawingContext context, Brush brush, double width, double radius)
    {
        if (width <= 0 || ActualHeight <= 0) return;
        context.DrawRoundedRectangle(brush, null, new Rect(0, 0, width, ActualHeight), radius, radius);
    }

    private static double Fraction(double? remaining) =>
        Math.Clamp((remaining ?? 0) / 100.0, 0, 1);
}
