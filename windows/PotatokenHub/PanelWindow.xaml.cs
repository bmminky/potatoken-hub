using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using PotatokenHub.Core;

namespace PotatokenHub;

public partial class PanelWindow : Window
{
    private static readonly Size SmallSize = new(220, 96);
    private static readonly Size LargeSize = new(320, 268);
    /// <summary>How far below the large preset still renders the large layout.</summary>
    private const double LargeTolerance = 24;

    private readonly UsageModel _model;

    private enum SizePreset
    {
        Small,
        Large,
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

    private Size SizeOf(SizePreset preset) => preset == SizePreset.Large ? LargeSize : SmallSize;

    private SizePreset PresetNearest(double width) =>
        width >= (SmallSize.Width + LargeSize.Width) / 2 ? SizePreset.Large : SizePreset.Small;

    public event Action? RightClicked;

    public PanelWindow(UsageModel model)
    {
        InitializeComponent();
        _model = model;
        _model.PropertyChanged += (_, _) => Dispatcher.Invoke(Render);

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

    public void ToggleSizePreset()
    {
        var showing = Math.Abs(Width - SizeOf(_activePreset).Width) < 0.5
            ? _activePreset
            : PresetNearest(Width);
        _activePreset = showing == SizePreset.Large ? SizePreset.Small : SizePreset.Large;
        AnimateTo(SizeOf(_activePreset));
    }

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

        _isPerformingOwnResize = true;
        var widthAnimation = new DoubleAnimation(target.Width, duration) { EasingFunction = ease };
        widthAnimation.Completed += (_, _) => _isPerformingOwnResize = false;

        BeginAnimation(WidthProperty, widthAnimation);
        BeginAnimation(HeightProperty, new DoubleAnimation(target.Height, duration) { EasingFunction = ease });
    }

    private void OnRefreshClick(object sender, RoutedEventArgs e) => _model.Refresh();

    private void OnHideClick(object sender, RoutedEventArgs e)
    {
        PersistPlacement();
        Hide();
    }

    private void Render()
    {
        var isLarge = Width >= LargeSize.Width - LargeTolerance && Height >= LargeSize.Height - LargeTolerance;
        LargeView.Visibility = isLarge ? Visibility.Visible : Visibility.Collapsed;
        SmallView.Visibility = isLarge ? Visibility.Collapsed : Visibility.Visible;

        if (isLarge)
        {
            BuildLargeSection(LargeClaude, _model.Claude);
            BuildLargeSection(LargeCodex, _model.Codex);
            UpdatedText.Text = _model.LastUpdated is { } updated
                ? L.T(
                    ko: $"업데이트 {updated:t}",
                    en: $"Updated {updated:t}",
                    ja: $"更新 {updated:t}",
                    zh: $"更新于 {updated:t}")
                : "";
        }
        else
        {
            BuildSmallRow(SmallClaude, _model.Claude);
            BuildSmallRow(SmallCodex, _model.Codex);
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
    /// Both windows measured against the full track and drawn from the same
    /// edge, the one with more remaining underneath — so whichever window is
    /// tighter always stays visible rather than being covered.
    /// </summary>
    private static UIElement NestedBar(UsageWindow baseWindow, UsageWindow overlay, Color accent, double height = 8)
    {
        var track = new Border
        {
            Height = height,
            CornerRadius = new CornerRadius(height / 2),
            Background = new SolidColorBrush(Color.FromArgb(0x33, 0x99, 0x99, 0x99)),
            Margin = new Thickness(0, 2, 0, 0),
        };

        var grid = new Grid();
        var baseFraction = (baseWindow.RemainingPercent ?? 0) / 100.0;
        var overlayFraction = (overlay.RemainingPercent ?? 0) / 100.0;

        var baseBar = new Border
        {
            CornerRadius = new CornerRadius(height / 2),
            Background = new SolidColorBrush(accent),
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        var overlayBar = new Border
        {
            CornerRadius = new CornerRadius(height / 2),
            Background = new SolidColorBrush(UsagePalette.ColorFor(overlay.RemainingPercent, Colors.White)),
            HorizontalAlignment = HorizontalAlignment.Left,
        };

        // Later children draw on top, so the longer bar goes in first.
        if (baseFraction >= overlayFraction)
        {
            grid.Children.Add(baseBar);
            grid.Children.Add(overlayBar);
        }
        else
        {
            grid.Children.Add(overlayBar);
            grid.Children.Add(baseBar);
        }
        track.Child = grid;

        // Widths are fractions of the measured track, set on layout rather than
        // via a scale transform, which would squash the rounded caps flat.
        grid.SizeChanged += (_, e) =>
        {
            var full = e.NewSize.Width;
            baseBar.Width = full * baseFraction;
            overlayBar.Width = full * overlayFraction;
        };

        return track;
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
