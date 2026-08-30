/// 手电筒模式测试：窄锥剔除（含俯视 bug 修复）+ 面数收敛 + 渲染不崩。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_renderer.dart';
import '../lib/widgets/voxel/voxel_world.dart';

void main() {
  VoxelFrame _frame({
    required VoxelCamera camera,
    required RenderConfig config,
  }) =>
      VoxelRenderer.buildFrame(
        world: VoxelWorld(),
        camera: camera,
        viewport: const Size(800, 500),
        cache: null,
        config: config,
      );

  VoxelCamera _cam({double yaw = 0, double pitch = 0, double fov = 1.0}) =>
      VoxelCamera(
        position: const Vec3(64, 48, 64),
        yaw: yaw,
        pitch: pitch,
        fov: fov,
      );

  // 管线改版后 opaque 列表恒空，面在 buckets；总面数直接看 faceCount。
  int _faces(VoxelFrame f) => f.faceCount;

  test('手电筒开：窄锥剔除使面数显著少于关闭（正视角）', () {
    final VoxelCamera cam = _cam(fov: 1.1);
    final int off = _faces(_frame(
      camera: cam,
      config: const RenderConfig(
        lodQuality: LodQuality.off,
        maxChunkBuildsPerFrame: 9999,
      ),
    ));
    final int on = _faces(_frame(
      camera: cam,
      config: const RenderConfig(
        lodQuality: LodQuality.off,
        maxChunkBuildsPerFrame: 9999,
        flashlight: true,
      ),
    ));
    expect(on, lessThan(off), reason: '手电筒窄锥应剔除锥外面，面数更少');
    expect(on, greaterThan(0), reason: '锥内仍有可见面');
  });

  test('俯视正下方 bug 修复：手电筒开启时俯视面数不爆炸', () {
    // 俯视（pitch≈-85°）：原 cullAzimuth 因水平分量→0 关闭剔除 → 全渲染所有方块。
    // 手电筒用完整视线锥（含俯仰），俯视时仍只保留脚下锥内面 → 面数收敛。
    final VoxelCamera cam = _cam(pitch: -85 * 3.14159 / 180, fov: 1.0);
    final int plain = _faces(_frame(
      camera: cam,
      config: const RenderConfig(
        lodQuality: LodQuality.off,
        maxChunkBuildsPerFrame: 9999,
      ),
    ));
    final int flashlight = _faces(_frame(
      camera: cam,
      config: const RenderConfig(
        lodQuality: LodQuality.off,
        maxChunkBuildsPerFrame: 9999,
        flashlight: true,
      ),
    ));
    expect(
      flashlight,
      lessThan(plain),
      reason: '俯视时手电筒视线锥应剔除锥外方块（修复「俯视渲染所有方块」）',
    );
  });

  test('手电筒渲染不抛异常（含泛光所需 frame 结构）', () {
    final VoxelFrame f = _frame(
      camera: _cam(fov: 1.2),
      config: const RenderConfig(
        lodQuality: LodQuality.balanced,
        flashlight: true,
      ),
    );
    expect(f.opaque, isNotNull);
    expect(f.opaquePlainBuckets, isNotNull);
  });
}
