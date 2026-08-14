import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/widgets/voxel/voxel_canvas_controller.dart';
import 'package:xingli_music/widgets/voxel/voxel_spectrum_bar.dart';

void main() {
  group('VoxelSpectrumBar', () {
    testWidgets('未播放（vizBands 为 null）也能渲染静态底线，不抛异常',
        (WidgetTester tester) async {
      final VoxelCanvasController controller = VoxelCanvasController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VoxelSpectrumBar(controller: controller)),
        ),
      );
      expect(find.byType(VoxelSpectrumBar), findsOneWidget);
      // 无播放状态：painter 不应因 vizBands 缺失而抛。
      expect(controller.vizBands, isNull);
    });

    testWidgets('有真实 envelope 时渲染 16 频段竖条，不抛异常',
        (WidgetTester tester) async {
      final VoxelCanvasController controller = VoxelCanvasController();
      final List<double> bands =
          List<double>.generate(16, (int i) => (i % 5) / 5);
      controller.applyEnvelope(bands, 0.4);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VoxelSpectrumBar(controller: controller)),
        ),
      );
      expect(find.byType(VoxelSpectrumBar), findsOneWidget);
      expect(controller.vizBands, bands);
    });

    test('applyEnvelope 自增 vizVersion，驱动频谱重绘', () {
      final VoxelCanvasController controller = VoxelCanvasController();
      final int before = controller.vizVersion;
      controller.applyEnvelope(List<double>.filled(16, 0.5), 0.2);
      expect(controller.vizVersion, before + 1);
      // 整体能量取均值并夹紧到 0~1。
      expect(controller.vizLevel, 0.5);
    });
  });
}
