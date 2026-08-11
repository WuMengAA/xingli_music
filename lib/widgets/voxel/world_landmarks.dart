/// ════════════════════════════════════════════════════════════════════════
/// 体素世界 · 地标锚点（Phase 3 接入 AI 操作）
/// ════════════════════════════════════════════════════════════════════════
///
/// 把"水 / 树 / 山顶"等语义地标翻译成世界坐标，并给出"对准某地标"的相机机位。
/// 纯函数 + 确定性（同 seed ⇒ 同锚点），可在测试里安全断言。
library;

import 'dart:math' as math;

import '../../models/companion_action.dart';
import 'voxel_camera.dart';
import 'voxel_world.dart';
import 'voxel_world_types.dart';

/// 世界中可抵达 / 可对准的地标锚点。
class WorldLandmarks {
  WorldLandmarks(this.world);
  final VoxelWorld world;

  /// 世界中心（地面）。
  Vec3 get center {
    final double cx = world.sizeX / 2;
    final double cz = world.sizeZ / 2;
    return Vec3(cx, VoxelCamera.groundHeightAt(world, cx, cz), cz);
  }

  /// 水面质心；无水方块时回落到**最低盆地**（世界最低的一列地表）。
  ///
  /// 默认种子地形最低高度 6、水面 5，世界可能完全无水方块，
  /// 此时"去水边"语义上指向最低洼地，依然有去处。
  Vec3 get water {
    double sx = 0, sy = 0, sz = 0;
    int n = 0;
    for (int x = 0; x < world.sizeX; x++) {
      for (int z = 0; z < world.sizeZ; z++) {
        for (int y = 0; y < world.maxY; y++) {
          if (world.get(x, y, z) == Voxel.water &&
              world.get(x, y + 1, z) == Voxel.air) {
            sx += x + 0.5;
            sy += y + 0.5;
            sz += z + 0.5;
            n++;
          }
        }
      }
    }
    if (n > 0) return Vec3(sx / n, sy / n, sz / n);
    // 无水方块：取地表最低的一列作"低地"。
    int lx = 0, lz = 0;
    int lowest = world.maxY;
    for (int x = 0; x < world.sizeX; x++) {
      for (int z = 0; z < world.sizeZ; z++) {
        final int h = world.surfaceHeight(x, z);
        if (h < lowest) {
          lowest = h;
          lx = x;
          lz = z;
        }
      }
    }
    return Vec3(
      lx + 0.5,
      VoxelCamera.groundHeightAt(world, lx + 0.5, lz + 0.5),
      lz + 0.5,
    );
  }

  /// 树林质心（取叶团）；无树时回落中心。
  Vec3 get tree {
    double sx = 0, sy = 0, sz = 0;
    int n = 0;
    for (int x = 0; x < world.sizeX; x++) {
      for (int z = 0; z < world.sizeZ; z++) {
        for (int y = 0; y < world.maxY; y++) {
          if (world.get(x, y, z) == Voxel.leaves) {
            sx += x + 0.5;
            sy += y + 0.5;
            sz += z + 0.5;
            n++;
          }
        }
      }
    }
    if (n == 0) return center;
    return Vec3(sx / n, sy / n, sz / n);
  }

  /// 最高点（山顶）：按**遮挡高度**（与站位一致）选峰，保证报告高度自洽。
  Vec3 get mountain {
    int bx = 0, bz = 0;
    double best = -1;
    for (int x = 0; x < world.sizeX; x++) {
      for (int z = 0; z < world.sizeZ; z++) {
        final double h =
            VoxelCamera.groundHeightAt(world, x + 0.5, z + 0.5);
        if (h > best) {
          best = h;
          bx = x;
          bz = z;
        }
      }
    }
    return Vec3(bx + 0.5, best, bz + 0.5);
  }

  /// 篝火（当前世界未生成，回落中心）。
  Vec3 get fire => center;

  /// 按地标取锚点（fire / 缺失地物均回落到有意义的位置）。
  Vec3 anchorFor(CompanionLandmark lm) => switch (lm) {
        CompanionLandmark.center => center,
        CompanionLandmark.water => water,
        CompanionLandmark.tree => tree,
        CompanionLandmark.mountain => mountain,
        CompanionLandmark.fire => fire,
      };

  /// 地标中文名（用于系统旁白）。
  static String nameOf(CompanionLandmark lm) => switch (lm) {
        CompanionLandmark.center => '中心',
        CompanionLandmark.water => '水边',
        CompanionLandmark.tree => '树下',
        CompanionLandmark.mountain => '山顶',
        CompanionLandmark.fire => '篝火旁',
      };
}

/// 相机工具：给出"对准某地标"的机位（站在地标南侧外、朝地标看）。
///
/// 纯函数，确定性；[WorldLandmarks.anchorFor] 返回 null 时回落全景机位。
VoxelCamera cameraForLandmark(VoxelWorld world, CompanionLandmark lm) {
  // anchorFor 对所有地标都返回非空锚点（缺失地物回落中心），无需判空。
  final Vec3 anchor = WorldLandmarks(world).anchorFor(lm);

  // 站在地标 -Z 方向、抬高一些，yaw=0 使 forward 指向 +Z（正对地标）。
  const double dist = 9.0;
  const double lift = 4.0;
  final Vec3 pos = Vec3(anchor.x, anchor.y + lift, anchor.z - dist);
  final double pitch = -math.atan2(lift, dist);
  return VoxelCamera(
    position: pos,
    yaw: 0,
    pitch: pitch,
    fov: 1.0,
  );
}
