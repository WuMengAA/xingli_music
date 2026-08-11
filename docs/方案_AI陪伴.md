# 星璃音乐 · 场景内 AI 陪伴技术方案（L 域）

> 版本：v1 草案（**仅方案，不含实现**；本文件不改动 `lib/` 任何代码）
> 目标工程：`xingli_music`（Flutter 3.44.8 + flutter_riverpod 2.6.1 + Dart SDK ^3.9.0）
> 对应分派：`docs/TODO_分派方案.md` §十二「L AI陪伴（P3，方案，需先定义）」
> 撰写依据（均为**实际读取源码**，非推测）：
> `lib/models/scene.dart` / `lib/scenes/scene_api.dart` / `lib/providers/scene/scene_providers.dart` /
> `lib/widgets/playback/unified_player.dart` / `lib/app_shell.dart` / `lib/pages/scene/scene_page.dart` /
> `lib/providers/audio/audio_providers.dart` / `lib/providers/audio/playback_notifier.dart` /
> `lib/services/audio/audio_service.dart` / `lib/providers/audio/spatial_providers.dart` /
> `lib/providers/explore/experiment_providers.dart` / `lib/pages/explore/consent_gate.dart` /
> `lib/providers/explore/sensor_providers.dart` / `lib/providers/mood/mood_providers.dart` /
> `lib/providers/session/session_providers.dart` / `lib/providers/settings/notification_providers.dart` /
> `lib/providers/settings/performance_providers.dart` / `lib/repositories/settings_repository.dart` /
> `lib/services/storage/storage_service.dart` / `lib/services/storage/usage_repository.dart` /
> `lib/models/server_config.dart` / `lib/providers/audio/server_config_provider.dart` /
> `lib/models/track.dart` / `pubspec.yaml` / `docs/体素世界技术方案.md` / `docs/PROJECT_STATE.md` / `README.md`

---

## 阅读指引

本文档有一个和其它方案不同的前提：**"AI 陪伴"这个需求目前只有一个名字，没有定义。**

用户在需求勾选里明确要了"AI 陪伴"，但没有说它是什么形态、说什么话、什么时候出现、能不能听见声音、要不要有一张脸。这些不是实现细节，是**产品定义**——定义不同，技术选型、成本、隐私边界、工作量会差 5 倍以上。

所以本文档的写法是：

1. **§1 先给定义建议**（三种形态 A/B/C + 推荐路径），这一节是给用户拍板用的，不拍板后面全是空中楼阁；
2. §2~§7 是**在"推荐路径"假设下**的完整技术方案，如果用户选了别的形态，受影响的章节会在各节开头用 `⚠ 依赖 Q<n>` 标出；
3. **§9 是需用户确认的问题清单**，共 18 条，按"必须先答"/"可延后"分级。

**如果时间只够读两节，请读 §1 与 §9。**

---

## 0.1 定义裁决（2026-08-10 用户拍板，已落实）

用户已对本方案 §9 的核心问题拍板，下文方案据此定型（原 §1「三种形态 A/B/C + 需用户拍板」已无意义）：

- **Q1 形态**：文字气泡（A，内核）+ 体素小人（C2，游戏内陪伴）。**排除 C3 立绘**。
- **Q2 关系**：**陌生人**设定——不是助手/朋友/恋人/咨询师，关系中性、有边界（沿用原 R1~R3 安全约束）。
- **Q3 触发**：**需用户先开启对话**（第一次必须由用户发起，你去接近这个陌生人）；建立联系后它才「活」起来。
- **Q4 主动**：之后**能自己主动发起对话与行动**（在游戏世界里可自主行动：走路/与环境互动等安全可逆行为）。
- **Q5 语音**：TTS 语音**暂押后**（先做文字气泡内核，离线可用；flutter_tts 待用户批准再引入）。
- **Q6 游戏接入**：以体素小人（C2）进入 3D 体素世界与玩家同游；玩家侧（音乐控制）的主动动作仍需用户确认（安全闸），游戏内世界行动可自主。
- **与 E 游戏合并为一个 phase**：随时可动、可加内容（见 `docs/TODO_分派方案.md` v4）。

> 实施顺序据此调整为：Phase 1（模板内核·离线）→ Phase 2（玩家侧气泡 + 安全闸）→ Phase 3（LLM 接入·云端/本地）→ Phase 4（TTS 语音）→ 游戏内 C2 体素小人随 E 的 G-1~G-4 进度接入（M5 体素联动）。

---

## 0. 现状核对（先承认代码里的九个事实）

和体素世界方案一样，先把"地基事实"钉死，方案全部围绕它们展开。以下每一条都已核对源码。

| # | 事实（已核对源码） | 对本方案的影响 |
|---|---|---|
| **F1** | `pubspec.yaml` 依赖里**没有任何 AI / LLM / TTS / STT 相关包**。网络能力只有 `http: ^1.2.2`，哈希只有 `crypto: ^3.0.6`（Subsonic token 用）。 | 任何形态的 AI 陪伴都需要**新增依赖**。而 `docs/TODO_分派方案.md` §十三 约束 2 明确规定「不改 pubspec.yaml，确需新依赖先记 TODO 汇报」。→ 纯文字形态可**零新依赖**（`http` 够用），这是形态 A 最大的工程优势；语音形态必然要新增依赖，需用户批准。 |
| **F2** | 工程内**没有任何 API Key 管理机制**。根目录 `.env` 只有一个 `FIGMA_ACCESS_TOKEN`（且已被 `.gitignore` 第 79~81 行忽略），Flutter 侧没有 `flutter_dotenv` 之类的读取方，App 运行时读不到它。 | 云端 LLM 的 Key 需要**从零设计一套配置与存放机制**。见 §3.3.3 与风险 R5。 |
| **F3** | 已有**用户自填服务端配置**的成熟先例：`ServerConfig`（`type/name/baseUrl/user/password/enabled/tags`）+ `ServerConfigNotifier`（SharedPreferences，key `server_configs`）+ `pages/settings/server_settings_page.dart`。 | AI 服务配置（Base URL / 模型名 / API Key）**可以直接复刻这套结构**，不用发明新范式。UI 也有现成参照。 |
| **F4** | `ServerConfig` 的注释写着「密码等敏感字段存于 flutter_secure_storage」，但**该依赖并不存在**（`grep secure_storage pubspec.yaml` 无结果），且 `toJson()` 里确实不含 `password` 字段——即密码目前**根本没有被持久化**（重启即丢）。 | 不能照抄这个"半成品"。API Key 若要持久化，必须显式决定用什么存（见 Q13）。**这是一个既有技术债，本方案不修，但必须绕开。** |
| **F5** | 已有一套完整的**实验准入 + 隐私同意**范式：`ExperimentConsentNotifier`（SP key `experiment_consent_v1`，`agree()/revoke()/setEnabled(id,on)`）+ `ConsentGate`（全屏同意卡片，含 `privacyNote`：「传感器与心情问卷数据全部在本机处理，不会上传到任何服务器；如需上传会先征得你的二次授权」）+ `experimentsProvider` 配置表（`ExperimentItem{id,name,description,icon,status,builder}`，`status` ∈ experimenting/stable/retired）。 | **AI 陪伴的一期落点应当就是一个 `ExperimentItem`**：零导航风险、零回归面、天然带同意门禁。而且 `privacyNote` 里那句「如需上传会先征得你的二次授权」——**AI 陪伴一旦上云就是在触发这句承诺**，必须做二次同意（见 §4.2）。 |
| **F6** | `AppShell.build()` 里**已经有两个全局 `ref.listen`**：监听 `activeSceneProvider`（切场景 → `minecraftSfxService.ensureScene` + 写通知中心）与 `nowPlayingProvider`（切曲 → 写通知中心）。`recentNotificationsProvider` 是 `StateNotifier<List<NotificationEvent>>`，上限 50 条，**不持久化**。 | 陪伴的"主动开口"触发器**不需要新的监听基础设施**，挂到既有 listen 旁边即可。而且已有"事件 → 一句话"的数据通道（通知中心），陪伴的低成本形态可以先借它跑通。 |
| **F7** | `AudioService` **已有 `setDuck(bool ducked)`**（`audio_service.dart:246`）：ducked 时把音乐音量压到 **0.15**，恢复时回 `_effectiveVolume(_musicVol)`，且**不改变记忆音量**。另有 `playSfx(path, {volume=0.25})` 播一次性音效。场景音景走 `AudioContextConfigFocus.mixWithOthers`（R3，不抢焦点）。 | 语音播报（TTS）**不需要新建音频通道，也不需要抢音频焦点**——直接复用 `setDuck(true)` → 播 → `setDuck(false)`。这让形态 B 的音频集成成本从"高"降到"中"。 |
| **F8** | 场景数据**天生就是可讲解的**：`Scene` 有 `mood`（"静默"/"湿润"/"呼吸"/"温暖"/"余晖"/"寂静"/"深邃"）、`desc`（"远处有微光，呼吸缓慢"这类一句话意象文案）、`soundscape`（"雨声 · 低频嗡鸣"）、`valence`/`energy` 数值坐标、`visual.glyph`。7 个内置场景全部填满。 | **"场景讲解"能力甚至可以不接 LLM**——`desc` + `mood` + `soundscape` 拼装就是合格的讲解词。这是"零 LLM 也能交付一期"的关键依据（见 §3.4 三级降级的 L3）。 |
| **F9** | 性能三档已裁决：`performanceModeProvider` + 派生 `noiseEnabledProvider`/`glassBlurProvider(0/12/20)`/`motionScaleProvider(0.5/1.0)`。用户明确要求：**正常模式 UI 必须完整，只有 powerSave 才能关效果**。另：debug APK 已 **157MB**；Android minSdk 21；需适配手表 412×502。 | 陪伴 UI 的降级只允许挂在 `powerSave` 上。**端侧 LLM 模型（最小可用量级 1~4GB）绝对不能打进 assets**——APK 已经 157MB。见 §3.3.2。 |

另外两条**非代码事实**（来自 `docs/TODO_分派方案.md`）：

- **L 域的执行边界**：「H/I/J/K/L = 只写 docs/ 对应方案 md，不改 lib」。本方案严格遵守。
- **K 域（智能自动化）与本域高度重叠**：K 域包含「AI 歌单推荐、语音控制（STT）」，产出 `docs/方案_智能自动化.md`（**尚未创建**）。→ LLM 客户端、Key 管理、STT 这三块基础设施**两个域都要用**，必须约定归属，否则重复建设。本方案的立场见 §3.1 与风险 R9。

---

## 1. 定义与形态建议（**本节需要用户拍板**）

### 1.1 先把"AI 陪伴"在星璃里的定义框出来

在给形态之前，必须先说清楚一个更根本的问题：**星璃是一个反打扰的产品。**

`README.md` 的设计原则写着四条：意境优先、恰到好处、**习惯性交互（"不要求用户主动打卡，而是通过使用行为自然记录"）**、**极简克制（"界面元素少，操作靠手势，不靠按钮"）**。第一版边界还明确写了"不做社交功能"。

一个话多的 AI 角色和这四条原则是**直接冲突**的。所以本方案给出的定义建议是：

> **星璃的 AI 陪伴 ≠ 聊天机器人。它是"场景的一部分"，而不是"叠在场景上的一个 App"。**
>
> 它的默认状态是**沉默**的；它在**你已经在做的事情**（切场景、切歌、深夜久坐、雨声里发呆）的间隙里说一句话；你想说话时它才接住你。它的语气单位是**一两句**，不是一整段。它的存在感应该接近场景里的一颗星、壁炉里的一声木柴爆响——**你注意到它时会觉得温暖，你不注意时它不存在。**

这个定义会直接推出三条硬约束，后面所有技术设计都受它约束：

| 约束 | 内容 | 技术后果 |
|---|---|---|
| **C1 沉默优先** | 主动开口必须有明确触发条件 + 频率上限 + 一键静音 | 需要"触发器 + 冷却"机制（§3.9.1），不能想说就说 |
| **C2 短句优先** | 单条输出建议 ≤ 40 字（约 2 行气泡），长回答需用户主动追问 | LLM `max_tokens` 压到 120 左右，直接降低 60%+ 的调用成本 |
| **C3 不抢视觉** | 陪伴 UI 不得遮挡场景卡堆核心区与播放器控制键 | 走 Overlay 浮层 + 自动消隐，不改 `UnifiedPlayer` 布局（§5） |

> ⚠ **这个定义本身就是 Q1**，如果用户想要的其实是"一个能长聊的 AI 朋友"，那 C1/C2 全部作废，方案要重写。请务必先确认。

### 1.2 三种可行形态

#### 形态 A · 文字气泡陪聊 + 场景讲解（代号「低语」）

**是什么**：场景页 / 播放器上方浮出一条半透明玻璃气泡，写一两句话。点气泡展开成一个可输入的对话面板（沿用现有 `LiquidGlass` + `_frostedPanel` 视觉语言）。不发声、无形象。

**用户看到的样子**（示意，非最终文案）：

```
   ╭──────────────────────────────────────╮
   │ ✦  雨已经下了二十分钟了。            │
   │    要不要把音景再调低一点？          │
   ╰──────────────────────────────────────╯
        ↑ 6 秒后自动淡出，点一下展开对话
```

**技术构成**：`http` 调云端 LLM（零新依赖）+ 一个 `StateNotifier` 管对话 + 一层 Overlay UI。

| 维度 | 评估 |
|---|---|
| 新增依赖 | **0 个**（`http` 已在） |
| APK 体积增量 | **≈ 0**（纯代码，无资源） |
| 首屏延迟 | 无（沉默态不请求） |
| 单次交互延迟 | 云端 800ms~2.5s（可流式，首字 ~400ms） |
| 与既有音频冲突 | **无** |
| 手表 412×502 可用性 | 好（气泡可缩为单行） |
| 隐私敞口 | 中（文本上云，可匿名化，见 §4） |
| 一期工作量 | **6~9 人日**（含模板降级层） |
| 断网/无 Key 体验 | **仍可用**（降级到模板讲解，见 §3.4） |

#### 形态 B · 语音对话（TTS 播报 +（可选）STT 输入）

**是什么**：在 A 的基础上，陪伴的话**被念出来**；进一步可以按住说话，语音提问。

**关键发现（F7）**：`AudioService.setDuck(true)` 已存在且会把音乐压到 0.15 而不改记忆音量——所以"念一句话"的音频编排是 `setDuck(true)` → TTS 播放 → `setDuck(false)`，**不需要抢音频焦点、不需要新音频通道、不会打断播放**。这比通常的语音助手集成便宜得多。

但 STT（听）是另一回事：它要**麦克风权限**、要处理"音乐正在外放导致回声"、要处理误唤醒。

| 维度 | 评估 |
|---|---|
| 新增依赖 | **2~3 个**：`flutter_tts`（系统 TTS）、`speech_to_text`（系统 STT）、若用云 TTS 还需音频缓存 |
| 新增权限 | **RECORD_AUDIO**（仅 STT）——目前 Manifest 只有 `POST_NOTIFICATIONS` 等，属**新增敏感权限** |
| APK 体积增量 | 系统 TTS/STT：+2~5MB；云 TTS：≈0 但每句都要下载音频 |
| 单次交互延迟 | 系统 TTS 首声 ~300ms；云 TTS 首声 1~3s（要等音频文件） |
| 与既有音频冲突 | **中**：TTS 已有 duck 方案；STT 期间必须**暂停音乐**，否则外放回声会让识别率崩掉 |
| 音质体验 | 系统 TTS **音色机械**，和星璃的意境调性冲突明显；云 TTS 好听但贵且必须上云 |
| 手表可用性 | TTS 好；STT 差（手表麦克风 + 嘈杂环境） |
| 隐私敞口 | **高**（云 TTS/STT = 语音上云；本机 TTS/STT 仍会经过系统厂商服务） |
| 增量工作量 | TTS：**+4~6 人日**；STT：**+6~9 人日** |
| 断网体验 | 系统 TTS 多数机型可离线；STT 多数机型**必须联网** |

> **判断**：TTS 值得做（成本可控 + 沉浸感增益大，深夜闭眼听雨时最有价值）；**STT 建议缓到最后**——它带来一个敏感权限、一个音频冲突、一个识别率风险，换来的只是"少打几个字"。而且 STT 与 K 域「语音控制」是同一块基础设施，应该由 K 域统一建（见 R9）。

#### 形态 C · 虚拟形象 / 角色立绘 + 台词

**是什么**：给陪伴一张"脸"——常驻在场景角落的一个视觉实体。有三种成本梯度：

| 子形态 | 实现 | 体积 | 美术成本 | 与星璃调性 |
|---|---|---|---|---|
| **C1 光点 / 星灵** | 纯 `CustomPaint` 粒子 + 呼吸辉光，**无美术资源** | ≈0 | 0（工程即可） | **极契合**（README 就叫"在星光中流淌的真理之光"，`SceneVisual.glyph` 已有 `✦ ❖ ☘ ☀ ❄ 〰`） |
| **C2 体素小人** | 复用即将到来的 3D 体素渲染器，一个 8×12×4 的体素角色跟着相机 | ≈0（程序生成） | 低 | 契合（与体素世界一致） |
| **C3 立绘 / Live2D** | PNG 立绘多表情，或 Live2D / Spine 运行时 | **+8~40MB**，Live2D 还要 +SDK | **高**（需美术产能，工程解决不了） | **冲突**：二次元立绘和"极简克制 + 意境优先"是两种审美 |

| 维度（以 C3 计） | 评估 |
|---|---|
| 新增依赖 | Live2D/Spine 运行时（Flutter 侧生态弱，可能要写 platform view） |
| APK 体积增量 | **+8~40MB**（当前 debug 已 157MB，F9） |
| 美术成本 | **本项目当前不具备**（无美术资源，`assets/` 只有 icons 与 figma） |
| 增量工作量 | C1：**+2~3 人日**；C2：**+4~6 人日**（且**依赖 E 域体素渲染器先落地**）；C3：**+10~15 人日 + 美术排期** |
| 风险 | C3 一旦定了形象，产品调性就被锁死，后悔成本极高 |

### 1.3 三形态横向对比（一页速查）

| | **A 文字气泡** | **B 语音对话** | **C 虚拟形象** |
|---|---|---|---|
| 定位 | 底座，不可跳过 | A 的**增强层** | A 的**表现层** |
| 能独立成立吗 | ✅ 能 | ❌ 必须先有 A 的对话内核 | ❌ 只是把 A 的话挂到一个形象上 |
| 新依赖 | 0 | 2~3 | C1=0 / C3=1~2 |
| 体积 | ≈0 | +2~5MB | C1≈0 / C3 +8~40MB |
| 一期工作量 | 6~9 人日 | +4~6（TTS）/ +6~9（STT） | C1 +2~3 / C3 +10~15 |
| 沉浸感增益 | 中 | **高**（闭眼场景下最强） | 中高（但可能**打断**意境） |
| 打扰风险 | 低 | **高**（声音无法被忽略） | 中 |
| 隐私敞口 | 中 | 高 | 与 A 同 |
| 手表适配 | 好 | TTS 好 / STT 差 | C1 好 / C3 差 |
| 后悔成本 | 低 | 中 | **高**（形象定了就改不动） |

### 1.4 推荐路径（本方案的建议）

> **推荐：以 A 为底座 → 叠 C1（光点形象，纯代码）→ 叠 B 的 TTS 半边 → STT 与 C3 押后并单独评估。**

理由四条：

1. **A 是唯一的"内核"**——B 和 C 都只是 A 的输出通道。先建 A，B/C 后面随时可加；先建 B/C，等于在没有内核的情况下先修管道。
2. **C1 光点几乎白送**：零依赖、零体积、零美术，而且 `SceneVisual.glyph`（`✦/❖/☘/☀/❄/〰`）+ `SceneVisual.accent` 已经为每个场景准备好了"这个场景的光是什么颜色、什么符号"——**陪伴光点直接吃场景的 accent 色，天生和场景一体**。这是本工程独有的便宜。
3. **TTS 便宜是因为 F7**：`setDuck` 已存在。这个能力如果不用，等于浪费既有资产。
4. **STT 与 C3 是两个"贵且可能后悔"的选择**，都不应该在定义还没被验证的一期里做。

**分层看**：

```
        ┌─────────────────────────────────────────┐
  C1/C3 │ 表现层：光点 / 体素小人 / 立绘           │  ← 可换、可关
        ├─────────────────────────────────────────┤
   B    │ 输出通道：文字气泡 ⇄ TTS 语音            │  ← 可加、可关
        ├─────────────────────────────────────────┤
   A    │ ★ 内核：上下文构造 + 对话状态 + LLM/模板  │  ← 不可跳过
        └─────────────────────────────────────────┘
```

### 1.5 人格设定初稿（⚠ 依赖 Q3，此处仅为讨论靶子）

如果按 §1.1 的定义走，人格应该是这样的——写在这里是为了让用户有个具体的东西可以否定：

| 项 | 建议 | 备注 |
|---|---|---|
| 名字 | **「璃」** 或 **「星璃」** | 与产品同名，避免多出一个需要建立认知的角色名；也可留空（无名字的"存在"更符合意境） |
| 自称 | 尽量不自称 | 避免"我是你的 AI 助手"这类破坏沉浸的话 |
| 语气 | 安静、克制、偶尔一点点幽默；**不热情、不打鸡血、不用感叹号** | 与 `Scene.desc` 的文风一致（"远处有微光，呼吸缓慢"） |
| 长度 | 主动开口 ≤ 25 字；被动回答 ≤ 40 字；用户明确追问才可长 | 对应 C2 |
| 禁区 | 不评价用户品味；不劝导；不追问隐私；不说"你应该" | 情感陪伴最容易翻车的地方 |
| 关系设定 | **"同处一个房间的沉默同伴"**，不是助手、不是恋人、不是心理咨询师 | 恋人向 / 咨询师向都会显著抬高安全与合规成本（见 Q4 与 R8） |

---

## 2. 能力矩阵

五项能力，按"能不能在没有 LLM 的情况下交付"排序。这个排序很重要：**它决定了一期能不能在 K 域 LLM 基础设施就位之前先跑起来。**

### 2.1 总览

| # | 能力 | 一句话 | 输入信号（全部来自既有 provider） | 输出 | 需要 LLM？ | 阶段 |
|---|---|---|---|---|---|---|
| **M1** | **场景与音乐讲解** | 解释"你现在在哪、在听什么" | `activeSceneProvider`（name/mood/desc/soundscape/valence/energy）、`nowPlayingProvider`（title/artist/album/duration） | 1~2 句 | **否**（F8：模板足够） | P1 |
| **M2** | **推荐引导** | 顺着当前情绪推下一首/下一个场景 | 同上 + `effectiveMusicLibraryProvider`、`sceneOrderProvider`、`playModeProvider` | 1 句 + 可点的行动按钮 | 否（可复用现有启发式） | P1 |
| **M3** | **陪聊** | 用户主动说话，它接住 | 用户输入 + M1 的上下文 | 1~3 句 | **是**（无法模板化） | P2 |
| **M4** | **情感陪伴** | 察觉状态变化，主动说一句 | M1 + `moodKindProvider`/`moodWeightProvider`、`lightLuxProvider`、`heartRateProvider`、时间、连续驻留时长、`usage_events` | 1 句，低频 | 建议是（模板易显得机械） | P3 |
| **M5** | **与体素世界互动** | 在 3D 世界里陪你逛、讲你造的东西 | `VoxelSceneCapture`（seed/相机位姿/时相）、`VoxelWorld` 方块统计、`world_audio_engine` 声源 | 1~2 句 + 世界内锚点 | 是 | P4（**阻塞于 E 域**） |

### 2.2 逐项展开

#### M1 · 场景与音乐讲解（P1，**无 LLM 可交付**）

这是整个方案里"性价比最高"的一项，因为 F8：`Scene` 已经自带讲解素材。

可用素材（7 个内置场景全部填满）：

| 场景 id | name | mood | desc | soundscape | valence/energy |
|---|---|---|---|---|---|
| starnight | 星夜 | 静默 | 远处有微光，呼吸缓慢 | 无底噪 · 星光流动 | 0.45 / 0.12 |
| rain | 雨 | 湿润 | 窗玻璃上的水珠缓慢滑落 | 雨声 · 低频嗡鸣 | 0.35 / 0.25 |
| forest | 森林 | 呼吸 | 树影间的光斑轻轻晃动 | 风声 · 鸟鸣（低频） | 0.60 / 0.35 |
| fireplace | 壁炉 | 温暖 | 木柴在火中缓慢裂开 | 火焰噼啪声 | 0.75 / 0.50 |
| dusk | 黄昏 | 余晖 | 天边最后一道光缓缓沉入山脊 | 风声 · 远处蝉鸣 | 0.55 / 0.40 |
| snow | 雪 | 寂静 | 白色的世界，声音被吸走了 | 风 · 高频减弱 | 0.40 / 0.10 |
| ocean | 海底 | 深邃 | 光在水波中弯曲 | 水声 · 低频嗡鸣 | 0.30 / 0.20 |

**无 LLM 的模板讲解**（示例，走 §3.4 的 L3 层）：

- 切到 rain → `「{desc}。这里的声音是{soundscape}。」` → "窗玻璃上的水珠缓慢滑落。这里的声音是雨声 · 低频嗡鸣。"
- 切歌 → `「{title} —— {artist}。和{scene.mood}挺配的。」`
- 高 energy 场景 + 低 energy 曲目 → `「这首比{name}安静一些，也挺好。」`（用 valence/energy 差做条件分支）

**有 LLM 时**：同样的结构化上下文喂给模型，让它换一种说法，避免"第三次切到雨时还是同一句"。

> 关键设计：**模板层不是"LLM 挂了才用的临时方案"，而是常驻的一层。** 它保证断网、无 Key、用户拒绝上云时陪伴依然存在（呼应体素方案的"任何情况不白屏"）。

#### M2 · 推荐引导（P1，**可复用既有实现**）

工程里**已经有一个推荐启发式**：`pages/explore/experiments/recommend_page.dart` 的 `_recommend(all, scene)`——"偏好 valence/energy 与场景接近的曲目"。它已经作为实验 `id: 'recommend'` 上线。

所以 M2 不是从零做推荐，而是**给既有推荐加一个"会说话的入口"**：

```
陪伴气泡：「雨天听这个可能更沉一点 —— 《…》」
          [ 播这首 ]   [ 换一个 ]   [ 不用了 ]
```

点「播这首」→ 直接调 `ref.read(playbackActionsProvider).playTrack(t)`（既有 API，返回提示串）。

> ⚠ **与 K 域重叠**：K 域也要做「AI 歌单推荐」。建议约定：**推荐算法归 K 域，陪伴只负责"把 K 域的推荐结果用人话说出来 + 提供一键执行"**。见 R9。

#### M3 · 陪聊（P2，**必须有 LLM**）

用户点开气泡 → 输入框 → 多轮。

设计要点：
- **多轮窗口不宜大**：建议只带最近 **6 轮**（12 条）+ 一份场景上下文摘要。理由：C2 要求短句，长历史带不来质量提升，只涨 token 成本。
- **每轮都刷新场景上下文**（用户可能聊到一半切了场景/切了歌）——这是"场景内陪伴"和普通聊天 App 的本质区别。
- **会话边界**：切场景是否清空对话？建议**不清空但插入一条系统标记**（"（场景变成了雪）"），让模型知道环境变了。→ 这是 Q7。

#### M4 · 情感陪伴（P3，**最需要 LLM，也最容易翻车**）

可用的"状态信号"在工程里已经全部就绪，但**都还没被接到一起**：

| 信号 | provider | 现状 | 可推断 |
|---|---|---|---|
| 心情类型 | `moodKindProvider`（默认 `'calm'`） | 已有，由心情分析实验写入 | 用户自述情绪 |
| 心情权重 | `moodWeightProvider`（默认 0.4） | 已有 | 情绪强度 |
| 环境光 | `lightLuxProvider` | Android 有值（自写 MethodChannel），其它平台 null | 深夜 / 白天 / 关灯躺着 |
| 心率 | `heartRateProvider` | **多数设备无此传感器 → null** | 紧张 / 平静（极不可靠） |
| 场景驻留 | `currentSceneIndexProvider` + 时间 | 需自行计时 | 发呆 / 频繁切换（焦躁） |
| 历史行为 | `usage_events` 表（sqflite） | 表已有，`logEvent/recent/clear` 已实现 | 长期偏好 |
| 播放状态 | `isPlayingProvider` / `musicPositionProvider` | 已有 | 是否在认真听 |

**触发示例**（全部必须过 §3.9.1 的冷却门）：

| 触发条件 | 陪伴反应 |
|---|---|
| `lux < 10` 且本地时间 23:00~04:00 且连续播放 > 40min | 「这个点了。要不要我把音量慢慢调下去？」+ [ 好 ] [ 不用 ] |
| 同一场景驻留 > 25min 且无任何交互 | 沉默（**什么都不做**——发呆是好事，不要打断） |
| 10 分钟内切换场景 ≥ 5 次 | 「一直在换。要不先停在这儿听完一首？」 |
| 切到 fireplace（valence 0.75，全场景最高） | 「暖起来了。」 |

> ⚠ **红线**：M4 绝不能做"情绪诊断"。不说"你看起来很难过"，只说"这个点了"。理由见 R8。

#### M5 · 与体素世界互动（P4，**阻塞于 E 域**）

`docs/体素世界技术方案.md` 目前是**方案完成、代码暂缓**状态（用户要求"先不着急做游戏"）。所以 M5 是**纯前瞻设计**，不排进前三期。

E 域一旦落地，会给陪伴提供三样它在 2D 里拿不到的东西：

| E 域产物 | 陪伴能做什么 |
|---|---|
| `VoxelSceneCapture{seed, cx/cy/cz, yaw/pitch/fov, phase}`（约 200B，随 Scene 持久化 + 随场景包分享） | 讲解"你把镜头对着的是什么"：解析相机朝向 → 命中的方块类型 → 「你正对着那片水。天快亮了。」 |
| `VoxelWorld`（24×24×20，`seed` 确定性生成） | 统计世界构成（水占比 / 树数量 / 最高点）→ 「这个种子里树特别多。」 |
| `world_audio_engine` 的声源列表 + `SpatialChannel`（前后左右） | 声音导览：「左边有水声，走过去看看？」——**并且陪伴自己的 TTS 也可以走 `SpatialMixer` 做定位**，让它"从某个方向说话" |

**最有意思的一条**：陪伴光点（C1）在 3D 世界里可以变成一个**跟随相机的体素小人（C2）**，它站在你旁边看同一片风景——这是形态 C2 相对 C3 的独有优势：**它天生和世界同构，不需要美术。**

> ⚠ M5 的依赖链：`E 域 Phase 1(渲染器) → E 域 Phase 4(取景/VoxelSceneCapture) → L 域 M5`。E 域 Phase 1~4 自身估算见体素方案 §6。**在 E 域动工之前，M5 不应该占用任何工时。**

---

## 3. 技术架构

### 3.1 分层（与体素方案同构，遵守"渲染/模型层不 import Flutter widgets"的既有铁律）

```
┌───────────────────────────────────────────────────────────────┐
│ UI 层    companion_bubble.dart      浮层气泡（自动消隐）        │
│          companion_panel.dart       展开式对话面板              │
│          companion_orb.dart         C1 光点形象（CustomPaint）  │
│          companion_settings_tile    设置页「陪伴」分类           │
├───────────────────────────────────────────────────────────────┤
│ 编排层   companion_director.dart    ★ 触发器 + 冷却 + 优先级     │
│          companion_actions.dart     把"建议"变成可执行动作       │
├───────────────────────────────────────────────────────────────┤
│ 状态层   companion_providers.dart   Riverpod（§3.6）            │
├───────────────────────────────────────────────────────────────┤
│ 内核层   companion_context.dart     ★ 采集既有 provider → 上下文 │
│          companion_engine.dart      ★ 三级降级调度（§3.4）       │
│          companion_persona.dart     人格/系统提示词/安全规则      │
│          companion_templates.dart   L3 模板库（无 LLM 兜底）      │
├───────────────────────────────────────────────────────────────┤
│ 服务层   llm_client.dart            ☆ LLM 抽象接口 + 云端实现     │
│          llm_config.dart            ☆ 服务配置（仿 ServerConfig） │
│          speech_service.dart        TTS/STT 抽象（形态 B）        │
├───────────────────────────────────────────────────────────────┤
│ 数据层   companion_models.dart      Message/Session/Context/Sug  │
│          companion_repository.dart  对话持久化 + 保留期 + 清除    │
└───────────────────────────────────────────────────────────────┘

★ = L 域自建        ☆ = 建议归属 K 域「智能自动化」，L 域只消费
```

**关于 ☆ 的归属主张**（对应 R9）：`llm_client.dart` / `llm_config.dart` / `speech_service.dart` 这三块是 **K 域（AI 推荐、语音控制）与 L 域（陪伴）共用的基础设施**。本方案的立场是：

> **由 K 域负责建 LLM/STT 基础设施并冻结接口，L 域只作为消费方。** 若 K 域排期晚于 L 域，则 L 域先建一个**最小可用版**放在 `lib/services/ai/` 下，但接口按"将来会被 K 域接管"来设计（纯抽象类 + 一个实现）。**两边都建 = 必然重复 = 必然不一致。这需要用户拍板（Q14）。**

### 3.2 新增文件清单

| 路径 | 职责 | 依赖 | 阶段 |
|---|---|---|---|
| `lib/models/companion_models.dart` | `CompanionMessage` / `CompanionSession` / `CompanionContext` / `CompanionSuggestion` / `CompanionTrigger` + JSON | 无（纯 Dart，可单测） | P1 |
| `lib/services/companion/companion_templates.dart` | L3 模板库：场景讲解 / 切歌 / 时段问候，条件分支 + 变量填充 | models | P1 |
| `lib/services/companion/companion_context.dart` | 从既有 provider 采集 → 组装 `CompanionContext`（含 token 预算裁剪） | 只读 Ref | P1 |
| `lib/services/companion/companion_persona.dart` | 人格定义、系统提示词模板、安全规则（拒答/危机词） | 无 | P2 |
| `lib/services/companion/companion_engine.dart` | 三级降级调度：L1 云端 → L2 端侧 → L3 模板；超时/取消/重试 | 全部 | P2 |
| `lib/services/companion/companion_director.dart` | 主动开口的触发器、冷却、优先级、静音时段 | context + engine | P3 |
| `lib/services/companion/companion_repository.dart` | 对话持久化（sqflite）+ 保留期 + 一键清除 + 导出 | sqflite | P2 |
| `lib/services/ai/llm_client.dart` ☆ | `abstract class LlmClient { Stream<String> complete(LlmRequest) }` + OpenAI 兼容实现 | `http` | P2 |
| `lib/services/ai/llm_config.dart` ☆ | `LlmConfig{provider,baseUrl,model,apiKey,enabled,maxTokens,temperature}` + 持久化（仿 `ServerConfig`，F3） | SP | P2 |
| `lib/services/ai/speech_service.dart` ☆ | TTS/STT 抽象；`SystemTtsService` / `CloudTtsService` | flutter_tts 等 | P4 |
| `lib/providers/companion/companion_providers.dart` | 见 §3.6 | Riverpod | P1 |
| `lib/widgets/companion/companion_bubble.dart` | 浮层气泡（`LiquidGlass` 风格 + 自动淡出 + 点击展开） | Flutter | P1 |
| `lib/widgets/companion/companion_panel.dart` | 展开式对话面板（消息流 + 输入框 + 建议按钮） | Flutter | P2 |
| `lib/widgets/companion/companion_orb.dart` | C1 光点：`CustomPaint` 呼吸辉光，取色 `Scene.visual.accent`，符号 `Scene.visual.glyph` | Flutter | P2 |
| `lib/pages/explore/experiments/companion_page.dart` | **一期落点**：实验页（受 `ConsentGate` 保护） | 全部 | P1 |
| `lib/pages/settings/companion_settings_page.dart` | 服务配置 / 隐私档位 / 频率 / 静音时段 / 清除数据 | 全部 | P2 |
| `test/companion_test.dart` | 模板渲染 / 上下文裁剪 / 冷却逻辑 / 降级路径 / JSON 往返 | — | 全阶段 |

**改动既有文件（最小侵入）**：见 §5，共 5 处，其中 4 处是**纯新增**、1 处是加一个列表项。

### 3.3 LLM 接入：云端 API vs 端侧小模型

#### 3.3.1 结论先行

> **云端 API 为主，端侧模型不进一期，且永远不打包进 APK。**

#### 3.3.2 对比

| 维度 | **云端 API** | **端侧小模型** |
|---|---|---|
| 典型选型 | OpenAI 兼容协议（DeepSeek / 通义 / 智谱 / Moonshot / 自建 vLLM 均兼容同一套 HTTP 接口） | `llama.cpp` (Qwen2.5-1.5B/3B-Instruct GGUF Q4)、MediaPipe LLM Inference (Gemma-2B)、Android AICore/Gemini Nano |
| Flutter 集成 | **`http` 直接发 POST，零新依赖**（SSE 流式也可用 `http` 的 `Stream` 解析） | 需 FFI + 原生库（`.so`），或平台通道；Flutter 侧生态不成熟 |
| 模型体积 | 0 | **Q4 量化后 0.9~2.5GB**（1.5B~3B）。当前 debug APK 已 157MB（F9） |
| 内存占用 | ≈0 | 推理时 1.5~3GB RAM——**Android minSdk 21 的低端机与手表直接出局** |
| 首字延迟 | 400ms~1.5s（取决于服务商） | 冷启动加载模型 3~15s；之后首字 1~4s（中端手机） |
| 生成速度 | 20~80 tok/s | 中端手机 3~12 tok/s（**说一句 30 字的话要 3~8 秒**） |
| 质量 | 好（7B~100B+ 级别） | 1.5B~3B 级别，中文短对话勉强，**人格一致性差、容易跑题** |
| 隐私 | 内容出设备（可匿名化，见 §4） | **完全不出设备** |
| 成本 | 按 token 计费（见 §3.3.4） | 一次性下载，零边际成本 |
| 断网 | ❌ 不可用 | ✅ 可用 |
| 发热/耗电 | 无 | **显著**（持续满载 CPU/GPU）——与"深夜听雨"场景直接冲突 |
| 工作量 | **2~3 人日** | **8~15 人日**（含下载管理、断点续传、存储检查、多 ABI 原生库、降级） |

#### 3.3.3 云端方案的落地形态（复刻 F3 的 `ServerConfig` 范式）

```dart
// lib/services/ai/llm_config.dart（伪代码，非实现）
enum LlmProvider { openaiCompatible, custom }

@immutable
class LlmConfig {
  final LlmProvider provider;
  final String name;        // 配置名，同时作为存储键（仿 ServerConfig.name）
  final String baseUrl;     // 如 https://api.deepseek.com/v1
  final String model;       // 如 deepseek-chat
  final String apiKey;      // ⚠ 存放策略见下 & Q13
  final bool enabled;
  final int maxTokens;      // 默认 120（对应约束 C2）
  final double temperature; // 默认 0.8（陪伴需要一点变化）
  final int timeoutMs;      // 默认 8000
}
```

**API Key 的三条路，必须选一条（Q13）**：

| 路 | 做法 | 泄露风险 | 成本承担方 | 适用 |
|---|---|---|---|---|
| **K1 用户自填** | 设置页里用户粘贴自己的 Key（完全复刻 `server_settings_page` 的交互） | 低（Key 是用户自己的） | **用户** | **个人自用产品的最优解**，本方案推荐 |
| **K2 内置 Key** | Key 硬编码/混淆进 App | **必然泄露**（APK 可反编译，混淆只是拖时间） | 开发者，且会被盗刷 | ❌ 不建议 |
| **K3 自建轻代理** | App → 自己的中转服务 → LLM 厂商；Key 只在服务端 | 低 | 开发者 | 要发行给他人时的唯一正解，但需要一台服务器 + 运维 + 鉴权 |

> README 第一版边界写着「不做云端同步」「不做复杂用户系统（先本地使用）」——**K3 与这两条边界冲突**。所以在当前阶段，**推荐 K1**。

Key 的**存放**（受 F4 的技术债影响，不能照抄）：

- 现状：工程无 `flutter_secure_storage`（F4），且 `ServerConfig.toJson()` 根本不存 password。
- 建议：**一期先存 `SharedPreferences`**（与 `server_configs` 同级别对待，风险相当且不新增依赖），在设置页明确告知"密钥保存在本机应用私有目录"；
- 若用户要求更高安全等级 → 新增 `flutter_secure_storage`（**需批准新依赖**，且注释里提到"Windows 需 VS 安装 ATL 组件"，会影响 H 域桌面构建）。

#### 3.3.4 成本估算（云端，⚠ 依赖 Q1 的"话痨程度"）

按约束 C2（输入约 400 token 上下文，输出 ≤ 120 token）估：

| 使用强度 | 日调用 | 日 token | 月 token | 月成本（按国产模型约 ¥1~2/百万 token 计） |
|---|---|---|---|---|
| 克制（推荐配置：主动开口 ≤ 8 次/天 + 偶尔陪聊） | ~15 | ~8K | ~240K | **< ¥1** |
| 中等（陪聊为主，每天聊 20 轮） | ~40 | ~21K | ~630K | **约 ¥1~2** |
| 话痨（每次切歌切场景都说话 + 长聊） | ~200 | ~104K | ~3.1M | **约 ¥5~10** |

> 结论：**单用户自用的成本可以忽略**。真正的成本风险不是钱，是 **Key 泄露后被盗刷**（R5）与**多用户分发后的成本失控**。

#### 3.3.5 端侧的正确定位

不是"不做"，是"不在一期做，且做的时候按插件式外挂"：

- **绝不进 assets**：沿用体素方案对音频素材的同款策略（"运行时探测外部目录，找不到回落合成，不进 assets"）——模型文件由用户**手动放入**或 App **按需下载**到应用私有目录；
- 只在**用户显式开启"完全离线隐私模式"**时才加载；
- 加载失败/内存不足 → 静默回落到 L3 模板层，**不报错、不白屏**；
- 手表 / minSdk21 低端机 → **直接不提供该选项**。

### 3.4 三级降级（本方案的核心设计）

体素方案有一条铁律叫"**任何情况不白屏**"。陪伴的对应铁律是：

> **任何情况不失语。** 断网、没配 Key、用户拒绝上云、API 超时、余额耗尽——陪伴都必须还能说话，哪怕说的是模板句。

```
用户/触发器发起
      │
      ▼
┌─────────────────────────────────────────────────┐
│ L1 · 云端 LLM                                    │
│  条件：已配置 + 已同意上云 + 有网 + 未超时(8s)    │
│  质量：★★★★  延迟：0.4~2.5s                     │
└─────────────────────────────────────────────────┘
      │ 失败 / 未配置 / 未同意 / 超时 / 用户选了离线档
      ▼
┌─────────────────────────────────────────────────┐
│ L2 · 端侧小模型（P5+，可选，默认关）              │
│  条件：模型已下载 + 设备够格 + 用户显式开启        │
│  质量：★★☆   延迟：1~8s                         │
└─────────────────────────────────────────────────┘
      │ 未启用 / 加载失败 / OOM
      ▼
┌─────────────────────────────────────────────────┐
│ L3 · 本地模板库（★ 常驻，永不失效）                │
│  条件：无                                        │
│  质量：★★（讲解够用，陪聊弱）  延迟：< 1ms        │
│  数据源：Scene.desc/mood/soundscape + Track 元数据│
└─────────────────────────────────────────────────┘
```

**L3 的能力边界要诚实**：模板能做 M1（讲解）、M2（推荐话术）、M4 的简单时段问候；**做不了 M3（自由陪聊）**。所以在 L3 状态下，输入框应当**降级为不可用并给出说明**（"现在只能听我说说场景。想聊天的话，去设置里配一个 AI 服务。"），而不是假装能聊然后答非所问。

**降级必须是静默的**：用户不该看到"错误：请求失败"。唯一的例外是**用户主动发起的陪聊**（M3）在 L3 下无法响应时，必须明确告知（否则用户会以为 App 坏了）。

### 3.5 上下文构造 `CompanionContext`

这是"场景内陪伴"区别于"套壳 ChatGPT"的**唯一技术关键点**：陪伴知道你在哪、在听什么、几点了、屋里亮不亮。

```dart
// lib/models/companion_models.dart（伪代码）
@immutable
class CompanionContext {
  // ── 场景（activeSceneProvider）──
  final String sceneName, sceneMood, sceneDesc, sceneSoundscape;
  final double sceneValence, sceneEnergy;

  // ── 音乐（nowPlayingProvider / musicPositionProvider / playModeProvider）──
  final String? trackTitle, trackArtist, trackAlbum;
  final Duration? position, duration;
  final bool isPlaying;
  final String playMode;              // order/reverse/shuffle/loop

  // ── 音频环境（audio_providers）──
  final bool whiteNoiseOn;            // whiteNoiseEnabledProvider
  final double musicVolume, soundscapeVolume;

  // ── 用户状态（mood / sensor）──
  final String moodKind;              // moodKindProvider，默认 'calm'
  final double moodWeight;            // moodWeightProvider，默认 0.4
  final double? lightLux;             // 仅 Android 有值
  final double? heartRate;            // 多数设备为 null

  // ── 时间与会话 ──
  final DateTime now;
  final Duration sceneDwell;          // 当前场景已停留多久
  final int sceneSwitchesLast10Min;   // 焦躁度指标

  // ── 体素（P4，E 域落地后）──
  final VoxelContextBrief? voxel;     // seed / 相机朝向命中方块 / 时相

  /// 序列化为喂给 LLM 的紧凑结构（隐私档位决定字段裁剪，见 §4.3）
  Map<String, dynamic> toPromptJson(PrivacyLevel level);
}
```

**采集原则**：`companion_context.dart` **只读不写**——用 `ref.read` 而非 `ref.watch`（避免上下文变化导致 UI 重建风暴），且**不新增任何 provider 订阅**，全部消费既有 provider。

**token 预算**：整个上下文 JSON 目标 ≤ 300 token；加系统提示词（人格 + 安全规则，约 250 token）+ 最近 6 轮对话（约 300 token）≈ **850 token 输入**。这就是 §3.3.4 成本估算的依据。

**裁剪顺序**（超预算时从后往前砍）：体素细节 → 传感器 → 播放模式/音量 → 历史轮次 → 曲目专辑。**场景四要素（name/mood/desc/soundscape）与当前曲目永不裁剪**——它们是"场景内"这三个字的全部含义。

### 3.6 Riverpod 状态设计

沿用工程既有风格：`StateProvider` 管开关、`StateNotifierProvider` 管复杂状态、`Provider` 管服务单例、`StreamProvider` 管流。文件落在 `lib/providers/companion/companion_providers.dart`。

```dart
// ── 开关与配置 ─────────────────────────────────────────
/// 陪伴总开关（默认 false —— 沉默优先 C1，用户不开就完全不存在）
final companionEnabledProvider = StateProvider<bool>((ref) => false);

/// 隐私档位（§4.3）。默认 offlineOnly = 绝不上云
final companionPrivacyProvider = StateProvider<PrivacyLevel>(
    (ref) => PrivacyLevel.offlineOnly);

/// 主动开口频率：off / rare(≤3次/天) / normal(≤8次/天)
final companionProactivityProvider = StateProvider<Proactivity>(
    (ref) => Proactivity.rare);

/// 静音时段（如 00:00~07:00 不主动说话）
final companionQuietHoursProvider = StateProvider<QuietHours?>((ref) => null);

/// LLM 服务配置列表（仿 serverConfigsProvider，SP key: 'llm_configs'）
final llmConfigsProvider =
    StateNotifierProvider<LlmConfigNotifier, List<LlmConfig>>(...);

// ── 服务单例 ───────────────────────────────────────────
final llmClientProvider = Provider<LlmClient?>((ref) { /* 无可用配置 → null */ });
final companionEngineProvider = Provider<CompanionEngine>(...);
final companionRepositoryProvider = Provider<CompanionRepository>(...);

// ── 上下文（只读派生，不缓存）──────────────────────────
final companionContextProvider = Provider<CompanionContext>(
    (ref) => CompanionContextBuilder(ref).build());

// ── 会话状态（核心）────────────────────────────────────
/// 当前会话消息列表 + 生成中标志 + 错误态
final companionSessionProvider =
    StateNotifierProvider<CompanionSessionNotifier, CompanionSession>(...);

/// 当前浮层气泡内容（null = 不显示）。由 director 写入，气泡消隐后自动置 null
final companionBubbleProvider = StateProvider<CompanionMessage?>((ref) => null);

/// 流式生成中的增量文本（打字机效果）
final companionStreamingProvider = StateProvider<String>((ref) => '');

// ── 编排（副作用容器，由 AppShell watch 激活）──────────
/// 主动开口编排器：内部 ref.listen 既有 provider，判定触发 + 冷却
/// 参照既有 shakeSceneLinkProvider 的"Provider<void> 里做 ref.listen"范式
final companionDirectorProvider = Provider<void>((ref) { /* ... */ });
```

**三个必须遵守的既有坑**（`docs/PROJECT_STATE.md` §四）：

1. **Provider 初始化期禁改其它 provider** → `CompanionDirector` 的首次触发必须放到 `addPostFrameCallback`，不能在 provider 构造里就写 `companionBubbleProvider`（这正是 `restoreSettings` 被改成普通函数的原因）。
2. **`initState` 禁读 `MediaQuery`** → 气泡的尺寸自适应放到首次 `build`（参照 `UnifiedPlayer._collapsedInit` 的写法）。
3. **测试环境无背景快照时 `LiquidGlass` 退回纯内容** → 气泡用 `LiquidGlass` 时要保证 widget test 里不崩（既有机制已兜住，只需不绕过它）。

### 3.7 TTS / STT 选型（形态 B，⚠ 依赖 Q5）

#### TTS

| 方案 | 依赖 | 体积 | 音质 | 离线 | 隐私 | 延迟 | 工作量 |
|---|---|---|---|---|---|---|---|
| **系统 TTS**（`flutter_tts`） | +1 | +1~2MB | ★★（机械，中文尤其明显） | 多数机型可 | 经系统厂商 | 300ms | 2 人日 |
| **云 TTS**（厂商 REST） | 0（用 `http`）+ 播放走既有 `just_audio` | ≈0 | ★★★★ | ❌ | **语音文本上云** | 1~3s | 4 人日 |
| **端侧神经 TTS** | 原生库 | +30~100MB | ★★★ | ✅ | ✅ | 1~2s | 10+ 人日 |

> **建议**：一期用**系统 TTS**（便宜、离线、可立刻验证"念出来到底好不好"），并在设置里给一句诚实的说明"音色由系统提供"。若用户验证后觉得音色毁气氛，再评估云 TTS。**先验证形态，再投资音质。**

#### STT

| 方案 | 依赖 | 权限 | 离线 | 工作量 |
|---|---|---|---|---|
| **系统 STT**（`speech_to_text`） | +1 | **RECORD_AUDIO** | 多数机型需联网 | 4 人日 |
| **云 STT** | +1（录音）+ `http` | **RECORD_AUDIO** | ❌ | 6~9 人日 |

> **建议**：**推迟，并划归 K 域**（K 域已明确包含「语音控制（STT）」）。L 域不重复建。

#### 与既有音频引擎的编排（关键，基于 F7）

```
【TTS 播报】——不抢焦点、不打断音乐
  1. audioService.setDuck(true)      // 音乐 → 0.15，记忆音量不变
  2. （可选）soundscape 不动          // 音景本就是 mixWithOthers(R3)，无需处理
  3. TTS 播放（系统通道 / 或 just_audio 播云 TTS 返回的音频）
  4. 播完 / 被打断 / 超时 5s
  5. audioService.setDuck(false)     // 恢复
  ⚠ 必须用 try/finally 保证第 5 步一定执行，否则音乐永远卡在 0.15

【STT 录音】——必须真暂停
  1. 记录 isPlaying
  2. audioService.pauseOnly()        // 既有 API
  3. 录音 + 识别（最长 10s）
  4. finally: 若原本在播 → audioService.resume()
  ⚠ 不能只 duck：手机外放 0.15 的音乐仍会被麦克风拾到，识别率崩
```

**并发保护**：TTS 播报与 `MinecraftSfxService.playSfx` 可能撞车（都是短音频）。建议 TTS 走**独立 player 实例**，且 director 在 TTS 期间不再触发新气泡（冷却门天然覆盖）。

**性能档联动**：`powerSave` 档下建议**默认关闭 TTS**（额外音频通道 + 唤醒 CPU）。这符合 F9 的"只有低性能模式才能关效果"。

### 3.8 工具调用（让陪伴"能动手"而不只是"会说话"）

陪伴说"要不要调低一点音量"，如果用户还得自己去拖滑杆，这个陪伴就是失败的。

**做法**：**不使用 LLM 的 function calling**（协议差异大、失败率高、增加 token），改用**受限的结构化建议**——让模型在回答末尾可选地输出一个极简标记，客户端解析成按钮：

```
模型输出：
  夜深了，音乐再轻一点会更好睡。
  [[act:music_volume:0.3]]

客户端渲染：
  ╭────────────────────────────────╮
  │ 夜深了，音乐再轻一点会更好睡。 │
  │        [ 调低音量 ]  [ 不用 ]  │
  ╰────────────────────────────────╯
```

**白名单动作表**（`companion_actions.dart`，全部映射到既有 API，**不新增任何播放/场景控制能力**）：

| 动作标记 | 映射到既有调用 | 备注 |
|---|---|---|
| `play_track:<uri>` | `playbackActionsProvider.playTrack(t)` | uri 必须在当前曲库内，否则丢弃 |
| `next_track` / `prev_track` | `playbackActionsProvider.next(direction: ±1)` | |
| `toggle_play` | `playbackActionsProvider.toggle()` | |
| `switch_scene:<sceneId>` | `currentSceneIndexProvider` + `audioService.switchSoundscape(scene)` | 复刻 `SceneShakeNotifier.nextScene()` 的既有写法 |
| `music_volume:<0..1>` | `musicVolumeProvider` + `audioService.setMusicVolume(v)` | |
| `soundscape_volume:<0..1>` | `soundscapeVolumeProvider` + `audioService.setSoundscapeVolume(v)` | |
| `white_noise:<on\|off>` | `whiteNoiseEnabledProvider` | R4：= 场景音景开关 |
| `play_mode:<order\|shuffle\|loop\|reverse>` | `playModeProvider` | |

**三条硬规则**：

1. **一切动作必须用户点击确认，AI 不得自动执行。** —— 违反这条就等于把播放控制权交给一个会幻觉的模型。
2. **未知标记静默丢弃**（不显示按钮、不报错）。
3. **一条消息最多 2 个动作按钮**（对应 C2/C3 的克制原则）。

### 3.9 与播放器 / 场景 / 体素世界的联动点

#### 3.9.1 触发器与冷却（`companion_director.dart`，主动开口的全部逻辑）

**触发源**（全部基于 F6 —— `AppShell` 已有的 `ref.listen` 范式，不新建基础设施）：

| id | 触发条件 | 优先级 | 冷却 | 能力 |
|---|---|---|---|---|
| `T1_scene_change` | `activeSceneProvider` 变化 | 中 | 同场景 30min 内只讲一次 | M1 |
| `T2_track_change` | `nowPlayingProvider.uri` 变化 | 低 | 10min 内最多 1 次 | M1/M2 |
| `T3_first_open` | 冷启动首帧后 + 5s | 中 | 每次冷启动 1 次 | M1 |
| `T4_long_session` | 连续播放 > 40min | 中 | 每 60min 最多 1 次 | M4 |
| `T5_late_night` | 本地时间 23:00~04:00 且 `lux < 10` | 高 | 每晚 1 次 | M4 |
| `T6_restless` | 10min 内切场景 ≥ 5 次 | 低 | 每 60min 1 次 | M4 |
| `T7_idle_dwell` | 同场景静止 > 25min | — | **永不触发**（发呆不打扰） | — |
| `T8_user_ask` | 用户主动输入 | **最高** | 无冷却 | M3 |

**全局闸门**（任一不满足则直接静默丢弃，连请求都不发）：

```
companionEnabledProvider == true
  && 不在 companionQuietHoursProvider 时段内
  && 今日主动开口计数 < proactivity 上限（rare=3 / normal=8）
  && 距上次开口 ≥ 全局冷却（建议 8 分钟）
  && 用户最近 3 次都没理气泡 → 当日主动开口降级为 0（★ 自适应闭嘴）
  && 当前不在 STT 录音 / TTS 播报中
```

> **"自适应闭嘴"是本设计里最重要的一条**。它让陪伴具备"看脸色"的能力——用户连续忽略就自动安静下来。没有这条，任何频率上限最终都会变成骚扰。

#### 3.9.2 与播放器的联动

- **读**：`nowPlayingProvider` / `isPlayingProvider` / `musicPositionProvider` / `musicDurationProvider` / `playModeProvider` / 音量四件套 → 全部进 `CompanionContext`。
- **写**：只经 §3.8 白名单 + 用户点击。
- **UI**：**不改 `UnifiedPlayer`（739 行）的内部布局**。气泡以 Overlay 形式浮在播放器**上方 8dp**，宽度对齐播放器的 `maxWidth: 560`。理由：`UnifiedPlayer` 同时被 `AppShell`（非场景页）与 `ScenePage` 挂载，改它等于同时改 5 个页面，回归面太大。
- **全屏播放态**：`_FullscreenPlaybackOverlay` 是独立 Overlay。陪伴气泡在此态下应**自动隐藏**（全屏是"专注听歌"的信号）。

#### 3.9.3 与场景的联动

- **读**：`activeSceneProvider` 全字段 + `sceneOrderProvider`（可推荐"下一个场景"）+ `sessionSeedProvider`。
- **视觉一体化**（这是本工程的独有优势）：气泡与光点取色 **`Scene.visual.accent`**，符号取 **`Scene.visual.glyph`**（`✦ ❖ ☘ ☀ ❄ 〰`）。切场景时陪伴的颜色跟着变——**陪伴看起来就像是场景长出来的，而不是贴上去的**。
- **写**：`switch_scene` 动作复刻 `SceneShakeNotifier.nextScene()`（同时改索引 + `switchSoundscape`）。
- **不碰 `Scene` 模型**：陪伴**不需要**给 `Scene` 加任何字段（与体素方案不同）。若将来要做"每个场景有不同人设"，才需要加 `companionPersonaId`——**这是 Q11**。

#### 3.9.4 与体素世界的联动（P4，阻塞于 E 域）

| 联动点 | 依赖 E 域产物 | 说明 |
|---|---|---|
| 世界内讲解 | `VoxelWorld` + `VoxelCamera` | 相机射线命中方块 → 讲解 |
| 取景点评 | `VoxelSceneCapture` | 拍完照说一句"这个角度天光正好" |
| 声音导览 | `world_audio_engine` + `SpatialChannel` | 「左边有水声」 |
| 空间化语音 | `SpatialMixer` / `SpatialPlayer` | 让 TTS 从某个方向传来 |
| 体素形象 C2 | 3D 渲染器 | 跟随相机的体素小人 |

> **强约束**：E 域当前是"方案完成，代码暂缓"。**L 域不得因为 M5 去推动 E 域开工**，也不得在 E 域动工前预留接口——按体素方案 §1.1 的"分层铁律"，接口应由 E 域定义，L 域消费。

---

## 4. 数据隐私

### 4.1 出发点：工程已经做出过一个承诺

`ConsentGate.privacyNote`（`lib/pages/explore/consent_gate.dart:17-19`）原文：

> 「隐私说明：传感器（光线 / 加速度）与心情问卷数据全部在本机处理，**不会上传到任何服务器**；**如需上传会先征得你的二次授权**。」

同页正文还有一条：「数据仅用于本地个性化，不会上传」。`README.md` 的核心机制表也写着「隐私分层：**本地优先**，用户可自主选择是否上传数据」。

**AI 陪伴一旦接云端 LLM，就是这个工程第一次真正把用户数据发出设备。** 而 `CompanionContext` 里恰好包含了承诺中点名的两类数据（传感器 lux / 心率、心情问卷结果 `moodKind`）。

> **因此：AI 陪伴的上云必须走一次独立的、明确的二次授权，不能复用实验总同意。这不是合规洁癖，是兑现代码里已经写下的承诺。**

### 4.2 三层同意结构

```
第一层：实验总同意（已存在）
   ExperimentConsentNotifier / SP key: experiment_consent_v1
   → 进入探索实验室的门票
        ↓
第二层：陪伴功能同意（新增）
   SP key: companion_consent_v1
   → 说明：陪伴会读取当前场景/曲目/时间等状态
   → 此层同意后，L3 模板陪伴即可用（★ 全程不联网，零数据外发）
        ↓
第三层：上云二次授权（新增，★ 关键）
   SP key: companion_cloud_consent_v1
   → 必须逐条列出"会发送什么、不会发送什么"（见 §4.3 表格）
   → 默认【拒绝】。用户不点，永远只有 L3
   → 可随时撤销；撤销后立即降级到 L3，并询问是否清除历史对话
```

**复用既有 UI 范式**：第二、三层直接复刻 `ConsentGate` 的卡片结构（图标 + 标题 + 要点列表 + `privacyNote` + 「同意并进入」/「暂不参与」双按钮）与 `ExperimentConsentNotifier` 的 `agree()/revoke()` 持久化写法。

### 4.3 隐私档位与字段裁剪（用户可选，默认最严）

| 档位 | 上云内容 | 陪伴质量 | 默认 |
|---|---|---|---|
| **P0 `offlineOnly`** | **什么都不发**，纯 L3 模板 | 会讲解，不会聊天 | ★ **默认** |
| **P1 `anonymous`** | 只发**结构化状态摘要**：场景 id/mood/valence/energy、时段（早/午/晚/深夜）、是否在播放、情绪档位。**不发**曲名、艺人、文件路径、原始 lux/心率数值 | 讲解好，陪聊泛泛 | 推荐 |
| **P2 `full`** | P1 + 曲名/艺人/专辑 + 用户输入的对话原文 + 最近 6 轮历史 | 完整 | 需明确勾选 |

**字段级白名单**（`CompanionContext.toPromptJson(level)` 的裁剪表）：

| 字段 | P1 anonymous | P2 full | 永不发送 |
|---|---|---|---|
| 场景 id / name / mood / desc / soundscape | ✅ | ✅ | |
| valence / energy | ✅ | ✅ | |
| 曲名 / 艺人 / 专辑 | ❌ 只发"正在播放：是" | ✅ | |
| **曲目 `uri` / `coverPath` / `extras`** | ❌ | ❌ | ★ **永不**（含本地文件绝对路径，可暴露用户目录结构与真实姓名） |
| 播放进度 / 时长 | 粗粒度（"刚开始/过半/快结束"） | ✅ | |
| 时间 | 只发时段枚举 | 完整时间 | |
| `lightLux` | 只发 `dark/dim/bright` 三档 | 同左（**原始 lux 值不发**） | 原始数值 |
| `heartRate` | ❌ | 只发 `low/normal/high` | ★ **原始 bpm 永不发送**（属健康数据） |
| `moodKind` / `moodWeight` | ✅（枚举 + 一位小数） | ✅ | |
| 用户对话原文 | ❌（P1 下陪聊不可用） | ✅ | |
| 设备标识 / 用户名 / 位置 | ❌ | ❌ | ★ **永不**（本方案不采集，也不新增任何标识符） |
| 曲库全量列表 | ❌ | ❌ | ★ **永不**（推荐时最多带 5 条候选的标题，且仅 P2） |

> **P1 下陪聊不可用是刻意设计**：既然用户不愿意让原话出设备，就不该假装能聊。诚实降级 > 偷偷上传。

### 4.4 本地存储

| 数据 | 位置 | 保留 | 清除 |
|---|---|---|---|
| 对话记录 | **sqflite 新表 `companion_messages`**（`id/session_id/role/content/ts/scene_id`） | 默认 **7 天**（Q12） | 设置页一键清除 + 撤销上云授权时询问 |
| 主动开口计数 / 冷却时间戳 | `SharedPreferences`（`companion.*` 前缀，对齐 `SettingsRepository` 的 `settings.*` 命名习惯） | 滚动 | 随对话一并清 |
| 陪伴触发事件（用于"自适应闭嘴"） | 复用既有 `usage_events` 表，`type='companion'` | 沿用既有策略 | `UsageRepository.clear(type: 'companion')` |
| 服务配置 / API Key | `SharedPreferences`（key `llm_configs`，仿 `server_configs`） | 长期 | 设置页删除配置 |

**为什么对话不复用 `usage_events`**：`usage_events` 是"行为分析"表（`type/payload/ts`），对话是**内容数据**，隐私等级不同，混在一起会让"清除对话"变成"清除全部行为记录"。建议独立表 + 独立清除入口。

> ⚠ 新建表需要 `UsageRepository.open()` 的 `version: 1 → 2` + `onUpgrade`。**这是本方案唯一需要动数据库迁移的地方**，必须写迁移单测（老库升级不丢 `usage_events` 数据）。

### 4.5 必须在 UI 上说清的四句话

设置页「陪伴 · 隐私」区块建议原文（可直接用）：

1. 「陪伴默认**只在本机**工作，不联网。」
2. 「开启 AI 服务后，你的**当前场景与状态摘要**会发送给你自己配置的服务商；**你的音乐文件路径、原始心率、设备信息永远不会被发送**。」
3. 「对话记录保存在本机，默认保留 7 天，可随时清除。」
4. 「API 密钥保存在本机应用私有目录。请使用你自己的密钥。」

---

## 5. 与现有模块的集成点

### 5.1 改动既有文件清单（共 5 处，**全部低风险**）

| 文件 | 改动 | 风险 | 阶段 |
|---|---|---|---|
| `lib/providers/explore/experiment_providers.dart` | `experimentsProvider` 列表**追加一项** `ExperimentItem(id:'companion', name:'AI 陪伴', description:'场景里的一个安静同伴', icon: Icons.auto_awesome_outlined, status: experimenting, builder: () => const CompanionPage())` | **极低**（该表就是为"新增实验只需在此追加"设计的，见其注释） | P1 |
| `lib/app_shell.dart` | `build()` 内加一行 `ref.watch(companionDirectorProvider);`（激活编排器，与既有 `ref.watch(settingsSyncProvider)` / `ref.watch(eqReapplyOnPlayProvider)` 同款）+ Stack 顶部加 `if (companionEnabled) const CompanionBubbleLayer()` | **低**（纯新增，不动既有结构）⚠ 注意文件头「门禁 G1 用 grep 扫本文件全文」的约定——新增 import 不得触碰被禁的暗色画布资产 | P2 |
| `lib/pages/scene/scene_page.dart` | `_showEntrySheet` 的三选一**加第 4 项**「陪伴」（`ListTile`，与既有三项同构） | **极低**（纯加一个 ListTile） | P2 |
| `lib/pages/settings/settings_page.dart` | 设置分类**新增「陪伴」**（参照既有「外观」分类的加法） | 低 | P2 |
| `lib/services/storage/usage_repository.dart` | `open()` 的 `version: 1 → 2` + `onUpgrade` 建 `companion_messages` 表 | **中**（数据库迁移，必须有单测护住） | P2 |

**明确不动的文件**（重要）：

- ❌ `lib/widgets/playback/unified_player.dart`（739 行，被 2 处挂载、影响 5 个页面）→ 气泡走 Overlay，不入侵
- ❌ `lib/models/scene.dart` / `lib/scenes/scene_api.dart` → 陪伴不需要 Scene 加字段，**`packSchemaVersion` 保持 1**（与体素方案要升 2 不冲突）
- ❌ `lib/services/audio/audio_service.dart` → 只调既有 `setDuck` / `pauseOnly` / `resume`，不加方法
- ❌ `lib/providers/audio/*` → 只读，不改
- ❌ `pubspec.yaml`（P1 阶段零新依赖；P4 TTS 阶段才需申请）

### 5.2 陪伴 UI 在各处的出现形态

| 位置 | 形态 | 触发 | 阶段 |
|---|---|---|---|
| **探索 · 实验室** | 独立实验页（完整对话界面 + 调试信息） | 用户主动进入 | **P1（一期唯一落点）** |
| **场景页** | 播放面板上方浮层气泡（宽度对齐 `maxWidth:560`），6s 自动淡出；点击展开面板 | director 触发 / 点光点 | P2 |
| **场景页右上角入口 sheet** | 第 4 项「陪伴」→ 打开对话面板 | 用户主动 | P2 |
| **场景卡堆角落** | C1 光点（呼吸辉光，取 `Scene.visual.accent`），常驻但极淡；有话说时微亮 | 常驻 | P2 |
| **其它三页（曲库/探索/设置）** | **不出现**（保持"陪伴属于场景"的语义） | — | — |
| **`NowPlayingPage`** | 底部一行淡文字（不弹气泡，不打断） | 低频 | P3 |
| **全屏播放 Overlay** | **完全不出现** | — | — |
| **体素世界页** | 世界内锚定气泡 + C2 体素小人 | — | P5（阻塞 E 域） |
| **设置页** | 「陪伴」分类：总开关 / 隐私档位 / 服务配置 / 频率 / 静音时段 / TTS / 清除数据 | — | P2 |

### 5.3 视觉规范（复用既有设计系统，不发明新东西）

| 元素 | 规范 | 来源 |
|---|---|---|
| 气泡容器 | `LiquidGlass(style: GlassStyle.frosted, radius: 20, tint: 0x0AFFFFFF, borderColor: 0x26FFFFFF)` | 复刻 `unified_player.dart` 的 `_frostedPanel(transparent: true)` |
| 最大宽度 | 560 | 对齐 `UnifiedPlayer` 的 `ConstrainedBox` |
| 文字 | `AppTextStyles.body` / `.artist`（次要行） | `core/theme/light_tokens.dart` |
| 主色 | `Scene.visual.accent`（**随场景变**）；回退 `context.appColors.accent` | `models/scene.dart` |
| 符号 | `Scene.visual.glyph`（`✦ ❖ ☘ ☀ ❄ 〰`） | 同上 |
| 动效 | 淡入 280ms `easeOutCubic`；乘以 `motionScaleProvider` | 复刻 `_FullscreenPlaybackOverlay`；`performance_providers.dart` |
| 触控热区 | ≥ 44dp（`AppSize.touchMin`） | 既有约定 C9 |
| 紧凑档（手表 412×502） | 气泡降为**单行 + 省略号**，光点缩到 16dp，展开面板走全屏路由而非浮层 | `ResponsiveLayout` |
| powerSave | 关闭光点粒子动画（变静态点）、关闭气泡模糊（`glassBlurProvider` 已为 0） | F9 |

---

## 6. 分阶段实施 + 工作量估算

切分原则与体素方案一致：**每个 Phase 可独立验收、可独立回滚**。P1 完全不依赖 LLM，因此**不被 K 域阻塞**。

### 依赖标注图例

- 🟢 **无外部依赖**，可立即开工
- 🟡 **依赖「K 智能自动化」域的 LLM 基础设施**（`llm_client` / `llm_config`），若 K 域未就位则 L 域自建最小版（见 §3.1 与 Q14）
- 🔵 **依赖「E 游戏」域体素世界代码落地**（当前"方案完成，代码暂缓"）
- 🔴 **依赖用户拍板 / 新依赖批准**

### Phase 0 · 定义拍板 🔴

**产出**：用户对 §9 问题清单中 **Q1~Q6（必答项）** 的答复。
**工作量**：0 人日（沟通）。
**⚠ 这是硬前置。** 没有 Q1~Q6 的答案，Phase 1 写出来的东西有很大概率要推翻重做。

### Phase 1 · 模板陪伴（零 LLM、零新依赖）🟢

**产出**：
`companion_models.dart` / `companion_templates.dart` / `companion_context.dart` /
`companion_providers.dart`（精简版）/ `companion_bubble.dart` /
`pages/explore/experiments/companion_page.dart` + `experimentsProvider` 追加一项 + `test/companion_test.dart`

**能力**：M1 场景讲解 + M2 推荐话术（复用既有 `_recommend` 启发式）。**不联网、不上传任何数据。**

**验收标准**：
1. 探索实验室出现「AI 陪伴」条目，受 `ConsentGate` 保护，点进去能用。
2. 切换 7 个内置场景，每个都能生成一句**不重复、不出戏**的讲解（同一场景连续 3 次进入，措辞至少 3 种变体）。
3. 切歌能生成一句结合 `Scene.mood` 的短评。
4. 推荐卡点「播这首」→ 真的播起来（走 `playbackActionsProvider.playTrack`）。
5. **全程飞行模式可用**（这条是 Phase 1 的核心价值证明）。
6. 气泡 6s 自动淡出；手表 412×502 下不溢出。
7. `flutter analyze lib` 0 错 0 警；`flutter test` 全绿（现有 50 条 + 新增约 8 条）。

**工作量**：**6~9 人日**
| 拆分 | 人日 |
|---|---|
| 模型 + 模板库（含 7 场景 × 3 变体文案） | 2~3 |
| 上下文采集器 | 1 |
| Providers + 实验页 | 1.5 |
| 气泡组件（含响应式 + 主题联动） | 1.5~2 |
| 单测 + 联调 | 1~1.5 |

### Phase 2 · 云端 LLM 文字陪聊 🟡🔴

**产出**：`llm_client.dart` ☆ / `llm_config.dart` ☆ / `companion_persona.dart` / `companion_engine.dart`（三级降级）/ `companion_repository.dart`（+ 数据库迁移 v1→v2）/ `companion_panel.dart` / `companion_orb.dart` / `companion_settings_page.dart` + 两层新同意

**能力**：M3 陪聊；M1/M2 升级为 LLM 生成。

**验收标准**：
1. 设置页能配置服务（Base URL / 模型 / Key），配置错误有清晰报错，**Key 不出现在任何日志里**（`LogService` 需过滤）。
2. **降级链全通**：拔网 → 自动回 L3 模板，**用户无感**；无 Key → 同上；8s 超时 → 同上。
3. 三层同意齐全；**默认 `offlineOnly`，不点二次授权永远不发一个字节**（用抓包或日志验证）。
4. 隐私 P1 档下，请求体中**不含**曲名、`uri`、原始 lux/bpm（逐字段核对）。
5. 流式输出打字机效果；生成中可取消。
6. 对话落库、7 天清理、一键清除、撤销授权后询问清除，全部可用。
7. **数据库迁移单测**：v1 老库升 v2 后 `usage_events` 数据零丢失。
8. 人格一致性抽检：连续 20 轮不出现"作为一个 AI 助手""我可以帮你"这类破坏沉浸的话。

**工作量**：**9~14 人日**（若 K 域已提供 `llm_client`/`llm_config`，**减 3~4 人日**）
| 拆分 | 人日 |
|---|---|
| LLM 客户端 + 流式解析 + 超时/取消 ☆ | 2~3 |
| 配置模型 + 持久化 + 设置页 ☆ | 2 |
| 人格 / 系统提示词 / 安全规则调优 | 1.5~2 |
| Engine 三级降级 | 1.5 |
| Repository + 数据库迁移 + 单测 | 1.5 |
| 对话面板 UI + 光点 C1 | 2~2.5 |
| 两层同意 UI | 0.5~1 |

### Phase 3 · 主动陪伴（触发器 + 情感）🟡

**产出**：`companion_director.dart` / `companion_actions.dart`（白名单动作）/ 频率与静音时段设置

**能力**：M4；§3.8 的可执行建议。

**验收标准**：
1. T1~T6 触发器逐条可复现（提供调试面板可手动触发）。
2. 冷却与频率上限生效：`rare` 档一天不超过 3 次（跑一天真机日志验证）。
3. **「自适应闭嘴」生效**：连续忽略 3 次气泡后，当日不再主动开口。
4. 静音时段内零主动开口。
5. 动作按钮全部走白名单，**未知标记静默丢弃**；**无任何自动执行**。
6. T7（发呆 25min）**确认不触发**——这条要专门测，因为它是"克制"的底线。

**工作量**：**5~7 人日**

### Phase 4 · TTS 语音播报 🔴（需批准新依赖 `flutter_tts`）

**产出**：`speech_service.dart` ☆（TTS 半边）+ 设置项 + `setDuck` 编排

**验收标准**：
1. 播报期间音乐压到 0.15，**播完精确恢复到用户原音量**（`try/finally` 保证；异常/杀进程后重启也不能卡在 0.15）。
2. 播报不打断音乐、不抢焦点、不影响锁屏控件与通知栏。
3. 与 `MinecraftSfxService` 同时发生时不互相踩踏。
4. `powerSave` 档默认关闭 TTS。
5. 手表上可正常播报。
6. **主观验收（关键）**：真机深夜实听——系统 TTS 音色**是否毁掉了雨夜的意境**。若毁了，止步并重新评估云 TTS（这是一个 go/no-go 闸门）。

**工作量**：**4~6 人日**

### Phase 5 · 体素世界联动 🔵

**产出**：世界内讲解 / 取景点评 / 声音导览 / C2 体素小人

**前置**：E 域 Phase 1（渲染器）+ Phase 4（取景 `VoxelSceneCapture`）已合入。

**工作量**：**6~9 人日**（**E 域未开工前不计入排期**）

### Phase 6 · STT 全语音（建议划归 K 域）🔴🟡

**前置**：新增 `speech_to_text` 依赖 + `RECORD_AUDIO` 权限 + K 域语音控制方案。

**工作量**：**6~9 人日**（本方案**不建议**在 L 域做）

### 汇总

| Phase | 内容 | 人日 | 依赖 | 可交付价值 |
|---|---|---|---|---|
| P0 | 定义拍板 | 0 | 🔴 用户 | 前置 |
| **P1** | **模板陪伴** | **6~9** | 🟢 | **可独立上线，离线可用** |
| P2 | 云端 LLM 陪聊 | 9~14 | 🟡🔴 | 完整陪伴体验 |
| P3 | 主动陪伴 | 5~7 | 🟡 | "活起来" |
| P4 | TTS | 4~6 | 🔴 | 沉浸感跃升 |
| P5 | 体素联动 | 6~9 | 🔵 | 阻塞于 E 域 |
| P6 | STT | 6~9 | 🔴🟡 | 建议归 K 域 |
| | **L 域主线（P1~P4）** | **24~36 人日** | | |
| | 含 P5 | 30~45 人日 | | |

### 依赖关系图

```
        P0 定义拍板（硬前置）
              │
              ▼
        P1 模板陪伴 🟢 ──────────────┐
              │                      │
              ▼                      │
        P2 云端 LLM 🟡🔴             │
         │        │                  │
         ▼        ▼                  ▼
   P3 主动陪伴  P4 TTS 🔴      P5 体素联动 🔵
                              （另需 E 域 Ph1+Ph4）
                    │
                    ▼
              P6 STT 🔴（建议→K 域）
```

**P3 与 P4 可并行**（一个是逻辑、一个是音频）。**P1 可以在 K 域完全没动静时先交付**——这是本排期最重要的性质。

---

## 7. 风险与权衡

| # | 风险 | 严重度 | 触发条件 | 缓释措施 | 关联 |
|---|---|---|---|---|---|
| **R1** | **定义未拍板就动手 → 大面积返工** | 🔴 最高 | Q1~Q6 未答就开始写 P1 | **P0 硬前置**：Q1~Q6 不答，P1 不开工；且 P1 刻意做成"形态无关"（纯模板讲解，A/B/C 都吃） | Q1~Q6 |
| **R2** | **主动开口变成骚扰**，违背"反打扰"产品基因 | 🔴 高 | 冷却/频率/自适应闭嘴任一失效 | 三重闸门（§3.9.1）+ "连续忽略 3 次自动闭嘴" + 静音时段 + 一键总开关 | Q8/Q9 |
| **R3** | **情感陪伴越界**：说出情绪诊断 / 恋人向 / 咨询向话语 | 🔴 高（合规） | M4 上线且提示词约束不足 | 人格禁区（§1.5）+ 输出安全规则（拒答危机词、不说"你看起来很难过"）+ 只描述环境不描述用户 | Q4/R8 |
| **R4** | **LLM 幻觉 → 错误动作**（如切到一个不存在的场景） | 🟡 中 | M3 + §3.8 动作按钮 | 白名单 + 参数校验（uri 必须在曲库内）+ **一切动作需用户点击，AI 绝不自动执行** + 未知标记静默丢弃 | §3.8 |
| **R5** | **API Key 泄露被盗刷** | 🟡 中（成本） | 选了 K2 硬编码方案，或 Key 明文落日志 | **推荐 K1（用户自填）**；Key 不进日志（`LogService` 过滤）；默认 `offlineOnly` 不发任何字节 | Q13 |
| **R6** | **系统 TTS 机械音色毁掉意境** | 🟡 中（体验） | P4 上线且用户主观不接受 | P4 设 **go/no-go 闸门**：真机深夜实听，毁意境即止步，回头评估云 TTS | Q5/Q15 |
| **R7** | **端侧模型拖垮低端机/手表** | 🟡 中 | 错误地把模型打进 assets | 铁律"**永不进 assets**"，仅用户在设置里手动开启 + 加载失败静默回落 L3 + minSdk21/手表直接不提供该选项 | §3.3.5 |
| **R8** | **情感陪伴合规成本失控** | 🟡 中（边界） | 产品想把陪伴做成"树洞/恋人/心理陪伴" | 关系设定**锁定"沉默同伴"**，恋人向/咨询师向会显著抬高安全与合规成本——需 Q4 明确否决 | Q4 |
| **R9** | **K/L 域重复建设 LLM 基础设施** | 🟡 中（效率） | K 域与 L 域各自写一套 `llm_client` | 主张"**K 域建、L 域消费**"；若 K 域晚于 L 域，L 域先建最小版但接口按"将来被接管"设计（抽象类 + 单实现） | Q14 |

> **R1 是全局总风险**：它不直接伤用户，但会让后面 24~36 人日的投入方向跑偏。只要 Q1~Q6 在 P0 阶段被回答，R1 就基本消解，R2~R9 都有明确缓释，不构成阻塞。

---

## 8. 决策摘要（一页速查）

> 同体素方案的"一页速查"风格，给拍板人 60 秒看完。

**这是什么**：在音乐场景里加一个"安静的、沉默优先的同伴"。它会说一两句话，不主动打扰，想聊时你才点开它。

**推荐形态（按优先级叠加）**：

```
A 文字气泡（内核，必做，零新依赖）
   → C1 光点形象（纯代码，吃 Scene.accent 色，几乎白送）
      → B 的 TTS 半边（念出来，复用既有 setDuck，便宜）
         → STT 与 C3 立绘 押后 + 单独评估
```

**三条不可谈判的硬约束**：

1. **C1 沉默优先**——主动开口必须有过触发 + 频率上限 + 一键静音 + 自适应闭嘴。
2. **C2 短句优先**——单条 ≤ 40 字，`max_tokens` 压到 120，直接砍掉 60%+ 成本。
3. **C3 不抢视觉**——走 Overlay 浮层，不改 `UnifiedPlayer` 布局。

**六个"工程已帮我省钱"的事实（F 系列）**：

- F1 文字形态可 **0 新依赖**（`http` 够用）
- F3 配置 UI 直接复刻 `ServerConfig` 范式
- F5 一期落点 = 一个 `ExperimentItem`，天然带同意门禁
- F7 TTS 复用 `setDuck`，音频集成从"高"降到"中"
- F8 场景数据天生可讲解，**无 LLM 也能交付 M1**
- F9 端侧模型**绝不进 APK**（已 157MB）

**最大风险**：**定义没拍板就开工 → 返工**（R1）。P0 阶段回答 Q1~Q6 即消解。

**最重要的工程铁律**：**任何情况不失语**（三级降级 L1 云端 → L2 端侧 → L3 模板）。断网、无 Key、拒上云、超时、被盗刷——陪伴都得能说话，哪怕说模板句。

**工作量与依赖**：

| 阶段 | 人日 | 依赖 | 可独立交付？ |
|---|---|---|---|
| P1 模板陪伴 | 6~9 | 🟢 无 | ✅ 飞行模式可用，**不阻塞于 K 域** |
| P2 云端 LLM 陪聊 | 9~14 | 🟡🔴 | K 域先建则 -3~4 人日 |
| P3 主动陪伴 | 5~7 | 🟡 | — |
| P4 TTS | 4~6 | 🔴 新依赖 | go/no-go 闸门 |
| P5 体素联动 | 6~9 | 🔵 E 域 | 阻塞于 E 域 |
| P6 STT | 6~9 | 🔴🟡 | 建议归 K 域 |
| **L 主线 P1~P4** | **24~36** | | |

**隐私承诺（兑现代码里已有的话）**：`ConsentGate.privacyNote` 写过"如需上传会先征得二次授权"。AI 陪伴第一次真正把数据发出设备，所以必须走**独立二次授权**，默认 `offlineOnly` 不发一个字节。

---

## 9. 需用户确认的问题清单

> 共 **18** 条。标 🔴 **必须先答**（不答 P1 就可能是返工），标 🟡 **可延后**（P2 及之后才会撞到）。
> 标 ★ 的会直接改变工作量级或产品性质。

### 🔴 必须先答（建议 P0 阶段一次性给齐）

| # | 问题 | 影响范围 | 不答的后果 |
|---|---|---|---|
| **Q1** ★ | **「AI 陪伴」到底是个什么东西？** 是本文定义的"场景里的沉默同伴（默认不说话、一两句、不抢视觉）"，还是"一个能长聊的 AI 朋友"？ | 全局。C1/C2/C3 全部约束、所有文案与频率设计 | 写出来的 P1 大概率推翻重做（R1） |
| **Q2** | 是否接受"一期只做 A 文字气泡 + 模板降级（不联网、不上传）"，把语音/形象推后？ | P1 范围、发布节奏 | 若强行塞语音/形象，P1 体积与依赖风险骤增 |
| **Q3** | 人格初稿（§1.5：名「璃」/不自称/安静克制/不热情/不用感叹号）是否接受？有无要改的基调？ | `companion_persona.dart`、系统提示词、安全规则 | 提示词只能拍脑袋写，一致性抽检难达标 |
| **Q4** ★ | 关系设定是否**明确锁定"沉默同伴"**，否决恋人向 / 咨询师向？ | M4 边界、合规成本（R3/R8） | 一旦要做情感向，安全与合规成本数量级上升 |
| **Q5** ★ | 语音形态 B（TTS/STT）是否进入**本期**路线图？先只做 TTS、还是本期纯文字？ | 新依赖 `flutter_tts`、`RECORD_AUDIO` 权限、P4 排期 | 若需求里"陪伴"本就含声音却没规划，后期要补依赖审批 |
| **Q6** ★ | 形象要哪个？C1 光点（纯代码）/ C2 体素小人（等 E 域）/ C3 立绘（美术+体积+审美锁死）？ | 视觉工作量、APK 体积、审美后悔成本（§1.2） | C3 一旦定档，产品调性被锁死，回头极贵 |

### 🟡 可延后（P2 启动前给即可）

| # | 问题 | 影响范围 | 备注 |
|---|---|---|---|
| **Q7** | 切场景时对话**清空还是保留**？（初稿建议：不清空，插入"（场景变成了雪）"系统标记） | M3 会话边界（`companion_session`） | 纯体验细节，P3 前定即可 |
| **Q8** | 主动开口频率**默认值**？`rare`(≤3/天) 还是 `normal`(≤8/天)？ | `companionProactivityProvider` 默认值 | 默认值偏保守更安全（R2） |
| **Q9** | 是否需要**静音时段**默认值（如 00:00~07:00 不主动说话）？ | `companionQuietHoursProvider` 默认值 | 默认 null（不静音）也可，留设置项 |
| **Q10** | M4 情感陪伴**是否要做**？还是一期只做讲解+陪聊？ | P3 排期、传感器接入 | M4 最容易翻车（R3），可押后 |
| **Q11** | 是否要做"**每个场景不同人设**"？ | 是否给 `Scene` 加 `companionPersonaId` 字段 | 加字段会动 `Scene` 模型，违反"不碰 Scene"主张（§3.9.3） |
| **Q12** | 对话记录**保留天数**？（初稿默认 7 天） | `companion_messages` 清理策略 | 涉及隐私，建议给区间选择 |
| **Q13** ★ | **API Key 怎么存**？`SharedPreferences`（零依赖，风险相当 `server_configs`）还是新增 `flutter_secure_storage`（需批依赖，且注释说 Windows 需 VS ATL 组件，影响 H 域桌面构建）？以及 Key 来源走 K1 用户自填 / K2 内置 / K3 自建代理？ | `llm_config.dart` 持久化、R5 | 决定泄露风险与是否要动 `pubspec.yaml` |
| **Q14** ★ | **K 域（智能自动化）与 L 域的 LLM/STT 基础设施归属**：谁建 `llm_client` / `llm_config` / `speech_service`？K 域建 L 域消费，还是 L 域先建最小版？ | §3.1 分层、是否重复建设（R9） | 需两域 owner 一起拍板，否则必然重复 |
| **Q15** | 若 P4 真机实测**系统 TTS 毁意境**，是否愿意额外投入云 TTS（语音上云、更贵）？ | P4 的 go/no-go 后决策 | 闸门设在 P4，不必现在答 |
| **Q16** | 产品**是否计划分发给他人**（而不只是自用）？ | K1 vs K3 选型（§3.3.3） | 自用 → K1；分发 → 必须 K3（需服务器+运维） |
| **Q17** | 是否需要"**导出对话**"功能（给用户的本地备份/查看）？ | `companion_repository` 能力 | 初稿未列，纯增量 |
| **Q18** | E 域体素世界**一旦开工**，M5 体素联动是否**立刻接**，还是等业务验证后再说？ | P5 触发时机 | 阻塞于 E 域，现在答只是预留态度 |

---

### 给拍板人的最短路径

1. 先答 **Q1、Q4、Q5、Q6**（四个带 ★ 的形态/边界问题）——它们决定"做的到底是个什么"。
2. 再答 **Q2、Q3、Q13、Q14**（范围/人格/Key/域归属）——它们决定"怎么建、谁来建、花多少"。
3. 其余 **Q7~Q12、Q15~Q18** 在对应 Phase 启动前给即可，不阻塞 P1。
4. 把上述答案回填本文件 §1 / §3 / §4 对应位置，即可把文档从"草案"转为"可排期"。

**一句话收口**：推荐以 **A 文字气泡为内核 + C1 光点形象 + B(TTS) 半边** 推进，**默认零依赖、零上云、离线可用**，把语音输入与立绘押后单独评估；当前**最大风险是定义未拍板导致返工**，请优先回答 Q1~Q6。

---
