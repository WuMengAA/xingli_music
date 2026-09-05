import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/widgets/voxel/voxel_canvas_controller.dart';

void main() {
  group('VoxelCanvasController.bandIndexFor (Phase 2 refined)', () {
    late VoxelCanvasController controller;

    setUp(() {
      // 8×8 画布，中心 (4,4)；预设表 6 型：rain(0)…cricket(5)。
      controller = VoxelCanvasController(cols: 8, rows: 8);
    });

    int band(String key, [int bandCount = 8]) =>
        controller.bandIndexFor(key, bandCount);

    test('bandCount<=1 恒返回 0', () {
      controller.blocks['4,4'] = 'rain';
      expect(band('4,4', 1), 0);
    });

    test('非法 key 返回 0（不抛）', () {
      expect(controller.bandIndexFor('bad', 8), 0);
    });

    test('中心：低频音色(rain)落最低 band，高频音色(cricket)偏高',
        () {
      controller.blocks['4,4'] = 'rain';
      controller.blocks['0,0'] = 'cricket'; // 占位，避免空
      controller.blocks['4,4'] = 'rain';
      final int rainCenter = band('4,4');
      controller.blocks['4,4'] = 'cricket';
      final int cricketCenter = band('4,4');
      expect(rainCenter, 0);
      expect(cricketCenter, greaterThan(rainCenter));
    });

    test('角落：径向涟漪把频段推到最高（无论音色）', () {
      controller.blocks['0,0'] = 'cricket';
      expect(band('0,0'), 7); // 16? 用默认 8 → bandCount-1=7
      controller.blocks['0,0'] = 'rain';
      final int rainCorner = band('0,0');
      expect(rainCorner, greaterThan(0)); // 涟漪生效：角落 rain 不再是最低
      expect(rainCorner, lessThan(7));
    });

    test('位置涟漪 + 音色音高混合：角落 rain 高于中心 rain、低于角落 cricket',
        () {
      controller.blocks['4,4'] = 'rain';
      controller.blocks['0,0'] = 'rain';
      controller.blocks['7,7'] = 'cricket';
      final int centerRain = band('4,4');
      final int cornerRain = band('0,0');
      final int cornerCricket = band('7,7');
      expect(cornerRain, greaterThan(centerRain));
      expect(cornerCricket, greaterThanOrEqualTo(cornerRain));
    });

    test('bandIndex 始终夹紧在 [0, bandCount-1]（多 bandCount）', () {
      controller.blocks['0,0'] = 'cricket';
      controller.blocks['4,4'] = 'rain';
      for (final int bc in <int>[4, 8, 16, 32]) {
        final int lo = band('4,4', bc);
        final int hi = band('0,0', bc);
        expect(lo, inInclusiveRange(0, bc - 1));
        expect(hi, inInclusiveRange(0, bc - 1));
      }
    });
  });
}
