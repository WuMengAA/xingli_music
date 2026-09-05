# 星璃音乐 · 全部记忆总索引（MEMORY INDEX）

> 本文件是**全部记忆的入口**：Hindsight 服务未配置（401：缺 API key）时，docs/MEMORY_*.md 是唯一记忆兜底（长期约定：用户要求必须长期写记忆）。

## 一、记忆文件索引

| 文件 | 日期 | 覆盖范围 |
|---|---|---|
| `MEMORY_2026-09-02_R32_voicehub_glass.md` | 2026-09-02 | R32 四项需求（液态玻璃流畅档 / iOS26 悬浮 Dock / 账号后端 / 电台还原 VoiceHub）+ **VoiceHub 完整侦查**（Nuxt4 全栈、Pixi.js WebGL、音源、账号体系、排期/点歌/通知全功能） |
| `MEMORY_2026-09-04_R33_radio_voicehub.md` | 2026-09-04（持续维护） | R33 电台还原 + 全部后续轮次：黑屏修复 / 性能优化 / SMTC / 天气 / 日历农历 / ClassIsland / 集控插件 / UI 选型 / 即开即用 / VoiceHub 对接闭环 / 持续修复轮 / cl05→cl09 发布 |

## 二、关键结论速查（跨文件汇总）

### 1. 项目事实
- **路径**：D:\Stellara\Music\xingli_music；Flutter SDK D:\flutter（精简源码 D:\flutter\engine\src\...）
- **版本**：发 0.26.9.x_beta_clNN（buildCount = 当日构建次数，次日清零；发布链：app_version.dart ↔ pubspec(+NNN=versionCode) ↔ build.gradle versionName）
- **git 红线**：文件编辑只用 edit/write 工具（禁 PowerShell 写源文件，曾致 mojibake 事故）；逐文件 git add 禁 `-A`；push 用 token URL + fetch/update-ref 同步 tracking
- **flutter.bat exit 1 恒为 stderr 镜像误报**（看 stderr 里有没有 `✓ Built`）

### 2. 外部系统/API
- **VoiceHub 正式地址**：`https://voicehub.245959623.xyz`（v1.5.9.8，Nuxt4 全栈）；开放 API 走 `X-API-Key` 头（`/api/open/songs.get`、`/api/open/schedules.get`）；点歌提交 `/api/songs/request.post` 需登录 cookie；网页**无 X-Frame-Options**（可内嵌）
- **GitHub 代理域名**：`https://gh.245959623.xyz/WuMengAA/xingli_music`（网页/Raw/API/下载/clone 全覆盖；raw.githubusercontent 被墙时走它）
- **天气**：Open-Meteo（免费无 key）；IP 定位 ip-api.com → 降级 ipapi.co
- **ClassIsland 集控**：本地被控端 localhost:43218（`control_server.dart`）
- **SMTC**：Windows 原生 C++/WinRT 桥（`windows/runner/smtc_bridge.cpp`）

### 3. 关键架构决策
- 图形后端：Windows Skia/ANGLE 默认（贴图可靠），深色主题 Spotify 炭黑层（#121212/#1A1A1A/#242424）
- 主题皮肤：`themeSkinColorProvider`→`withSkin` 驱动 accent（深色自动提亮 +0.12）
- 工具 provider（天气/日历/ClassIsland/VoiceHub）**首 watch 自动 load**（microtask），页面不再手动 load
- 播放解析：`buildStreamResolver` 按 `track.sourceId` 在 `activeSourcesProvider` 反查源——**新来源必须对齐源 id**（如 VoiceHub 网易云曲目 sourceId 必须 `'netease'`）
- Relay/P2P 自研电台层**保留**（用户明确），VoiceHub 作为可选数据源/网页卡片接入

### 4. 已修复的关键 bug（防复发）
- 枚举越界防崩（OrderItem.status/orderDecision/NetMessage.type/lodQuality 一律 clamp 0..len-1）
- 农历越界（solarToLunar 夹紧 1900-01-31~2100-12-31；日历 _shift 限 1900-2100）
- 歌单报错（playlistTracks 必须 LEFT JOIN play_stats 取元数据）
- 天气 modal sheet 不刷新（showModalBottomSheet 需 StatefulBuilder 本地 setSheet）
- 黑屏（ThrottledWidgetsBinding 看门狗 / Mali Impeller→Skia 反射降级 / NormalTheme 底色）
- InkWell 缺 Material（播放控件透明 Material 兜底 ×6）

### 5. 发布产物
- 最新 Release：`0.26.9.3_beta_cl09`（VoiceHub 闭环；Windows zip 37MB + arm64/arm32 APK + sha256）
- OTA manifest：gh-pages（Windows 走 Pages、安卓走 Releases 回退）；manifest PUT contents API 流程
- 发布流程沉淀见 MEMORY_2026-09-04 尾部

## 三、进行中/待办（下一轮接续）
- **VoiceHub 设计语言融入 + 内嵌网页卡片**（goal-9c5e6005，未完成）：
  - 星璃世界页加「VoiceHub」入口卡片 → WebView 内嵌 `voicehub.245959623.xyz`（webview_flutter 4.9.0 已缓存；Android 优先，Windows 需 desktop_webview_window 联网拉；网页无 X-Frame 限制）
  - 界面用 VoiceHub 网页；**音源/播放本地处理**并联动（网页浏览 + 本地拉排期/点歌 → 网易云/B站本地解析链播放）
  - 音乐卡/播放器加强封面主色驱动 + 呼吸光晕 + 信息密度徽标（VoiceHub 设计语言；现有 `_DynamicBackground` 已同源，待强化）
- issue #5：qa_v2 M2 探索 Gate 集成测试偶发红（now_playing Column overflow 场景待真机确认）

## 四、约定
- 每轮结束必须写 docs/MEMORY（用户强要求）
- 问题用 GitHub issue 记录（#2/#3/#4 已 closed，#5 open）
- 新功能/修复 = analyze 0 告警 + 能构建 + 提交 + push 才收口