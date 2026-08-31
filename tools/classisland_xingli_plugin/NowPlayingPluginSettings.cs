using System.Text.Json.Serialization;

namespace ClassIslandXingliPlugin;

/// <summary>
///「星璃 · 正在播放」组件设置模型。
/// 由 ClassIsland 自动加载/保存（ComponentBase&lt;T&gt; 的 Settings 属性）。
/// </summary>
public sealed class NowPlayingPluginSettings
{
    /// <summary>星璃 NowPlaying 服务地址（默认本机）。异机/容器场景可改为局域网地址。</summary>
    [JsonPropertyName("url")]
    public string Url { get; set; } = "http://127.0.0.1:8742";

    /// <summary>轮询间隔（秒）。</summary>
    [JsonPropertyName("pollSeconds")]
    public double PollSeconds { get; set; } = 2.0;

    /// <summary>可选鉴权 token（v1.1）。留空 = 关闭鉴权（默认，v1 冻结行为）。
    /// 星璃端启用 token 后，此处需一致，否则请求返回 401 显示「未连接」。</summary>
    [JsonPropertyName("token")]
    public string Token { get; set; } = "";
}