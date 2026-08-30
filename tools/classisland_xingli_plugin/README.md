# 星璃联动插件

联动 [星璃音乐](https://github.com/wumengaa/xingli_music) 的 ClassIsland 2 插件。

## 功能

在主界面添加「**星璃 · 正在播放**」组件，显示：

- 当前曲目（标题 / 歌手 / 直播标记 / 播放进度）
- 电台状态条（房间名 + DJ；仅入台/开台时显示）
- 星璃未运行时显示「未连接星璃」

## 要求

- 星璃音乐 **Windows 版**运行中（内置本地状态服务，端口 **8742**，协议 v1）
- 协议与端口详见星璃仓库 `docs/方案_ClassIsland联动.md`

## 使用

1. 安装插件（放入 ClassIsland `Plugins` 目录）
2. 【应用设置】→【组件】→ 将「星璃 · 正在播放」拖入主界面
3. 打开星璃音乐，组件自动显示当前播放内容

## 里程碑

- **M1**（当前）：组件骨架 + 只读显示
- **M2**：回环远程控制按钮（播放/暂停/切歌）
- **M3**：异机部署 + 可选 token 鉴权

## 开发

```powershell
dotnet build ClassIslandXingliPlugin.csproj
# 调试：launchSettings 已配置 ClassIsland 本体加载本插件（-epp）
```

## 开源协议

MIT（星璃音乐仓库同协议，见 `LICENSE`）。