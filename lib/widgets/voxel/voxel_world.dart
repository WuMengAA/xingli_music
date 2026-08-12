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

import 'dart:math' as math;
import 'dart:typed_data' show Int32List;

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
    // R26e 分层叠加：2D 高度图为基石，逐层叠加洞穴/浮空岛/矿脉（全部 O(列高)）。
    final (bool hasIsland, int islandBase) = _islandInfo(x, z);
    for (int y = 0; y <= h; y++) {
      // 洞穴：低于地表 2 格起、伪 3D 噪声 > 阈值 → 留空（洞内不产矿）。
      // 阈值按实测值域标定（伪 3D 噪声实际 ±0.35，0.15 触发适度空洞）。
      if (y < h - 1 &&
          y > 1 &&
          _noise3(x.toDouble(), y.toDouble(), z.toDouble(), 0.16) > 0.15) {
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
          if (ore.abs() > 0.32) {
            final int t = ((ore * 100).abs().round()) % 3;
            v = t == 0 ? Voxel.gold : (t == 1 ? Voxel.ironOre : Voxel.coalOre);
          }
        }
      }
      col[y] = v;
    }
    // 浮空岛（独立悬浮层，与地面列无关；顶部草 + 内核石）
    if (hasIsland) {
      for (int y = islandBase; y <= islandBase + 2 && y < maxY; y++) {
        col[y] = y == islandBase + 2 ? Voxel.grass : Voxel.stone;
      }
    }
    // 低洼注水
    if (h < waterLevel) {
      for (int y = h + 1; y <= waterLevel; y++) {
        col[y] = Voxel.water;
      }
    }
    // 结构（沙漠沙堡）：确定性散列后处理，覆盖在列生成之上。
    for (int y = h + 1; y <= h + 2 && y < maxY; y++) {
      final Voxel? sv = _structureBlock(x, z, y, h);
      if (sv != null) col[y] = sv;
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
    final Biome biome = _biomeAtS(x, z, shiftX, shiftZ);
    final BiomeSpec spec = kBiomes[biome]!;
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
    double h = spec.baseHeight + spec.amplitude * ampMul * n + cont * 20.0 + elev;
    if (n > 0.15) {
      h += math.pow(n - 0.15, 1.6).toDouble() * 14; // 正向隆起 → 尖峰/悬崖
    } else if (n < -0.15) {
      h -= math.pow(-(n + 0.15), 1.6).toDouble() * 9; // 负向加深 → 峡谷
    }
    return h.round().clamp(8, maxYV - 6);
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

  /// R26e 沙漠结构（沙堡）：确定性 hash + 沙漠群系 → 底座 3×3（cobble）+
  /// 四角柱（brick）。返回本列 (x,z) 在高度 [y] 处的结构方块；无则 null。
  /// O(9 邻域 × hash) 每列一次（列重建时），符合「结构=确定性散列后处理」。
  Voxel? _structureBlock(int x, int z, int y, int h) {
    if (_biomeAt(x, z) != Biome.desert) return null;
    if (h <= waterLevel) return null;
    for (int dx = -1; dx <= 1; dx++) {
      for (int dz = -1; dz <= 1; dz++) {
        final int cx = x + dx;
        final int cz = z + dz;
        if (_hash(cx * 7 + 3, cz * 7 + 11) >= 0.04) continue; // ~1/25 中签
        final int ch = _heightCached(cx, cz);
        if (_biomeAt(cx, cz) != Biome.desert || ch <= waterLevel) continue;
        if (y == ch + 1) {
          if ((x - cx).abs() <= 1 && (z - cz).abs() <= 1) return Voxel.cobble;
        } else if (y == ch + 2) {
          if ((x - cx).abs() == 1 && (z - cz).abs() == 1) return Voxel.brick;
        }
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

  /// Perlin 分形（4 octaves）。
  static double _fbm(double x, double z) {
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
    const int waterLevelV = 43; // 默认水位（与构造默认一致）
    const int maxYV = 256; // 默认高度（与构造默认一致）
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
