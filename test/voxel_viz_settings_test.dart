import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/models/voxel.dart';
import 'package:xingli_music/widgets/voxel/voxel_canvas_controller.dart';

void main() {
  group('VoxelVizSettings', () {
    test('默认值与 Phase1 原始观感一致', () {
      const VoxelVizSettings s = VoxelVizSettings.defaults;
      expect(s.amplitude, 0.9);
      expect(s.ripplePosWeight, 0.55);
      expect(s.beatPulse, 0.15);
    });

    test('toJson / fromJson 往返一致', () {
      const VoxelVizSettings s = VoxelVizSettings(
        amplitude: 1.2,
        ripplePosWeight: 0.3,
        beatPulse: 0.25,
      );
      final VoxelVizSettings back = VoxelVizSettings.fromJson(s.toJson());
      expect(back.amplitude, s.amplitude);
      expect(back.ripplePosWeight, s.ripplePosWeight);
      expect(back.beatPulse, s.beatPulse);
    });

    test('超范围值夹紧到 [0,2]', () {
      final VoxelVizSettings back = VoxelVizSettings.fromJson(<String, dynamic>{
        'amplitude': 99.0,
        'ripplePosWeight': -5.0,
        'beatPulse': 0.15,
      });
      expect(back.amplitude, 2.0);
      expect(back.ripplePosWeight, 0.0);
    });

    test('copyWith 局部覆盖', () {
      const VoxelVizSettings s = VoxelVizSettings();
      final VoxelVizSettings c = s.copyWith(amplitude: 1.4);
      expect(c.amplitude, 1.4);
      expect(c.ripplePosWeight, s.ripplePosWeight);
      expect(c.beatPulse, s.beatPulse);
    });
  });

  group('VoxelSoundScene.viz 持久化', () {
    test('场景写入并读回 viz 设置', () {
      const VoxelVizSettings viz = VoxelVizSettings(
        amplitude: 1.1,
        ripplePosWeight: 0.2,
        beatPulse: 0.3,
      );
      final VoxelSoundScene scene = VoxelSoundScene(
        id: 's1',
        name: 't',
        cols: 8,
        rows: 8,
        blocks: const <String, String>{},
        viz: viz,
      );
      final VoxelSoundScene back =
          VoxelSoundScene.fromJson(scene.toJson());
      expect(back.viz?.amplitude, 1.1);
      expect(back.viz?.ripplePosWeight, 0.2);
      expect(back.viz?.beatPulse, 0.3);
    });

    test('旧场景无 viz 字段 → 读回 null（向后兼容）', () {
      final VoxelSoundScene back = VoxelSoundScene.fromJson(<String, dynamic>{
        'id': 's',
        'name': 'n',
        'cols': 8,
        'rows': 8,
        'blocks': <String, String>{},
      });
      expect(back.viz, isNull);
    });
  });

  group('VoxelCanvasController viz 编辑态', () {
    late VoxelCanvasController controller;
    setUp(() => controller = VoxelCanvasController(cols: 8, rows: 8));

    test('setVizSettings 更新参数并触发重绘（vizVersion 自增）', () {
      final int before = controller.vizVersion;
      controller.setVizSettings(const VoxelVizSettings(amplitude: 1.3));
      expect(controller.vizSettings.amplitude, 1.3);
      expect(controller.vizVersion, before + 1);
    });

    test('load 应用场景携带的 viz；toScene 写回', () {
      const VoxelVizSettings viz = VoxelVizSettings(ripplePosWeight: 0.8);
      final VoxelSoundScene scene = VoxelSoundScene(
        id: 's',
        name: 'n',
        cols: 8,
        rows: 8,
        blocks: const <String, String>{'4,4': 'rain'},
        viz: viz,
      );
      controller.load(scene);
      expect(controller.vizSettings.ripplePosWeight, 0.8);
      expect(controller.toScene('s', 'n').viz?.ripplePosWeight, 0.8);
    });

    test('ripplePosWeight=1 → 纯位置涟漪（中心 rain 与 cricket 同 band）', () {
      controller.blocks['4,4'] = 'rain';
      controller.blocks['4,4'] = 'cricket';
      controller.setVizSettings(const VoxelVizSettings(ripplePosWeight: 1.0));
      // 中心 radialFrac=0 → combined=0 → 最低 band，与音色无关。
      expect(controller.bandIndexFor('4,4', 8), 0);
    });

    test('ripplePosWeight=0 → 纯音色音高（中心 rain=低、cricket=高）', () {
      controller.blocks['4,4'] = 'rain';
      final int rainCenter = controller.bandIndexFor('4,4', 8);
      controller.blocks['4,4'] = 'cricket';
      controller.setVizSettings(const VoxelVizSettings(ripplePosWeight: 0.0));
      final int cricketCenter = controller.bandIndexFor('4,4', 8);
      expect(rainCenter, 0);
      expect(cricketCenter, greaterThan(rainCenter));
    });
  });
}
