/// R26skel 骨骼朝向回归测试：模型正面 (+Z) 在 yawA=-lookYaw 旋转后必须
/// 与相机视线方向一致（之前用 π-lookYaw 反向，致第三身月亮步）。
/// 头部俯仰 -lookPitch 才能让正面跟随视线（之前反向）。
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_renderer.dart';
import '../lib/widgets/voxel/voxel_world.dart';

/// 复刻 _emitBox 内的 _rot 公式（与 voxel_renderer.dart 同步）。
List<double> rot(double x, double y, double z,
    {required double rotYaw, required double rotX}) {
  // 与代码一致：rotYaw=0 时直接不旋转。
  if (rotYaw == 0 && rotX == 0) return <double>[x, y, z];
  final double yawA = -rotYaw; // R26skel 修正
  final double cosY = math.cos(yawA);
  final double sinY = math.sin(yawA);
  final double cosR = math.cos(rotX);
  final double sinR = math.sin(rotX);
  final double x1 = rotYaw == 0 ? x : x * cosY - z * sinY;
  final double z1 = rotYaw == 0 ? z : x * sinY + z * cosY;
  final double y2 = rotX == 0 ? y : y * cosR - z1 * sinR;
  final double z2 = rotX == 0 ? z1 : y * sinR + z1 * cosR;
  return <double>[x1, y2, z2];
}

void main() {
  group('R26skel 模型朝向', () {
    test('lookYaw=相机 yaw 时，模型正面（+Z）旋转后与相机视线方向一致', () {
      // 对每个 lookYaw，模型正面方向 = rot(0, 0, 1) 的 (x, z)。
      // 相机视线方向 = (sin(yaw), 0, cos(yaw))。
      // 期望：模型正面方向 == 相机视线方向（分量容差 < 1e-6）。
      final List<double> yaws = <double>[
        0.0,
        0.5,
        math.pi / 4,
        math.pi / 2,
        3 * math.pi / 4,
        math.pi,
        -math.pi / 2,
      ];
      for (final double yaw in yaws) {
        final List<double> front = rot(0, 0, 1, rotYaw: yaw, rotX: 0);
        final double expectX = math.sin(yaw);
        final double expectZ = math.cos(yaw);
        expect(front[0], closeTo(expectX, 1e-6),
            reason: 'yaw=$yaw 正面 x 不对齐相机');
        expect(front[2], closeTo(expectZ, 1e-6),
            reason: 'yaw=$yaw 正面 z 不对齐相机');
      }
    });

    test('lookPitch<0（俯视）时，头部正面应朝下', () {
      // 头正面（旋转 yaw 后）= (sin(yaw), 0, cos(yaw))；施加 pitch=R 后：
      // rotX 绕 X 轴在 pivotY/pivotZ，y 方向被 pitch 调制。
      // 俯视 pitch<0 → 头正面 y 分量 < 0（朝下）。
      // 用 -lookPitch 作为 rotX（修正后），lookPitch=-0.7 → rotX=+0.7。
      // 头正面初始 (0,0,1) 经 rotX=+0.7 绕 X 轴：y'=-sin(0.7)≈-0.64<0。✓
      for (final double pitch in <double>[-0.8, -0.3, 0.0, 0.3, 0.8]) {
        final double rotX = -pitch; // R26skel 修正
        final List<double> front = rot(0, 0, 1, rotYaw: 0, rotX: rotX);
        if (pitch < -0.01) {
          expect(front[1], lessThan(-0.1),
              reason: '俯视 pitch=$pitch 头正面 y 应<0 (实际 ${front[1]})');
        } else if (pitch > 0.01) {
          expect(front[1], greaterThan(0.1),
              reason: '仰视 pitch=$pitch 头正面 y 应>0 (实际 ${front[1]})');
        } else {
          expect(front[1], closeTo(0, 1e-6));
        }
      }
    });

    test('lookYaw 连续性：yaw=0 与 yaw=ε 不应出现 180° 跳变', () {
      // 修复前 yawA=π-yaw：yaw=0 → yawA=π (因 rotYaw==0 守卫实际不转)；
      // yaw=ε → yawA≈π → 接近 180° 旋转。跳变≈180°。
      // 修复后 yawA=-yaw：yaw=0 → 0°，yaw=ε → ε°。连续。
      final List<double> f0 = rot(0, 0, 1, rotYaw: 0, rotX: 0);
      final List<double> fe = rot(0, 0, 1, rotYaw: 0.001, rotX: 0);
      final double dx = (f0[0] - fe[0]).abs();
      final double dz = (f0[2] - fe[2]).abs();
      expect(dx + dz, lessThan(0.01),
          reason: 'yaw 0→ε 跳变过大 dx=$dx dz=$dz');
    });
  });

  group('R26skel 帧渲染（无回归）', () {
    test('加入 player 实体后帧多出 36 面，且坐标有限', () {
      final VoxelWorld world =
          VoxelWorld(sizeX: 24, sizeZ: 24, maxY: 64, waterLevel: 20);
      final VoxelCamera camera = VoxelCamera(
        position: const Vec3(12, 35, 4),
        yaw: 0.3,
        pitch: -0.4,
        fov: 1.0,
        far: 128,
      );
      const VoxelEntity e = VoxelEntity(
        position: Vec3(12, 30, 12),
        color: Color(0xFFC8A079),
        lookYaw: 0.3,
        lookPitch: -0.2,
        swing: 0.4,
      );
      final VoxelFrame noEnt = VoxelRenderer.buildFrame(
        world: world,
        camera: camera,
        viewport: const Size(400, 300),
        config: const RenderConfig(renderDistance: 8, maxFaces: 30000),
        entities: const <VoxelEntity>[],
      );
      final VoxelFrame withEnt = VoxelRenderer.buildFrame(
        world: world,
        camera: camera,
        viewport: const Size(400, 300),
        config: const RenderConfig(renderDistance: 8, maxFaces: 30000),
        entities: const <VoxelEntity>[e],
      );
      expect(withEnt.faceCount - noEnt.faceCount, greaterThanOrEqualTo(36));
      for (final RenderFace f in withEnt.opaque) {
        for (int i = 0; i < f.xy.length; i++) {
          expect(f.xy[i].isFinite, isTrue);
        }
      }
    });
  });
}