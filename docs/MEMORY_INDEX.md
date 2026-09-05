# 星璃音乐 · 记忆总索引

> Hindsight 未配置（401 缺 key）时，`docs/MEMORY_*.md` 是唯一记忆兜底。

## 一、记忆文件
| 文件 | 覆盖 |
|---|---|
| `MEMORY_2026-09-02_R32_voicehub_glass.md` | R32 四需求（液态玻璃流畅档 / iOS26 悬浮 Dock / 账号后端 / 电台还原 VoiceHub）+ VoiceHub 全侦查（Nuxt4 全栈、Pixi.js、音源、账号、排期/点歌/通知） |
| `MEMORY_2026-09-04_R33_radio_voicehub.md` | R33 电台还原 + 后续轮次：黑屏 / 性能 / SMTC / 天气 / 农历 / ClassIsland / 集控 / UI 选型 / 即开即用 / VoiceHub 闭环 / cl05→cl09 发布 |

## 二、速查
**项目事实**
- 路径 `D:\Stellara\Music\xingli_music`；Flutter SDK `D:\flutter`
- 版本 `0.26.9.x_beta_clNN`（buildCount=当日次数，次日清零）；三处同步 app_version.dart ↔ pubspec(+NNN=versionCode) ↔ build.gradle versionName
- git 红线：源文件只用 edit/write（禁 PowerShell 写，曾 mojibake）；逐文件 add 禁 `-A`；push 用 token URL + fetch/update-ref
- `flutter.bat` exit 1 恒为 stderr 镜像误报（看 stderr 有无 `✓ Built`）

**外部系统**
- VoiceHub `https://voicehub.245959623.xyz`（v1.5.9.8 Nuxt4）：开放 API 走 `X-API-Key`（/api/open/songs.get、/api/open/schedules.get）；点歌 /api/songs/request.post 需登录 cookie；网页无 X-Frame（可内嵌）
- GitHub 代理 `https://gh.245959623.xyz/WuMengAA/xingli_music`（网页 / Raw / API / 下载 / clone）
- 天气 Open-Meteo（免费无 key）；IP 定位 ip-api.com → 降级 ipapi.co
- ClassIsland 集控 localhost:43218（control_server.dart）
- SMTC Windows 原生 C++/WinRT 桥（windows/runner/smtc_bridge.cpp）

**架构决策**
- 图形：Windows Skia/ANGLE 默认；深色 Spotify 炭黑 #121212 / #1A1A1A / #242424
- 皮肤 `themeSkinColorProvider`→`withSkin` 驱动 accent（深色 +0.12）
- 工具 provider（天气 / 日历 / ClassIsland / VoiceHub）首 watch 自 load
- 播放 `buildStreamResolver` 按 `sourceId` 反查 activeSourcesProvider——新源必须对齐 id（VoiceHub 网易云=`netease`）
- Relay/P2P 自研电台层保留；VoiceHub 作可选数据源 / 网页卡片

**防复发 bug**
- 枚举越界 clamp（OrderItem.status / orderDecision / NetMessage.type / lodQuality）
- 农历越界（solarToLunar 夹 1900-01-31~2100-12-31）
- 歌单 LEFT JOIN play_stats
- 天气 modal 用 StatefulBuilder
- 黑屏（看门狗 / Mali Impeller→Skia / NormalTheme 底色）
- InkWell 缺 Material ×6 兜底

**发布**
- 最新 Release `0.26.9.5_beta_cl01`（M2 收尾：探索 Gate 双重滚动 + 进度条 Material 兜底；Windows zip 37.9MB + arm64/arm32 APK + sha256）
- OTA manifest gh-pages（Win 走 Pages、安卓走 Releases 回退）

## 三、待办
- VoiceHub 设计语言融入 + 内嵌卡片（goal-9c5e6005，未完成）：星璃世界页加入口 → webview_flutter 内嵌 voicehub 站点（Android 优先；音源 / 播放本地处理并联动）
- issue #5：qa_v2 M2 探索 Gate 集成测试偶发红（now_playing overflow 待真机确认）

## 四、约定
- 每轮结束写 docs/MEMORY；问题记 GitHub issue（#2 / #3 / #4 closed，#5 open）
- 收口 = analyze 0 告警 + 可构建 + 提交 + push
