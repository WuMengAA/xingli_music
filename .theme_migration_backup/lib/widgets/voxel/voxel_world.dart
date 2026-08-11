/// ════════════════════════════════════════════════════════════════════════
/// 体素世界（类我的世界 · 3D 地形）
/// ════════════════════════════════════════════════════════════════════════
///
/// 纯数据模型 + 确定性地形生成（值噪声 fbm 高度图 + 分层 + 树木）。
/// 不依赖 Flutter 渲染，可在任意 Isolate / 测试中使用。
library;

import 'dart:math';

import 'voxel_world_types.dart';

/// 体素世界：固定足迹 [sizeX]×[sizeZ]，最大高度 [maxY]。
class VoxelWorld {
  VoxelWorld({
    this.sizeX = 24,
    this.sizeZ = 24,
    this.maxY = 20,
    int seed = 20260810,
    this.waterLevel = 5,
  }) : _blocks = List<Voxel>.filled(sizeX * sizeZ * maxY, Voxel.air) {
    _generate(seed);
  }

  final int sizeX;
  final int sizeZ;
  final int maxY;
  final int waterLevel;

  final List<Voxel> _blocks;

  int _idx(int x, int y, int z) => x + sizeX * (z + sizeZ * y);

  /// 取方块（越界返回空气）。
  Voxel get(int x, int y, int z) {
    if (x < 0 || z < 0 || y < 0 || x >= sizeX || z >= sizeZ || y >= maxY) {
      return Voxel.air;
    }
    return _blocks[_idx(x, y, z)];
  }

  /// 是否实心（用于面剔除）。
  bool isSolid(int x, int y, int z) {
    final Voxel v = get(x, y, z);
    return kVoxelSpecs[v]!.solid;
  }

  /// 地表高度（最高实心方块 y，无水则取水面上方）。用于相机贴地。
  int surfaceHeight(int x, int z) {
    int top = 0;
    for (int y = 0; y < maxY; y++) {
      if (isSolid(x, y, z)) top = y;
    }
    return top;
  }

  // ── 地形生成 ─────────────────────────────────────────────

  void _generate(int seed) {
    final _Rng rng = _Rng(seed);
    final List<List<int>> height = List<List<int>>.generate(
      sizeX,
      (_) => List<int>.filled(sizeZ, 0),
    );

    const double base = 6.0;
    const double amp = 9.0;

    for (int x = 0; x < sizeX; x++) {
      for (int z = 0; z < sizeZ; z++) {
        final double n = _fbm(x + 1000, z + 1000);
        height[x][z] = (base + n * amp).round().clamp(2, maxY - 6);
      }
    }

    // 填充列
    for (int x = 0; x < sizeX; x++) {
      for (int z = 0; z < sizeZ; z++) {
        final int h = height[x][z];
        final Voxel surface = h > 13
            ? Voxel.snow
            : h <= waterLevel + 1
                ? Voxel.sand
                : Voxel.grass;
        for (int y = 0; y <= h; y++) {
          Voxel v;
          if (y == h) {
            v = surface;
          } else if (y > h - 3) {
            v = (surface == Voxel.sand) ? Voxel.sand : Voxel.dirt;
          } else {
            v = Voxel.stone;
          }
          _set(x, y, z, v);
        }
        // 低洼注水
        if (h < waterLevel) {
          for (int y = h + 1; y <= waterLevel; y++) {
            _set(x, y, z, Voxel.water);
          }
        }
      }
    }

    // 树木（仅草地、留边界）
    for (int x = 2; x < sizeX - 2; x++) {
      for (int z = 2; z < sizeZ - 2; z++) {
        if (height[x][z] <= waterLevel + 1) continue;
        if (get(x, height[x][z], z) != Voxel.grass) continue;
        if (rng.nextDouble() < 0.05) {
          _plantTree(x, height[x][z], z, rng);
        }
      }
    }
  }

  void _set(int x, int y, int z, Voxel v) {
    _blocks[_idx(x, y, z)] = v;
  }

  void _plantTree(int x, int groundY, int z, _Rng rng) {
    final int trunk = 3 + rng.nextInt(2);
    final int topY = groundY + trunk;
    for (int y = groundY + 1; y <= topY; y++) {
      _set(x, y, z, Voxel.wood);
    }
    // 树冠（菱形叶团）
    final int crown = 2;
    for (int dy = -crown; dy <= 1; dy++) {
      final int r = dy <= 0 ? crown + dy : 1;
      for (int dx = -r; dx <= r; dx++) {
        for (int dz = -r; dz <= r; dz++) {
          final int lx = x + dx;
          final int lz = z + dz;
          final int ly = topY + dy;
          if (lx < 0 || lz < 0 || ly < 0 || lx >= sizeX || lz >= sizeZ) {
            continue;
          }
          if (get(lx, ly, lz) == Voxel.air) {
            _set(lx, ly, lz, Voxel.leaves);
          }
        }
      }
    }
  }

  // ── 值噪声（确定性）───────────────────────────────────

  double _hash(int x, int z) {
    int n = x * 374761393 + z * 668265263;
    n = (n ^ (n >> 13)) * 1274126177;
    n = n ^ (n >> 16);
    return ((n & 0x7fffffff) % 100000) / 100000.0;
  }

  double _smooth(double t) => t * t * (3 - 2 * t);

  double _valueNoise(double x, double z) {
    final int xi = x.floor();
    final int zi = z.floor();
    final double xf = x - xi;
    final double zf = z - zi;
    final double v00 = _hash(xi, zi);
    final double v10 = _hash(xi + 1, zi);
    final double v01 = _hash(xi, zi + 1);
    final double v11 = _hash(xi + 1, zi + 1);
    final double u = _smooth(xf);
    final double v = _smooth(zf);
    return (v00 * (1 - u) + v10 * u) * (1 - v) +
        (v01 * (1 - u) + v11 * u) * v;
  }

  double _fbm(double x, double z) {
    double amp = 1.0;
    double freq = 1.0;
    double sum = 0.0;
    double norm = 0.0;
    for (int o = 0; o < 4; o++) {
      sum += amp * _valueNoise(x * freq, z * freq);
      norm += amp;
      amp *= 0.5;
      freq *= 2.0;
    }
    return sum / norm;
  }
}

/// 轻量确定性随机数（LCG）。
class _Rng {
  _Rng(int seed) : _s = seed & 0x7fffffff;
  int _s;
  double nextDouble() {
    _s = (1103515245 * _s + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }

  int nextInt(int n) => (nextDouble() * n).floor();
}
