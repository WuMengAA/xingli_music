# 电台核心（Radio Station Core） · 产品需求文档（PRD）

> 模块定位：`xingli_music` 社交扩展的**统一核心抽象**
> 文档版本：`0.1.0_draft` · 详尽规格
> 关联文档：[校园点歌（点歌队列）](./PRD_校园点歌系统.md) · [一起听（同步收听）](./PRD_一起听系统.md) · [总览](./README_社交模块.md)
>
> ⚠️ **本文件是战略核心**：校园点歌与一起听均为电台的子能力，统一以本文的「电台房 / DJ / 听众 / RoomCaps」为底座。落地实现以本文件为准。

---

## 1. 定位与演进

- **演进目标**：社交模块最终形态 = **电台（Radio Station）**。
- **校园点歌** = 电台在「校园广播台」场景下的默认开场形态（实名/班级/匿名表白），对应子能力「点歌队列」。
- **一起听** = 电台的「同步收听」子能力（听众跟随 DJ 播放）。
- **代码对齐**：现有 `session_provider` 的 `NetRole.host` + `dj` 字段、`listenState` 消息，已是电台核心实现雏形。

---

## 2. 核心概念

| 概念 | 定义 | 代码对应 |
|---|---|---|
| 电台房 Room | 一个 DJ + N 听众的实时房间 | `RoomState`（`hostSeed`/`hostOptions`/`dj`） |
| 电台 DJ | 播放真值源，控制切歌/进度/审核点歌 | `NetRole.host` + `dj=true` |
| 听众 Listener | 跟随播放、可聊天、可点歌 | `NetRole.client` |
| 能力开关 RoomCaps | 区分电台形态 | 新增，`{ syncListen, acceptOrder }` |
| 同步收听 | DJ 播放态→全员跟随 | `listenState` 广播 |
| 点歌队列 | 听众点歌→DJ 审核→插播 | `orderSong` 系列消息 |

---

## 3. 电台形态矩阵（RoomCaps）

| 形态 | syncListen | acceptOrder | 典型场景 |
|---|---|---|---|
| 校园广播台 | ✅ | ✅ | 校园点歌 + 同步收听 |
| 好友一起听 | ✅ | ❌ | 纯同步听歌 |
| 纯点歌台 | ❌ | ✅ | 仅收点歌不强制同步 |
| 公告台 | ❌ | ❌ | 仅 DJ 播音 + 聊天 |

---

## 4. 功能清单（核心层）

### 4.1 电台房管理
- **F-R1 创建电台**：命名 + 形态（`RoomCaps`）+ 公开/私密（邀请码）。
- **F-R2 发现电台**：局域网发现（LAN discovery 8767）+ 好友列表 + 邀请码加入。
- **F-R3 成员管理**：DJ 可踢人、禁言、转让房主；成员列表实时同步。
- **F-R4 房间生命周期**：DJ 退出触发转让或解散（超时 60s）。

### 4.2 同步底座（被同步收听子能力复用）
- **F-R5 状态真值**：DJ 端 `AudioService`（`nowPlayingProvider`/`isPlayingProvider`/`musicPositionProvider`）为唯一真值源。
- **F-R6 状态广播**：变化即发 `listenState { trackId, isPlaying, positionMs }`，节流 ~500ms。
- **F-R7 进房快照**：新成员进房拉 `roomSnap`（当前曲+进度+歌单+聊天历史）追平。

### 4.3 实时通道
- **F-R8 聊天**：复用 `chat` 消息。
- **F-R9 传输通道（已决）**：relay-server 中转（NAT 打洞失败回退），relay 仅路由不存内容。

---

## 5. 数据模型

```dart
// 电台房（核心）
class RadioRoom {
  final String roomId;
  final String name;
  final String hostPeerId;
  final RoomCaps caps;          // 形态开关
  final bool isPrivate;
  final String? inviteCode;
  final List<String> listenerPeerIds;
}

// 形态开关
class RoomCaps {
  final bool syncListen;   // 同步收听（一起听）
  final bool acceptOrder;  // 点歌队列（校园点歌）
}

// 复用现有：
//   PeerInfo (session_provider) —— 成员，扩展 classroom/role
//   Track (models/track) —— 曲目
//   NetRole.host/client —— DJ/听众
```

---

## 6. 网络消息（汇总两子能力）

| 类型 | 归属 | 方向 |
|---|---|---|
| `listenState` | 同步收听 | DJ→全员（已存在） |
| `requestListen` | 同步收听 | 听众→DJ（已存在） |
| `chat` | 公共 | 双向（已存在） |
| `orderSong` | 点歌队列 | 听众→DJ（新增） |
| `orderAck` / `orderUpdate` | 点歌队列 | DJ→听众（新增） |
| `roomCreate` / `roomList` / `roomJoin` / `roomSnap` | 核心 | 双向 |
| `kickPeer` / `transferHost` | 核心 | DJ→系统 |

---

## 7. 复用清单

| 能力 | 代码 | 用法 |
|---|---|---|
| 联机拓扑 | `session_provider.dart` | `NetRole`/`PeerInfo`/`dj` |
| 消息协议 | `net_message.dart` | `listenState`/`chat`/`requestListen` + 扩展 `orderSong` |
| WebSocket | `net_node.dart` | 长连 |
| 发现 | `lan_discovery.dart` (UDP 8767) | 发现附近电台 |
| 播放真值 | `audio_providers.dart` | `AudioService` + 状态 provider |
| 播放控制 | `playback_notifier` | DJ 切歌/seek |
| 曲目 | `models/track.dart` | 歌单/点歌 |
| 选曲 | `aggregate_search_*` | 加歌/点歌 |
| 通知 | `notification_*` | 邀请/状态变更 |

---

## 8. 权限矩阵（核心层）

| 动作 | DJ | 听众 | 系统 |
|---|---|---|---|
| 创建电台 | ✅ | ❌ | — |
| 播放/暂停/切歌/seek（同步真值） | ✅ | ❌ | — |
| 审核点歌（caps.acceptOrder） | ✅ | 发起 | — |
| 跟随播放（caps.syncListen） | 真值 | ✅ | — |
| 聊天 | ✅(加入后) | ✅ | — |
| 踢人/禁言/转让 | ✅ | ❌ | 超时回收 |
| 解散 | ✅ | ❌ | — |

---

## 9. 非功能需求
- **NF-1 同步精度**：听众与 DJ 偏差稳态 < 1.5s（弱网放宽 3s）；seek 后 2s 内对齐。
- **NF-2 实时性**：点歌→DJ 收件箱 < 1s（局域网）/ < 3s（relay）。
- **NF-3 一致性**：全员队列/状态最终一致（广播 + 进房快照）。
- **NF-4 隐私**：relay 不存储内容；匿名点歌不落昵称。
- **NF-5 复用**：不新建播放引擎，全部走 `AudioService`。

---

## 10. 原型导航（核心页）

### 10.1 电台 Tab（发现）
```
┌─────────────────────────────┐
│  电台  🔍                   │
├─────────────────────────────┤
│ 我的电台 / 进行中            │
│  ┌───────────────────────┐  │
│  │ 🎧 周末蹦迪房 DJ:阿星 │  │
│  │   3人同步中 · 晴天     │  │
│  └───────────────────────┘  │
│ 附近（局域网）               │
│  ┌───────────────────────┐  │
│  │ 📻 晨光广播台 ●LIVE   │  │
│  │   点歌+收听 进行中     │  │
│  └───────────────────────┘  │
│  [ + 创建电台 ]             │
└─────────────────────────────┘
```

### 10.2 创建电台（选形态）
```
┌─────────────────────────────┐
│  创建电台                ✕   │
├─────────────────────────────┤
│  名称：[ 周末蹦迪房     ]    │
│  形态：                      │
│   ☑ 同步收听（一起听）       │
│   ☑ 接受点歌（校园点歌）     │
│  公开 / ☑ 需要邀请码         │
├─────────────────────────────┤
│        [  创 建  ]           │
└─────────────────────────────┘
```

---

## 11. 待评审清单
- [ ] 主播/电台主身份认定（OQ-1）
- [x] 跨公网通道（OQ-2）— relay-server 中转
- [ ] 跨音源不同步降级（OQ-1 听）
- [ ] `listenState` 实际下发触发点核对（OQ-4）
- [x] 点歌/一起听合并为电台房（OQ-3，战略已决）

---

## 12. 后续动作
1. 评审本核心抽象与形态矩阵。
2. 技术核对 `session_provider` 中 `listenState` 是否真正订阅 `musicPositionProvider` 下发。
3. 落地顺序：电台核心（房间/成员/同步底座）→ 点歌队列（MVP：局域网电台）→ 同步收听细化。
4. ASCII 原型成熟后升级 Ardot 高保真。
