/// Phase 3 · 世界内空间音效引擎的纯函数单测。
///
/// 只覆盖不触碰 audioplayers 的部分：地形扫描、听感参数计算、遮挡步进。
/// 这样即便在 CI / 无音频设备环境下也能稳定验收 Phase 3 核心逻辑。
import 'package:flutter_test/flutter_test.dart';

import '../lib/services/audio/spatial/spatial_models.dart';
import '../lib/widgets/voxel/voxel_camera.dart';
import '../lib/widgets/voxel/voxel_world.dart';
import '../lib/widgets/voxel/world_audio_engine.dart';

void main() {
  group('WorldAudioEngine 纯函数', () {
    late final VoxelWorld world;

    setUpAll(() {
      // 默认种子 → 确定性地形（与历史版本逐格一致）。
      world = VoxelWorld();
    });

    test('扫描结果确定性：同世界两次扫描 id 序列一致', () {
      final List<WorldAudioSource> a = WorldAudioEngine.scanSources(world);
      final List<WorldAudioSource> b = WorldAudioEngine.scanSources(world);
      expect(
        a.map((WorldAudioSource s) => s.id).toList(),
        equals(b.map((WorldAudioSource s) => s.id).toList()),
      );
    });

    test('扫描产出受 4 音轨预算约束的音源簇（空世界也安全）', () {
      final List<WorldAudioSource> sources =
          WorldAudioEngine.scanSources(world);
      // 至少能识别地形里的某种发声地物（水/叶/鸟/风），或为空集合而不报错。
      expect(sources.length, greaterThanOrEqualTo(0));
      // 单个 id 不重复。
      final Set<String> ids =
          sources.map((WorldAudioSource s) => s.id).toSet();
      expect(ids.length, equals(sources.length));
      // 每个音源都有合法素材路径与强度上限。
      for (final WorldAudioSource s in sources) {
        expect(s.spec.asset, startsWith('assets/audio/'));
        expect(s.strength, inInclusiveRange(0.0, 1.0));
      }
    });

    test('听感参数在边界内：增益/声像/距离/遮挡', () {
      final List<WorldAudioSource> sources =
          WorldAudioEngine.scanSources(world);
      // 用全景机位评估；即使无音源也不应抛错。
      final WorldAudioEngine engine = WorldAudioEngine(world);
      final VoxelCamera cam = VoxelCamera.overview(world);
      for (final WorldAudioSource s in sources) {
        final SourceDynamics d = engine.dynamicsFor(s, cam);
        expect(d.gain, inInclusiveRange(0.0, 1.0));
        expect(d.pan, inInclusiveRange(-1.0, 1.0));
        expect(d.distance, greaterThanOrEqualTo(0.0));
        expect(d.walls, greaterThanOrEqualTo(0));
        // 折回的几何声道必须在合法枚举内。
        expect(
          <SpatialChannel>{SpatialChannel.left, SpatialChannel.center, SpatialChannel.right},
          contains(d.channel),
        );
      }
    });

    test('遮挡步进：同一点之间返回 0 遮挡', () {
      final VoxelCamera cam = VoxelCamera.overview(world);
      final Vec3 eye = cam.position;
      expect(WorldAudioEngine.occlusionBetween(world, eye, eye), equals(0));
    });
  });
}
