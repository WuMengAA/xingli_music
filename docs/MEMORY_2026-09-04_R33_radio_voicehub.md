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

## 发布：0.26.9.3_beta_cl05（2026-09-03，7bec661 + 35c8092 + GitHub Release）
- ⚠️ 版本日期教训：首版误写成 9 月 4 日（0.26.9.4_beta_cl05）并建了 GitHub Release，
  用户纠正「今天是 9 月 3」→ 修正 app_version day 4→3 + changelog 版本串，删掉错误
  release/tag（API DELETE），重建 0.26.9.3_beta_cl05 并重新上传资产。**发版前先跟用户
  确认今天日期**，勿按会话假设推版本号
- 版本号：month 8→9、day 31→3（今天 2026-09-03）、buildCount 4→5；changelog 顶部加 cl05 条目
- 构建：`flutter build windows --release` 通过；`tools/publish_windows_ota.ps1` 里 **tar 打包失败
  （系统无 tar.exe）** → 手动 `Compress-Archive`（平铺 Release 目录）+ `Get-FileHash` 生成 sha256
- **publish_pages_ota.ps1 两个坑**（已修复并提交 35c8092）：
  ① `flutter build apk | Out-Host` 的 stderr 镜像提示被 PS 当 NativeCommandError → 配合
  `$ErrorActionPreference='Stop'` 中断脚本 → 改 `2>&1 | ForEach-Object { $_.ToString() }` + 显式查 exit
  ② **edit 工具重写 .ps1 会丢 UTF-8 BOM** → PS 按 ANSI 解析中文 → 括号/引号错配语法错；
  修完必须字节级补回 EF BB BF（`ReadAllBytes` + 前置 3 字节，勿走文本解码）
  ③ raw.githubusercontent 被墙 → 旧 manifest 拉取加 GitHub API 兜底（contents API base64 解码）
- GitHub Release：gh CLI 未装 → REST API（POST /releases → uploads.github.com 传 asset）。
  body 用 `[System.IO.File]::ReadAllText(path, UTF8)` 读字符串（`Get-Content -Raw` 会被
  ConvertTo-Json 整形对象而 422）；请求体 UTF-8 字节数组防中文乱码
- 资产：`xingli_music_windows_x64.zip`（36.9 MB，平铺 exe+dll+data）+
  `xingli_music_windows_x64.zip.sha256`（`<hash>  xingli_music_windows_x64.zip`，ascii 无换行）
- 发布地址：https://github.com/WuMengAA/xingli_music/releases/tag/0.26.9.3_beta_cl05

## OTA（gh-pages）发布实战（2026-09-03，0.26.9.3_beta_cl05）
- **网络现状**：github.com API/Releases 上传通；raw.githubusercontent 被墙；git 协议 clone/push
  大对象（gh-pages 分支 121MB 历史）持续超时 → `publish_pages_ota.ps1` 全自动流程跑不通
- **最终方案（API 重建分支，绕开 git 协议）**：
  ① 大文件（APK/zip）**不上 gh-pages**，全放 **Releases**（uploads.github.com 通，zip 37MB/APK 43MB 均成功）
  ② gh-pages manifest 新 tag **只列 Windows zip**（安卓资产缺失 → 客户端 `assetFor` 为 null →
     自动回退 Releases URL 下载 APK——正是 ota_service.downloadAndVerify 的设计）
  ③ 分支更新走 git trees/commits API：`base_tree=旧root tree` + 增量 tree 条目（新 zip blob +
     新 manifest blob）→ POST /git/commits（parent=旧 tip）→ PATCH /git/refs/heads/gh-pages
  ④ blob 上传：<40MB 可 API（zip 37MB 成功）；>40MB（APK 43MB）报 "input too large" 422 → 只能走 Releases
- **API 重建分支要点**：blob sha 由内容决定（本地 `git hash-object` 与 API 一致——zip 实测 f2237aae 相同）；
  无需本地 clone/旧 blob，tree 里直接引用远端已有 blob sha 即可
- **验证**：`https://wumengaa.github.io/xingli_music/ota/manifest.json` 200，latest=0.26.9.3_beta_cl05，
  新 zip 可下载且 sha256 与本地一致；versions 保留历史（cl03/cl01）
- **客户端约定**（ota_service.dart）：Pages URL = `wumengaa.github.io/xingli_music/ota/<tag>/<asset>`；
  manifest 无该平台资产 → Releases URL `github.com/<owner>/<repo>/releases/download/<tag>/<asset>`
  且 sha256 从 manifest（Pages）或 .sha256 资产（Releases）取
- **publish_pages_ota.ps1 已修**（fb94edd/e3877f2）：EAP Stop→Continue + flutter build 2>&1 透传 +
  raw 拉取失败 API 兜底 + UTF-8 BOM（edit 工具重写 .ps1 会丢 BOM → 字节级补回 EF BB BF）

## 安卓黑屏修复 + 性能优化（2026-09-03，6fe4c00/baee4a8/5268bc9）
用户反馈：安卓启动/开机就黑屏 + 间歇性偶发黑。三处根因修复：
- **6fe4c00** ① `ThrottledWidgetsBinding` 加 500ms 看门狗——节流 Timer 挂起/帧丢失时强制补帧
  （R22 曾因 Timer 无限挂起致双端开机黑屏；R33 再加兜底防帧饿死）；
  ② `LiquidGlassWidgets.initialize()` 预热 try-catch + 4s 超时——预热抛异常不再卡死启动（降级继续）
- **baee4a8** `NormalTheme` 窗口底色 `?android:colorBackground`（深色=纯黑）→ `@color/launch_background_color`
  品牌深紫——splash → Flutter 首帧之间不再是黑屏（values + values-night 两处）
- **5268bc9** 性能：低端机自动性能档——`isLowEndDevice()`（Android CPU≤4 核 或 /proc/meminfo MemTotal<3GB），
  新用户（`oobeDoneProvider==false`）首启默认进「性能」档（特效关/帧率 24/动画最快），
  老用户已持久化选择优先不受影响；放在 `restoreSettings` 里、`_mapLegacyPerformance` 前
- **发布更新**：黑屏/性能修复后需**重新构建并更新** release 资产（zip/APK）+ gh-pages manifest

## Mali/旧 GPU 黑渲染降级（2026-09-03，1872cc3）
用户反馈：Mali/旧 GPU 设备仍有黑渲染。根因：AndroidManifest 强制 `EnableImpeller=true`，
FlutterLoader 在引擎构造时读 `ApplicationInfo.metaData` 的该值决定 Impeller 开关——**静态且无法
运行时改**（`dartVmArgs` 是 VM 参数、`getFlutterShellArgs` 仅 FlutterActivity 自建引擎路径用，
AudioServicePlugin 用 `new FlutterEngine(context)` 都不走）。
- **修复**：MainActivity `onCreate` 在 `super.onCreate` 前调 `applyEngineBackendOverride()`——
  **反射改写 metaData 的 `io.flutter.embedding.android.EnableImpeller`**（metaData 是 PackageManager
  缓存的 Bundle 引用，putBoolean 持久生效，FlutterLoader 构造引擎时读到新值）：
  - 用户「图形后端」选 `skiaOpengl`/`software` → 禁用 Impeller（回退 Skia）
  - 默认 `auto` 且 **Mali GPU**（`ro.hardware.egl` 含 mali / `libGLES_mali.so` 驱动库存在 /
    `Build.HARDWARE` 含 mali）→ 自动禁用 Impeller
  - 其余保持 manifest 默认（Impeller 开）
- **设置链路**：设置页 `engineBackend` chips 安卓也可选 → `repo.setEngineBackend` 写 prefs
  （shared_preferences 文件名 `FlutterSharedPreferences`、key 前缀 `flutter.`）→ MainActivity
  读 `flutter.settings.engineBackend` 判断。**需重启生效**（引擎构造时定）。
- **构建验证**：`flutter build apk --release --split-per-abi` 通过（Java 编译 OK）；APK 已重传 release

## 功能拓展五项（2026-09-03，a69015d/662291a/e4d5b97/73fdc4b/64f8f65）
- **SMTC（a69015d）**：Windows 任务栏媒体控件+全局媒体键桥
  - `windows/runner/smtc_bridge.cpp`：WinRT `SystemMediaTransportControls` 经
    `ISystemMediaTransportControlsInterop::GetForWindow(hwnd)` 获取（**Win32 桌面无 CoreWindow，
    `GetForCurrentView` 不可用**；interop 头是 `um\SystemMediaTransportControlsInterop.h` 不是
    `winrt/Windows.Media.Interop.h`）；同步标题/歌手/专辑/本地封面缩略图 + 播放态/进度/时长；
    媒体键 play/pause/next/previous/stop + 进度拖动回 Dart（MethodChannel
    `com.stelarith.xingli_music/smtc`）
  - `lib/services/audio/smtc_bridge.dart`：非 Windows no-op；`audio_handler` 媒体项/状态流镜像 +
    系统键转发 PlaybackController
  - **CMake 三要素**：新源文件 + `target_compile_features(... cxx_std_20)`（指定初始化器）+ 链接
    `windowsapp.lib`（RoGetActivationFactory 等 WinRT 符号）；`Thumbnail` 收
    `RandomAccessStreamReference`（投影签名）；`std::string→hstring` 需自写 UTF-8 转换
- **星璃天气（662291a）**：Open-Meteo（免费无 key）——Geocoding 城市搜索（中文）+ Forecast
  实时/7 日；`weatherProvider` 城市列表/默认城市 SharedPreferences 持久化；`weather_page`
  当前天气大卡+7 日横滚+城市管理；场景页 AppBar 加入口（相机/评估旁）
- **星璃日历（e4d5b97）**：`calendarProvider`（CalendarEvent+SharedPreferences+公历固定节日表）；
  `calendar_page` 月视图（今天高亮/节日徽标）+点日增删事件；场景页入口
- **ClassIsland 联动（73fdc4b）**：`classislandProvider` 集控客户端——配置服务器 URL+班级
  （SharedPreferences）；2min 周期 GET `/api/classisland/status`（约定 JSON
  `{code,data:{date,classes:[{start,end,name,teacher,room}]}}`）；当前课/下一节判定；
  播放上报 POST `/api/classisland/report`；`classisland_page` 课表+配置
- **集控插件（64f8f65）**：`services/tools/control_server.dart` 本地被控端
  `http://127.0.0.1:43218/api/control`（POST JSON `{action,payload}`）：
  report/set_weather/set_volume/play/pause/notice（全局横幅，`kControlMessengerKey` 注入
  MaterialApp）；仅绑 loopbackIPv4；`ClassIslandNotifier.instance` 单例（audio_handler 无 ref
  直调上报，StateNotifierProvider 委托同实例）；app_shell 启动段挂载；classisland_page 加被控端状态卡
- **注意事项**：`c.textPrimary` 是 Color 不是 TextStyle——页面用 `.style(...)` 需在文件内自建
  Color 扩展；天气/日历/集控共用「场景页 AppBar 图标入口」模式；页面内 `ref.watch(...)` 时
  无状态变化也要刷新当前课判定（每 build 取 `DateTime.now()`）

## UI 选型 + 后续可做项（2026-09-03，bdc13fe/6039c4f）
- **UI 选型（bdc13fe）**：用 `D:\Stellara\.md\design-md`（70+ 品牌设计库）对比
  Spotify/Apple/Linear/Notion/Raycast → 音乐 App 选 **Spotify 式「内容优先深色沉浸」**
  （UI 退后/封面发光/单一 accent/pill 几何）。落地：`AppDarkColors` 深色表面改炭黑三级
  （bg #000→#121212、surface #1C1C1E→#1A1A1A、surfaceHigh/placeholder #2C2C2E→#242424）。
  确认 **accent 已跟皮肤**（`themeSkinColorProvider`→`withSkin` 深色提亮 +0.12 lightness，
  非写死 iOS 蓝）。选型文档：`docs/UI_DESIGN_2026-09-03.md`
- **集控鉴权（b252e57）**：`ControlServer.setToken` + SharedPreferences 持久化（control.token）；
  `_handle` 校验 `X-Control-Token` 头（配置了则必须匹配否则 401，空=免鉴权）；classisland_page
  被控端卡显示 token 状态+设置对话框
- **SMTC 网络封面（25b5ad9）**：`smtc_bridge.dart` 加 artUrl——网络封面异步下载到临时文件
  （`Directory.systemTemp/smtc_art`，内存缓存 URL→path 避免切歌重下），下载成功补发媒体项
  （原生侧以最后一次为准）；audio_handler 传 coverUrl
- **日历农历（7f21bf3）**：`solarToLunar()` 标准农历数据表 1900-2100（`_lunarInfo` 位编码：
  位4-15 大小月 0=29/1=30、位1-4 闰月位置、位16 闰月大）——闰月/干支/生肖/农历节日
  （春节/元宵/龙抬头/端午/七夕/中元/中秋/重阳/腊八/除夕 12-29/30）；月标题干支年+生肖、
  日期格农历日名（节日优先）、详情 sheet 完整农历。**测试 test/lunar_calendar_test.dart
  6 锚点全过**（2023-2026 春节+中秋+2026-09-03=七月廿二）
- **天气自动定位（6039c4f）**：IP 定位 `http://ip-api.com/json/?lang=zh-CN`（免费无权限弹窗）
  → 城市/经纬度/省份 → setDefaultCity；天气页城市管理 sheet 加「自动定位当前城市」按钮，
  失败 SnackBar 提示手动搜索（注意 ip-api.com 是 http 明文，仅取经纬度无隐私敏感）

## 即开即用/少步骤/高密度/功能整合（2026-09-03，a2f6d8d）
- **工具面板（功能整合归类）**：`pages/tools/tools_panel_page.dart`——天气/日历/ClassIsland
  三个 AppBar 独立图标收敛为一个「工具」(grid_view) 图标；面板内嵌三工具迷你卡
  （天气:城市+温度+图标 / 日历:今日事件数 / ClassIsland:当前课+下一节）+ 顶部今日概览条
  （公历+农历干支+节日+生肖），点卡片 push 对应详情页——一屏多信息、入口集中、步骤少
- **主页今日信息行（信息密度）**：问候区「星璃音乐」下加一行
  `周X · 农历M月D日 · 节日 · 城市温度°图标`（`_TodayInfoLine`，复用 weather/calendar
  provider 只读，不触发请求）；场景页 AppBar 从 6 图标降到 4
- **启动即用侦查结论**：启动 postFrame 的 reOOBE/渠道引导/OTA 检查均为**条件触发**
  （版本升级/切渠道/有更新才弹），非频繁打扰——不砍保留
- **高频操作路径现状**：音乐卡（UnifiedPlayer 传输行 prev/play/next/volume）常驻底部，
  任何 Tab 一步控制播放/切歌；「最近在听」在曲库 Tab 顶部（Terms.recentlyPlayed）一步可达——
  均无需再改
- **注意**：`ClassIslandNotifier.instance.state` 直接访问会触发 lint
  （invalid_use_of_visible_for_testing_member）——面板/页面读状态一律
  `ref.watch(classislandProvider)`（StateNotifierProvider 委托单例）

## cl06 发布 + 后续可做项全落地（2026-09-03，6cf16be）
- **版本**：buildCount 5→6（0.26.9.3_beta_cl06）；pubspec +116→+117（versionCode）；
  **gradle versionName 曾过期**（0.26.8.31_beta_cl03 → 0.26.9.3_beta_cl06，发版必同步）
- **后续可做项落地**：
  - 播放页大封面 320→380（沉浸）
  - IP 定位双源降级：ip-api.com 失败 → ipapi.co（https 备用，`_locateVia` 泛化 parse）
  - 集控 notice 改走**全局通知弹条**（`appNotifyRef`，右上角 ≤1/3 宽），替代底部
    SnackBar；移除 `kControlMessengerKey`/`scaffoldMessengerKey`（MaterialApp 干净了）
  - 工具面板加快捷跳转：最近在听→曲库 Tab、常用设置→设置 Tab
    （`_jumpToTab`：popUntil 首路由 + `shellPageIndexProvider` 设 Tab）
  - 曲库列表紧凑化：`_TrackRowCard` 垂直 padding 8→6、行间距 12→8、排行行 16→10
- **安卓产出（用户问"为什么没有安卓产出"）**：前几轮只验证了 Windows 构建（analyze+
  build windows），未重建上传 APK——本轮 `flutter build apk --release --split-per-abi`
  产出 arm64(43.2MB)+arm32(40.7MB)，连同 Windows zip(37MB)+sha256 上传
  Release `0.26.9.3_beta_cl06`（id 382763961）；gh-pages manifest 更新
  （API 流程：blob→tree→commit d34d6d3→ref，cl06 仅列 Windows 资产，安卓走 Releases 回退）
- **发布地址**：https://github.com/WuMengAA/xingli_music/releases/tag/0.26.9.3_beta_cl06

## Bug 修复 + 曲库联动（2026-09-03/04，4a00604/5c760c8）
- **歌单报错根因**：`track_stats_db.playlistTracks` 原 SQL `SELECT t.*` 只取
  `playlist_tracks` 四列（playlist_id/track_key/sort_index/added_at），但
  `PlaylistTrack.fromRow` 读 title/artist/source_id → **必然报错**。修复：
  LEFT JOIN `play_stats`（按 track_key）取元数据 + `COALESCE(s.title, t.track_key)`
  兜底未播过的歌单曲（play_stats 无行防 NULL）；orderBy 全部加表限定
  （s.title/s.play_count/t.sort_index 等）。**教训：JOIN 查询的 SELECT 列必须
  覆盖 fromRow 所需字段**
- **天气无法添加查询根因**：`showModalBottomSheet` 的 builder 是**独立路由**，
  页面 `setState` 不重建已弹出的 modal sheet → 搜索结果/定位状态永远不显示。
  修复：sheet 内用 `StatefulBuilder` + `setSheet` 本地刷新（doSearch/doLocate），
  await 后按 `sheetCtx.mounted` / State `mounted` 分别守卫
- **曲库-工具联动（5c760c8）**：曲库页分类切换条下新增 `_ToolsQuickRow`——
  天气/日历/ClassIsland/全部工具 四个胶囊图标入口，不切 Tab 直达工具页
- **GitHub 代理域名（用户提供）**：`https://gh.245959623.xyz/WuMengAA/xingli_music`
  可代理网页/下载/Raw/API；git clone 也可走
  `git clone https://gh.245959623.xyz/WuMengAA/xingli_music.git`
  （raw.githubusercontent 被墙时下载资产走此代理）

## 持续自主修复循环（2026-09-04，cl08 发布 4e590c3）
用户要求「就不能一直修吗」——持续主动审计修复，不等报 bug。本轮（cl08）修复 9 项：
- **OTA 下载（552b87b/451b623）**：候选源列表主源→镜像代理 gh.245959623.xyz 重试
  （`_download` 接受 List 候选逐个试）；下载前删残留、校验失败/下载失败清坏文件
- **SMTC 网络封面（dea68a9）**：临时目录泄漏——原每首都 `createTempSync` 新建目录
  从不清理 → 改固定 `smtc_art` 目录 + URL hash 文件名 + 缓存上限 8 淘汰最旧
- **Provider 自动加载（977a272/28545f6）**：weather/calendar/classisland 三个
  provider 首 watch 时 `microtask(load)`——工具面板/主页今日行冷启动即显示，
  不必先进各页；页面 initState 的手动 load 删除（避免重复请求）
- **天气 JSON 空安全（977a272）**：`data['current'] as Map` 在结构异常时抛强转
  → 缺失时降级报"数据异常"不清旧数据
- **集控 _respond 防双写（9b327de）**：`_route` 内部已回包后再抛异常会 double-close
  → 响应头已设置则直接忽略
- **ClassIsland 配置输入被清（8f8966d）**：`_configCard` 在 build 里给 controller
  赋值，任何 rebuild（如进度刷新）清空用户输入 → 改 initState `microtask` 预填
- **发布**：cl08 Release 4 资产 + gh-pages manifest（build=8）
- **Issue 规范**：新问题开 issue（#2 歌单报错/#3 天气添加查询已修并 closed；
  将来修复完更新 issue 状态）

## 持续修复 round 2（2026-09-04，89b788b）
- **reorderApproved 越界（89b788b）**：拖到列表末尾时 `newIndex == approved.length`
  → `insert` 抛 RangeError 崩。修复：`newIndex<0→0`、`>=length→length-1`（老 clamp
  只夹下限不夹上限）。教训：ReorderableListView 的 onReorderItem newIndex 在拖到
  末尾时可能等于 itemCount，**必须夹上限**
- **审计结论（无 bug 项）**：`album_detail tracks[i-1]`（i==0 返回头部安全）、
  `voxel_save` 时间解析（tryParse 前置 + try/catch）、农历闰月循环（测试 6 锚点证明）、
  `_ToolsQuickRow` 横向滚动防溢出、now_playing 封面 clamp、TrackPicker 空/loading/error
  三态齐全、聚合搜索 Riverpod 按 keyword 重建无竞态、OTA staging 清理、日志上传器
  缓冲/重试/丢弃/健康摘要齐全、`_switchBackend` 状态机、队列操作 firstOrNull 空态安全
- **issue 收口**：#2/#3 已标 closed（注明修复版本 cl08）

## VoiceHub 合并接入（2026-09-04，4c504b0/a58c42d/6bc830c/8657a7c）
用户要求「两个合二为一，不单独实现电台功能」+ **relay/P2P 自研层保留**。
方案：星璃作为 VoiceHub 开放 API 客户端（Nuxt 4 全栈系统，Postgres+Docker）。
- **正式部署地址**：`https://voicehub.245959623.xyz`（用户确认；页面默认 hint）
- **开放 API**（X-API-Key 头认证）：
  - GET `/api/open/songs.get` —— 点歌列表：search/semester/grade/page/limit/sortBy/sortOrder
  - GET `/api/open/schedules.get` —— 排期列表：semester/date/playTimeId/search/分页
  - POST `/api/songs/request.post` —— 点歌提交（**需登录用户 cookie**；body：
    title/artist/cover(http 前缀校验)/musicPlatform/musicId/bilibiliCid/bilibiliPage…）
- **数据字段对齐（真实页面确认）**：歌/排期卡片显示封面(coverUrl) + 「曲名-歌手」+ 投稿人(requester) + 热度 🔥（voteCount/votes/vote_count 三字段兼容）；schedules 的 song 可嵌套或平铺两形态
- **代码**：
  - `services/voicehub/voicehub_client.dart`：可注入 http.Client（MockClient 测试）；
    fetchSongs/fetchSchedules/submitSong(cookies 可选)；401 明确报错
  - `providers/voicehub/voicehub_provider.dart`：baseUrl+apiKey 持久化（voicehub.*），
    首 watch 自动 load，refresh/search 失败记 error 不抛
  - `pages/explore/experiments/voicehub_page.dart`：探索页「VoiceHub 点歌」入口
    （_UtilityItem voice_chat_rounded）→ 配置卡 + 点歌/排期双 Tab + 搜索；
    **点歌点击即播**：网易云曲目 `netease://song/<musicId>` 占位 URI 走既有解析链
- **测试**：test/voicehub_client_test.dart 5/5（songs/schedules 解析含嵌套、
  401 认证失败、submitSong 成功/未登录、请求体字段对齐）
- **完成闭环（897797a/26430cc）**：
  - **点歌提交**：配置卡加「登录 cookie」输入（浏览器登录 VoiceHub 后复制，
    `voicehub.cookie` 持久化）；点歌列表 trailing「点歌」按钮 → provider
    `submitSong`（未配 cookie 明确报错；成功自动 refresh）
  - **网易云播放**：`sourceId='netease'`（`buildStreamResolver` 按 sourceId
    反查源，`voicehub:xxx` 找不到源就会回落默认分支播不了——曾因此只见本地
    列表）；需先登录网易云（`NeteaseSource.enabled && api.isLoggedIn`）
  - **B站播放**：VoiceHub 曲目 `musicId` 即 bvid（可能带 `:cid` 后缀，
    `split(':')` 截断）→ `bilibili://video/<bvid>` 占位 URI + `sourceId=
    'bilibili'` + extras.bvid；需先登录哔哩哔哩
  - **设置页入口（180b37e）**：内容服务地址同区新增「VoiceHub 点歌」，点击
    直达；探索页也有 `_UtilityItem` 入口（两处）
- **遗留**：B站源 `resolveStreamUrl` 需 `_fetchCid(bvid)`（bvid→cid 转换）

## cl09 发布（2026-09-04，c299e40）
- **版本**：buildCount 8→9（0.26.9.3_beta_cl09）；pubspec +119→+120（versionCode 120）；
  gradle versionName 同步
- **内容**：VoiceHub 对接闭环全量——客户端/点歌/排期/网易云+B站播放/登录 cookie
  点歌提交/设置页+探索页双入口；播放控件 InkWell Material 兜底 ×6；changelog 简洁 4 点
- **发布**：Release `0.26.9.3_beta_cl09`（id 382994727）4 资产（Windows zip 37MB +
  sha256 + arm64/arm32 APK）；gh-pages manifest 更新（commit 5046824，build=9）→
  https://github.com/WuMengAA/xingli_music/releases/tag/0.26.9.3_beta_cl09
- **发布流程复用**（几次发版沉淀）：zip 平铺 Compress-Archive → Release API 建 ->
  uploads.github.com 传 4 资产 → manifest PUT contents API（base64 + old sha）→
  校验 readback；flutter.bat exit 1 恒为 stderr 镜像误报（看 stderr 里有没有 Built）
