/// ════════════════════════════════════════════════════════════════════════
/// 性能与质量体系（R21 重构）
/// ════════════════════════════════════════════════════════════════════════
///
/// 用户定版（2026-08-11）：
/// 1. 档位只分「性能 / 质量」两档（替代旧三档 power_save/balanced/smooth，
///    旧值自动迁移）；
/// 2. 帧率限制 24 / 30 / 60 / 120（全局，体素场景 / 3D 视图接入）；
/// 3. 图形后端选配（OpenGL / Vulkan / DX11 / 软件，Windows 重启生效）；
/// 4. 特效开关组独立可覆盖（噪点 / 玻璃模糊 / 背景动画 / 液态玻璃），
///    null = 跟随档位默认。
///
/// 全部 StateProvider 不读 prefs：初始值内置，冷启动由 restoreSettings
/// 显式覆盖、运行期由 settingsSyncProvider 落盘（纯组件/测试可 watch）。
library;

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../widgets/voxel/voxel_renderer.dart' show LodQuality;

/// 性能档位（字符串持久化：performance / quality）。
enum PerformanceMode {
  /// 性能优先：特效默认关闭、帧率默认 24、动画最快（低端机 / 发热控制）。
  performance,

  /// 质量优先：特效默认全开、帧率默认 60（旗舰 / 桌面端）。
  quality,
}

/// 各档位的帧率默认值（切档位时自动联动，手动改过则保留）。
FpsLimit defaultFpsFor(PerformanceMode m) =>
    m == PerformanceMode.performance ? FpsLimit.fps24 : FpsLimit.fps60;

/// 当前性能档位，默认「质量」。
final performanceModeProvider = StateProvider<PerformanceMode>(
  (ref) => PerformanceMode.quality,
);

/// 帧率限制档位（cl46：3 / 24 / 30 / 45 / 60 / 无限制）。
enum FpsLimit {
  fps3(3),
  fps24(24),
  fps30(30),
  fps45(45),
  fps60(60),
  unlimited(0);

  const FpsLimit(this.value);

  /// 每秒帧数（0 = 无限制）。
  final int value;

  /// 用户可读文案。
  String get label => this == FpsLimit.unlimited ? '无限制' : '$value FPS';
}

/// 全局帧率限制，默认 60（随档位预设联动，见 `defaultFpsFor`）。
final fpsLimitProvider = StateProvider<FpsLimit>(
  (ref) => FpsLimit.fps60,
);

/// 图形渲染后端（仅 Windows 可选，需重启；Android 恒为 Impeller 自动）。
enum EngineBackend {
  /// 平台推荐默认：Windows = Impeller(DX11)，Android = Impeller 自动。
  auto('自动（推荐）'),

  /// Skia + OpenGL/ANGLE（旧默认路径）。
  skiaOpengl('Skia (OpenGL)'),

  /// Impeller + D3D11（Windows 默认，绕开 Skia 崩溃区）。
  impellerD3D11('Impeller (DX11)'),

  /// Impeller + Vulkan（实验；需 GPU/驱动支持，不支持时不可选）。
  impellerVulkan('Impeller (Vulkan)'),

  /// 软件渲染（无 GPU 依赖，最稳但最慢）。
  software('软件渲染');

  const EngineBackend(this.label);

  final String label;
}

/// 当前图形后端：Windows 默认 DX11（用户要求），其余平台默认自动。
final engineBackendProvider = StateProvider<EngineBackend>((ref) {
  return (!kIsWeb && Platform.isWindows)
      ? EngineBackend.impellerD3D11
      : EngineBackend.auto;
});

/// Vulkan 后端是否可用。
///
/// ⚠️ Flutter Windows 引擎的 Impeller **仅实现 D3D11**，`enable-impeller-vulkan`
/// switch 在 Windows 上不被识别（R22 实测切换无效果）。故 Windows 恒返回
/// false（引擎能力限制，与 GPU/驱动无关）；其它平台同样不提供该选项。
final vulkanSupportedProvider = Provider<bool>((ref) => false);

/// 上次启动**实际生效**的渲染后端（main.cpp 启动时写入
/// `engine_backend_active.txt`；与配置值不同——Vulkan 会回退 DX11）。
final engineBackendActiveProvider = FutureProvider<String>((ref) async {
  if (kIsWeb || !Platform.isWindows) return 'auto';
  try {
    final Directory dir = await getApplicationSupportDirectory();
    final File f =
        File('${dir.path}${Platform.pathSeparator}engine_backend_active.txt');
    if (await f.exists()) {
      final String s = (await f.readAsString()).trim();
      if (s.isNotEmpty) return s;
    }
  } catch (_) {
    // 文件缺失/不可读：回 unknown，UI 显示「未知（首次启动）」
  }
  return 'unknown';
});

/// 后端值 → 展示文案（设置页「当前生效」用）。
String engineBackendLabel(String v) => switch (v) {
      'impellerD3D11' => 'Impeller (DX11)',
      'skiaOpengl' => 'Skia (OpenGL)',
      'software' => '软件渲染',
      'auto' => '自动（平台默认）',
      _ => '未知',
    };

// ── 特效开关组：null = 跟随档位默认 ────────────────────────────────────

bool _modeDefaultNoise(PerformanceMode m) => m == PerformanceMode.quality;
double _modeDefaultBlur(PerformanceMode m) =>
    m == PerformanceMode.quality ? 16 : 0;
bool _modeDefaultBg(PerformanceMode m) => m == PerformanceMode.quality;
bool _modeDefaultGlass(PerformanceMode m) => m == PerformanceMode.quality;

/// 方块贴图（图集纹理）默认：标准档开、性能档关（与噪点/模糊同思路）。
bool _modeDefaultTexture(PerformanceMode m) => m == PerformanceMode.quality;

/// 噪点纹理：null 跟随档位。
final noiseOverrideProvider = StateProvider<bool?>((ref) => null);

/// 噪点纹理是否渲染（AppShell 全屏 / 播放面板 / 沉浸画布）。
final noiseEnabledProvider = Provider<bool>((ref) {
  return ref.watch(noiseOverrideProvider) ??
      _modeDefaultNoise(ref.watch(performanceModeProvider));
});

/// 玻璃模糊强度覆盖：null 跟随档位。
final glassBlurOverrideProvider = StateProvider<double?>((ref) => null);

/// 玻璃模糊强度（0 = 关闭模糊，仅纯色半透明）。
final glassBlurProvider = Provider<double>((ref) {
  return ref.watch(glassBlurOverrideProvider) ??
      _modeDefaultBlur(ref.watch(performanceModeProvider));
});

/// 背景动画（体素场景天光/水波等）覆盖：null 跟随档位。
final bgAnimationOverrideProvider = StateProvider<bool?>((ref) => null);

/// 背景动画是否启用。
final bgAnimationEnabledProvider = Provider<bool>((ref) {
  return ref.watch(bgAnimationOverrideProvider) ??
      _modeDefaultBg(ref.watch(performanceModeProvider));
});

/// 液态玻璃（FragmentShader 折射）覆盖：null 跟随档位。
final liquidGlassOverrideProvider = StateProvider<bool?>((ref) => null);

/// 液态玻璃是否启用。
final liquidGlassEnabledProvider = Provider<bool>((ref) {
  return ref.watch(liquidGlassOverrideProvider) ??
      _modeDefaultGlass(ref.watch(performanceModeProvider));
});

/// 方块贴图（图集纹理）覆盖：null 跟随档位。
/// P7·#507：贴图从「仅高清画质档自动接图集」改为**独立可开关设置**——
/// 不再绑死 [GraphicsQuality.texture]，用户可在「个性 · 画面特效」里手动开/关，
/// 标准档默认开（图集生产者本身健康，仅消费闸此前卡在画质档）。
final textureOverrideProvider = StateProvider<bool?>((ref) => null);

/// 方块贴图是否启用（null = 跟随档位默认，见 [_modeDefaultTexture]）。
final textureEnabledProvider = Provider<bool>((ref) {
  return ref.watch(textureOverrideProvider) ??
      _modeDefaultTexture(ref.watch(performanceModeProvider));
});

/// 动画时长缩放系数（1.0 标准 / 0.5 性能最快）。
final motionScaleProvider = Provider<double>((ref) {
  return ref.watch(performanceModeProvider) == PerformanceMode.performance
      ? 0.5
      : 1.0;
});

/// 界面密度（布局自定义最小可用版：Dock 紧凑 / 标准）。
enum UiDensity {
  compact('紧凑'),
  standard('标准');

  const UiDensity(this.label);

  final String label;
}

/// 当前界面密度，默认「标准」。
final uiDensityProvider = StateProvider<UiDensity>(
  (ref) => UiDensity.standard,
);

// ── 全局 UI 大小（R26skel-b3：整体界面缩放，0.8~1.2）───────────────

/// 全局 UI 大小允许范围。
const double kUiScaleMin = 0.8;
const double kUiScaleMax = 1.2;

/// 全局 UI 大小（整体界面缩放系数，默认 1.0）。
/// 由 `app.dart` 的 MaterialApp.builder 应用：MediaQuery 尺寸/文字/安全区
/// 一起按系数缩放（与旧「紧凑密度」同一机制，但改为可调滑杆）。
final uiScaleProvider = StateProvider<double>((ref) => 1.0);

// ── 场景背景渲染画质（R26skel-b4：独立于游戏画质）───────────────

/// 场景背景画质档（场景页 / 播放器背景的体素取景渲染，**与游戏画质无关**）。
enum SceneBgQuality {
  low('低', renderDistance: 12, maxFaces: 800),
  medium('中', renderDistance: 20, maxFaces: 3000),
  high('高', renderDistance: 32, maxFaces: 6000);

  const SceneBgQuality(this.label,
      {required this.renderDistance, required this.maxFaces});

  final String label;
  final int renderDistance;
  final int maxFaces;
}

/// 场景背景画质档（默认「中」= 原质量档 20 距离 / 3000 面）。
final sceneBgQualityProvider =
    StateProvider<SceneBgQuality>((ref) => SceneBgQuality.medium);

/// 场景背景帧率上限（P7·#507：默认 30→24，背景系渲染统一下调到 24FPS 省电）。
final sceneBgFpsProvider = StateProvider<int>((ref) => 24);

/// 场景背景 · 雾。
final sceneBgFogProvider = StateProvider<bool>((ref) => true);

/// 场景背景 · 水波动画。
/// R27：默认关——水面上下浮动对性能影响大，仅「高」画质建议手动开启（见设置）。
final sceneBgWaterProvider = StateProvider<bool>((ref) => false);

/// 场景背景 · 天空渐变。
final sceneBgSkyProvider = StateProvider<bool>((ref) => true);

/// 场景背景 · 动画开关（false = 静态单帧，最省电；与场景页「实时渲染」联动，
/// 任一开启即实时重绘）。默认关：单帧静态才能稳 60fps（用户确认）。
final sceneBgAnimProvider = StateProvider<bool>((ref) => false);

/// 玻璃/液态玻璃模糊采样率上限（毛玻璃 [BackdropFilter] 重采样帧率封顶）。
/// P7·#507：默认 24 FPS——高帧率（60/120）下避免每帧对背景重采高斯模糊，
/// 中低端机 UI 卡顿的主因之一；此前 [PicturePreset.blurFps] 定义却从未消费
/// （死代码），现经本 provider 接入 liquid_glass 的节流层。
final blurFpsProvider = StateProvider<int>((ref) => 24);

// ── 体素区块 / LOD（R23m：16×16 区块，视距与 LOD 可调）───────────────

/// 视距（区块数，默认 4 = 64 格）。
final viewDistanceChunksProvider = StateProvider<int>((ref) => 4);

/// LOD 起始距离（区块数，默认 2 = 32 格外开始降精度）。
final lodStartChunksProvider = StateProvider<int>((ref) => 2);

/// 每 N 区块降一级精度（默认 1 = 每远一区块降一级）。
final lodStepChunksProvider = StateProvider<int>((ref) => 1);

/// P6·R26r18：LOD 质量档位（off=全满精度方阵 / balanced=原 2 档 / high=P1 多档细）。
/// 用户明确要求「LOD 要能减少远处面数」（①）——故默认改为 balanced（原 2 档
/// 马赛克），远景大方块正常发射、远山渐变可见、面数由 LOD 预算收敛。
/// 弱 GPU 上若仍见 progressive 闪烁，用户可在「游戏画面」手动切回 off；
/// 默认开 balanced 以满足「拉满视距也要减面」的诉求。
final lodQualityProvider = StateProvider<LodQuality>((ref) => LodQuality.balanced);

/// P3·R26r18：LOD 通道区块级视锥剔除开关（默认开，FP/TP 下远景面数约减半）。
final lodFrustumCullProvider = StateProvider<bool>((ref) => true);

/// 音乐播放引擎（S2 · media_kit 迁移）。
enum MusicEngine {
  /// just_audio：默认，Android 真 EQ 支持，行为已验证。
  justAudio('just_audio'),

  /// media_kit（libmpv）：全格式 / Hi-Res / 无缝播放（EQ 走模拟层）。
  mediaKit('media_kit (libmpv)');

  const MusicEngine(this.label);

  final String label;
}

/// 当前播放引擎。
///
/// 默认值按平台区分：
/// - Android：默认 [mediaKit]（libmpv 多线程解码，规避 ExoPlayer 切歌崩溃，
///   用户反馈「默认解码器导致切换音乐崩溃」的根因）；
/// - 其余平台 / Web：默认 [justAudio]（支持硬件 EQ、行为已验证）。
/// 用户可在「设置 → 画面 → 性能与质量 → 播放引擎」中切回 just_audio。
final musicEngineProvider = StateProvider<MusicEngine>(
  (ref) => (!kIsWeb && Platform.isAndroid)
      ? MusicEngine.mediaKit
      : MusicEngine.justAudio,
);

// ─────────────────────────────────────────────────────────────────────────
// 渲染/机制开关（cl30+ · 设置「更多」里可调；默认值与渲染管线一致）
// ─────────────────────────────────────────────────────────────────────────

/// 侧面剔除（区块级 LOD 面剔除，`RenderConfig.lodFaceCull`）。
/// 默认开（cl30 已启用，配合 allowMask 迟滞防 popping）。
final faceCullEnabledProvider = StateProvider<bool>((ref) => true);

/// 遮挡剔除（隐藏被相邻不透明方块完全盖住的内部面）。
final occlusionCullEnabledProvider = StateProvider<bool>((ref) => true);

/// 背面剔除（去掉背向相机的三角面，GPU/软件均收益）。
final backFaceCullEnabledProvider = StateProvider<bool>((ref) => true);

/// 视锥剔除（区块级，`RenderConfig.frustumCull`）。
/// 默认关（历史曾误删可见区块 → 幽灵方块/侧面缺失，面数由预算收敛）。
final frustumCullEnabledProvider = StateProvider<bool>((ref) => false);

/// 水下滤镜（蓝色色调 + 阳光衰减；关 = 水下无滤镜）。
final underwaterFilterEnabledProvider = StateProvider<bool>((ref) => true);

/// 水流动（G4：放置水源后向四周 9 格扩散，20tps 驱动）。
/// R27：默认关——水面流动对性能影响大，仅「高」画质建议手动开启（见设置）。
final waterFlowEnabledProvider = StateProvider<bool>((ref) => false);

/// 手电筒模式（R26fl）：FOV 不变，完整视线窄锥剔除 + 边界黑化 + 泛光。
final flashlightEnabledProvider = StateProvider<bool>((ref) => false);

// ── LOD 参数（用户确认体系：开关 / 起始区块 / 步长格 / 采样 2 幂 / 最远区块）──

/// LOD 总开关（关 = 满精度方阵，无远景大方块）。
final lodEnabledProvider = StateProvider<bool>((ref) => true);

/// LOD 步长（格）：每档向外推的间距（3/9/16 格）。
final lodStepBlocksProvider = StateProvider<int>((ref) => 16);

/// LOD 采样基数（最细大方块边长：2x2 / 4x4 / 8x8）。
final lodSampleBaseProvider = StateProvider<int>((ref) => 4);

/// LOD 最远渲染距离（区块，4~32；可大于基础视距，远景大方块看得更远）。
/// cl45：默认 8→16——LOD 地平线 256 格，视距不再硬剔、看得更远；
/// cl46：默认 16→32——用户要求近 2 区块到远 32 区块渐进 LOD（最外档
/// cell≥32 走地平线 Impostor 超省模式，远景面数≈单元数，不会成面数黑洞）。
/// #506：默认 32→64——用户要求 LOD 终点提到 64 区块（16 内近 LOD 立体柱有顶、
/// 32 外转双面板）；受 maxFaces 预算封顶，远距面数不爆炸。
final lodMaxChunksProvider = StateProvider<int>((ref) => 64);

/// 阴影渲染（太阳方向投影阴影：顶面被太阳方向相邻方块遮挡时调暗）。
final shadowRenderProvider = StateProvider<bool>((ref) => true);

/// 环境光屏蔽 AO（方块角落/缝隙变暗，增强立体感；关 = 均匀亮度更省）。
final aoEnabledProvider = StateProvider<bool>((ref) => true);

/// 方块描边总开关（cl45：默认开）。开 = 玩家 5 格内实描边 + 5~12 格极淡渐隐；
/// 关 = 完全不描边（省面数、画面更干净）。
final outlineEnabledProvider = StateProvider<bool>((ref) => true);

/// 边界雾（cl45：默认关，与 LOD 互斥）。开 = 视距边缘快速收口雾 + LOD 关闭
/// （传统视距雾）；关 = LOD 远景大方块延伸到 lodMaxChunks（看得更远）。
final boundaryFogEnabledProvider = StateProvider<bool>((ref) => false);

// ── 渲染精度 / 几何精度（画面设置，倍率式：1.0 = 画质档默认）──

/// 渲染精度（分辨率倍率，0.25~2.0；同比例、画面不缩放、尺寸不变，仅降低
/// 内部渲染分辨率——1080p ×0.5 = 半分辨率渲染再放大铺满，帧率翻倍）。
/// 取代原 renderScale + renderRatio 两个旋钮（用户要求合并为单一「渲染精度」）。
final renderPrecisionScaleProvider = StateProvider<double>((ref) => 1.0);

/// 几何精度（面数倍率 0.5×/1×/1.5×/2×；乘 maxFaces，与渲染分辨率无关）。
final renderPrecisionProvider = StateProvider<double>((ref) => 1.0);

// ── 全局画面预设（精度 + 模糊 + 噪点 + 动画 + 液态玻璃 + 帧率 一键套用）──

/// 全局画面预设（cl54-G5：四档——省电 / 流畅 / 标准 / 高质）。
enum PicturePreset {
  powerSave(
    '省电',
    '关闭所有动效、保留不透明、限制全局帧率 24fps，并提醒省电',
  ),
  smooth(
    '流畅',
    '无特效 + 低特效毛玻璃，但毛玻璃限制帧率 5fps',
  ),
  standard(
    '标准',
    '标准特效 + 标准毛玻璃，限制毛玻璃模糊 24fps',
  ),
  high(
    '高质',
    '开启所有特效 + 液态玻璃，模糊 30fps',
  );

  const PicturePreset(this.label, this.blurb);
  final String label;

  /// 档位简介（OOBE / 设置页展示）。
  final String blurb;

  /// 渲染精度（分辨率倍率）。
  double get precision => const <PicturePreset, double>{
        PicturePreset.powerSave: 0.5,
        PicturePreset.smooth: 0.75,
        PicturePreset.standard: 1.0,
        PicturePreset.high: 1.25,
      }[this]!;

  /// 噪点纹理覆盖（null = 跟随档位）。
  bool? get noise => const <PicturePreset, bool?>{
        PicturePreset.powerSave: false,
        PicturePreset.smooth: false,
        PicturePreset.standard: true,
        PicturePreset.high: true,
      }[this]!;

  /// 玻璃模糊强度覆盖（null = 跟随档位）。
  double? get blur => const <PicturePreset, double?>{
        PicturePreset.powerSave: 0.0,
        PicturePreset.smooth: 4.0,
        PicturePreset.standard: 8.0,
        PicturePreset.high: 14.0,
      }[this]!;

  /// 玻璃模糊渲染帧率（毛玻璃采样上限；省电=关模糊，不适用）。
  /// P7·#507：high 30→24，统一背景系模糊采样到 24FPS。
  int get blurFps => const <PicturePreset, int>{
        PicturePreset.powerSave: 0,
        PicturePreset.smooth: 5,
        PicturePreset.standard: 24,
        PicturePreset.high: 24,
      }[this]!;

  /// 背景动画覆盖（null = 跟随档位）。
  bool? get anim => const <PicturePreset, bool?>{
        PicturePreset.powerSave: false,
        PicturePreset.smooth: false,
        PicturePreset.standard: true,
        PicturePreset.high: true,
      }[this]!;

  /// 液态玻璃覆盖（null = 跟随档位）。
  bool? get liquid => const <PicturePreset, bool?>{
        PicturePreset.powerSave: false,
        PicturePreset.smooth: false,
        PicturePreset.standard: false,
        PicturePreset.high: true,
      }[this]!;

  /// 全局帧率限制（0 = 不覆盖，跟随现有档位）。
  FpsLimit? get fps => const <PicturePreset, FpsLimit?>{
        PicturePreset.powerSave: FpsLimit.fps24,
        PicturePreset.smooth: FpsLimit.fps30,
        PicturePreset.standard: FpsLimit.fps45,
        PicturePreset.high: null,
      }[this]!;

  /// 是否「省电」档（套用时提醒）。
  bool get isPowerSave => this == PicturePreset.powerSave;
}

/// 当前画面预设（纯 UI 状态；套用预设会一次性写入各特效 override）。
final picturePresetProvider =
    StateProvider<PicturePreset>((ref) => PicturePreset.standard);

/// 套用画面预设：一次设好 渲染精度 + 模糊 + 噪点 + 背景动画 + 液态玻璃 +
/// 全局帧率（cl54-G5）。
void applyPicturePreset(WidgetRef ref, PicturePreset p) {
  ref.read(picturePresetProvider.notifier).state = p;
  ref.read(renderPrecisionScaleProvider.notifier).state = p.precision;
  ref.read(noiseOverrideProvider.notifier).state = p.noise;
  ref.read(glassBlurOverrideProvider.notifier).state = p.blur;
  ref.read(bgAnimationOverrideProvider.notifier).state = p.anim;
  ref.read(liquidGlassOverrideProvider.notifier).state = p.liquid;
  // P7·#507：模糊采样率随预设联动（powerSave=0 关模糊 / smooth=5 / standard=24 / high=24）。
  ref.read(blurFpsProvider.notifier).state = p.blurFps;
  final FpsLimit? fps = p.fps;
  if (fps != null) {
    ref.read(fpsLimitProvider.notifier).state = fps;
  }
}

/// OOBE 完成标记（首次启动欢迎页；完成后不再显示）。
final oobeDoneProvider = StateProvider<bool>((ref) => false);

/// cl46：世界自动备份间隔（分钟：5 / 15 / 30 / 60）。
final backupIntervalMinutesProvider = StateProvider<int>((ref) => 15);

/// cl46：自定义世界机制——全局偏移率（0.0~1.0，参与地形 / 群系 / 结构生成）。
final worldGenOffsetProvider = StateProvider<double>((ref) => 0.0);

/// cl46：世界机制细调——地形起伏偏移（0.0~1.0）。
final worldGenTerrainProvider = StateProvider<double>((ref) => 0.0);

/// cl46：世界机制细调——群系分布偏移（0.0~1.0）。
final worldGenBiomeProvider = StateProvider<double>((ref) => 0.0);

/// cl46：世界机制细调——结构生成偏移（0.0~1.0）。
final worldGenStructureProvider = StateProvider<double>((ref) => 0.0);
