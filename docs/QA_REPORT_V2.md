# QA 验收报告 · 星璃音乐空间 v2 增量回归（M1–M6 全量 + v1 R1–R15 回归）

| 项 | 值 |
|---|---|
| 文档版本 | v2.0 |
| 作者 | 严过关（QA 工程师） |
| 项目路径 | `D:\Stellara\Music\xingli_music` |
| 核验基线 | master = `0809157`（ce102f6 T01/T02 → 553ba4f 依赖 → 0809157 场景包导出） |
| 核验方式 | 只读审查 + 静态分析（grep）+ 新增 25 单测 + 6 集成 widget 测试 + `flutter analyze` |
| 核验日期 | 2026-08-09 |
| 结论 | **✅ 通过（P1-1 已修复，第 2 轮回归 33/33 全绿）** |

---

## 1. 执行环境与工程门禁

| 检查项 | 命令 | 结果 |
|---|---|---|
| Flutter SDK | `flutter --version` → 3.44.8 stable（`D:\flutter\bin\flutter`） | ✅ 可用 |
| 静态分析 | `flutter analyze`（含新增 test 文件） | ✅ **No issues found!**（0 error / 0 warning / 0 info） |
| 单元测试 | `flutter test test/qa_v2_unit_test.dart` | ✅ **第 2 轮：25/25 全过**（第 1 轮 23/25，P1-1 修复后 2 例转绿） |
| 集成测试 | `flutter test test/qa_v2_widget_test.dart` | ✅ 7/7 全过（含 P1-1 复验：FolderView 竖屏树 + 横屏 master-detail） |
| 既有回归 | `flutter test test/widget_test.dart` | ✅ 1 用例通过 |
| 测试总量 | 全量 `flutter test` | ✅ **第 2 轮：33 用例 33/33 全绿**（25 单测 + 7 widget 测试 + 1 既有） |
| git 状态 | `git log` | ✅ 修复提交 `4ebbdf4`（fix: M3 folder view unmodifiable list crash）在 master；`android/gradle.properties` 有本地未提交改动（工程师本机构建参数，非提交内容，QA 未改动） |

> ⚠️ 工作树说明：`android/gradle.properties`（-Xmx1536m / daemon=false / kotlin JVM warning）为本地环境改动，不在 v2 提交内，不影响判定。

---

## 2. 总览表

| 模块 | 验收结论 | 说明 |
|---|---|---|
| **A. v1 回归 R1–R15** | ✅ 无回归 | R12/R13 一票否决通过；app.dart 零改动（R7/R8/R9 代码链完整，真机待验） |
| **M1 UI 统一 + 横屏** | ✅ | PageScaffold/Terms/InfoRow/StateChip 单一出处；横屏 800×500 widget 测试无 overflow |
| **M2 探索实验场** | ✅ | ConsentGate 方案 A + 持久化（单测）；实验列表数据驱动；第 6 槽管理；EQ supported 判定；lux null 兜底 |
| **M3 曲库三形态** | ✅（第 2 轮 P1-1 已修复） | 文件夹视图修复后竖屏树 + 横屏 master-detail 均正常；卡片/专辑/搜索/持久化均 ✅ |
| **M4 音源归并** | ✅ | 三组卡片；server_settings_page 瘦身；健康 StateChip；R12 可达 |
| **M5 场景扩展** | ✅ | Scene 新字段 JSON 兼容（单测）；Voxel 控制器全能力（单测）；等距坐标（单测）；小游戏/自定义场景/配色/导出（代码链） |
| **M6 通知中心** | ✅ | 三区块（widget 测试）；播放控制硬绑真实流（代码走查 + widget 测试）；事件日志内存态（单测） |
| **C1 取色铁律** | ✅（附数据类命中说明） | 无 UI 色字面量；命中均为场景数据/预设色板类 |
| **C3 主题作用域** | ✅ | 主 Shell 页 0 命中 palette/design_tokens/app_theme import |

---

## 3. A · v1 回归（R1–R15 逐项复核）

| # | 回归项 | 状态 | 证据 |
|---|---|---|---|
| R1 | 本地音乐扫描 | ✅ | `audio_providers.dart` 链完整，`lib/services/` 扫描零改动（v2 diff 不含） |
| R2 | 本地目录源 | ✅ | `server_settings_page.dart` 本地目录组保留（增/删/启停/重扫） |
| R3 | Subsonic 源 | ✅ | `server_settings_page.dart:73` `SubsonicSource(c).testConnection()` 保留 |
| R4 | 电台源 | ✅ | 公开电台组 + `RadioSource(tags:)` 保留（:74） |
| R5 | 空源回退演示源 | ✅ | `audio_providers.dart:98-100` `all.isEmpty → DemoSource().getTracks()`（行号微移，逻辑不变） |
| R6 | 后台播放 | ⚠️ 真机待验 | `app.dart` v2 **零改动**（diff 空），代码链完整 |
| R7 | 媒体会话/锁屏控件 | ⚠️ 真机待验 | `app.dart` 零改动；`notificationColor: AppColors.accent`（:85）保留 |
| R8 | 耳机断开暂停 | ⚠️ 真机待验 | `app.dart` 零改动，`becomingNoisyEventStream` 保留 |
| R9 | 来电 duck/暂停 | ⚠️ 真机待验 | `app.dart` 零改动，`interruptionEventStream` 保留 |
| R10 | 音量/静音生效 | ✅ | `settings_page.dart:261/280` 均先写 provider 再 `setMusicVolume/setSoundscapeVolume` |
| R11 | 播放模式可达生效 | ✅ | `settings_page.dart:584` `playbackActionsProvider.setMode(m)` |
| R12 | **音源设置页可达（一票否决）** | ✅ | `settings_page.dart:321` `Theme(data: kLightTheme, child: ServerSettingsPage())`；且新页仍可配置服务器/电台/目录 |
| R13 | 场景编辑器可达（一票否决） | ✅ | `settings_page.dart:353` `SceneEditorPage(sceneId: 'rain')` |
| R14 | 场景切换+音景副作用 | ✅ | `app_shell.dart` `ref.listen(activeSceneProvider)` 保留并新增通知事件记录（A5） |
| R15 | 通知栏主题色 #7C6BFF | ✅ | `app.dart:85` `notificationColor: AppColors.accent` |

> v1 遗留 P2 复查：P2-1 曲库网格/点击即播 → **v2 已落地**（CardView/AlbumCard + playbackActions）；P2-3 曲库/设置搜索栏 → **已落地**（AppSearchBar）；P2-2 ScenePage 仍用 SceneCardStack（v2 未要求替换，保留）；P2-4 调色盘 → **v2 已落地**（微光圆点三选一 + SceneColorPanel）；P2-5 PopScope / P2-6 SceneEditor 白字残留 → 非 v2 范围，未变更。

---

## 4. B · v2 新功能逐条验收

### M1 · UI 统一 + 横屏

| 验收项 | 结果 | 证据 |
|---|---|---|
| P0-M1-1 PageScaffold 三区接入 5 Shell 页 + 全屏路由页 | ✅ | `page_scaffold.dart`（标题/搜索/leadingPanel/actions/onBack）；scene/explore/library/settings/home 5 页全部 `PageScaffold`；album_detail/custom_scene_list/edit/voxel_editor/实验页亦接入 |
| P0-M1-2 命名词典单一出处 | ✅（附注） | `naming_dict.dart` 8 实体齐全；grep 全 pages/widgets：硬编码实体名仅 3 处且与 Terms 值一致（`library_page.dart:60` SegmentedButton '专辑'、`server_settings_page.dart:251` 弹窗 '服务器'、`app_dock.dart` Dock 标签），**无「服务器 vs 音源」「设置 vs 设定」冲突** |
| P0-M1-3 InfoRow/StateChip 唯一实现 | ✅ | `info_row.dart`（封面48+歌名+歌手+右对齐时长）被 folder_view detail / album_detail 复用；`state_chip.dart` 被 explore 实验卡 / server_settings 健康 / settings 实验管理复用；grep 无第二份实现 |
| P0-M1-4 横屏 ≥600dp 重排、禁止整屏缩放 | ✅ | `AppSize.landscapeBreakpoint=600`；曲库网格 `SliverGridDelegateWithMaxCrossAxisExtent`（横 220/竖 200）；探索列表 320/280；文件夹横屏 master-detail；无整屏 ScaleTransition/FittedBox；**widget 测试 800×500 三页渲染无 RenderFlex overflow** |
| P1-M1-5 Dock/MiniPlayer 横屏自适应（方案 C） | ✅ | `app_dock.dart` `Center+ConstrainedBox(maxWidth:560)`；`mini_player.dart` `maxWidth:760`；`content_container.dart` `maxWidth:1200`；竖屏 390<560/760 不受影响（代码走查） |
| P1-M1-6 网格列数随宽度调整 | ✅ | 卡片 2→4 列、专辑 2→4 列、探索 ≥2 列均按宽度判定 |

### M2 · 探索实验场

| 验收项 | 结果 | 证据 |
|---|---|---|
| P0-M2-1 首次进入 Gate（方案 A）+ 持久化 | ✅ | `consent_gate.dart` 全屏卡片（实验性/不稳定/数据用途/可随时退出）；「暂不参与」→ 只读条款 + 再次进入（方案 A）；`experimentConsentProvider` 持久化 key `experiment_consent_v1`；**单测：agree/revoke/setEnabled 持久化并重启加载**；widget 测试：首次进入出现 Gate → 同意 → 实验列表 |
| P0-M2-2 实验列表数据驱动 | ✅ | `experimentsProvider` 静态配置表（6 项，含 builder）；`explore_page.dart` 不硬编码清单 |
| P0-M2-3 六实验项入口 | ✅ | recommend/search/equalizer/voxel_game/mood/sensor 全在配置表；实验页均含「实验」StateChip 标识 |
| P0-M2-4 已下线置灰禁入 | ✅（代码路径） | `explore_page.dart:109-119` `retired → Opacity(0.5) + onTap:null`；当前配置无 retired 实项（示例注释保留），逻辑存在 |
| P1-M2-5 设置第 6 槽实验管理 | ✅ | `settings_ui_providers.dart` `SettingsSection.experiment` 第 6 槽；`settings_page.dart` 同意状态/撤销同意/逐项启停（`SwitchListTile` + `setEnabled`） |
| P1-M2-6 隐私说明 | ✅ | `consent_gate.dart` privacyNote + sensor_page/experiment 页内固定文案（本地处理不上传） |
| C 实验 EQ | ✅ | `eq_engine.dart` `supported`（Android true / 其余 false）+ `SimulatedEqEngine`；`equalizer_page.dart:45` `engine.supported ? 'Android 真 EQ' : '模拟层'` + unsupportedNote；**单测：预设表数值与 §3.2.4 一致**；`audio_providers.dart` Android 经 `AudioPipeline(androidAudioEffects:[eq])` 装配 ✅ |
| F 实验传感器 | ✅ | `sensor_service.dart` light（Android-only 兜底 null）+ accelerometer（sensors_plus）；`sensor_providers.dart` lux=null → 遮罩 1.0 + 页面「当前设备不支持」；订阅 dispose 防泄漏 |

### M3 · 曲库三形态

| 验收项 | 结果 | 证据 |
|---|---|---|
| P0-M3-1 SegmentedButton 切换 + 持久化 | ✅ | `library_page.dart:45-70`；`libraryViewStyleProvider` 持久化 key `library_view_style_v1`；**单测：setStyle(album) 持久化并重启加载**；widget 测试：三态渲染 |
| P0-M3-2 卡片样式 2/4 列点击即播 | ✅ | `card_view.dart` `AlbumCard` + `playbackActionsProvider.playTrack`（C6） |
| P0-M3-3 文件夹样式 | ✅（第 2 轮修复后） | `folder_view.dart` buildFolderTree 显式传可变列表（P1-1 已修复）；竖屏树 + 横屏 master-detail 走查通过；新增确定性 widget 测试复验 |
| P0-M3-4 专辑样式 + 详情页 | ✅ | `album_view.dart` 聚合 + `album_detail_page.dart` 复用 InfoRow 点击即播 |
| P1-M3-5 同源 + 搜索三态 + 切换保上下文 | ✅ | 三视图全部 watch `effectiveMusicLibraryProvider`；`library_page._filter` 按标题/歌手/专辑过滤；切换样式不触碰 `nowPlayingProvider`（代码走查无写入） |
| P1-M3-6 加载/错误/空态一致 | ✅ | `state_views.dart` LoadingView/ErrorView/EmptyView + `LibraryEmptyView` 三视图共用 |
| 横屏文件夹 master-detail | ✅（第 2 轮修复后） | 布局代码 + 确定性 widget 测试验证：900×500 下 master（左目录树）+ detail（右 InfoRow 歌曲列表）正常渲染 |

### M4 · 音源归并

| 验收项 | 结果 | 证据 |
|---|---|---|
| P0-M4-1 单一入口 + server_settings_page 瘦身 | ✅ | 设置页「音源」分类单入口（R12）；`server_settings_page.dart` 585 行仅含三组音源卡片 + 增删改测，**全局播放/粒子/关于区块已删除**（grep 0 命中） |
| P0-M4-2 三组卡片（本地目录/Subsonic/公开电台） | ✅ | `_GroupCard` ×3，各组标题 + 添加 + 条目（开关/编辑/删除/测试连接） |
| P0-M4-3 既有能力保留 | ✅ | 目录添加/开关/删除/重扫（`_invalidateLibrary`）、服务器增删改/测试/标签、电台标签配置均在 |
| P1-M4-4 健康状态 StateChip | ✅ | `source_health.dart` + `sourceHealthProvider`（connecting/ok/failed + lastTestedAt + errorDetail）；`_EntryTile` 渲染 `StateChip` + 「上次 HH:MM」；**单测：状态机 + 文案** |

### M5 · 场景扩展 + 2.5D

| 验收项 | 结果 | 证据 |
|---|---|---|
| P0-M5-1 2.5D 音效编辑器 | ✅（代码链） | `voxel_sound_editor_page.dart`：放置/删除（toggleBlock）/试听（SoundBlockMixer preview loop）/撤销/重做/清空/保存；竖屏面板上画布下、横屏左画布右面板 |
| P0-M5-2 自定义场景列表 | ✅ | `custom_scene_list_page.dart` 内置/自定义分组 + 来源标记 + 显示开关 + 新建 |
| P0-M5-3 编辑：名称/描述/心情/图标/显示/BGM 选曲 | ✅ | `custom_scene_edit_page.dart` BGM 从曲库 ChoiceChip 选曲写入 `bgmUri/bgmTitle/bgmArtist`；`visible` 开关 |
| P0-M5-4 配色微光圆点持久化 | ✅ | `scene_page.dart` 右上 40dp 微光圆点三选一 → `SceneColorPanel` → `customScenesProvider.save(scene.copyWith(visual/bgTop/bgBottom/accent))` |
| P1-M5-5 撤销/重做/清空 | ✅ | `voxel_canvas_controller.dart` undo/redo 栈（上限 64）/clear；**单测全过** |
| P1-M5-6 场景包导出 | ✅ | `custom_scene_list_page.dart` `Scenes.encodePack(scene)` + Clipboard（复用 `scene_packer`/`scene_api`） |
| Scene 模型新字段兼容 | ✅ | `scene.dart` visible/bgmUri/bgmTitle/bgmArtist 可空默认；**单测：旧 JSON 反序列化不崩、新字段往返一致** |
| Voxel 坐标 `"$col,$row"` | ✅ | `voxel_canvas_controller.keyOf/parseKey`；**单测：投影正逆变换一致（§3.2.3）** |
| SoundBlockMixer 混音 | ✅（代码链，⚠️ 真机待验） | count→volume（cap 1.0）+ x 位置微调；`preview/stop/dispose`；依赖文件 IO（ogg 查找）未做单测 |
| 小游戏可玩原型 | ✅（代码链，⚠️ 真机待验） | `voxel_minigame_page.dart` Ticker 每 8 tick 移动；方向键/WASD/D-pad；收集 +10 分；清空判胜；重开 |

### M6 · 通知中心

| 验收项 | 结果 | 证据 |
|---|---|---|
| P0-M6-1 三区块合一 | ✅ | `notification_center.dart` ① 运行状态（3 开关）② 媒体控制（封面/歌名歌手/播放暂停/上下首/进度）③ 场景状态（图标/名称/音景开关/快捷切换 chips）+ ④ 最近事件日志；**widget 测试：设置→通知 渲染「运行状态/当前播放/场景状态/最近事件」全部命中** |
| **P0-M6-2 播放控制硬绑真实流（禁本地推断）** | ✅ | 代码走查：`_MediaCard` 只读 `nowPlayingProvider`/`isPlayingProvider`/`musicPositionProvider`/`musicDurationProvider`；动作全走 `playbackActionsProvider` + `runPlaybackAction`（C8 消费）；**无 setState/本地布尔**；场景切换走 `currentSceneIndexProvider` + `audioServiceProvider.switchSoundscape` |
| P1-M6-3 锁屏关闭仍可应用内控制 | ✅ | 媒体卡不依赖 `lockScreenProvider`，恒渲染（代码走查） |
| P2-M6-4 最近事件日志（内存态） | ✅ | `recentNotificationsProvider` + `app_shell.dart` 自动记录播放/切场景事件；**单测：append/clear/上限 50** |

---

## 5. C · 静态合规

### C1 · 无字面量 Color(0x / Colors.white*

`grep -rn "Color(0x" lib/`（排除 core/theme、canvas 孤岛、v1 豁免资产）命中如下，**全部为数据/预设类，非 UI 色**：

| 文件 | 行 | 性质 | 判定 |
|---|---|---|---|
| `models/voxel.dart` | 54-99（6 处） | 2.5D 音效块**预设库**顶面色（数据，渲染块外观，非 UI chrome） | ✅ 数据类（同 §7.9 场景数据精神） |
| `pages/scene/custom_scene_edit_page.dart` | 91/93/203/205 | 新建场景默认视觉（任务明确豁免） | ✅ 豁免 |
| `widgets/scene/scene_color_panel.dart` | 33-51/64 | 配色面板**预设色板**（写入 Scene.visual/bgTop/bgBottom/accent）+ 自定义取色默认值 | ✅ 数据类（面板预设 = 用户可选的场景数据） |
| `providers/theme/theme_providers.dart` | 9 | `0xFF4A3A8A` 默认用户主色 —— **v1 既有** Canvas 暗色孤岛数据层（v2 diff 未改） | ✅ 既有生态（非 v2 回归） |

`Colors.white*`（排除豁免）：**0 命中** ✅

> 说明：按任务字面豁免清单（Scene.visual/bgTop/bgBottom/accent、custom_scene_edit_page 默认色），voxel 预设色与 scene_color_panel 预设色板不在清单内；但按 C1 契约精神（§7.9「场景数据允许 Color(0x...)」）与 v1 先例（scene_editor_page 数据默认值豁免），二者均属**数据/预设**而非 UI 取色，判为豁免。若严格按字面清单执行，可将其视为 P2 观察项（不影响浅色一致性）。

### C3 · 主题作用域铁律

主 Shell 与 4 Tab 页 + Home + 设置子页 grep `core/theme/(palette|design_tokens|app_theme).dart` import：**0 命中** ✅（canvas_page / theme_providers 等暗色孤岛生态除外）。

### 工程门禁

| 门禁 | 结果 |
|---|---|
| `flutter analyze` 0 error / 0 warning / 0 info | ✅ No issues found! |
| 新增依赖 | ✅ 仅 sensors_plus ^7.0.0 + light ^3.0.0（架构 §6 一致） |
| 删除文件 | ✅ 0 |

---

## 6. 缺陷清单

### P1-1 · 文件夹视图 `buildFolderTree` 对非空曲库必崩（P0-M3-3 核心功能失效）—— ✅ 第 2 轮已修复

> **修复状态**：工程师提交 `4ebbdf4` 已修复；QA 独立复验通过（详见 §9 第 2 轮回归结论）。以下为第 1 轮发现记录，保留存档。

- **严重度**：**P1**（P0 需求 M3 文件夹样式完全不可用；不影响其他视图与启动）
- **位置**：
  - `lib/models/library_folder.dart:14-15` —— `children = const <LibraryFolderNode>[]`、`tracks = const <Track>[]`（**不可变 const 列表**）
  - `lib/widgets/library/folder_view.dart:240-268` —— `buildFolderTree()` 构造节点时**未传可变列表**，随后 `current.tracks.add(t)`（:252/:265）与 `current.children.add(child)`（:258）在**任何曲目存在时**抛 `Unsupported operation: Cannot add to an unmodifiable list`
- **失败用例**：`test/qa_v2_unit_test.dart` → `M3 · 文件夹目录树派生`（本地路径建树 / 在线曲目归源）2 例
  - 期望：本地 3 首 → 根节点 trackCount=3、Music→2 专辑子树；在线 1 首 → 「音源」虚拟目录
  - 实际：`Unsupported operation: Cannot add to an unmodifiable list` at `folder_view.dart:261`
- **影响面**：设置任一音源/演示流有曲目后，曲库页切「文件夹」样式即崩溃（竖屏树与横屏 master-detail 均受影响）；`FolderView` 空态（0 首）不触发。
- **建议修复**（工程师执行，QA 未改源码）：`buildFolderTree` 内创建节点时显式传可变列表，如
  ```dart
  LibraryFolderNode root = LibraryFolderNode(name: '全部', pathKey: '/root',
      children: <LibraryFolderNode>[], tracks: <Track>[]);
  // 子节点同理：LibraryFolderNode(name: segs[i], pathKey: path,
  //     children: <LibraryFolderNode>[], tracks: <Track>[]);
  ```
  或把模型默认值改为可增长列表（`this.tracks = <Track>[]` 去掉 const）。修复后重跑 2 例单测 + `flutter analyze`。

### P2 观察项（非阻塞）

| # | 项 | 说明 |
|---|---|---|
| P2-1 | 命名词典未全覆盖 | 3 处硬编码与 Terms 值一致（SegmentedButton '专辑'、服务器弹窗标题、Dock 标签），建议后续统一走 `Terms.*` |
| P2-2 | 无已下线实验实项 | retired 置灰逻辑存在但配置表无 retired 项（示例被注释），无法在 UI 实测置灰禁入 |
| P2-3 | SceneColorPanel 自定义取色范围 | 色相滑块 + 固定饱和/明度（简单取色），符合 PRD「简单取色」 |

---

## 7. 智能路由判定

**第 1 轮（初判）：源码有 Bug → 路由给工程师（FAIL）** —— P1-1 `buildFolderTree` 不可变列表崩溃（详见 §6）。

**第 2 轮（复验后终判）：✅ PASS —— 全部通过，路由 NoOne**

- P1-1 已由工程师提交 `4ebbdf4` 修复（`folder_view.dart` buildFolderTree 根节点与子节点均显式传 `children: <LibraryFolderNode>[]` / `tracks: <Track>[]`，模型默认值保持 const）；
- QA 独立复验（trust but verify）：全量 `flutter test` **33/33 全绿**、`flutter analyze` **No issues found**；
- 修复后新增确定性复验用例：`qa_v2_widget_test.dart` → `P1-1 复验：FolderView 直接渲染非空曲库（竖屏树 + 横屏 master-detail）`（竖屏 400×800 目录树 + 横屏 900×500 master-detail，非空 3 首在线曲目不再抛 Unsupported operation）。
- 无残留源码缺陷；QA 测试自身无未修复项；C1/C3 达标；R12/R13 一票否决通过。

---

## 8. 遗留风险（真机待验 ⚠️）

| 项 | 说明 |
|---|---|
| R6-R9（后台播放/锁屏/耳机/来电） | app.dart 零改动，代码链完整，需 Android 真机验证 |
| AndroidEqualizer 真 EQ | 装配正确（`AudioPipeline(androidAudioEffects:)`）；需真机验证播放中生效（R-04） |
| light lux / 摇一摇 | 桌面无传感器；需 Android 真机验证 lux 数值与加速度阈值 |
| SoundBlockMixer 试听 | 依赖 `minecraft_music/sfx/sounds/*.ogg` 文件 IO；代码链完整，需设备验证 |
| 2.5D 小游戏可玩性 | 逻辑完整（移动/收集/计分/重开），手感需真机/桌面实测 |

---

## 9. 第 2 轮回归结论（P1-1 修复复验）

| 项 | 值 |
|---|---|
| 复验基线 | master 修复提交 `4ebbdf4`（fix: M3 folder view unmodifiable list crash） |
| 复验方式 | 全量测试重跑 + `flutter analyze` + 源码走查 + 新增确定性复验用例 |
| 复验日期 | 2026-08-09 |

### 9.1 复验结果

| 检查 | 命令 | 结果 |
|---|---|---|
| 全量测试 | `flutter test` | ✅ **33/33 全绿**（25 单测 + 7 widget 测试 + 1 既有） |
| 静态分析 | `flutter analyze` | ✅ **No issues found!**（0 error / 0 warning / 0 info） |
| P1-1 单测 | `qa_v2_unit_test.dart` M3 文件夹目录树 2 例（本地路径建树 / 在线曲目归源） | ✅ 由失败转绿 |
| P1-1 集成复验 | `qa_v2_widget_test.dart` P1-1 复验用例（FolderView 直接渲染 3 首在线曲目） | ✅ 竖屏目录树（400×800）+ 横屏 master-detail（900×500）均渲染正常，无 `Unsupported operation` |

### 9.2 修复走查（第 3 项重点）

- **一处修复全覆盖**：`FolderView.build()` 在竖屏/横屏分支**之前**（`folder_view.dart:33`）调用一次 `buildFolderTree(widget.tracks)`，竖屏可展开树与横屏 master-detail 共用同一修复后的函数，无第二处建树逻辑；
- **非空曲库不再崩溃**：根节点与子节点均显式传 `children: <LibraryFolderNode>[]` / `tracks: <Track>[]`，`current.tracks.add()` / `current.children.add()` 不再触碰 const 列表；
- **模型默认值保持 const**：`library_folder.dart` 未改（const 默认值对只读构造安全），修复集中在消费方，符合工程师交付说明；
- 演示流（3 首在线曲目）在应用内切「文件夹」样式亦不再崩溃（由复验用例覆盖同一数据形态）。

### 9.3 终判

**✅ PASS —— 全部通过，路由 NoOne。** P1-1 闭环；v2 六模块（M1–M6）验收通过；v1 R1–R15 无回归；R12/R13 一票否决通过；C1/C3 达标；遗留项仅为真机待验（§8）。

*报告结束。*
