/// ════════════════════════════════════════════════════════════════════════
/// 体素世界（类我的世界 · 3D 地形 · 无限地图）
/// ════════════════════════════════════════════════════════════════════════
///
/// R23k 升级：
/// - **Perlin 梯度噪声**（替代值噪声）生成高度图，同 seed 完全确定；
/// - **无限地图**：`sizeX×sizeZ` 是预生成的「出生大陆」足迹，越界坐标由
///   确定性列生成函数即时补列（带缓存），玩家可以走到任意远；
/// - **编辑覆盖层**：`setVoxel` 支持任意坐标，越界修改也生效（破坏/放置）。
///
/// 纯数据模型 + 确定性生成，不依赖 Flutter 渲染，可在任意 Isolate / 测试使用。
library;

import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File, FileSystemEntity, Platform;
import 'dart:math' as math;
import 'dart:typed_data' show Int32List;

import 'voxel_daynight.dart';
import 'voxel_world_types.dart';

/// 体素世界：出生大陆 [sizeX]×[sizeZ]，最大高度 [maxY]，水平无限延伸。
/// 新建世界的可选参数（cl29）：作弊 / 结构 / 浮空岛等「一堆」开关的单一真相源。
/// 默认全开 = 与历史版本行为一致（旧存档 / 无 options 时回落到此默认值）。
class WorldOptions {
  // R28：作弊 / 浮空岛默认关闭——新建世界不再默认「可作弊 + 满屏浮岛」，
  // 用户须主动勾选。仅旧存档（fromJson 缺字段）回落到 true 以兼容历史行为。
  const WorldOptions({
    this.cheats = false,
    this.structures = true,
    this.floatingIslands = false,
  });

  /// 作弊：开启后游戏内可随时切换生存 / 创造模式（热栏「模式」按钮）。
  final bool cheats;
  /// 结构：沙漠沙堡等确定性后处理结构是否生成。
  final bool structures;
  /// 浮空岛：悬空草顶石核团块是否生成（R26e 设计特性）。
  final bool floatingIslands;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cheats': cheats,
        'structures': structures,
        'floatingIslands': floatingIslands,
      };

  static WorldOptions fromJson(dynamic json) {
    if (json is! Map) return const WorldOptions();
    bool b(String k) => json[k] is bool ? json[k] as bool : true;
    return WorldOptions(
      cheats: b('cheats'),
      structures: b('structures'),
      floatingIslands: b('floatingIslands'),
    );
  }
}

/// 结构种类（数据驱动：决定模板与生成群系，大跃进扩展）。
enum StructureKind {
  sandcastle,
  villageHut,
  desertTemple,
}

class VoxelWorld {
  VoxelWorld({
    this.sizeX = 24,
    this.sizeZ = 24,
    // G6（用户确认）：世界最高 y=128、最低 y=0（原 256）。海平面=32。
    this.maxY = 128,
    this.seed = defaultSeed,
    this.waterLevel = 32,
    this.options = const WorldOptions(),
  }) : _blocks = List<Voxel>.filled(sizeX * sizeZ * maxY, Voxel.air) {
    _generate(seed);
  }

  /// 基准种子：与历史版本行为对齐的默认值。
  ///
  /// 地形噪声按「相对基准种子的偏移」采样，`seed == defaultSeed` 时偏移恒为 0。
  static const int defaultSeed = 20260810;

  /// 预生成大陆的宽度 / 深度（水平可无限延伸，此处只是出生区足迹）。
  final int sizeX;
  final int sizeZ;
  final int maxY;
  final int waterLevel;

  /// 世界种子：同 seed ⇒ 逐格相同的世界（拍照复现的技术前提）。
  final int seed;

  /// 新建世界可选参数（cl29：作弊 / 结构 / 浮空岛等开关）。
  final WorldOptions options;

  /// 噪声采样偏移（由 [seed] 派生，基准种子时为 0）。
  late final double _shiftX = _noiseShift(seed, 1);
  late final double _shiftZ = _noiseShift(seed, 2);

  /// 出生大陆预生成数组。
  final List<Voxel> _blocks;

  /// 编辑覆盖层：按 chunk 分桶。外层 key = (cx,cz)，内层 key = chunk 内
  /// 局部编码 (lx | ly<<4 | lz<<11)，任意坐标（含大陆外、负坐标、大范围）
  /// 都即时生效。get 优先查它 → 破坏/放置即时可见。
  /// cl38（开放世界）：原为 Map<int,Voxel>（_editKey=x*65536+z*256+y，z 锁
  /// 0-255、x±32767）→ 改为 chunk 分桶，(cx,cz) 独立 int 不再受限，且天然
  /// 支撑 P2 流式加载 / P4 分块存档（每 chunk 独立读写）。
  final Map<(int, int), Map<int, Voxel>> _edits =
      <(int, int), Map<int, Voxel>>{};

  /// 开放世界 P2：编辑层分块存储（null = 流式关闭，沿用旧行为）。
  /// 由应用层世界创建后调用 [initChunkStore] 启用；单测/非应用上下文保持 null
  /// （[VoxelWorld] 不强制依赖 dart:io，仍可在 Isolate / 测试使用）。
  ChunkEditStore? _chunkStore;

  /// 流式加载半径（chunk 数）：玩家周围此范围内编辑层常驻 RAM。
  static const int streamRadius = 8;
  /// 卸载缓冲：超出 [streamRadius] + [streamMargin] 的 chunk 才卸载到磁盘，
  /// 避免玩家在半径边界来回走动时频繁加载/卸载（抖动）。
  static const int streamMargin = 3;

  /// 大陆外列生成缓存：key = x*65521 + z，值为整列方块。
  /// 上限 [maxGenColumns] 列，超出删一半（R23o 不再整体清空）。
  final Map<int, List<Voxel>> _genCache = <int, List<Voxel>>{};

  /// 高度缓存（R23o）：列 → 地形高度，避免同一列高度重复算 fbm。
  final Map<int, int> _heightCache = <int, int>{};

  /// 树信息缓存（R23o）：列 → (有无树, 树顶Y)。
  final Map<int, (bool, int)> _treeCache = <int, (bool, int)>{};

  /// 上限 [maxGenColumns] 列，超出删一半（R23o 不再整体清空）。
  /// R23s 性能：提到 16384 覆盖整个视距窗口（128×128 = 16384 列），
  /// 避免玩家移动时窗口滑动导致列被反复重建（fbm + 树，卡顿主因之一）。
  static const int maxGenColumns = 16384;

  int _idx(int x, int y, int z) => x + sizeX * (z + sizeZ * y);

  /// chunk 边长（列）。世界按 16×16 列分块；y 方向不分块（整列 maxY 高）。
  static const int kChunkSize = 16;

  /// (x,z) → chunk 坐标（record (cx,cz)）。Dart ~/ 向负无穷取整 → 负坐标
  /// 也正确分桶，cx/cz 为独立 int，范围 ±很大（不再受限）。
  static (int, int) _chunkOf(int x, int z) =>
      (x ~/ kChunkSize, z ~/ kChunkSize);

  /// chunk 内局部编码：lx(bit0-3) | ly(bit4-10) | lz(bit11-14)。
  /// 负坐标用 %+size 修正回 [0,size)，保证 key 唯一且可逆。
  static int _localKey(int x, int y, int z) {
    final int lx = ((x % kChunkSize) + kChunkSize) % kChunkSize;
    final int lz = ((z % kChunkSize) + kChunkSize) % kChunkSize;
    return lx | (y << 4) | (lz << 11);
  }

  /// 由局部 key 反解 (lx,ly,lz)（toJson/loadJson 往返用）。
  static (int, int, int) _unpackLocal(int k) =>
      (k & 15, (k >> 4) & 127, (k >> 11) & 15);

  /// 取方块（任意坐标；大陆外即时确定性生成，越界高度返回空气）。
  Voxel get(int x, int y, int z) {
    if (y < 0 || y >= maxY) return Voxel.air;
    // R23o：edits 为空时跳过 Map 查找（渲染热路径，每帧数万次 get）。
    if (_edits.isNotEmpty) {
      final Map<int, Voxel>? chunk = _edits[_chunkOf(x, z)];
      if (chunk != null) {
        final Voxel? edit = chunk[_localKey(x, y, z)];
        if (edit != null) return edit;
      }
    }
    if (x >= 0 && z >= 0 && x < sizeX && z < sizeZ) {
      return _blocks[_idx(x, y, z)];
    }
    return _infiniteColumn(x, z)[y];
  }

  /// 是否实心（用于面剔除）。
  bool isSolid(int x, int y, int z) {
    final Voxel v = get(x, y, z);
    return kVoxelSpecs[v]!.solid;
  }

  /// 地表高度（最高实心方块 y，无水则取水面上方）。任意坐标。
  int surfaceHeight(int x, int z) {
    int top = 0;
    for (int y = 0; y < maxY; y++) {
      if (isSolid(x, y, z)) top = y;
    }
    return top;
  }

  /// 生成地形高度（R23q：缓存版，渲染器"地表带"遍历用）。
  ///
  /// 返回 Perlin 噪声地形高度（不含树/编辑）；树冠最高约 +6，渲染时
  /// 在该值基础上放宽到 +7。比逐格扫 [surfaceHeight] 快一个数量级。
  int terrainHeightAt(int x, int z) => _heightCached(x, z);

  /// 公开修改方块（MC 玩法：破坏/放置）。任意坐标，越界也生效。
  void setVoxel(int x, int y, int z, Voxel v) {
    if (y < 0 || y >= maxY) return;
    (_edits.putIfAbsent(_chunkOf(x, z), () => <int, Voxel>{}))
        [_localKey(x, y, z)] = v;
    _dirtyColumn(x, z);
    _syncLight(x, y, z, v);
  }

  // ── G4：水流动（MC 式，1s=20tick 驱动）──────────────────
  //
  // 放置水源后，向 4 水平邻 + 下方扩散，最多 [kWaterSpread] 格（用户确认 9 格）。
  // 每个扩散出的水格携带「剩余扩散距离」，每 tick 递减，到 0 停止 →
  // 距离限制不会被新位置重置（防无限扩散）。流动水写进编辑层（与破坏/放置
  // 同一持久化通道），渲染走既有 water 路径。

  /// 水最大扩散距离（用户确认：四周 9 格范围）。
  static const int kWaterSpread = 9;

  /// 待扩散队列：位置 + 剩余扩散距离。放置水时加入；扩散到边界/无可流空间
  /// 或距离耗尽后自然清空。
  final List<(int, int, int, int)> _waterQueue = <(int, int, int, int)>[];

  /// 登记一个水源（放置水时调用），触发扩散。
  void addWaterSource(int x, int y, int z) {
    if (y < 0 || y >= maxY) return;
    _waterQueue.add((x, y, z, kWaterSpread));
  }

  /// 是否可被水占据（空气）。
  bool _waterable(int x, int y, int z) {
    if (y < 0 || y >= maxY) return false;
    final Voxel v = get(x, y, z);
    return v == Voxel.air;
  }

  /// 单步扩散（每 tick 调一次）：对队列中剩余距离 > 0 的水格，向 4 水平邻 +
  /// 下方各扩散 1 格；扩散出的新水格带 remaining-1 入队。返回**本次新写入的
  /// 水位置**（空表 = 无可流空间 / 距离耗尽，扩散自然结束）——调用方据此
  /// 失效对应区块几何缓存并置脏。
  List<(int, int, int)> spreadWater() {
    if (_waterQueue.isEmpty) return const <(int, int, int)>[];
    final List<(int, int, int)> wrote = <(int, int, int)>[];
    final List<(int, int, int, int)> next = <(int, int, int, int)>[];
    const List<(int, int, int)> dirs = <(int, int, int)>[
      (1, 0, 0),
      (-1, 0, 0),
      (0, 0, 1),
      (0, 0, -1),
      (0, -1, 0), // 下
    ];
    for (final (int sx, int sy, int sz, int rem) in _waterQueue) {
      if (rem <= 0) continue;
      for (final (int dx, int dy, int dz) in dirs) {
        final int nx = sx + dx, ny = sy + dy, nz = sz + dz;
        if (!_waterable(nx, ny, nz)) continue;
        setVoxel(nx, ny, nz, Voxel.water);
        wrote.add((nx, ny, nz));
        next.add((nx, ny, nz, rem - 1));
      }
    }
    _waterQueue
      ..clear()
      ..addAll(next);
    return wrote;
  }

  // ── R23v 方块光源登记 ────────────────────────────────────
  /// 已放置的发光方块（世界坐标 → 方块类型）。
  ///
  /// 地形生成不产出发光方块，光源只可能来自玩家放置，故集合天然稀疏；
  /// 渲染时按相机位置就近取若干个参与着色，成本可忽略。
  final Map<(int, int, int), Voxel> _lights = <(int, int, int), Voxel>{};

  /// 光源数量硬上限（防止玩家铺满火把把渲染拖死）。
  static const int maxLights = 512;

  /// 只读光源视图。
  Map<(int, int, int), Voxel> get lights => _lights;

  void _syncLight(int x, int y, int z, Voxel v) {
    final bool emits = kBlockLights.containsKey(v);
    final (int, int, int) k = (x, y, z);
    if (emits) {
      if (_lights.length < maxLights || _lights.containsKey(k)) {
        _lights[k] = v;
      }
    } else {
      _lights.remove(k);
    }
  }

  /// 取 [eyeX],[eyeZ] 附近最多 [limit] 个光源（按水平距离近优先）。
  ///
  /// 渲染器每帧调一次；返回空表时着色走纯天光路径，零额外开销。
  List<PointLight> lightsNear(
    double eyeX,
    double eyeZ, {
    double radius = 48,
    int limit = 10,
  }) {
    if (_lights.isEmpty) return const <PointLight>[];
    final List<(double, PointLight)> found = <(double, PointLight)>[];
    final double r2 = radius * radius;
    for (final MapEntry<(int, int, int), Voxel> e in _lights.entries) {
      final double cx = e.key.$1 + 0.5;
      final double cz = e.key.$3 + 0.5;
      final double dx = cx - eyeX;
      final double dz = cz - eyeZ;
      final double d2 = dx * dx + dz * dz;
      if (d2 > r2) continue;
      final ({double strength, double range, int tint}) spec =
          kBlockLights[e.value]!;
      found.add((
        d2,
        PointLight(
          x: cx,
          y: e.key.$2 + 0.5,
          z: cz,
          strength: spec.strength,
          range: spec.range,
          tint: spec.tint,
        ),
      ));
    }
    if (found.isEmpty) return const <PointLight>[];
    found.sort(((double, PointLight) a, (double, PointLight) b) =>
        a.$1.compareTo(b.$1));
    final int n = found.length < limit ? found.length : limit;
    return <PointLight>[for (int i = 0; i < n; i++) found[i].$2];
  }

  /// 编辑后使该列缓存失效（下次 get 重新生成）。
  void _dirtyColumn(int x, int z) {
    final int key = x * 65521 + z;
    _genCache.remove(key);
    _heightCache.remove(key);
    _treeCache.remove(key);
  }

  // ── 出生大陆生成（与无限列同一套确定性列函数，边界连续）────────

  void _generate(int seed) {
    for (int x = 0; x < sizeX; x++) {
      for (int z = 0; z < sizeZ; z++) {
        final List<Voxel> col = _infiniteColumn(x, z);
        for (int y = 0; y < maxY; y++) {
          _blocks[_idx(x, y, z)] = col[y];
        }
      }
    }
  }

  /// 大陆外列生成（确定性，同 (x,z) 恒同；带缓存）。
  ///
  /// R23o：缓存满时**删掉最早插入的一半**而非整体 clear——
  /// 整体清空会让下一帧整窗重建（表现为"区块一直刷新加载"的卡顿抖动）。
  List<Voxel> _infiniteColumn(int x, int z) {
    final int key = x * 65521 + z;
    final List<Voxel>? cached = _genCache[key];
    if (cached != null) return cached;
    if (_genCache.length >= maxGenColumns) {
      final int remove = maxGenColumns ~/ 2;
      final List<int> stale = _genCache.keys.take(remove).toList();
      for (final int k in stale) {
        _genCache.remove(k);
        _heightCache.remove(k);
        _treeCache.remove(k);
      }
    }
    final List<Voxel> col = _buildColumn(x, z);
    _genCache[key] = col;
    return col;
  }

  /// 确定性单列生成：群系 → 高度图（Perlin fbm）→ 分层 → 注水 → 树。
  ///
  /// R23u：接入生物群系（GDD §2.3）——按低频群系噪声选群系，决定地表方块、
  /// 地形基准高度/振幅、植被密度；山顶按 [BiomeSpec.snowLine] 落雪。
  /// R23o：树检查改为「树信息缓存」——每列只算一次邻域树状态，
  /// 不再每次生成都重算邻列 fbm（原实现每列 ≈ 49 邻列 × 2 次 fbm，
  /// 玩家一走窗口滑动 → 大量新列 → 帧率打爆；这是卡顿最大头）。
  List<Voxel> _buildColumn(int x, int z) {
    final List<Voxel> col = List<Voxel>.filled(maxY, Voxel.air);
    final int h = _heightCached(x, z);
    final Biome biome = _biomeAt(x, z);
    final BiomeSpec spec = kBiomes[biome]!;
    final bool snowCap = spec.snowy &&
        h > (spec.baseHeight + spec.amplitude * spec.snowLine);
    final Voxel surface = snowCap ? Voxel.snow : spec.surface;
    // R26e 分层叠加：2D 高度图为基石，逐层叠加洞穴/浮空岛/矿脉（全部 O(列高)）。
    final (bool hasIsland, int islandBase) = _islandInfo(x, z);
    for (int y = 0; y <= h; y++) {
      // 洞穴：低于地表 2 格起、伪 3D 噪声 > 阈值 → 留空（洞内不产矿）。
      // R26r13：用户「地下没有方块，请延到 y=0」——原阈值 0.15 在 ±0.35
      // 实用值域下掏空约 1/3~1/2 地下、连成大空洞，看着像空心。抬到 0.62
      // 且仅浅层(y>4)可挖：地下近全实心到底(y=0)，只留极少数小气穴
      //（保留挖矿趣味），矿脉（y<h-4 的 0.4 尺度噪声）不受影响。
      if (y < h - 1 &&
          y > 3 &&
          (_noise3(x.toDouble(), y.toDouble(), z.toDouble(), 0.16) > 0.60 ||
           _noise3(x.toDouble() + 137.0, y.toDouble() + 71.0, z.toDouble() + 53.0,
                   0.085) > 0.55)) {
        continue;
      }
      Voxel v;
      if (y == h) {
        v = surface;
      } else if (y > h - 3) {
        v = (surface == Voxel.sand || surface == Voxel.snow)
            ? surface
            : spec.subsurface;
      } else {
        v = Voxel.stone;
        // 矿脉：深层石头中的稀有斑块（金 / 铁 / 煤，伪 3D 噪声分型）。
        // 阈值按实测值域标定（伪 3D 噪声@0.4 实际 ±0.42，0.32 触发稀疏斑块）。
        if (y < h - 4) {
          final double ore =
              _noise3(x.toDouble(), y.toDouble(), z.toDouble(), 0.4);
          if (ore.abs() > 0.30) {
            final int t = ((ore * 100).abs().round()) % 7;
            final double depth = y / (h - 4); // 0=近地表 1=最深处
            v = switch (t) {
              0 => Voxel.coalOre,
              1 => Voxel.ironOre,
              2 => Voxel.gold,
              3 => depth > 0.45 ? Voxel.redstoneOre : Voxel.ironOre,
              4 => depth > 0.5 ? Voxel.lapisOre : Voxel.coalOre,
              5 => depth > 0.7 ? Voxel.diamondOre : Voxel.ironOre,
              6 => depth > 0.6 ? Voxel.emeraldOre : Voxel.coalOre,
              _ => Voxel.coalOre,
            };
          }
        }
      }
      col[y] = v;
    }
    // 浮空岛（独立悬浮层，与地面列无关；顶部草 + 内核石）。
    // cl29：受 options.floatingIslands 开关控制（默认开，保持历史行为）。
    if (hasIsland && options.floatingIslands) {
      for (int y = islandBase; y <= islandBase + 2 && y < maxY; y++) {
        col[y] = y == islandBase + 2 ? Voxel.grass : Voxel.stone;
      }
    }
    // 低洼注水 —— G6 分层 + G3 河流（用户确认）：
    //   · 海平面（海洋）= y=32：h < 32 → 注满到 32。
    //   · G3 河流：走廊噪声命中 → 注水到该列水表（下游 32、上游缓升≤43），
    //     形成连续可流动河道（V 型河谷已有下切）。
    //   · 陆地水 32–43（非河道）：池塘/湖泊蓄积地，**概率生成且不允许过多**——
    //     仅当本列高度处于 32–43 的「蓄水带」且确定性噪声命中（概率约 1/4）
    //     才注水到水表（32~43 之间），形成零星河/塘/湖，而非全陆地淹成海。
    //   · 43–64 高山流水/瀑布：极少（概率 ~1/20），仅高山带(h≥43)偶尔注一薄层。
    //   · 地下水 0–32：极少（概率 ~1/24），在地下深层留一条水脉。
    if (h < waterLevel) {
      for (int y = h + 1; y <= waterLevel; y++) {
        col[y] = Voxel.water;
      }
    } else {
      // F3（用户确认）：天坑/高处洼地自然积水——本列高度显著低于 4 邻
      // （形成封闭凹坑）时，即使不在 32–43 蓄水带也注满坑底（水池不空心）。
      final bool pit = h >= waterLevel &&
          h < 64 &&
          terrainHeightAt(x + 1, z) > h + 2 &&
          terrainHeightAt(x - 1, z) > h + 2 &&
          terrainHeightAt(x, z + 1) > h + 2 &&
          terrainHeightAt(x, z - 1) > h + 2;
      // G3 河流优先：与下切共用同一走廊判定（连续河道）。
      final double rv = _riverNoise(x, z, _shiftX, _shiftZ);
      if (rv < -0.22) {
        final int waterTable = (32 + ((h - 40) * 0.5).round().clamp(0, 11))
            .clamp(33, 43);
        for (int y = h + 1; y <= waterTable && y < maxY; y++) {
          col[y] = Voxel.water;
        }
      } else if (pit) {
        // 天坑/洼地：填到坑底上方 1 格（保证有水的实感，不空心）。
        for (int y = h + 1; y <= h + 1 && y < maxY; y++) {
          col[y] = Voxel.water;
        }
      } else if (h < 43) {
        // 陆地蓄水带（32–43）：概率约 1/4，避免整片陆地变湖泊。
        // R26fx3：湖泊概率提高（0.5→0.35）且更分散（频率 0.05→0.07）。
        final double lake = _noise3(x.toDouble(), z.toDouble(), 0.0, 0.07);
        if (lake > 0.35) {
          final int waterTable = (32 + ((lake - 0.35) * 22).round())
              .clamp(33, 43);
          for (int y = h + 1; y <= waterTable && y < maxY; y++) {
            col[y] = Voxel.water;
          }
        }
      } else if (h >= 43 && h < 64) {
        // 高山流水/瀑布带（43–64）：极少（~1/20），只在陡坡处注一薄层。
        final double fall = _noise3(x.toDouble(), z.toDouble(), 7.0, 0.08);
        if (fall > 0.82) {
          for (int y = h + 1; y <= h + 2 && y < maxY; y++) {
            col[y] = Voxel.water;
          }
        }
      }
    }
    // 地下水（0–32）：极少（~1/24），深埋一脉（挖矿时偶遇）。
    if (h > 24) {
      final double gw = _noise3(x.toDouble(), 3.0, z.toDouble(), 0.1);
      if (gw > 0.84) {
        final int gy = (8 + ((gw - 0.84) * 20).round()).clamp(2, 28);
        if (gy < h) col[gy] = Voxel.water;
      }
    }
    // 结构（沙漠沙堡）：确定性散列后处理，覆盖在列生成之上。
    // cl29：受 options.structures 开关控制（默认开）。
    if (options.structures) {
      for (int y = h + 1; y <= h + 4 && y < maxY; y++) {
        final Voxel? sv = _structureBlock(x, z, y, h);
        if (sv != null) col[y] = sv;
      }
    }
    // 树：本列树干 + 树冠，以及 5×5 邻列树冠对本列的覆盖（缓存加速）。
    _applyTrees(col, x, z, h);
    return col;
  }

  /// 生物群系（低频噪声分区，确定性）。
  ///
  /// R23u：单 octave Perlin 低频采样 → 大区块（数百格）连续群系；
  /// 频段：山地（稀）→ 森林 → 平原（常见）→ 沙漠。
  Biome _biomeAt(int x, int z) => _biomeAtS(x, z, _shiftX, _shiftZ);

  /// R26f：生物群系纯函数版（Isolate 预热复用，与实例采样同一算法；
  /// 一致性由测试锁死，避免双实现漂移）。
  static Biome _biomeAtS(int x, int z, double shiftX, double shiftZ) {
    // R26j：群系阈值随种子偏移（±0.06）→ 每个世界群系比例不同
    //（沙漠世界 / 森林世界 / 山地世界），不再千篇一律。默认种子不动。
    final bool isDefault = shiftX == 0 && shiftZ == 0;
    final double bShift = isDefault ? 0 : _styleF(shiftX, shiftZ, 4) * 0.12 - 0.06;
    final double bx = x * 0.012 + 5000 + shiftX * 0.01;
    final double bz = z * 0.012 + 5000 + shiftZ * 0.01;
    final double b = _perlin(bx, bz) + bShift;
    // R27 水域噪声（独立低频场）：低值 → 海洋 / 河流盆地；与陆群系正交，
    // 山体可没入海（岛）、平原可裂河谷，地形更自然。频率更低 → 大水域。
    final double wx = x * 0.006 + 9000 + shiftX * 0.008;
    final double wz = z * 0.006 + 9000 + shiftZ * 0.008;
    final double w = _perlin(wx, wz);
    if (w < -0.30) return Biome.ocean;
    if (w < -0.10) return Biome.river;
    if (b > 0.42) return Biome.snowMountain;
    if (b > 0.28) return Biome.mountain;
    if (b > 0.05) return Biome.forest;
    if (b < -0.15) return Biome.desert;
    return Biome.plains;
  }

  /// 公开生物群系查询（坐标 HUD 用：玩家脚下群系标签）。
  Biome biomeAt(int x, int z) => _biomeAt(x, z);

  /// 树冠半径（菱形叶团）。
  static const int _crownRadius = 2;

  /// 取 (tx,tz) 的树信息（确定性，带缓存，一次算好高度 + 抽签 + 树顶）。
  (bool, int) _treeInfo(int tx, int tz) {
    final int key = tx * 65521 + tz;
    final (bool, int)? c = _treeCache[key];
    if (c != null) return c;
    final bool has = _hasTreeAt(tx, tz);
    final int topY = has ? _heightCached(tx, tz) + _treeTrunk(tx, tz) : 0;
    if (_treeCache.length > maxGenColumns * 8) _treeCache.clear();
    _treeCache[key] = (has, topY);
    return (has, topY);
  }

  /// 判定 (tx, tz) 是否有一棵树（群系植被密度 + 确定性抽签）。
  bool _hasTreeAt(int tx, int tz) {
    final int h = _heightCached(tx, tz);
    if (h <= waterLevel + 1) return false;
    final Biome biome = _biomeAt(tx, tz);
    final BiomeSpec spec = kBiomes[biome]!;
    if (spec.treeDensity <= 0) return false;
    return _treeChance(tx, tz) < spec.treeDensity;
  }

  /// 地形高度（确定性，带缓存；缓存上限与列缓存同步）。
  int _heightCached(int x, int z) {
    final int key = x * 65521 + z;
    return _heightCache.putIfAbsent(key, () => _heightAt(x, z));
  }

  /// 树高（确定性，按群系树干范围）。
  int _treeTrunk(int tx, int tz) => _treeTrunkS(tx, tz, _shiftX, _shiftZ);

  /// R26f：树高纯函数版（Isolate 预热复用）。
  static int _treeTrunkS(int tx, int tz, double shiftX, double shiftZ) {
    final Biome biome = _biomeAtS(tx, tz, shiftX, shiftZ);
    final BiomeSpec spec = kBiomes[biome]!;
    final int span = (spec.maxTrunk - spec.minTrunk + 1).clamp(1, 99);
    return spec.minTrunk + (_hash(tx * 3 + 1, tz * 3 + 5) * span).floor();
  }

  /// R26f：树有无纯函数版（Isolate 预热复用；h 为已算出的地形高度）。
  static bool _hasTreeAtS(
      int tx, int tz, double shiftX, double shiftZ, int h, int waterLevelV) {
    if (h <= waterLevelV + 1) return false;
    final Biome biome = _biomeAtS(tx, tz, shiftX, shiftZ);
    final BiomeSpec spec = kBiomes[biome]!;
    if (spec.treeDensity <= 0) return false;
    return _treeChance(tx, tz) < spec.treeDensity;
  }

  /// 把本列及邻列的树应用到本列（树冠半径 2 → 5×5 邻域足够）。
  void _applyTrees(List<Voxel> col, int x, int z, int selfH) {
    for (int tx = x - _crownRadius; tx <= x + _crownRadius; tx++) {
      for (int tz = z - _crownRadius; tz <= z + _crownRadius; tz++) {
        final (bool has, int topY) = _treeInfo(tx, tz);
        if (!has) continue;
        if (tx == x && tz == z) {
          // 本列树：树干 + 树冠。
          for (int y = selfH + 1; y <= topY && y < maxY; y++) {
            col[y] = Voxel.wood;
          }
          for (int dy = -_crownRadius; dy <= 1; dy++) {
            final int r = dy <= 0 ? _crownRadius + dy : 1;
            for (int dx = -r; dx <= r; dx++) {
              for (int dz = -r; dz <= r; dz++) {
                if (dx == 0 && dz == 0) continue; // 树干占位已填
                final int ly = topY + dy;
                if (ly >= 0 && ly < maxY && col[ly] == Voxel.air) {
                  col[ly] = Voxel.leaves;
                }
              }
            }
          }
        } else {
          // 邻树树冠盖到本列。
          for (int dy = -_crownRadius; dy <= 1; dy++) {
            final int r = dy <= 0 ? _crownRadius + dy : 1;
            if ((x - tx).abs() > r || (z - tz).abs() > r) continue;
            final int ly = topY + dy;
            if (ly >= 0 && ly < maxY && col[ly] == Voxel.air) {
              col[ly] = Voxel.leaves;
            }
          }
        }
      }
    }
  }

  /// 地形高度（确定性，任意坐标；含生物群系基准/振幅）。
  ///
  /// R26e 悬崖增强：对噪声正负区间做幂陡化——正值抬成尖峰、负值削成峡谷，
  /// 地形从「缓坡」变「有陡崖」，代价仅为每列一次幂运算（O(列数)）。
  int _heightAt(int x, int z) =>
      _heightAtS(x, z, _shiftX, _shiftZ, waterLevel, maxY);

  /// R26f：地形高度纯函数版（Isolate 预热复用，与实例采样同一算法）。
  static int _heightAtS(
    int x,
    int z,
    double shiftX,
    double shiftZ,
    int waterLevelV,
    int maxYV,
  ) {
    // R26fx3：群系边界平滑——4 角群系 baseHeight/amplitude 等权混合，
    // 消除硬边界「高低差」（森林/沙漠/山地交界不再悬崖式突变）。
    double mixBase = 0, mixAmp = 0;
    for (int dx = 0; dx <= 1; dx++) {
      for (int dz = 0; dz <= 1; dz++) {
        final BiomeSpec s2 =
            kBiomes[_biomeAtS(x + dx, z + dz, shiftX, shiftZ)]!;
        mixBase += s2.baseHeight * 0.25;
        mixAmp += s2.amplitude * 0.25;
      }
    }
    // R26j：种子风格参数（由 shift 确定性派生，纯函数 → Isolate 与实例一致）。
    // 默认种子（shift=0）保持历史观感不变；换种子才派生风格：
    //   elev 海拔偏移 -3~+3（低海拔世界→更多海洋，高海拔→山地大陆）
    //   ampMul 山体幅度 0.6~1.5（平滑丘陵 ↔ 陡峭崎岖）
    //   warp 域扭曲强度 0~24（打破平直线条，山脊扭成麻花）
    final bool isDefault = shiftX == 0 && shiftZ == 0;
    final double elev = isDefault ? 0 : _styleF(shiftX, shiftZ, 1) * 6.0 - 3.0;
    final double ampMul = isDefault ? 1.0 : 0.6 + _styleF(shiftX, shiftZ, 2) * 0.9;
    final double warp = isDefault ? 0 : _styleF(shiftX, shiftZ, 3) * 24.0;
    // 域扭曲：先算低频扭曲偏移，再用扭曲后的坐标取高度（不同种子山形各异）。
    double sx = x + 1000.5 + shiftX;
    double sz = z + 1000.5 + shiftZ;
    if (warp > 0.01) {
      sx += _perlin(x * 0.02 + 300, z * 0.02 + 300) * warp;
      sz += _perlin(x * 0.02 + 500, z * 0.02 + 500) * warp;
    }
    // R26e 修复：Perlin 在整数网格点恒为 0（梯度点积在顶点归零）——此前
    // defaultSeed 世界高度噪声恒 0、地形恒平。加 0.5 小数偏移恢复起伏。
    final double n = _fbm(sx, sz);
    // 大陆层：超低频噪声（freq≈0.004）决定海洋/大陆宏观轮廓（默认种子为 0）。
    final double cont = isDefault
        ? 0
        : _perlin(
            x * 0.004 + 7000 + shiftX * 0.001,
            z * 0.004 + 7000 + shiftZ * 0.001,
          );
    // Perlin fbm 输出约 ±1 → 群系基准高度 ±振幅。
    double h = mixBase + mixAmp * ampMul * n + cont * 20.0 + elev;
    // R26r8：平滑地形——尖峰/悬崖放大从 ×14 降到 ×4、峡谷从 ×9 降到 ×2.5，
    // 消除突兀峭壁与尖刺，保留缓坡起伏（不再是「陡峭崎岖」）。
    if (n > 0.15) {
      h += math.pow(n - 0.15, 1.6).toDouble() * 4;
    } else if (n < -0.15) {
      h -= math.pow(-(n + 0.15), 1.6).toDouble() * 2.5;
    }
    final int base = h.round().clamp(8, maxYV - 6);
    // G3：河流下切（V 型河谷 + 冲积扇 + 地转偏向力）。仅陆地列（h ≥ 海平面）
    // 参与，避免把海底/浅滩挖穿；下切后的河床高度与 Isolate 预热共用同一
    // 纯函数 → 渲染/碰撞/遮挡一致。
    final (int cut, int _) =
        _riverInfo(x, z, shiftX, shiftZ, base, waterLevelV);
    return (base - cut).clamp(2, maxYV - 6);
  }

  /// G3：河流走廊噪声（纯函数，确定性）。低频 Perlin + 地转偏向力侧偏。
  /// 数值越低越靠河道中线。供 [_riverInfo]（下切）与 [_buildColumn]（注水）
  /// 共用同一判定，保证河床与水面一致。
  static double _riverNoise(
    int x,
    int z,
    double shiftX,
    double shiftZ,
  ) {
    // R26fx3：走廊频率降低 → 河道更宽更连贯（不再断断续续）。
    final double fx = x * 0.006 + 300.0 + shiftX * 0.01;
    final double fz = z * 0.006 + 700.0 + shiftZ * 0.01;
    double r = _perlin(fx, fz);
    // 地转偏向力简化：z>0 为北半球 → 河道向 +X（右）偏，z<0 南半球向 -X（左）偏。
    // 叠加一个低频横向梯度，让同一河道的南北两侧深度不对称 → 凹凸岸。
    final double coriolis = z >= 0 ? 1.0 : -1.0;
    final double bank = _perlin(fx + 50.0, fz) * 0.25 * coriolis;
    return r + bank;
  }

  /// G3：河流信息（纯函数，确定性，Isolate 一致）。
  ///
  /// 返回 `(下切量 cut, 水表 waterTable)`。低频「河流走廊」噪声 + 随机抖动
  /// 定义河道中线，向两侧 V 型下切到水面下；下游（接近海平面）深度衰减 →
  /// 冲积扇；地转偏向力按半球侧偏（z 轴正 = 北：北半球右偏、南半球左偏 →
  /// 凹凸岸）。水表随上游缓升（高原河流水位略高），保证河道连续有水。
  static (int, int) _riverInfo(
    int x,
    int z,
    double shiftX,
    double shiftZ,
    int base,
    int waterLevelV,
  ) {
    if (base < waterLevelV) return (0, waterLevelV); // 海洋/低洼：不挖
    final double r = _riverNoise(x, z, shiftX, shiftZ);
    // R26fx3：河道判定阈值放宽 -0.22 → 更多列入河、水流更连贯。
    const double river = -0.22;
    if (r >= river) return (0, waterLevelV);
    // 水表：下游=海平面 32，上游随高度缓升（≤43 陆地水带上限）。
    final int waterTable =
        (waterLevelV + ((base - 40) * 0.5).round().clamp(0, 11))
            .clamp(waterLevelV, 43);
    // 下切：挖到水面下 3 格（V 型，两侧 base 高、中间深），保证连续有水。
    final int cut = base - (waterTable - 3);
    // 冲积扇：下游（高度接近海平面）深度衰减 → 河谷变浅、扇状展开。
    final double downstream =
        ((base - waterLevelV) / 14.0).clamp(0.0, 1.0); // 1=远上游 0=入海口
    final int fanned = (cut * (0.25 + 0.75 * downstream)).round();
    if (fanned < 1) return (0, waterLevelV);
    return (fanned, waterTable);
  }

  /// R26e 伪 3D 噪声（确定性、零额外依赖）：三张 2D Perlin 在不同平面组合，
  /// 用于洞穴 / 矿脉的**体块**判定。量级约 ±1（洞穴阈值与矿脉阈值以此标定）。
  static double _noise3(double x, double y, double z, double scale) {
    final double a = _perlin(x * scale + 5000, y * scale + 3000);
    final double b = _perlin(y * scale + 3000, z * scale + 7000);
    final double c = _perlin(z * scale + 7000, x * scale + 9000);
    return a * 0.5 + b * 0.3 + c * 0.2;
  }

  /// R26e 浮空岛判定（确定性）：低频噪声 > 阈值且远离出生点 → 该列在
  /// [60, ~100] 高度区间有一块 3 格厚浮岛（顶部草、内核石）。O(列数)。
  /// 阈值按实测值域标定（perlin@0.05 实际 ±0.35，0.18 触发上部成片区域）。
  (bool, int) _islandInfo(int x, int z) {
    final double n = _perlin(
      x * 0.05 + 2000 + _shiftX * 0.01,
      z * 0.05 + 2000 + _shiftZ * 0.01,
    );
    if (n < 0.18) return (false, 0);
    if (x.abs() < 4 && z.abs() < 4) return (false, 0); // 避开出生区
    final int base = 60 + ((n - 0.18) * 160).round().clamp(0, 40);
    return (true, base);
  }

  /// 各结构 footprint 半径（方块数 = (2r+1)²），结构种类见顶层 [StructureKind]。
  static const Map<StructureKind, int> _structFootprint =
      <StructureKind, int>{
    StructureKind.sandcastle: 1, // 3×3
    StructureKind.villageHut: 2, // 5×5
    StructureKind.desertTemple: 3, // 7×7
  };

  /// 结构模板：相对偏移 (dx, dy, dz)（dy=0 为地表上方第一格）→ 方块。
  static Voxel? _templateBlock(
      StructureKind kind, int dx, int dy, int dz, int radius) {
    switch (kind) {
      case StructureKind.sandcastle:
        if (dy == 0) return Voxel.cobble;
        if (dy == 1 && dx.abs() == 1 && dz.abs() == 1) return Voxel.brick;
        return null;
      case StructureKind.villageHut:
        if (dy > 3) return null;
        final bool edge = dx.abs() == radius || dz.abs() == radius;
        if (dy < 3) {
          if (!edge) return null;
          if (dz == radius && dx == 0 && dy < 2) return null; // 门洞
          return Voxel.planks;
        }
        return Voxel.planks; // 顶板
      case StructureKind.desertTemple:
        if (dy > radius) return null;
        final int r = radius - dy; // 逐层收缩
        if (dx.abs() <= r && dz.abs() <= r) {
          final bool shell = dx.abs() == r || dz.abs() == r;
          return shell ? Voxel.sand : null; // 砂岩外壳 + 中空内腔
        }
        return null;
    }
  }

  /// 该列坐标是否中签为某结构原点 + 群系匹配（确定性散列）。
  StructureKind? _structureKindAt(int cx, int cz) {
    if (_hash(cx * 7 + 3, cz * 7 + 11) >= 0.04) return null; // ~1/25
    final Biome b = _biomeAt(cx, cz);
    if (b == Biome.desert) {
      final double k = _hash(cx * 13 + 5, cz * 13 + 9);
      return k < 0.3 ? StructureKind.desertTemple : StructureKind.sandcastle;
    }
    if (b == Biome.plains || b == Biome.forest) return StructureKind.villageHut;
    return null;
  }

  /// R26e+大跃进：结构（沙堡 / 村庄小屋 / 沙漠神庙）。确定性散列后处理，
  /// 扫描邻域找中签原点，再按相对偏移取模板方块覆盖到列上。
  Voxel? _structureBlock(int x, int z, int y, int h) {
    if (h <= waterLevel) return null;
    const int R = 3; // 最大 footprint 半径
    for (int dx = -R; dx <= R; dx++) {
      for (int dz = -R; dz <= R; dz++) {
        final int cx = x + dx;
        final int cz = z + dz;
        final StructureKind? kind = _structureKindAt(cx, cz);
        if (kind == null) continue;
        final int ch = _heightCached(cx, cz);
        if (ch <= waterLevel) continue;
        final int radius = _structFootprint[kind]!;
        if (dx.abs() > radius || dz.abs() > radius) continue;
        final int ry = y - ch - 1;
        if (ry < 0) continue;
        final Voxel? b = _templateBlock(kind, dx, ry, dz, radius);
        if (b != null) return b;
      }
    }
    return null;
  }

  /// 树的确定性抽签：与列坐标强相关（同 (x,z) 恒同）。
  static double _treeChance(int x, int z) {
    final double h = _hash(x * 31 + 7, z * 31 + 13);
    return h;
  }

  // ── Perlin 梯度噪声（确定性）────────────────────────

  /// 种子 → 噪声平移量（确定性整数散列）。
  ///
  /// `seed == defaultSeed` 时返回 0，保证默认世界与历史版本完全一致；
  /// 其余 seed 映射到 [0, 4096) 的确定性偏移，得到互不相同的地形。
  static double _noiseShift(int seed, int salt) {
    final int d = seed - defaultSeed;
    if (d == 0) return 0;
    int n = d * 2654435761 + salt * 40503;
    n = (n ^ (n >> 15)) * 668265263;
    n = n ^ (n >> 13);
    return ((n & 0x7fffffff) % 262144) / 64.0;
  }

  static double _hash(int x, int z) {
    int n = x * 374761393 + z * 668265263;
    n = (n ^ (n >> 13)) * 1274126177;
    n = n ^ (n >> 16);
    return ((n & 0x7fffffff) % 100000) / 100000.0;
  }

  /// R26j：由噪声平移量（种子派生）确定性取 [0,1) 风格参数。
  /// 纯函数（只依赖 shiftX/shiftZ），保证 Isolate 预热与实例采样一致。
  static double _styleF(double shiftX, double shiftZ, int salt) {
    final int a = (shiftX * 1000).round() * 31 + salt;
    final int b = (shiftZ * 1000).round() * 31 + salt * 7;
    return _hash(a, b);
  }

  static double _smooth(double t) => t * t * (3 - 2 * t);

  /// 确定性伪随机梯度（两个分量 -1~1）。
  static (double, double) _grad(int ix, int iz) {
    final double gx = _hash(ix, iz) * 2 - 1;
    final double gz = _hash(ix ^ 0x9E3779B9, iz ^ 0x85EBCA6B) * 2 - 1;
    return (gx, gz);
  }

  /// 2D Perlin 梯度噪声，输出约 ±1。
  static double _perlin(double x, double z) {
    final int xi = x.floor();
    final int zi = z.floor();
    final double xf = x - xi;
    final double zf = z - zi;
    final double u = _smooth(xf);
    final double v = _smooth(zf);
    final (double, double) g00 = _grad(xi, zi);
    final (double, double) g10 = _grad(xi + 1, zi);
    final (double, double) g01 = _grad(xi, zi + 1);
    final (double, double) g11 = _grad(xi + 1, zi + 1);
    final double n00 = g00.$1 * xf + g00.$2 * zf;
    final double n10 = g10.$1 * (xf - 1) + g10.$2 * zf;
    final double n01 = g01.$1 * xf + g01.$2 * (zf - 1);
    final double n11 = g11.$1 * (xf - 1) + g11.$2 * (zf - 1);
    return (n00 * (1 - u) + n10 * u) * (1 - v) +
        (n01 * (1 - u) + n11 * u) * v;
  }

  /// Perlin 分形（4 octaves，R26r8：persistence 0.5→0.4——压低高频局部粗糙，
  /// 地形更平滑；仍保留山体/丘陵的整体起伏）。
  static double _fbm(double x, double z) {
    double amp = 1.0;
    double freq = 1.0;
    double sum = 0.0;
    double norm = 0.0;
    for (int o = 0; o < 4; o++) {
      sum += amp * _perlin(x * freq, z * freq);
      norm += amp;
      amp *= 0.4;
      freq *= 2.0;
    }
    return sum / norm;
  }

  // ── R24d 自动存档序列化 ──────────────────────────────
  /// 序列化为可持久化的 JSON。地形由 [seed] 确定性复现，仅保存玩家编辑层
  /// （破坏 / 放置的方块）与发光方块——"存档存进所有东西"的方块侧全部在此。
  /// 序列化编辑层（chunk 分桶，每项 [cx, cz, lx, ly, lz, voxelIndex]）。
  /// cl38（开放世界 chunk 化）：字段明确、可逆，不再依赖打包 key。
  List<List<int>> _serializeEdits() {
    final List<List<int>> edits = <List<int>>[];
    for (final MapEntry<(int, int), Map<int, Voxel>> ce in _edits.entries) {
      final int cx = ce.key.$1;
      final int cz = ce.key.$2;
      for (final MapEntry<int, Voxel> e in ce.value.entries) {
        final (int lx, int ly, int lz) = _unpackLocal(e.key);
        edits.add(<int>[cx, cz, lx, ly, lz, Voxel.values.indexOf(e.value)]);
      }
    }
    return edits;
  }

  /// 序列化发光方块（每项 [x, y, z, voxelIndex]）。
  List<List<int>> _serializeLights() => <List<int>>[
        for (final MapEntry<(int, int, int), Voxel> e in _lights.entries)
          <int>[
            e.key.$1,
            e.key.$2,
            e.key.$3,
            Voxel.values.indexOf(e.value),
          ],
      ];

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schema': 2, // cl38 起：chunk 化 edits 格式
      'seed': seed,
      'maxY': maxY,
      'sizeX': sizeX,
      'sizeZ': sizeZ,
      'waterLevel': waterLevel,
      'edits': _serializeEditsFull(),
      'lights': _serializeLights(),
      'options': options.toJson(),
    };
  }

  /// G9 cl66：仅编辑层 + 发光方块的快照（地形由 seed 确定性复现，不同步）。
  /// 供联机主机在成员加入 / 重连时下发，使其加入即看到他人已建结构。
  /// 返回 `{edits: [...], lights: [...]}`，与 [loadJson] 接收格式一致。
  Map<String, dynamic> editLayerJson() => <String, dynamic>{
        'edits': _serializeEdits(),
        'lights': _serializeLights(),
      };

  /// G9 cl67：位置范围裁剪的编辑层快照——只返回距 (cx,cz) 的 chunk Chebyshev
  /// 距离 <= [radius] 的编辑与发光方块，供联机「按玩家位置范围同步」：主机按
  /// 请求者的机位裁剪，仅下发其周围 N 格区块，避免大世界全量淹没网络/内存。
  /// [radius] < 0 退化为全量（与 [editLayerJson] 等价，存档/迁移沿用）。
  /// 形状与 [editLayerJson] / [mergeEditLayer] 接收端一致。
  Map<String, dynamic> editLayerJsonNear(int cx, int cz, int radius) {
    final List<List<int>> edits = <List<int>>[];
    for (final MapEntry<(int, int), Map<int, Voxel>> ce in _edits.entries) {
      if (radius >= 0) {
        final int d =
            math.max((ce.key.$1 - cx).abs(), (ce.key.$2 - cz).abs());
        if (d > radius) continue;
      }
      for (final MapEntry<int, Voxel> e in ce.value.entries) {
        final (int lx, int ly, int lz) = _unpackLocal(e.key);
        edits.add(<int>[
          ce.key.$1,
          ce.key.$2,
          lx,
          ly,
          lz,
          Voxel.values.indexOf(e.value),
        ]);
      }
    }
    final List<List<int>> lights = <List<int>>[];
    for (final MapEntry<(int, int, int), Voxel> e in _lights.entries) {
      final int lcx = e.key.$1 ~/ kChunkSize;
      final int lcz = e.key.$3 ~/ kChunkSize;
      if (radius >= 0) {
        final int d = math.max((lcx - cx).abs(), (lcz - cz).abs());
        if (d > radius) continue;
      }
      lights.add(<int>[
        e.key.$1,
        e.key.$2,
        e.key.$3,
        Voxel.values.indexOf(e.value),
      ]);
    }
    return <String, dynamic>{
      'edits': edits,
      'lights': lights,
    };
  }

  /// G9 cl67：合并式应用编辑层快照（**不清空**现有 [_edits]）。
  /// 与 [loadJson] 解码头逻辑完全一致，但去掉 `_edits.clear()` / `_lights.clear()`，
  /// 保留客户端自身此前已合并的远处编辑（范围同步下，客户端可能先后合并过多个
  /// 不同范围的快照）。对同一区块重复应用幂等（后写覆盖先写，主机权威值胜出）。
  /// 默认按 [schema]=2 的 chunk 化格式解码（[loadJson] 也兼容旧格式，但快照只
  /// 产出自 cl38 起的新格式，故此处只读 schema>=2 分支）。
  void mergeEditLayer(Map<String, dynamic> json) {
    final int schema = (json['schema'] as int?) ?? 2;
    for (final dynamic e in (json['edits'] as List<dynamic>? ?? <dynamic>[])) {
      final List<dynamic> a = e as List<dynamic>;
      if (schema >= 2 && a.length >= 6) {
        final int cx = a[0] as int;
        final int cz = a[1] as int;
        final int lx = a[2] as int;
        final int ly = a[3] as int;
        final int lz = a[4] as int;
        final int vi = a[5] as int;
        if (vi >= 0 && vi < Voxel.values.length) {
          final int x = cx * kChunkSize + lx;
          final int z = cz * kChunkSize + lz;
          (_edits.putIfAbsent((cx, cz), () => <int, Voxel>{}))
              [_localKey(x, ly, z)] = Voxel.values[vi];
        }
      }
    }
    for (final dynamic e in (json['lights'] as List<dynamic>? ?? <dynamic>[])) {
      final List<dynamic> a = e as List<dynamic>;
      if (a.length >= 4) {
        final int x = a[0] as int;
        final int y = a[1] as int;
        final int z = a[2] as int;
        final int vi = a[3] as int;
        if (vi >= 0 && vi < Voxel.values.length) {
          _lights[(x, y, z)] = Voxel.values[vi];
        }
      }
    }
  }

  /// 从存档恢复玩家编辑层与发光方块。
  ///
  /// 调用方应先校验 [seed] 一致（地形不同则编辑坐标无意义），不一致时跳过。
  void loadJson(Map<String, dynamic> json) {
    _edits.clear();
    _chunkStore?.clearAllSync(); // 同步清旧世界磁盘缓存，避免陈旧 chunk 复活（杜绝竞态）
    final int schema = (json['schema'] as int?) ?? 1;
    for (final dynamic e in (json['edits'] as List<dynamic>? ?? <dynamic>[])) {
      final List<dynamic> a = e as List<dynamic>;
      if (schema >= 2 && a.length >= 6) {
        // 新格式 [cx, cz, lx, ly, lz, vi]
        final int cx = a[0] as int;
        final int cz = a[1] as int;
        final int lx = a[2] as int;
        final int ly = a[3] as int;
        final int lz = a[4] as int;
        final int vi = a[5] as int;
        if (vi >= 0 && vi < Voxel.values.length) {
          final int x = cx * kChunkSize + lx;
          final int z = cz * kChunkSize + lz;
          (_edits.putIfAbsent((cx, cz), () => <int, Voxel>{}))
              [_localKey(x, ly, z)] = Voxel.values[vi];
        }
      }
      // 旧格式 [key, vi]（cl37 及以前）：打包 key 不可靠反解 → 安全跳过，
      // 世界靠 seed 重建；玩家历史编辑在 cl38 后由新格式写入。
    }
    _lights.clear();
    for (final dynamic e
        in (json['lights'] as List<dynamic>? ?? <dynamic>[])) {
      final List<dynamic> a = e as List<dynamic>;
      final int x = a[0] as int;
      final int y = a[1] as int;
      final int z = a[2] as int;
      final int vi = a[3] as int;
      if (vi >= 0 && vi < Voxel.values.length) {
        _lights[(x, y, z)] = Voxel.values[vi];
      }
    }
  }

  /// 开放世界 P2：启用编辑层分块流式。
  ///
  /// [baseDir] 为应用支持目录（_appDataDir / voxelChunkBaseDir）；内部建
  /// `voxel_chunks/` 子目录存放每 chunk 一个文件。重复调用安全（已初始化则跳过）。
  Future<void> initChunkStore(Directory baseDir, int seed) async {
    if (_chunkStore != null) return;
    final Directory d = Directory('${baseDir.path}/voxel_chunks');
    await d.create(recursive: true);
    _chunkStore = ChunkEditStore(d, seed);
  }

  /// 开放世界 P2：按玩家当前 chunk 流式加载/卸载编辑层。
  ///
  /// - 半径内 [streamRadius] 的 chunk：若 RAM 缺失则从磁盘读入（与
  ///   [mergeEditLayer] 单 chunk 解码同款）；地形由 seed 确定性复现，无编辑的
  ///   chunk 自然留空（不建空文件）。
  /// - 半径 + [streamMargin] 外的 chunk：写回磁盘后从 RAM 删除，释放内存。
  ///
  /// 单玩家场景专用。联机时远端 chunk 可能不在本机玩家半径内，宿主端若需对外
  /// 广播编辑层仍读 RAM（已知边界，详见 P2 设计说明）。
  Future<void> streamAround(int pcx, int pcz) async {
    final ChunkEditStore? store = _chunkStore;
    if (store == null) return;
    // 1) 加载附近缺失 chunk
    for (int cx = pcx - streamRadius; cx <= pcx + streamRadius; cx++) {
      for (int cz = pcz - streamRadius; cz <= pcz + streamRadius; cz++) {
        if (_edits.containsKey((cx, cz))) continue;
        final Map<int, Voxel>? c = store.readChunkSync(cx, cz);
        if (c == null || c.isEmpty) continue;
        _edits[(cx, cz)] = c;
      }
    }
    // 2) 卸载远处 chunk（先收集待删 key，遍历中不改 Map）
    final int limit = streamRadius + streamMargin;
    final List<(int, int)> toUnload = <(int, int)>[];
    for (final (int cx, int cz) in _edits.keys) {
      if ((cx - pcx).abs() > limit || (cz - pcz).abs() > limit) {
        toUnload.add((cx, cz));
      }
    }
    for (final (int cx, int cz) in toUnload) {
      final Map<int, Voxel>? chunk = _edits[(cx, cz)];
      if (chunk != null) await store.writeChunk(cx, cz, chunk);
      _edits.remove((cx, cz));
    }
  }

  /// 全量存档用：RAM 编辑层 + 磁盘上已卸载的 chunk，保证整世界不丢。
  /// 联网快照 [editLayerJson]/[editLayerJsonNear] 仍用 [_serializeEdits]（仅 RAM），
  /// 避免把整世界发给加入的客户端。
  List<List<int>> _serializeEditsFull() {
    final List<List<int>> edits = _serializeEdits();
    final ChunkEditStore? store = _chunkStore;
    if (store == null) return edits;
    for (final (int cx, int cz) in store.listChunksSync()) {
      if (_edits.containsKey((cx, cz))) continue; // RAM 为最新，跳过磁盘
      final Map<int, Voxel>? c = store.readChunkSync(cx, cz);
      if (c == null) continue;
      for (final MapEntry<int, Voxel> e in c.entries) {
        final (int lx, int ly, int lz) = _unpackLocal(e.key);
        edits.add(<int>[cx, cz, lx, ly, lz, Voxel.values.indexOf(e.value)]);
      }
    }
    return edits;
  }

  // ── R26f：Isolate 地形预热 ──────────────────────────────
  //
  // 跑图/转身时新 chunk 的高度 + 树判定在主线程算 fbm（缓存 miss），是
  // 卡顿来源之一。这里提供**纯函数版**批量预计算（compute() 可在后台
  // Isolate 调用，参数/返回值均可传输），主线程算完后用
  // [injectTerrainPrecache] 回填缓存，渲染热路径从此命中缓存。
  // 与实例采样的同一套算法（static 纯函数），一致性由测试锁死。

  /// 批量预计算 (cx,cz) 为中心 radius 方块半径的列数据。
  /// 返回扁平 [Int32List]，每列 4 个 int = [x, z, height, treeTopY]
  /// （treeTopY == height 表示无树；[withTrees] 为 false 时恒等于 height）。
  /// 顶层可调（compute 要求），不访问任何实例状态。
  static Int32List precomputeTerrain(
    int seed,
    int cx,
    int cz,
    int radius,
    bool withTrees,
  ) {
    final double shiftX = _noiseShift(seed, 1);
    final double shiftZ = _noiseShift(seed, 2);
    // G6：Isolate 静态默认与构造默认一致（海平面 32、最高 128）。
    const int waterLevelV = 32; // 默认水位（与构造默认一致）
    const int maxYV = 128; // 默认高度（与构造默认一致）
    final int span = radius * 2;
    final Int32List out = Int32List(span * span * 4);
    int i = 0;
    for (int z = cz - radius; z < cz + radius; z++) {
      for (int x = cx - radius; x < cx + radius; x++) {
        final int h = _heightAtS(x, z, shiftX, shiftZ, waterLevelV, maxYV);
        int top = h;
        if (withTrees &&
            _hasTreeAtS(x, z, shiftX, shiftZ, h, waterLevelV)) {
          top = h + _treeTrunkS(x, z, shiftX, shiftZ);
        }
        out[i++] = x;
        out[i++] = z;
        out[i++] = h;
        out[i++] = top;
      }
    }
    return out;
  }

  /// compute() 单参数包装：[seed, cx, cz, radius, withTrees(0/1)]。
  /// 供 `compute(VoxelWorld.precomputeTerrainArgs, args)` 后台调用。
  static Int32List precomputeTerrainArgs(List<int> a) =>
      precomputeTerrain(a[0], a[1], a[2], a[3], a[4] != 0);

  /// 回填 Isolate 预计算的高度/树缓存（[precomputeTerrain] 的输出）。
  /// seedFor 与实例 seed 不一致（换世界）则丢弃。
  void injectTerrainPrecache(Int32List data, int seedFor) {
    if (seedFor != seed) return;
    final int n = data.length ~/ 4;
    for (int i = 0; i < n; i++) {
      final int x = data[i * 4];
      final int z = data[i * 4 + 1];
      final int h = data[i * 4 + 2];
      final int top = data[i * 4 + 3];
      _heightCache[x * 65521 + z] = h;
      _treeCache[x * 65521 + z] = (top > h, top);
    }
  }
}

/// 开放世界 P2：编辑层分块持久化存储。
///
/// 每个 chunk 一个文件：`{dir}/{seed}.{cx}.{cz}.json`，内容为
/// `[[cx,cz,lx,ly,lz,vi], ...]`（与 [VoxelWorld._serializeEdits] 同格式，
/// 复用其解码逻辑）。文件名含 seed 以隔离不同世界。
/// 仅负责磁盘读写，不持有编辑语义；[VoxelWorld] 负责 RAM↔磁盘的加载/卸载调度。
class ChunkEditStore {
  ChunkEditStore(this.dir, this.seed);

  final Directory dir;
  final int seed;

  File _file(int cx, int cz) => File('${dir.path}/$seed.$cx.$cz.json');

  /// 写入一个 chunk 的编辑（localEdits = chunk 内 _localKey → Voxel）。
  /// 空 chunk 不写文件（改为删除已有文件）。失败静默（RAM 仍保留编辑）。
  Future<void> writeChunk(int cx, int cz, Map<int, Voxel> localEdits) async {
    try {
      final File f = _file(cx, cz);
      if (localEdits.isEmpty) {
        if (await f.exists()) await f.delete();
        return;
      }
      final List<List<int>> arr = <List<int>>[
        for (final MapEntry<int, Voxel> e in localEdits.entries)
          () {
            final (int lx, int ly, int lz) = VoxelWorld._unpackLocal(e.key);
            return <int>[cx, cz, lx, ly, lz, Voxel.values.indexOf(e.value)];
          }(),
      ];
      await f.writeAsString(jsonEncode(arr));
    } catch (_) {
      // 磁盘不可写：放弃本次落盘
    }
  }

  /// 同步读（全量存档用）。无文件返回 null。
  Map<int, Voxel>? readChunkSync(int cx, int cz) {
    try {
      final File f = _file(cx, cz);
      if (!f.existsSync()) return null;
      final List<dynamic> arr =
          jsonDecode(f.readAsStringSync()) as List<dynamic>;
      final Map<int, Voxel> m = <int, Voxel>{};
      for (final dynamic e in arr) {
        final List<dynamic> a = e as List<dynamic>;
        if (a.length >= 6) {
          final int vi = a[5] as int;
          if (vi >= 0 && vi < Voxel.values.length) {
            m[VoxelWorld._localKey(a[2] as int, a[3] as int, a[4] as int)] =
                Voxel.values[vi];
          }
        }
      }
      return m;
    } catch (_) {
      return null;
    }
  }

  /// 同步列出磁盘上所有 chunk 坐标（全量存档用）。
  List<(int, int)> listChunksSync() {
    try {
      final List<(int, int)> out = <(int, int)>[];
      if (!dir.existsSync()) return out;
      final String pfx = '$seed.';
      for (final FileSystemEntity e in dir.listSync()) {
        if (e is! File) continue;
        final String n = e.path.split(Platform.pathSeparator).last;
        if (!n.startsWith(pfx) || !n.endsWith('.json')) continue;
        final String body = n.substring(pfx.length, n.length - 5);
        final List<String> parts = body.split('.');
        if (parts.length == 2) {
          out.add((int.parse(parts[0]), int.parse(parts[1])));
        }
      }
      return out;
    } catch (_) {
      return const <(int, int)>[];
    }
  }

  /// 清空本 seed 的所有 chunk 文件（loadJson 全量载入新世界前调用，避免陈旧缓存复活）。
  Future<void> clearAll() async {
    try {
      if (!dir.existsSync()) return;
      final String pfx = '$seed.';
      await for (final FileSystemEntity e in dir.list()) {
        final String n = e.path.split(Platform.pathSeparator).last;
        if (e is File && n.startsWith(pfx) && n.endsWith('.json')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 同步清空（loadJson 调用，避免异步 [clearAll] 与首次流式加载的竞态）。
  void clearAllSync() {
    try {
      if (!dir.existsSync()) return;
      final String pfx = '$seed.';
      for (final FileSystemEntity e in dir.listSync()) {
        final String n = e.path.split(Platform.pathSeparator).last;
        if (e is File && n.startsWith(pfx) && n.endsWith('.json')) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
