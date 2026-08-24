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
        if (e.ClickCount == 2)
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
        var toLarge = Math.Abs(Width - LargeSize.Width) > Math.Abs(Width - SmallSize.Width);
        AnimateTo(toLarge ? LargeSize : SmallSize);
    }

    /// <summary>
    /// BackEase gives the overshoot-and-settle the macOS build hand-rolls with a
    /// damped oscillation; WPF drives it on the compositor rather than a timer.
    /// </summary>
    private void AnimateTo(Size target)
    {
        var ease = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.35 };
        var duration = new Duration(TimeSpan.FromMilliseconds(340));

        BeginAnimation(WidthProperty, new DoubleAnimation(target.Width, duration) { EasingFunction = ease });
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

        var header = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 7) };
        header.Children.Add(new TextBlock
        {
            Text = snapshot.Provider.DisplayName(),
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(accent),
        });
        if (!snapshot.SourceExists)
        {
            header.Children.Add(new TextBlock
            {
                Text = "  " + L.T(ko: "데이터 없음", en: "No data", ja: "データなし", zh: "无数据"),
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
                VerticalAlignment = VerticalAlignment.Center,
            });
        }
        host.Children.Add(header);

        if (snapshot.PairedWindows() is { } paired)
        {
            host.Children.Add(BuildPairedRow(paired.Base, paired.Overlay, accent));
        }
        else if (snapshot.Windows.Count == 0)
        {
            host.Children.Add(new TextBlock
            {
                Text = "—",
                Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
                FontSize = 11,
            });
        }
        else
        {
            foreach (var window in snapshot.Windows)
            {
                host.Children.Add(BuildSingleRow(window, accent));
            }
        }
    }

    private static UIElement BuildPairedRow(UsageWindow baseWindow, UsageWindow overlay, Color accent)
    {
        var stack = new StackPanel();

        var line = new Grid();
        line.Children.Add(new TextBlock
        {
            Text = $"{overlay.Label}  {Percent(overlay)}",
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(UsagePalette.ColorFor(overlay.RemainingPercent, Colors.White)),
            HorizontalAlignment = HorizontalAlignment.Left,
        });
        line.Children.Add(new TextBlock
        {
            Text = $"{baseWindow.Label}  {Percent(baseWindow)}",
            FontSize = 12,
            Foreground = new SolidColorBrush(accent),
            HorizontalAlignment = HorizontalAlignment.Right,
        });
        stack.Children.Add(line);

        stack.Children.Add(NestedBar(baseWindow, overlay, accent));

        var resets = new Grid { Margin = new Thickness(0, 3, 0, 0) };
        if (ResetText.Of(overlay) is { } overlayReset)
        {
            resets.Children.Add(Caption(overlayReset, HorizontalAlignment.Left));
        }
        if (ResetText.Of(baseWindow) is { } baseReset)
        {
            resets.Children.Add(Caption(baseReset, HorizontalAlignment.Right));
        }
        stack.Children.Add(resets);

        return stack;
    }

    private static UIElement BuildSingleRow(UsageWindow window, Color accent)
    {
        var stack = new StackPanel { Margin = new Thickness(0, 0, 0, 4) };

        var line = new Grid();
        line.Children.Add(new TextBlock
        {
            Text = window.Label,
            FontSize = 12,
            FontWeight = window.WindowMinutes < 24 * 60 ? FontWeights.SemiBold : FontWeights.Normal,
            Foreground = new SolidColorBrush(Colors.White),
            HorizontalAlignment = HorizontalAlignment.Left,
        });
        line.Children.Add(new TextBlock
        {
            Text = Percent(window),
            FontSize = 12,
            Foreground = new SolidColorBrush(UsagePalette.ColorFor(window.RemainingPercent, Colors.White)),
            HorizontalAlignment = HorizontalAlignment.Right,
        });
        stack.Children.Add(line);

        stack.Children.Add(SimpleBar(window.RemainingPercent, 8));

        if (ResetText.Of(window) is { } reset)
        {
            stack.Children.Add(Caption(reset, HorizontalAlignment.Left));
        }

        return stack;
    }

    private static void BuildSmallRow(Panel host, ProviderSnapshot snapshot)
    {
        host.Children.Clear();
        var accent = UsagePalette.AccentFor(snapshot.Provider);
        var paired = snapshot.PairedWindows();
        var display = paired?.Base ?? snapshot.Windows.FirstOrDefault();

        var line = new Grid { Margin = new Thickness(0, 0, 0, 3) };
        line.Children.Add(new TextBlock
        {
            Text = snapshot.Provider.DisplayName(),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(accent),
            HorizontalAlignment = HorizontalAlignment.Left,
        });
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
    /// The short window drawn over the long one, capped at the long window's own
    /// current extent — a 100% 5-hour window fills exactly the weekly bar's
    /// width, never past it.
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

        grid.Children.Add(baseBar);
        grid.Children.Add(overlayBar);
        track.Child = grid;

        // Widths are fractions of the measured track, set on layout rather than
        // via a scale transform, which would squash the rounded caps flat.
        grid.SizeChanged += (_, e) =>
        {
            var full = e.NewSize.Width;
            baseBar.Width = full * baseFraction;
            overlayBar.Width = full * baseFraction * overlayFraction;
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
        FontSize = 10,
        Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
        HorizontalAlignment = alignment,
    };

    private static string Percent(UsageWindow window) =>
        window.RemainingPercent is { } r ? $"{(int)r}%" : "—";
}
