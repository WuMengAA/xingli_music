using ClassIsland.Core;
using ClassIsland.Core.Abstractions;
using ClassIsland.Core.Attributes;
using ClassIsland.Core.Extensions.Registry;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace ClassIslandXingliPlugin;

/// <summary>
/// 星璃联动插件入口（ClassIsland 2 / PluginSdk 1.7.106.2-dev-v2）。
/// M1：注册「星璃 · 正在播放」组件；轮询星璃端 /nowplaying（协议 v1）。
/// </summary>
[PluginEntrance]
public class Plugin : PluginBase
{
    public override void Initialize(HostBuilderContext context, IServiceCollection services)
    {
        services.AddComponent<NowPlayingStatusComponent>();
    }
}