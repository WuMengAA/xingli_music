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

import 'voxel_daynight.dart';
import 'voxel_world_types.dart';

/// 体素世界：出生大陆 [sizeX]×[sizeZ]，最大高度 [maxY]，水平无限延伸。
class VoxelWorld {
  VoxelWorld({
    this.sizeX = 24,
    this.sizeZ = 24,
    this.maxY = 256,
    this.seed = defaultSeed,
    this.waterLevel = 43,
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

  /// 噪声采样偏移（由 [seed] 派生，基准种子时为 0）。
  late final double _shiftX = _noiseShift(seed, 1);
  late final double _shiftZ = _noiseShift(seed, 2);

  /// 出生大陆预生成数组。
  final List<Voxel> _blocks;

  /// 编辑覆盖层：key = x*65536 + z*256 + y（任意坐标，含大陆外）。
  /// get 优先查它 → 破坏/放置在任何位置都即时生效。
  final Map<int, Voxel> _edits = <int, Voxel>{};

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

  static int _editKey(int x, int y, int z) =>
      x * 65536 + z * 256 + y.clamp(0, 255);

  /// 取方块（任意坐标；大陆外即时确定性生成，越界高度返回空气）。
  Voxel get(int x, int y, int z) {
    if (y < 0 || y >= maxY) return Voxel.air;
    // R23o：edits 为空时跳过 Map 查找（渲染热路径，每帧数万次 get）。
    if (_edits.isNotEmpty) {
      final Voxel? edit = _edits[_editKey(x, y, z)];
      if (edit != null) return edit;
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
    _edits[_editKey(x, y, z)] = v;
    _dirtyColumn(x, z);
    _syncLight(x, y, z, v);
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
    for (int y = 0; y <= h; y++) {
      Voxel v;
      if (y == h) {
        v = surface;
      } else if (y > h - 3) {
        v = (surface == Voxel.sand || surface == Voxel.snow)
            ? surface
            : spec.subsurface;
      } else {
        v = Voxel.stone;
      }
      col[y] = v;
    }
    // 低洼注水
    if (h < waterLevel) {
      for (int y = h + 1; y <= waterLevel; y++) {
        col[y] = Voxel.water;
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
  Biome _biomeAt(int x, int z) {
    final double bx = x * 0.012 + 5000 + _shiftX * 0.01;
    final double bz = z * 0.012 + 5000 + _shiftZ * 0.01;
    final double b = _perlin(bx, bz);
    if (b > 0.3) return Biome.mountain;
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
  int _treeTrunk(int tx, int tz) {
    final Biome biome = _biomeAt(tx, tz);
    final BiomeSpec spec = kBiomes[biome]!;
    final int span = (spec.maxTrunk - spec.minTrunk + 1).clamp(1, 99);
    return spec.minTrunk + (_hash(tx * 3 + 1, tz * 3 + 5) * span).floor();
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
  int _heightAt(int x, int z) {
    final Biome biome = _biomeAt(x, z);
    final BiomeSpec spec = kBiomes[biome]!;
    final double n = _fbm(x + 1000 + _shiftX, z + 1000 + _shiftZ);
    // Perlin fbm 输出约 ±1 → 群系基准高度 ±振幅。
    final double h = spec.baseHeight + spec.amplitude * n;
    return h.round().clamp(8, maxY - 6);
  }

  /// 树的确定性抽签：与列坐标强相关（同 (x,z) 恒同）。
  double _treeChance(int x, int z) {
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

  double _hash(int x, int z) {
    int n = x * 374761393 + z * 668265263;
    n = (n ^ (n >> 13)) * 1274126177;
    n = n ^ (n >> 16);
    return ((n & 0x7fffffff) % 100000) / 100000.0;
  }

  double _smooth(double t) => t * t * (3 - 2 * t);

  /// 确定性伪随机梯度（两个分量 -1~1）。
  (double, double) _grad(int ix, int iz) {
    final double gx = _hash(ix, iz) * 2 - 1;
    final double gz = _hash(ix ^ 0x9E3779B9, iz ^ 0x85EBCA6B) * 2 - 1;
    return (gx, gz);
  }

  /// 2D Perlin 梯度噪声，输出约 ±1。
  double _perlin(double x, double z) {
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

  /// Perlin 分形（4 octaves）。
  double _fbm(double x, double z) {
    double amp = 1.0;
    double freq = 1.0;
    double sum = 0.0;
    double norm = 0.0;
    for (int o = 0; o < 4; o++) {
      sum += amp * _perlin(x * freq, z * freq);
      norm += amp;
      amp *= 0.5;
      freq *= 2.0;
    }
    return sum / norm;
  }

  // ── R24d 自动存档序列化 ──────────────────────────────
  /// 序列化为可持久化的 JSON。地形由 [seed] 确定性复现，仅保存玩家编辑层
  /// （破坏 / 放置的方块）与发光方块——"存档存进所有东西"的方块侧全部在此。
  Map<String, dynamic> toJson() {
    // 编辑层 key 是 [x*65536 + z*256 + y] 的打包整数（含负数坐标）；
    // 负数下 Dart 的 ~/ 向零截断，无法可靠反解 x/y/z，故直接存原始 key。
    final List<List<int>> edits = <List<int>>[
      for (final MapEntry<int, Voxel> e in _edits.entries)
        <int>[e.key, Voxel.values.indexOf(e.value)],
    ];
    final List<List<int>> lights = <List<int>>[
      for (final MapEntry<(int, int, int), Voxel> e in _lights.entries)
        <int>[
          e.key.$1,
          e.key.$2,
          e.key.$3,
          Voxel.values.indexOf(e.value),
        ],
    ];
    return <String, dynamic>{
      'seed': seed,
      'maxY': maxY,
      'sizeX': sizeX,
      'sizeZ': sizeZ,
      'waterLevel': waterLevel,
      'edits': edits,
      'lights': lights,
    };
  }

  /// 从存档恢复玩家编辑层与发光方块。
  ///
  /// 调用方应先校验 [seed] 一致（地形不同则编辑坐标无意义），不一致时跳过。
  void loadJson(Map<String, dynamic> json) {
    _edits.clear();
    for (final dynamic e in (json['edits'] as List<dynamic>? ?? <dynamic>[])) {
      final List<dynamic> a = e as List<dynamic>;
      final int key = a[0] as int;
      final int vi = a[1] as int;
      if (vi >= 0 && vi < Voxel.values.length) {
        _edits[key] = Voxel.values[vi];
      }
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
}
