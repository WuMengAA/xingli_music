using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace ClassIslandXingliPlugin;

/// <summary>
/// 星璃正在播放快照 —— 与星璃端 `GET /nowplaying`（协议 v1）对应。
/// 字段缺失时以可空类型存放；`application/json` 中字段不存在即 null。
/// </summary>
public sealed class NowPlayingTrack
{
    [JsonPropertyName("title")] public string? Title { get; init; }
    [JsonPropertyName("artist")] public string? Artist { get; init; }
    [JsonPropertyName("album")] public string? Album { get; init; }
    [JsonPropertyName("coverUrl")] public string? CoverUrl { get; init; }
    [JsonPropertyName("isLiveStream")] public bool? IsLiveStream { get; init; }
    [JsonPropertyName("sourceId")] public string? SourceId { get; init; }
}

/// <summary>电台房信息（仅入台/开台时非空）。</summary>
public sealed class NowPlayingRadio
{
    [JsonPropertyName("inStation")] public bool? InStation { get; init; }
    [JsonPropertyName("role")] public string? Role { get; init; }
    [JsonPropertyName("isDj")] public bool? IsDj { get; init; }
    [JsonPropertyName("djName")] public string? DjName { get; init; }
    [JsonPropertyName("roomName")] public string? RoomName { get; init; }
    [JsonPropertyName("roomCode")] public string? RoomCode { get; init; }
    [JsonPropertyName("mode")] public string? Mode { get; init; }
    [JsonPropertyName("memberCount")] public int? MemberCount { get; init; }
}

public sealed class NowPlayingSnapshot
{
    [JsonPropertyName("schema")] public int Schema { get; init; }
    [JsonPropertyName("app")] public string? App { get; init; }
    [JsonPropertyName("track")] public NowPlayingTrack? Track { get; init; }
    [JsonPropertyName("isPlaying")] public bool IsPlaying { get; init; }
    [JsonPropertyName("positionMs")] public long? PositionMs { get; init; }
    [JsonPropertyName("durationMs")] public long? DurationMs { get; init; }
    [JsonPropertyName("radio")] public NowPlayingRadio? Radio { get; init; }

    /// <summary>展示用：`标题 - 歌手`；无曲目时返回播放器状态文本。</summary>
    public string DisplayTitle =>
        Track is null ? (IsPlaying ? "正在播放…" : "未在播放")
        : string.IsNullOrWhiteSpace(Track.Artist) ? Track.Title ?? ""
        : $"{Track.Title} - {Track.Artist}";

    /// <summary>电台展示条文本；未入台时为 null。</summary>
    public string? RadioText => Radio is { InStation: true } r
        ? (string.IsNullOrWhiteSpace(r.RoomName)
            ? $"电台 · {r.DjName ?? "未知 DJ"}"
            : $"电台 · {r.RoomName}（{r.DjName ?? "?"}）")
        : null;
}

/// <summary>
/// 星璃 NowPlaying 服务客户端：轮询 `GET /nowplaying`，异常时保持上一次快照不炸。
/// 线程安全：Fetch 可被定时器周期性调用。
/// </summary>
public sealed class NowPlayingClient : IDisposable
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly JsonSerializerOptions _json = new() { PropertyNameCaseInsensitive = true };

    public NowPlayingClient(string? baseUrl = null, string? token = null)
    {
        _baseUrl = (baseUrl ?? "http://127.0.0.1:8742").TrimEnd('/');
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
        if (!string.IsNullOrWhiteSpace(token))
            _http.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", token.Trim());
    }

    /// <summary>拉取一次快照；请求失败或解析失败返回 null（调用方保持旧值即可）。</summary>
    public async Task<NowPlayingSnapshot?> FetchAsync(CancellationToken ct = default)
    {
        try
        {
            using var res = await _http.GetAsync(_baseUrl + "/nowplaying", ct).ConfigureAwait(false);
            if (!res.IsSuccessStatusCode) return null;
            await using var stream = await res.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
            return await JsonSerializer.DeserializeAsync<NowPlayingSnapshot>(
                stream, _json, ct).ConfigureAwait(false);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or JsonException)
        {
            return null;
        }
    }

    /// <summary>
    /// 发送远程控制指令（`play|pause|toggle|next|prev`，仅本机回环）。
    /// 服务端只接受 127.0.0.1/::1 来源；返回 true 表示服务端已受理。
    /// </summary>
    public async Task<bool> ControlAsync(string action, CancellationToken ct = default)
    {
        try
        {
            var payload = JsonSerializer.Serialize(new { action });
            using var content = new StringContent(payload, System.Text.Encoding.UTF8, "application/json");
            using var res = await _http.PostAsync(_baseUrl + "/control", content, ct).ConfigureAwait(false);
            return res.IsSuccessStatusCode;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return false;
        }
    }

    public void Dispose() => _http.Dispose();
}