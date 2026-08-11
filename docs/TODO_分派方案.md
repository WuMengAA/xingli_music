# 星璃音乐 · 需求全景与专家分派方案 v4

> 生成：2026-08-10 08:33 · 更新：2026-08-10 18:32（用户裁决）
> 覆盖范围：原 7 域（S/V/A/D/E/F/G）+ 新增 5 域（H 跨平台 / I 音源 / J 社交 / K 智能 / L AI陪伴）+ 保护机制 P
> **平台裁决（2026-08-10）**：当前**仅做 Android + Windows** 两个目标；**Web 暂停作为目标平台投入**（构建/预览保留，但不排期 Web 专属功能）；iOS / macOS / Linux / TV 大屏 / 车载（CarPlay·Android Auto）全部**延后**。
> **游戏 + AI 陪伴合并为一个 Phase**：用户裁决"游戏和 AI 陪伴是一个 phase，随时可动，也可以加内容" → E 与 L 并进，不再暂缓、不互相阻塞。
> **AI 陪伴定义已拍板**：陌生人设定，需用户先开启对话，之后可主动发起对话与行动；接入游戏内以体素小人陪伴；玩家侧（音乐控制）主动动作仍需用户确认（安全闸）。
> **保护机制 P 已立项**（日志脱敏 / 分享码隐私 / 密钥 AES-256 落盘）。
> 总原则：大工程先出方案再实现；低风险模块直接实现。

## 〇、域索引与状态总览

| 域 | 名称 | 代表性需求 | 状态 | 类型 | 优先级 |
|---|---|---|---|---|---|
| S | 稳定性 | 闪退回归 / 删废弃 / 性能复核 | 进行中(派专家) | 实现 | P0 |
| V | 视觉 | 主题配色全局统一 | 进行中(派专家) | 实现 | P1 |
| A | 适配 | 手表 412×502 小屏 | 进行中(派专家) | 实现 | P1 |
| D | 素材 | 音效裁剪压缩 / Minecraft 管线 | 已完成(566MB→4.2MB) | - | - |
| E | 游戏 | 3D 体素世界 + 拍照当场景背景 | **Phase 1 已启动**（与 L 合并） | 实现 | P1 |
| F | 功能 | 歌词 / 网易云音源 | 歌词进行中；网易云 PC Web 取源调研中 | 实现 | P1/P2 |
| G | 工程 | APK 精简 / Web 预览 | APK 进行中；Web 暂停 | 实现 | P2 |
| H | 跨平台 | **仅 Android + Windows**（Web 暂停；iOS/macOS/Linux/TV/车载 延后） | 范围收窄 | 方案 | P2 |
| I | 音源 | 网易云(PC Web 登录取源调研中) / QQ / Spotify / Apple / SMB / DLNA | 调研+实现 | 方案+实现 | P2 |
| J | 社交 | 场景分享码 / 社区场景商店 / 导出 | 待调研 | 方案 | P3 |
| K | 智能 | AI 推荐 / 睡眠定时 / 自动切场景 / 语音控制 | 待调研 | 方案 | P3 |
| L | AI陪伴 | 陌生人设定·接入游戏·可主动行动（与 E 合并） | 定义已拍板；Phase 1 已启动 | 实现 | P1 |
| P | 保护机制 | 日志脱敏 / 分享码隐私 / 密钥 AES-256 落盘 | **已立项(派专家)** | 实现 | P0 |

## 一、S 稳定性（P0，实现）

- S-1 闪退最终回归：连平板（无线 adb 192.168.1.125:35531 或 USB）→ `flutter build apk --debug` → `adb install -r` → 播本地音乐 3 分钟，确认进程存活、无 FATAL。边界：只验证，除非发现新异常点才改 audio_service。
- S-2 删废弃文件：确认 `mini_player.dart`/`scene_playback_panel.dart`/`canvas_page.dart`/`more_panel`/`orb`/`palette_panel`/`reactive_particles`/`scene_particles`/`volume_slider` 无引用后删除；`flutter analyze` 0 错误、`flutter test` 全绿。
- S-3 性能模式复核：确认 normal 模式 blur=12/20、tint 不减淡、动画完整；只有 powerSave 关效果（用户明确要求"不要删 UI，低性能模式才可以关"）。

## 二、V 视觉（P1，实现）

- V-1 主题/配色全局统一：审计所有页面/组件取色路径（硬编码 vs `context.appColors`/`AppColors`/`AppColors`），统一替换；场景视觉"另外说"暂不动。验收：`flutter analyze` 0 错误，全页走主题系统。
- V-2（待定）场景视觉统一：随 G-3 拍照背景一并规划。

## 三、A 适配（P1，实现）

- A-1 手表 412×502：ResponsiveLayout 紧凑档逐屏检查（场景/曲库/探索/设置/播放面板），修溢出与不可点，热区 ≥44dp；只改布局约束不动功能。

## 四、D 素材（已完成）

- 566MB 原始 m4a → 21 个可循环片段共 4.2MB → `assets/audio/` + `manifest.json`；`tools/audio_pipeline/`（inspect/sample/encode.py）。Minecraft 音源管线路线图见 `.codebuddy/plans/Minecraft_素材管线优化路线图_13ac165c.md`，落地待 E 游戏阶段调用。

## 五、E 游戏（P1，与 L 合并推进）

> 用户裁决（2026-08-10）："游戏和 AI 陪伴是一个 phase，随时可动，也可以加内容" → **E 与 L 并进，不再暂缓**。方案见 `docs/体素世界技术方案.md`。
- G-1 3D 体素世界渲染器（相机/渲染/交互/面剔除/深度排序/天空雾）—— **Phase 1 已启动**。
- G-2 世界内空间音效（接 spatial_mixer + 素材管线，按相机朝向/距离定位）—— Phase 3。
- G-3 拍照/选区 → 播放器场景背景（存机位不存像素：seed+相机位姿+fov≈200B；实时背景 18fps 只动水/叶；省电退化为静态 PNG；与 LiquidGlassCapture 互斥）—— Phase 4。
- 与 L 的衔接：AI 陪伴以体素小人（C2）出现在 3D 世界里，随 G-1~G-4 进度接入（M5 体素联动）。

## 六、F 功能（P1/P2，实现）

- F-1 歌词：本地 lrc 解析 + 网易云歌词 API（`api/lyrics`），播放页滚动显示（歌词专家进行中）。
- F-2 网易云音源：**走"官方 PC Web 登录 + 取源"路线**（调研中，见 `docs/方案_音源扩充.md` 新增章节）；登录态 cookie 持久用 AES-256 加密落盘（P 保护机制提供 SecureBox）。

## 七、G 工程（P2，实现）

- G-1 release APK 精简：`flutter build apk --release`（abiFilters arm64+v7a）验证体积与运行（APK 专家进行中）。
- G-2 Web 预览：**暂停作为目标平台投入**（构建/localhost:8899 保留但不排期专属功能）；待 Android + Windows 稳定后复议。

## 八、H 跨平台（P2，方案，范围已收窄）

**用户裁决（2026-08-10）**：当前**仅做 Android + Windows** 两个目标平台；**Web 暂停作为目标平台投入**（构建/预览保留，但不排期 Web 专属功能）；**iOS / macOS / Linux / TV 大屏 / 车载(CarPlay·Android Auto) 全部延后**，待 Android + Windows 稳定后再议。
- 决策记录里曾拍板 iOS 10 / Win 7，但 Flutter 3.44 实际下限为 iOS 13 / Win 10（见 `docs/方案_跨平台扩展.md` F1/F2），届时按可达下限执行。
- 现状：Android（minSdk 21）在跑；Windows 需补桌面构建配置（见跨平台方案 §Windows）；Web 暂不作为目标。
- 详细可行性见 `docs/方案_跨平台扩展.md`（覆盖范围含全平台，执行以本裁决为准）。

## 九、I 音源（P2，方案+实现）

- 网易云（**PC Web 登录取源路线**调研中）/ QQ音乐 / Spotify / Apple Music / 本地网络 SMB / DLNA 投送。现状：本地 + Demo 远端流 + on_audio_query。重点：各平台授权/SDK、版权、与 audio_service 集成、实现顺序。产出 `docs/方案_音源扩充.md`（已补充"PC Web 登录取源"章节）。
- cookie/密钥落盘走 P 保护机制 SecureBox（AES-256）。

## 十、J 社交（P3，方案）

需调研：场景分享码（复用 scene_packer.encodePack，**导入须重写 id 防覆盖内置场景**，见 P）/ 社区场景商店 / 场景·拍照背景导出（图片/视频）。重点：后端方案（自建/BaaS/纯本地）、账号体系、合规。产出 `docs/方案_社交分享.md`。

## 十一、K 智能（P3，方案）

需调研：AI 歌单推荐（基于 Scene mood/valence/energy）/ 睡眠定时器 / 按时间·天气·心率自动切场景（传感器 MethodChannel 光线·心率已写未接）/ 语音控制（STT）。产出 `docs/方案_智能自动化.md`。

## 十二、L AI陪伴（P1，定义已拍板，与 E 合并推进）

**定义已拍板（2026-08-10 用户裁决）**：
- **陌生人设定**：AI 是一个"陌生人"，不是助手/朋友/恋人/咨询师；关系中性、有边界。
- **需用户先开启对话**：第一次必须由用户发起（你去接近这个陌生人）；建立联系后它才"活"起来。
- **可主动发起对话与行动**：之后它能主动说话、在游戏世界里自主行动（走路/与环境互动等安全可逆行为）。
- **接入游戏内陪伴**：以体素小人（C2）形态出现在 3D 世界与玩家同游；玩家侧（音乐控制）的主动动作仍需用户确认（安全闸），游戏内世界行动可自主。
- 形态 = A 文字气泡（内核）+ C2 体素小人（游戏内）；**排除 C3 立绘**。语音 TTS 暂押后。
- 详细设计已更新进 `docs/方案_AI陪伴.md`（新增"定义裁决"小节，Q1~Q6 已答）。
- **与 E 合并为一个 phase，随时可动，可加内容**。

## 十三、执行约束（所有专家遵守）

1. 不碰 git（不 commit/push）；工作区未提交改动为基线。
2. 不改 pubspec.yaml（确需新依赖先记 TODO 汇报，P 保护机制复用现有 `crypto` 包不新增依赖）。
3. 各专家独立工作域，文件不交叉：
   - S=音频服务+构建验证；V=theme/取色；A=布局/ResponsiveLayout；D=tools+assets；
   - E=lib/widgets/voxel(新建相机/渲染/3D视图)+voxel_world(seed)；L=lib/{models,services,providers,widgets}/companion + 实验页（**不碰 app_shell/scene_page/unified_player**，留待后续 phase）；
   - F=lyrics+netease；G=构建配置；H/I/J/K=只写 docs/ 对应方案 md；
   - **P=audio_service(日志脱敏)+models/scene(toJson隐私)+scenes/scene_api(导入重写id)+services/security(新建 SecureBox)**。
4. 完成后汇报：改/建了什么、验证结果、遗留风险。
5. 环境坑：flutter cache 写保护先清 lockfile；磁盘满先清 Temp。

## 十四、P 保护机制（P0，实现，已立项）

> 用户指令"加入保护机制"。针对方案类专家审计出的真实代码级隐私/安全隐患。

- P-1 日志脱敏：审计 `lib/services/audio/audio_service.dart` 及全局日志，凡打印 uri/url/token/路径处一律脱敏（剥离 query 参数、掩码 token），绝不让带凭据的字符串进日志；排查 `app.log` 明文留存机制，确保敏感数据不入日志、必要时缩短留存/加密。
- P-2 分享码隐私：`Scene.toJson()` 序列化用于分享时**不得外泄本机绝对路径**（如 `soundscapePath` 含 `C:\Users\真实用户名\...`）；`scene_api.decodePack` 导入时**重写 id**（分配新 uuid，标记非内置），防止恶意包覆盖内置场景。
- P-3 密钥 AES-256 落盘：新建 `lib/services/security/secure_store.dart`，基于现有 `crypto` 包实现 AES-256 加解密；提供 `SecureBox` 把密文存 SharedPrefs，供网易云 cookie / 未来 API key 使用（即使日志泄露也只见密文）。不直接实现网易云，只提供落盘后端 + 接入钩子。
- 验收：`flutter analyze lib` 0 错误；P-1/P-2 给出改动点说明；P-3 提供 SecureBox 单测或示例。
