# 代码侧现状快照（草稿，供文档整理合并用）

> 核对时间：2026-08-10 08:00 · 基于 git 工作区 84 个改动文件、lib 129 个 dart 文件

## 一、模块清单（lib/ 目录树）

```
lib/
├── core/                  # 基础设施
│   ├── app_version.dart   # 版本规范 0.大版本.年.月.日_阶段_cl构建次数
│   ├── layout/responsive_layout.dart   # 紧凑<320 / 横屏≥600 / 大屏≥800
│   ├── motion/            # 动画时长（motionScaleProvider 缩放）
│   ├── terms/naming_dict.dart          # 命名词典（Terms.scene 等）
│   ├── theme/             # theme_providers / theme_skins(6皮肤) / app_theme_colors / light_tokens
│   └── utils/
├── models/
│   ├── scene.dart         # Scene + SceneVisual（见下）
│   └── voxel.dart         # 2.5D 音效方块模型（VoxelSoundScene / VoxelBlock）
├── pages/
│   ├── canvas/voxel_canvas_page.dart   # 新版沉浸画布（2.5D，待替换为 3D 体素世界）
│   ├── explore/experiments/voxel_minigame_page.dart  # 体素小游戏（既有）
│   ├── scene/             # scene_page / custom_scene_edit_page / custom_scene_list_page / voxel_sound_editor_page
│   ├── settings/          # settings_page(5组) / server_settings_page / scene_editor_page / ...
│   └── now_playing/ library/ home/    # 播放页/曲库/首页
├── providers/
│   ├── audio/             # audio_providers / playback_notifier / equalizer_providers / spatial_providers
│   ├── scene/             # scene_providers / scene_custom_providers / voxel_scene_providers
│   ├── settings/          # settings_ui_providers / performance_providers / settings_persistence_providers
│   ├── shell/             # shell_providers / liquid_glass_capture_provider
│   └── canvas/ color_memory/ explore/ feedback/ library/ mood/ session/ storage/ theme/
├── repositories/settings_repository.dart   # 设置持久化
├── scenes/                # scene_api(门面) / scene_deploy / scene_packer
├── services/
│   ├── audio/             # audio_service(524行,_safe包装) / audio_handler / eq_engine(10段) /
│   │   │                  # local_music_scanner(MediaStore+目录遍历fallback) / sound_block_mixer /
│   │   │                  # soundscape_generator / minecraft_sfx_service / ambient_soundscape_service /
│   │   │                  # visualizer_service / playback_controller
│   │   └── spatial/       # spatial_models(287行) / spatial_mixer(141行) / spatial_synth(188行)
│   ├── music_sources/     # 音源（含 LocalDirMusicSource）
│   ├── sensor/            # 自写 MethodChannel(光线/心率) + sensors_plus(陀螺仪)
│   ├── storage/           # 存储
│   └── permission_service.dart
└── widgets/
    ├── shell/             # app_dock(液态玻璃+动画缩放) / content_container / ...
    ├── voxel/             # voxel_world(噪声地形) / voxel_world_types / voxel_canvas_view / voxel_canvas_controller
    ├── liquid_glass.dart  # FragmentShader 折射+色散，blur 可空(跟随 glassBlurProvider)
    ├── playback/unified_player.dart    # 一体化播放面板（R1/R2）
    ├── scene/scene_color_panel.dart    # 配色面板
    ├── card_stack.dart / noise_texture.dart / album_card.dart / page_scaffold.dart / ...
```

## 二、Scene 数据模型（models/scene.dart，实核）

字段：id / name / mood / desc / track / artist / soundscape / icon(assets/icons文件名) / visual(SceneVisual) / visualWeight / valence / energy / musicSourceId(专属音源) / soundscapePath(自定义音景文件) / particleColor / particleMotion(rain|snow|fireplace|ocean|starnight|dust) / bgTop / bgBottom / visible(默认true) / bgmUri+bgmTitle+bgmArtist(默认BGM)。

- 内置 7 场景：starnight 星夜 / rain 雨 / forest 森林 / fireplace 壁炉 / dusk 黄昏 / snow 雪(minecraft音源) / ocean 海底(minecraft音源)
- 自定义：id 以 `custom_` 开头；内置场景可「覆盖副本」修改（id 不变）
- 持久化：customScenesProvider → SharedPreferences key `custom_scenes_v1`（JSON 数组）
- 门面：Scenes.encodePack/decodePack（schema=1，JSON 打包，未来分享/导入用）
- 场景顺序：sceneOrderProvider + currentSceneIndexProvider(StateProvider) + activeSceneProvider(派生)
- 切换逻辑：R5 只切音景层与视觉，不中断音乐（audioService.switchSoundscape(scene)）

## 三、场景页结构（scene_page.dart）

- PageScaffold(title: 场景) + 右上角 40dp 微光圆点入口（三选一：首页/沉浸画布/配色面板）
- SceneCardStack（卡片堆） + UnifiedPlayer（一体化播放面板，底部固定）
- 沉浸画布入口 → VoxelCanvasPage（全屏路由，脱离 Dock）

## 四、2.5D 画布（voxel_canvas_page.dart，待替换）

- 数据源：voxelSoundScenesProvider（用户在 VoxelSoundEditorPage 保存的 VoxelSoundScene 列表）
- 渲染：VoxelCanvasView 等距方块 CustomPaint（tileW 46 / tileH 28）
- 互动：点击方块 → SoundBlockMixer.playType；播放音景 → 按数量/位置混合循环
- 顶栏 chips 切场景；空态引导去编辑器
- 三处共用 voxel_canvas_view/controller：voxel_canvas_page / voxel_minigame_page / voxel_sound_editor_page

## 五、空间音效引擎（services/audio/spatial/）

- spatial_models.dart：SpatialChannel(前后左右)/ChannelLayout(mono/stereo/surround)/SpatialTrack(≤4轨)/SoundMaterial 6类(Rw+α)/transmissionLoss/waterFlow(BFS曼哈顿≤9菱形)
- spatial_synth.dart：合成 water/fireplace/furnace/rain/wind/cave 的 PCM WAV
- spatial_mixer.dart：SpatialPlayer(多轨+声道增益+材料衰减) / SpatialMixer
- spatial_providers.dart：mixerProvider + channelLayoutProvider + SpatialPresets
- 测试：test/spatial_audio_test.dart（7 用例）

## 六、性能模式（providers/settings/performance_providers.dart）

- PerformanceMode 枚举：powerSave(省电) / balanced(均衡,默认) / smooth(流畅)
- performanceModeProvider：不读 prefs（默认 balanced，restoreSettings 恢复 + settingsSync 落盘，key settings.performanceMode）
- 派生：noiseEnabledProvider(省电关噪点) / glassBlurProvider(0/12/20) / motionScaleProvider(0.5/1.0)
- LiquidGlass：blur<=0 跳过 BackdropFilter；省电 tint 减淡
- **用户裁决：正常模式 UI 必须完整，只有低性能模式才能关效果**

## 七、音频素材（audio_material/，2026-08-10 07:35）

10 个真实 m4a，共约 566MB：
- ［短多采样］鸟叫合集 4.9MB
- ［长］432Hz雨声 35.9MB
- ［长］夏天环境音 145MB
- ［长］树叶窸窸窣窣 104MB
- ［长］海滩 6.8MB
- ［长］环境音 16.9MB
- ［长］田野风铃 30.9MB
- ［长］竹林窸窣、风声 144MB
- ［长］篝火燃烧 34.9MB
- ［长］雨林、鸟叫 56.6MB

## 八、测试与构建现状

- flutter test：50/50 全绿（42 存量 + 7 空间音效 + 1 补充）——注：QA_REPORT 时期 47过2失败(探索Gate/通知中心)为历史状态，后续已修复
- flutter analyze lib：0 错误 0 警告
- debug APK 157MB（多ABI 118MB + kernel_blob 58MB + VkLayer 14.5MB）；release+abiFilters(arm64+v7a) 预计 25-40MB
- Web：build/web + localhost:8899（python -m http.server 8899）

## 九、设备

- 手表：84522968115051（Phh Treble vanilla, Android 11, 412×502）——蓝牙音频未就绪曾触发闪退
- 平板：一加Pad PA2353（Android 14, 1840×2800）无线 adb 192.168.1.125:35531
