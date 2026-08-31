using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using ClassIsland.Core.Abstractions.Controls;

namespace ClassIslandXingliPlugin;

/// <summary>
/// 「星璃 · 正在播放」组件设置控件（组件设置页）。
/// 读取/写回 <see cref="NowPlayingPluginSettings"/>；编辑即时同步到组件。
/// 注意：Settings 在初始化完成后才可用（构造期内为 null）。
/// </summary>
public sealed partial class NowPlayingSettingsControl : ComponentBase<NowPlayingPluginSettings>
{
    private readonly TextBox _urlBox = new()
    {
        Watermark = "http://127.0.0.1:8742",
        MinWidth = 280,
    };

    private readonly TextBox _pollBox = new()
    {
        Watermark = "2",
        MinWidth = 80,
    };

    private bool _initialized;

    public NowPlayingSettingsControl()
    {
        var panel = new StackPanel
        {
            Orientation = Orientation.Vertical,
            Spacing = 6,
            Children =
            {
                Label("星璃状态服务地址"),
                _urlBox,
                Label("轮询间隔（秒）"),
                _pollBox,
                new TextBlock
                {
                    Text = "星璃音乐 Windows 端需运行中（内置本地状态服务，协议 v1）。"
                         + "保存后组件自动按新配置刷新；控制按钮仅本机回环可用。",
                    FontSize = 12,
                    Foreground = new SolidColorBrush(Color.FromRgb(130, 138, 170)),
                    TextWrapping = TextWrapping.Wrap,
                    MaxWidth = 320,
                },
            },
        };
        Content = panel;

        _urlBox.TextChanged += (_, _) => Flush();
        _pollBox.TextChanged += (_, _) => Flush();
    }

    private static TextBlock Label(string text) => new()
    {
        Text = text,
        FontSize = 12,
        Foreground = new SolidColorBrush(Color.FromRgb(120, 124, 148)),
    };

    /// <summary>把当前编辑内容写回设置模型；构造期 Settings 为 null 时忽略。</summary>
    private void Flush()
    {
        var settings = Settings;
        if (settings is null) return;
        settings.Url = string.IsNullOrWhiteSpace(_urlBox.Text) ? "http://127.0.0.1:8742" : _urlBox.Text.Trim();
        settings.PollSeconds = double.TryParse(_pollBox.Text, out var sec) && sec > 0 ? sec : 2.0;
    }

    protected override void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        if (_initialized) return;
        _initialized = true;
        // 初始化（Settings 可用）后回填一次初值，避免覆盖用户编辑
        Dispatcher.UIThread.Post(() =>
        {
            var settings = Settings;
            if (settings is null) return;
            _urlBox.Text = settings.Url;
            _pollBox.Text = settings.PollSeconds.ToString("0.#");
        }, DispatcherPriority.Background);
    }
}