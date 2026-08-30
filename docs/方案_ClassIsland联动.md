# ClassIsland 联动 · 音乐播放显示 + 电台显示（方案）

> 定位：把星璃音乐的「正在播放」与「电台状态」投送到 [ClassIsland](https://classisland.tech/)（.NET 8 班级信息屏应用）——大屏上常驻显示当前曲目 / 当前电台，无需打开星璃主界面。
> 关联：白皮书 §投屏与网络源、`PRD_电台核心.md`、`lib/services/cast/cast_stream_server.dart`（T11）。
> 日期：2026-08-31 · 版本：0.1.0_draft

---

## 1. 背景与目标

ClassIsland 是跑在班级/办公多媒体大屏上的课表信息面板（组件 + 插件 + 主题系统，支持第三方自定义组件与跨进程通信）。星璃音乐作为「本地文件的智能策展人」，常有「大屏播放 + 电台广播」的班级/宿舍场景。

**联动内容**（用户提议）：
1. **音乐播放显示**：ClassIsland 面板显示星璃当前正在播放的曲目（封面 / 标题 / 歌手 / 进度）。
2. **电台显示**：本端在电台房（校园广播 / 一起听）时，面板显示电台信息（房间名 / 角色 / DJ / 人数）。

**设计原则**：
- 星璃端**只加一个本地 HTTP 状态服务**，不改播放链路、不依赖任何新包（纯 dart:io，同 T11 投屏服务器）。
- 协议先定稿（下文 §3），消费端（ClassIsland 插件）是纯客户端，可独立迭代。
- 只读状态对局域网开放；**写操作（远程控制）仅限本机回环**，防班级其他人乱按。

---

## 2. 架构总览

```
┌─────────────────────────────┐        ┌──────────────────────────────┐
│ 星璃音乐（Windows/Android） │  HTTP  │ ClassIsland 插件（.NET 8）  │
│                             │  8742  │  「星璃媒体」组件             │
│ ┌─────────────────────────┐ │  ◄──── │  - 轮询 GET /nowplaying       │
│ │ playback 真值源          │ │  ────► │  - 封面/标题/歌手/进度/电台   │
│ │ (nowPlaying/isPlaying/  │ │ POST   │  - 可选按钮: 播放/暂停/切歌    │
│ │  position/duration)     │ │ /control│    (仅当 ClassIsland 同机)   │
│ └───────────┬─────────────┘ │        └──────────────────────────────┘
│             │ Riverpod 组装  │
│ ┌───────────▼─────────────┐ │
│ │ NowPlayingServer        │ │
│ │ (dart:io, 端口 8742)    │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

- **同机部署**（最常见）：ClassIsland 与星璃跑在同一台电脑，插件访问 `http://127.0.0.1:8742`。
- **异机部署**（星璃在另一台主机/手机）：插件访问 `http://<星璃局域网IP>:8742`，只读展示；远程控制默认关闭（回环策略）。

---

## 3. 协议契约（v1，冻结）

### 3.1 `GET /nowplaying` → 200 JSON

```json
{
  "schema": 1,
  "app": "xingli_music",
  "track": {
    "title": "Minecraft - Sweden",
    "artist": "C418",
    "album": "Volume Alpha",
    "coverUrl": "http://.../cover.jpg",
    "isLiveStream": false,
    "sourceId": "local"
  },
  "isPlaying": true,
  "positionMs": 83241,
  "durationMs": 211000,
  "radio": null
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `schema` | int | 契约版本，恒 1 |
| `app` | string | 固定 `xingli_music` |
| `track` | object\|null | 当前曲目；无播放时 `null` |
| `track.title` / `artist` | string | 歌名 / 歌手（Track 模型直映射，缺失给空串） |
| `track.album` | string\|null | 专辑名 |
| `track.coverUrl` | string\|null | 远程封面 URL（本地源为 `coverPath` 需经本服务转发的 URL，v1 可为 null） |
| `track.isLiveStream` | bool | 直播流（公开电台）语义：无进度 |
| `track.sourceId` | string | 归属源（local/radio/subsonic…） |
| `isPlaying` | bool | 播放 / 暂停（与引擎真源一致） |
| `positionMs` / `durationMs` | int\|null | 进度 / 时长（电台直播流为 null） |
| `radio` | object\|null | 电台状态；不在电台房时为 `null` |

### 3.2 `radio` 对象（电台显示）

```json
{
  "inStation": true,
  "role": "host",
  "isDj": true,
  "djName": "星璃",
  "roomName": "午间点歌台",
  "roomCode": "1048",
  "mode": "campus",
  "memberCount": 6
}
```

| 字段 | 类型 | 来源（NetSessionState） |
|---|---|---|
| `inStation` | bool | `role != offline` |
| `role` | "host"\|"client"\|null | `role` |
| `isDj` | bool | `dj`（本端是否 DJ / 音源） |
| `djName` | string\|null | peers 中 `isHost` 者显示名；本端是 DJ 时用 `localName` |
| `roomName` | string\|null | `roomMeta.name`（ready 帧回传） |
| `roomCode` | string\|null | `roomCode`（中转房间号，房主展示用） |
| `mode` | "campus"\|"listen"\|null | `roomMeta.mode` |
| `memberCount` | int\|null | `roomMeta.members` |

### 3.3 `GET /health` → 200 `{"ok":true,"app":"xingli_music","version":"0.26.8.31_beta_cl01"}`

插件探活：服务未启动 / 端口不通则插件显示「星璃未运行」。

### 3.4 `POST /control`（本机回环专用）

```json
{"action": "play" | "pause" | "toggle" | "next" | "prev"}
```

- 成功 → `204`；未知 action → `400`；超过回环来源 → `403`；未注入控制器 → `501`。
- 控制器实现走现有 `playbackControllerProvider`（与系统媒体控件同一致，切歌逻辑复用曲库+播放方式）。

### 3.5 传输与编码

- HTTP 1.1，`Content-Type: application/json; charset=utf-8`（响应体 UTF-8）。
- 无鉴权（v1，局域网只读 + 回环写）；异机控制后续加 `?token=` 可选。
- 服务绑定 `InternetAddress.anyIPv4`，端口 `8742`，被占自动 +1（复用 T11 模式）。

---

## 4. 星璃端实现（Flutter）

### 4.1 新文件

| 文件 | 职责 |
|---|---|
| `lib/services/cast/now_playing_server.dart` | 纯 dart:io HttpServer 单例；注入 `NowPlayingSnapshot Function() reader` 与 `Future<bool> Function(String)? control`；路由 /nowplaying /health /control；**零 Riverpod 依赖**（可单测） |
| `lib/providers/cast/now_playing_providers.dart` | Riverpod 组装层：从 playback + session provider 读取真值组快照；Windows 端在 AppShell 常驻启动 |

### 4.2 快照模型（now_playing_server.dart 内）

```dart
class NowPlayingTrack {
  final String title, artist; final String? album, coverUrl, sourceId; final bool isLiveStream;
}
class NowPlayingRadio {
  final bool inStation; final String? role, djName, roomName, roomCode, mode; final bool isDj; final int? memberCount;
}
class NowPlayingSnapshot {
  final NowPlayingTrack? track; final bool isPlaying; final int? positionMs, durationMs; final NowPlayingRadio? radio;
  Map<String, dynamic> toJson();
}
```

### 4.3 启动时机

- `AppShell` 根部挂 `nowPlayingBridgeProvider`（`Provider<void>`，内部读容器、`Platform.isWindows` 才 `start()`——Android 上不常驻，省电且无暴露面）。
- `version` 字段从 `app_version.dart` 读，与 OTA 同源。

### 4.4 单测（`test/services/now_playing_server_test.dart`）

- 注入固定 reader，断言 `/nowplaying` JSON（含 track + radio 两形态、track=null 形态）。
- `/health` ok + version。
- `/control`：回环来源命中 controller；未知 action 400。
- 未知路径 404。

---

## 5. ClassIsland 端（.NET 8 插件，独立交付）

> 仓库内 `tools/classisland_xingli_plugin/`（独立 csproj，不入 Flutter 构建）。遵循 ClassIsland 插件约定（NuGet `ClassIsland.Core`，入口实现 `CliPluginBase`）。

组件形态：**「星璃媒体」信息组件**（添加到 ClassIsland 组件列表，可放主屏任意位置）：
- 显示：封面缩略图（有 coverUrl 时）+ 标题 + 歌手 + 播放进度条（isLiveStream 时隐藏）+ 电台条（inStation 时：🎙 房间名 · DJ · 人数）。
- 配置：服务器地址（默认 `http://127.0.0.1:8742`）+ 轮询间隔（默认 2s，可调 1~10s）。
- 未运行态：显示「星璃音乐未运行」灰条。
- 交互（仅地址为回环时可用）：点击播放/暂停、切歌小按钮 → POST /control。

### 5.1 里程碑

| M | 内容 | 依赖 |
|---|---|---|
| M0 | 星璃端 NowPlayingServer + 协议冻结（本文档） | 本轮 |
| M1 | ClassIsland 插件骨架：组件配置页 + 轮询 + 只读显示 | M0 |
| M2 | 回环远程控制按钮 | M0 |
| M3 | 异机部署文档 + 可选 token 鉴权 | M0 |

### 5.2 与 ClassIsland 的生态边界

- 不修改 ClassIsland 本体；仅通过插件 API 注入组件。
- 状态展示走 HTTP 协议，不依赖 ClassIsland 内部媒体通道（避免版本耦合）。

---

## 6. 边界与已知限制（v1）

- 封面：本地曲库 `coverPath` 是本地文件路径，ClassIsland 同机可读文件路径（插件可直读），异机需星璃转发——v1 插件直读本机路径，异机场景 coverUrl 为 null 显示占位图。
- 端到端确认需 ClassIsland 实际运行环境（本机无 ClassIsland 时打桩验证协议 + 插件编译级校验）。
- 电台是星璃内部的房间模型；ClassIsland 侧仅消费 `radio` 对象，不参与房间逻辑。

---

## 7. 验收清单

- [ ] `flutter analyze` 无新增 error（0 errors）
- [ ] `test/services/now_playing_server_test.dart` 全绿（并入全量测试）
- [ ] Windows 启动 AppShell 后 `http://127.0.0.1:8742/health` 返回 ok
- [ ] 播放中 `http://127.0.0.1:8742/nowplaying` 返回真实曲目；进电台房后 `radio` 出现
- [ ] ClassIsland 插件（M1 交付后）在大屏显示封面/标题/歌手/电台条