using System.Windows;
using System.Windows.Forms;
using PotatokenHub.Core;
using Application = System.Windows.Application;
using MessageBox = System.Windows.MessageBox;

namespace PotatokenHub;

public partial class App : Application
{
    private NotifyIcon _tray = null!;
    private UsageModel _model = null!;
    private PanelWindow _panel = null!;
    private System.Drawing.Icon? _currentIcon;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _model = new UsageModel();
        _panel = new PanelWindow(_model);
        _panel.RightClicked += ShowContextMenu;

        _tray = new NotifyIcon
        {
            Visible = true,
            Text = "potatoken hub",
        };
        _tray.MouseClick += OnTrayClick;

        AlertManager.Shared.Notify = (title, body) =>
            _tray.ShowBalloonTip(5000, title, body, ToolTipIcon.None);

        _model.PropertyChanged += (_, _) => UpdateTray();
        UpdateTray();

        _panel.Show();
    }

    private void OnTrayClick(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Right)
        {
            ShowContextMenu();
            return;
        }
        TogglePanel();
    }

    private void TogglePanel()
    {
        if (_panel.IsVisible)
        {
            _panel.PersistPlacement();
            _panel.Hide();
        }
        else
        {
            _panel.Show();
            _panel.Activate();
        }
    }

    private void UpdateTray()
    {
        var previous = _currentIcon;
        _currentIcon = TrayBadge.Render(
            UsageModel.Tightest(_model.Claude),
            UsageModel.Tightest(_model.Codex));
        _tray.Icon = _currentIcon;
        // Only safe to dispose after the control has taken the new one.
        previous?.Dispose();

        // A NotifyIcon tooltip is capped at 63 characters.
        var tooltip = TrayBadge.Tooltip(_model.Claude, _model.Codex);
        _tray.Text = tooltip.Length > 63 ? tooltip[..63] : tooltip;
    }

    private void ShowContextMenu()
    {
        var menu = new ContextMenuStrip();

        menu.Items.Add(L.T(ko: "새로고침", en: "Refresh", ja: "更新", zh: "刷新"), null,
            (_, _) => _model.Refresh());
        menu.Items.Add(L.T(ko: "숨기기", en: "Hide", ja: "隠す", zh: "隐藏"), null,
            (_, _) => { _panel.PersistPlacement(); _panel.Hide(); });

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(BuildSizeMenu());

        var onTop = new ToolStripMenuItem(
            L.T(ko: "항상 위", en: "Always on Top", ja: "常に手前に表示", zh: "总在最前"),
            null,
            (_, _) =>
            {
                Settings.AlwaysOnTop = !Settings.AlwaysOnTop;
                _panel.Topmost = Settings.AlwaysOnTop;
            })
        { Checked = Settings.AlwaysOnTop };
        menu.Items.Add(onTop);

        var startup = new ToolStripMenuItem(
            L.T(ko: "로그인 시 자동 실행", en: "Launch at Login", ja: "ログイン時に起動", zh: "开机自启动"),
            null,
            (_, _) => LaunchAtLogin.Toggle())
        { Checked = LaunchAtLogin.IsEnabled };
        menu.Items.Add(startup);

        menu.Items.Add(BuildLanguageMenu());

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(L.T(
                ko: "potatoken hub 정보",
                en: "About potatoken hub",
                ja: "potatoken hub について",
                zh: "关于 potatoken hub"),
            null, (_, _) => ShowAbout());

        menu.Items.Add(L.T(ko: "앱 종료하기", en: "Quit", ja: "アプリを終了", zh: "退出应用"), null,
            (_, _) => Quit());

        menu.Show(System.Windows.Forms.Cursor.Position);
    }

    /// <summary>
    /// Size picker. The double-click toggle stays the quick way to switch;
    /// this is the explicit one, and it shows which preset is active.
    /// </summary>
    private ToolStripMenuItem BuildSizeMenu()
    {
        var parent = new ToolStripMenuItem(
            L.T(ko: "창 크기", en: "Window Size", ja: "ウインドウサイズ", zh: "窗口大小"));

        (PanelWindow.SizePreset Preset, string Title)[] options =
        [
            (PanelWindow.SizePreset.Small, L.T(ko: "소형", en: "Small", ja: "小", zh: "小")),
            (PanelWindow.SizePreset.Large, L.T(ko: "대형", en: "Large", ja: "大", zh: "大")),
        ];

        foreach (var (preset, title) in options)
        {
            var item = new ToolStripMenuItem(title, null, (_, _) =>
            {
                // Show the panel first, so picking a size from the tray also
                // brings it back when it's hidden.
                if (!_panel.IsVisible) _panel.Show();
                _panel.ApplyPreset(preset);
            })
            { Checked = _panel.ActivePreset == preset };
            parent.DropDownItems.Add(item);
        }

        return parent;
    }

    private ToolStripMenuItem BuildLanguageMenu()
    {
        // Titled in all four languages so it stays findable whichever one is active.
        var parent = new ToolStripMenuItem("언어 / Language / 言語 / 语言");

        (L.Language Language, string Title)[] options =
        [
            (L.Language.System, L.T(
                ko: "시스템 언어 따름", en: "Follow System",
                ja: "システム言語に従う", zh: "跟随系统语言")),
            (L.Language.Korean, "한국어"),
            (L.Language.English, "English"),
            (L.Language.Japanese, "日本語"),
            (L.Language.Chinese, "中文"),
        ];

        foreach (var (language, title) in options)
        {
            var item = new ToolStripMenuItem(title, null, (_, _) =>
            {
                L.Preference = language;
                _model.Refresh();
            })
            { Checked = L.Preference == language };
            parent.DropDownItems.Add(item);
        }

        return parent;
    }

    private static void ShowAbout()
    {
        var version = System.Reflection.Assembly.GetEntryAssembly()?
            .GetName().Version?.ToString(3) ?? "1.5.0";

        MessageBox.Show(
            L.T(
                ko: $"potatoken hub {version}\n만든 사람  bmminky\nhttps://github.com/bmminky/potatoken-hub",
                en: $"potatoken hub {version}\nCreated by bmminky\nhttps://github.com/bmminky/potatoken-hub",
                ja: $"potatoken hub {version}\n作成者 bmminky\nhttps://github.com/bmminky/potatoken-hub",
                zh: $"potatoken hub {version}\n作者 bmminky\nhttps://github.com/bmminky/potatoken-hub"),
            "potatoken hub",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void Quit()
    {
        _panel.PersistPlacement();
        _tray.Visible = false;
        _tray.Dispose();
        _currentIcon?.Dispose();
        Shutdown();
    }
}
