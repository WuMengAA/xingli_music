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
/// 「星璃 · 正在播放」组件（M1 骨架：只读显示）。
/// 轮询星璃端本地 HTTP 服务（默认 127.0.0.1:8742，协议 v1），
/// 展示当前曲目 + 电台状态；星璃未运行/端口冲突时显示「未连接」。
/// </summary>
[ComponentInfo(
    "E7C5B3A2-4F8D-4B2A-9C1E-3D6A8F0B2E41",
    "星璃 · 正在播放",
    "\uE9B0",
    "联动星璃音乐：显示正在播放的曲目（标题/歌手/电台）。需要星璃 Windows 端运行。")]
public sealed partial class NowPlayingStatusComponent : ComponentBase, IDisposable
{
    private readonly NowPlayingClient _client = new();
    private readonly CancellationTokenSource _cts = new();
    private readonly DispatcherTimer _timer;
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

        _prevButton.Click += async (_, _) => await _client.ControlAsync("prev");
        _toggleButton.Click += async (_, _) => await _client.ControlAsync("toggle");
        _nextButton.Click += async (_, _) => await _client.ControlAsync("next");

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        _timer.Tick += OnTick;
    }

    private async void OnTick(object? sender, EventArgs e)
    {
        if (_cts.IsCancellationRequested) return;
        var snapshot = await _client.FetchAsync(_cts.Token).ConfigureAwait(true);
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
        _client.Dispose();
    }
}