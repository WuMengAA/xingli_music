/// AI 陪伴「理解 → 快速操作」纯函数单测（不碰渲染 / 音频）。
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import '../lib/models/companion_action.dart';
import '../lib/services/companion/companion_template_service.dart';
import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_world.dart';
import '../lib/widgets/voxel/world_landmarks.dart';

bool _has(
  List<CompanionAction> acts,
  CompanionActionKind kind, {
  CompanionLandmark? landmark,
  bool? enabled,
}) =>
    acts.any((CompanionAction a) =>
        a.kind == kind &&
        (landmark == null || a.landmark == landmark) &&
        (enabled == null || a.enabled == enabled));

void main() {
  group('理解 → 动作派生', () {
    final CompanionTemplateService svc = CompanionTemplateService();

    test('去水边 → 走过去 + 看向水边', () {
      final List<CompanionAction> a = svc.deriveActions('去水边看看');
      expect(_has(a, CompanionActionKind.moveFigure,
          landmark: CompanionLandmark.water), isTrue);
      expect(_has(a, CompanionActionKind.focusCamera,
          landmark: CompanionLandmark.water), isTrue);
    });

    test('去树下 → 走过去 + 看向树下', () {
      final List<CompanionAction> a = svc.deriveActions('走到树下');
      expect(_has(a, CompanionActionKind.moveFigure,
          landmark: CompanionLandmark.tree), isTrue);
      expect(_has(a, CompanionActionKind.focusCamera,
          landmark: CompanionLandmark.tree), isTrue);
    });

    test('看山顶 → 镜头对准山顶（并走到山顶）', () {
      final List<CompanionAction> a = svc.deriveActions('看山顶');
      expect(_has(a, CompanionActionKind.focusCamera,
          landmark: CompanionLandmark.mountain), isTrue);
      expect(_has(a, CompanionActionKind.moveFigure,
          landmark: CompanionLandmark.mountain), isTrue);
    });

    test('回中心 → 只走回中心', () {
      final List<CompanionAction> a = svc.deriveActions('回到中心');
      expect(_has(a, CompanionActionKind.moveFigure,
          landmark: CompanionLandmark.center), isTrue);
      expect(_has(a, CompanionActionKind.focusCamera), isFalse);
    });

    test('转一圈 → 镜头环绕', () {
      final List<CompanionAction> a = svc.deriveActions('转一圈');
      expect(_has(a, CompanionActionKind.orbitCamera), isTrue);
    });

    test('关掉世界音效 → 关闭；打开世界音效 → 开启', () {
      expect(_has(svc.deriveActions('关掉世界音效'),
          CompanionActionKind.toggleWorldAudio, enabled: false), isTrue);
      expect(_has(svc.deriveActions('打开世界音效'),
          CompanionActionKind.toggleWorldAudio, enabled: true), isTrue);
    });

    test('纯闲聊（你好）→ 不出动作，只聊天', () {
      expect(svc.deriveActions('你好'), isEmpty);
      expect(svc.deriveActions('今天有点累'), isEmpty);
    });

    test('英文关键词也能识别', () {
      expect(_has(svc.deriveActions('go to the water'),
          CompanionActionKind.moveFigure, landmark: CompanionLandmark.water),
          isTrue);
      expect(_has(svc.deriveActions('orbit'), CompanionActionKind.orbitCamera),
          isTrue);
    });
  });

  group('地标锚点（纯函数 · 确定性）', () {
    final VoxelWorld world = VoxelWorld();
    final WorldLandmarks lm = WorldLandmarks(world);

    test('中心 / 水边 / 山顶 / 树下 均有去处（不为 null）', () {
      expect(lm.center, isNotNull);
      expect(lm.water, isNotNull);
      expect(lm.mountain, isNotNull);
      expect(lm.tree, isNotNull);
      expect(lm.anchorFor(CompanionLandmark.fire), isNotNull);
    });

    test('同 seed 两次取锚点一致（确定性）', () {
      final WorldLandmarks a = WorldLandmarks(VoxelWorld(seed: 123));
      final WorldLandmarks b = WorldLandmarks(VoxelWorld(seed: 123));
      expect(a.water, equals(b.water));
      expect(a.mountain, equals(b.mountain));
    });

    test('山顶不低于中心（海拔语义：山顶是最高列）', () {
      expect(lm.mountain.y, greaterThanOrEqualTo(lm.center.y - 0.001));
    });
  });

  group('相机对准地标', () {
    final VoxelWorld world = VoxelWorld();

    test('对准水边的机位，能把水边投到视口中央附近', () {
      final Vec3 anchor = WorldLandmarks(world).water;
      final VoxelCamera cam =
          cameraForLandmark(world, CompanionLandmark.water);
      final ScreenPoint? sp = cam.project(anchor, const Size(800, 600));
      expect(sp, isNotNull);
      // 正对地标：水平 / 垂直都应贴近中心（800/2, 600/2）。
      expect((sp!.x - 400).abs(), lessThan(60));
      expect((sp.y - 300).abs(), lessThan(120));
    });
  });
}
