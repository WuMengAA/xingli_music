# MEMORY — R33 电台模块深度完善 · 2026-09-04

**目标**：Radio 模块 VoiceHub 风格深度完善 + 代码审查 + 崩溃修复 + UI 美化 + 功能补全

## R32 四项（已完成，8b62653~848882d）
1. 液态玻璃全部流畅档位（`kDefaultPerformancePreset = smooth`）
2. 底部 Dock 离底 12px 悬浮（iOS26 设计标准）
3. 账号后端全做（改密/资料同步，relay cl16 已部署）
4. 电台还原 VoiceHub（点歌悬浮窗 + 房联排队）

## R33 九项（本轮完成，5956ac8~6a5a652）

### 1. Bug 修复（5956ac8）
- **voxel_world_view3d.dart**：L564 加 `late final NetSessionNotifier _netSession;`，initState 注入，dispose 改读字段——修复 `Bad state: Cannot use "ref" after the widget was disposed`
- **local_music_scanner.dart**：L67 修复 MediaStore 不同实现类型不一致（`int`/`String?`），`switch` 多类型容错

### 2. 电台 UI 美化（bfd31d2）—— VoiceHub 风格
- 全页玻璃卡片（`LiquidGlass` frosted 包裹所有卡）
- DJ 卡：头像 + 脉冲光环（`_LivePulse` 呼吸动画组件）+ LIVE 标 + 「DJ 自选」按钮（DJ 端）+ 「你」光晕角标（房主）
- 已播历史条：`已播 X 首 · 今日 Y 首` + 查看按钮
- 正在播放 LIVE mini bar：脉冲 LIVE 标 + 当前曲目 + 进度条 + 时间格式 `m:ss`
- 点歌队列玻璃卡：按状态分组（待审批/待播放）+ 单行折叠（最多 3 条 + 剩余数）
- 成员列表：每行 LiquidGlass 卡片 + DJ 光晕徽章

### 3. DJ 自选播放（8ab1ca7）
- `session_provider.dart` 新增 `djAddToQueue(Track, message)`：DJ 从曲库/在线搜直接塞 approved 队列（无需审批，VoiceHub 排期核心）
- 提取共享 `lib/widgets/social/track_picker.dart`：本地 + 网易云 + 哔哩哔哩双源搜索弹层（供 DJ 自选和听众点歌共用）

### 4. 点歌状态机补全（8817472）
- `session_provider.dart` 新增 `setOrderStatus` / `playOrder` / `markPlayed`
- `_playAsDj` 播放前：把当前 playing 项自动标为 played（**不再丢播放记录**），再把 approved → playing

### 5. 已播历史持久化（ffdc95b）
- 新增 `lib/providers/radio/radio_history_provider.dart`：`PlayedRecord { id, track, fromName, source('dj'|'listener'), at }`，SharedPreferences 存最近 100 条
- 电台页「已播 X 首 · 今日 Y 首」统计条
- `_HistoryPage`：已播历史列表（DJ/听众标记 + 相对时间：刚刚/3m 前/2h 前/MM/DD HH:mm）
- 播放前自动写入 played 记录

### 6. 代码审查清理（b73469e）
- 移除 8 处未用 `path_provider` / `foundation` import
- `voxel_renderer.dart` copyWith 补全 11 个缺失参数 → 消除 10 处 `dead_null_aware_expression` 警告
- `local_music_scanner.dart` switch 重构消除死代码告警
- **analyze 警告：54 → 34**（降 20，剩余均为 pre-existing info-level）

### 7. 队列分色统计（6a5a652）
- `order_queue_page.dart` 队列头按状态分类计数：待审批/待播/播放中/已播/已拒，VoiceHub 风格色 chip
- 听众和 DJ 一眼看清排队情况

## 服务端（relay）
- **Relay 版本**：cl16 已部署（PID 5672，端口 8092）
- 账号后端：`/api/auth/change-password` PUT 路由（旧密码校验→重加盐）；`_authUpdateProfile`（displayName≤32/avatar≤512）
- 广播协议：`orderQueue` / `orderDecision` / `listenState` 三类——DJ 自选、审批、播放、一起听全部走现有广播通道，**无需 relay 新增路由**（`_broadcastOrderQueue` 全量同步）

## Push 通道
- 已确认：URL 内嵌 token `https://x-access-token:<PAT>@github.com/WuMengAA/xingli_music.git`（绕过 GCM GUI 弹窗）
- 本地 `~/.git-credentials` 存 token
- 每次 push 后 `git fetch origin main` 同步 tracking ref，`git log --oneline origin/main..main` 验证

## 关键文件清单
- `lib/pages/social/station_room_page.dart`（763→871 行）：全页 VoiceHub 玻璃 + DJ 徽章 + 已播条 + LIVE mini bar + 历史页
- `lib/pages/social/order_queue_page.dart`：队列分色统计 + played 记录写入 + DJ 播放状态流转
- `lib/providers/net/session_provider.dart`：`djAddToQueue` + `setOrderStatus` + `playOrder` + `markPlayed`
- `lib/providers/radio/radio_history_provider.dart`（新建）：PlayedRecord + SharedPreferences 持久化
- `lib/widgets/social/track_picker.dart`（新建）：共享选曲弹层（本地 + 网易云 + 哔哩哔哩）
- `lib/widgets/social/order_floating_card.dart`（R32 新建，R33 未动）：点歌悬浮窗
- `lib/widgets/liquid_glass.dart`：玻璃组件 API（R32 已定型，R33 未改）
- `lib/services/audio/local_music_scanner.dart`：MediaStore 容错修复

## 关键组件 API 速查
- `LiquidGlass{child,radius=24,style,GlassStyle.frosted|liquid,blur,tint,borderColor,refraction=5,dispersion=1.2,padding,forceGlass}`
- `OrderItem{id,track,fromId,fromName,message,anonymous,status,at}`
- `OrderStatus{pending/approved/playing/played/rejected}`
- `OrderStatus.playing` 单例：任意时刻最多 1 首（由 `markPlayed` 前置清理保证）

## R33 剩余 / 未做
- VoiceHub 排期拖拽（需自定义拖放 + 持久化，成本较高，未做）
- 多音源在电台上下文显式切换 UI（网易云/哔哩哔哩/本地，需新增 provider，未做）
- **版本 `0.26.8.31_beta_cl04`**（`lib/core/app_version.dart`：buildCount 3→4，changelog 新增 cl04 条目）
- 全量 147 既有 info 未处理（属 pre-existing，非 R33 新增）

## 听众端 toast 通知（6208a25）
- `NetSessionState` 新增 `notifyId`（toast 文案）、`lastNotifyTrackUri`（去重字段）
- `orderDecision`：听众收到自己点歌的审批结果 → `你的点歌已被 DJ 批准 ✓` / `拒绝 ✗`
- `listenState` 换曲：`DJ 正在播放《X》`（lastNotifyTrackUri 去重，不重复弹）
- `NetSessionNotifier.resetNotify()` 消费后清空
- `order_queue_page.dart` 使用 `Consumer` + `bottomSheet` 监听并弹 SnackBar

## 关键约束
- 短回、直接、要证据、不反复确认
- 逐文件 `git add <path>`，绝不 `git add -A`
- Hindsight 401（apiToken 未配置），记忆走 docs md
- 工作目录 `D:\Stellara\Music\xingli_music`

## ⚠️ 严重回归修复（2f14f1c，2026-09-04）
- **事故**：上轮用 PowerShell `ReadAllText+Replace+WriteAllText(UTF8 no BOM)` 批量编辑时，
  把 4 个源文件损坏成 **UTF-8↔GBK 双重编码 mojibake + 注释与代码合并行 + 字符串字面量截断**
  （`/// 注释...€?final StateProvider...` 同一行，注释吞掉后续声明），并已 push 到 GitHub。
  损坏文件：`settings_layout_provider.dart` / `favorites_page.dart` / `local_music_scanner.dart` / `lyrics_view.dart`。
  症状：settingsLayoutProvider/loadSettingsLayoutAsset 等符号消失 → 级联全项目 parse error（0 编译）。
- **诊断要点**：`flutter analyze` 的 parse error 是金标准；git status/diff 可能因
  autocrlf 归一化显示 clean（用 `git rev-parse HEAD:<path>` + `Get-FileHash` 对比能发现 blob 已损坏）；
  纯 strict-UTF8 校验检测不出 mojibake（是合法 UTF-8，只是内容错）。
- **修复**：从历史干净 commit 恢复——`settings_layout_provider@96be26b` /
  `local_music_scanner@5956ac8` / `favorites_page@d315414` / `lyrics_view@d315414` /
  `settings_item_registry@13d7a76`（`git restore --source=<commit> -- <path>`）。
  补回 app_shell 误删的 `settings_layout_provider` 导入（loadSettingsLayoutAsset 调用点，
  因 provider 损坏被误判 unused）。
- **铁律**：所有文件编辑只用 `edit`/`write` 工具，**禁用 PowerShell 写文件**（WriteAllText/Replace 是事故根因）。
- **结果**：analyze 0 error 0 warning（后续已全部清完，见下）。
- **voxel_world_view3d 历史遗留**：曾有 botched edit（删 _idleDelay 且叠两个 @visibleForTesting），已 revert。
- 新增：station_room_page DJ 卡 LIVE 标旁音源指示 chip（本地/网易/B站/环境音）。

## 后续清理（444ca67 / ab8bb7d，2026-09-04）
- **444ca67** voxel_world_view3d 死代码大扫除：11 个未用字段/方法全清（-183 行）→ warning 11→0。
  - 纯死声明：`_idleDelay` / `_autoOrbit` / `_entitiesFor` / `_bodyWaterRatio` / `_queueJump` / `_LiftPad` / `_HoldButton`
  - 旧输入处理器 `_press`/`_release`（被 `_onKey`/`_onJumpButtonDown` 取代，跳跃由 `_fpJumpQueued`/`_held` 实现）
  - 写了从未读字段：`_idle`(+8 写入) / `_mcSelected`(+2 写入) / `_brokeInHold`(+1 写入)
  - `_openSaveMenu` 保留备用——修好 `// ignore: unused_element`（原规则名被中文吃掉失效；须紧贴声明上一行）
  - 移除因删 `_entitiesFor` 变未用的 `companion_models` import
- **ab8bb7d** info 级清理 32 处：5 unused import / 7 prefer_final / 4 const / 重命名(p_extension→pExtension,
  _sumFaces→sumFaces, _rot→rot) / 闭包改函数声明 / 字符串插值&花括号 / 文档注释尖括号。
  info 84→52。
- **01e5bdd** VoiceHub 多音源显式切换：`dj_audio_source_provider.dart`（DjAudioSource{local,netease,bilibili}，
  SharedPreferences 键 `dj_audio_source`）；DJ 卡源 chip 仅 host 可点（PopupMenu 切换 + toast）；听众仍只读指示；
  TrackPicker 加 `initialSource`（默认 local 保持听众行为）——在线按偏好平台过滤（网易只出网易/B站只出B站）。
- **当前状态**：analyze 0 error 0 warning；剩 52 条 info（19 use_build_context_synchronously / 18 deprecated /
  10 voxel_world_view3d curly_braces 等，非阻塞，后续可清）。

## R33 收尾四项（ab3c6cb / 958ea35，2026-09-04）
- **ab3c6cb** 剩余 52 条 info 全清 → **analyze 0 error 0 warning 0 info（全项目零告警）**：
  - curly_braces×9（voxel_world_view3d if 块补花括号）
  - use_build_context_synchronously×19：await gap 后补 mounted/context.mounted 守卫
    （教训：State.context 用 `mounted` 检查；其他 BuildContext（参数/闭包捕获）用 `context.mounted`/`ctx.mounted`；
    守卫被其他条件 `&&` 组合时拆成独立 exit 守卫）
  - deprecated×18：Radio→**RadioGroup 祖先**（`RadioGroup<T>(groupValue,onChanged,child)`，Radio 去掉
    groupValue/onChanged；注意 flutter widgets/radio_group.dart）；`Share.shareXFiles`→
    `SharePlus.instance.share(ShareParams(files:...,subject:...,text:...))`；`onReorder`→`onReorderItem`
    **（onReorderItem 的 newIndex 已预偏移，回调内绝不能再手动 `b-1`，否则双重偏移）**；
    activeColor→activeThumbColor；withOpacity→withValues
  - library_private_types：`lodCellGet/lodCellPut` 改 `_lodCellGet/_lodCellPut`
- **958ea35** 三项功能收尾：
  - **白噪音默认关闭**：`whiteNoiseEnabledProvider` 默认 false；settings_repository 持久化默认 false
    （老用户已开启不受影响）；Scene.whiteNoise 构造默认 + json 解析默认均 false
  - **OOBE 改版**（原生极简方向）：内容窄栏聚焦（maxWidth 420 居中）、标题 22→26/w700、副题行高 1.5、
    进度点 active 光晕、品牌页锚定 `AppVersion.displayShort`
  - **字体背景颜色自适应**：新增共享工具 `core/theme/adaptive_text_color.dart`（`adaptiveForeground(bg)`，
    WCAG computeLuminance 阈值 0.5）；落地 voxel_world_view3d `_drawNameTag`（玩家名标签底色=实体色可深可浅，
    底亮深字/底暗白字，修复浅色实体名白字看不清）
- **返回原点**：push 后 `git fetch <token-url> main` + `update-ref refs/remotes/origin/main FETCH_HEAD` 同步 tracking。

## R33 收尾⑤（4016ff1 / 15bbabb，2026-09-04）
- **4016ff1** VoiceHub 排期管理拖拽：
  - `session_provider.reorderApproved(oldIndex,newIndex)`（approved 子列表内移动，newIndex 已按移除项偏移；
    非 approved 保持原序、approved 段排后，全量广播 orderQueue）
  - `order_queue_page` 队列按状态分组：非 approved 平铺 + approved「待播」独立小节；
    DJ 端 ReorderableListView.builder + ReorderableDragStartListener（仅手柄可拖，提示「按住 ≡ 拖拽排序」），听众只读
- **15bbabb** OOBE 改版走查（widget test 驱动的真实修复）：
  - **2 处 ListTile debug 断言修复**：`_contractTile`(ExpansionTile)/`_switchRow`(SwitchListTile) 外层
    DecoratedBox 改 **Material**(color+shape+clip)——ListTile 家族必须在 Material 上画背景/波纹，
    DecoratedBox 触发 "ListTile background color or ink splashes may be invisible"（真机 debug 也崩）
  - `_capCard` 宽度改 LayoutBuilder 按父约束算（原按全屏宽，桌面宽屏溢出 420 窄栏）
  - 新增 `test/oobe_layout_test.dart`：1280×800 前 6 页 + 360×720 品牌页无溢出冒烟测试
    （要点：`prefsProvider` 必须 override（default 抛 UnimplementedError）；品牌页徽章无限动画
    → 禁 pumpAndSettle 用固定时长 pump）
  - 验证：`flutter build windows --debug` 通过；`flutter test test/` 2/2 通过
- **测试基建备注**：项目此前无 test/；OOBE 冒烟测试是首个，全流程
  `SharedPreferences.setMockInitialValues` → `prefsProvider.overrideWithValue` → pump。
