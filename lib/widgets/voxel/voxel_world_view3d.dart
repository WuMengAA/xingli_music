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
import 'dart:io' show Directory, File;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../../models/companion_action.dart';
import '../../models/companion_models.dart';
import '../../providers/companion/companion_providers.dart';
import '../../pages/canvas/photo_gallery_page.dart';
import '../../pages/canvas/voxel_canvas_page.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/scene/scene_custom_providers.dart';
import '../../providers/voxel/world_audio_provider.dart';
import 'voxel_capture_models.dart';
import 'voxel_world_types.dart';
import 'world_landmarks.dart';

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
import '../../providers/settings/performance_providers.dart';
import '../../services/audio/minecraft_sfx_service.dart';
import 'voxel_camera.dart';
import 'voxel_crafting.dart';
import 'voxel_daynight.dart';
import 'voxel_inventory.dart';
import 'voxel_inventory_panel.dart';
import 'voxel_items.dart';
import 'voxel_mobs.dart';
import 'voxel_renderer.dart';
import 'voxel_survival.dart';
import 'voxel_world.dart';
import 'voxel_save.dart';
import 'view_mode_button.dart';
import 'world_audio_engine.dart';

/// 相机移动方向（D-pad / 键盘按住时累积）。
enum _Nav { forward, back, left, right, up, down }

/// 视角模式（R23：2.5D 等距 / 3D 俯瞰 / 3D 第一人称；R23k + 第三人称跟随）。
enum _ViewMode { iso2d5, orbit, firstPerson, thirdPerson }

/// 画面精度档（R24c）：在 [PerformanceMode] 基础上进一步细分渲染参数。
enum GraphicsQuality {
  /// 流畅：近视距 + 关雾 + 关水波 + 关贴图，保帧率。
  smooth('流畅', viewDistanceChunks: 3, lodStartChunks: 1, lodStepChunks: 1,
      maxFaces: 9000, fog: false, water: false, texture: false),

  /// 标准：均衡视距 + 雾 + 水波 + 贴图。
  standard('标准', viewDistanceChunks: 4, lodStartChunks: 2, lodStepChunks: 2,
      maxFaces: 16000, fog: true, water: true, texture: true),

  /// 高清：远视距 + 贴图 + 雾 + 水波，面数更宽。
  fine('高清', viewDistanceChunks: 6, lodStartChunks: 3, lodStepChunks: 2,
      maxFaces: 26000, fog: true, water: true, texture: true);

  const GraphicsQuality(
    this.label, {
    required this.viewDistanceChunks,
    required this.lodStartChunks,
    required this.lodStepChunks,
    required this.maxFaces,
    required this.fog,
    required this.water,
    required this.texture,
  });

  final String label;
  final int viewDistanceChunks;
  final int lodStartChunks;
  final int lodStepChunks;
  final int maxFaces;
  final bool fog;
  final bool water;
  final bool texture;
}

/// 3D 体素世界视图（撑满父容器）。
class VoxelWorldView3D extends ConsumerStatefulWidget {
  const VoxelWorldView3D({
    super.key,
    required this.world,
    this.initialCamera,
    this.showControls = true,
    this.showStats = false,
    this.cameraOut,
  });

  final VoxelWorld world;

  /// 初始机位（默认 [VoxelCamera.overview] 全景俯瞰）。
  final VoxelCamera? initialCamera;

  /// 相机外送口：每帧把当前机位写入，供父级「拍照取景」读取。
  ///
  /// 不触发 rebuild（只写 value，父级按需 `.value` 读取）。
  final ValueNotifier<VoxelCamera>? cameraOut;

  /// 是否显示 D-pad 等操作件。
  final bool showControls;

  /// 是否显示面数 / 列数调试角标（同时是「遮挡剔除」开关）。
  final bool showStats;

  @override
  ConsumerState<VoxelWorldView3D> createState() => _VoxelWorldView3DState();
}

class _VoxelWorldView3DState extends ConsumerState<VoxelWorldView3D>
    with SingleTickerProviderStateMixin {
  /// 移动速度（方块 / 秒）。
  static const double _moveSpeed = 6.0;

  /// 自动巡航角速度（弧度 / 秒，约 2 分钟一圈）。
  static const double _orbitSpeed = 0.052;

  /// 空闲多久后开始自动旋转（秒，按 motionScale 缩放）。
  static const double _idleDelay = 6.0;

  late VoxelCamera _camera;
  late final Ticker _ticker;
  final ValueNotifier<VoxelFrame> _frame = ValueNotifier<VoxelFrame>(
    VoxelFrame.empty,
  );
  final Set<_Nav> _held = <_Nav>{};

  /// 世界内空间音效引擎（Phase 3）：按相机机位把地形地物翻译成有方位的声音。
  /// 出错也不影响画面（全部吞掉），预览页退出时释放。
  WorldAudioEngine? _audio;

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
  bool _occlusionCull = true;

  // ── R23 视角模式 ─────────────────────────────────────
  _ViewMode _viewMode = _ViewMode.orbit;

  /// 第一人称：玩家脚底坐标（世界，方块单位）。
  Vec3 _fpPos = Vec3.zero;
  double _fpVy = 0;
  bool _fpOnGround = true;
  bool _fpJumpQueued = false;

  // ── R24 跳跃 / 自动跳跃 / 坐标系统 ──────────────────
  /// 自动跳跃（默认关闭）：撞到 1 格台阶时自动抬升迈过。
  bool _autoJump = false;
  /// 坐标系统 HUD 开关（默认显示，类 F3）。
  bool _showCoords = true;
  /// 是否已进入世界（首屏选择前为 false，显示「创造/生存」面板）。
  bool _started = false;
  /// 坐标串（notifier：只让坐标 HUD 重绘）。
  final ValueNotifier<String> _coordsText = ValueNotifier<String>('');

  // ── R24c 画面精度 / 16×16 纹理图集 ──────────────────
  /// 画面精度档（流畅 / 标准 / 高清），影响视距 / LOD / 面数 / 雾 / 水波 / 贴图。
  GraphicsQuality _quality = GraphicsQuality.standard;

  /// 16×16 纹理图集（异步构建；null = 尚未就绪，回退纯色）。
  ui.Image? _atlas;

  /// HUD 折叠（沉浸模式）：隐藏全部控件，仅留准星。
  bool _uiCollapsed = false;

  /// 虚拟摇杆输出（x=横移, y=前后；上为负）。
  double _joyX = 0;
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

  /// 破坏/放置交互半径（格，MC 默认 5）。
  static const double _reach = 5.0;

  // ── R23f 蹲 / 碰撞 / 瞄准框 ─────────────────────────
  /// 是否蹲下（Shift 或 D-pad 下）：视线降低、碰撞箱变矮、移速减半。
  bool _crouching = false;

  /// 准星瞄准的目标方块（notifier：值变化自动通知瞄准框 painter 重绘）。
  final ValueNotifier<(int, int, int)?> _aimNotifier =
      ValueNotifier<(int, int, int)?>(null);

  /// 是否绘制瞄准框（第一人称/第三人称、非相机模式）。
  bool get _showAim =>
      (_viewMode == _ViewMode.firstPerson ||
          _viewMode == _ViewMode.thirdPerson) &&
      !_cameraMode;

  // 由 build 中的 provider 读取写入，Ticker 回调消费。
  RenderConfig _config = const RenderConfig();

  // ── R23w 背包 / 生存 / 生物 / 挖掘 ───────────────────
  /// 36 格背包（前 9 格 = 快捷栏）。
  final VoxelInventory _inv = VoxelInventory();

  /// 生命 / 饥饿 / 经验。
  final PlayerVitals _vitals = PlayerVitals();

  /// 僵尸 + 掉落物世界。
  late final MobWorld _mobs = MobWorld(world: widget.world);

  /// 背包面板是否打开。
  bool _bagOpen = false;

  /// 是否正按住（长按挖掘）。
  bool _acting = false;

  /// 本次按住期间是否已挖掉方块（松手时不再补一刀）。
  bool _brokeInHold = false;

  /// 正在挖的方块（null = 没在挖）。
  (int, int, int)? _miningAt;

  /// 当前方块所需总耗时（秒）。
  double _miningNeed = 0;

  /// 已挖时长（秒）。
  double _miningTime = 0;

  /// 挖掘进度 0~1（notifier：只重绘裂纹层）。
  final ValueNotifier<double> _crackNotifier = ValueNotifier<double>(0);

  /// 攻击冷却（秒），防止长按变成连击机枪。
  double _attackCd = 0;

  /// 上一帧玩家水平位置（算移动距离 → 疲劳）。
  double _lastPx = 0, _lastPz = 0;

  // ── R23v 昼夜循环 ───────────────────────────────────
  /// 昼夜推进器：默认从清晨出发、10 分钟一昼夜；HUD 时钟可锁定档位。
  final DayNightCycle _time = DayNightCycle(phase: 0.16);

  /// 时钟串（notifier：只让 HUD 时钟重绘，不触发整页 rebuild）。
  final ValueNotifier<String> _clockText = ValueNotifier<String>('');

  /// R23s：区块几何缓存——跨帧复用 occlusion 可见面，大幅提升体素世界帧率。
  /// 由本 state 持有，编辑方块 / 换世界 / 切换遮挡剔除时失效。
  final VoxelChunkCache _chunkCache = VoxelChunkCache();

  Duration _interval = const Duration(milliseconds: 56);
  double _motionScale = 1;
  bool _autoOrbit = true;

  @override
  // ── R24d 30s 自动存档状态 ─────────────────────────────
  Timer? _saveTimer;
  DateTime? _lastSavedAt;

  void initState() {
    super.initState();
    _camera = widget.initialCamera ?? VoxelCamera.overview(widget.world);
    // 小人初始站在世界中心。
    _figurePos = Vec3(
      widget.world.sizeX / 2,
      VoxelCamera.groundHeightAt(
        widget.world,
        widget.world.sizeX / 2,
        widget.world.sizeZ / 2,
      ),
      widget.world.sizeZ / 2,
    );
    _figureTarget = _figurePos;

    // R23w：按当前模式装包（创造给满、生存给起步套装）。
    _syncInventoryForMode();

    // 世界音效：按开关决定是否起播。
    _audioEnabled = ref.read(worldAudioEnabledProvider);
    _syncAudio();

    // R24c：按当前精度档位初始化渲染配置（默认「标准」= 视距/雾/水波/贴图全开）。
    _config = _configFor(_quality);

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
      Uint8List? skin;
      try {
        final ByteData bd = await rootBundle.load('assets/player_skin.png');
        skin = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      } catch (_) {
        skin = null;
      }
      final ui.Image img = await VoxelTextureAtlas.build(skinBytes: skin);
      if (!mounted) {
        img.dispose();
        return;
      }
      _atlas = img;
      _dirty = true;
      setState(() {});
    }();

    // R24d：自动存档——进入世界先尝试恢复上次存档，并启动 30s 周期落盘。
    unawaited(_restoreSave());
    _saveTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _saveNow(),
    );
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
    } else if (!_audioEnabled && _audio != null) {
      _audio?.dispose();
      _audio = null;
    }
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
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(writeVoxelSave(_buildSaveData())); // 退出前最后落盘（不触发 setState）
    _audio?.dispose();
    _ticker.dispose();
    _frame.dispose();
    _aimNotifier.dispose();
    _clockText.dispose();
    _crackNotifier.dispose();
    _coordsText.dispose();
    _inv.dispose();
    _vitals.dispose();
    _mobs.clear();
    super.dispose();
  }

  // ── 渲染循环 ─────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    // 瞄准框每帧刷新（独立于地形重建的帧率节流），保证选择框始终跟手、不卡顿。
    if (_showAim) {
      final ((int, int, int), (int, int, int))? aim = _raycast();
      _aimNotifier.value = aim?.$1;
    }
    if (_lastTick != Duration.zero && elapsed - _lastTick < _interval) {
      return; // 帧率节流（按性能档位）
    }
    final double dt = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.25);
    _lastTick = elapsed;

    if (_held.isNotEmpty) {
      _idle = 0;
      if (_viewMode == _ViewMode.firstPerson ||
          _viewMode == _ViewMode.thirdPerson) {
        _applyNavFP(dt);
      } else {
        _applyNav(dt);
      }
    } else {
      _idle += dt;
      // 自动巡航仅俯瞰模式（第一人称/2.5D 不自动转）。
      if (_autoOrbit &&
          _viewMode == _ViewMode.orbit &&
          _idle > _idleDelay * _motionScale) {
        _camera = _camera.rotate(_orbitSpeed * dt, 0);
        _dirty = true;
      }
    }

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

    if (!_dirty || _viewport.isEmpty) return;
    _dirty = false;
    // 外送当前机位（供父级拍照取景，不触发 rebuild）
    widget.cameraOut?.value = _camera;
    _frame.value = VoxelRenderer.buildFrame(
      world: widget.world,
      camera: _camera,
      viewport: _viewport,
      config: _config.copyWith(occlusionCull: _occlusionCull),
      timePhase: _time.phase,
      wavePhase: _wave,
      // R23w：AI 小人 + 僵尸 + 掉落物 + 玩家方块人（#169）一起交给渲染器。
      // 玩家在 orbit / thirdPerson 下可见（脚底=_fpPos，orbit 落到地表），
      // firstPerson 沉浸时不显示自身。
      entities: _buildEntities(),
      cache: _chunkCache,
      lights: widget.world.lightsNear(_camera.position.x, _camera.position.z),
    );
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

  /// 组装本帧实体列表：玩家方块人（#169）+ AI 小人 + 僵尸/掉落物。
  ///
  /// 玩家在 [orbit] / [thirdPerson] 下渲染（脚底=_fpPos；orbit 无第一人称位移，
  /// 用地表高度落位避免埋进地形）；[firstPerson] 沉浸视角不显示自身。
  List<VoxelEntity> _buildEntities() {
    final List<VoxelEntity> ents = <VoxelEntity>[];
    if (_viewMode == _ViewMode.orbit || _viewMode == _ViewMode.thirdPerson) {
      final double py = _viewMode == _ViewMode.orbit
          ? VoxelCamera.groundHeightAt(widget.world, _fpPos.x, _fpPos.z)
          : _fpPos.y;
      ents.add(VoxelEntity(
        position: Vec3(_fpPos.x, py, _fpPos.z),
        color: const Color(0xFFC8A079), // 无皮肤时的纯色回退（肤色）
        scale: 1.0,
        useSkin: true,
      ));
    }
    if (_companionEntities.isNotEmpty) ents.addAll(_companionEntities);
    if (!_mobs.isEmpty) ents.addAll(_mobs.toEntities());
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

  /// 第三人称相机位：玩家身后 4 格、上方 2.5 格（跟随玩家朝向）。
  ///
  /// R23m：相机带碰撞箱——从玩家位置沿视线方向步进，遇到实心方块
  /// 就把相机**拉近到阻挡前一格**（MC 式第三人称防穿墙），并兜底抬出。
  Vec3 _thirdPersonPos() {
    final double sy = math.sin(_camera.yaw);
    final double cy = math.cos(_camera.yaw);
    const double dist = 4.0;
    final Vec3 from = Vec3(_fpPos.x, _fpPos.y + 1.6, _fpPos.z);
    final Vec3 target = Vec3(
      from.x - sy * dist,
      _fpPos.y + 2.5,
      from.z - cy * dist,
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
    final double step = _moveSpeed * (crouch ? 0.5 : 1.0) * dt;
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
    double lift = 0;
    if (!_survival) {
      if (_held.contains(_Nav.up)) lift += step;
      if (_held.contains(_Nav.down)) lift -= step;
    }

    // ── 水平：逐轴移动 + 碰撞（滑动）──
    // R23k：无限地图——不再 clamp 到出生大陆边界（删空气墙），
    // 只留一个超大软边界兜底（±1e6，实际到不了）。
    final double dx = (sy * forward + cy * strafe) * step;
    final double dz = (cy * forward - sy * strafe) * step;
    final double baseY = _fpPos.y + lift;
    const double limit = 1000000.0;
    final double desiredX = (_fpPos.x + dx).clamp(-limit, limit);
    final double desiredZ = (_fpPos.z + dz).clamp(-limit, limit);
    bool blockedX = false;
    bool blockedZ = false;
    if (!_bodyCollides(desiredX, baseY, _fpPos.z, bodyH)) {
      _fpPos = Vec3(desiredX, _fpPos.y, _fpPos.z);
    } else {
      blockedX = true;
    }
    if (!_bodyCollides(_fpPos.x, baseY, desiredZ, bodyH)) {
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

    final bool inWater = _fpInWater();

    // ── 垂直：统一重力（生存+创造），创造 Q/E 升降对抗重力 ──
    double ny;
    if (_survival) {
      if (_fpJumpQueued && _fpOnGround) {
        _fpVy = inWater
            ? 4.0
            : math.sqrt(
                2 * VoxelCamera.gravity * VoxelCamera.jumpHeight,
              );
        _fpOnGround = false;
      }
      _fpJumpQueued = false;
      final double g =
          inWater ? VoxelCamera.gravity * 0.35 : VoxelCamera.gravity;
      _fpVy -= g * dt;
      if (inWater && _fpVy < -1.5) _fpVy = -1.5;
      ny = _fpPos.y + _fpVy * dt;
    } else {
      _fpJumpQueued = false;
      if (lift != 0) {
        // 创造：按住升降 → 直接位移（零冲量）。
        _fpVy = 0;
        ny = _fpPos.y + lift;
      } else {
        // 创造：松开升降也下落（R23f：修复"没有下落物理"）。
        _fpVy -= VoxelCamera.gravity * 0.9 * dt;
        ny = _fpPos.y + _fpVy * dt;
      }
    }

    // ── 垂直碰撞：上升逐级检测头顶（跳跃顶到方块即停，防穿模）──
    if (ny > _fpPos.y) {
      double top = _fpPos.y;
      for (double yy = _fpPos.y + 0.2; yy <= ny + 1e-6; yy += 0.2) {
        if (_bodyCollides(_fpPos.x, yy, _fpPos.z, bodyH)) break;
        top = yy;
      }
      ny = top;
      if (ny <= _fpPos.y + 1e-9) {
        ny = _fpPos.y;
        _fpVy = 0; // 顶头停住
      }
    }

    // ── 落地（生存+创造都落地）──
    final double ground =
        VoxelCamera.groundHeightAt(w, _fpPos.x, _fpPos.z);
    if (ny <= ground) {
      if (_survival && _fpVy < -12) {
        final int dmg = ((_fpVy.abs() - 12) * 1.2).round().clamp(1, 12);
        _damage(dmg);
      }
      ny = ground;
      _fpVy = 0;
      _fpOnGround = true;
    }

    // ── 重叠推出兜底（R23g）：若玩家仍与方块重叠（放置卡身 / 地形突变
    // 卡进方块 / 任何漏网穿模），把脚底抬到该方块顶部，杜绝"穿到上面"。
    _fpPos = Vec3(_fpPos.x, ny, _fpPos.z);
    {
      final int xi = _fpPos.x.floor();
      final int zi = _fpPos.z.floor();
      if (xi >= 0 && xi < w.sizeX && zi >= 0 && zi < w.sizeZ) {
        final int yTop = (_fpPos.y + bodyH).floor();
        for (int ly = _fpPos.y.floor(); ly <= yTop; ly++) {
          if (ly < 0) continue;
          if (ly >= w.maxY) break;
          if (w.get(xi, ly, zi).occludes) {
            _fpPos = Vec3(_fpPos.x, ly + 1.0, _fpPos.z);
            _fpVy = 0;
            _fpOnGround = false; // 悬空，下一帧重力继续
            break;
          }
        }
      }
    }
    ny = _fpPos.y;

    _camera = _camera.copyWith(
      // R23k：第三人称 = 相机悬在玩家身后（跟随），第一人称 = 眼高。
      position: _viewMode == _ViewMode.thirdPerson
          ? _thirdPersonPos()
          : Vec3(_fpPos.x, ny + eyeH, _fpPos.z),
    );
    _dirty = true;
  }

  /// 玩家包围盒（0.6 宽 × [bodyH] 高）与实心方块是否碰撞（水/叶不挡）。
  ///
  /// R23k：无限地图——x/z 不再有边界空气墙，越界由世界确定性生成地形；
  /// 碰撞判定完全交给 [VoxelWorld.get]（越界高度返回空气）。
  bool _bodyCollides(double x, double y, double z, [double bodyH = 1.75]) {
    final VoxelWorld w = widget.world;
    final int xi = x.floor();
    final int zi = z.floor();
    final int yTop = (y + bodyH).floor();
    for (int yy = y.floor(); yy <= yTop; yy++) {
      if (yy < 0) continue;
      if (yy >= w.maxY) return true;
      if (w.get(xi, yy, zi).occludes) return true;
    }
    return false;
  }

  /// 玩家当前是否泡在水里。
  bool _fpInWater() {
    final VoxelWorld w = widget.world;
    return w.get(
          _fpPos.x.floor(),
          _fpPos.y.floor(),
          _fpPos.z.floor(),
        ) ==
        Voxel.water;
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
    // 死亡清场：附近的僵尸不跟着重生点刷屏。
    _mobs.zombies.clear();
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

    // 僵尸 + 掉落物。
    final int before = _mobs.zombies.length + _mobs.items.length;
    _mobs.tick(
      dt,
      playerPos: p,
      isNight: _time.isNight,
      survival: _survival && fp,
      onHitPlayer: _damage,
      onPickup: (ItemStack s) => _inv.add(s) == 0,
    );
    if (before > 0 || _mobs.zombies.isNotEmpty || _mobs.items.isNotEmpty) {
      _dirty = true;
    }

    _tickMining(dt, fp);
  }

  /// 长按挖掘：按方块硬度 / 工具倍率累积进度，满了才破坏。
  void _tickMining(double dt, bool fp) {
    if (!_acting || !fp || _cameraMode || _bagOpen) {
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
      // 创造模式秒破；生存模式按硬度 / 工具算时间。
      _miningNeed = _survival ? breakSeconds(v, _inv.tool) : 0.0;
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
    w.setVoxel(hit.$1, hit.$2, hit.$3, Voxel.air);
    _invalidateChunkAt(hit.$1, hit.$3);
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

  /// 攻击准星方向最近的僵尸。
  void _tryAttack() {
    if (!_survival || _attackCd > 0 || _mobs.zombies.isEmpty) return;
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
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('背包放不下 $left 个${itemNameOf(r.output)}')),
      );
    }
  }

  /// 吃掉某格的食物。
  void _eatSlot(int index) {
    final ItemStack s = _inv.at(index);
    if (s.isEmpty || foodValue(s.item) <= 0) return;
    if (!_vitals.eat(s.item)) return;
    _inv.set(index, s.plus(-1));
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final bool fp = _viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson;
    final bool down = event is KeyDownEvent || event is KeyRepeatEvent;
    final bool up = event is KeyUpEvent;
    final LogicalKeyboardKey k = event.logicalKey;

    // 空格：生存 = 跳跃入队；创造 = 按住飞升（松手停止）。
    if (k == LogicalKeyboardKey.space && fp) {
      if (_survival) {
        if (down) _fpJumpQueued = true;
      } else {
        if (down) {
          _held.add(_Nav.up);
        } else if (up) {
          _held.remove(_Nav.up);
        }
      }
      return KeyEventResult.handled;
    }
    // Shift：生存 = 蹲（按住）；创造 = 按住下降（与 MC 飞行一致）。
    if ((k == LogicalKeyboardKey.shiftLeft ||
            k == LogicalKeyboardKey.shiftRight) &&
        fp) {
      if (_survival) {
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
        _selectSlot(slot);
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
      if (survival) {
        _vitals.respawn();
        _mobs.clear();
      }
      _syncInventoryForMode();
      _viewMode = _ViewMode.firstPerson;
      _started = true;
      _dirty = true;
    });
  }

  void _press(_Nav nav) {
    // 第一人称/第三人称：
    // 下 = 创造下降（触屏 LiftPad）；生存 = 蹲。上 = 创造飞升（松手停）。
    if (_viewMode == _ViewMode.firstPerson ||
        _viewMode == _ViewMode.thirdPerson) {
      if (nav == _Nav.down) {
        if (_survival) {
          _crouching = true;
        } else {
          _held.add(nav); // 创造：LiftPad 下 = 下降
        }
        _idle = 0;
        return;
      }
      if (nav == _Nav.up && _survival) {
        _idle = 0;
        _queueJump();
        return;
      }
      if (nav == _Nav.up) {
        _held.add(nav); // 创造：飞升
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
    if (nav == _Nav.down && _survival) _crouching = false;
    _idle = 0;
  }

  /// 体素 DDA 射线：从相机眼睛沿视线步进，返回第一个实心方块坐标（瞄准/破坏用）。
  /// 射线拾取：返回 (命中方块坐标, 命中的那个面的外法线)。
  /// 连续步进并记录"从上一格(空气/水)跨入实体格"的那一步方向，即为我们看得见、
  /// 且选中了的那个面的外法线（指向相机一侧）。
  ((int, int, int), (int, int, int))? _raycast() {
    final Vec3 origin = _camera.position;
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
  void _placeAt() {
    final ((int, int, int), (int, int, int))? hit = _raycast();
    if (hit == null) return;
    final ((int, int, int) b, (int, int, int) n) = hit;
    // 面可见性：外法线 N 与视线 V 夹角 θ∈(0°,180°) 且面朝相机 ⇔ -N·V ∈ (0,1)。
    final Vec3 view = _camera.forwardVector().normalized;
    final Vec3 N = Vec3(n.$1.toDouble(), n.$2.toDouble(), n.$3.toDouble())
        .normalized;
    final double facing = -N.dot(view); // = cos(θ)，θ 为 N 与 V 夹角
    if (facing <= 1e-3 || facing >= 0.9999) {
      // 排除 0°（面背对/不可见）与 180°（完全正对）的退化情况。
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
    widget.world.setVoxel(px, py, pz, _mcSelected);
    _invalidateChunkAt(px, pz);
    _dirty = true;
  }

  /// 攻击/破坏统一入口：生存=攻击僵尸；创造=直接破坏。
  void _primaryAction() {
    if (_bagOpen || _cameraMode) return;
    if (_viewMode != _ViewMode.firstPerson &&
        _viewMode != _ViewMode.thirdPerson) {
      return;
    }
    if (_survival) {
      _tryAttack();
    } else {
      final ((int, int, int), (int, int, int))? h = _raycast();
      if (h != null) _breakBlock(h.$1);
    }
  }

  void _invalidateChunkAt(int x, int z) {
    _chunkCache.invalidate(x ~/ 16, z ~/ 16);
  }

  String _facingLabel(double yaw) {
    final double a = ((yaw % (2 * math.pi)) + 2 * math.pi) % (2 * math.pi);
    const List<String> dirs = <String>['北', '东', '南', '西'];
    final int i = ((a + math.pi / 4) / (math.pi / 2)).floor() % 4;
    return dirs[i];
  }

  String _biomeLabel(Biome b) => b.name;

  void _setView(_ViewMode mode) {
    _viewMode = mode;
    if (mode == _ViewMode.firstPerson || mode == _ViewMode.thirdPerson) {
      final int sx = widget.world.sizeX ~/ 2;
      final int sz = widget.world.sizeZ ~/ 2;
      final int top = widget.world.surfaceHeight(sx, sz);
      _fpPos = Vec3(sx.toDouble(), (top + 1).toDouble(), sz.toDouble());
      _fpVy = 0;
      _fpOnGround = true;
      _fpJumpQueued = false;
    }
    _dirty = true;
    setState(() {});
  }

  /// 视角切换按钮回调：循环 2.5D / 俯瞰 / 第一人称 / 第三人称。
  ///
  /// 具体实现由本方法提供（外部只需把 [ViewModeButton.onPressed] 指向它），
  /// 组件本身不依赖任何视角枚举。
  void _cycleViewMode() {
    const List<_ViewMode> order = <_ViewMode>[
      _ViewMode.orbit,
      _ViewMode.iso2d5,
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
    _camera = _camera.copyWith(fov: f.clamp(30.0, 100.0));
    _dirty = true;
  }

  void _snack(String m) {
    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m)));
    } catch (_) {
      // 无 Scaffold 祖先时静默
    }
  }

  // ── R24d 自动存档：序列化 / 恢复 / 周期落盘 ─────────────
  Map<String, dynamic> _buildSaveData() => <String, dynamic>{
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

  Future<void> _saveNow() async {
    await writeVoxelSave(_buildSaveData());
    if (!mounted) return;
    _lastSavedAt = DateTime.now();
    setState(() {});
  }

  Future<void> _restoreSave() async {
    final Map<String, dynamic>? data = await readVoxelSave();
    if (!mounted || data == null) return;
    // 世界编辑层：seed 一致才恢复，避免地形 / 编辑错位。
    final Map<String, dynamic>? wj =
        data['world'] as Map<String, dynamic>?;
    if (wj != null && wj['seed'] == widget.world.seed) {
      widget.world.loadJson(wj);
    }
    final Map<String, dynamic>? vj = data['vitals'] as Map<String, dynamic>?;
    if (vj != null) _vitals.loadJson(vj);
    final Map<String, dynamic>? ij = data['inv'] as Map<String, dynamic>?;
    if (ij != null) _inv.loadJson(ij);
    final int vm = (data['viewMode'] as int?) ?? _viewMode.index;
    if (vm >= 0 && vm < _ViewMode.values.length) {
      _viewMode = _ViewMode.values[vm];
    }
    _cameraMode = (data['cameraMode'] as bool?) ?? _cameraMode;
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
    final Map<String, dynamic>? cj = data['camera'] as Map<String, dynamic>?;
    if (cj != null) {
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
    }
    _lastSavedAt = data['savedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(data['savedAt'] as int)
        : null;
    _dirty = true;
    if (mounted) setState(() {});
    _snack('已恢复上次的世界存档');
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
      final Directory dir = await getApplicationDocumentsDirectory();
      final File file = File(
        '${dir.path}/voxel_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      _snack('已保存截图');
    } catch (e) {
      _snack('截图失败: $e');
    }
  }

  // ── 画面精度 → 渲染配置映射（R24c）────────────────────
  RenderConfig _configFor(GraphicsQuality q) => RenderConfig(
        viewDistanceChunks: q.viewDistanceChunks,
        lodStartChunks: q.lodStartChunks,
        lodStepChunks: q.lodStepChunks,
        maxFaces: q.maxFaces,
        fogEnabled: q.fog,
        waterAnimation: q.water,
        textureEnabled: q.texture,
        occlusionCull: _occlusionCull,
        backFaceCull: true,
        skyGradient: true,
      );

  void _setQuality(GraphicsQuality q) {
    if (_quality == q) return;
    _quality = q;
    _config = _configFor(q);
    _dirty = true;
    setState(() {});
  }

  void _onJoystick(Offset v) {
    _joyX = v.dx;
    _joyY = v.dy;
    _idle = 0;
  }

  void _toggleBag() => setState(() => _bagOpen = !_bagOpen);

  // ── HUD ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // #170：世界空间音效音量 / 主音量变化即时下发到引擎（引擎在本视图内持有）
    ref.listen<double>(worldSfxVolumeProvider,
        (_, __) => _audio?.setGlobalVolume(_worldAudioGain()));
    ref.listen<double>(masterVolumeProvider,
        (_, __) => _audio?.setGlobalVolume(_worldAudioGain()));

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
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                _ToggleChip(
                  icon: Icons.high_quality,
                  label: _quality.label,
                  onTap: () => _setQuality(
                    GraphicsQuality.values[(GraphicsQuality.values
                                .indexOf(_quality) +
                            1) %
                        GraphicsQuality.values.length],
                  ),
                ),
                // 视角切换：独立按钮组件，点击触发 _cycleViewMode（外部实现）。
                ViewModeButton(
                  onPressed: _cycleViewMode,
                  label: _viewModeLabel(),
                  tooltip: '切换视角',
                  semanticsLabel: '切换视角，当前${_viewModeLabel()}',
                  active: _viewMode != _ViewMode.orbit,
                ),
                if (_lastSavedAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0x59000000),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x40FFFFFF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(Icons.save_outlined,
                            size: 16, color: Color(0xFFF2F5FA)),
                        const SizedBox(width: 4),
                        Text(
                          '存档 ${_fmtTime(_lastSavedAt!)}',
                          style: const TextStyle(
                            color: Color(0xFFF2F5FA),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                _ToggleChip(
                  icon: Icons.place,
                  label: '坐标',
                  active: _showCoords,
                  onTap: () => setState(() => _showCoords = !_showCoords),
                ),
                if (fp)
                  _ToggleChip(
                    icon: Icons.run_circle_outlined,
                    label: '自动跳',
                    active: _autoJump,
                    onTap: () => setState(() => _autoJump = !_autoJump),
                  ),
                if (fp)
                  _ToggleChip(
                    icon: Icons.camera_alt_outlined,
                    label: '拍照',
                    active: _cameraMode,
                    onTap: () => setState(() => _cameraMode = !_cameraMode),
                  ),
                _ToggleChip(
                  icon: Icons.flutter_dash,
                  label: _survival ? '生存' : '创造',
                  active: _survival,
                  onTap: () => _enterWorld(!_survival),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _clockText,
                  builder: (BuildContext c, String s, Widget? _) =>
                      _ClockChip(text: s),
                ),
                _ToggleChip(
                  icon: _uiCollapsed ? Icons.fullscreen : Icons.fullscreen_exit,
                  label: _uiCollapsed ? '展开' : '折叠',
                  onTap: () => setState(() => _uiCollapsed = !_uiCollapsed),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 坐标 HUD（第一人称）
    if (fp && _showCoords)
      controls.add(
        Positioned(
          top: 64,
          left: AppSpace.md,
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

    // 左侧：FP/TP 摇杆；观景 LiftPad
    if (_started)
      controls.add(
        Positioned(
          left: AppSpace.md,
          bottom: fp ? 150 : 120,
          child: fp
              ? _Joystick(onChanged: _onJoystick)
              : _LiftPad(onPress: _press, onRelease: _release),
        ),
      );

    // 右侧：三大动作按钮（放大，防重叠）
    if (_started && fp && !_cameraMode)
      controls.add(
        Positioned(
          right: AppSpace.md,
          bottom: 150,
          child: Column(
            children: <Widget>[
              _BigActionButton(
                icon: Icons.flash_on_rounded,
                label: '攻击',
                // 按下即触发一次；按住（或拖动）期间持续挖掘/攻击，松手停止。
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
              const SizedBox(height: 12),
              _BigActionButton(
                icon: Icons.add_box_rounded,
                label: '放置',
                onTap: _placeAt,
              ),
              const SizedBox(height: 12),
              _BigActionButton(
                icon: Icons.arrow_upward_rounded,
                label: '跳',
                onTap: _queueJump,
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
                  onToggleSurvival: () => _enterWorld(!_survival),
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
            onClose: () => setState(() => _cameraMode = false),
          ),
        ),
      );

    // 背包面板
    if (_bagOpen)
      controls.add(
        Positioned.fill(
          child: GestureDetector(
            onTap: _toggleBag,
            child: Container(
              color: const Color(0x88000000),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('背包',
                          style: TextStyle(color: Color(0xFFF2F5FA))),
                      const SizedBox(height: 12),
                      VoxelHotbar(
                        inventory: _inv,
                        onSelect: _selectSlot,
                        onOpenBag: _toggleBag,
                        survival: _survival,
                        onToggleSurvival: () => _enterWorld(!_survival),
                      ),
                      const SizedBox(height: 12),
                      _ToggleChip(
                          icon: Icons.close, label: '关闭', onTap: _toggleBag),
                    ],
                  ),
                ),
              ),
            ),
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

    return SizedBox.expand(
      child: Stack(
        children: <Widget>[
            Positioned.fill(
              child: Listener(
                onPointerSignal: _onPointerSignal,
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
                          frame, _quality.texture ? _atlas : null),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
            if (_showAim)
              Positioned.fill(
                child: CustomPaint(painter: _AimBoxPainter(this)),
              ),
            if (fp)
              Positioned.fill(
                child: CustomPaint(painter: _CrosshairPainter()),
              ),
            if (fp)
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _crackNotifier,
                  builder: (BuildContext c, double _, Widget? __) =>
                      CustomPaint(painter: _CrackPainter(_crackNotifier)),
                ),
              ),
            if (!_started)
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _BigActionButton(
                      icon: Icons.flight_rounded,
                      label: '创造',
                      onTap: () => _enterWorld(false),
                    ),
                    const SizedBox(width: 24),
                    _BigActionButton(
                      icon: Icons.favorite_rounded,
                      label: '生存',
                      onTap: () => _enterWorld(true),
                    ),
                  ],
                ),
              ),
            ...controls,
          ],
        ),
      );
  }
}   // ← 关闭 _VoxelWorldView3DState

/// R24c: 体素帧画家：消费 [VoxelFrame]，按图集分流纯色/贴图；画家算法单桶（先不透明后半透明，根治水穿透）。
class _VoxelFramePainter extends CustomPainter {
  _VoxelFramePainter(this.frame, this.atlas);
  final VoxelFrame frame;
  final ui.Image? atlas;

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
    ..shader = _shader;

  late final Paint _plainPaint = Paint()..blendMode = ui.BlendMode.srcOver;

  late final Paint _edgePaint = Paint()..blendMode = ui.BlendMode.srcOver;

  @override
  void paint(Canvas canvas, Size size) {
    final SkyPalette sky = frame.sky;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          <Color>[sky.zenith, sky.horizon],
        ),
    );
    _drawSkyDecor(canvas, size);
    // R25：批量网格优先（每材质 1 次 drawVertices，GPU 加速）；占位空帧回退逐面。
    if (frame.opaquePlain != null ||
        frame.opaqueTextured != null ||
        frame.waterBatch != null ||
        frame.edges != null) {
      _drawBatched(canvas);
    } else {
      final bool textured = _shader != null;
      _drawFaces(canvas, frame.opaque, textured);
      _drawFaces(canvas, frame.translucent, textured);
    }
  }

  /// R25：批量提交。不透明纯色 → 贴图 → 水面 → 描边线段，各 1 次 drawVertices。
  void _drawBatched(Canvas canvas) {
    final VoxelFrame f = frame;
    if (f.opaquePlain != null) {
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          f.opaquePlain!.positions,
          colors: f.opaquePlain!.colors,
        ),
        ui.BlendMode.srcOver,
        _plainPaint,
      );
    }
    if (f.opaqueTextured != null) {
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          f.opaqueTextured!.positions,
          colors: f.opaqueTextured!.colors,
          textureCoordinates: f.opaqueTextured!.uv!,
        ),
        ui.BlendMode.srcOver,
        _texPaint,
      );
    }
    if (f.waterBatch != null) {
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          f.waterBatch!.positions,
          colors: f.waterBatch!.colors,
          textureCoordinates: f.waterBatch!.uv!,
        ),
        ui.BlendMode.srcOver,
        _texPaint,
      );
    }
    if (f.edges != null) {
      // 描边批次：每条边是细长方块（2 三角形），一次性提交。
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          f.edges!.positions,
          colors: f.edges!.colors,
        ),
        ui.BlendMode.srcOver,
        _edgePaint,
      );
    }
  }

  /// 太阳 + 云（天象层）：画在天空渐变之上、地形之下。
  /// 太阳方向来自 [VoxelFrame.sunX/Y/Z]（世界空间），粗略映射到屏幕；夜间 sunWeight≈0 不绘制。
  void _drawSkyDecor(Canvas canvas, Size size) {
    final double sw = frame.sunWeight;
    if (sw > 0.04) {
      final double ang = math.atan2(frame.sunX, frame.sunZ);
      final double sx = size.width * 0.5 + math.sin(ang) * size.width * 0.42;
      final double sy = size.height * 0.62 - frame.sunY * size.height * 0.5;
      if (sy > -60 && sy < size.height) {
        final double r = 24 + sw * 16;
        canvas.drawCircle(
          Offset(sx, sy),
          r,
          Paint()
            ..color = Color.fromARGB(
              (255 * sw.clamp(0.25, 1)).round(), 255, (200 * sw).round() + 40, 120),
        );
        canvas.drawCircle(
          Offset(sx, sy),
          r * 2.4,
          Paint()
            ..color = Color.fromARGB((70 * sw).round(), 255, 235, 160)
            ..blendMode = ui.BlendMode.screen,
        );
      }
    }
    // 云：自然云朵形态——柔边叠加团块（边缘高斯模糊），不再是硬边方块/椭圆。
    // 每团由主团 + 两个错位子团拼出蓬松轮廓，半透明白叠加。
    for (int i = 0; i < 5; i++) {
      final double cx = (size.width * (0.08 + 0.21 * i)) % size.width;
      final double cy = size.height * (0.20 + 0.035 * (i % 3));
      for (final (double ox, double oy, double w, double h) in const <
          (double, double, double, double)>[
        (-34, 6, 70, 28),
        (38, 4, 64, 26),
        (0, 0, 130, 36),
      ]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + ox, cy + oy),
            width: w,
            height: h,
          ),
          Paint()
            ..color = const Color(0xC0FFFFFF)
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9),
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

  @override
  bool shouldRepaint(covariant _VoxelFramePainter old) =>
      !identical(old.frame, frame) || !identical(old.atlas, atlas);
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            Icon(icon, size: 16, color: const Color(0xFFF2F5FA)),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Color(0xFFF2F5FA), fontSize: 12)),
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
  const _Joystick({required this.onChanged});
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
      onPanStart: (DragStartDetails d) => _update(d.localPosition),
      onPanUpdate: (DragUpdateDetails d) => _update(d.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
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
        width: 64,
        height: 64,
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

/// 3D 体素世界全屏页（Phase 1 预览入口）。
///
/// 顶栏：返回 · 标题 · 当前 seed 短哈希 · 「换个世界」（验证 seed 决定地形）。
class VoxelWorld3DPage extends StatefulWidget {
  const VoxelWorld3DPage({super.key, this.seed = VoxelWorld.defaultSeed});

  final int seed;

  @override
  State<VoxelWorld3DPage> createState() => _VoxelWorld3DPageState();
}

class _VoxelWorld3DPageState extends State<VoxelWorld3DPage> {
  late int _seed = widget.seed;
  late VoxelWorld _world = VoxelWorld(seed: _seed);

  /// 子视图外送的当前机位（拍照取景用）。
  late final ValueNotifier<VoxelCamera> _cameraOut =
      ValueNotifier<VoxelCamera>(VoxelCamera.overview(_world));

  @override
  void dispose() {
    _cameraOut.dispose();
    super.dispose();
  }

  void _reroll() {
    setState(() {
      _seed = _seed * 31 + 17 & 0x7fffffff;
      _world = VoxelWorld(seed: _seed);
    });
  }

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
              child: VoxelWorldView3D(world: _world, cameraOut: _cameraOut),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Row(
                  children: <Widget>[
                    _GlassCircleButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      '体素世界 $_seedTag',
                      style: AppTextStyles.subtitle.copyWith(
                        color: const Color(0xFFF2F5FA),
                      ),
                    ),
                    const Spacer(),
                    _GlassCircleButton(
                      icon: Icons.shuffle_rounded,
                      onTap: _reroll,
                    ),
                    const SizedBox(width: AppSpace.xs),
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
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('已设为「${active.name}」的场景背景'),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    // #168：2.5D 画布降为 3D 内附加玩法，从 3D 世界可回退进入。
                    _GlassCircleButton(
                      icon: Icons.auto_awesome,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const VoxelCanvasPage(),
                        ),
                      ),
                    ),
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
    required this.onClose,
  });

  final double fov;
  final ValueChanged<double> onFov;
  final VoidCallback onShutter;
  final VoidCallback onGallery;
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
              value: fov.clamp(0.35, 1.5),
              min: 0.35,
              max: 1.5,
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
