using System;
using System.Threading;
using System.Threading.Tasks;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using ClassIsland.Core.Abstractions.Controls;
using ClassIsland.Core.Attributes;

namespace ClassIslandXingliPlugin;

/// <summary>
/// 「星璃 · 正在播放」组件（M1 骨架 + M2 控制按钮 + 设置配置化）。
/// 按设置轮询星璃端 HTTP 服务（默认 127.0.0.1:8742，协议 v1），
/// 展示当前曲目 + 电台状态；星璃未运行/地址不可达时显示「未连接」。
/// </summary>
[ComponentInfo(
    "E7C5B3A2-4F8D-4B2A-9C1E-3D6A8F0B2E41",
    "星璃 · 正在播放",
    "\uE9B0",
    "联动星璃音乐：显示正在播放的曲目（标题/歌手/电台）+ 回环控制按钮。需要星璃 Windows 端运行。")]
public sealed partial class NowPlayingStatusComponent : ComponentBase<NowPlayingPluginSettings>, IDisposable
{
    private readonly CancellationTokenSource _cts = new();
    private readonly DispatcherTimer _timer;
    private NowPlayingClient? _client;
    private string? _clientUrl;
    private readonly TextBlock _mainLine = new()
    {
        Text = "未连接星璃",
        Foreground = new SolidColorBrush(Color.FromRgb(233, 236, 255)),
        FontSize = 20,
        FontWeight = FontWeight.SemiBold,
        TextTrimming = TextTrimming.CharacterEllipsis,
        MaxWidth = 320,
    };

    private readonly TextBlock _subLine = new()
    {
        Text = "启动星璃音乐后自动显示",
        Foreground = new SolidColorBrush(Color.FromRgb(150, 158, 196)),
        FontSize = 13,
        TextTrimming = TextTrimming.CharacterEllipsis,
        MaxWidth = 320,
    };

    private readonly TextBlock _radioLine = new()
    {
        Text = "",
        Foreground = new SolidColorBrush(Color.FromRgb(190, 178, 255)),
        FontSize = 13,
        TextTrimming = TextTrimming.CharacterEllipsis,
        MaxWidth = 320,
        IsVisible = false,
    };

    private readonly Button _prevButton = new() { Content = "上一首" };
    private readonly Button _toggleButton = new() { Content = "播放" };
    private readonly Button _nextButton = new() { Content = "下一首" };

    public NowPlayingStatusComponent()
    {
        var buttonPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            Margin = new Avalonia.Thickness(0, 6, 0, 0),
            Children = { _prevButton, _toggleButton, _nextButton },
        };

        var panel = new StackPanel
        {
            Orientation = Orientation.Vertical,
            Spacing = 3,
            Children = { _mainLine, _subLine, _radioLine, buttonPanel },
        };
        Content = panel;

        _prevButton.Click += async (_, _) => await Client().ControlAsync("prev");
        _toggleButton.Click += async (_, _) => await Client().ControlAsync("toggle");
        _nextButton.Click += async (_, _) => await Client().ControlAsync("next");

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _timer.Tick += OnTick;
    }

    /// <summary>按设置目标地址取得客户端；地址变更时重建（设置可在运行期修改）。</summary>
    private NowPlayingClient Client()
    {
        var url = Settings?.Url;
        if (string.IsNullOrWhiteSpace(url)) url = "http://127.0.0.1:8742";
        if (_client is null || !string.Equals(_clientUrl, url, StringComparison.OrdinalIgnoreCase))
        {
            _client?.Dispose();
            _client = new NowPlayingClient(url);
            _clientUrl = url;
        }
        return _client;
    }

    private async void OnTick(object? sender, EventArgs e)
    {
        if (_cts.IsCancellationRequested) return;

        // Settings 在组件初始化完成后才可用；此处可能为 null（异常时保持默认）
        var settings = Settings;
        var interval = settings?.PollSeconds is > 0 ? settings.PollSeconds : 2.0;
        if (Math.Abs(_timer.Interval.TotalSeconds - interval) > 0.01)
            _timer.Interval = TimeSpan.FromSeconds(interval);

        var snapshot = await Client().FetchAsync(_cts.Token).ConfigureAwait(true);
        Apply(snapshot);
    }

    private void Apply(NowPlayingSnapshot? snapshot)
    {
        if (snapshot is null)
        {
            _mainLine.Text = "未连接星璃";
            _subLine.Text = "启动星璃音乐后自动显示";
            _radioLine.IsVisible = false;
            _toggleButton.Content = "播放";
            SetButtonsEnabled(false);
            return;
        }

        SetButtonsEnabled(true);
        _mainLine.Text = snapshot.DisplayTitle;
        _mainLine.Foreground = new SolidColorBrush(
            snapshot.IsPlaying ? Color.FromRgb(233, 236, 255) : Color.FromRgb(160, 168, 200));
        _toggleButton.Content = snapshot.IsPlaying ? "暂停" : "播放";

        var sub = BuildSubLine(snapshot);
        _subLine.Text = sub;

        var radio = snapshot.RadioText;
        _radioLine.Text = radio ?? "";
        _radioLine.IsVisible = radio is not null;
    }

    private void SetButtonsEnabled(bool value)
    {
        _prevButton.IsEnabled = value;
        _toggleButton.IsEnabled = value;
        _nextButton.IsEnabled = value;
    }

    private static string BuildSubLine(NowPlayingSnapshot s)
    {
        if (s.Track is null) return s.IsPlaying ? "正在播放…" : "暂停中";
        var parts = new System.Collections.Generic.List<string>();
        if (s.Track.IsLiveStream == true) parts.Add("直播");
        if (!string.IsNullOrWhiteSpace(s.Track.SourceId)) parts.Add(s.Track.SourceId!);
        if (s.DurationMs is { } d && d > 0 && s.PositionMs is { } p)
        {
            static string Fmt(long ms)
            {
                var t = TimeSpan.FromMilliseconds(ms);
                return t.TotalHours >= 1
                    ? $"{(int)t.TotalHours}:{t.Minutes:D2}:{t.Seconds:D2}"
                    : $"{t.Minutes}:{t.Seconds:D2}";
            }
            parts.Add($"{Fmt(p)} / {Fmt(d)}");
        }
        return parts.Count > 0 ? string.Join(" · ", parts) : s.Track.Album ?? "";
    }

    protected override void OnAttachedToVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        _timer.Start();
    }

    protected override void OnDetachedFromVisualTree(Avalonia.VisualTreeAttachmentEventArgs e)
    {
        _timer.Stop();
        base.OnDetachedFromVisualTree(e);
    }

    public void Dispose()
    {
        _timer.Stop();
        _cts.Cancel();
        _cts.Dispose();
        _client?.Dispose();
        _client = null;
    }
}