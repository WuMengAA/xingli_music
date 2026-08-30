/// 体素实体（AI 陪伴小人）渲染单测：验证实体盒子面能被正确投影并入帧。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_renderer.dart';
import '../lib/widgets/voxel/voxel_world.dart';

void main() {
  group('VoxelRenderer 实体', () {
    late final VoxelWorld world;
    late final VoxelCamera camera;

    setUpAll(() {
      world = VoxelWorld();
      camera = VoxelCamera.overview(world);
    });

    VoxelFrame _frame([List<VoxelEntity> entities = const <VoxelEntity>[]]) =>
        VoxelRenderer.buildFrame(
          world: world,
          camera: camera,
          viewport: const Size(800, 500),
          // R23k：无限地图后俯瞰会看到大陆外生成的地形，面数变多——
          // 测试放宽预算，避免实体面被裁剪，也避免断言被面数波动干扰。
          config: const RenderConfig(
            renderDistance: 22,
            maxFaces: 60000,
          ),
          entities: entities,
        );

    // 统计帧内总面数（管线改版后 opaque/translucent 恒空，面在 buckets 里）。
    int _facesOf(VoxelFrame f) => f.faceCount;

    test('无实体时帧面数与地形一致', () {
      final VoxelFrame a = _frame();
      final VoxelFrame b = _frame(const <VoxelEntity>[]);
      expect(_facesOf(b), equals(_facesOf(a)));
    });

    test('加入实体会多出方块面，且进入视口（不越界）', () {
      const VoxelEntity e = VoxelEntity(
        position: Vec3(12, 5, 12),
        color: Color(0xFF7CC8FF),
      );
      final VoxelFrame noEnt = _frame();
      final VoxelFrame withEnt = _frame(<VoxelEntity>[e]);
      expect(_facesOf(withEnt), greaterThan(_facesOf(noEnt)));
      // 实体盒子共 6 盒 × 6 面 = 36 面（未被预算裁剪时）。
      expect(_facesOf(withEnt) - _facesOf(noEnt), greaterThanOrEqualTo(36));
      // 实体面顶点投影成功（有限、量级合理；渲染器只做近裁剪，不入视口裁剪，
      // 所以允许越出 0~500 视口边界；无限地形远处面坐标可较大。R23s 移除列级
      // 方位剔除后，更多地形面被合法投影（含相机侧后方的面，由 project 返回
      // null 自然丢弃），边界坐标可略大，故放宽到 ±20000）。
      for (final VoxelMeshBatch? b in withEnt.opaquePlainBuckets) {
        final VoxelMeshBatch? batch = b;
        if (batch == null) continue;
        for (int i = 0; i < batch.positions.length; i++) {
          expect(batch.positions[i].isFinite, isTrue);
          expect(batch.positions[i], inInclusiveRange(-20000.0, 20000.0));
        }
      }
    });

    test('发光实体走半透明 Pass', () {
      const VoxelEntity e = VoxelEntity(
        position: Vec3(12, 5, 12),
        color: Color(0xFF7CC8FF),
        glow: true,
      );
      final VoxelFrame withEnt = _frame(<VoxelEntity>[e]);
      final VoxelFrame noEnt = _frame();
      // R24c 单桶设计：实体面并入统一深度桶（opaque），translucent 列表恒空。
      // 发光实体多出 36 个面（6格×6面），进入同一桶。
      expect(withEnt.translucent.length, equals(noEnt.translucent.length));
      expect(
        _facesOf(withEnt) - _facesOf(noEnt),
        greaterThanOrEqualTo(36),
        reason: '发光实体的 36 个面应并入统一深度桶',
      );
    });
  });
}
