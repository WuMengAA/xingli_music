/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 3D 视图（Phase 1 · 渲染循环 + 交互 + 性能档位）
/// ════════════════════════════════════════════════════════════════════════
///
/// [VoxelWorldView3D]：`Ticker` 驱动 [VoxelRenderer]，`CustomPaint` 输出。
/// - **交互**：单指拖拽旋转（yaw / pitch）、双指捏合 + 滚轮变焦（fov）、
///   D-pad / 方向键 / WASD 移动相机、空闲若干秒后自动缓慢旋转。
/// - **性能**：读 `performanceModeProvider` 决定帧率与渲染档
///   （powerSave 12fps / 关雾 / 关天空渐变 / 关波纹；balanced 18fps；smooth 24fps），
///   动画时长乘 `motionScaleProvider`。
/// - **隔离**：画布外包 [RepaintBoundary]（方案要求：避免带着上层
///   `BackdropFilter` 高频重绘）；帧数据经 `ValueNotifier` 直接驱动
///   `CustomPainter.repaint`，不走 `setState`，省掉整轮 build/layout。
///
/// [VoxelWorld3DPage]：全屏调试 / 预览页（Phase 1 入口，从 2.5D 沉浸画布进入）。
/// 与 2.5D 的 `VoxelCanvasView` 完全并存、零 import 交集，可随时回滚。
library;

import 'dart:async';
import 'dart:convert' show JsonEncoder;
import 'dart:io' show Directory, File, FileMode;
import 'dart:math' as math;
import 'dart:typed_data' show Int32List;
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import '../../models/companion_action.dart';
import '../../models/companion_models.dart';
import '../../providers/companion/companion_providers.dart';
import '../../pages/canvas/photo_gallery_page.dart';
import '../../pages/canvas/voxel_canvas_page.dart';
import '../../pages/settings/settings_page.dart';
import '../../providers/settings/settings_layout_provider.dart';
import '../../providers/audio/audio_providers.dart';
import '../../widgets/playback/unified_player.dart';
import '../../widgets/lyrics/lyrics_view.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/scene/scene_custom_providers.dart';
import '../../providers/scene/voxel_scene_providers.dart';
import '../../models/scene.dart';
import '../../providers/voxel/world_audio_provider.dart';
import '../../providers/voxel/graphics_quality_provider.dart';
import '../../providers/voxel/cloud_view_distance_provider.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/settings/notification_providers.dart';
import '../../providers/voxel/hud_layout_provider.dart';
import '../../providers/storage/storage_providers.dart';
import 'voxel_capture_models.dart';
import 'voxel_world_types.dart';
import 'world_landmarks.dart';
import '../../services/voxel/world_to_canvas_exporter.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'voxel_textures.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../services/voxel/voxel_music_engine.dart';
import '../../services/voxel/voxel_audio_bundle.dart';
import 'voxel_camera.dart';
import 'voxel_crafting.dart';
import 'voxel_daynight.dart';
import 'voxel_inventory.dart';
import 'voxel_inventory_panel.dart';
import 'voxel_items.dart';
import 'voxel_mobs.dart';
import 'voxel_renderer.dart';
import 'voxel_survival.dart';
import 'player_controller.dart';
import 'voxel_world.dart';
import 'voxel_save.dart';
import 'view_mode_button.dart';
import 'world_audio_engine.dart';
import '../../widgets/notification/app_notify.dart';
import '../../providers/net/session_provider.dart';

/// 相机移动方向（D-pad / 键盘按住时累积）。
enum _Nav { forward, back, left, right, up, down }

/// 视角模式（R23：2.5D 等距 / 3D 俯瞰 / 3D 第一人称；R23k + 第三人称跟随）。
enum _ViewMode { iso2d5, orbit, firstPerson, thirdPerson }

/// 画面精度档（cl76：收纳折叠——只留控制游戏画质的四档预设）。
///
/// 低画质已足够：**无贴图 / 无水波 / 无光影（阴影+AO 渲染配置强制关闭）**，
/// 纯色平铺 + 雾 + 远景 LOD。高画质不再堆复杂度——最远只到「地平线」档。
enum GraphicsQuality {
  /// 省电：2 主区块 + 2 LOD 区块（共 4 区块），24fps。最轻量。
  powerSave('省电',
      viewDistanceChunks: 2,
      lodMaxChunks: 2,
      lodStartChunks: 1,
      lodStepChunks: 1,
      maxFaces: 4000,
      fpsCap: 24,
      fog: false,
      water: false,
      texture: false,
      renderScale: 0.5),

  /// 流畅：4 主区块 + 4 LOD 区块（共 8 区块），60fps。默认基线。
  smooth('流畅',
      viewDistanceChunks: 4,
      lodMaxChunks: 4,
      lodStartChunks: 2,
      lodStepChunks: 2,
      maxFaces: 12000,
      fpsCap: 60,
      fog: true,
      water: false,
      texture: false,
      renderScale: 1.0),

  /// 地平线：4 主区块 + 28 LOD 区块（共 32 区块），60fps。
  /// 远景山脉/立体地形靠 LOD 渲染；视距上限 4 区块、LOD 最远可到 60 区块
  /// （极值共 64 区块）。帧率上限 60fps。
  horizon('地平线',
      viewDistanceChunks: 4,
      lodMaxChunks: 28,
      lodStartChunks: 2,
      lodStepChunks: 2,
      maxFaces: 24000,
      fpsCap: 60,
      fog: true,
      water: false,
      texture: false,
      renderScale: 1.0),

  /// 自动：默认开启。基线 4+4（流畅档），运行时 10 秒窗口采样真实帧率，
  /// ≥30fps 不降 LOD 区块；不足则主视距区块逐档下调（4→2）直至满足。
  /// 帧率上限 60fps。
  auto('自动',
      viewDistanceChunks: 4,
      lodMaxChunks: 4,
      lodStartChunks: 2,
      lodStepChunks: 2,
      maxFaces: 12000,
      fpsCap: 60,
      fog: true,
      water: false,
      texture: false,
      renderScale: 1.0);

  const GraphicsQuality(
    this.label, {
    required this.viewDistanceChunks,
    required this.lodMaxChunks,
    required this.lodStartChunks,
    required this.lodStepChunks,
    required this.maxFaces,
    required this.fpsCap,
    required this.fog,
    required this.water,
    required this.texture,
    required this.renderScale,
  });

  final String label;
  final int viewDistanceChunks;

  /// LOD 最远区块（省电 2 / 流畅 4 / 地平线 28 / 自动 4）。
  final int lodMaxChunks;
  final int lodStartChunks;
  final int lodStepChunks;
  final int maxFaces;

  /// 档位帧率上限（省电 24 / 其余 60）。
  final int fpsCap;
  final bool fog;
  final bool water;
  final bool texture;

  /// 渲染分辨率倍率（省电 0.5 = 半分辨率渲染 + 放大，帧率翻倍）。
  final double renderScale;
}

/// 3D 体素世界视图（撑满父容器）。
class VoxelWorldView3D extends ConsumerStatefulWidget {
  const VoxelWorldView3D({
    super.key,
    required this.world,
    this.initialCamera,
    this.initialCameraMode = false,
    this.showControls = true,
    this.showStats = false,
    this.cameraOut,
    this.autoStart = true,
    this.survival = false,
    this.initialSaveData,
    this.readOnly = false,
    this.multiplayer = false,
  });

  final VoxelWorld world;

  /// 初始机位（默认 [VoxelCamera.overview] 全景俯瞰）。
  final VoxelCamera? initialCamera;

  /// cl29·②：进入即打开相机取景面板（场景页「拍照取景」入口透传）。
  final bool initialCameraMode;

  /// 相机外送口：每帧把当前机位写入，供父级「拍照取景」读取。
  ///
  /// 不触发 rebuild（只写 value，父级按需 `.value` 读取）。
  final ValueNotifier<VoxelCamera>? cameraOut;

  /// 是否显示 D-pad 等操作件。
  final bool showControls;

  /// 是否显示面数 / 列数调试角标（同时是「遮挡剔除」开关）。
  final bool showStats;

  /// G9：是否开启联机模式（注册远端编辑/变换回调、广播本地机位）。
  final bool multiplayer;

  /// H1r2：进入即自动开始游玩（不再显示首屏菜单——主菜单已独立成页）。
  /// false 仅用于测试（停在未开始态）。
  final bool autoStart;

  /// H1r2：autoStart 时的模式（true=生存 / false=创造）。
  final bool survival;

  /// R26fx：进入时恢复的存档数据（位置/视角/编辑层/背包；null = 全新世界）。
  final Map<String, dynamic>? initialSaveData;

  /// R26skel：只读预览——不恢复存档、不起存档定时器、不自动进入世界
  /// （照片墙「进入场景」等外部预览用，避免叠加游戏/叠加存档）。
  final bool readOnly;

  @override
  ConsumerState<VoxelWorldView3D> createState() => _VoxelWorldView3DState();
}

/// R26r3：渲染/帧循环异常落盘（支持目录 `voxel_render_error.log`，追加）。
/// 单帧异常不再杀死 Ticker（否则视角永久冻住、画面停在残影）——先保证应用
/// 活着，再由日志精确定位根因。
Future<void> _logRenderError(String where, Object e, StackTrace st) async {
  try {
    final Directory dir = await getApplicationSupportDirectory();
    final File f = File('${dir.path}/voxel_render_error.log');
    await f.writeAsString(
      '${DateTime.now().toIso8601String()} [$where] $e\n$st\n\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

class _VoxelWorldView3DState extends ConsumerState<VoxelWorldView3D>
    with SingleTickerProviderStateMixin {
  /// 移动速度（方块 / 秒，cl28：对齐我的世界——走 4.3、蹲 1.7、疾跑 5.6）。
  /// 基准值取 MC 行走 4.317 方块/秒，疾跑倍率 1.3 → 5.59 ≈ MC 冲刺 5.612。
  static const double _moveSpeed = 4.3;

  /// 自动巡航角速度（弧度 / 秒，约 2 分钟一圈）。
  static const double _orbitSpeed = 0.052;

  /// 空闲多久后开始自动旋转（秒，按 motionScale 缩放）。
  static const double _idleDelay = 6.0;

  late VoxelCamera _camera;

  /// R26g：测试钩子——当前相机俯仰（回归测试验证「进入第一人称归位
  /// pitch、不再朝下看灰地面」用；跨库测试无法直接读私有 `_camera`）。
  @visibleForTesting
  double get debugCameraPitch => _camera.pitch;

  /// R26h：世界种子短哈希（顶部居中信息条「世界名」用）。
  String get _seedTag =>
      '#${(widget.world.seed & 0xffff).toRadixString(16).toUpperCase().padLeft(4, '0')}';
  late final Ticker _ticker;
  final ValueNotifier<VoxelFrame> _frame = ValueNotifier<VoxelFrame>(
    VoxelFrame.empty,
  );
  final Set<_Nav> _held = <_Nav>{};

  /// 世界内空间音效引擎（Phase 3）：按相机机位把地形地物翻译成有方位的声音。
  /// 出错也不影响画面（全部吞掉），预览页退出时释放。
  WorldAudioEngine? _audio;

  /// 游戏内无音乐播放时的「我的世界」主题背景音乐轮换引擎（#322）。
  VoxelMusicEngine? _bgMusic;
  bool _bgMusicActive = false;

  /// AI 陪伴体素小人（破冰后才出现；主动发言时发光），每帧随地形一起渲染。
  List<VoxelEntity> _companionEntities = const <VoxelEntity>[];

  /// 小人当前站位（脚底中心，随 AI 指令平滑移动）。
  Vec3 _figurePos = Vec3.zero;

  /// 小人移动目标（null = 不动）。
  Vec3? _figureTarget;

  /// 镜头对准目标机位（null = 不强制对准）。
  VoxelCamera? _cameraTarget;

  /// 镜头环绕到期时间（null = 不环绕）。
  DateTime? _orbitUntil;

  /// 世界内空间音效启用状态（缓存，用于检测 provider 变化）。
  bool _audioEnabled = true;

  /// 小人是否发光（主动发言时），由 build 写入、tick 复用。
  bool _figureGlow = false;

  Size _viewport = Size.zero;
  Duration _lastTick = Duration.zero;
  double _idle = 0;
  double _wave = 0;
  bool _dirty = true;
  // R26r2：恢复遮挡剔除——透视根因是绘制顺序（已由深度排序修复），与剔除无关；
  // 恢复后性能回正常，正确性由画家算法保证。
  bool _occlusionCull = true;

  // cl30：重建增量门控 + 限频（正视用户「视角旋转剔除过度 + 刷新不持久」）。
  // 记录上次实际重建的机位/时相/分辨率倍率/区块失效序号；仅在「运动超阈值 或
  // 水波/昼夜推进 或 区块编辑 或 动态分辨率变化」且「距上次重建 ≥ minInterval」
  // 时才重跑整条管线，否则复用上一帧（屏幕空间，仅微动 → 误差 < ε，视觉无感）。
  // 这把「每 tick 全速重建」改为「运动即时重建 + 微动/动画/缩放走限频上限」，
  // 直接消除旋转卡顿——而 R26q 删掉的固定 56ms 节流之所以 stutter，是因它与
  // 输入解耦成固定 cadence；本方案运动即时、仅封顶，故不卡。各档 minInterval
  // 越大越「干脆不刷新」（性能档 50ms≈20fps 重建，高清档 16ms≈60fps 上限）。
  Duration _minRebuildInterval = const Duration(milliseconds: 33);
  double _lastBuildYaw = 0, _lastBuildPitch = 0;
  double _lastBuildEyeX = 0, _lastBuildEyeY = 0, _lastBuildEyeZ = 0;
  double _lastBuildPhase = 0, _lastBuildDynScale = 1.0;
  DateTime? _lastBuildAt;
  int _chunkInvalidSerial = 0; // 递增计数器（_invalidateChunkAt 自增）
  int _lastChunkSerial = 0; // 上次重建时记录的 _chunkInvalidSerial 快照
  bool _firstBuild = true;
  // G9：远端事件强制重建标志——远端编辑/玩家变换时置真并清静态快照，确保
  // 本地相机静止（已录 _staticPicture）时也能即时重绘远端变化。
  bool _forceRebuild = false;

  // G4：水流动按 20tps（1s=20 tick）驱动——独立 tick 累计器，与帧率解耦。
  double _waterTickAcc = 0;
  static const double _waterTickInterval = 1 / 20; // 50ms / tick
  // allowMask 面级 LOD 持久化缓存（cl30：旋转时侧面面不 popping，见 buildFrame）。
  final Map<(int, int), int> _allowMaskCache = <(int, int), int>{};
  final Map<(int, int), double> _allowMaskDotCache = <(int, int), double>{};

  static const Map<GraphicsQuality, int> _minRebuildMs = <GraphicsQuality, int>{
    GraphicsQuality.powerSave: 42, // 24fps 重建（"干脆不刷新"）
    GraphicsQuality.smooth: 16, // 60fps 上限（几乎不节流）
    GraphicsQuality.horizon: 16, // 60fps 上限
    GraphicsQuality.auto: 16, // 60fps 上限（降档由 FPS 监测器处理）
  };
  Duration _minIntervalFor(GraphicsQuality q) =>
      Duration(milliseconds: _minRebuildMs[q] ?? 33);

  // ── R23 视角模式 ─────────────────────────────────────
  // R26m：去掉俯视/2.5D 视角——初始即第一人称（进入世界前是中心地表预览）。
  _ViewMode _viewMode = _ViewMode.firstPerson;

  /// 第一人称：玩家脚底坐标（世界，方块单位）。
  Vec3 _fpPos = Vec3.zero;
  double _fpVy = 0;
  // R26r11：走路摇摆——相位按水平位移推进，静止平滑归零（玩家模型四肢摆动）。
  double _walkPhase = 0;
  double _walkSwing = 0;

  // G9：联机远端玩家快照（id → 状态）；收到远端 transform 即更新。
  final Map<String, PeerInfo> _remotePlayers = <String, PeerInfo>{};
  // G9：位置广播定时器（~100ms 上报自身机位 / 视角）。
  Timer? _netBroadcastTimer;
  // G9 cl67：编辑层快照按玩家位置范围同步——最近一次拉取快照时本地所在 chunk，
  // 用于「机位跨 chunk 时重新拉取」（游走加载/卸载）。初始化为不可能命中的哨兵值，
  // 强制首帧即拉取一次。
  int _lastSnapCx = -0x7FFFFFFF;
  int _lastSnapCz = -0x7FFFFFFF;
  // 快照覆盖半径（chunk 数）。远大于渲染视距窗口（渲染 ~8 chunk 见方），保证
  // 近端编辑始终被覆盖；远端大世界按游走按需加载，不全量下发（cl67 范围同步）。
  static const int _kSnapRadiusCount = 8;

  // R26r5：视角 Y 缓冲——跳跃 / 蹲下 / 上升下降时相机高度平滑跟随（不硬切）。
  double _eyeSmoothY = 0;
  bool _eyeSmoothInit = false;
  static const double _eyeSmoothK = 10.0; // 时间常数 ≈0.1s
  bool _fpOnGround = true;
  bool _fpJumpQueued = false;
  bool _jumpHeld = false; // cl28：跳跃键按住态（按住 = 水中持续上浮）
  double _oxygen = 1.0; // cl28：氧气（0~1，水下耗尽溺水），仅生存
  double _drownTimer = 0.0; // cl28：溺水伤害节拍（每 0.5s 扣 1 点）
  final ValueNotifier<double> _oxygenNotifier =
      ValueNotifier<double>(1.0); // cl28：供 HUD 氧气条重绘
  bool _submerged = false; // cl28：眼睛是否没入水中（每帧刷新，驱动跳跃键/氧气条 UI）
  bool _waterHintShown = false; // cl28：入水一次性提示是否已弹（每次进世界重置）

  // ── R24 跳跃 / 自动跳跃 / 坐标系统 ──────────────────
  /// 自动跳跃（R26r34 默认开启）：撞到 1 格台阶时自动抬升迈过。
  bool _autoJump = true;
  /// 坐标系统 HUD 开关（默认显示，类 F3）。
  bool _showCoords = true;
  /// 是否已进入世界（H1r2：autoStart 时启动即 true；主菜单已独立成页）。
  bool _started = false;

  /// H1r2：游戏暂停（打开游戏菜单时默认暂停整个世界——tick 冻结）。
  bool _paused = false;
  /// 坐标串（notifier：只让坐标 HUD 重绘）。
  final ValueNotifier<String> _coordsText = ValueNotifier<String>('');

  // ── R24c 画面精度 / 16×16 纹理图集 ──────────────────
  /// 画面精度档（流畅 / 标准 / 高清），影响视距 / LOD / 面数 / 雾 / 水波 / 贴图。
  // R26o：默认画质 = 流畅（低画质纯色为基础）；initState 里再按 provider 覆盖。
  GraphicsQuality _quality = GraphicsQuality.auto;

  // ── cl76_hotfix2：自动画质档——运行时 FPS 监测（10s 滚动窗口）──
  /// 自动档主视距区块（固定上限 4；帧率不足先降 LOD、LOD 到底再降此值，最小 2）。
  int _autoViewChunks = 4;
  /// 自动档 LOD 区块（基线 4，帧率富足上调 +4 → 上限 64）。
  int _autoLodChunks = 4;
  Duration _autoWindowStart = Duration.zero;
  int _autoFrames = 0;

  /// 16×16 纹理图集（异步构建；null = 尚未就绪，回退纯色）。
  ui.Image? _atlas;

  /// HUD 折叠（沉浸模式）：隐藏全部控件，仅留准星。
  bool _uiCollapsed = false;

  // ── R26h UI 重组：顶栏精简 + 折叠面板 + 顶部居中信息条 ──
  /// 折叠面板（坐标 / 模式等次级控制）开合。
  bool _foldOpen = false;
  /// 会话开始时间（顶部「游戏时长」统计用）。
  DateTime? _sessionStart;

  /// 虚拟摇杆输出（x=横移, y=前后；上为负）。
  double _joyX = 0;

  // R26o：第三人称摄像机环绕参数（「环绕」摇杆控制；默认身后 4 格、
  // 上方 2.5 格 = pitch asin(0.9/4)≈0.227）。
  double _tpCamYaw = 0;
  double _tpCamPitch = 0.227;
  double _tpCamDist = 4.0;
  double _joyY = 0;

  // ── R23d 相机模式（取景 + 焦距 + 快门截图）────────────
  bool _cameraMode = false;

  /// 双指捏合/滚轮调焦距（FOV）：记录上一帧缩放基准与焦点，避免抖动。
  Offset _scaleFocal = Offset.zero;
  double _lastScale = 1.0;

  /// 截图锚：包住 3D 画布的 RepaintBoundary。
  final GlobalKey _captureKey = GlobalKey();

  // ── R23d MC 玩法（第一人称：破坏 / 放置）─────────────
  Voxel _mcSelected = Voxel.stone;

  // ── R23e 物理 / 生存模式 ────────────────────────────
  /// true=生存模式（生命/摔落伤害/禁飞）；false=创造（可飞行）。
  bool _survival = false;

  // R28：存档是否成功恢复过玩家数值。true 时进生存模式不再 respawn（清零满血），
  // 否则每次进世界都把存档里的血量/饥饿冲掉 → 用户感知「数值每次被刷新」。
  bool _vitalsRestored = false;

  // R26p-camera：创造飞行模式。false=未飞行（受重力下落）；true=飞行（无重力、
  // 保持当前高度，升降键控制 altitude）。双击跳跃切换；再次双击退出→开始下落。
  bool _flyMode = false;
  DateTime? _lastJumpPress;

  /// 破坏/放置交互半径（格，MC 默认 5）。
  static const double _reach = 5.0;

  // ── R23f 蹲 / 碰撞 / 瞄准框 ─────────────────────────
  /// 是否蹲下（Shift 或 D-pad 下）：视线降低、碰撞箱变矮、移速减半。
  bool _crouching = false;

  /// R26c 是否疾跑（Ctrl）：移速 ×1.35（蹲下时无效）。
  bool _sprinting = false;

  /// 准星瞄准的目标方块（notifier：值变化自动通知瞄准框 painter 重绘）。
  final ValueNotifier<(int, int, int)?> _aimNotifier =
      ValueNotifier<(int, int, int)?>(null);

  /// 是否绘制瞄准框（第一人称/第三人称、非相机模式）。
  bool get _showAim =>
      (_viewMode == _ViewMode.firstPerson ||
          _viewMode == _ViewMode.thirdPerson) &&
      !_cameraMode;

  // R26f：瞄准射线降频缓存（10Hz，_raycast 每帧跑是 CPU 浪费）。
  Duration? _aimCastAt;
  ((int, int, int), (int, int, int))? _aimCached;

  // R26f：僵尸/掉落物 tick 累计器（~8Hz 门控）。
  double _mobTickAcc = 0;
  // R26r10：掉落物独立高频 tick 累计器（~30Hz）。
  double _dropTickAcc = 0;

  // R26f：静态地形 Picture 缓存（挂机/观景大杀器）。
  // 相机连续静止 ≥1.5s 且无输入 → 录整帧快照，之后跳过 buildFrame 直接
  // drawPicture（CPU -90%）；任何相机变化 / 交互 / 地形编辑 / 画质切换即失效。
  ui.Picture? _staticPicture;
  VoxelCamera? _staticCamKey;
  Duration? _staticSince;

  // 由 build 中的 provider 读取写入，Ticker 回调消费。
  RenderConfig _config = const RenderConfig();

  // ── R23w 背包 / 生存 / 生物 / 挖掘 ───────────────────
  /// 36 格背包（前 9 格 = 快捷栏）。
  final VoxelInventory _inv = VoxelInventory();

  /// 生命 / 饥饿 / 经验（cl38 P1：改由 [playerVitalsProvider] 单例真相源提供，
  /// 供开放世界多系统共享；外部 13 处 _vitals.xxx() 引用保持不变）。
  /// late final：在 initState 从 provider 注入（dispose 后仍可用，不依赖 ref）。
  late final PlayerVitals _vitals;

  /// 僵尸 + 掉落物世界。
  late final MobWorld _mobs = MobWorld(world: widget.world);

  /// 背包面板是否打开。
  bool _bagOpen = false;

  /// 是否正按住（长按挖掘）。
  bool _acting = false;

  // R26r5：左键「按下位置 + 是否已拖动」——按下即转动（拖动）不破坏物品，
  // 只有「按下→松开未动」才算一次点击破坏（见 _onPointerDown/_onPointerMove/_onPointerUp）。
  Offset _downPos = Offset.zero;
  bool _downMoved = false;

  // R26k：桌面鼠标绑定（FPS）——鼠标移动视角、左键挖掘/攻击、右键放置；
  // Alt 按住暂停视角（可点 UI）。触屏拖拽环视走 GestureDetector（不受影响）。
  // R26m：光标保持可见；[ _mousePos] 用于「边缘续转」（贴窗口边缘继续转）。
  bool _fpMouseCaptured = true;
  Offset? _lastMousePos;
  Offset? _mousePos;

  /// 本次按住期间是否已挖掉方块（松手时不再补一刀）。
  bool _brokeInHold = false;

  /// 正在挖的方块（null = 没在挖）。
  (int, int, int)? _miningAt;

  /// 当前方块所需总耗时（秒）。
  double _miningNeed = 0;

  // R26r7：创造模式破坏冷却（0.5s 允许破坏一个方块）。
  DateTime? _lastBreakAt;

  // R26r7：自适应分辨率——望向脚下/天上等面数陡增场景自动降渲染倍率保帧。
  double _dynScale = 1.0;
  double _frameDynScale = 1.0; // 当前帧实际用的倍率（画家读取，保证帧/画一致）
  int _slowFrames = 0;
  int _fastFrames = 0;

  /// 已挖时长（秒）。
  double _miningTime = 0;

  /// 挖掘进度 0~1（notifier：只重绘裂纹层）。
  final ValueNotifier<double> _crackNotifier = ValueNotifier<double>(0);

  /// 攻击冷却（秒），防止长按变成连击机枪。
  double _attackCd = 0;

  /// 上一帧玩家水平位置（算移动距离 → 疲劳）。
  double _lastPx = 0, _lastPz = 0;

  // ── R23v 昼夜循环 ───────────────────────────────────
  /// 昼夜推进器：默认从清晨出发、cl28 起 20 分钟一昼夜（对齐 MC；1 秒=20 ticks）；
  /// HUD 时钟可锁定档位。
  final DayNightCycle _time = DayNightCycle(phase: 0.16, dayLength: 1200);

  /// 时钟串（notifier：只让 HUD 时钟重绘，不触发整页 rebuild）。
  final ValueNotifier<String> _clockText = ValueNotifier<String>('');

  /// R23s：区块几何缓存——跨帧复用 occlusion 可见面，大幅提升体素世界帧率。
  /// 由本 state 持有，编辑方块 / 换世界 / 切换遮挡剔除时失效。
  final VoxelChunkCache _chunkCache = VoxelChunkCache();

  double _motionScale = 1;
  bool _autoOrbit = true;

  // ── R24d 30s 自动存档状态 ─────────────────────────────
  Timer? _saveTimer;
  DateTime? _lastSavedAt;

  /// R27：返回键退出闸门——true 时允许 PopScope 真正 pop（仅 [_saveAndExit] 时临时置 true）。
  bool _allowPop = false;
  /// R27：上次按返回键的时间（用于「连按两次 = 保存退出」判定）。
  DateTime? _lastBackPress;

  /// R26d 手动存档命名输入（存档菜单弹层用）。
  final TextEditingController _saveNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // cl38 P1：玩家生存状态单一真相源（开放世界多系统共享）。
    _vitals = ref.read(playerVitalsProvider);
    // cl29·②：场景页「拍照取景」入口透传——进入即开相机取景面板。
    if (widget.initialCameraMode) _cameraMode = true;
    // R26m：初始相机 = 世界中心地表第一人称（去掉俯视 overview 预览）。
    final double cx0 = widget.world.sizeX / 2;
    final double cz0 = widget.world.sizeZ / 2;
    _camera = widget.initialCamera ??
        VoxelCamera(
          position: Vec3(
            cx0,
            VoxelCamera.groundHeightAt(widget.world, cx0, cz0) +
                VoxelCamera.eyeHeight,
            cz0,
          ),
          pitch: -0.15,
        );
    // 小人初始站在世界中心。
    // F2（用户确认）：出生点必须找**陆地**（地表 > 海平面）——G6 后世界中心
    // 可能是海洋/河流，直接落 center 会「在水下出生」。从中心向外螺旋找第一
    // 个地表高于水位的陆地列；找不到则回落中心（保底）。
    final int wl = widget.world.waterLevel;
    int sx = widget.world.sizeX ~/ 2;
    int sz = widget.world.sizeZ ~/ 2;
    bool foundLand = false;
    for (int r = 0; r <= 48 && !foundLand; r++) {
      for (int dz = -r; dz <= r; dz++) {
        for (int dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dz.abs() != r) continue; // 只扫环
          final int h = widget.world.terrainHeightAt(sx + dx, sz + dz);
          if (h > wl + 1) {
            sx += dx;
            sz += dz;
            foundLand = true;
            break;
          }
        }
        if (foundLand) break;
      }
    }
    _figurePos = Vec3(
      sx.toDouble(),
      VoxelCamera.groundHeightAt(widget.world, sx.toDouble(), sz.toDouble()),
      sz.toDouble(),
    );
    _figureTarget = _figurePos;
    // R26 修复：玩家位置此前仅声明为 Vec3.zero 从未初始化 → 第一人称出生在
    // 世界 (0,0) 角落/半空（用户反馈「玩家在半空中」）。与世界中心小人同点：
    // 中心地表高度落位，保证进入即可正常行走/落地。
    _fpPos = _figurePos;
    _fpOnGround = true;
    _lastPx = _fpPos.x;
    _lastPz = _fpPos.z;

    // R26fx：从存档进入时恢复玩家状态（位置/视角/编辑层/背包）——
    // 不再每次重置摄像头（存档已记录视角方向）。
    final Map<String, dynamic>? initData = widget.initialSaveData;
    if (initData != null) _applyInitialSave(initData);

    // R23w：按当前模式装包（创造给满、生存给起步套装）。
    _syncInventoryForMode();

    // 世界音效：按开关决定是否起播。
    _audioEnabled = ref.read(worldAudioEnabledProvider);
    _syncAudio();

    // R26f：Isolate 地形预热——首帧后后台算玩家周边 12 格半径的高度/树，
    // 回填缓存（compute 跑在后台 isolate，主线程不卡；结果与实例采样同一
    // 算法，seed 校验防换世界误填）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final int seed = widget.world.seed;
      final List<int> args = <int>[
        seed,
        widget.world.sizeX ~/ 2,
        widget.world.sizeZ ~/ 2,
        12,
        1, // withTrees
      ];
      unawaited(
        compute(VoxelWorld.precomputeTerrainArgs, args).then((Int32List data) {
          if (!mounted) return;
          widget.world.injectTerrainPrecache(data, seed);
        }),
      );
    });

    // R24c：按当前精度档位初始化渲染配置（默认「标准」= 视距/雾/水波/贴图全开）。
    // R26c：画质档提升为共享 provider（游戏中快捷设置可改），初始值取自 provider；
    // 变更监听（ref.listen）须在 build 中注册（Riverpod 限制）。
    _quality = ref.read(graphicsQualityProvider);
    _config = _configFor(_quality);
    // R26d：载入 HUD 自定义布局（postFrame 后改 provider——initState 修改
    // provider 会触发「build 期修改」断言）。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(hudLayoutProvider.notifier).state =
          readHudLayout(ref.read(prefsProvider));
      ref.read(hudScaleProvider.notifier).state =
          readHudScale(ref.read(prefsProvider));
    });

    // 打开世界时，若此前已有排队的操作（用户在聊天里先下了指令），立即落地。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final List<CompanionAction> queued =
          ref.read(companionStateProvider).pendingActions;
      if (queued.isNotEmpty) _applyActions(queued);
    });

    _ticker = createTicker(_onTick)..start();

    // R24c：异步构建纹理图集（含可选的玩家皮肤，#169）。皮肤缺失/解码失败
    // 安全回退为无皮肤图集，实体走纯色。
    () async {
      // R26g：不再加载玩家皮肤——自身方块人模型已移除（其皮肤贴图在高画质下
      // 会污染地形批次导致黑方块）。skinBytes:null ⇒ _hasSkin=false，实体一律
      // 纯色，图集更省内存，且无任何副作用。
      ui.Image? img;
      try {
        img = await VoxelTextureAtlas.build(skinBytes: null);
      } catch (_) {
        img = null;
      }
      if (img == null || !mounted) {
        img?.dispose();
        return;
      }
      _atlas = img;
      _dirty = true;
      setState(() {});
    }();

    // R24d：自动存档——进入世界先尝试恢复上次存档，并启动 30s 周期落盘。
    // R26skel：readOnly 预览（照片墙「进入场景」等）**不碰存档**——不恢复、
    // 不写盘，避免叠加游戏/叠加存档；仅允许主菜单·世界存档路径进入真实游戏。
    if (!widget.readOnly) {
      unawaited(_restoreSave());
      _saveTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _saveNow(),
      );
    }

    // H1r2：autoStart（主菜单「新的世界」/ 读档进入）→ 首帧后直接进入世界。
    if (widget.autoStart && !widget.readOnly) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enterWorld(widget.survival);
        // R27：进入即落盘首份自动存档——新世界从 t=0 即持久（不再等 30s 周期，
        // 防启动后崩/退出丢档；直接回应「新建游戏没存档」）。
        unawaited(_saveNow());
      });
    }

    // G9：联机模式——注册远端编辑/变换回调，启动 ~100ms 位置广播。
    if (widget.multiplayer) {
      final NetSessionNotifier net = ref.read(netSessionProvider.notifier);
      net.onRemoteEdit = (int x, int y, int z, int v) {
        widget.world.setVoxel(x, y, z, Voxel.values[v]);
        _invalidateChunkAt(x, z);
        _staticPicture = null; // 清静态快照：远端编辑必须即时重绘
        _forceRebuild = true; // 计入重建门控（即便本地相机静止）
        _dirty = true;
      };
      net.onRemoteTransform = (String id, double x, double y, double z,
          double yaw, double pitch, int vm) {
        _remotePlayers[id] = PeerInfo(
          id: id,
          x: x,
          y: y,
          z: z,
          yaw: yaw,
          pitch: pitch,
          viewMode: vm,
        );
        _staticPicture = null; // 清静态快照：远端玩家移动必须即时重绘
        _forceRebuild = true; // 计入重建门控
        _dirty = true;
      };
      // G9 cl67：重连成功后重拉自身周围快照（连接视为全新，主机不主动下发，
      // 须客户端按新机位重新请求）；cl65 仍清旧远端玩家缓存避免重复方块人。
      net.onReconnected = () {
        _remotePlayers.clear();
        _staticPicture = null;
        _forceRebuild = true;
        _dirty = true;
        if (ref.read(netSessionProvider).role == NetRole.client) {
          _requestSnapshotAroundMe();
        }
      };
      // G9 cl67：编辑层快照——按玩家位置范围同步（加入 / 重连 / 游走时看到
      // 自身周围他人已建结构）。客户端：收到快照合并到本地世界（[mergeEditLayer]
      // 不清空现有 _edits，保留此前已合并的远处编辑 + 本地自身编辑；随后
      // 清静态快照 + 强制重建 + 失效几何缓存）。
      net.onEditSnapshot = (List<dynamic> edits, List<dynamic> lights) {
        widget.world.mergeEditLayer(<String, dynamic>{
          'schema': 2,
          'edits': edits,
          'lights': lights,
        });
        _chunkCache.clear(); // 编辑层已变 → 全量几何缓存失效，强制整帧重建
        _staticPicture = null; // 清静态快照：快照必须即时重绘
        _forceRebuild = true; // 计入重建门控（即便本地相机静止）
        _dirty = true;
      };
      // 主机：提供权威编辑层快照，但按请求者机位就近裁剪（[editLayerJsonNear]），
      // 只回发其周围 _kSnapRadiusCount 格区块（地形不同步，仅编辑层）。
      if (ref.read(netSessionProvider).role == NetRole.host) {
        net.editSnapshotProvider = (int cx, int cz, int radius) =>
            widget.world.editLayerJsonNear(_fpPos.x ~/ VoxelWorld.kChunkSize,
                _fpPos.z ~/ VoxelWorld.kChunkSize, radius);
      }
      // 客户端：注册回调后按自身机位主动拉取一次快照（避免「welcome/Snapshot
      // 早于 world 视图回调注册」竞态；主机不再主动全量下发，改由客户端按
      // 机位请求，二者契合 cl67 范围同步）。
      if (ref.read(netSessionProvider).role == NetRole.client) {
        _requestSnapshotAroundMe();
      }
      _netBroadcastTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _broadcastMyTransform(),
      );
    }
  }

  /// 世界空间音效的最终增益（#170）：世界通道音量 × 主音量。
  double _worldAudioGain() =>
      (ref.read(worldSfxVolumeProvider) * ref.read(masterVolumeProvider))
          .clamp(0.0, 1.0);

  /// 启动 / 停止世界空间音效（受 [worldAudioEnabledProvider] 控制，失败静默）。
  void _syncAudio() {
    if (!mounted) return;
    if (_audioEnabled && _audio == null) {
      try {
        _audio = WorldAudioEngine(widget.world);
        _audio!.prepare();
        // #170：世界空间音效通道音量 × 主音量，起播即生效
        _audio!.setGlobalVolume(_worldAudioGain());
        unawaited(
          _audio!.start(_camera).catchError((Object _, StackTrace __) {}),
        );
      } catch (_) {
        _audio = null;
      }
      // #322：游戏内无音乐播放 → 启动 MC 主题背景音乐轮换。
      if (_bgMusic == null) {
        _bgMusic = VoxelMusicEngine();
        // Bug④（#375）：安卓进世界崩溃根因。init() 是「未 await 的 Future」，
        // 原 .then 没有 .catchError——一旦 init（或 .then 内 setActive）抛异常，
        // 即成为主 isolate 的「未处理异步错误」，安卓 release 直接原生崩溃/ANR
        // （桌面 debug 仅红屏）。与上方 WorldAudioEngine 路径（line 703 已
        // catchError）对称，这里也必须兜底吞掉，失败静默（无素材 = 不播 BGM）。
        unawaited(
          _bgMusic!.init().then((_) {
            if (!mounted) return;
            try {
              final bool playing =
                  ref.read(isPlayingProvider).valueOrNull ?? false;
              _bgMusicActive = !playing;
              unawaited(_bgMusic!.setActive(_bgMusicActive));
            } catch (_) {
              // setActive 失败（audioplayers 在安卓初始化异常等）：静默放弃 BGM。
            }
          }).catchError((Object _, StackTrace __) {
            // init 失败：保留 _bgMusic 实例但不再激活，避免重复尝试触发崩溃。
          }),
        );
      }
    } else if (!_audioEnabled && _audio != null) {
      _audio?.dispose();
      _audio = null;
      _bgMusic?.dispose();
      _bgMusic = null;
    }
  }

  /// 每帧同步背景音乐激活态：游戏内有音乐播放则让位暂停，否则续播（#322）。
  void _syncBgMusic() {
    if (_bgMusic == null) return;
    final bool playing = ref.read(isPlayingProvider).valueOrNull ?? false;
    if (playing == _bgMusicActive) return;
    _bgMusicActive = playing;
    unawaited(_bgMusic!.setActive(!playing));
  }

  /// 把一组 AI 动作落地到世界（走位 / 转镜头 / 环绕 / 控音效），随后消费队列。
  void _applyActions(List<CompanionAction> actions) {
    final WorldLandmarks landmarks = WorldLandmarks(widget.world);
    for (final CompanionAction a in actions) {
      switch (a.kind) {
        case CompanionActionKind.moveFigure:
          final Vec3? target =
              a.landmark != null ? landmarks.anchorFor(a.landmark!) : null;
          if (target != null) _figureTarget = target;
        case CompanionActionKind.focusCamera:
          if (a.landmark != null) {
            _cameraTarget = cameraForLandmark(widget.world, a.landmark!);
          }
        case CompanionActionKind.orbitCamera:
          _orbitUntil = DateTime.now().add(const Duration(seconds: 6));
        case CompanionActionKind.toggleWorldAudio:
          if (a.enabled != null) {
            ref.read(worldAudioEnabledProvider.notifier).state = a.enabled!;
          }
      }
    }
    ref.read(companionStateProvider.notifier).consumeActions();
    _dirty = true;
  }

  /// 由陪伴会话状态推导出世界中的体素小人实体。
  ///
  /// - 未破冰（陌生人尚未接触）→ 不渲染（它只是"坐着"，不在世界里走动）；
  /// - 已接触 → 出现在 [_figurePos]（初始世界中心，可被 AI 指令移动）；
  /// - 最后一条是它主动发的消息 → 发光（高亮提示用户它开口了）。
  List<VoxelEntity> _entitiesFor(CompanionSession s) {
    if (!s.firstContactMade) return const <VoxelEntity>[];
    final bool speaking = s.messages.isNotEmpty &&
        s.messages.last.role == CompanionRole.companion &&
        s.messages.last.proactive;
    return <VoxelEntity>[
      VoxelEntity(
        position: _figurePos,
        color: const Color(0xFF7CC8FF),
        scale: 1.0,
        glow: speaking,
      ),
    ];
  }

  @override
  void didUpdateWidget(covariant VoxelWorldView3D oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.world, widget.world)) {
      // 换世界：保留视角，机位按新地形重新贴地（Phase 4「换个世界」的雏形）。
      final VoxelCamera fresh = VoxelCamera.overview(widget.world);
      _camera = fresh.copyWith(yaw: _camera.yaw, fov: _camera.fov);
      _chunkCache.clear(); // 换世界：几何全部失效
      _dirty = true;
      _staticPicture = null; // R26f：换世界 → 静态快照失效
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNameCtrl.dispose();
    unawaited(writeVoxelSave(_buildSaveData())); // 退出前最后落盘（不触发 setState）
    _audio?.dispose();
    _bgMusic?.dispose();
    _ticker.dispose();
    _frame.dispose();
    _aimNotifier.dispose();
    _clockText.dispose();
    _crackNotifier.dispose();
    _coordsText.dispose();
    _inv.dispose();
    // cl38 P1：_vitals 生命周期由 playerVitalsProvider 管理（ref.onDispose 清理），
    // 此处不再 dispose，避免与 provider 双重 dispose。
    _mobs.clear();
    // G9：联机清理——取消位置广播并解绑远端回调（世界退出后不再接收远端推送）。
    _netBroadcastTimer?.cancel();
    _netBroadcastTimer = null;
    if (widget.multiplayer) {
      final NetSessionNotifier net = ref.read(netSessionProvider.notifier);
      net.onRemoteEdit = null;
      net.onRemoteTransform = null;
      net.onReconnected = null;
      net.onEditSnapshot = null;
      net.editSnapshotProvider = null;
    }
    super.dispose();
  }

  // ── 渲染循环 ─────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    try {
    // 瞄准框每帧刷新（独立于地形重建的帧率节流），保证选择框始终跟手、不卡顿。
    // R26f：射线本体降频到 10Hz（100ms 缓存），瞄准框显示用缓存结果——射线遍历
    // 每帧跑是大头 CPU 浪费，10Hz 下选择框手感不变。
    if (_showAim) {
      if (_aimCastAt == null ||
          elapsed - _aimCastAt! >= const Duration(milliseconds: 100)) {
        _aimCastAt = elapsed;
        _aimCached = _raycast();
      }
      _aimNotifier.value = _aimCached?.$1;
    }
    // R26q：移除固定 56ms 重建节流——它把实际世界重建压到 ~18fps，导致转动视角
    // 明显卡顿（而 Ticker 仍 60fps，FPS 计数"正常"）。重建本就由 `_dirty` 门控：
    // 有变化才重建、静止后由静态快照(_staticPicture)完全跳过，无需再节流。
    // 现在相机转动时每帧全速重建 → 顺滑。
    final double dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _lastTick = elapsed;

    // cl76_hotfix2：自动画质——10 秒滚动窗口采样真实帧率，**双向**调节：
    // - 帧率富足（≥45fps）→ LOD 上调 4+4+n（上限 64 区块），看得更远；
    // - 不足（<30fps）→ 先降 LOD（≥2），LOD 到底再降主视距区块（≥2）；
    // - 中间区间保持；视距固定上限 4、LOD 上限 64（最大渲染约束）。
    if (_quality == GraphicsQuality.auto) {
      _autoFrames++;
      if (_autoWindowStart == Duration.zero) _autoWindowStart = elapsed;
      final Duration win = elapsed - _autoWindowStart;
      if (win >= const Duration(seconds: 10)) {
        final double fps = _autoFrames / (win.inMilliseconds / 1000.0);
        _autoWindowStart = elapsed;
        _autoFrames = 0;
        bool changed = false;
        if (fps >= 45 && _autoLodChunks < 64) {
          _autoLodChunks = math.min(64, _autoLodChunks + 4);
          changed = true;
        } else if (fps < 30) {
          if (_autoLodChunks > 2) {
            _autoLodChunks = math.max(2, _autoLodChunks - 4);
            changed = true;
          } else if (_autoViewChunks > 2) {
            _autoViewChunks--;
            changed = true;
          }
        }
        if (changed) {
          _config = _configFor(_quality);
          _dirty = true;
        }
      }
    }

    // H1r2：游戏暂停——整个世界冻结（物理/时间/玩法/音效推进全停，仅菜单活）。
    if (!_paused) {
    // R26n：第一/第三人称**每帧**跑物理（重力/落地/移动）——此前只在按键时
    // 跑，松开按键即停重力 → 走平地被地形推起后悬浮、无下落物理（用户反馈）。
    // 自动巡航（orbit 模式）已随俯视/2.5D 一并移除，不再需要。
    final bool fpNow = _viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson;
    if (fpNow) {
      _applyNavFP(dt);
      // cl28 氧气 + 溺水：眼睛没入水中缓慢耗尽（~15s），出水 5s 回满；
      // 耗尽后每 0.5s 扣 1 点生命（仅生存）。
      if (_survival) _tickOxygen(dt);
      // cl28 UI 同步：每帧刷新「是否没入水中」→ 驱动跳跃键变「游↑」+ 氧气条显隐；
      // 首次入水弹一次性提示，告知新水机制（无浮力 / 缓沉 / 按跳上浮 / 氧气耗尽）。
      _submerged = _headInWater();
      if (_submerged && !_waterHintShown) {
        _waterHintShown = true;
        _snack('水中无浮力，会缓慢下沉；按住跳跃上浮 · 注意氧气条');
      }
    } else if (_held.isNotEmpty) {
      _applyNav(dt);
    }

    // R26m：鼠标贴窗口边缘 → 持续转视角（FPS 手感，无需平台鼠标捕获）。
    _applyEdgeLook(dt);

    if (_config.waterAnimation) {
      _wave = (_wave + dt * 0.35 / _motionScale) % 1000;
      _dirty = true;
    }

    // R23v 昼夜推进：时相变化 → 天色 / 光照 / 时钟一起走。
    if (_time.advance(dt)) _dirty = true;
    final String clock = '${_time.clock} · ${_time.mode.label}';
    if (_clockText.value != clock) _clockText.value = clock;

    // R24 坐标系统：第一人称/第三人称下实时刷新玩家坐标 + 朝向 + 群系。
    if (_viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson) {
      final String cs =
          'X ${_fpPos.x.toStringAsFixed(1)}  Y ${_fpPos.y.toStringAsFixed(1)}  '
          'Z ${_fpPos.z.toStringAsFixed(1)}\n'
          '${_facingLabel(_camera.yaw)} · '
          '${_biomeLabel(widget.world.biomeAt(_fpPos.x.floor(), _fpPos.z.floor()))}';
      if (_coordsText.value != cs) _coordsText.value = cs;
    }

    // R23w 玩法推进：饥饿 / 僵尸 / 掉落物 / 长按挖掘。
    _tickGameplay(dt);

    // G4：水流动按 20tps（1s=20 tick）驱动——累计真实 dt，满一个 tick（50ms）
    // 走一步扩散；与帧率解耦（60fps 下每 ~3 帧扩散一步，挂机不扩散）。
    // cl30+：设置「水流动」开关关闭时跳过扩散（waterFlowEnabledProvider）。
    _waterTickAcc += dt;
    while (_waterTickAcc >= _waterTickInterval) {
      _waterTickAcc -= _waterTickInterval;
      if (!ref.read(waterFlowEnabledProvider)) continue;
      final List<(int, int, int)> wrote = widget.world.spreadWater();
      if (wrote.isNotEmpty) {
        // 扩散写进编辑层 → 失效这些位置所在区块的几何缓存（让新水渲染出来）。
        final Set<int> invalidated = <int>{};
        for (final (int wx, int _, int wz) in wrote) {
          final int cx = wx ~/ 16, cz = wz ~/ 16;
          final int key = cx * 4096 + cz;
          if (invalidated.add(key)) {
            _chunkCache.invalidate(cx, cz);
          }
        }
        _dirty = true;
        _staticPicture = null; // 水扩散 → 静态快照失效
      }
    }

    // AI 指令落地：平滑把小人移到目标、把镜头对准目标。
    _stepFigure(dt);
    _stepCamera(dt);

    // 镜头环绕（AI「转一圈」）：到期前持续慢转。
    if (_orbitUntil != null) {
      if (DateTime.now().isBefore(_orbitUntil!)) {
        _camera = _camera.rotate(_orbitSpeed * dt, 0);
        _dirty = true;
      } else {
        _orbitUntil = null;
      }
    }

    // 相机变化 → 推动世界空间音效（增益 / 声像 / 隔音随机位刷新）。
    _audio?.onCamera(_camera);
    // #322：同步背景音乐激活态（游戏内无音乐才播）。
    _syncBgMusic();
    }

    // R26f：静态快照检测——相机连续静止 ≥1.5s 且无输入 → 录整帧 Picture，
    // 之后跳过 buildFrame 直接 drawPicture（挂机/观景 CPU -90%）。
    // 任何相机变化 / 输入 / 地形编辑 / 画质切换即失效（编辑处手动清）。
    final VoxelCamera? sk = _staticCamKey;
    final bool camSame = sk != null &&
        _camera.position.x == sk.position.x &&
        _camera.position.y == sk.position.y &&
        _camera.position.z == sk.position.z &&
        _camera.yaw == sk.yaw &&
        _camera.pitch == sk.pitch &&
        _camera.fov == sk.fov;
    if (_held.isEmpty && camSame) {
      _staticSince ??= elapsed;
      if (elapsed - _staticSince! >= const Duration(milliseconds: 1500) &&
          _staticPicture == null) {
        _staticPicture = _recordStaticPicture(_frame.value);
        if (mounted) setState(() {}); // 让 painter 拿到快照
      }
    } else {
      _staticSince = null;
      if (_staticPicture != null) {
        _staticPicture = null;
        _dirty = true; // 快照失效 → 恢复实时渲染
      }
      _staticCamKey = _camera;
    }
    if (_staticPicture != null) return; // 快照命中：跳过 buildFrame

    if (!_dirty || _viewport.isEmpty) return;
    _dirty = false; // 先消费；若被节流跳过，下方会重新置位以保留请求

    // cl30：重建增量门控 + 限频（减少刷新频率 / 干脆不刷新，正视用户
    // 「视角旋转剔除过度 + 刷新不持久」）。仅「运动超阈值 / 水波·昼夜推进 /
    // 区块编辑 / 动态分辨率变化」且距上次重建 ≥ minInterval 时才重跑整条
    // 管线，否则复用上一帧（屏幕空间，仅微动 → 误差 < ε，视觉无感）→ 旋转不卡。
    final double clYaw = (_camera.yaw - _lastBuildYaw).abs();
    final double clPitch = (_camera.pitch - _lastBuildPitch).abs();
    final double clDx = _camera.position.x - _lastBuildEyeX;
    final double clDy = _camera.position.y - _lastBuildEyeY;
    final double clDz = _camera.position.z - _lastBuildEyeZ;
    final double clPos = math.sqrt(clDx * clDx + clDy * clDy + clDz * clDz);
    double clPhase = (_time.phase - _lastBuildPhase) % 1.0;
    if (clPhase > 0.5) clPhase -= 1.0;
    final double clPhaseAbs = clPhase.abs();
    final bool clChunkChanged = _chunkInvalidSerial != _lastChunkSerial;
    final bool clScale = (_dynScale - _lastBuildDynScale).abs() > 1e-4;
    final bool clMotion = (clYaw + clPitch) > 0.004 || clPos > 0.02;
    // P0(性能合集)：clAnim 仅由「真实时相变化」驱动——去掉 `|| _config.waterAnimation`。
    // 原写法让水波（smooth 起恒开）每帧把 clReal 置真 → 每帧全量 buildFrame → 低档
    // 也在做 8 区块遍历 + 面数预算裁剪的纯 CPU 浪费（5090 卡死主因之一）。水波动画
    // 本身是顶点级小成本，重绘由 _dirty 门控即可，无需每帧重建整条管线。
    final bool clAnim = clPhaseAbs > 1e-7;
    final bool clReal = _firstBuild ||
        clMotion ||
        clAnim ||
        clChunkChanged ||
        clScale ||
        _forceRebuild;
    final DateTime clNow = DateTime.now();
    final DateTime? clLastAt = _lastBuildAt; // 本地副本便于空安全提升
    final bool clWithinInterval = clLastAt != null &&
        clNow.difference(clLastAt) < _minRebuildInterval;
    if (!clReal) {
      // 无可检测变化（如仅 occlusion 开关 / 纯强制 _dirty）：达限频窗口才重建，
      // 否则保留请求（更新类操作在 ≤minInterval 内终会生效）。
      if (clWithinInterval) {
        _dirty = true;
        return;
      }
    } else if (!_firstBuild && clWithinInterval) {
      _dirty = true; // 限频跳过（运动/动画/编辑/缩放走限频上限 → 不卡）
      return;
    }
    // 外送当前机位（供父级拍照取景，不触发 rebuild）
    widget.cameraOut?.value = _camera;
    // R26o：渲染分辨率倍率（性能档 0.5 → 半分辨率渲染 + 画家放大）。
    // R26r7：乘以动态倍率 _dynScale——望向脚下/天上等面数陡增场景自动降。
    // cl46 修复：**必须**与画家 renderScale 完全一致（_quality.renderScale ×
    // renderPrecisionScale × _dynScale）。此前漏乘 renderPrecisionScale，画家
    // 却乘了它 → frame 顶点在较大的视口空间、paint 却按较小空间放大 1/rs 倍
    // → 画面被放大只显示屏幕左上角（用户实测「拉低拉高分辨率只显示左上角」）。
    final double rs = _quality.renderScale *
        ref.read(renderPrecisionScaleProvider) *
        _dynScale;
    _frameDynScale = _dynScale; // 快照：画家与本帧用同一倍率，避免拉伸错位
    final Stopwatch sw = Stopwatch()..start();
    _frame.value = VoxelRenderer.buildFrame(
      world: widget.world,
      // cl45：相机 far 推到「LOD 地平线」——视距不再硬剔，LOD 远景大方块
      // 可越过视距延伸到 lodMaxChunks（看得更远、更流畅）。
      camera: _camera.copyWith(far: _renderFar()),
      viewport: Size(_viewport.width * rs, _viewport.height * rs),
      // R26x：贴图是否启用由画质档（GraphicsQuality.texture）经 [_configFor]
      // 决定（高清档启用，其余纯色）；图集本身恒构建以备切换。仅在此同步遮挡剔除。
      config: _config.copyWith(occlusionCull: _occlusionCull),
      timePhase: _time.phase,
      wavePhase: _wave,
      // R23w：AI 小人 + 僵尸 + 掉落物 + 玩家方块人一起交给渲染器。
      // R26o：玩家在 thirdPerson 下渲染自身模型（脚底=_fpPos）；firstPerson 不显示。
      entities: _buildEntities(),
      cache: _chunkCache,
      lights: widget.world.lightsNear(_camera.position.x, _camera.position.z),
      // cl30：allowMask 面级 LOD 持久化缓存（旋转时侧面面不 popping）。
      allowMaskCache: _allowMaskCache,
      allowMaskDotCache: _allowMaskDotCache,
    );
    sw.stop();
    // cl30：记录本次重建的机位/时相/分辨率，供增量门控判据。
    _lastBuildYaw = _camera.yaw;
    _lastBuildPitch = _camera.pitch;
    _lastBuildEyeX = _camera.position.x;
    _lastBuildEyeY = _camera.position.y;
    _lastBuildEyeZ = _camera.position.z;
    _lastBuildPhase = _time.phase;
    _lastBuildDynScale = _dynScale;
    _lastBuildAt = clNow;
    _lastChunkSerial = _chunkInvalidSerial;
    _firstBuild = false;
    _forceRebuild = false; // 已消费强制重建信号
    // R26r7：自适应分辨率——重建耗时 >13ms 连续 3 帧 → 降倍率（0.85×，下限 0.5）；
    // 持续 <6ms 30 帧 → 回升（1.1×，上限 1.0）。只影响分辨率，不动逻辑。
    final double buildMs = sw.elapsedMicroseconds / 1000.0;
    if (buildMs > 13) {
      _slowFrames++;
      _fastFrames = 0;
      if (_slowFrames >= 3 && _dynScale > 0.5) {
        _dynScale = math.max(0.5, _dynScale - 0.15);
        _slowFrames = 0;
        _dirty = true; // 下帧用新倍率重建
      }
    } else if (buildMs < 6 && _dynScale < 1.0) {
      _fastFrames++;
      _slowFrames = 0;
      if (_fastFrames >= 30) {
        _dynScale = math.min(1.0, _dynScale + 0.1);
        _fastFrames = 0;
        _dirty = true;
      }
    }
    } catch (e, st) {
      // R26r3：防御性渲染——单帧异常不得杀死 Ticker（否则视角永久冻住、画面
      // 停在残影）。放弃本帧并落盘日志，后续输入仍会置 dirty 重试。
      _dirty = false;
      unawaited(_logRenderError('_onTick', e, st));
    }
  }

  /// R26f：录制静态整帧快照（相机静止时），用于挂机/观景的 drawPicture。
  ui.Picture _recordStaticPicture(VoxelFrame frame) {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final Canvas cv = Canvas(rec);
    _VoxelFramePainter(
      frame,
      _quality.texture ? _atlas : null,
      renderScale: _quality.renderScale *
          ref.read(renderPrecisionScaleProvider) *
          _frameDynScale,
    ).paint(cv, _viewport);
    return rec.endRecording();
  }

  /// 小人平滑走向目标（指数逼近，帧率无关）。
  void _stepFigure(double dt) {
    final Vec3? target = _figureTarget;
    if (target == null) return;
    const double eps = 0.02;
    if ((target - _figurePos).length < eps) {
      _figurePos = target;
      _figureTarget = null;
      _syncEntityPositions();
      return;
    }
    final double k = 1 - math.exp(-dt * 3.0);
    _figurePos = Vec3(
      _figurePos.x + (target.x - _figurePos.x) * k,
      _figurePos.y + (target.y - _figurePos.y) * k,
      _figurePos.z + (target.z - _figurePos.z) * k,
    );
    _syncEntityPositions();
    _dirty = true;
  }

  /// 镜头平滑对准目标机位（位置 + yaw/pitch 指数逼近）。
  void _stepCamera(double dt) {
    final VoxelCamera? target = _cameraTarget;
    if (target == null) return;
    final double k = 1 - math.exp(-dt * 2.5);
    final Vec3 np = Vec3(
      _camera.position.x + (target.position.x - _camera.position.x) * k,
      _camera.position.y + (target.position.y - _camera.position.y) * k,
      _camera.position.z + (target.position.z - _camera.position.z) * k,
    );
    // yaw 走最短弧
    double dyaw = target.yaw - _camera.yaw;
    while (dyaw > math.pi) {
      dyaw -= 2 * math.pi;
    }
    while (dyaw < -math.pi) {
      dyaw += 2 * math.pi;
    }
    final double nyaw = _camera.yaw + dyaw * k;
    final double npitch =
        _camera.pitch + (target.pitch - _camera.pitch) * k;
    _camera = _camera.copyWith(position: np, yaw: nyaw, pitch: npitch);

    if ((target.position - np).length < 0.05 &&
        dyaw.abs() < 0.02 &&
        (target.pitch - npitch).abs() < 0.02) {
      _camera = target;
      _cameraTarget = null;
    }
    _dirty = true;
  }

  /// 用最新站位 / 发光态刷新实体列表（tick 移动小人时同步帧数据）。
  void _syncEntityPositions() {
    if (_companionEntities.isEmpty) return;
    _companionEntities = <VoxelEntity>[
      VoxelEntity(
        position: _figurePos,
        color: const Color(0xFF7CC8FF),
        scale: 1.0,
        glow: _figureGlow,
      ),
    ];
  }

  /// G9 cl67：按本地机位向主机请求周围编辑层快照（范围同步）。
  /// 仅客户端调用；记录的 [_lastSnapCx/_lastSnapCz] 用于「机位跨 chunk 时
  /// 重新拉取」去重，避免每 100ms 重复请求。
  void _requestSnapshotAroundMe() {
    if (!widget.multiplayer) return;
    if (ref.read(netSessionProvider).role != NetRole.client) return;
    final int cx = _fpPos.x ~/ VoxelWorld.kChunkSize;
    final int cz = _fpPos.z ~/ VoxelWorld.kChunkSize;
    _lastSnapCx = cx;
    _lastSnapCz = cz;
    ref.read(netSessionProvider.notifier).requestEditSnapshot(
          cx,
          cz,
          _kSnapRadiusCount,
        );
  }

  /// G9：上报自身机位 / 视角给会话层（~100ms 定时器调用）。
  void _broadcastMyTransform() {
    if (!widget.multiplayer) return;
    final Vec3 p = (_viewMode == _ViewMode.firstPerson ||
            _viewMode == _ViewMode.thirdPerson)
        ? _fpPos
        : _camera.position;
    // G9 cl67：机位跨 chunk 则重新拉取周围快照（游走加载/卸载——离开原范围
    // 后远端新区块的编辑按需补齐，先前范围外的编辑不再全量持有）。注意用
    // [_fpPos]（玩家脚底权威坐标）判定跨块，与 [_requestSnapshotAroundMe]
    // 一致，避免非第一人称模式下相机与 fpPos 不一致导致的重复请求。
    if (ref.read(netSessionProvider).role == NetRole.client) {
      final int cx = _fpPos.x ~/ VoxelWorld.kChunkSize;
      final int cz = _fpPos.z ~/ VoxelWorld.kChunkSize;
      if (cx != _lastSnapCx || cz != _lastSnapCz) {
        _requestSnapshotAroundMe();
      }
    }
    ref.read(netSessionProvider.notifier).broadcastTransform(
          p.x,
          p.y,
          p.z,
          _camera.yaw,
          _camera.pitch,
          _viewModeIndex,
        );
  }

  /// G9：本地视角模式 → 网络索引（与 [PeerInfo.viewMode] 对齐：
  /// 0=2.5D 等距 / 1=俯瞰 / 2=第一人称 / 3=第三人称）。
  int get _viewModeIndex {
    switch (_viewMode) {
      case _ViewMode.iso2d5:
        return 0;
      case _ViewMode.orbit:
        return 1;
      case _ViewMode.firstPerson:
        return 2;
      case _ViewMode.thirdPerson:
        return 3;
    }
  }

  /// G9：依 peer id 稳定取色（哈希 → 色相），多人互相区分。
  Color _peerColor(String id) {
    int h = 0;
    for (final int c in id.codeUnits) {
      h = (h * 31 + c) & 0xffffffff;
    }
    final double hue = (h % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.6).toColor();
  }

  /// 组装本帧实体列表：玩家方块人（#169）+ AI 小人 + 僵尸/掉落物。
  ///
  /// 玩家在 [orbit] / [thirdPerson] 下渲染（脚底=_fpPos；orbit 无第一人称位移，
  /// 用地表高度落位避免埋进地形）；[firstPerson] 沉浸视角不显示自身。
  List<VoxelEntity> _buildEntities() {
    // R26o：第三人称渲染**玩家自身模型**（纯色方块人，不用皮肤贴图——贴图
    // 图集在目标平台渲染黑，纯色安全）；第一人称沉浸不显示自身。
    final List<VoxelEntity> ents = <VoxelEntity>[];
    if (_viewMode == _ViewMode.thirdPerson) {
      ents.add(VoxelEntity(
        position: Vec3(_fpPos.x, _fpPos.y, _fpPos.z),
        color: const Color(0xFFC8A079), // 肤色（无皮肤纯色回退）
        scale: 1.0,
        swing: _walkSwing, // R26r11：走路摇摆
        // R26r14：模型朝向跟随相机——lookYaw 使躯干/四肢转向视线水平方向
        // （身体跟随头部），lookPitch 使头部俯仰跟随视线（头部跟随视线）。
        lookYaw: _camera.yaw,
        lookPitch: _camera.pitch,
        // R26r12：加载了 MC 皮肤（VoxelTextureAtlas.hasSkin）时贴到玩家模型；
        // 未加载时回退纯色，无副作用。
        useSkin: true,
      ));
    }
    if (_companionEntities.isNotEmpty) ents.addAll(_companionEntities);
    if (!_mobs.isEmpty) ents.addAll(_mobs.toEntities());
    // G9：联机远端玩家——始终渲染为彩色方块人（本地第一人称不显示自身，
    // 但其他玩家应可见彼此；依 id 稳定取色区分多人）。
    for (final PeerInfo peer in _remotePlayers.values) {
      if (peer.x == null || peer.y == null || peer.z == null) continue;
      ents.add(VoxelEntity(
        position: Vec3(peer.x!, peer.y!, peer.z!),
        color: _peerColor(peer.id),
        scale: 1.0,
        lookYaw: peer.yaw,
        lookPitch: peer.pitch,
        label: peer.name, // G9：头顶名字标签
      ));
    }
    return ents;
  }

  void _applyNav(double dt) {
    final double step = _moveSpeed * dt;
    double forward = 0;
    double strafe = 0;
    double lift = 0;
    if (_held.contains(_Nav.forward)) forward += step;
    if (_held.contains(_Nav.back)) forward -= step;
    if (_held.contains(_Nav.right)) strafe += step;
    if (_held.contains(_Nav.left)) strafe -= step;
    if (_held.contains(_Nav.up)) lift += step;
    if (_held.contains(_Nav.down)) lift -= step;
    _camera = _camera.move(
      forward: forward,
      strafe: strafe,
      lift: lift,
      world: widget.world,
    );
    // R23m：俯瞰 / 2.5D 相机也带碰撞箱——穿进实心方块时抬出，防视角穿模。
    _camera = _camera.copyWith(position: _cameraPushOut(_camera.position));
    _dirty = true;
  }

  /// 相机碰撞箱（R23m）：相机不允许待在实心方块内部。
  /// 穿模时把相机抬到所在列块顶上方（保留 x/z，最小位移）。
  Vec3 _cameraPushOut(Vec3 pos) {
    final VoxelWorld w = widget.world;
    final int y = pos.y.floor();
    if (y < 0) return Vec3(pos.x, 0.6, pos.z);
    final int x = pos.x.floor();
    final int z = pos.z.floor();
    if (w.get(x, y, z).occludes) {
      return Vec3(pos.x, y + 1.0 + 0.25, pos.z);
    }
    return pos;
  }

  /// 第三人称相机位：玩家身后 [ _tpCamDist] 格、上方 [_tpCamPitch] 角
  /// （默认 ≈ 身后 4 格、上方 2.5 格，跟随玩家朝向）。
  ///
  /// R23m：相机带碰撞箱——从玩家位置沿视线方向步进，遇到实心方块
  /// 就把相机**拉近到阻挡前一格**（MC 式第三人称防穿墙），并兜底抬出。
  /// R26o：yaw/pitch/dist 由第三人称「环绕」摇杆调节，可一键复原。
  Vec3 _thirdPersonPos() {
    final double yaw = _camera.yaw + _tpCamYaw;
    final double cp = math.cos(_tpCamPitch);
    final double sp = math.sin(_tpCamPitch);
    final double dist = math.max(1.0, _tpCamDist);
    final Vec3 from = Vec3(_fpPos.x, _fpPos.y + 1.6, _fpPos.z);
    final Vec3 target = Vec3(
      from.x - math.sin(yaw) * cp * dist,
      from.y + sp * dist,
      from.z - math.cos(yaw) * cp * dist,
    );
    final VoxelWorld w = widget.world;
    final double dx = (target.x - from.x) / dist;
    final double dy = (target.y - from.y) / dist;
    final double dz = (target.z - from.z) / dist;
    Vec3 cam = target;
    for (double t = 0.2; t <= dist; t += 0.2) {
      final Vec3 p =
          Vec3(from.x + dx * t, from.y + dy * t, from.z + dz * t);
      final int y = p.y.floor();
      if (y >= 0 && y < w.maxY && w.get(p.x.floor(), y, p.z.floor()).occludes) {
        final double t2 = (t - 0.2).clamp(0.0, dist);
        cam = Vec3(from.x + dx * t2, from.y + dy * t2, from.z + dz * t2);
        break;
      }
    }
    return _cameraPushOut(cam);
  }

  /// 第一人称走位 + 物理（R23f：方块碰撞 / 蹲 / 创造也有下落 / 防穿模）。
  ///
  /// - 水平：逐轴移动 + 包围盒碰撞（撞墙该轴不动，可沿墙滑动）；
  /// - 垂直：**生存与创造都受重力**（创造按住 Q/E 升降对抗重力）；
  ///   上升逐级检测头顶碰撞（跳跃顶到方块即停，防穿模）；
  /// - 蹲（Shift / D-pad 下）：眼高 1.6→0.9、碰撞箱 1.8→1.05、移速减半；
  /// - 生存：摔落伤害 + 落水减速浮力；创造：无伤。
  void _applyNavFP(double dt) {
    final VoxelWorld w = widget.world;
    final bool crouch = _crouching;
    // cl28：对齐 MC 速度基准（行走 4.317 / 冲刺 5.612 方块/秒）。
    // 疾跑倍率 1.2→1.3（4.3×1.3≈5.59≈MC 冲刺）；蹲 0.4（4.3×0.4≈1.72≈MC 潜行）。
    // R26r16：创造飞行提速（对齐 MC——飞行明显快于走路，Ctrl 冲刺飞更快）。
    // 该倍率同时作用于水平位移与升降 lift（两者都由 step 派生）。
    final double flyMul =
        (!_survival && _flyMode) ? (_sprinting ? 3.5 : 2.2) : 1.0;
    final double speedMul =
        (crouch ? 0.4 : (_sprinting ? 1.3 : 1.0)) * flyMul;
    final double step = _moveSpeed * speedMul * dt;
    final double eyeH = crouch ? 0.9 : VoxelCamera.eyeHeight;
    final double bodyH = crouch ? 1.05 : 1.75;

    double forward = 0;
    double strafe = 0;
    if (_held.contains(_Nav.forward)) forward += 1;
    if (_held.contains(_Nav.back)) forward -= 1;
    if (_held.contains(_Nav.right)) strafe += 1;
    if (_held.contains(_Nav.left)) strafe -= 1;
    // R24c：虚拟摇杆（上 = -dy = 前进）。与键盘叠加，并限幅避免斜向超速。
    forward += -_joyY.clamp(-1.0, 1.0);
    strafe += _joyX.clamp(-1.0, 1.0);
    final double mag = math.sqrt(forward * forward + strafe * strafe);
    if (mag > 1) {
      forward /= mag;
      strafe /= mag;
    }
    final double sy = math.sin(_camera.yaw);
    final double cy = math.cos(_camera.yaw);

    // 创造模式飞行升降（Q/E；生存忽略）。
    // R26r17：下降比上升快（×1.8）——带重力直觉，下落更利落（MC 手感里
    // 上升慢、下降快）。上升保持原 step，下降单独加倍率。
    // R26r20：飞行 = 创造专属**许可**——只有 _flyMode 才读取升降键（未飞行时
    // 上=跳、下=蹲，不再直接位移）。
    const double kDescendMul = 1.8;
    double lift = 0;
    if (!_survival && _flyMode) {
      if (_held.contains(_Nav.up)) lift += step;
      if (_held.contains(_Nav.down)) lift -= step * kDescendMul;
    }

    // ── 水平：逐轴移动 + 碰撞（滑动）──
    // R23k：无限地图——不再 clamp 到出生大陆边界（删空气墙），
    // 只留一个超大软边界兜底（±1e6，实际到不了）。
    final double dx = (sy * forward + cy * strafe) * step;
    final double dz = (cy * forward - sy * strafe) * step;
    // R26r11：走路摇摆——按水平位移推进相位（走得越快摆得越快），静止归零。
    final double hDist = math.sqrt(dx * dx + dz * dz);
    final bool moving = hDist > 0.001;
    if (moving) _walkPhase += hDist * 9.0;
    final double targetSwing = moving ? math.sin(_walkPhase) * 0.7 : 0.0;
    _walkSwing += (targetSwing - _walkSwing) * (moving ? 0.5 : 0.25);
    final double baseY = _fpPos.y + lift;
    const double limit = 1000000.0;
    final double desiredX = (_fpPos.x + dx).clamp(-limit, limit);
    final double desiredZ = (_fpPos.z + dz).clamp(-limit, limit);
    bool blockedX = false;
    bool blockedZ = false;
    // R26c：蹲下时「边缘不掉落」——目标格脚下无支撑（悬空）则不让走，
    // 可安全停在方块边缘观察/看风景而不失足。
    // R26r7：跳跃中（空中）允许「跨 1 格台阶」——水平被台阶挡时，若抬高
    // 1 格后身体能通过则放行（竖直方向正被跳跃抬升，落地即踏上台阶）。
    final bool crouchGuard = crouch;
    // H3：1 格台阶自动上步收敛为 MC 式 step-up（baseY → +1 找可行）；
    // 蹲守边缘时抬高后脚下无支撑则拒绝（修 H3 bug1：原 assistStep 绕过蹲守）。
    if ((!_bodyCollides(desiredX, baseY, _fpPos.z, bodyH) &&
            (!crouchGuard || _hasSupport(desiredX, _fpPos.z))) ||
        _stepUpOk(desiredX, baseY, _fpPos.z, bodyH, crouchGuard)) {
      _fpPos = Vec3(desiredX, _fpPos.y, _fpPos.z);
    } else {
      blockedX = true;
    }
    if ((!_bodyCollides(_fpPos.x, baseY, desiredZ, bodyH) &&
            (!crouchGuard || _hasSupport(_fpPos.x, desiredZ))) ||
        _stepUpOk(_fpPos.x, baseY, desiredZ, bodyH, crouchGuard)) {
      _fpPos = Vec3(_fpPos.x, _fpPos.y, desiredZ);
    } else {
      blockedZ = true;
    }

    // ── R24 自动跳跃（默认关闭）：水平撞到 1 格台阶时自动抬升迈过 ──
    // 关闭（默认）则撞墙只是贴墙滑动，不会自动跳。
    if (_autoJump && !_crouching && (blockedX || blockedZ)) {
      final double stepY = _fpPos.y + 1.0;
      if (!_bodyCollides(_fpPos.x, stepY, _fpPos.z, bodyH) &&
          !_bodyCollides(desiredX, stepY, _fpPos.z, bodyH) &&
          !_bodyCollides(_fpPos.x, stepY, desiredZ, bodyH) &&
          !_bodyCollides(desiredX, stepY, desiredZ, bodyH)) {
        _fpPos = Vec3(desiredX, stepY, desiredZ);
        _fpOnGround = false;
      }
    }

    // cl28 无浮力水物理：仅判身体是否泡水（_bodyInWater）；不再算泡水比例，
    // 浮力被移除——水中恒定弱下坠（缓沉），按住跳跃才上浮（见下方分支）。
    final bool inWater = _bodyInWater();

    // ── 垂直：统一重力（生存+创造），创造 Q/E 升降对抗重力 ──
    double ny;
    if (_survival) {
      // cl28：水中按跳跃 = 上浮冲量（不限于落地；配合下方按住跳跃持续上浮）。
      if (_fpJumpQueued && (_fpOnGround || inWater)) {
        _fpVy = inWater
            ? 4.0
            : math.sqrt(
                2 * VoxelCamera.gravity * VoxelCamera.jumpHeight,
              );
        _fpOnGround = false;
      }
      _fpJumpQueued = false;
      if (inWater) {
        // cl28 无浮力水物理：移除 H3 浮力（净加速度不再为正）；改为恒定弱下坠
        //（缓慢下沉），按住跳跃 = 持续上浮加速，对齐「水改无浮力、慢慢下降、
        // 必须按跳跃上浮」。
        if (_jumpHeld) {
          _fpVy += VoxelCamera.gravity * 0.55 * dt; // 上浮加速
          if (_fpVy > 3.5) _fpVy = 3.5; // 上浮限速
        } else {
          _fpVy -= VoxelCamera.gravity * 0.18 * dt; // 缓沉
          if (_fpVy < -2.0) _fpVy = -2.0; // 缓沉限速
        }
      } else {
        _fpVy -= VoxelCamera.gravity * dt;
        if (_fpVy < -50) _fpVy = -50; // 全局下落限速（防大 dt 穿地）
      }
      ny = _fpPos.y + _fpVy * dt;
    } else {
      // 创造：单击跳跃（落地才跳；双击已由 _onJumpInput 切换飞行）。
      // R26r20：与生存**同一**跳跃公式 + 同一重力（含水中提速/限速）——修复
      // 「创造跳得比生存高」（旧 0.9× 重力使创造跳高 ~11%）。
      if (_fpJumpQueued && _fpOnGround) {
        _fpVy = inWater
            ? 4.0
            : math.sqrt(2 * VoxelCamera.gravity * VoxelCamera.jumpHeight);
        _fpOnGround = false;
      }
      _fpJumpQueued = false;
      if (_flyMode) {
        // R26p-camera：创造飞行——无重力，保持当前高度；升降键控制 altitude。
        _fpVy = 0;
        ny = _fpPos.y + lift;
      } else {
        // 创造未飞行：与生存同重力下落（统一跳跃高度；不再 0.9×）。
        if (inWater) {
          // cl28：与生存同一无浮力水物理（按住跳跃上浮 / 否则缓沉）。
          if (_jumpHeld) {
            _fpVy += VoxelCamera.gravity * 0.55 * dt;
            if (_fpVy > 3.5) _fpVy = 3.5;
          } else {
            _fpVy -= VoxelCamera.gravity * 0.18 * dt;
            if (_fpVy < -2.0) _fpVy = -2.0;
          }
        } else {
          _fpVy -= VoxelCamera.gravity * dt;
          if (_fpVy < -50) _fpVy = -50;
        }
        ny = _fpPos.y + _fpVy * dt;
      }
    }

    // ── 垂直碰撞：上升检测（跳跃顶到方块即停，防穿模）──
    // H3：去 0.2 量化——目标高度整段 AABB 检测，无碰撞直接取完整 ny（飞行/
    // 跳跃平滑）；有碰撞再从起点向上 0.05 细扫找最后可行点（平滑顶头停）。
    if (ny > _fpPos.y) {
      if (!_bodyCollides(_fpPos.x, ny, _fpPos.z, bodyH)) {
        // 整段无碰撞 → 直接用
      } else {
        double top = _fpPos.y;
        for (double yy = _fpPos.y + 0.05; yy <= ny + 1e-6; yy += 0.05) {
          if (_bodyCollides(_fpPos.x, yy, _fpPos.z, bodyH)) break;
          top = yy;
        }
        ny = top;
        if (ny <= _fpPos.y + 1e-9) {
          ny = _fpPos.y;
          _fpVy = 0; // 顶头停住
        }
      }
    }

    // ── 落地（生存+创造都落地）──
    // R26r5：边缘容差——原本站在地上、脚下 4 角任一仍有支撑 → 不下落
    // （身体最多可探出 0.6 碰撞箱的 75%）；全悬空才掉。
    // R26r6：从脚底往下扫地面——树叶实体化后，不限起始高度会被头顶树冠
    // 误判成"脚下的地"（旧 R26n「被顶到树顶」的根因）。
    double ground =
        VoxelCamera.groundHeightAt(w, _fpPos.x, _fpPos.z, _fpPos.y + 0.5);
    if (_fpOnGround) {
      final double cornerH = _cornerSupportHeight();
      if (cornerH > ground) ground = cornerH;
    }
    if (ny <= ground) {
      if (_survival && _fpVy < -12) {
        final int dmg = ((_fpVy.abs() - 12) * 1.2).round().clamp(1, 12);
        _damage(dmg);
      }
      ny = ground;
      _fpVy = 0;
      _fpOnGround = true;
      // R26r16：飞行中**主动下降**触地 → 自动退出飞行（对齐 MC）。只在 lift < 0
      // 时取消：从地面双击起飞那一帧 lift >= 0，不会被立刻打断。
      // R26fix：落地即退出飞行（未按住上升时），并清空升降键残留 + 双击计时，
      // 治「按飞行后落地，下一次跳不起来也飞不了」的卡死状态。
      if (_flyMode && !_held.contains(_Nav.up)) {
        _flyMode = false;
        _held.remove(_Nav.up);
        _held.remove(_Nav.down);
        _lastJumpPress = null;
        _fpJumpQueued = false;
      }
    }

    // ── 重叠推出兜底（R23g + R26r8）：若玩家仍与方块重叠（放置卡身 / 地形
    // 突变卡进方块 / 任何漏网穿模），把脚底抬到方块顶，杜绝"穿到上面"。
    // R26r8：改为检查整个 0.6 足迹的 4 角列（原只查中心列——半身探进墙里时
    // 中心列是空气 → 检测不到 → 卡在方块里）。
    _fpPos = Vec3(_fpPos.x, ny, _fpPos.z);
    // R26r14：长方体碰撞箱兜底推出——若玩家 AABB 仍与任何实心方块相交，
    // 沿「最小平移向量（MTV）」推出，上/下/左/右/前/后任意方向皆可，直至完全
    // 不相交（保证「不可相交」）。地基每帧水平/竖直已分轴解算，此处只兜底
    // 漏网（放置卡身 / 地形突变 / 顶头落块）；被向上推出→悬空，落地分支随即
    // 置 _fpOnGround，跳跃/飞行恢复。
    const double pr = 0.3; // 玩家半宽（与 _bodyCollides 一致）
    _fpPos = Vec3(_fpPos.x, ny, _fpPos.z);
    for (int guard = 0; guard < 6; guard++) {
      double bestMag = double.infinity;
      double ox = 0, oy = 0, oz = 0;
      bool any = false;
      final int xi0 = (_fpPos.x - pr).floor();
      final int xi1 = (_fpPos.x + pr).floor();
      final int zi0 = (_fpPos.z - pr).floor();
      final int zi1 = (_fpPos.z + pr).floor();
      final int yi0 = _fpPos.y.floor();
      final int yi1 = (_fpPos.y + bodyH).floor();
      for (int xi = xi0; xi <= xi1; xi++) {
        if (xi < 0 || xi >= w.sizeX) continue;
        for (int zi = zi0; zi <= zi1; zi++) {
          if (zi < 0 || zi >= w.sizeZ) continue;
          for (int yi = yi0; yi <= yi1; yi++) {
            if (yi < 0 || yi >= w.maxY) continue;
            if (!w.get(xi, yi, zi).occludes) continue;
            any = true;
            // 该方块 AABB [xi,xi+1]×[yi,yi+1]×[zi,zi+1] 与玩家盒各轴最小推出量。
            final double penXp = (xi + 1) - (_fpPos.x - pr); // 沿 +X
            final double penXn = (_fpPos.x + pr) - xi; // 沿 -X
            final double penYp = (yi + 1) - _fpPos.y; // 沿 +Y（上）
            final double penYn = (_fpPos.y + bodyH) - yi; // 沿 -Y（下）
            final double penZp = (zi + 1) - (_fpPos.z - pr); // 沿 +Z
            final double penZn = (_fpPos.z + pr) - zi; // 沿 -Z
            final double penX = math.min(penXp, penXn);
            final double penY = math.min(penYp, penYn);
            final double penZ = math.min(penZp, penZn);
            double px = 0, py = 0, pz = 0;
            final double penMin = math.min(penX, math.min(penY, penZ));
            // H3：近等轴时偏好向上（penY ≤ min×1.2）——地形突变/生成卡进
            // 方块时优先把玩家抬出（避免被横向挤向悬崖/侧墙）。
            if (penY <= penMin * 1.2 && penY > 0) {
              py = penYp <= penYn ? penYp : -penYn;
            } else if (penX <= penY && penX <= penZ) {
              px = penXp <= penXn ? penXp : -penXn;
            } else if (penZ <= penY) {
              pz = penZp <= penZn ? penZp : -penZn;
            } else {
              py = penYp <= penYn ? penYp : -penYn;
            }
            final double mag = px.abs() + py.abs() + pz.abs();
            if (mag < bestMag) {
              bestMag = mag;
              ox = px;
              oy = py;
              oz = pz;
            }
          }
        }
      }
      if (!any) break;
      _fpPos = Vec3(_fpPos.x + ox, _fpPos.y + oy, _fpPos.z + oz);
      if (oy > 0) {
        _fpOnGround = false; // 被向上顶出 → 悬空，下一帧重力继续
        _fpVy = 0;
      } else if (oy < 0) {
        _fpVy = 0; // 头顶被压下 → 停住冲量
      }
    }
    ny = _fpPos.y;

    // R26r5：视角 Y 缓冲——目标高度每帧指数趋近（跳跃 / 蹲下 / 升降不硬切；
    // X/Z 仍即时跟随，水平移动不拖沓）。
    final Vec3 rawCam = _viewMode == _ViewMode.thirdPerson
        ? _thirdPersonPos()
        : Vec3(_fpPos.x, ny + eyeH, _fpPos.z);
    if (!_eyeSmoothInit) {
      _eyeSmoothY = rawCam.y;
      _eyeSmoothInit = true;
    } else {
      _eyeSmoothY +=
          (rawCam.y - _eyeSmoothY) * (1 - math.exp(-dt * _eyeSmoothK));
    }
    _camera = _camera.copyWith(
      position: Vec3(rawCam.x, _eyeSmoothY, rawCam.z),
    );
    _dirty = true;
  }

  /// 玩家包围盒（0.6 宽 × [bodyH] 高）与实心方块是否碰撞（水/叶不挡）。
  ///
  /// R26p：原实现只测玩家**中心那一列**（半径 0），0.6 宽身体会直接插进墙里。
  /// 改为测整个足迹 AABB——覆盖 [x-r, x+r] × [z-r, z+r] 内所有列，杜绝穿模，
  /// 同时保留逐轴移动时的「贴墙滑动」。r=0.3 即 0.6 宽的一半。
  bool _bodyCollides(double x, double y, double z, [double bodyH = 1.75]) {
    final VoxelWorld w = widget.world;
    const double r = 0.3; // 玩家半宽（0.6 宽），贴墙不穿模
    final int xMin = (x - r).floor();
    final int xMax = (x + r).floor();
    final int zMin = (z - r).floor();
    final int zMax = (z + r).floor();
    final int yTop = (y + bodyH).floor();
    for (int yy = y.floor(); yy <= yTop; yy++) {
      if (yy < 0) continue;
      if (yy >= w.maxY) return true;
      for (int xi = xMin; xi <= xMax; xi++) {
        for (int zi = zMin; zi <= zMax; zi++) {
          if (w.get(xi, yy, zi).occludes) return true;
        }
      }
    }
    return false;
  }

  /// R26c 蹲下边缘保护：位置 (x, z) 的脚下（脚底下方一格）是否有支撑方块。
  /// R26r5：改为 4 角任一侧支撑即算（允许探出碰撞箱最多 75%）；蹲下移动时
  /// 目标格无支撑则不让走（MC 式「边缘蹲守不掉落」）。
  bool _hasSupport(double x, double z) {
    final VoxelWorld w = widget.world;
    final int y = (_fpPos.y - 0.1).floor();
    if (y < 0) return true;
    if (y >= w.maxY) return false;
    for (final double cx in <double>[x - 0.3, x + 0.3]) {
      for (final double cz in <double>[z - 0.3, z + 0.3]) {
        if (w.get(cx.floor(), y, cz.floor()).occludes) return true;
      }
    }
    return false;
  }

  /// R26r5：脚下 4 角支撑高度。任一角「不高于脚底」的列顶即视为支撑，
  /// 返回最高支撑高度；全悬空返回 -∞。用于落地边缘容差（最多探出 75%）。
  /// R26r6：同样从脚底往下扫（树叶实体化后树冠不算"脚下的支撑"）。
  double _cornerSupportHeight() {
    final VoxelWorld w = widget.world;
    double best = double.negativeInfinity;
    for (final double cx in <double>[_fpPos.x - 0.3, _fpPos.x + 0.3]) {
      for (final double cz in <double>[_fpPos.z - 0.3, _fpPos.z + 0.3]) {
        final double g =
            VoxelCamera.groundHeightAt(w, cx, cz, _fpPos.y + 0.5);
        if (g <= _fpPos.y + 0.02 && g > best) best = g;
      }
    }
    return best;
  }

  /// H3：身体 AABB（0.6 宽 × 站立高）是否泡水——任一格是水即算（不再只看脚）。
  bool _bodyInWater() {
    final VoxelWorld w = widget.world;
    const double r = 0.3;
    final int xMin = (_fpPos.x - r).floor();
    final int xMax = (_fpPos.x + r).floor();
    final int zMin = (_fpPos.z - r).floor();
    final int zMax = (_fpPos.z + r).floor();
    final int yTop = (_fpPos.y + 1.75).floor();
    for (int yy = _fpPos.y.floor(); yy <= yTop; yy++) {
      for (int xi = xMin; xi <= xMax; xi++) {
        for (int zi = zMin; zi <= zMax; zi++) {
          if (w.get(xi, yy, zi) == Voxel.water) return true;
        }
      }
    }
    return false;
  }

  /// cl28：眼睛是否没入水中（仅头顶附近一格，供氧气判定；区别于全身泡水）。
  /// 身体任一格是水即算"泡水"，但氧气只关心眼睛（视角）是否在水下。
  bool _headInWater() {
    final VoxelWorld w = widget.world;
    const double r = 0.3;
    final int xMin = (_fpPos.x - r).floor();
    final int xMax = (_fpPos.x + r).floor();
    final int zMin = (_fpPos.z - r).floor();
    final int zMax = (_fpPos.z + r).floor();
    final double eyeY = _fpPos.y + VoxelCamera.eyeHeight;
    final int y0 = eyeY.floor();
    final int y1 = (eyeY + 0.2).floor();
    for (int yy = y0; yy <= y1; yy++) {
      for (int xi = xMin; xi <= xMax; xi++) {
        for (int zi = zMin; zi <= zMax; zi++) {
          if (w.get(xi, yy, zi) == Voxel.water) return true;
        }
      }
    }
    return false;
  }

  /// H3：身体泡水比例（0~1，浮力强度依据；站立高 1.75 的足迹采样）。
  double _bodyWaterRatio() {
    final VoxelWorld w = widget.world;
    const double r = 0.3;
    int total = 0, wet = 0;
    final int xMin = (_fpPos.x - r).floor();
    final int xMax = (_fpPos.x + r).floor();
    final int zMin = (_fpPos.z - r).floor();
    final int zMax = (_fpPos.z + r).floor();
    final int yTop = (_fpPos.y + 1.75).floor();
    for (int yy = _fpPos.y.floor(); yy <= yTop; yy++) {
      for (int xi = xMin; xi <= xMax; xi++) {
        for (int zi = zMin; zi <= zMax; zi++) {
          total++;
          if (w.get(xi, yy, zi) == Voxel.water) wet++;
        }
      }
    }
    return total == 0 ? 0 : wet / total;
  }

  /// H3：MC 式 1 格台阶 step-up——baseY → +1 抬高后身体可通行即放行；
  /// 蹲守边缘（crouch）时抬高后脚下无支撑则拒绝（不绕过边缘保护）。
  bool _stepUpOk(double x, double y, double z, double bodyH, bool crouch) {
    final double stepY = y + 1.0;
    if (_bodyCollides(x, stepY, z, bodyH)) return false;
    if (crouch && !_hasSupport(x, z)) return false;
    return true;
  }

  /// 扣血（仅生存）；生命归零 → 传回世界中心重生。
  void _damage(int dmg) {
    if (!_survival) return;
    _vitals.damage(dmg);
    if (_vitals.isDead) _respawn();
  }

  void _respawn() {
    final double cx = widget.world.sizeX / 2;
    final double cz = widget.world.sizeZ / 2;
    _fpPos = Vec3(
      cx,
      VoxelCamera.groundHeightAt(widget.world, cx, cz),
      cz,
    );
    _fpVy = 0;
    _fpOnGround = true;
    _vitals.respawn();
    _eyeSmoothInit = false; // 重生传送 → 视角 Y 缓冲重置（不跨图平滑）
    // cl28：重生清空氧气与溺水节拍（避免带着 0 氧复活即死）。
    _oxygen = 1.0;
    _drownTimer = 0.0;
    _oxygenNotifier.value = 1.0;
    // 死亡清场：附近的僵尸不跟着重生点刷屏。
    _mobs.zombies.clear();
  }

  /// cl28：氧气消耗 / 恢复 + 溺水伤害（仅生存）。眼睛没入水中 → 按 dt 扣氧
  ///（~15 秒耗尽）；出水 → 按 dt 回氧（~5 秒满）；耗尽 → 每 0.5s 扣 1 点生命。
  void _tickOxygen(double dt) {
    if (_headInWater()) {
      _oxygen -= dt / 15.0; // ~15 秒耗尽
      if (_oxygen < 0) _oxygen = 0;
      _drownTimer += dt;
      if (_oxygen <= 0 && _drownTimer >= 0.5) {
        _drownTimer = 0;
        _damage(1); // 溺水：每 0.5 秒 1 点
      }
    } else {
      _oxygen += dt / 5.0; // 出水 5 秒回满
      if (_oxygen > 1) _oxygen = 1;
      _drownTimer = 0;
    }
    if (_oxygenNotifier.value != _oxygen) _oxygenNotifier.value = _oxygen;
  }

  // ── R23w 玩法推进（生存 / 生物 / 掉落物 / 挖掘）────────

  /// 玩家当前位置（第一/三人称用脚底，其余用相机）。
  Vec3 get _playerPos =>
      (_viewMode == _ViewMode.firstPerson ||
              _viewMode == _ViewMode.thirdPerson)
          ? _fpPos
          : _camera.position;

  void _tickGameplay(double dt) {
    final bool fp = _viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson;
    final Vec3 p = _playerPos;

    // 疲劳：按水平位移累积（只在生存模式消耗饥饿）。
    final double mdx = p.x - _lastPx;
    final double mdz = p.z - _lastPz;
    _lastPx = p.x;
    _lastPz = p.z;
    if (_survival && fp) {
      _vitals.tick(dt, moved: math.sqrt(mdx * mdx + mdz * mdz));
      // 生命变化由 VoxelVitalsHud 自行监听 _vitals 重绘。
    }

    if (_attackCd > 0) _attackCd -= dt;

    // 僵尸 + 掉落物（R26f：降频 ~8Hz 累计，每帧 tick 是大头 CPU）。
    _mobTickAcc += dt;
    if (_mobTickAcc >= 0.12) {
      final double mdt = _mobTickAcc;
      _mobTickAcc = 0;
      final int before = _mobs.zombies.length + _mobs.items.length;
      _mobs.tick(
        mdt,
        playerPos: p,
        isNight: _time.isNight,
        survival: _survival && fp,
        onHitPlayer: _damage,
      );
      if (before > 0 || _mobs.zombies.isNotEmpty || _mobs.items.isNotEmpty) {
        _dirty = true;
      }
    }
    // R26r10：掉落物独立高频 tick（~30Hz）——下落/浮动/拾取跟手（僵尸仍 8Hz）。
    _dropTickAcc += dt;
    if (_dropTickAcc >= 0.03 && _mobs.items.isNotEmpty) {
      _dropTickAcc = 0;
      _mobs.tickItemsOnly(
        0.03,
        p,
        (ItemStack s) => _inv.add(s) == 0,
      );
      _dirty = true;
    }

    _tickMining(dt, fp);
  }

  /// 长按挖掘：按方块硬度 / 工具倍率累积进度，满了才破坏。
  void _tickMining(double dt, bool fp) {
    if (!_acting || !fp || _cameraMode || _bagOpen || _downMoved) {
      _resetMining();
      return;
    }
    final ((int, int, int), (int, int, int))? h = _raycast();
    if (h == null) {
      _resetMining();
      return;
    }
    final (int, int, int) hit = h.$1;
    if (_miningAt != hit) {
      _miningAt = hit;
      _miningTime = 0;
      final Voxel v = widget.world.get(hit.$1, hit.$2, hit.$3);
      // 创造模式秒破 → R26r7 限制为 0.5s 一块；生存按硬度/工具算时间。
      _miningNeed = _survival ? breakSeconds(v, _inv.tool) : 0.5;
      if (_miningNeed < 0) {
        // 不可破坏（空气 / 水）。
        _miningAt = null;
        return;
      }
    }
    _miningTime += dt;
    final double p = _miningNeed <= 0
        ? 1.0
        : (_miningTime / _miningNeed).clamp(0.0, 1.0);
    if ((_crackNotifier.value - p).abs() > 0.01 || p >= 1) {
      _crackNotifier.value = p;
    }
    if (p >= 1) {
      _breakBlock(hit);
      _resetMining();
    }
  }

  void _resetMining() {
    if (_miningAt == null && _crackNotifier.value == 0) return;
    _miningAt = null;
    _miningTime = 0;
    _crackNotifier.value = 0;
  }

  /// 真正破坏一个方块：掉落物 + 经验 + 音效 + 缓存失效。
  void _breakBlock((int, int, int) hit) {
    final VoxelWorld w = widget.world;
    final Voxel broken = w.get(hit.$1, hit.$2, hit.$3);
    if (broken == Voxel.air || broken == Voxel.water) return;
    // R26r7：创造模式破坏冷却 0.5s 一块（点击与长按统一限速）。
    if (!_survival) {
      final DateTime now = DateTime.now();
      if (_lastBreakAt != null &&
          now.difference(_lastBreakAt!).inMilliseconds < 500) {
        return;
      }
      _lastBreakAt = now;
    }
    w.setVoxel(hit.$1, hit.$2, hit.$3, Voxel.air);
    if (widget.multiplayer) {
      ref.read(netSessionProvider.notifier).broadcastEdit(
        hit.$1, hit.$2, hit.$3, Voxel.values.indexOf(Voxel.air),
      );
    }
    _invalidateChunkAt(hit.$1, hit.$3);
    // G4（用户确认「海洋水不会流动」）：破坏方块后，若 4 邻或下方有**任何水**
    // （含海洋/河流天然水），登记该水为水源 → 20tps 扩散流入空腔（MC 海水会
    // 流入挖开的坑）。仅当破的是「与水体相邻」的方块时触发，避免无谓扩散。
    for (final (int dx, int dy, int dz) in const <(int, int, int)>[
      (1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1), (0, -1, 0),
    ]) {
      final int nx = hit.$1 + dx, ny = hit.$2 + dy, nz = hit.$3 + dz;
      if (w.get(nx, ny, nz) == Voxel.water) {
        w.addWaterSource(nx, ny, nz);
        break;
      }
    }
    _staticPicture = null; // R26f：地形编辑 → 静态快照失效
    unawaited(ref.read(minecraftSfxServiceProvider).playBlockSound(broken));
    if (_survival) {
      if (canHarvest(broken, _inv.tool)) {
        _mobs.spawnDrops(hit.$1, hit.$2, hit.$3, dropsOf(broken));
      }
      final int gain = xpOnBreak(broken);
      if (gain > 0) _vitals.addXp(gain);
    } else {
      // 创造：直接进包，方便接着搭。
      _inv.add(ItemStack(broken));
    }
    _brokeInHold = true;
    _dirty = true;
  }

  /// 攻击准星方向最近的僵尸；返回是否命中（供合并键先攻后挖）。
  bool _tryAttack() {
    if (!_survival || _attackCd > 0 || _mobs.zombies.isEmpty) return false;
    final Vec3 from = Vec3(
      _fpPos.x,
      _fpPos.y + (_crouching ? 1.15 : 1.62),
      _fpPos.z,
    );
    if (_mobs.hitNearest(
      from,
      _camera.forwardVector(),
      damage: 4 + _inv.tool.tier.level,
    )) {
      _attackCd = 0.45;
      _dirty = true;
      return true;
    }
    return false;
  }

  /// 附近是否有可当工作台用的方块（箱子 / 熔炉，半径 4 格）。
  bool get _hasTable {
    final VoxelWorld w = widget.world;
    final Vec3 p = _playerPos;
    final int px = p.x.floor();
    final int py = p.y.floor();
    final int pz = p.z.floor();
    for (int dx = -4; dx <= 4; dx++) {
      for (int dy = -2; dy <= 2; dy++) {
        for (int dz = -4; dz <= 4; dz++) {
          final Voxel v = w.get(px + dx, py + dy, pz + dz);
          if (v == Voxel.chest || v == Voxel.furnace) return true;
        }
      }
    }
    return false;
  }

  /// 合成（材料够才扣、产物装不下就退回）。
  void _craft(CraftRecipe r) {
    final Map<Voxel, int> have = <Voxel, int>{};
    for (final ItemStack s in _inv.slots) {
      if (s.isEmpty) continue;
      have[s.item] = (have[s.item] ?? 0) + s.count;
    }
    if (!Crafting.canCraft(r, have, hasTable: _hasTable)) return;
    for (final MapEntry<Voxel, int> e in r.inputs.entries) {
      _inv.take(e.key, e.value);
    }
    final int left = _inv.add(Crafting.outputOf(r));
    if (left > 0 && mounted) {
      // D（用户确认）：所有通知统一走全局右上角弹条，不再用底部 SnackBar。
      _snack('背包放不下 $left 个${itemNameOf(r.output)}');
    }
  }

  /// 手持食物时进食（右键 / 使用动作触发）。
  void _eatHeld() {
    final ItemStack s = _inv.at(_inv.selected);
    if (s.isEmpty || foodValue(s.item) <= 0) return;
    if (!_vitals.eat(s.item)) {
      if (mounted) _snack('已经吃饱了');
      return;
    }
    _inv.set(_inv.selected, s.plus(-1));
    // #321：进食音效（素材缺失 = 安全 no-op）。
    unawaited(
      ref.read(minecraftSfxServiceProvider).playActionSfx(VoxelActionSfx.eat),
    );
  }

  /// 按当前模式重置物资（创造给满、生存给起步套装）。
  void _syncInventoryForMode() {
    if (_survival) {
      _inv.clear();
      _inv.set(0, const ItemStack(Voxel.planks, 16));
      _inv.set(1, const ItemStack(Voxel.torch, 8));
      _inv.set(2, const ItemStack(Voxel.bread, 3));
      _inv.selected = 0;
    } else {
      _inv.fillCreative(kCreativeBlocks);
    }
    // R26fx3：同步当前选中方块（否则放置用过期/默认 stone）。
    _mcSelected = _inv.at(_inv.selected).item;
  }

  // ── 交互 ────────────────────────────────────────────────

  /// 单指拖动 / 双指平移 → 相机旋转（视角跟随手指）；双指捏合 → 调焦距（FOV）。
  /// 统一走 Scale 识别器：focalPoint 位移驱动环视，scale 比值驱动焦距，互不干扰。
  void _onScaleStart(ScaleStartDetails d) {
    _idle = 0;
    _scaleFocal = d.localFocalPoint;
    _lastScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _idle = 0;
    // 环视：用焦点位移（单指拖动或双指平移都走这里）。
    final Offset delta = d.localFocalPoint - _scaleFocal;
    _scaleFocal = d.localFocalPoint;
    if (delta != Offset.zero) {
      _camera = _camera.rotate(delta.dx * 0.006, -delta.dy * 0.005);
    }
    // 焦距：双指捏合（scale != 1 时）。比值累乘，避免一帧跳变。
    if ((d.scale - _lastScale).abs() > 1e-4) {
      _camera = _camera.zoom(d.scale / _lastScale);
      _lastScale = d.scale;
    }
    _dirty = true;
  }

  /// 滚轮/触控板滚动 → 调焦距（FOV）：上滚拉近、下滚拉远。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _idle = 0;
    final double factor = 1.0 + (-event.scrollDelta.dy) * 0.0015;
    _camera = _camera.zoom(factor);
    _dirty = true;
  }

  // ── R26k：桌面鼠标绑定（FPS 操作）─────────────────────────
  // 触屏拖拽环视走 GestureDetector._onScaleUpdate；这里只处理鼠标：
  //   移动 → 视角（相对位移，与光标位置解耦）
  //   左键按下 → 攻击/挖掘（按住 = 连续，复用 _acting 长按挖掘）
  //   右键按下 → 放置
  //   Alt 按住 → 显示光标 + 解绑（可点 UI），松开重新绑定。

  // R26p-camera：环视（鼠标/拖拽转视角）在相机模式下也允许——否则进相机模式
  // 后既不能用鼠标也不能用拖拽取景（「鼠标不跟随」）。挖掘/放置仍仅在非相机模式。
  bool get _fpLookActive =>
      (_viewMode == _ViewMode.firstPerson ||
          _viewMode == _ViewMode.thirdPerson) &&
      !_bagOpen;

  bool get _fpMouseActive => _fpLookActive && !_cameraMode;

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    _lastMousePos = e.position;
    _mousePos = e.position;
    _downPos = e.position;
    _downMoved = false;
    // _fpMouseActive 已排除相机模式（相机模式只环视、不挖掘/放置）。
    if (!_fpMouseActive || !_fpMouseCaptured) return;
    if (e.buttons & kSecondaryMouseButton != 0) {
      _placeAt();
    } else if (e.buttons & kPrimaryMouseButton != 0) {
      // R26r5：不再「按下即破坏」——按下仅开始挖掘蓄力；一旦拖动（转动视角）
      // 立即取消（_onPointerMove）；松开未动才算一次点击破坏（_onPointerUp）。
      _acting = true;
      _dirty = true;
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    _lastMousePos = null;
    if (e.buttons & kPrimaryMouseButton != 0) return; // 左键仍按着（多键）
    final bool wasActing = _acting;
    _acting = false;
    if (wasActing) _resetMining();
    // R26r5：松开左键且未拖动 = 一次点击 → 破坏/攻击（转动视角不破坏物品）。
    if (wasActing && !_downMoved) _primaryAction();
    _downMoved = false;
    _dirty = true;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    final Offset? last = _lastMousePos;
    _lastMousePos = e.position;
    _mousePos = e.position;
    if (last == null) return; // 首次进入不跳
    // R26r5：按住左键拖动 = 转动视角，不破坏物品——位移超阈值即取消挖掘/攻击。
    if (_acting && (e.position - _downPos).distance > 6) {
      _downMoved = true;
      _acting = false;
      _resetMining();
    }
    if (!_fpLookActive || !_fpMouseCaptured) return;
    final Offset delta = e.position - last;
    if (delta == Offset.zero) return;
    _camera = _camera.rotate(delta.dx * 0.003, -delta.dy * 0.003);
    _idle = 0;
    _dirty = true;
  }

  /// R26m：边缘续转——鼠标停在窗口边缘时继续转视角（无鼠标捕获时的 FPS
  /// 替代方案：不需要第三方插件/平台通道，贴边即连续转向，离开边缘即停）。
  void _applyEdgeLook(double dt) {
    if (!_fpLookActive || !_fpMouseCaptured) return;
    final Offset? m = _mousePos;
    if (m == null || _viewport.isEmpty) return;
    const double margin = 16.0;
    double rx = 0, ry = 0;
    if (m.dx < margin) {
      rx = -1;
    } else if (m.dx > _viewport.width - margin) {
      rx = 1;
    }
    if (m.dy < margin) {
      ry = 1;
    } else if (m.dy > _viewport.height - margin) {
      ry = -1;
    }
    if (rx == 0 && ry == 0) return;
    const double speed = 1.7; // rad/s
    _camera = _camera.rotate(rx * speed * dt, ry * speed * dt);
    _idle = 0;
    _dirty = true;
  }

  // R26p-camera：跳跃输入（键盘空格 / 移动端「跳」键共用）。
  // 生存：入队一次跳跃。创造：**单击 = 普通跳跃**；320ms 内再按一次 = 切换飞行
  //（起飞）；飞行中再双击 = 落地（开始下落）。除非双击，否则飞行不落。
  // R26p-camera + R26r7：跳跃输入（键盘空格 / 移动端「跳」键共用）。
  // 生存：入队一次跳跃。
  // 创造：单击（按住）= 普通跳跃；**飞行中按住 = 上升**；320ms 内再按一次 =
  // 切换飞行（起飞 / 落地）。除非双击，否则飞行不落。
  void _onJumpButtonDown() {
    _jumpHeld = true; // cl28：按住态（水中持续上浮）
    if (_survival) {
      _fpJumpQueued = true;
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastJumpPress != null &&
        now.difference(_lastJumpPress!).inMilliseconds < 320) {
      // 双击 → 切换飞行（取消双击里第一次的跳跃/上升）。
      _flyMode = !_flyMode;
      _fpVy = 0;
      if (_flyMode) {
        // R26r20：起飞先查净空——狭小空间（顶头）不强制上升，改为平飞（可横向
        // 滑出逃生）；有净空才续接上升（对齐 MC：双击起飞后不松手就一直升）。
        if (!_bodyCollides(_fpPos.x, _fpPos.y + 0.2, _fpPos.z, 1.75)) {
          _held.add(_Nav.up);
        }
      } else {
        // 退出飞行 → 立即停止上升并开始下落（**必须移除**，否则 lift 常驻）。
        _held.remove(_Nav.up);
      }
      _lastJumpPress = null;
      _fpJumpQueued = false;
      _dirty = true;
    } else {
      _lastJumpPress = now;
      if (_flyMode) {
        _held.add(_Nav.up); // 飞行中按住 = 上升
        _idle = 0;
      } else {
        _fpJumpQueued = true; // 单击 = 普通跳跃
      }
    }
  }

  void _onJumpButtonUp() {
    _jumpHeld = false; // cl28：松开即停止上浮
    if (_survival) return;
    // R26r16「上升问题」根因修复：原来带 `if (_flyMode)` 守卫——当双击的第二下
    // 刚把飞行**关掉**，随后松手时守卫不成立 → _Nav.up 永久滞留在 _held 里；
    // _applyNavFP 的 lift 只看 !_survival 不看 _flyMode，于是每帧 ny = y + step
    // 且 _fpVy 被清零（零重力）→ 玩家匀速无限上升且停不下来。
    // 松手一律移除，杜绝这一类「按键状态泄漏」。
    _held.remove(_Nav.up);
    _idle = 0;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final bool fp = _viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson;
    final bool down = event is KeyDownEvent || event is KeyRepeatEvent;
    final bool up = event is KeyUpEvent;
    final LogicalKeyboardKey k = event.logicalKey;

    // H1r2：Esc = 打开/关闭游戏菜单（暂停整个世界；仅已进入世界时生效）。
    if (k == LogicalKeyboardKey.escape && _started && down) {
      _setPaused(!_paused);
      return KeyEventResult.handled;
    }
    // 暂停时其余按键全部吞掉（世界冻结，不响应操作）。
    if (_paused) return KeyEventResult.handled;

    // R26k：Alt 按住 = 显示光标并临时解绑鼠标视角（松开重新绑定）。
    if ((k == LogicalKeyboardKey.altLeft ||
            k == LogicalKeyboardKey.altRight) &&
        fp) {
      if (down) {
        _fpMouseCaptured = false;
      } else if (up) {
        _fpMouseCaptured = true;
      }
      _lastMousePos = null;
      return KeyEventResult.handled;
    }
    // R26c：Ctrl = 疾跑（按住提速；蹲下时无效，由 _applyNavFP 速度倍率处理）。
    if ((k == LogicalKeyboardKey.controlLeft ||
            k == LogicalKeyboardKey.controlRight) &&
        fp) {
      _sprinting = down;
      return KeyEventResult.handled;
    }
    // 空格：生存 = 跳跃入队；创造 = 单击跳 / 飞行中按住上升 / 双击切换飞行。
    // R26r16：**必须忽略 KeyRepeatEvent**——系统按键重复约 30Hz，每次重复都落在
    // 320ms 双击窗口内 → 按住空格会让 _flyMode 每秒被 toggle 十几次（乱飞根因）。
    // 只认真实的按下 / 抬起。
    if (k == LogicalKeyboardKey.space && fp) {
      if (event is KeyDownEvent) _onJumpButtonDown();
      if (event is KeyUpEvent) _onJumpButtonUp();
      return KeyEventResult.handled;
    }
    // Shift：生存 = 蹲（按住）；创造 = 未飞行蹲 / 飞行中下降（与 MC 一致）。
    if ((k == LogicalKeyboardKey.shiftLeft ||
            k == LogicalKeyboardKey.shiftRight) &&
        fp) {
      if (_survival || !_flyMode) {
        _crouching = down;
      } else {
        if (down) {
          _held.add(_Nav.down);
        } else if (up) {
          _held.remove(_Nav.down);
        }
      }
      return KeyEventResult.handled;
    }
    // E：开 / 关背包（对齐 MC，不再用作飞行）。
    if (k == LogicalKeyboardKey.keyE && event is KeyDownEvent) {
      setState(() => _bagOpen = !_bagOpen);
      return KeyEventResult.handled;
    }
    // 数字键 1-9：选快捷栏。
    if (event is KeyDownEvent) {
      int? slot;
      if (k == LogicalKeyboardKey.digit1) {
        slot = 0;
      } else if (k == LogicalKeyboardKey.digit2) {
        slot = 1;
      } else if (k == LogicalKeyboardKey.digit3) {
        slot = 2;
      } else if (k == LogicalKeyboardKey.digit4) {
        slot = 3;
      } else if (k == LogicalKeyboardKey.digit5) {
        slot = 4;
      } else if (k == LogicalKeyboardKey.digit6) {
        slot = 5;
      } else if (k == LogicalKeyboardKey.digit7) {
        slot = 6;
      } else if (k == LogicalKeyboardKey.digit8) {
        slot = 7;
      } else if (k == LogicalKeyboardKey.digit9) {
        slot = 8;
      }
      if (slot != null) {
        // Cl29_hotfix：背包开启且正手持物品时，数字键 1-9 把光标物品移入
        // 对应快捷栏格（落位逻辑同左键）；否则仍按旧逻辑选快捷栏。
        if (_bagOpen && _inv.carrying) {
          _inv.cursorToHotbar(slot + 1);
        } else {
          _selectSlot(slot);
        }
        return KeyEventResult.handled;
      }
    }
    // 方向键 / WASD：移动。
    final _Nav? nav = switch (k) {
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => _Nav.forward,
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.keyS => _Nav.back,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.keyA => _Nav.left,
      LogicalKeyboardKey.arrowRight || LogicalKeyboardKey.keyD => _Nav.right,
      _ => null,
    };
    if (nav == null) return KeyEventResult.ignored;
    if (down) {
      _held.add(nav);
    } else if (up) {
      _held.remove(nav);
    }
    return KeyEventResult.handled;
  }

  /// 选快捷栏第 [i] 格（数字键 1-9 / 触屏点选共用）。
  void _selectSlot(int i) {
    if (i < 0 || i >= VoxelInventory.hotbarSize) return;
    setState(() {
      _inv.selected = i;
      final ItemStack s = _inv.at(i);
      if (!s.isEmpty) _mcSelected = s.item;
      _dirty = true;
    });
  }

  /// 首屏「创造 / 生存」选择后进入世界：切第一人称并装好对应物资。
  void _enterWorld(bool survival) {
    setState(() {
      _survival = survival;
      _flyMode = false; // 进入世界重置飞行：创造默认落地，双击跳跃起飞
      _lastJumpPress = null;
      // R26r16：清掉可能滞留的升降键（防「进世界就一直往上飘」）。
      _held.remove(_Nav.up);
      _held.remove(_Nav.down);
      _fpVy = 0;
      if (survival) {
        // R28：仅「新世界（存档无数值）」才重置生存数值；已恢复存档则保留，
        // 避免进生存把自动存档的血量/饥饿冲掉。
        if (!_vitalsRestored) _vitals.respawn();
        _mobs.clear();
      }
      _syncInventoryForMode();
      _viewMode = _ViewMode.firstPerson;
      // R26g 修复：初始相机是 overview（pitch ≈ -78° 垂直俯视），进入第一
      // 人称时此前只改 position 不动 pitch → 玩家持续朝下看满屏灰地面/石头
      // （用户反馈「点击生存后画面被套上灰色滤镜、无法关闭」）。归位为水平
      // 略俯视（-0.15），保留 yaw 面朝方向，进入即见正常地平线。
      _camera = _camera.copyWith(pitch: -0.15);
      _eyeSmoothInit = false; // 进入世界 → 视角 Y 缓冲从当前高度起步
      _started = true;
      _waterHintShown = false; // cl28：每次进世界重置 → 首次入水再弹一次提示
      _currentMeta = null; // 全新世界，无父存档（备份将归到最近手动存档/新建）
      _sessionStart = DateTime.now(); // R26h：会话计时起点
      _dirty = true;
    });
  }

  /// cl29：受 options.cheats 门控的生存 / 创造切换（热栏「模式」按钮）。
  /// 未开启作弊 → 拦截并提示，避免误触改变模式。
  void _toggleSurvival() {
    if (!widget.world.options.cheats) {
      _snack('未开启作弊，无法切换生存 / 创造模式');
      return;
    }
    _enterWorld(!_survival);
  }

  /// H4：脱离卡死——把玩家传送到当前位置上方最近的安全地表（上探空气+
  /// 下探地面），清空速度与蹲伏。卡进方块/悬崖/洞穴口时一键脱出。
  void _unstick() {
    final VoxelWorld w = widget.world;
    final int cx = _fpPos.x.floor().clamp(0, w.sizeX - 1);
    final int cz = _fpPos.z.floor().clamp(0, w.sizeZ - 1);
    // 1) 找 (cx,cz) 最高非空气方块顶（下探地面）。
    int top = 0;
    for (int y = w.maxY - 1; y >= 0; y--) {
      if (w.get(cx, y, cz) != Voxel.air) {
        top = y + 1;
        break;
      }
    }
    // 2) 在该列向上找 2 格净空（站立身高 ~1.75），留 0.01 浮空防 z-fight。
    for (int dy = 0; dy <= 12; dy++) {
      final double feet = top + dy + 0.01;
      if (!_bodyCollides(_fpPos.x, feet, _fpPos.z)) {
        setState(() {
          _fpPos = Vec3(_fpPos.x, feet, _fpPos.z);
          _fpVy = 0;
          _fpOnGround = true;
          _crouching = false;
          _held.remove(_Nav.up);
          _held.remove(_Nav.down);
        });
        _snack('已脱离卡死');
        return;
      }
    }
    _snack('未找到安全位置，请换个姿势再试');
  }

  /// H2：场景拍摄——把当前视角（机位 + 世界种子）与玩家中心 16×16 的音效源
  /// 存成独立场景记录（画面实时渲染 + 音效原样重放），出现在主页场景列表。
  Future<void> _captureScene() async {
    final String? raw = await _promptSceneName();
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    final String finalName = raw.trim();
    // 1) 机位 + 种子（画面：主页用同 seed 世界 + 同机位实时渲染）。
    final VoxelSceneCapture base =
        VoxelSceneCapture.fromCamera(widget.world, _camera, timePhase: 0.25);
    // 2) 玩家中心 16×16 内所有音效源（原封不动复用）。
    final List<VoxelSoundscapeSource> sounds = WorldAudioEngine
        .scanSources(widget.world)
        .where((WorldAudioSource s) =>
            (s.x - _fpPos.x).abs() <= 8 && (s.z - _fpPos.z).abs() <= 8)
        .map((WorldAudioSource s) => VoxelSoundscapeSource(
              kind: s.kind.name,
              x: s.x,
              y: s.y,
              z: s.z,
              strength: s.strength,
            ))
        .toList();
    final Scene scene = Scene(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: finalName,
      mood: '体素',
      desc: '体素世界取景 · ${sounds.length} 个音效',
      track: '',
      artist: '',
      soundscape: 'voxel',
      icon: 'star',
      visual: const SceneVisual(
        gradientColors: <Color>[Color(0xFF0B1220), Color(0xFF1B2A4A)],
        stops: <double>[0, 1],
        accent: Color(0xFF9B7BFF),
        glyph: '✦',
      ),
      visualWeight: 0.8,
      valence: 0.5,
      energy: 0.5,
      voxelCapture: base.withSounds(sounds),
    );
    await ref.read(customScenesProvider.notifier).save(scene);
    if (mounted) _snack('已保存场景「$finalName」· ${sounds.length} 个音效');
  }

  /// H2：场景命名弹窗（留空取消）。
  Future<String?> _promptSceneName() {
    final TextEditingController c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('场景拍摄'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('命名场景画面与音效（存为独立场景，主页可复用）'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '场景名称（如：山谷清晨）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (String v) => Navigator.of(dctx).pop(v.trim()),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(c.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// H1r2：开/关游戏菜单（默认暂停整个世界——tick 冻结，仅菜单活）。
  void _setPaused(bool v) {
    if (_paused == v) return;
    setState(() {
      _paused = v;
      if (v) {
        // 暂停：收起折叠面板 + 清滞留按键，世界进入冻结帧。
        _foldOpen = false;
        _held.clear();
      } else {
        _lastTick = Duration.zero; // 恢复时 dt 不跳变
      }
    });
  }

  /// H1r2：保存并退出——落盘当前世界 → 返回主菜单页。
  Future<void> _saveAndExit() async {
    await _saveNow();
    if (!mounted) return;
    _snack('已保存并退出');
    // R27：临时放开 PopScope 闸门，等 rebuild 生效后再 pop，避免被自身 PopScope 拦截。
    _allowPop = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// R27：游戏中返回键接管（安卓系统返回 / 桌面 Esc）。
  ///
  /// - 任一内嵌面板（背包 / 折叠 HUD / 相机 / UI 折叠 / 暂停菜单）打开时 →
  ///   仅关闭该面板，不退出世界（这些面板不是独立路由，返回键不会自动收掉）。
  /// - 处于游戏主界面时：单次 → 弹提醒「请用存档保存退出」且不退出；
  ///   1.5s 内第二次 → 直接保存并退出（应急退出）。
  void _onWorldPop(bool didPop, Object? result) {
    if (didPop) return; // 已在退出流程（_allowPop=true 触发的真正 pop）
    // 1) 关闭最上层的内嵌面板（非路由弹层，需手动收掉）。
    if (_bagOpen) {
      _toggleBag();
      return;
    }
    if (_foldOpen) {
      setState(() => _foldOpen = false);
      return;
    }
    if (_cameraMode) {
      setState(() => _cameraMode = !_cameraMode);
      return;
    }
    if (_uiCollapsed) {
      setState(() => _uiCollapsed = false);
      return;
    }
    if (_paused) {
      _setPaused(false);
      return;
    }
    // 2) 主游戏界面：单击提醒 / 双击保存退出。
    final DateTime now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(milliseconds: 1500)) {
      _lastBackPress = null;
      _saveAndExit();
    } else {
      _lastBackPress = now;
      appNotify(
        context,
        '请通过「游戏菜单 → 保存退出」离开世界；连按两次返回可快速保存退出',
        title: '提示',
      );
    }
  }

  /// H1r2：恢复存档——从 自动备份（≤20）/ 手动备份 中任选，恢复到当前世界
  /// （回退当前档，不切换别的存档；H5 保持）。
  Future<void> _openRestorePicker() async {
    final List<VoxelAutoBackupMeta> autos = await listAutoBackups();
    final List<VoxelManualSaveMeta> manuals = await listManualSaves();
    if (!mounted || !context.mounted) return;
    // 组「标签 + 时间 + 加载器」：自动备份 + 各存档的手动备份。
    final List<
        (String, DateTime, Future<Map<String, dynamic>?> Function())> items =
        <(String, DateTime, Future<Map<String, dynamic>?> Function())>[];
    for (final VoxelAutoBackupMeta a in autos) {
      items.add((
        '自动备份 · ${_fmtTime(a.createdAt)}',
        a.createdAt,
        () => readAutoBackup(a.ts),
      ));
    }
    for (final VoxelManualSaveMeta m in manuals) {
      final List<VoxelManualSaveMeta> baks = await listBackups(m.id);
      for (final VoxelManualSaveMeta b in baks) {
        final List<String> parts = b.id.split('|');
        if (parts.length != 2) continue;
        items.add((
          '${m.name} · 备份 ${_fmtTime(b.createdAt)}',
          b.createdAt,
          () => readBackup(parts[0], parts[1]),
        ));
      }
    }
    items.sort(((a, b) => b.$2.compareTo(a.$2)));
    if (items.isEmpty) {
      _snack('暂无可用备份（自动/手动备份都会出现在这里）');
      return;
    }
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text('恢复存档', style: AppTextStyles.subtitle),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (BuildContext c, int i) {
                  final (String label, DateTime at, _) = items[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.restore),
                    title: Text(label, style: context.appText.body),
                    subtitle: Text(
                      '${at.month}月${at.day}日 ${_fmtTime(at)}',
                      style: context.appText.artist,
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(label),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final (String label, DateTime _, Future<Map<String, dynamic>?> Function() loader) =
        items.firstWhere((dynamic e) => e.$1 == pick);
    final Map<String, dynamic>? data = await loader();
    if (data == null) {
      if (mounted) _snack('该备份已损坏，无法恢复');
      return;
    }
    await _applySaveData(data);
    await _saveNow(); // 恢复结果立即落盘
    if (mounted) {
      _snack('已恢复到「$label」');
      _setPaused(false); // 恢复后继续游玩
    }
  }

  void _press(_Nav nav) {
    // 第一人称/第三人称：
    // 下 = 生存/创造未飞行：蹲；创造飞行中：下降。上 = 生存/创造未飞行：跳；
    // 创造飞行中：飞升（松手停）。
    if (_viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson) {
      if (nav == _Nav.down) {
        if (_survival || !_flyMode) {
          _crouching = true; // 生存任何时候 / 创造未飞行 = 蹲（R26r20）
        } else {
          _held.add(nav); // 创造飞行中：LiftPad 下 = 下降
        }
        _idle = 0;
        return;
      }
      if (nav == _Nav.up) {
        if (_survival || !_flyMode) {
          _idle = 0;
          _queueJump(); // 生存 / 创造未飞行：上 = 跳跃（统一逻辑）
          return;
        }
        _held.add(nav); // 创造飞行中：飞升
        _idle = 0;
        return;
      }
      // 前后左右：第一/三人称移动
      _held.add(nav);
      _idle = 0;
      return;
    }
    // orbit / iso：方向键旋转视角
    _held.add(nav);
    _idle = 0;
  }

  void _release(_Nav nav) {
    _held.remove(nav);
    if (nav == _Nav.down && (_survival || !_flyMode)) _crouching = false;
    _idle = 0;
  }

  /// 体素 DDA 射线：从相机眼睛沿视线步进，返回第一个实心方块坐标（瞄准/破坏用）。
  /// 射线拾取：返回 (命中方块坐标, 命中的那个面的外法线)。
  /// 连续步进并记录"从上一格(空气/水)跨入实体格"的那一步方向，即为我们看得见、
  /// 且选中了的那个面的外法线（指向相机一侧）。
  ((int, int, int), (int, int, int))? _raycast() {
    // R26r20·C：第三人称下射线从**角色眼位**（玩家脚下 + 眼高）出发、沿角色
    // 看向（= 相机视线方向）——不再从相机位置出发（TP 相机绕后/贴墙收缩时会
    // 穿墙破坏墙后方块）。第一人称相机即在眼位，行为不变。
    final Vec3 origin = _viewMode == _ViewMode.thirdPerson
        ? Vec3(
            _fpPos.x,
            _fpPos.y + (_crouching ? 0.9 : VoxelCamera.eyeHeight),
            _fpPos.z,
          )
        : _camera.position;
    final Vec3 dir = _camera.forwardVector().normalized;
    const double step = 0.05;
    int? lx, ly, lz;
    (int, int, int)? prev;
    for (double t = 0; t <= _reach; t += step) {
      final int bx = (origin.x + dir.x * t).floor();
      final int by = (origin.y + dir.y * t).floor();
      final int bz = (origin.z + dir.z * t).floor();
      if (bx == lx && by == ly && bz == lz) continue;
      lx = bx;
      ly = by;
      lz = bz;
      final Voxel v = widget.world.get(bx, by, bz);
      if (v != Voxel.air && v != Voxel.water) {
        final (int, int, int) p = prev ?? (bx, by - 1, bz);
        // 跨入方向 = 该面的外法线（朝相机）。
        return ((bx, by, bz), (bx - p.$1, by - p.$2, bz - p.$3));
      }
      prev = (bx, by, bz);
    }
    return null;
  }

  void _queueJump() {
    if (_viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson) {
      _fpJumpQueued = true;
      _idle = 0;
    }
  }

  /// 在准星所指方块"看得见的那一面"外侧空格放置当前选中方块。
  ///
  /// 规则（按需求）：
  ///  1. 取离视角最近、被射线命中的方块；
  ///  2. 取该方块被选中的那个面的外法线（朝相机）；
  ///  3. 面法线与视线夹角须在 (0°,180°) 内（不含 0°/180° 端点），即该面可见；
  ///  4. 目标格须为空气且不与玩家身体重叠，才算放得下。
  void _placeAt({bool eatFood = true}) {
    // #321：手持食物时，「使用 / 右键」直接进食（而非放置方块）。
    // R26fx：移动端「放置」按钮传 eatFood:false（进食归「使用」键）。
    final ItemStack held = _inv.at(_inv.selected);
    if (eatFood && !held.isEmpty && foodValue(held.item) > 0) {
      _eatHeld();
      return;
    }
    final ((int, int, int), (int, int, int))? hit = _raycast();
    if (hit == null) return;
    final ((int, int, int) b, (int, int, int) n) = hit;
    // 面可见性：外法线 N 与视线 V 夹角 θ∈(0°,180°) 且面朝相机 ⇔ -N·V ∈ (0,1)。
    final Vec3 view = _camera.forwardVector().normalized;
    final Vec3 N = Vec3(n.$1.toDouble(), n.$2.toDouble(), n.$3.toDouble())
        .normalized;
    final double facing = -N.dot(view); // = cos(θ)，θ 为 N 与 V 夹角
    if (facing <= 1e-3) {
      // 仅排除 0°（面背对/不可见）退化情况。
      // 注：180°（正对墙面）是「最常见放置姿态」，原阈值 0.9999 会把它拒掉，
      // 导致正对方块放不上去（R26r33 修复无法放置方块）。故只挡不可见面。
      return;
    }
    final int px = b.$1 + n.$1, py = b.$2 + n.$2, pz = b.$3 + n.$3;
    if (widget.world.get(px, py, pz) != Voxel.air) return;
    // 不与玩家身体重叠（第一/三人称）。
    if (_viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson) {
      final Vec3 fp = _playerPos;
      if ((px - fp.x).abs() < 0.9 &&
          (pz - fp.z).abs() < 0.9 &&
          py <= fp.y + 1.8 &&
          py >= fp.y - 0.2) {
        return;
      }
    }
    // R26fx3：放置**手持物品**（修复「拿木板却放石头/拿食物放不了」——
    // 旧实现用独立 _mcSelected，与背包不同步）。
    final Voxel toPlace = held.item;
    if (toPlace == Voxel.air) return;
    widget.world.setVoxel(px, py, pz, toPlace);
    if (widget.multiplayer) {
      ref.read(netSessionProvider.notifier).broadcastEdit(
        px, py, pz, Voxel.values.indexOf(toPlace),
      );
    }
    _invalidateChunkAt(px, pz);
    // G4：放置水 → 登记水源，后续由 20tps 扩散（MC 式，四周 9 格）。
    if (toPlace == Voxel.water) {
      widget.world.addWaterSource(px, py, pz);
    }
    _dirty = true;
    _staticPicture = null; // R26f：地形编辑 → 静态快照失效
  }

  /// 攻击/破坏统一入口：生存=攻击僵尸；创造=直接破坏。
  /// R26fx3：破坏/攻击合并——先尝试攻击实体（命中即攻击），否则破坏方块。
  /// 生存/创造都能挖；有僵尸时先打僵尸。
  void _primaryAction() {
    if (_bagOpen || _cameraMode) return;
    if (_viewMode != _ViewMode.firstPerson &&
        _viewMode != _ViewMode.thirdPerson) {
      return;
    }
    if (_tryAttack()) return;
    final ((int, int, int), (int, int, int))? h = _raycast();
    if (h != null) _breakBlock(h.$1);
  }

  void _invalidateChunkAt(int x, int z) {
    final int cx = x ~/ 16, cz = z ~/ 16;
    // R26r10：编辑影响相邻区块的遮挡——区块边界方块破坏/放置后，邻居的
    // 被遮挡面也要重建，否则只失效本块时边界方块的邻面仍用旧遮挡缓存
    // →「更新不及时 / 幽灵面」。3×3 全失效（便宜，只是 map remove）。
    for (int dx = -1; dx <= 1; dx++) {
      for (int dz = -1; dz <= 1; dz++) {
        _chunkCache.invalidate(cx + dx, cz + dz);
      }
    }
    _chunkInvalidSerial++; // cl30：区块编辑 → 自增，重建门控据此立即重建
  }

  String _facingLabel(double yaw) {
    final double a = ((yaw % (2 * math.pi)) + 2 * math.pi) % (2 * math.pi);
    const List<String> dirs = <String>['北', '东', '南', '西'];
    final int i = ((a + math.pi / 4) / (math.pi / 2)).floor() % 4;
    return dirs[i];
  }

  String _biomeLabel(Biome b) {
    switch (b) {
      case Biome.plains:
        return '平原';
      case Biome.forest:
        return '森林';
      case Biome.desert:
        return '沙漠';
      case Biome.mountain:
        return '高山';
      case Biome.snowMountain:
        return '雪山';
      case Biome.river:
        return '河流';
      case Biome.ocean:
        return '海洋';
    }
  }

  void _setView(_ViewMode mode) {
    _viewMode = mode;
    if (mode == _ViewMode.firstPerson || mode == _ViewMode.thirdPerson) {
      // R26o：视角切换**在角色当前位置**进行（不再重置到世界中心/随机点，
      // 用户「切换视角是在角色本身的位置切换」）。只归位俯仰避免沿用俯视。
      _fpVy = 0;
      _fpJumpQueued = false;
      // R26r16：切视角时清掉滞留升降键，避免带着 _Nav.up 进入第一人称后狂升。
      _held.remove(_Nav.up);
      _held.remove(_Nav.down);
      _eyeSmoothInit = false; // 第一/三人称切换 → 视角 Y 缓冲重置（避免悬空漂移）
      _camera = _camera.copyWith(pitch: -0.15);
    }
    _dirty = true;
    setState(() {});
  }

  /// 视角切换按钮回调：R26m 起只循环 第一人称 ↔ 第三人称（去掉俯视/2.5D）。
  ///
  /// 具体实现由本方法提供（外部只需把 [ViewModeButton.onPressed] 指向它），
  /// 组件本身不依赖任何视角枚举。
  void _cycleViewMode() {
    const List<_ViewMode> order = <_ViewMode>[
      _ViewMode.firstPerson,
      _ViewMode.thirdPerson,
    ];
    final int i = order.indexOf(_viewMode);
    _setView(order[(i + 1) % order.length]);
    _snack('视角：${_viewModeLabel()}');
  }

  /// 当前视角的中文标签（供按钮展示 / 无障碍）。
  String _viewModeLabel() {
    switch (_viewMode) {
      case _ViewMode.iso2d5:
        return '2.5D';
      case _ViewMode.orbit:
        return '俯瞰';
      case _ViewMode.firstPerson:
        return '第一人称';
      case _ViewMode.thirdPerson:
        return '第三人称';
    }
  }

  void _setFov(double f) {
    // ⚠️ 相机内部 fov 是**弧度**（minFov=0.55≈31.5° / maxFov=1.92≈110°），
    // 滑块 _CameraPanel 也工作在弧度（value 0.35~1.5、标签按 fov>=1.1 判广角）。
    // 之前的 clamp(30.0, 100.0) 是角度写法，会把任意弧度输入（<30）钳到 30 弧度
    // （≈1719°）→ tan 周期翻转 → 投影 f 变负 → 画面畸变/颠倒。改为弧度边界。
    // R26skel-fix：setState 让滑块/「广角·标准·长焦」标签实时跟随拖动。
    setState(() {
      _camera = _camera.copyWith(
        fov: f.clamp(VoxelCamera.minFov, VoxelCamera.maxFov),
      );
      _dirty = true;
    });
  }

  /// 世界内操作通知：统一走全局**小 toast**（recentNotificationsProvider），
  /// 与播放/场景事件同款式（右上角 3s 小弹条，R26r21d），不再用底部 SnackBar。
  void _snack(String m) {
    if (!mounted) return;
    ref.read(recentNotificationsProvider.notifier).append('世界', m);
  }

  // ── R24d 自动存档：序列化 / 恢复 / 周期落盘 ─────────────
  /// R26r15：当前世界身份（来自上一次读档的 `_meta`：名称 / 父存档）。
  /// 自动存档时原样写回，使「备份当前世界」能归到正确的所属存档——
  /// 保证「备份的备份还是备份」（平铺、不套娃）。
  Map<String, dynamic>? _currentMeta;

  Map<String, dynamic> _buildSaveData() {
    final Map<String, dynamic> data = <String, dynamic>{
      'v': 1,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'world': widget.world.toJson(),
      'camera': <String, dynamic>{
        'px': _camera.position.x,
        'py': _camera.position.y,
        'pz': _camera.position.z,
        'yaw': _camera.yaw,
        'pitch': _camera.pitch,
        'fov': _camera.fov,
        'near': _camera.near,
        'far': _camera.far,
        'fullWidth': _camera.fullWidth,
      },
      'viewMode': _viewMode.index,
      'cameraMode': _cameraMode,
      'fpPos': <double>[_fpPos.x, _fpPos.y, _fpPos.z],
      'figurePos': <double>[_figurePos.x, _figurePos.y, _figurePos.z],
      'vitals': _vitals.toJson(),
      'inv': _inv.toJson(),
    };
    // 保留当前世界身份，供「备份当前世界」正确归到所属存档。
    if (_currentMeta != null) data['_meta'] = _currentMeta;
    return data;
  }

  Future<void> _saveNow() async {
    await writeVoxelSave(_buildSaveData());
    // R27：游戏中保存 → 同步刷新所属手动存档的「最近保存时间」，使存档列表显示最新时间。
    if (_currentMeta is Map<String, dynamic> &&
        _currentMeta!['id'] is String) {
      final String mid = _currentMeta!['id'] as String;
      unawaited(touchManualSaveLastSaved(mid));
    }
    if (!mounted) return;
    _lastSavedAt = DateTime.now();
    setState(() {});
  }

  Future<void> _restoreSave() async {
    try {
      final Map<String, dynamic>? data = await readVoxelSave();
      if (!mounted || data == null) return;
      // R27：自动存档属「上一个世界」。若存档种子与本世界不同（换种子新开世界），
      // 整份跳过——避免旧存档的机位/状态串到新世界（「新建游戏没存档」观感：
      // 进新世界却落在旧存档坐标）。同种子才继续（真正续档）。
      final Map<String, dynamic>? wj =
          data['world'] as Map<String, dynamic>?;
      if (wj != null && wj['seed'] != widget.world.seed) return;
      await _applySaveData(data);
      if (mounted) _snack('已恢复上次的世界存档');
    } catch (e, st) {
      // R26r13：恢复失败不再静默——落盘日志便于定位（位置不恢复的隐患）。
      unawaited(_logRenderError('restoreSave', e, st));
    }
  }

  /// 应用一份存档数据到当前世界（自动恢复 / 手动读档共用）。
  ///
  /// R26r13：**玩家位置 / 机位优先恢复**，世界编辑层 / 生存 / 背包各段独立
  /// try/catch——旧版或损坏存档里任一字段抛异常会中断整个恢复，导致玩家位置
  /// 永不恢复（重进存档回中心 =「位置没保存」+ 编辑层没恢复像「重载」）。
  /// 现在位置永远先恢复，其余段失败静默跳过。
  /// R26fx：进入世界时应用存档的玩家状态（位置/相机视角/编辑层/背包）。
  /// 与 [_applySaveData] 同逻辑，但 initState 阶段调用（不可 setState）。
  void _applyInitialSave(Map<String, dynamic> data) {
    final List<dynamic>? fp = data['fpPos'] as List<dynamic>?;
    if (fp != null && fp.length >= 3) {
      _fpPos = Vec3(
        (fp[0] as num).toDouble(),
        (fp[1] as num).toDouble(),
        (fp[2] as num).toDouble(),
      );
      _figurePos = _fpPos;
      _figureTarget = _fpPos;
    }
    final int vm = (data['viewMode'] as int?) ?? _viewMode.index;
    if (vm >= 0 && vm < _ViewMode.values.length) {
      _viewMode = _ViewMode.values[vm];
    }
    _cameraMode = (data['cameraMode'] as bool?) ?? _cameraMode;
    final Map<String, dynamic>? cj = data['camera'] as Map<String, dynamic>?;
    if (cj != null) {
      try {
        _camera = VoxelCamera(
          position: Vec3(
            (cj['px'] as num).toDouble(),
            (cj['py'] as num).toDouble(),
            (cj['pz'] as num).toDouble(),
          ),
          yaw: (cj['yaw'] as num).toDouble(),
          pitch: (cj['pitch'] as num).toDouble(),
          fov: (cj['fov'] as num).toDouble(),
          near: (cj['near'] as num?)?.toDouble() ?? _camera.near,
          far: (cj['far'] as num?)?.toDouble() ?? _camera.far,
          fullWidth: (cj['fullWidth'] as bool?) ?? _camera.fullWidth,
        );
      } catch (_) {}
    }
    try {
      final Map<String, dynamic>? wj = data['world'] as Map<String, dynamic>?;
      if (wj != null && wj['seed'] == widget.world.seed) {
        widget.world.loadJson(wj);
      }
    } catch (_) {}
    try {
      final Map<String, dynamic>? vj = data['vitals'] as Map<String, dynamic>?;
      if (vj != null) {
        _vitals.loadJson(vj);
        _vitalsRestored = true; // R28：存档确有数值 → 进生存不再 respawn
      }
    } catch (_) {}
    try {
      final Map<String, dynamic>? ij = data['inv'] as Map<String, dynamic>?;
      if (ij != null) _inv.loadJson(ij);
    } catch (_) {}
    _lastSavedAt = data['savedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(data['savedAt'] as int)
        : null;
    final dynamic m = data['_meta'];
    _currentMeta = (m is Map<String, dynamic>) ? Map<String, dynamic>.from(m) : null;
    _chunkCache.clear();
    _dirty = true;
  }

  Future<void> _applySaveData(Map<String, dynamic> data) async {
    // ── 1. 玩家位置 / 小人位置（最优先，绝不因其他段失败而丢）──
    final List<dynamic>? fp = data['fpPos'] as List<dynamic>?;
    if (fp != null && fp.length >= 3) {
      _fpPos = Vec3(
        (fp[0] as num).toDouble(),
        (fp[1] as num).toDouble(),
        (fp[2] as num).toDouble(),
      );
    }
    final List<dynamic>? fig = data['figurePos'] as List<dynamic>?;
    if (fig != null && fig.length >= 3) {
      _figurePos = Vec3(
        (fig[0] as num).toDouble(),
        (fig[1] as num).toDouble(),
        (fig[2] as num).toDouble(),
      );
      _figureTarget = _figurePos;
    }
    // ── 2. 视角模式 / 相机机位 ──
    final int vm = (data['viewMode'] as int?) ?? _viewMode.index;
    if (vm >= 0 && vm < _ViewMode.values.length) {
      _viewMode = _ViewMode.values[vm];
    }
    _cameraMode = (data['cameraMode'] as bool?) ?? _cameraMode;
    final Map<String, dynamic>? cj = data['camera'] as Map<String, dynamic>?;
    if (cj != null) {
      try {
        _camera = VoxelCamera(
          position: Vec3(
            (cj['px'] as num).toDouble(),
            (cj['py'] as num).toDouble(),
            (cj['pz'] as num).toDouble(),
          ),
          yaw: (cj['yaw'] as num).toDouble(),
          pitch: (cj['pitch'] as num).toDouble(),
          fov: (cj['fov'] as num).toDouble(),
          near: (cj['near'] as num?)?.toDouble() ?? _camera.near,
          far: (cj['far'] as num?)?.toDouble() ?? _camera.far,
          fullWidth: (cj['fullWidth'] as bool?) ?? _camera.fullWidth,
        );
      } catch (_) {
        // 机位损坏：保留当前机位
      }
    }
    // ── 3. 世界编辑层（seed 一致才恢复）──
    try {
      final Map<String, dynamic>? wj = data['world'] as Map<String, dynamic>?;
      if (wj != null && wj['seed'] == widget.world.seed) {
        widget.world.loadJson(wj);
      }
    } catch (_) {
      // 编辑层损坏：跳过（地形仍按种子正确生成）
    }
    // ── 4. 生存 / 背包（各自容错）──
    try {
      final Map<String, dynamic>? vj = data['vitals'] as Map<String, dynamic>?;
      if (vj != null) {
        _vitals.loadJson(vj);
        _vitalsRestored = true; // R28：存档确有数值 → 进生存不再 respawn
      }
    } catch (_) {
      // 生存数值损坏：跳过
    }
    try {
      final Map<String, dynamic>? ij = data['inv'] as Map<String, dynamic>?;
      if (ij != null) _inv.loadJson(ij);
    } catch (_) {
      // 背包损坏：跳过
    }
    _lastSavedAt = data['savedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(data['savedAt'] as int)
        : null;
    // R26r15：记住当前世界身份（名称/父存档），自动存档时原样保留，
    // 让「备份当前世界」能归到正确的所属存档（备份的备份仍是该存档的平铺备份）。
    final dynamic m = data['_meta'];
    _currentMeta = (m is Map<String, dynamic>) ? Map<String, dynamic>.from(m) : null;
    _chunkCache.clear(); // 地形编辑层变了 → 几何缓存全量失效
    _dirty = true;
    if (mounted) setState(() {});
  }

  // ── R26d 手动存档（可命名 + 存档菜单）───────────────
  Future<void> _loadManual(String id, String name) async {
    final Map<String, dynamic>? data = await readManualSave(id);
    if (data == null || !mounted) return;
    await _applySaveData(data);
    // 立即把读档后的世界（含 _meta 身份）落盘为「当前世界」，
    // 保证紧接着的「备份当前世界」读到正确的所属存档。
    await writeVoxelSave(_buildSaveData());
    if (mounted) _snack('已读取存档「$name」');
  }

  // ── R26p：游戏中也可以备份当前世界 / 导出存档（与主页管理器共享函数）──
  /// R26r15：备份=快照「当前正在玩的世界」（自动存档），**不切换**世界——
  /// 备份后你仍运行原存档，需手动在存档列表点「进入」才读取该备份。
  /// 备份落到「当前世界所属存档」：正在玩某备份(_meta.parent)则归父存档；
  /// 否则归最近手动存档；都没有则新建「我的世界」。保证「备份的备份还是备份」
  /// （平铺、不套娃）。这是唯一的备份入口，语义与使用处文案完全统一。
  Future<void> _doBackupCurrent() async {
    final Map<String, dynamic>? cur = await readVoxelSave();
    if (!mounted) return;
    if (cur == null) {
      if (mounted) _snack('当前没有可备份的世界');
      return;
    }
    // 解析目标存档：优先当前世界所属父存档，否则最近手动存档，否则新建。
    String? parentId;
    if (cur['_meta'] is Map && (cur['_meta'] as Map)['parent'] is String) {
      parentId = (cur['_meta'] as Map)['parent'] as String;
    }
    if (parentId != null && (await readManualSave(parentId)) != null) {
      await createBackup(parentId);
      if (mounted) {
        _snack('已备份当前世界 · 在存档列表点「进入」可读取');
      }
      return;
    }
    final List<VoxelManualSaveMeta> saves = await listManualSaves();
    if (!mounted) return;
    if (saves.isEmpty) {
      final String id = await writeManualSave(cur, '我的世界');
      await createBackup(id);
      if (mounted) _snack('已新建并备份「我的世界」');
      return;
    }
    await createBackup(saves.first.id);
    if (mounted) _snack('已备份当前世界 · 在存档列表点「进入」可读取');
  }

  Future<void> _exportManualFromMenu(String id, String name) async {
    try {
      final File f = await manualSaveFile(id);
      if (!await f.exists()) {
        if (mounted) _snack('文件不存在');
        return;
      }
      await Share.shareXFiles(
        <XFile>[XFile(f.path)],
        subject: name,
        text: '星璃音乐 · 体素世界存档「$name」',
      );
    } catch (_) {
      if (mounted) _snack('导出失败');
    }
  }

  /// R26h：游戏中快捷设置（由外层页迁入内部 State）。**不复制**首页设置 UI——
  /// 直接读写首页设置的同一批 provider（白噪音/世界音效/帧率/播放引擎 →
  /// 天然联动）；画质档是 3D 内私有状态（[_setQuality] 同步渲染配置）。
  /// 底部弹窗可滚动（isScrollControlled + 高度上限），窄屏选项也不被截断。
  /// R26skel：**游戏设置 = 全局设置页「游戏」合集**——暂停菜单「游戏设置」
  /// 直接打开全局设置页并定位到「游戏」合集（不再用独立快捷弹窗，避免两套 UI）。
  void _openGlobalGameSettings() {
    ref.read(layoutSelectedCollectionProvider.notifier).state = 'game';
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  /// 存档菜单（R26r15 收尾）：新建世界（可自定义种子）独立于备份；列表可
  /// 进入 / 重命名 / 导出 / 删除（带确认）。「备份」只有唯一的「备份当前世界」
  /// 动作（快照正在运行的世界、不切换），不再有「备份到该存档」这类歧义入口。
  /// 所有变更**原地刷新列表**、不再重开弹层——修复「删除后无限套娃」。
  ///
  /// H5：**游戏中不能切换存档、只允许备份** —— `inGame=true`（顶栏「存档」
  /// 进入）隐藏「新建世界」与存档列表「进入」，仅保留备份/重命名/导出/删除；
  /// 主菜单「存档」（inGame=false）保留完整能力（未进入世界，切换合法）。
  /// R26fx：我的存档（游戏菜单第二位）——合并「手动存档 + 恢复备份 + 详情」。
  /// 只显示当前存档（与「世界存档」总表区别：聚焦当前世界，直接展示详细信息）。
  Future<void> _openMySaves() async {
    if (!mounted || !context.mounted) return;
    final List<VoxelAutoBackupMeta> autos = await listAutoBackups();
    final List<VoxelManualSaveMeta> manuals = await listManualSaves();
    if (!mounted || !context.mounted) return;
    final String curName = _currentMeta?['name'] as String? ?? '当前世界（未命名）';
    final int seed = widget.world.seed;
    final String pos =
        'X ${_fpPos.x.toStringAsFixed(1)} · Y ${_fpPos.y.toStringAsFixed(1)} · Z ${_fpPos.z.toStringAsFixed(1)}';
    final String view =
        'Yaw ${(_camera.yaw * 180 / math.pi).round()}° · Pitch ${(_camera.pitch * 180 / math.pi).round()}°';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.inventory_2_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('我的存档', style: AppTextStyles.subtitle),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(curName, style: context.appText.body),
              const SizedBox(height: 4),
              Text(
                '种子 #${(seed & 0xffff).toRadixString(16).toUpperCase().padLeft(4, '0')}'
                ' · 保存于 ${_lastSavedAt == null ? '—' : _fmtTime(_lastSavedAt!)}',
                style: context.appText.artist,
              ),
              Text('位置 $pos · 视角 $view', style: context.appText.artist),
              Text('自动备份 ${autos.length} 份 · 手动存档 ${manuals.length} 个',
                  style: context.appText.artist),
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _saveNow();
                      if (mounted) _snack('已手动存档（当前视角/位置已记录）');
                    },
                    icon: const Icon(Icons.save_alt_rounded, size: 18),
                    label: const Text('手动存档'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openRestorePicker();
                    },
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('恢复备份'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _renameCurrentSave(sheetContext),
                    icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                    label: const Text('重命名'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// R26fx：重命名当前存档（无手动存档则提示先手动存档）。
  Future<void> _renameCurrentSave(BuildContext sheetContext) async {
    final String? id = _currentMeta?['id'] as String?;
    if (id == null) {
      _snack('当前世界尚无手动存档，请先「手动存档」');
      return;
    }
    final TextEditingController ctrl =
        TextEditingController(text: _currentMeta?['name'] as String? ?? '');
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('重命名存档'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '存档名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await renameManualSave(id, name);
    if (mounted) _snack('已重命名为「$name」');
  }

  // ignore: unused_element（已由 _openMySaves 取代；保留备用）
  Future<void> _openSaveMenu({bool inGame = true}) async {
    List<VoxelManualSaveMeta> saves = await listManualSaves();
    if (!mounted || !context.mounted) return;
    final TextEditingController seedCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext c, StateSetter setSheet) {
            Future<void> refresh() async {
              final List<VoxelManualSaveMeta> s = await listManualSaves();
              if (c.mounted) setSheet(() => saves = s);
            }

            void enter(String id, String name) {
              Navigator.of(sheetContext).pop();
              _loadManual(id, name);
            }

            Future<void> newWorld() async {
              final String rawName = _saveNameCtrl.text.trim();
              final int seed = int.tryParse(seedCtrl.text.trim()) ??
                  math.Random().nextInt(1 << 30);
              final String finalName =
                  rawName.isEmpty ? '世界 ${_stampNow()}' : rawName;
              final Map<String, dynamic> data = freshWorldSave(seed);
              try {
                await writeManualSave(data, finalName);
                await writeVoxelSave(data);
              } catch (_) {
                if (c.mounted) _snack('新建失败');
                return;
              }
              if (!c.mounted) return;
              Navigator.of(sheetContext).pop();
              if (mounted) {
                _snack('已新建世界「$finalName」（种子 $seed）');
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => VoxelWorld3DPage(seed: seed),
                  ),
                );
              }
            }

            Future<void> confirmDelete(VoxelManualSaveMeta s) async {
              final bool? ok = await showDialog<bool>(
                context: context,
                builder: (BuildContext dctx) => AlertDialog(
                  title: const Text('删除存档'),
                  content: Text('确定删除「${s.name}」及其全部备份？此操作不可恢复。'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(dctx).pop(false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dctx).pop(true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (ok != true || !mounted) return;
              await deleteSaveWithBackups(s.id);
              await refresh();
              _snack('已删除「${s.name}」');
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: AppSpace.md,
                  right: AppSpace.md,
                  top: AppSpace.md,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                      AppSpace.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('存档管理', style: AppTextStyles.subtitle),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      inGame
                          ? '游戏内仅备份当前世界；切换/恢复请退出到主页设置·世界存档'
                          : '新建=全新种子世界；备份=保存当前世界；点存档「进入」读取',
                      style: context.appText.artist,
                    ),
                    const SizedBox(height: AppSpace.md),
                    // ── 新建世界（自定义种子，独立于备份；游戏内 H5 隐藏）──
                    if (!inGame) ...<Widget>[
                      Text('新建世界', style: context.appText.body),
                      const SizedBox(height: AppSpace.xs),
                      TextField(
                        controller: _saveNameCtrl,
                        decoration: const InputDecoration(
                          hintText: '世界名称（留空自动命名）',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        style: context.appText.body,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: seedCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '种子（数字，留空随机）',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              style: context.appText.body,
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          FilledButton.icon(
                            onPressed: newWorld,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('新建并进入'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.md),
                    ],
                    // ── 备份当前世界（独立动作，不与新建混为一谈）──
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _doBackupCurrent();
                          await refresh();
                        },
                        icon: const Icon(Icons.backup_outlined, size: 18),
                        label: const Text('备份当前世界'),
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    // ── 存档列表 ──
                    if (saves.isEmpty)
                      Text('暂无存档', style: context.appText.artist)
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: saves.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpace.xs),
                          itemBuilder: (BuildContext c2, int i) {
                            final VoxelManualSaveMeta s = saves[i];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.public),
                              title: Text(s.name, style: context.appText.body),
                              subtitle: Text(
                                '${s.createdAt.month}月${s.createdAt.day}日 '
                                '${_fmtTime(s.createdAt)}',
                                style: context.appText.artist,
                              ),
                              // H5：游戏内不能切换存档——禁用进入；主菜单可进。
                              onTap: inGame ? null : () => enter(s.id, s.name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (!inGame)
                                    IconButton(
                                      tooltip: '进入',
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: () => enter(s.id, s.name),
                                    ),
                                  PopupMenuButton<String>(
                                    onSelected: (String act) async {
                                      if (act == 'rename') {
                                        final String? newName =
                                            await _promptRename(s.name);
                                        if (newName == null || !mounted) return;
                                        await renameManualSave(s.id, newName);
                                        await refresh();
                                        _snack('已重命名为「$newName」');
                                      } else if (act == 'delete') {
                                        await confirmDelete(s);
                                      } else if (act == 'export') {
                                        Navigator.of(sheetContext).pop();
                                        await _exportManualFromMenu(
                                            s.id, s.name);
                                      }
                                    },
                                    itemBuilder: (BuildContext bc) =>
                                        const <PopupMenuEntry<String>>[
                                      PopupMenuItem<String>(
                                        value: 'rename',
                                        child: Text('重命名'),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'export',
                                        child: Text('导出分享'),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Text('删除'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    seedCtrl.dispose();
  }

  String _stampNow() {
    final DateTime t = DateTime.now();
    return '${t.month}月${t.day}日 ${_fmtTime(t)}';
  }

  /// 弹输入框重命名，返回新名称（取消返回 null）。
  Future<String?> _promptRename(String current) async {
    final TextEditingController c =
        TextEditingController(text: current);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('重命名存档'),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (String v) => Navigator.of(dctx).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(c.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    c.dispose();
    return result == null || result.isEmpty ? null : result;
  }

  String _fmtTime(DateTime t) {
    final int h = t.hour, m = t.minute, s = t.second;
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(h)}:${p2(m)}:${p2(s)}';
  }

  Future<void> _capture() async {
    try {
      final RenderRepaintBoundary? boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image img = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      // R26p2：存到「应用支持目录 / captures」，不再进用户「文档」目录。
      final Directory dir = await getApplicationSupportDirectory();
      final Directory capDir = Directory('${dir.path}/captures');
      await capDir.create(recursive: true);
      final String ts = DateTime.now().millisecondsSinceEpoch.toString();
      final File png = File('${capDir.path}/voxel_$ts.png');
      final File json = File('${capDir.path}/voxel_$ts.json');
      await png.writeAsBytes(bytes.buffer.asUint8List());
      // 同时写场景快照 JSON，使照片墙能「进入场景」（否则只有图、进不去）。
      final VoxelSceneCapture cap = VoxelSceneCapture.fromCamera(
        widget.world,
        _camera,
        aspect: 1.0,
        timePhase: 0.25,
      );
      await json.writeAsString(const JsonEncoder().convert(cap.toJson()));
      _snack('已保存截图');
    } catch (e) {
      _snack('截图失败: $e');
    }
  }

  // ── 画面精度 → 渲染配置映射（R24c）────────────────────
  /// cl45：渲染 far = max(视距, LOD 地平线) —— LOD 远景可越过视距看得更远。
  double _renderFar() =>
      math.max(_config.viewDistanceChunks, _config.lodMaxChunks) *
      RenderConfig.chunkSize.toDouble();

  RenderConfig _configFor(GraphicsQuality q) => RenderConfig(
        // P0(性能合集)：视距以**档位自身值为硬上限**——切「省电」档就跑 2 区块，
        // 不再被全局 provider 的历史值顶高 → 低档不再卡死。用户在设置页手动调小
        // 仍生效（min 取小）；想调大必须切更高档位。
        // cl76_hotfix2：自动档用运行时 _autoViewChunks（FPS 监测双向调节），
        // 视距固定上限 4、LOD 上限 64（最大渲染约束）。
        viewDistanceChunks: q == GraphicsQuality.auto
            ? _autoViewChunks
            : math.min(
                q.viewDistanceChunks, ref.read(viewDistanceChunksProvider)),
        lodStartChunks: ref.read(lodStartChunksProvider),
        lodStepChunks: ref.read(lodStepChunksProvider),
        // R26lod：LOD 参数体系——开关/步长格/采样 2 幂/最远区块（可 > 视距）。
        lodMasterEnabled: ref.read(lodEnabledProvider),
        lodStepBlocks: ref.read(lodStepBlocksProvider),
        lodSampleBase: ref.read(lodSampleBaseProvider),
        lodMaxChunks: q == GraphicsQuality.auto
            ? _autoLodChunks
            : ref.read(lodMaxChunksProvider),
        // cl45：边界雾（可选，与 LOD 互斥）——开=传统视距雾，关=LOD 远景。
        boundaryFog: ref.read(boundaryFogEnabledProvider),
        // 性能受限时近处也 LOD：perf/smooth 满精度带收窄到 3×3（fullBand=1），
        // 带外更近就开始合成大方块（配合 lodStart 调小）。
        fullBandChunks: q == GraphicsQuality.powerSave ||
                q == GraphicsQuality.smooth
            ? 1
            : 2,
        // R26p2：云层区块视距独立可调（与首页「游戏画面」同源）。
        cloudViewDistanceChunks: ref.read(cloudViewDistanceProvider),
        // R26fx：渲染精度倍率（0.5×~2× 乘面数预算）。
        maxFaces: (q.maxFaces * ref.read(renderPrecisionProvider)).round(),
        fogEnabled: q.fog,
        waterAnimation: q.water,
        textureEnabled: q.texture,
        // R26r2：恢复剔除——透视根因=绘制顺序（已由深度排序修复），剔除无害。
        // 遮挡剔除：隐藏方块内部面（最大面数收益；被遮挡面本就会被近面盖住）。
        // R26r2：恢复剔除——透视根因=绘制顺序（已由深度排序修复），剔除无害。
        // cl30+：遮挡/背面/视锥/侧面剔除全部提升为设置项（faceCullEnabled 等），
        // 用户可在「设置 → 机制 → 渲染与机制」里单独开关；默认值与管线一致。
        occlusionCull: ref.read(occlusionCullEnabledProvider),
        // 背面剔除：去掉背向相机的面（面数减半；画家算法下背面本来就看不见）。
        backFaceCull: ref.read(backFaceCullEnabledProvider),
        // 视锥剔除：按用户反馈关闭（R26r33）——前向剔除会误删可见区块，
        // 导致幽灵方块乱飘 / 高大物体侧面缺失 / 地下不渲染。面数由 maxFaces
        // 预算收敛（最远面优先裁、雾掩盖），关闭不增面数、只换「画哪些面」。
        frustumCull: ref.read(frustumCullEnabledProvider),
        // R26r2：LOD 采样保持关闭——采样抽稀会在远处制造「空洞」= 另一种透视，
        // 正确性优先；远处面数由地形面数预算收敛（最远面优先裁、雾掩盖）。
        // R26r18·P6：LOD 质量档位（high=多档细 LOD 全开；balanced=原 2 档；
        // off=全距离满精度方阵）。视锥剔除开关接 lodFrustumCullProvider（#268 接入）。
        lodQuality: ref.read(lodQualityProvider),
        lodFrustumCull: ref.read(lodFrustumCullProvider),
        // R26fl：手电筒模式（完整视线窄锥剔除 + 边界黑化 + 泛光）。
        flashlight: ref.read(flashlightEnabledProvider),
        // cl76：收纳折叠——去掉复杂光影：阴影 / 环境光屏蔽强制关闭（低画质已
        // 足够，纯色平铺 + 雾 + 远景 LOD 即可）。手电筒属玩法机制，保留开关。
        shadowRender: false,
        aoEnabled: false,
        // cl45：方块描边总开关（玩家 5 格内实描边 + 5~12 格极淡渐隐）。
        outlineEnabled: ref.read(outlineEnabledProvider),
        skyGradient: true,
        // 用户确认（性能优化：面剔除）：开启区块朝向减面（allowMask 侧面剔除）
        // ——配合 cl30 迟滞持久化（跨帧复用旧 mask，消除旋转 popping）与
        // `!camera.fullWidth` 守卫（俯瞰/2.5D 全图不受影响）。远处侧壁面由
        // 方位 dot 阈值裁掉，近处全保留；面数显著下降（用户「森林面数太多」）。
        lodFaceCull: ref.read(faceCullEnabledProvider),
      );

  void _setQuality(GraphicsQuality q) {
    if (_quality == q) return;
    _quality = q;
    // R26p：画质档切换 → 把其内置的视距/LOD 子参数写回共享 provider，
    // 使首页「游戏画面」页的滑块与游戏内状态始终一致（修复「参数不同步」）。
    // provider 变更由 settings_persistence_providers 的 listener 自动落盘。
    ref.read(viewDistanceChunksProvider.notifier).state =
        q.viewDistanceChunks.clamp(2, 4); // cl76_hotfix2：视距上限 4
    ref.read(lodStartChunksProvider.notifier).state =
        q.lodStartChunks.clamp(0, 6);
    ref.read(lodStepChunksProvider.notifier).state =
        q.lodStepChunks.clamp(1, 4);
    // cl76：LOD 最远区块随档位写回（省电 2 / 流畅 4 / 地平线 28 / 自动 4）。
    ref.read(lodMaxChunksProvider.notifier).state =
        q.lodMaxChunks.clamp(2, 64);
    // cl76_hotfix2：自动档重置监测基线（视距 4 / LOD 4，下次 10s 窗口重新采样）。
    if (q == GraphicsQuality.auto) {
      _autoViewChunks = q.viewDistanceChunks;
      _autoLodChunks = q.lodMaxChunks;
      _autoWindowStart = Duration.zero;
      _autoFrames = 0;
    }
    _config = _configFor(q);
    _minRebuildInterval = _minIntervalFor(q); // cl30：重建限频随档位调整
    _dirty = true;
    _staticPicture = null; // R26f：画质切换 → 静态快照失效
    setState(() {});
  }

  void _onJoystick(Offset v) {
    _joyX = v.dx;
    _joyY = v.dy;
    _idle = 0;
  }

  // ── R26o：第三人称摄像机环绕（另一摇杆控制，一键复原）────────
  void _onTpCamJoy(Offset v) {
    _tpCamYaw += v.dx * 0.018;
    _tpCamPitch = (_tpCamPitch - v.dy * 0.018).clamp(-0.35, 1.25);
    _dirty = true;
  }

  void _resetTpCam() {
    setState(() {
      _tpCamYaw = 0;
      _tpCamPitch = 0.227; // 默认身后 4 格、上方 2.5 格
      _tpCamDist = 4.0;
    });
    _dirty = true;
  }

  void _toggleBag() => setState(() {
        // Cl29_hotfix：关闭背包时把光标（手持）物品归还，避免悬空。
        if (_bagOpen) _inv.returnCursor();
        _bagOpen = !_bagOpen;
      });

  // ── HUD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // #170：世界空间音效音量 / 主音量变化即时下发到引擎（引擎在本视图内持有）
    ref.listen<double>(worldSfxVolumeProvider,
        (_, __) => _audio?.setGlobalVolume(_worldAudioGain()));
    ref.listen<double>(masterVolumeProvider,
        (_, __) => _audio?.setGlobalVolume(_worldAudioGain()));
    // R26p：世界音效开关即时生效——之前只 init 读一次，菜单里开关只改状态
    // 不调 _syncAudio()，故开关「没绑定好」。此处补 live 监听（启动/停止引擎）。
    ref.listen<bool>(worldAudioEnabledProvider, (_, bool v) {
      if (!mounted) return;
      _audioEnabled = v;
      _syncAudio();
    });
    // R26c：游戏中快捷设置改画质档 → 同步渲染配置（ref.listen 须在 build）。
    ref.listen<GraphicsQuality>(graphicsQualityProvider,
        (GraphicsQuality? prev, GraphicsQuality next) {
      if (prev != next && mounted) _setQuality(next);
    });
    // R26i：可见度（视距）独立可调 → 改后同步渲染配置并重绘。
    // R26m：监听持久化的 viewDistanceChunksProvider（首页设置同源）。
    ref.listen<int>(viewDistanceChunksProvider, (_, __) {
      if (!mounted) return;
      _config = _configFor(_quality);
      _dirty = true;
      _staticPicture = null; // 视距变化 → 静态快照失效
    });
    // R26p2：云层区块视距独立可调 → 改后同步渲染配置并重绘。
    ref.listen<int>(cloudViewDistanceProvider, (_, __) {
      if (!mounted) return;
      _config = _configFor(_quality);
      _dirty = true;
      _staticPicture = null; // 云层视距变化 → 静态快照失效
    });
    // R26d：HUD 布局变化自动持久化到 prefs。
    ref.listen<Map<String, Offset>>(hudLayoutProvider, (prev, next) {
      if (prev == next) return;
      unawaited(saveHudLayout(ref.read(prefsProvider), next));
    });
    // R26x：HUD 缩放持久化（变更即落盘）。
    ref.listen<double>(hudScaleProvider, (prev, next) {
      if (prev == next) return;
      unawaited(saveHudScale(ref.read(prefsProvider), next));
    });

    final bool fp = _viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson;
    final List<Widget> controls = <Widget>[];

    // 顶部控制条
    controls.add(
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: AppSpace.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  // R26h：顶部居中信息条（世界名 · 存档时间 · 游戏时长）
                  _WorldInfoBar(
                    seedTag: _seedTag,
                    lastSavedAt: _lastSavedAt,
                    sessionStart: _sessionStart,
                  ),
                  const SizedBox(height: 6),
                  // R26h：顶栏只保留「菜单 / 视角 / 相机 / 存档 / 设置 / 时间」，
                  // 其余次级控制（坐标 / 模式 / 自动跳 / 画质 / 沉浸）收进折叠面板。
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      // R26fx：折叠菜单改名「更多」（原「菜单」）。
                      _ToggleChip(
                        icon: Icons.menu,
                        label: '更多',
                        active: _foldOpen,
                        onTap: () => setState(() => _foldOpen = !_foldOpen),
                      ),
                      // 视角切换：独立按钮组件，点击触发 _cycleViewMode。
                      ViewModeButton(
                        onPressed: _cycleViewMode,
                        label: _viewModeLabel(),
                        tooltip: '切换视角',
                        semanticsLabel: '切换视角，当前${_viewModeLabel()}',
                        active: _viewMode != _ViewMode.orbit,
                      ),
                      // R26fx：顶栏整理——相机/存档收进折叠菜单，顶栏只留
                      // 菜单 / 视角 / 暂停 / 设置 / 时钟（信息合并、简化）。
                      // H1r2：游戏菜单（默认暂停整个世界）
                      _ToggleChip(
                        icon: _paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        label: _paused ? '继续' : '菜单',
                        active: _paused,
                        onTap: () => _setPaused(!_paused),
                      ),
                      // R26skel：游戏设置已移入菜单（暂停 → 菜单 → 游戏设置）。
                      ValueListenableBuilder<String>(
                        valueListenable: _clockText,
                        builder: (BuildContext c, String s, Widget? _) =>
                            _ClockChip(text: s),
                      ),
                    ],
                  ),
                  // ⑨：游戏内顶部居中液态玻璃播放器。
                  // 关键：作为顶栏 Column 的子项而非固定 top——顶栏 chips 在窄屏
                  // 会折行（见 P2 注释：固定 top:66 曾压住第二行 chips），放进
                  // Column 后播放器随折行自然下移，任何屏宽都不可能重叠；
                  // crossAxisAlignment.center 天然居中，maxWidth 560 由播放器自带。
                  // 交互：下拉箭头展开/收起，点信息区进沉浸卡片（带歌词，
                  // 搜索/音质已并入卡片，默认音量收起）。
                  if (_started) ...<Widget>[
                    const SizedBox(height: 6),
                    UnifiedPlayer(
                      lyricsSlot: const LyricsView(),
                    ),
                  ],
                ],
              ),
          ),
        ),
      ),
    );

    // R26h：折叠面板（坐标 / 模式 / 自动跳 / 画质 / 沉浸），开合时显示在顶栏下方。
    // P2（用户确认）：改用可拖拽 _HudWrap——固定 top:66 在窄屏顶栏折行时会
    // 压住第二行 chips（UI 重叠）。拖拽 HUD 位置持久化，任何屏宽都不重叠。
    if (_foldOpen)
      controls.add(
        _HudWrap(
          id: HudIds.foldPanel,
          defaultPos: const Offset(0.02, 0.14),
          child: _FoldPanel(
            showCoords: _showCoords,
            onToggleCoords: () => setState(() => _showCoords = !_showCoords),
            survival: _survival,
            onToggleSurvival: _toggleSurvival,
            onOpenCamera: () => setState(() => _cameraMode = !_cameraMode),
            autoJump: _autoJump,
            onToggleAutoJump: () => setState(() => _autoJump = !_autoJump),
            uiCollapsed: _uiCollapsed,
            onToggleUiCollapsed: () =>
                setState(() => _uiCollapsed = !_uiCollapsed),
            // R26fl：手电筒模式（FOV 不变窄锥剔除 + 边界黑化 + 泛光）。
            flashlight: ref.watch(flashlightEnabledProvider),
            onToggleFlashlight: () => ref
                .read(flashlightEnabledProvider.notifier)
                .state = !ref.read(flashlightEnabledProvider),
            // R26x：HUD 大小（摇杆 / 动作键缩放）。
            hudScale: ref.watch(hudScaleProvider),
            onHudScale: (double v) =>
                ref.read(hudScaleProvider.notifier).state = v,
            // H4：脱离卡死（卡进方块/悬崖时一键脱出）。
            onUnstick: _unstick,
            // H2：场景拍摄（机位 + 16×16 音效 → 独立场景记录）。
            onCaptureScene: _captureScene,
            onClose: () => setState(() => _foldOpen = false),
          ),
        ),
      );

    // G9：联机 HUD（同伴列表 + 一起听 + 离开），仅联机模式显示。
    if (widget.multiplayer) controls.add(_buildMultiplayerHud());

    // 坐标 HUD（第一人称，R26d：位置可自定义）
    if (fp && _showCoords)
      controls.add(
        _HudWrap(
          id: HudIds.coords,
          defaultPos: const Offset(0.02, 0.075),
          child: ValueListenableBuilder<String>(
            valueListenable: _coordsText,
            builder: (BuildContext c, String s, Widget? _) => Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x66000000),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                s,
                style: const TextStyle(
                  color: Color(0xFFF2F5FA),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),
      );

    // 左侧：FP/TP 摇杆；观景 LiftPad（R26d：位置可自定义）
    if (_started)
      controls.add(
        _HudWrap(
          id: HudIds.joystick,
          defaultPos: const Offset(0.02, 0.83),
          // R26n：去掉 LiftPad 上下箭头（用户「把左边上下箭头删了」）——
          // 第一/第三人称统一用摇杆移动；创造升降改由右侧「上升」按钮 + Shift。
          child: _Joystick(
            onChanged: _onJoystick,
            // R26fix：HUD 编辑模式（hudEditProvider）下手势让位给外层 _HudWrap
            // 拖动 → 「移动键可拖动位置」。
            enabled: !ref.watch(hudEditProvider),
          ),
        ),
      );

    // R26skel-b3：动作键拆 4 个**独立**元素（攻击/放置/蹲/跳 各自可拖拽调位），
    // 不再连成一体——布局编辑模式（hudEditProvider）下可自由分开摆放。
    // 默认右下锚定 2×2 网格；旧「actions」整体簇位置（如有）作迁移锚点，
    // 保证老用户已有布局不跳变。
    if (_started && fp && !_cameraMode) {
      final Size vs = MediaQuery.of(context).size;
      const double kBtn = 72, kGap = 10, kMargin = 16;
      final double cell = kBtn + kGap;
      final double gridW = kBtn * 2 + kGap;
      final double gridH = kBtn * 2 + kGap;
      double nx(double px) => px / vs.width;
      double ny(double py) => py / vs.height;
      final Offset? oldAnchor =
          ref.watch(hudLayoutProvider)[HudIds.actions];
      final Offset anchor = oldAnchor ??
          Offset(
              nx(vs.width - kMargin - gridW), ny(vs.height - kMargin - gridH));
      final Offset dPlace = Offset(anchor.dx + nx(cell), anchor.dy);
      final Offset dDuck = Offset(anchor.dx, anchor.dy + ny(cell));
      final Offset dJump =
          Offset(anchor.dx + nx(cell), anchor.dy + ny(cell));
      controls
        ..add(_HudWrap(
          id: HudIds.actBreak,
          defaultPos: anchor,
          child: _BigActionButton(
            icon: Icons.flash_on_rounded,
            label: '攻击',
            // R26fx3：破坏/攻击合并（一个键：先攻后挖，生存创造都能挖）。
            onPress: () {
              _primaryAction();
              _acting = true;
              _dirty = true;
            },
            onRelease: () {
              _acting = false;
              _resetMining();
              _dirty = true;
            },
          ),
        ))
        ..add(_HudWrap(
          id: HudIds.actPlace,
          defaultPos: dPlace,
          child: _BigActionButton(
            icon: Icons.add_box_rounded,
            label: '放置',
            // R26fx3：放置/使用合并（手持食物=吃，方块=放置）。
            onPress: _placeAt,
            onRelease: () {},
          ),
        ))
        ..add(_HudWrap(
          id: HudIds.actDuck,
          defaultPos: dDuck,
          child: _BigActionButton(
            icon: Icons.keyboard_arrow_down_rounded,
            label: _flyMode ? '降' : '蹲',
            // 蹲/降：飞行中 = 下降，地面 = 蹲下。
            onPress: () => setState(() {
              if (_flyMode) {
                _held.add(_Nav.down);
              } else {
                _crouching = true;
              }
            }),
            onRelease: () => setState(() {
              if (_flyMode) {
                _held.remove(_Nav.down);
              } else {
                _crouching = false;
              }
            }),
          ),
        ))
        ..add(_HudWrap(
          id: HudIds.actJump,
          defaultPos: dJump,
          child: _BigActionButton(
            icon: Icons.arrow_upward_rounded,
            label: _submerged
                ? '游↑'
                : (_survival ? '跳' : (_flyMode ? '升' : '跳')),
            onPress: _onJumpButtonDown,
            onRelease: _onJumpButtonUp,
          ),
        ));
    }

    // R26o：第三人称「环绕」摄像机摇杆（另一摇杆控制相机环绕玩家）+ 一键复原。
    if (_started &&
        fp &&
        _viewMode == _ViewMode.thirdPerson &&
        !_cameraMode)
      controls.add(
        _HudWrap(
          id: 'tpCamOrbit',
          defaultPos: const Offset(0.82, 0.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('环绕',
                  style: TextStyle(color: Color(0xFFF2F5FA), fontSize: 11)),
              const SizedBox(height: 4),
              _Joystick(onChanged: _onTpCamJoy),
              const SizedBox(height: 6),
              _GlassCircleButton(
                icon: Icons.center_focus_strong,
                onTap: _resetTpCam,
              ),
            ],
          ),
        ),
      );

    // 底部居中：生命/饱食度（上）+ 物品栏（下）
    if (_started)
      controls.add(
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSpace.md,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_survival && (_oxygen < 0.999 || _submerged))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  // cl28 氧气条：仅水下或未满时显示（满氧且出水则隐藏，对齐 MC HUD）。
                  child: ValueListenableBuilder<double>(
                    valueListenable: _oxygenNotifier,
                    builder: (BuildContext context, double oxy, Widget? _) =>
                        SizedBox(
                      width: 190,
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.water_drop_rounded,
                              size: 14, color: Color(0xFF5BD6FF)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: oxy,
                                minHeight: 6,
                                backgroundColor: const Color(0x66000000),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF5BD6FF),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_survival)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: VoxelVitalsHud(vitals: _vitals),
                ),
              Center(
                child: VoxelHotbar(
                  inventory: _inv,
                  onSelect: _selectSlot,
                  onOpenBag: _toggleBag,
                  survival: _survival,
                  onToggleSurvival: _toggleSurvival,
                ),
              ),
            ],
          ),
        ),
      );

    // 相机面板
    if (_cameraMode)
      controls.add(
        Positioned(
          top: 56,
          right: AppSpace.md,
          child: _CameraPanel(
            fov: _camera.fov,
            onFov: _setFov,
            onShutter: _capture,
            onGallery: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PhotoGalleryPage()),
            ),
            onCaptureScene: _captureScene,
            onClose: () => setState(() => _cameraMode = false),
          ),
        ),
      );

    // 背包面板（Cl29_hotfix：完整 3×9 背包 + 1×9 物品栏，MC 式点选交互）
    if (_bagOpen)
      controls.add(
        Positioned.fill(
          child: VoxelInventoryPanel(
            inventory: _inv,
            hasTable: _hasTable,
            onClose: _toggleBag,
            onCraft: _craft,
          ),
        ),
      );

    // 折叠态：仅留展开按钮
    if (_uiCollapsed) {
      controls
        ..clear()
        ..add(
          Positioned(
            right: AppSpace.md,
            bottom: AppSpace.md,
            child: _GlassCircleButton(
              icon: Icons.fullscreen,
              onTap: () => setState(() => _uiCollapsed = false),
            ),
          ),
        );
    }

    // G9：断线覆盖层——连接丢失（status==error）时居中提示并引导返回大厅；
    // 置于折叠态 clear 之后，确保即便 UI 折叠也可见。仅联机模式。
    if (widget.multiplayer) controls.add(_buildDisconnectOverlay());

    // R26 修复：_viewport 此前从未被赋值（恒为 Size.zero），导致 _onTick 里
    // `_viewport.isEmpty` 永远为 true → buildFrame 永不执行 → 帧恒为 empty，
    // 画面只剩天空+云（用户反馈「3D 渲染不出来 / 天空盒盖在前面」的根因）。
    // 用 LayoutBuilder 从实际布局约束取视口尺寸（与 2.5D 画布页同模式）。
    // R26b：外层包 Focus 绑定键盘（_onKey 此前从未被任何 widget 引用 →
    // WASD/方向键/空格/Shift 全失效，玩家完全无法移动/跳跃/蹲）。
    // R26m：光标保持可见——隐藏 + 无平台鼠标捕获会让视角转到窗口边缘就
    // "卡死"、体感像"转不动/绑错了"（用户反馈）。相对移动 + 边缘续转
    // （见 _applyEdgeLook）实现无需插件的 FPS 视角；Alt 仍可暂停视角。
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: _onWorldPop,
      child: Focus(
      onKeyEvent: _onKey,
      autofocus: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _viewport = constraints.biggest;
          return SizedBox.expand(
            child: Stack(
              children: <Widget>[
            Positioned.fill(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                // R26k：桌面鼠标绑定——移动视角 / 左键挖掘 / 右键放置。
                // 控件（摇杆/动作键/顶栏胶囊）在 Stack 上层先命中，不受影响。
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                child: GestureDetector(
                  // 独立触控区：单指拖动环视；双指捏合 / 滚轮调焦距（FOV）。
                  // 按钮（Joystick/动作键/顶栏胶囊）在其上以 opaque 命中，互不误触。
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: RepaintBoundary(
                  key: _captureKey,
                  child: ValueListenableBuilder<VoxelFrame>(
                    valueListenable: _frame,
                    builder: (BuildContext c, VoxelFrame frame, Widget? _) =>
                        CustomPaint(
                          painter: _VoxelFramePainter(
                            frame,
                            _quality.texture ? _atlas : null,
                            staticPicture: _staticPicture,
                            // R26fx：渲染分辨率 × 渲染比例 × 动态缩放（倍率式）。
                            renderScale: _quality.renderScale *
                                ref.watch(renderPrecisionScaleProvider) *
                                _frameDynScale,
                            // F4：水下滤镜——眼睛没入水中时叠加蓝色调。
                            underwater:
                                _submerged && ref.watch(underwaterFilterEnabledProvider),
                            // R26fl：手电筒模式——锥内泛光光晕 + 四周暗角。
                            flashlight: ref.watch(flashlightEnabledProvider),
                          ),
                          child: const SizedBox.expand(),
                        ),
                  ),
                ),
              ),
            ),
          ),
            if (_showAim)
              Positioned.fill(
                // 纯视觉叠层：CustomPaint 默认命中（painter 非空且无 child →
                // RenderCustomPaint.hitTestSelf 返回 true）会吃掉下方 3D 画布的
                // 拖拽/缩放事件，导致「视角不能滑动」。IgnorePointer 放行到画布。
                child: IgnorePointer(
                  child: CustomPaint(painter: _AimBoxPainter(this)),
                ),
              ),
            if (fp)
              Positioned.fill(
                // 同上：准星纯视觉，必须 IgnorePointer，否则吞掉拖拽事件。
                child: IgnorePointer(
                  child: CustomPaint(painter: _CrosshairPainter()),
                ),
              ),
            if (fp)
              // R29：准星所指方块名（单一事实源 = VoxelSpec.displayName）。
              // 直接「标明方块名称」，与背包标签同源，无需另维护一份映射。
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<(int, int, int)?>(
                    valueListenable: _aimNotifier,
                    builder: (
                      BuildContext c,
                      (int, int, int)? block,
                      Widget? _,
                    ) {
                      if (block == null) return const SizedBox.shrink();
                      final Voxel v =
                          widget.world.get(block.$1, block.$2, block.$3);
                      if (v.isEmpty) return const SizedBox.shrink();
                      return Align(
                        alignment: const Alignment(0, 0.055),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xAA0A1018),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            v.spec.displayName,
                            style: const TextStyle(
                              color: Color(0xFFEFF3FA),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              shadows: <Shadow>[
                                Shadow(blurRadius: 3, color: Color(0xCC000000)),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (fp)
              Positioned.fill(
                // 同上：挖掘裂纹纯视觉叠层，必须 IgnorePointer，否则吞掉画布的
                // 拖拽/缩放事件，导致「视角不能滑动」。
                child: IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _crackNotifier,
                    builder: (BuildContext c, double _, Widget? __) =>
                        CustomPaint(painter: _CrackPainter(_crackNotifier)),
                  ),
                ),
              ),
            // H1r2：游戏菜单（默认暂停整个世界）——继续游戏 / 恢复存档 /
            // 开放世界 / 保存退出。
            if (_paused && _started)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0x99000000),
                  child: Center(
                    child: _PauseMenu(
                      onResume: () => _setPaused(false),
                      // R26fx：第二项「我的存档」（合并 手动存档 + 恢复备份 + 详情）。
                      onRestore: _openMySaves,
                      onOpenWorld: () => _snack('开放世界（联机）开发中，敬请期待'),
                      // R26skel：游戏设置（原顶栏「设置」）移入菜单——
                      // 打开全局设置页「游戏」合集（唯一入口，不再独立弹窗）。
                      onOpenSettings: _openGlobalGameSettings,
                      onSaveExit: _saveAndExit,
                    ),
                  ),
                ),
              ),
            ...controls,
          ],
        ),
        );
        },
      ),
      ),
      ),
    );
  }

  // ── G9：联机 HUD / 断线覆盖层 ──────────────────────────

  /// 离开联机会话并返回大厅（遵循 PopScope 闸门，确保真正 pop）。
  void _leaveSession() {
    ref.read(netSessionProvider.notifier).leave();
    if (!mounted) return;
    _allowPop = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// 世界内联机 HUD：角色 / 房主地址 / 同伴列表 / 一起听状态 / 离开按钮。
  Widget _buildMultiplayerHud() {
    final NetSessionState net = ref.watch(netSessionProvider);
    final bool isHost = net.role == NetRole.host;
    final String roleLabel = isHost ? '房主' : '玩家';
    final String addr = isHost
        ? (net.port != null ? '本机 · 端口 ${net.port}' : '本机')
        : (net.hostIp != null
            ? '${net.hostIp}${net.port != null ? ':' + net.port.toString() : ''}'
            : '连接中…');
    final List<PeerInfo> peers = net.peers;
    final String peerText = peers.isEmpty
        ? '暂无同伴'
        : '同伴 ${peers.length}：${peers.map((p) => p.name).join('、')}';
    return Positioned(
      left: AppSpace.md,
      top: 56,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xAA0A1018),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.group, size: 16, color: Color(0xFF7CC8FF)),
                const SizedBox(width: 6),
                Text(roleLabel,
                    style: const TextStyle(
                        color: Color(0xFFEFF3FA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(addr,
                    style: const TextStyle(
                        color: Color(0x99F2F5FA),
                        fontSize: 11,
                        fontFamily: 'monospace')),
              ],
            ),
            const SizedBox(height: 4),
            Text(peerText,
                style: const TextStyle(color: Color(0xCCF2F5FA), fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.music_note, size: 14, color: Color(0xFFFFD66B)),
                const SizedBox(width: 4),
                Text(isHost ? '一起听 · 你为 DJ' : '一起听 · 跟随房主',
                    style: const TextStyle(
                        color: Color(0xCCFFF2DA), fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _leaveSession,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5484D),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('离开联机',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 断线覆盖层：连接丢失时提示。
  /// - [ConnStatus.reconnecting]：非致命「重连中…」覆盖层（带进度圈 + 第 N 次
  ///   尝试），世界继续渲染，可手动返回大厅放弃；
  /// - [ConnStatus.error]：致命「连接已断开」，引导返回大厅。
  Widget _buildDisconnectOverlay() {
    final NetSessionState net = ref.watch(netSessionProvider);
    if (net.status != ConnStatus.reconnecting &&
        net.status != ConnStatus.error) {
      return const SizedBox.shrink();
    }
    final bool reconnecting = net.status == ConnStatus.reconnecting;
    final String title = reconnecting ? '重连中…' : '连接已断开';
    final String sub = reconnecting
        ? '正在尝试重新连接（第 ${net.reconnectAttempt} 次）\n稍候即可恢复联机'
        : (net.error ?? '与房主的连接已丢失');
    final Color iconColor =
        reconnecting ? const Color(0xFF7CC8FF) : const Color(0xFFFF6B6B);
    return Positioned.fill(
      child: Container(
        color: const Color(0xCC000000),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2230),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (reconnecting)
                  const SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF7CC8FF)),
                    ),
                  )
                else
                  Icon(Icons.wifi_off, size: 48, color: iconColor),
                const SizedBox(height: 16),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(sub,
                    style: const TextStyle(
                        color: Color(0xCCF2F5FA), fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _leaveSession,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F7CFF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('返回大厅',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}   // ← 关闭 _VoxelWorldView3DState

/// R24c: 体素帧画家：消费 [VoxelFrame]，按图集分流纯色/贴图；画家算法单桶（先不透明后半透明，根治水穿透）。
class _VoxelFramePainter extends CustomPainter {
  _VoxelFramePainter(
    this.frame,
    this.atlas, {
    this.staticPicture,
    this.renderScale = 1.0,
    this.underwater = false,
    this.flashlight = false,
  });
  final VoxelFrame frame;
  final ui.Image? atlas;

  /// F4：眼睛没入水中时叠加水下蓝色滤镜（在 [paint] 尾部绘制）。
  final bool underwater;

  /// R26fl：手电筒模式——锥内泛光光晕 + 四周暗角（paint 尾部叠加）。
  final bool flashlight;

  /// R26f：静态快照（相机静止 ≥1.5s 录制的整帧 Picture）。
  /// 非空时直接 drawPicture 跳过全部绘制逻辑（挂机/观景 CPU -90%）。
  final ui.Picture? staticPicture;

  /// R26o：渲染分辨率倍率。帧坐标按 renderScale 倍视口算出，绘制时放大
  /// 1/renderScale 铺满全屏（性能档 0.5 = 半分辨率 + 放大，帧率翻倍）。
  final double renderScale;

  late final ui.ImageShader? _shader = atlas == null
      ? null
      : ui.ImageShader(
          atlas!,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          Float64List.fromList(<double>[
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
          ]),
        );

  late final Paint _texPaint = Paint()
    ..blendMode = ui.BlendMode.srcOver
    // R26 修复：图集异步构建完成前 / 失败时 shader 为 null，此时若 Paint 用
    // 默认色（不透明黑）会把「贴图批次」整体画成黑色（用户反馈「默认画质下
    // 全部方块黑色」）。回退为白色 → 顶点色（tint 明暗）直接透出 = 纯色地形，
    // 图集就绪后自动恢复正常贴图。
    ..color = const Color(0xFFFFFFFF)
    ..shader = _shader;

  late final Paint _plainPaint = Paint()..blendMode = ui.BlendMode.srcOver;

  @override
  void paint(Canvas canvas, Size size) {
    // R26f：静态快照命中 → 整帧直接播放，跳过天空/天象/批次全部绘制。
    final ui.Picture? pic = staticPicture;
    if (pic != null) {
      canvas.drawPicture(pic);
      // G9：名字标签即便静态快照也实时绘制（HUD 应始终可见，不随场景冻结）。
      if (frame.nameLabels.isNotEmpty) _drawNameLabels(canvas);
      return;
    }
    final SkyPalette sky = frame.sky;
    // R26o：低分辨率渲染——整帧画在 renderScale 倍空间再放大铺满全屏。
    canvas.save();
    canvas.scale(1.0 / renderScale);
    final Size fs = Size(size.width * renderScale, size.height * renderScale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, fs.width, fs.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, fs.height),
          <Color>[sky.zenith, sky.horizon],
        ),
    );
    _drawSkyDecor(canvas, fs);
    // R25：批量网格优先（每材质按深度桶 1 次 drawVertices，GPU 加速）；
    // 占位空帧（所有桶为空）回退逐面绘制。
    if (frame.opaquePlainBuckets.any((b) => b != null) ||
        frame.opaqueTexturedBuckets.any((b) => b != null) ||
        frame.waterBuckets.any((b) => b != null)) {
      _drawBatched(canvas);
    } else {
      final bool textured = _shader != null;
      _drawFaces(canvas, frame.opaque, textured);
      _drawFaces(canvas, frame.translucent, textured);
    }
    // F4（用户确认）：水下滤镜——全屏蓝色调 + 顶部轻微暗角（浸水视觉），
    // 抵消「水下没有滤镜和光照很难受」；配合画面前的水雾/波光更自然。
    if (underwater) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fs.width, fs.height),
        Paint()
          ..color = const Color(0x502A6FA8) // 半透明海水蓝
          ..blendMode = ui.BlendMode.srcOver,
      );
      // 顶部暗角（水面近处更暗，模拟阳光透入衰减）。
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fs.width, fs.height * 0.35),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, 0),
            Offset(0, fs.height * 0.35),
            <Color>[const Color(0x55001030), const Color(0x00001030)],
          ),
      );
    }
    // R26fl：手电筒泛光——锥中心暖白光斑（blur 泛光）+ 四周暗角（黑化滤镜）。
    if (flashlight) {
      final Offset glowCenter = Offset(fs.width / 2, fs.height * 0.42);
      canvas.drawCircle(
        glowCenter,
        fs.width * 0.58,
        Paint()
          ..shader = ui.Gradient.radial(
            glowCenter,
            fs.width * 0.58,
            <Color>[const Color(0x5EFFF3C4), const Color(0x00FFF3C4)],
          )
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 24),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, fs.width, fs.height),
        Paint()
          ..shader = ui.Gradient.radial(
            glowCenter,
            fs.width * 0.68,
            <Color>[const Color(0x00000000), const Color(0x99000000)],
            <double>[0.52, 1.0],
          ),
      );
    }
    // G9：联机远端玩家名字标签——画在最上层（玩家名字永远清晰可见），
    // 坐标由相机投影得到（scaled 空间，与太阳月亮同坐标系）。
    if (frame.nameLabels.isNotEmpty) _drawNameLabels(canvas);
    canvas.restore();
  }

  /// R25：批量提交。地形面 / 水面 / 描边按相机深度 8 桶（远→近）逐桶交错提交，
  /// 每桶内 不透明纯色 → 贴图 → 水面 → 描边，确保画家算法正确（无透视/穿墙）。
  void _drawBatched(Canvas canvas) {
    final VoxelFrame f = frame;
    // R26q：画家算法——远→近绘制。桶索引 bkt=(depth/far*8)：桶 7=最远、桶 0=最近。
    // 必须先画远桶(7)、后画近桶(0)，近面才能盖住远面，消除「透视/穿墙」。
    // 原循环 for(i=0..7) 是「先近后远」，远面盖在近面上 = 典型的 x-ray，已反转。
    for (int i = 7; i >= 0; i--) {
      final VoxelMeshBatch? plain = f.opaquePlainBuckets[i];
      if (plain != null) {
        canvas.drawVertices(
          ui.Vertices.raw(
            ui.VertexMode.triangles,
            plain.positions,
            colors: plain.colors,
          ),
          ui.BlendMode.srcOver,
          _plainPaint,
        );
      }
      final VoxelMeshBatch? tex = f.opaqueTexturedBuckets[i];
      if (tex != null) {
        canvas.drawVertices(
          ui.Vertices.raw(
            ui.VertexMode.triangles,
            tex.positions,
            colors: tex.colors,
            textureCoordinates: tex.uv,
          ),
          ui.BlendMode.srcOver,
          _texPaint,
        );
      }
      final VoxelMeshBatch? water = f.waterBuckets[i];
      if (water != null) {
        canvas.drawVertices(
          ui.Vertices.raw(
            ui.VertexMode.triangles,
            water.positions,
            colors: water.colors,
            textureCoordinates: water.uv,
          ),
          ui.BlendMode.srcOver,
          _texPaint,
        );
      }
    }
  }

  /// 太阳 + 月亮（天象层）：画在天空渐变之上、地形之下。
  /// 坐标来自 [VoxelFrame.sunSX/sunSY] 等——由相机投影得到（真实 3D 天象，
  /// 转视角时随世界移动，不是屏幕固定）；落在相机后方/地平线下时
  /// [VoxelFrame.sunVisible]/[VoxelFrame.moonVisible]=false，不绘制。
  void _drawSkyDecor(Canvas canvas, Size size) {
    // 太阳（白天）。④：无极过渡（sw 平滑驱动透明度）+ 泛光（bloom）+ 镜头炫光
    // （lens flare），全部用 plus 叠加，低成本、无额外 pass。
    if (frame.sunVisible && frame.sunWeight > 0.04) {
      final double sx = frame.sunSX;
      final double sy = frame.sunSY;
      if (sy > -140 && sy < size.height + 140) {
        final double sw = frame.sunWeight.clamp(0.0, 1.0);
        final double a = sw.clamp(0.25, 1.0);
        final Offset c = Offset(sx, sy);
        final double r = 20 + sw * 16;
        // 泛光（bloom）：半径递增、透明度递减的多层光晕（plus 叠加）。
        const List<double> halos = <double>[1.8, 3.2, 5.5];
        const List<double> haloA = <double>[0.20, 0.10, 0.05];
        for (int i = 0; i < halos.length; i++) {
          canvas.drawCircle(
            c,
            r * halos[i],
            Paint()
              ..color = Color.fromARGB(
                  (255 * haloA[i] * a).round(), 255, 240, 200)
              ..blendMode = ui.BlendMode.plus,
          );
        }
        // 核心。
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..color = Color.fromARGB(
              (255 * a).round(), 255, (200 * sw).round() + 40, 120),
        );
        // 镜头炫光（lens flare）：沿「太阳 → 屏幕中心」铺一组低透明光斑。
        final Offset sc = Offset(size.width / 2, size.height / 2);
        final double dx = sc.dx - sx, dy = sc.dy - sy;
        const List<double> tF = <double>[0.15, 0.4, 0.62, 0.85, 1.15];
        const List<double> fr = <double>[1.2, 0.5, 1.6, 0.35, 0.9];
        const List<double> fa = <double>[0.10, 0.14, 0.07, 0.16, 0.05];
        for (int i = 0; i < tF.length; i++) {
          final Offset p = Offset(sx + dx * tF[i], sy + dy * tF[i]);
          if (p.dx < -90 || p.dx > size.width + 90 ||
              p.dy < -90 || p.dy > size.height + 90) continue;
          canvas.drawCircle(
            p,
            r * fr[i],
            Paint()
              ..color = Color.fromARGB(
                  (255 * fa[i] * a).round(), 255, 235, 190)
              ..blendMode = ui.BlendMode.plus,
          );
        }
      }
    }
    // 月亮（夜里，sunWeight 低时）。投影取 -sunDir，故夜间月亮在天顶附近。
    if (frame.moonVisible && frame.sunWeight < 0.5) {
      final double mx = frame.moonSX;
      final double my = frame.moonSY;
      if (my > -80 && my < size.height + 80) {
        canvas.drawCircle(
          Offset(mx, my),
          15,
          Paint()..color = const Color(0xFFE8ECF2),
        );
        canvas.drawCircle(
          Offset(mx, my),
          36,
          Paint()
            ..color = const Color(0x332C3350)
            ..blendMode = ui.BlendMode.screen,
        );
      }
    }
  }

  void _drawFaces(Canvas canvas, List<RenderFace> faces, bool textured) {
    for (final RenderFace f in faces) {
      final int c = textured
          ? (f.translucent
              ? (f.tint & 0x00FFFFFF) |
                  ((kWaterAlpha * 255).round().clamp(0, 255) << 24)
              : f.tint)
          : f.argb;
      final Int32List colors = Int32List.fromList(<int>[c, c, c, c]);
      if (textured && f.uv != null) {
        final ui.Vertices v = ui.Vertices.raw(
          ui.VertexMode.triangleFan,
          f.xy,
          textureCoordinates: f.uv!,
          colors: colors,
        );
        canvas.drawVertices(v, ui.BlendMode.srcOver, _texPaint);
      } else {
        final ui.Vertices v = ui.Vertices.raw(
          ui.VertexMode.triangleFan,
          f.xy,
          colors: colors,
        );
        canvas.drawVertices(v, ui.BlendMode.srcOver, _plainPaint);
      }
    }
  }

  /// G9：联机远端玩家名字标签——画在所有内容之上。坐标来自 [VoxelFrame]
  /// （相机投影的 scaled 空间，与太阳月亮同坐标系），转视角 / 远端移动时随世界
  /// 更新；落在相机后方时 buildFrame 不存储，此处仅画可见者。
  void _drawNameLabels(Canvas canvas) {
    for (final VoxelNameLabel lb in frame.nameLabels) {
      _drawNameTag(canvas, lb);
    }
  }

  void _drawNameTag(Canvas canvas, VoxelNameLabel lb) {
    // 设备字号恒定（scaled 空间绘制，乘 renderScale 抵消 1/renderScale 放大）。
    final double fontPx = 14 * renderScale;
    final ui.ParagraphBuilder pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center),
    )
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: fontPx,
        fontWeight: FontWeight.w600,
      ))
      ..addText(lb.text);
    final ui.Paragraph para = pb.build();
    para.layout(ui.ParagraphConstraints(width: 240 * renderScale));
    final double tw = para.width;
    final double th = para.height;
    // 标签中心对齐头顶投影点，略上移避免压住头部。
    final Offset c = Offset(lb.sx, lb.sy - th * 0.5 - 6 * renderScale);
    final RRect bg = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: c,
        width: tw + 14 * renderScale,
        height: th + 8 * renderScale,
      ),
      Radius.circular(8 * renderScale),
    );
    canvas.drawRRect(bg, Paint()..color = lb.color.withValues(alpha: 0.85));
    canvas.drawParagraph(para, Offset(c.dx - tw / 2, c.dy - th / 2));
  }

  @override
  bool shouldRepaint(covariant _VoxelFramePainter old) =>
      !identical(old.frame, frame) ||
      !identical(old.atlas, atlas) ||
      old.underwater != underwater;
}

/// R26d：可拖动 HUD 锚点。位置以归一化坐标存 [hudLayoutProvider]；
/// 布局编辑模式（[hudEditProvider]）下显示琥珀边框、可拖动，关闭自动保存。
/// 核心元素（退出 / 标题 / 底部物品栏 / 顶部控制条）不包此组件 = 锁定。
class _HudWrap extends ConsumerWidget {
  const _HudWrap({
    super.key,
    required this.id,
    required this.defaultPos,
    required this.child,
  });

  /// 元素 id（见 [HudIds]）。
  final String id;

  /// 默认归一化位置（0~1，相对视口），未自定义时使用。
  final Offset defaultPos;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool edit = ref.watch(hudEditProvider);
    final Offset pos = ref.watch(hudLayoutProvider)[id] ?? defaultPos;
    // R26x：HUD 整体缩放（摇杆 / 动作键大小）= 手动档位([hudScaleProvider])
    // × 屏幕自适应基准([hudResponsiveScale])——平板放大、小屏/竖屏缩小，
    // 解决「控件不随屏幕变化、竖屏杂乱」（游戏页布局修复 #1）。
    final double scale =
        ref.watch(hudScaleProvider) * hudResponsiveScale(context);
    // R26g 修复：此前用 LayoutBuilder 取尺寸再返回 Positioned——Positioned
    // 被包在 LayoutBuilder 子级里违反 ParentDataWidget（Positioned 必须直接
    // 挂在 Stack 下），进入世界（摇杆/动作键出现）即抛异常（用户「点生存
    // 后画面异常」的伴随 bug）。改用 MediaQuery 视口尺寸计算归一化位置，
    // 直接返回 Positioned（作为 Stack 的直接子级，合法）。
    final Size size = MediaQuery.of(context).size;
    final double left = pos.dx * size.width;
    final double top = pos.dy * size.height;
    final Widget content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: edit
          ? (DragUpdateDetails d) {
              final Offset np = Offset(
                (pos.dx + d.delta.dx / size.width).clamp(0.0, 0.92),
                (pos.dy + d.delta.dy / size.height).clamp(0.0, 0.92),
              );
              ref
                  .read(hudLayoutProvider.notifier)
                  .update((Map<String, Offset> m) => <String, Offset>{...m, id: np});
            }
          : null,
      child: Container(
        decoration: edit
            ? BoxDecoration(
                border: Border.all(color: const Color(0xFFFFC107)),
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Transform.scale(scale: scale, child: child),
      ),
    );
    return Positioned(left: left, top: top, child: content);
  }
}

/// 顶栏胶囊按钮。
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 自适应：按屏幕短边缩放内边距/图标/字号，竖屏小屏不拥挤、平板不袖珍。
    final double s = hudResponsiveScale(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
        constraints: BoxConstraints(minHeight: 32 * s),
        decoration: BoxDecoration(
          color: active
              ? context.appColors.accent.withValues(alpha: 0.55)
              : const Color(0x59000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x40FFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16 * s, color: const Color(0xFFF2F5FA)),
            SizedBox(width: 4 * s),
            Text(label,
                style: TextStyle(color: const Color(0xFFF2F5FA), fontSize: 12 * s)),
          ],
        ),
      ),
    );
  }
}

/// 时钟胶囊。
class _ClockChip extends StatelessWidget {
  const _ClockChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.access_time, size: 14, color: Color(0xFFF2F5FA)),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(color: Color(0xFFF2F5FA), fontSize: 12)),
        ],
      ),
    );
  }
}

/// R24c: Virtual joystick (replaces DPad). Drag outputs normalized Offset(dx,dy in [-1,1]); dy up = negative = forward.
class _Joystick extends StatefulWidget {
  const _Joystick({required this.onChanged, this.enabled = true});

  /// R26fix：HUD 编辑模式下手势让位给外层拖动（移动键可拖动位置）。
  final bool enabled;
  final void Function(Offset) onChanged;
  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  static const double _size = 120;
  static const double _radius = _size / 2;
  static const double _knob = 52;
  Offset _delta = Offset.zero;

  void _update(Offset local) {
    final Offset d = local - const Offset(_radius, _radius);
    final double dist = d.distance;
    final double max = _radius - _knob / 2;
    _delta = dist > max ? d * (max / dist) : d;
    setState(() {});
    widget.onChanged(Offset(
      (_delta.dx / max).clamp(-1.0, 1.0),
      (_delta.dy / max).clamp(-1.0, 1.0),
    ));
  }

  void _reset() {
    _delta = Offset.zero;
    setState(() {});
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: widget.enabled
          ? (DragStartDetails d) => _update(d.localPosition)
          : null,
      onPanUpdate: widget.enabled
          ? (DragUpdateDetails d) => _update(d.localPosition)
          : null,
      onPanEnd: widget.enabled ? (_) => _reset() : null,
      onPanCancel: widget.enabled ? _reset : null,
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.3),
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Stack(
          children: <Widget>[
            const Center(
              child: Icon(Icons.circle, size: 18, color: Color(0x55FFFFFF)),
            ),
            Positioned(
              left: _radius - _knob / 2 + _delta.dx,
              top: _radius - _knob / 2 + _delta.dy,
              child: Container(
                width: _knob,
                height: _knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.appColors.accent.withValues(alpha: 0.55),
                  border: Border.all(color: const Color(0xAAFFFFFF)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// R24c: Enlarged action button (place / mine-attack / jump). 64dp circle, icon + label, avoids UI overlap.
/// 支持两种触发：普通点击 [onTap]，或按住 [onPress]/[onRelease]（攻击键拖动连续破坏用）。
class _BigActionButton extends StatelessWidget {
  const _BigActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.onPress,
    this.onRelease,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onPress;
  final VoidCallback? onRelease;

  @override
  Widget build(BuildContext context) {
    final bool hold = onPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hold ? null : onTap,
      onTapDown: hold ? (_) => onPress?.call() : null,
      onTapUp: hold ? (_) => onRelease?.call() : null,
      onTapCancel: hold ? () => onRelease?.call() : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.appColors.accent.withValues(alpha: 0.32),
          border: Border.all(color: const Color(0x88FFFFFF)),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x44000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 26, color: const Color(0xFFF2F5FA)),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.caption.copyWith(color: const Color(0xFFF2F5FA), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
/// H1r2：游戏菜单（暂停面板）——打开即默认暂停整个世界。
/// 按钮：继续游戏 / 我的存档 / 开放世界 / 游戏设置 / 保存退出。
class _PauseMenu extends StatelessWidget {
  const _PauseMenu({
    required this.onResume,
    required this.onRestore,
    required this.onOpenWorld,
    required this.onOpenSettings,
    required this.onSaveExit,
  });

  final VoidCallback onResume;
  final VoidCallback onRestore;
  final VoidCallback onOpenWorld;
  final VoidCallback onOpenSettings;
  final VoidCallback onSaveExit;

  @override
  Widget build(BuildContext context) {
    const Color ink = Color(0xFFF2F5FA);
    final Color accent = context.appColors.accent;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: const Color(0x40FFFFFF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.pause_circle_outline, size: 20, color: ink),
              const SizedBox(width: 8),
              Text(
                '已暂停世界',
                style: AppTextStyles.subtitle.copyWith(color: ink),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            '游戏菜单 · 时间/物理/生物已全停',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: ink),
          ),
          const SizedBox(height: AppSpace.md),
          _PauseButton(
            icon: Icons.play_arrow_rounded,
            label: '继续游戏',
            accent: accent,
            ink: ink,
            onTap: onResume,
          ),
          _PauseButton(
            icon: Icons.inventory_2_outlined,
            label: '我的存档',
            accent: accent,
            ink: ink,
            onTap: onRestore,
          ),
          _PauseButton(
            icon: Icons.public_rounded,
            label: '开放世界',
            accent: accent,
            ink: ink,
            onTap: onOpenWorld,
          ),
          // R26skel：游戏设置收进菜单（原顶栏「设置」按钮移除）——
          // 与「设置」页「游戏」集合共享同一批 provider。
          _PauseButton(
            icon: Icons.tune_rounded,
            label: '游戏设置',
            accent: accent,
            ink: ink,
            onTap: onOpenSettings,
          ),
          _PauseButton(
            icon: Icons.save_alt_rounded,
            label: '保存退出',
            accent: accent,
            ink: ink,
            onTap: onSaveExit,
          ),
        ],
      ),
    );
  }
}

/// 游戏菜单行按钮。
class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    required this.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: const Color(0x2EFFFFFF)),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: ink),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(color: ink),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 升 / 降按钮（观景用，脱离地形）。
class _LiftPad extends StatelessWidget {
  const _LiftPad({required this.onPress, required this.onRelease});

  final void Function(_Nav) onPress;
  final void Function(_Nav) onRelease;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _HoldButton(
          icon: Icons.arrow_upward_rounded,
          nav: _Nav.up,
          onPress: onPress,
          onRelease: onRelease,
        ),
        const SizedBox(height: AppSpace.xs),
        _HoldButton(
          icon: Icons.arrow_downward_rounded,
          nav: _Nav.down,
          onPress: onPress,
          onRelease: onRelease,
        ),
      ],
    );
  }
}

/// 按住持续生效的圆形按钮（44dp 热区，沿用 accent 半透明语言）。
class _HoldButton extends StatelessWidget {
  const _HoldButton({
    required this.icon,
    required this.nav,
    required this.onPress,
    required this.onRelease,
  });

  final IconData icon;
  final _Nav nav;
  final void Function(_Nav) onPress;
  final void Function(_Nav) onRelease;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onPress(nav),
      onTapUp: (_) => onRelease(nav),
      onTapCancel: () => onRelease(nav),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.appColors.accent.withValues(alpha: 0.22),
          border: Border.all(
            color: const Color(0x66FFFFFF),
          ),
        ),
        child: Icon(icon, size: 24, color: const Color(0xFFF2F5FA)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// 全屏预览页
// ══════════════════════════════════════════════════════════════════════

/// 3D 体素世界全屏页（Phase 1 预览入口；H1r2：主菜单「新的世界/读取存档」进入）。
///
/// 顶栏：返回 · 标题 · 当前 seed 短哈希 · 「换个世界」（验证 seed 决定地形）。
class VoxelWorld3DPage extends StatefulWidget {
  const VoxelWorld3DPage({
    super.key,
    this.seed = VoxelWorld.defaultSeed,
    this.autoStart = true,
    this.survival = false,
    this.options,
    this.openCamera = false,
    this.initialSaveData,
    this.multiplayer = false,
  });

  final int seed;

  /// H1r2：进入即自动开始游玩（主菜单「新的世界」/ 读档恢复均 true）。
  final bool autoStart;

  /// H1r2：autoStart 时的模式（true=生存 / false=创造）。
  final bool survival;

  /// G9：联机模式（大厅进入时 true）。
  final bool multiplayer;

  /// cl29：新建世界选项（作弊 / 结构 / 浮空岛等）；null = 回落默认全开。
  final WorldOptions? options;

  /// cl29·②：进入即打开相机取景面板（场景页「拍照取景」入口用，
  /// 让相机功能从 Scene 模块直接可达，无需先在 3D 世界里找相机按钮）。
  final bool openCamera;

  /// R26fx：进入时恢复的存档数据（位置/视角/编辑层/背包；null = 全新世界）。
  final Map<String, dynamic>? initialSaveData;

  @override
  State<VoxelWorld3DPage> createState() => _VoxelWorld3DPageState();
}

class _VoxelWorld3DPageState extends State<VoxelWorld3DPage> {
  /// R26g：视图 State 桥（设置弹层里的「存档列表」入口需触达视图层的
  /// `_openSaveMenu`，用 GlobalKey 拿视图 State 动态调用）。
  final GlobalKey _viewKey = GlobalKey();
  late int _seed = widget.seed;
  late VoxelWorld _world =
      VoxelWorld(seed: _seed, options: widget.options ?? const WorldOptions());

  @override
  void initState() {
    super.initState();
    // cl46：自定义世界机制——全局偏移率（0~1）→ seed 偏移（0~65536），
    // 调整后新世界/新存档整体变化（地形/群系/结构随噪声偏移重排）。
    try {
      final double off = ProviderScope.containerOf(context)
          .read(worldGenOffsetProvider);
      if (off != 0) {
        _seed = widget.seed + (off * 65536).round();
      }
    } catch (_) {
      // provider 不可用（测试等）时忽略，保持原 seed。
    }
  }

  /// 子视图外送的当前机位（拍照取景用）。
  late final ValueNotifier<VoxelCamera> _cameraOut =
      ValueNotifier<VoxelCamera>(VoxelCamera.overview(_world));

  @override
  void dispose() {
    _cameraOut.dispose();
    super.dispose();
  }

  // R26h：_openQuickSettings 已迁入内部 _VoxelWorldView3DState（顶栏「设置」
  // 按钮直接调用；存档列表入口改为直接调用本类的 _openSaveMenu，去掉 _viewKey 中转）。

  String get _seedTag =>
      '#${(_seed & 0xffff).toRadixString(16).toUpperCase().padLeft(4, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      // ⚠️ 必须用 SizedBox.expand 强制撑满：Stack 默认 StackFit.loose，
      // 尺寸由非定位子级（顶部按钮行 ~40px）决定 → Positioned.fill 的
      // 3D 视图只分到 40px 高，世界和所有 UI 全挤在屏幕最上方一条，
      // 下方 9/10 空白（R23c 布局测试实测：Scaffold 872.7 高、
      // VoxelWorldView3D 只有 40px —— 用户数月来"3D 在顶部"的真根因）。
      body: SizedBox.expand(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: VoxelWorldView3D(
                key: _viewKey,
                world: _world,
                cameraOut: _cameraOut,
                initialCameraMode: widget.openCamera,
                autoStart: widget.autoStart,
                survival: widget.survival,
                initialSaveData: widget.initialSaveData,
                multiplayer: widget.multiplayer,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(
                  children: <Widget>[
                    // R26skel：去掉左上角「退出游戏」按钮——游戏唯一入口
                    // 收敛到游戏主菜单，游戏内退出走「菜单 → 保存退出」。
                    const Spacer(),
                    Consumer(
                      builder: (BuildContext ctx, WidgetRef ref, Widget? _) =>
                          _GlassCircleButton(
                        icon: Icons.camera_alt_outlined,
                        onTap: () {
                          final active = ref.read(activeSceneProvider);
                          final VoxelSceneCapture cap =
                              VoxelSceneCapture.fromCamera(
                            _world,
                            _cameraOut.value,
                            timePhase: 0.25,
                          );
                          ref
                              .read(customScenesProvider.notifier)
                              .save(active.copyWith(voxelCapture: cap));
                          appNotify(ctx, '已设为「${active.name}」的场景背景');
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    // Module "MusicViz-2.5D"：把当前视角区域的 3D 体素"转化"为
                    // 2.5D 音效画布（带地形高度），保存后进入沉浸画布随真音乐联动。
                    // G1（用户确认）：右上角曾有「进 2.5D 画布」(auto_awesome) 与
                    // 「转化 2.5D」(view_in_ar) 两个功能重复的入口 → 去重，仅保留本按钮。
                    Consumer(
                      builder: (BuildContext ctx, WidgetRef ref, Widget? _) =>
                          _GlassCircleButton(
                        icon: Icons.view_in_ar_rounded,
                        onTap: () async {
                          final Vec3 p = _cameraOut.value.position;
                          final ExportResult r =
                              WorldToCanvasExporter.exportRegion(
                            _world,
                            p.x.floor(),
                            p.z.floor(),
                            7,
                          );
                          await ref
                              .read(voxelSoundScenesProvider.notifier)
                              .save(r.scene);
                          if (!mounted) return;
                          await Navigator.of(ctx).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  VoxelCanvasPage(initialScene: r.scene),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// R26h：顶部居中信息条——世界名 · 存档时间 · 游戏时长 三合一。
/// 游戏时长由内部 1s 定时器自更新，与渲染帧率解耦。
class _WorldInfoBar extends StatefulWidget {
  const _WorldInfoBar({
    required this.seedTag,
    this.lastSavedAt,
    this.sessionStart,
  });

  final String seedTag;
  final DateTime? lastSavedAt;
  final DateTime? sessionStart;

  @override
  State<_WorldInfoBar> createState() => _WorldInfoBarState();
}

class _WorldInfoBarState extends State<_WorldInfoBar> {
  Timer? _timer;
  String _duration = '0秒';

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant _WorldInfoBar old) {
    super.didUpdateWidget(old);
    if (old.sessionStart != widget.sessionStart ||
        old.lastSavedAt != widget.lastSavedAt) {
      _refresh();
    }
  }

  void _refresh() {
    final DateTime? s = widget.sessionStart;
    final Duration d = s == null ? Duration.zero : DateTime.now().difference(s);
    final int h = d.inHours;
    final int m = d.inMinutes % 60;
    final int sec = d.inSeconds % 60;
    final String dur =
        h > 0 ? '$h时${m}分' : (m > 0 ? '$m分${sec}秒' : '${sec}秒');
    if (mounted && dur != _duration) setState(() => _duration = dur);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(DateTime t) {
    final int h = t.hour, m = t.minute, s = t.second;
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(h)}:${p2(m)}:${p2(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final String save =
        widget.lastSavedAt == null ? '—' : _fmt(widget.lastSavedAt!);
    final TextStyle style = const TextStyle(
      color: Color(0xFFF2F5FA),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.public, size: 15, color: Color(0xFFF2F5FA)),
          const SizedBox(width: 5),
          Text('体素世界 ${widget.seedTag}', style: style),
          const SizedBox(width: 10),
          const Icon(Icons.save_outlined, size: 14, color: Color(0xFFF2F5FA)),
          const SizedBox(width: 4),
          Text('存档 $save', style: style),
          const SizedBox(width: 10),
          const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFF2F5FA)),
          const SizedBox(width: 4),
          Text('时长 $_duration', style: style),
        ],
      ),
    );
  }
}

/// R26h/R26p2：折叠面板——收纳次级控制（坐标 / 模式 / 自动跳 / 沉浸），
/// 由顶栏「菜单」按钮开合，避免顶栏按钮过多。视距 / 画质仅保留在首页
/// 「游戏画面」设置页（与游戏内共享 provider），不在游戏内菜单堆砌。
class _FoldPanel extends StatelessWidget {
  const _FoldPanel({
    required this.showCoords,
    required this.onToggleCoords,
    required this.survival,
    required this.onToggleSurvival,
    required this.onOpenCamera,
    required this.autoJump,
    required this.onToggleAutoJump,
    required this.uiCollapsed,
    required this.onToggleUiCollapsed,
    required this.flashlight,
    required this.onToggleFlashlight,
    required this.hudScale,
    required this.onHudScale,
    required this.onUnstick,
    required this.onCaptureScene,
    required this.onClose,
  });

  final bool showCoords;
  final VoidCallback onToggleCoords;
  final bool survival;
  final VoidCallback onToggleSurvival;
  final VoidCallback onOpenCamera;
  final bool autoJump;
  final VoidCallback onToggleAutoJump;
  final bool uiCollapsed;
  final VoidCallback onToggleUiCollapsed;
  final bool flashlight;
  final VoidCallback onToggleFlashlight;
  final double hudScale;
  final ValueChanged<double> onHudScale;
  final VoidCallback onUnstick;
  final VoidCallback onCaptureScene;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final Widget sep = const SizedBox(height: 6);
    return Container(
      width: 232,
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: const Color(0x40FFFFFF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('折叠菜单', style: context.appText.body)),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: const Icon(Icons.close, size: 18, color: Color(0xFFF2F5FA)),
              ),
            ],
          ),
          sep,
          _ToggleChip(
            icon: Icons.place,
            label: '坐标',
            active: showCoords,
            onTap: onToggleCoords,
          ),
          sep,
          _ToggleChip(
            icon: Icons.flutter_dash,
            label: survival ? '生存' : '创造',
            active: survival,
            onTap: onToggleSurvival,
          ),
          // R26fix：创造模式「飞行」开关——一键起飞/落地，不依赖双击手感。
          sep,
          // R26fx：相机入口保留在「更多」；存档已移入游戏菜单（暂停 → 菜单）第二位。
          _ToggleChip(
            icon: Icons.camera_alt_outlined,
            label: '相机',
            onTap: onOpenCamera,
          ),
          sep,
          _ToggleChip(
            icon: Icons.run_circle_outlined,
            label: '自动跳',
            active: autoJump,
            onTap: onToggleAutoJump,
          ),
          sep,
          _ToggleChip(
            icon: uiCollapsed ? Icons.fullscreen : Icons.fullscreen_exit,
            label: uiCollapsed ? '展开' : '折叠',
            active: uiCollapsed,
            onTap: onToggleUiCollapsed,
          ),
          sep,
          // R26fl：手电筒模式（FOV 不变：窄锥剔除 + 边界黑化 + 泛光）。
          _ToggleChip(
            icon: Icons.flashlight_on_outlined,
            label: '手电筒',
            active: flashlight,
            onTap: onToggleFlashlight,
          ),
          sep,
          // H4：脱离卡死（卡进方块/悬崖时一键脱出到安全地表）。
          _ToggleChip(
            icon: Icons.free_cancellation_outlined,
            label: '脱离卡死',
            active: false,
            onTap: onUnstick,
          ),
          sep,
          // R26x：HUD 大小滑块（摇杆 / 动作键整体缩放）。
          Row(
            children: <Widget>[
              const Icon(Icons.zoom_out_map_rounded,
                  size: 16, color: Color(0xFFF2F5FA)),
              const SizedBox(width: 6),
              Expanded(
                child: Slider(
                  value: hudScale,
                  min: kHudScaleMin,
                  max: kHudScaleMax,
                  divisions: 6,
                  label: '${(hudScale * 100).round()}%',
                  onChanged: onHudScale,
                ),
              ),
              Text('${(hudScale * 100).round()}%',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFF2F5FA))),
            ],
          ),
          sep,
          // H2：场景拍摄（机位 + 16×16 音效 → 独立场景记录）。
          _ToggleChip(
            icon: Icons.add_a_photo_outlined,
            label: '场景拍摄',
            active: false,
            onTap: onCaptureScene,
          ),
        ],
      ),
    );
  }
}

/// 深色画面上的半透明圆形按钮。
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x59000000),
          border: Border.all(color: const Color(0x40FFFFFF)),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFFF2F5FA)),
      ),
    );
  }
}

/// 相机模式取景面板（R23d）：焦距滑块 + 快门 + 关闭。
/// 第三人称 / 第一人称下拖拽缩放被禁用，焦距只由滑块调节。
class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.fov,
    required this.onFov,
    required this.onShutter,
    required this.onGallery,
    required this.onCaptureScene,
    required this.onClose,
  });

  final double fov;
  final ValueChanged<double> onFov;
  final VoidCallback onShutter;
  final VoidCallback onGallery;

  /// R26fx：相机 > 场景拍摄（机位+音效存成场景，联动主页场景列表）。
  final VoidCallback onCaptureScene;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final String mode = fov >= 1.1
        ? '广角'
        : (fov <= 0.6 ? '长焦' : '标准');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x990B1220),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x44FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.photo_camera_outlined,
              size: 16, color: Color(0xFFF2F5FA)),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Slider(
              // 相机 fov 为弧度，滑块范围与 VoxelCamera 弧度边界对齐
              // （原 0.35~1.5 与 _setFov 旧角度钳制不一致）。
              value: fov.clamp(VoxelCamera.minFov, VoxelCamera.maxFov),
              min: VoxelCamera.minFov,
              max: VoxelCamera.maxFov,
              activeColor: const Color(0xFFFFD54F),
              onChanged: onFov,
            ),
          ),
          Text(mode,
              style: const TextStyle(color: Color(0xFFF2F5FA), fontSize: 11)),
          const SizedBox(width: 8),
          // 快门
          GestureDetector(
            onTap: onShutter,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF5A5A),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          // R26fx：相机 > 场景拍摄（机位+音效存成场景，联动主页）。
          GestureDetector(
            onTap: onCaptureScene,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xAA9B7BFF),
                border: Border.all(color: const Color(0x66FFFFFF)),
              ),
              child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          // 照片墙（R23k：照片=场景，随时进入）
          GestureDetector(
            onTap: onGallery,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x66000000),
                border: Border.all(color: const Color(0x55FFFFFF)),
              ),
              child: const Icon(Icons.photo_library_outlined,
                  size: 18, color: Color(0xFFF2F5FA)),
            ),
          ),
          const SizedBox(width: 6),
          // 关闭
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x66000000),
                border: Border.all(color: const Color(0x55FFFFFF)),
              ),
              child: const Icon(Icons.close,
                  size: 18, color: Color(0xFFF2F5FA)),
            ),
          ),
        ],
      ),
    );
  }
}

/// R23w 挖掘进度：准星外一圈弧，挖满即破。
///
/// 用 [ValueNotifier] 做 repaint 源，只重绘这一层，不触发整页 rebuild。
class _CrackPainter extends CustomPainter {
  _CrackPainter(this.progress) : super(repaint: progress);

  final ValueNotifier<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double p = progress.value;
    if (p <= 0) return;
    final Offset c = Offset(size.width / 2, size.height / 2);
    final Rect rect = Rect.fromCircle(center: c, radius: 18);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * p.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = const Color(0xFFFFE08A)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _CrackPainter old) => false;
}

/// 第一人称准星（屏幕中央十字）。
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 2;
    final Offset c = Offset(size.width / 2, size.height / 2);
    const double r = 10;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
    canvas.drawCircle(c, 1.6, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 瞄准方块高亮框（R23f）：把准星目标方块投影为 12 条边线框，
/// 直观显示"方块碰撞箱"与交互目标。随 [_aimNotifier] 变化重绘。
class _AimBoxPainter extends CustomPainter {
  _AimBoxPainter(this._state) : super(repaint: _state._aimNotifier);

  final _VoxelWorldView3DState _state;

  @override
  void paint(Canvas canvas, Size size) {
    final (int, int, int)? block = _state._aimNotifier.value;
    final VoxelCamera camera = _state._camera;
    if (block == null || size.isEmpty) return;

    final ViewBasis b = camera.basis;
    final ProjectionParams proj = camera.projectionFor(size);
    ScreenPoint? proj3(double wx, double wy, double wz) =>
        VoxelCamera.projectWith(wx, wy, wz, b, proj);
    if (proj3(block.$1 + 0.5, block.$2 + 0.5, block.$3 + 0.5) == null) {
      return; // 目标在近裁剪后（看不到就不画）
    }

    final double x0 = block.$1.toDouble();
    final double y0 = block.$2.toDouble();
    final double z0 = block.$3.toDouble();
    const List<int> cx = <int>[0, 1, 1, 0, 0, 1, 1, 0];
    const List<int> cy = <int>[0, 0, 1, 1, 0, 0, 1, 1];
    const List<int> cz = <int>[0, 0, 0, 0, 1, 1, 1, 1];
    // 12 条边（立方体索引对）。
    const List<(int, int)> edges = <(int, int)>[
      (0, 1), (1, 2), (2, 3), (3, 0),
      (4, 5), (5, 6), (6, 7), (7, 4),
      (0, 4), (1, 5), (2, 6), (3, 7),
    ];

    // 8 顶点投影；任一在近裁剪后则跳过该边（简单裁剪）。
    final List<ScreenPoint?> pts = <ScreenPoint?>[
      for (int i = 0; i < 8; i++)
        proj3(x0 + cx[i], y0 + cy[i], z0 + cz[i]),
    ];

    final Paint line = Paint()
      ..color = const Color(0xE6000000)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    for (final (int a, int b2) in edges) {
      final ScreenPoint? pa = pts[a];
      final ScreenPoint? pb = pts[b2];
      if (pa == null || pb == null) continue;
      canvas.drawLine(Offset(pa.x, pa.y), Offset(pb.x, pb.y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _AimBoxPainter oldDelegate) => true;
}
