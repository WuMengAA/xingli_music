/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 世界内空间音效引擎（Phase 3）
/// ════════════════════════════════════════════════════════════════════════
///
/// 把 [VoxelWorld] 里的地物翻译成**有位置的声音**，并随相机移动实时更新
/// 音量 / 声像 / 隔音，交给 `services/audio/spatial` 的 [SpatialMixer] 播放。
///
/// ### 遵循用户既定约束
/// - **最多 4 条音轨**（[SpatialSound.maxTracks]）：本引擎同时最多点亮
///   [maxSources] = 4 个世界音源，超出的按「响度」淘汰；
/// - **声道空间化**：以相机为几何中心，音源方位投影到相机右向量 →
///   声像（-1 全左 / +1 全右），前后用增益近似；
/// - **材料隔音**：相机→音源连线做 DDA 体素步进，统计遮挡方块数与
///   主导材料，走 [transmissionLoss] 衰减；
/// - **物体动能**：水面按连通面积估算响度（面积越大水声越厚）。
///
/// ### 为什么不用「每方块一个播放器」
/// 24×24 的世界里水方块动辄上百个，逐块播放会瞬间打爆音频通道。
/// 引擎改为**聚类**：同类地物按网格聚成音源簇，取质心作发声点，
/// 簇内方块数决定基础响度。
library;

import 'dart:async';
import 'dart:math' as math;

import '../../services/audio/spatial/spatial_mixer.dart';
import '../../services/audio/spatial/spatial_models.dart';
import 'voxel_camera.dart';
import 'voxel_world.dart';
import 'voxel_world_types.dart';

/// 世界音源类型。
enum WorldSfx {
  /// 水（河/湖面）。
  water,

  /// 树叶沙沙。
  leaves,

  /// 鸟鸣（有林地时出现）。
  birds,

  /// 高处的风。
  wind,

  /// 篝火（玩家放置，Phase 3 预留）。
  campfire,
}

/// 音源类型 → 素材 + 声学材料。
class SfxSpec {
  const SfxSpec({
    required this.asset,
    required this.material,
    required this.baseVolume,
    required this.refDistance,
  });

  /// 素材路径（`assets/` 前缀，由 SpatialPlayer 转 AssetSource）。
  final String asset;

  /// 承载材料（决定隔音曲线）。
  final SoundMaterial material;

  /// 基础音量（0~1，未计距离/隔音）。
  final double baseVolume;

  /// 参考距离（方块）：超过该距离开始明显衰减。
  final double refDistance;
}

const Map<WorldSfx, SfxSpec> _kSfxSpecs = <WorldSfx, SfxSpec>{
  // 水：glass 材料（导声极好），传得远
  WorldSfx.water: SfxSpec(
    asset: 'assets/audio/beach_waves_a.m4a',
    material: SoundMaterial.glass,
    baseVolume: 0.55,
    refDistance: 10,
  ),
  // 叶：wool 一样吸音，衰减快
  WorldSfx.leaves: SfxSpec(
    asset: 'assets/audio/leaves_rustle_a.m4a',
    material: SoundMaterial.wool,
    baseVolume: 0.42,
    refDistance: 7,
  ),
  WorldSfx.birds: SfxSpec(
    asset: 'assets/audio/birds_chirp_a.m4a',
    material: SoundMaterial.wood,
    baseVolume: 0.34,
    refDistance: 14,
  ),
  WorldSfx.wind: SfxSpec(
    asset: 'assets/audio/bamboo_wind_a.m4a',
    material: SoundMaterial.stone,
    baseVolume: 0.30,
    refDistance: 18,
  ),
  WorldSfx.campfire: SfxSpec(
    asset: 'assets/audio/campfire_a.m4a',
    material: SoundMaterial.wood,
    baseVolume: 0.50,
    refDistance: 8,
  ),
};

/// 世界里的一个发声点。
class WorldAudioSource {
  const WorldAudioSource({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.z,
    this.strength = 1.0,
    this.chance,
  });

  final String id;
  final WorldSfx kind;

  /// 发声点世界坐标（方块单位，取簇质心）。
  final double x, y, z;

  /// 簇规模折算的响度系数（0~1）。
  final double strength;

  /// 触发概率（鸟鸣：每片自然叶 0.01% 概率；null = 必然触发）。
  final double? chance;

  SfxSpec get spec => _kSfxSpecs[kind]!;

  /// 转为可播放的 [SpatialSound]（单轨；4 音轨预算留给多音源并发）。
  SpatialSound toSound(SpatialChannel channel) => SpatialSound(
        id: id,
        name: kind.name,
        material: spec.material,
        tracks: <SpatialTrack>[
          SpatialTrack(
            id: '${id}_t0',
            channel: channel,
            volume: (spec.baseVolume * strength).clamp(0.0, 1.0),
            audioPath: spec.asset,
          ),
        ],
      );
}

/// 音源在当前机位下的实时听感参数。
class SourceDynamics {
  const SourceDynamics({
    required this.gain,
    required this.pan,
    required this.walls,
    required this.distance,
  });

  /// 距离衰减倍率（0~1）。
  final double gain;

  /// 声像（-1 全左 / +1 全右）。
  final double pan;

  /// 相机与音源之间的遮挡方块数。
  final int walls;

  /// 欧氏距离（方块）。
  final double distance;

  /// 折算成几何声道（用于无 balance 支持的平台降级）。
  SpatialChannel get channel {
    if (pan < -0.45) return SpatialChannel.left;
    if (pan > 0.45) return SpatialChannel.right;
    return SpatialChannel.center;
  }
}

/// 世界音效引擎。
///
/// 用法：
/// ```dart
/// final engine = WorldAudioEngine(world);
/// await engine.start();          // 扫描 + 起播
/// engine.onCamera(camera);       // 每 tick 调（内部节流）
/// await engine.dispose();
/// ```
class WorldAudioEngine {
  WorldAudioEngine(
    this.world, {
    SpatialMixer? mixer,
    this.maxSources = 4,
    this.updateInterval = const Duration(milliseconds: 400),
    List<WorldAudioSource>? presetSources,
  })  : _mixer = mixer ?? SpatialMixer(),
        _sources = presetSources ?? const <WorldAudioSource>[];

  final VoxelWorld world;
  final SpatialMixer _mixer;

  /// 同时点亮的音源上限（对齐「一个音效最多 4 音轨」的预算）。
  final int maxSources;

  /// 动态参数更新节流间隔（避免每帧 setVolume 打爆平台通道）。
  final Duration updateInterval;

  List<WorldAudioSource> _sources = const <WorldAudioSource>[];
  final Set<String> _playing = <String>{};
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _disposed = false;

  /// 随机源（鸟鸣概率触发用）。
  final math.Random _rng = math.Random();

  /// 全局音量因子（R23i：主界面「主音量 × 背景声」同步进来，游戏与全局共享）。
  double _globalVol = 1.0;
  VoxelCamera? _lastCamera;

  /// 设置全局音量（0~1），立即按最近机位重算所有在播音源。
  void setGlobalVolume(double v) {
    _globalVol = v.clamp(0.0, 1.0);
    final VoxelCamera? cam = _lastCamera;
    if (cam != null) unawaited(_apply(cam, force: true));
  }

  /// 扫描出的全部候选音源（只读）。
  List<WorldAudioSource> get sources => List<WorldAudioSource>.unmodifiable(_sources);

  /// 当前在播的音源 id。
  Set<String> get playingIds => Set<String>.unmodifiable(_playing);

  /// 扫描世界并准备音源（不起播，起播交给首次 [onCamera]）。
  ///
  /// H2：若构造时已注入 `presetSources`（主页背景重放 16×16 音效），
  /// 则直接使用注入源、不重新扫描。
  void prepare() {
    if (_sources.isEmpty) _sources = scanSources(world);
  }

  /// 扫描 + 按初始机位起播。
  Future<void> start(VoxelCamera camera) async {
    if (_sources.isEmpty) prepare();
    await _apply(camera, force: true);
  }

  /// 相机变化回调（每 tick 调用，内部按 [updateInterval] 节流）。
  void onCamera(VoxelCamera camera) {
    if (_disposed || _busy) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastUpdate) < updateInterval) return;
    _lastUpdate = now;
    unawaited(_apply(camera));
  }

  Future<void> _apply(VoxelCamera camera, {bool force = false}) async {
    if (_disposed || _busy) return;
    _busy = true;
    try {
      // 1) 算每个音源的听感参数，按「有效响度」排序取前 maxSources
      final List<(WorldAudioSource, SourceDynamics)> ranked =
          <(WorldAudioSource, SourceDynamics)>[
        for (final WorldAudioSource s in _sources) (s, dynamicsFor(s, camera)),
      ]..sort((
              (WorldAudioSource, SourceDynamics) a,
              (WorldAudioSource, SourceDynamics) b,
            ) =>
            b.$2.gain.compareTo(a.$2.gain));

      final List<(WorldAudioSource, SourceDynamics)> keep = ranked
          .take(maxSources)
          .where(((WorldAudioSource, SourceDynamics) e) {
        // R29：鸟鸣按概率触发（每片自然叶 0.01%），不触发则该 tick 静音。
        if (e.$1.chance != null && _rng.nextDouble() >= e.$1.chance!) {
          return false;
        }
        return e.$2.gain > 0.02;
      }).toList();
      final Set<String> keepIds =
          keep.map(((WorldAudioSource, SourceDynamics) e) => e.$1.id).toSet();

      // 2) 停掉不在名单里的
      for (final String id in _playing.toList()) {
        if (!keepIds.contains(id)) {
          await _mixer.stopById(id);
          _playing.remove(id);
        }
      }

      // 3) 起播新的 / 更新在播的
      _lastCamera = camera;
      for (final (WorldAudioSource s, SourceDynamics d) in keep) {
        if (_disposed) return;
        if (!_playing.contains(s.id)) {
          // R23i：起播音量也乘全局因子，避免全局音量变化瞬间爆音。
          await _mixer.play(
            s.toSound(d.channel).scaled(_globalVol),
            walls: d.walls,
          );
          _playing.add(s.id);
        }
        await _mixer.updateDynamics(
          s.id,
          gain: (d.gain * _globalVol).clamp(0.0, 1.0),
          pan: d.pan,
          walls: d.walls,
        );
      }
    } finally {
      _busy = false;
    }
  }

  /// 计算单个音源在当前机位下的听感参数（纯函数，可单测）。
  SourceDynamics dynamicsFor(WorldAudioSource s, VoxelCamera camera) {
    final Vec3 eye = camera.position;
    final Vec3 delta = Vec3(s.x - eye.x, s.y - eye.y, s.z - eye.z);
    final double dist = delta.length;

    // 距离衰减：反平方软化版，refDistance 处约 0.5
    final double ref = s.spec.refDistance;
    final double atten = 1.0 / (1.0 + (dist / ref) * (dist / ref));

    // 遮挡：DDA 体素步进统计挡住的方块数
    final int walls = occlusionBetween(world, eye, Vec3(s.x, s.y, s.z));

    // 方位：投影到相机右向量做声像；背后的声音再压一档
    final ViewBasis basis = camera.basis;
    final Vec3 dir = delta.normalized;
    final double pan = dir.dot(basis.right).clamp(-1.0, 1.0);
    final double front = dir.dot(basis.forward);
    final double backDamp = front >= 0 ? 1.0 : 0.75;

    final double gain = (atten * s.strength * backDamp).clamp(0.0, 1.0);
    return SourceDynamics(
      gain: gain,
      pan: pan,
      walls: walls,
      distance: dist,
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _playing.clear();
    await _mixer.dispose();
  }

  // ── 静态：世界扫描 / 遮挡 ────────────────────────────────

  /// 扫描世界，把地物聚成音源簇。
  ///
  /// 聚类粒度 [cell]（默认 8 格）：同一网格内的同类方块合成一个发声点，
  /// 取质心作坐标，方块数折算 [WorldAudioSource.strength]。
  static List<WorldAudioSource> scanSources(VoxelWorld world, {int cell = 8}) {
    final Map<String, _Cluster> water = <String, _Cluster>{};
    final Map<String, _Cluster> leaves = <String, _Cluster>{};

    for (int x = 0; x < world.sizeX; x++) {
      for (int z = 0; z < world.sizeZ; z++) {
        for (int y = 0; y < world.maxY; y++) {
          final Voxel v = world.get(x, y, z);
          if (v == Voxel.air) continue;
          if (v == Voxel.water) {
            // 只有**水面**发声（水下不重复计数）
            if (world.get(x, y + 1, z) != Voxel.air) continue;
            _addTo(water, cell, x, y, z);
          } else if (v == Voxel.leaves) {
            _addTo(leaves, cell, x, y, z);
          }
        }
      }
    }

    final List<WorldAudioSource> out = <WorldAudioSource>[];

    // 水：簇内方块数 ≥ 6 才成"一片水"
    water.forEach((String key, _Cluster c) {
      if (c.count < 6) return;
      out.add(WorldAudioSource(
        id: 'water_$key',
        kind: WorldSfx.water,
        x: c.cx,
        y: c.cy,
        z: c.cz,
        strength: waterStrengthFor(c.count),
      ));
    });

    // 叶：≥ 12 块才算"树林"；同点附加鸟鸣（弱一档）
    leaves.forEach((String key, _Cluster c) {
      if (c.count < 12) return;
      final double st = _strength(c.count, full: 90);
      out.add(WorldAudioSource(
        id: 'leaves_$key',
        kind: WorldSfx.leaves,
        x: c.cx,
        y: c.cy,
        z: c.cz,
        strength: st,
      ));
      out.add(WorldAudioSource(
        id: 'birds_$key',
        kind: WorldSfx.birds,
        x: c.cx,
        y: c.cy + 2,
        z: c.cz,
        strength: st * 0.8,
        // R29：每片自然叶 0.01% 概率生存鸟鸣（按簇内叶数折算）。
        chance: birdChanceFor(c.count),
      ));
    });

    // 风：世界最高点上方（山顶风声），恒定 1 个
    final (int px, int py, int pz) = _highestPoint(world);
    if (py > world.waterLevel + 6) {
      out.add(WorldAudioSource(
        id: 'wind_peak',
        kind: WorldSfx.wind,
        x: px + 0.5,
        y: py + 2.0,
        z: pz + 0.5,
        strength: 0.9,
      ));
    }

    return out;
  }

  /// 相机到音源连线上的**遮挡方块数**（DDA 体素步进）。
  ///
  /// 只统计 [VoxelX.occludes] 为真的方块：水和树叶不算墙
  /// （水导声、叶只吸音，已在材料衰减里体现）。
  static int occlusionBetween(VoxelWorld world, Vec3 from, Vec3 to) {
    final Vec3 d = to - from;
    final double dist = d.length;
    if (dist < 1e-6) return 0;
    // 步长半格：足够密，又不至于把一个方块数成两次（下方去重）
    final int steps = math.min(256, (dist * 2).ceil());
    final Vec3 step = d * (1.0 / steps);

    int walls = 0;
    int lastX = -9999, lastY = -9999, lastZ = -9999;
    for (int i = 1; i < steps; i++) {
      final double px = from.x + step.x * i;
      final double py = from.y + step.y * i;
      final double pz = from.z + step.z * i;
      final int bx = px.floor();
      final int by = py.floor();
      final int bz = pz.floor();
      if (bx == lastX && by == lastY && bz == lastZ) continue;
      lastX = bx;
      lastY = by;
      lastZ = bz;
      if (world.get(bx, by, bz).occludes) walls++;
    }
    return walls;
  }

  static void _addTo(
    Map<String, _Cluster> map,
    int cell,
    int x,
    int y,
    int z,
  ) {
    final String key = '${x ~/ cell}_${z ~/ cell}';
    (map[key] ??= _Cluster()).add(x + 0.5, y + 0.5, z + 0.5);
  }

  /// 方块数 → 响度系数（对数压缩，避免大湖直接爆音）。
  static double _strength(int count, {required int full}) {
    final double t = (count / full).clamp(0.0, 1.0);
    return (0.35 + 0.65 * math.sqrt(t)).clamp(0.0, 1.0);
  }

  /// 水边音效增益：按水量从 10% 增长到 75%（R29 用户要求）。
  ///
  /// 既有管线 effective = baseVolume × strength²（strength 在两处各用一次），
  /// 这里反解 strength 使 effective ≈ target，从而精确落在 0.10~0.75 区间。
  static double waterStrengthFor(int count, {int full = 80}) {
    final double frac = (count / full).clamp(0.0, 1.0);
    final double target = 0.10 + 0.65 * frac;
    final double bv = _kSfxSpecs[WorldSfx.water]!.baseVolume;
    return math.sqrt((target / bv).clamp(0.0, 1.0));
  }

  /// 鸟鸣触发概率：每片自然叶 0.01%（封顶 0.95）。
  static double birdChanceFor(int leafCount) =>
      (leafCount * 0.0001).clamp(0.0, 0.95);

  static (int, int, int) _highestPoint(VoxelWorld world) {
    int bx = 0, by = 0, bz = 0;
    for (int x = 0; x < world.sizeX; x++) {
      for (int z = 0; z < world.sizeZ; z++) {
        final int h = world.surfaceHeight(x, z);
        if (h > by) {
          by = h;
          bx = x;
          bz = z;
        }
      }
    }
    return (bx, by, bz);
  }
}

/// 聚类累加器。
class _Cluster {
  double _sx = 0, _sy = 0, _sz = 0;
  int count = 0;

  void add(double x, double y, double z) {
    _sx += x;
    _sy += y;
    _sz += z;
    count++;
  }

  double get cx => count == 0 ? 0 : _sx / count;
  double get cy => count == 0 ? 0 : _sy / count;
  double get cz => count == 0 ? 0 : _sz / count;
}
