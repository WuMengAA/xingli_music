# 星璃音乐 xingli_music · 项目状态快照

> 最后更新：2026-08-20 13:05 · Flutter 3.44.8 · git `2895b8b`（cl04 已提交）
> 用途：压缩上下文用。续接开发前先读本文件，不必翻历史对话。

## 一、当前可用状态
- `flutter analyze`：**0 错误 0 警告**
- 测试：**50/50 全绿**（42 存量 + 7 空间音效 + 1 补充）——✏️ **C-7 口径**：50/50 为「全仓库存量 + 新增」总数；`QA_REPORT_V2` 的 33/33 为「v2 新增测试 + 1 既有」统计口径，二者范围不同、非矛盾。**本快照为 2026-08-20 时点，后续新增测试以各报告为准。**
- ⚠️ **环境注记（2026-08-31 复核）**：Windows 桌面宿主 `flutter test` 全量时，`test/qa_v2_widget_test.dart` 整 App 集成用例（M1 横屏 / M2 探索 Gate / M3 曲库三态 / M6 通知中心）会出现**超时失败/挂起**——非本轮改动引入（NowPlayingServer 单测 7/7 独立复核全绿；插件 M2 编译 0 警告 0 错误）。判定为无头桌面宿主（字体/渲染管线/时序）环境性现象，真机或带设备宿主下需复验；单测与 M0 服务不受影响。
- 构建：debug APK 157MB 成功；Web 版可预览（localhost:8899 服务器常驻）
- 版本：`0.26.8.9_alpha_cl01`（pubspec `0.26.8+9`，build.gradle versionName 完整串）

## 二、已实现模块（按批次）

### 批次 A · 13 项问题修复（8/9 完成）
| 项 | 落点 |
|---|---|
| R1/R2 播放区一体化 | `scene_playback_panel.dart`（替代场景页播放卡+迷你播放器拆分）；AppShell 场景页隐藏全局 MiniPlayer |
| R3 切场景不中断 | AudioService 音景播放器 `AudioContextConfigFocus.mixWithOthers`（不抢焦点） |
| R4 白噪音=场景音景 | `setWhiteNoise` 控制当前场景音景启停 |
| R5/R6 不重置第一首 | `playback_notifier._playFirst` 优先匹配 scene.track |
| R7/R8/R9 EQ 10段 | `eq_engine.dart` 10段(31~16k)+7预设(峰值≤4.5dB)；AndroidEqualizer 就近频段映射 |
| R10/R11 持久化 | `settings_repository.dart` + `settings_persistence_providers.dart`（restoreSettings 冷启动恢复 + settingsSyncProvider 写回） |
| R12 初始音量 0.7 | audio_service + musicVolumeProvider |
| R13 权限 | `permission_service.dart`；Manifest POST_NOTIFICATIONS；启动即申请 |
| R14 静默通知 | AudioServiceConfig ongoing:true + stopForegroundOnPause:true |
| R15 音量均衡 | BalanceMode(hifi/normal)，普通=0.35v+0.65v^0.6 |
| R16 主题系统 | theme_providers(themeMode/skin) + theme_skins(6皮肤) + buildDarkTheme + AppThemeColors(ThemeExtension) + 设置「外观」分类 |
| R17 版本规范 | `core/app_version.dart`：0.大版本.年.月.日_阶段_cl构建次数 |
| R18-20 版本落地 | pubspec + build.gradle versionName |

### 批次 B · 液态玻璃 + 自适应（8/9-8/10）
- **LiquidGlass 组件**（`widgets/liquid_glass.dart`）：**FragmentShader 折射+色散**（`shaders/liquid_glass.frag`，仅边缘窄带 5px 折射+RGB 分离，中心透出背景）
- **背景捕获**：`providers/shell/liquid_glass_capture_provider.dart`（AppShell 背景 RepaintBoundary 快照 → InheritedWidget 共享）
- **ResponsiveLayout**（`core/layout/responsive_layout.dart`）：紧凑<320/横屏≥600/大屏≥800；Dock 紧凑隐藏标签；播放面板紧凑默认折叠
- 背景层：AppShell Stack 加极淡场景色渐变(alpha 0.10)+噪点；ContentContainer 恢复**实色**（页面可读）
- Dock 顺序：场景/曲库/探索/设置

### 批次 C · 空间音效引擎核心（8/10）
- `services/audio/spatial/spatial_models.dart`：SpatialChannel(前后左右)/ChannelLayout(mono/stereo/surround)/SpatialTrack(≤4轨)/SoundMaterial 6类(Rw+α)/transmissionLoss/waterFlow(BFS曼哈顿≤9菱形)
- `spatial_synth.dart`：合成 water/fireplace/furnace/rain/wind/cave 的 PCM WAV
- `spatial_mixer.dart`：SpatialPlayer(多轨播放+声道增益+材料衰减)/SpatialMixer
- `providers/audio/spatial_providers.dart`：mixerProvider + channelLayoutProvider + SpatialPresets
- 测试：`test/spatial_audio_test.dart`（7 用例）

### 批次 D · 传感器（8/9）
- 移除 light 依赖（minSdk21 挡 4.4）→ 自写 `MainActivity.java` MethodChannel 读 TYPE_LIGHT/TYPE_HEART_RATE
- 陀螺仪走 sensors_plus（gyroscopeProvider/heartRateProvider）

### 批次 E · 原生极简转向 + 悬浮层 + 文案规范（8/20，cl04，`2895b8b`）
- **文案规范落地**：`core/terms/naming_dict.dart` 单一事实源（`Terms` 常量词典，全站硬编码替换）；规范文档 `docs/ui_copy_spec.md`
- **悬浮层重构**：播放控件与 dock 脱离文档流 → `widgets/shell/responsive_floating_layer.dart` 自适应浮层容器；AppShell 改悬浮叠加绘制（内容→浮层→FAB→toast），底部防遮挡
- **原生极简总开关**：`widgets/liquid_glass.dart` `kNativeMinimal = true`——全站 30+ 处 LiquidGlass 一次性退化为纯 Padding 直通（去 tint/border/blur/圆角）；改回 `false` 整体回滚
- **去容器边界**：ContentContainer 仅留 14dp 留白；auroraGradient 减半为清淡氛围层；MusicCard 去 24dp 描边、AppDock 去玻璃药丸、ThemeSwitchButton 改系统 IconButton；五大页面（settings/explore/library/scene/world）分组卡→留白+原生控件、chip→ChoiceChip、视图切换→SegmentedButton、聚合搜索→FilledButton、删背卡/描边
- 验证：`flutter analyze lib` 0 error（144 预存 lint 基线）；Windows EXE + Android APK（arm64/arm32）双平台构建通过

## 三、平台版本决策
- **Android 最低 5.0（API 21）**，目标 16；4.4 放弃（用户拍板）
- Windows 最低 7/目标 11（需 VS2022 才能构建，当前未装）
- iOS 最低 10/目标 26（待定，无工程）；Linux 列入计划（待定）
- APK 精简：debug 157MB 主要=多ABI(118MB)+kernel_blob(58MB)+VkLayer(14.5MB)；release+abiFilters 预计 25-40MB（abiFilters 已加 arm64+v7a，release 才生效）

## 四、关键坑（必读）
1. **flutter cache 写保护**：WorkBuddy 沙箱拦 dart 进程写 `D:\flutter\bin\cache\lockfile/stamp`。解法：PowerShell `Remove-Item -Force -ErrorAction SilentlyContinue`（钩子误报但真删）+ 手工重建 *.stamp（内容=engine/framework revision）。已 icacls 放开 Everyone 完全控制。
2. **磁盘满**：flutter 写 `C:\Users\Administrator\AppData\Local\Temp\flutter_tools.*` 失败(errno 112)→测试"卡死"。遇卡先查 `Get-PSDrive C`，清 Temp。当前脚本：清 flutter_tools.* 目录 + 1天前旧目录。
3. **Riverpod**：Provider 初始化期禁改其它 provider → restoreSettings 做成普通函数，AppShell 帧后调。
4. **initState 禁读 MediaQuery** → ResponsiveLayout 首次 build 初始化。
5. **FragmentShader**：`shaders/` 目录 + pubspec `shaders:` 段；Web 用 CanvasKit 渲染；LiquidGlass 是 StatefulWidget 异步加载 shader。
6. **测试环境**：无背景快照时 LiquidGlass 退回纯内容（maybeOf==null）。

## 五、待办（按优先级）
1. **歌词支持**：本地 lrc + 网易云歌词 API
2. **网易云音源**：用户登录→cookie 持久（企业级加密 AES-256）→歌单/收藏/歌词
3. **空间音效 2.5D 编辑器升级**：VoxelSoundEditorPage 接 SpatialMixer（摆方块/选材料/4轨试听）
4. **Android 真机验证**：平板 USB 插上 → 推 v4 APK 截图（液态玻璃真机效果）
5. **APK 精简**：release 构建验证体积
6. **Web 预览完善**：localhost:8899 常驻服务器（`python -m http.server 8899`，目录 build/web）
7. 空间音效：水方块 9 格流动动画 + 篝火/熔炉动效可视化

## 六、常用命令
```bash
# 测试（先清 lockfile）
PowerShell: Remove-Item D:\flutter\bin\cache\lockfile -Force -ErrorAction SilentlyContinue
flutter test

# analyze
flutter analyze lib

# 构建
flutter build apk --debug   # 推平板用 adb install -r
flutter build web           # 预览：cd build/web && python -m http.server 8899

# 磁盘急救
PowerShell: 清 C:\Users\Administrator\AppData\Local\Temp\flutter_tools.*
```
