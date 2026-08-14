import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import 'voxel_canvas_controller.dart';

/// 2.5D 实时频谱条（Module "MusicViz-2.5D" · Phase 2：真实频谱条）。
///
/// 把控制器当前帧的 16 频段能量渲染成一组竖条，低频在左、高频在右，
/// 颜色由 `accent`（紫）渐变到青，直观呈现"声音长什么样"。
/// 未播放（`vizBands == null`）时回落静态底线，不闪烁。
///
/// 重绘信号复用控制器自身（`repaint: controller`）：`applyEnvelope`
/// 每帧 `notifyListeners` + `vizVersion` 自增 → 自动随音乐跳动。
class VoxelSpectrumBar extends StatelessWidget {
  const VoxelSpectrumBar({
    super.key,
    required this.controller,
    this.height = 52,
  });

  final VoxelCanvasController controller;

  /// 频谱条区域高度。
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SpectrumPainter(
          controller: controller,
          repaint: controller,
        ),
      ),
    );
  }
}

/// 频谱竖条 painter（与 [_VoxelPainter] 同思路：控制器即重绘信号）。
class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.controller,
    super.repaint,
  });

  final VoxelCanvasController controller;

  static const double _gap = 2.0;
  static const double _radius = 3.0;
  static const double _topPad = 6.0;
  static const double _minBar = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final List<double>? bands = controller.vizBands;
    final int n = bands?.length ?? 16;
    final double usableH = (size.height - _topPad).clamp(0.0, size.height);
    final double bw = (size.width - _gap * (n - 1)) / n;

    for (int i = 0; i < n; i++) {
      final double v = bands == null ? 0.0 : bands[i].clamp(0.0, 1.0);
      final double barH = (usableH * v).clamp(_minBar, usableH);
      final double x = i * (bw + _gap);
      final double y = size.height - barH;
      // 低频(accent 紫) → 高频(青)，频段渐变。
      final Color c = n <= 1
          ? AppColors.accent
          : Color.lerp(AppColors.accent, Colors.cyanAccent, i / (n - 1))!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, bw, barH),
          Radius.circular(_radius),
        ),
        Paint()..color = c,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.controller.vizVersion != controller.vizVersion;
}
