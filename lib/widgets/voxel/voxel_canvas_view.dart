import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import '../../models/voxel.dart';
import 'voxel_canvas_controller.dart';

/// 2.5D 等距画布视图（v2 M2-D / M5-1 共享渲染基础）。
///
/// 纯 Flutter `CustomPaint` 实现，零第三方 3D 依赖（Q3 已裁决）。
/// 等距投影（架构 §3.2.3）：
/// ```
/// screenX = (col - row) * tileW / 2 + offsetX
/// screenY = (col + row) * tileH / 2 + offsetY
/// ```
/// 绘制：顶面（菱形）+ 左右侧面（伪 3D 厚度）；手势命中做像素 → 网格逆变换。
class VoxelCanvasView extends StatelessWidget {
  const VoxelCanvasView({
    super.key,
    required this.controller,
    this.onTapBlock,
    this.tileW = 44,
    this.tileH = 26,
    this.height = 320,
    this.showGrid = true,
  });

  final VoxelCanvasController controller;

  /// 点击方块回调（(col,row)）。
  final void Function(int col, int row)? onTapBlock;

  /// 瓦片宽 / 高（等距菱形对角线的一半）。
  final double tileW;
  final double tileH;

  /// 画布高度（宽度自适应）。
  final double height;

  /// 是否绘制网格线（小游戏里可关闭）。
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double w = constraints.maxWidth;
          final double h = height;
          // 画布居中，菱形区偏移
          final double offsetX = w / 2;
          final double offsetY = h / 2 - (controller.cols + controller.rows) * tileH / 4;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails d) {
              final (int, int)? cell = _hitTest(
                d.localPosition.dx,
                d.localPosition.dy,
                offsetX,
                offsetY,
              );
              if (cell != null) onTapBlock?.call(cell.$1, cell.$2);
            },
            child: CustomPaint(
              size: Size(w, h),
              painter: _VoxelPainter(
                controller: controller,
                offsetX: offsetX,
                offsetY: offsetY,
                tileW: tileW,
                tileH: tileH,
                showGrid: showGrid,
                repaint: controller,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 像素 → 网格坐标（等距逆变换）。
  (int, int)? _hitTest(double x, double y, double offsetX, double offsetY) {
    final double u = (x - offsetX) / (tileW / 2);
    final double v = (y - offsetY) / (tileH / 2);
    final double colF = (u + v) / 2;
    final double rowF = (v - u) / 2;
    final int col = colF.floor();
    final int row = rowF.floor();
    if (!controller.inBounds(col, row)) return null;
    // 菱形内判定（点到菱形中心的曼哈顿距离）
    final double cx = (col - row) * tileW / 2 + offsetX;
    final double cy = (col + row) * tileH / 2 + offsetY;
    final double dx = (x - cx).abs();
    final double dy = (y - cy).abs();
    if (dx / (tileW / 2) + dy / (tileH / 2) > 1.0) return null;
    return (col, row);
  }
}

/// 等距菱形瓦片 painter。
class _VoxelPainter extends CustomPainter {
  _VoxelPainter({
    required this.controller,
    required this.offsetX,
    required this.offsetY,
    required this.tileW,
    required this.tileH,
    required this.showGrid,
    // repaint: 控制器自身作为重绘信号源——applyEnvelope（每帧）与编辑
    // （setBlock/load）都 notifyListeners → 自动重绘。
    super.repaint,
  });

  final VoxelCanvasController controller;
  final double offsetX;
  final double offsetY;
  final double tileW;
  final double tileH;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.borderDefault;

    // 底格
    for (int row = 0; row < controller.rows; row++) {
      for (int col = 0; col < controller.cols; col++) {
        final Offset c = _center(col, row);
        final Path diamond = _diamond(c);
        if (showGrid) {
          canvas.drawPath(diamond, gridPaint);
        }
      }
    }

    // 方块（先画侧面再画顶面，保持前后遮挡大致正确：row+col 从小到大）
    final List<(int, int)> cells = controller.allCells();
    cells.sort(((int, int) a, (int, int) b) {
      final int sa = a.$1 + a.$2;
      final int sb = b.$1 + b.$2;
      return sa.compareTo(sb);
    });
    for (final (int, int) cell in cells) {
      final String? typeId = controller.blocks[VoxelCanvasController.keyOf(
        cell.$1,
        cell.$2,
      )];
      if (typeId == null) continue;
      final VoxelBlockType type = voxelBlockTypeById(typeId);
      final String key = VoxelCanvasController.keyOf(cell.$1, cell.$2);

      // ── Module "MusicViz-2.5D"：音乐驱动的高度起伏 + 脉冲 + 亮度 ──
      // 静态度底（来自 3D 提取高度比）叠加当前帧频段能量 → 挤出厚度。
      final List<double>? bands = controller.vizBands;
      final double beat = controller.vizBeat;
      final double level = controller.vizLevel;
      final int bandCount = bands?.length ?? 16;
      final double h = controller.heightOf(key);
      final double energy = bands == null
          ? 0.0
          : bands[controller.bandIndexFor(key, bandCount)].clamp(0.0, 1.0);
      final VoxelVizSettings viz = controller.vizSettings;
      final double hh = tileH / 2;
      final double depth = hh * (0.4 + h * 0.6 + energy * viz.amplitude);
      // 节拍脉冲：顶面菱形缩放（强度随可视化设置，默认 1.0 → 1.15）。
      final double topScale = 1.0 + beat * viz.beatPulse;
      // 整体亮度随 level 呼吸（0.7~1.3，保 WCAG 对比，不压暗丢失）。
      final double brightness = (1.0 + (level - 0.5) * 0.3).clamp(0.7, 1.3);

      _drawBlock(canvas, cell.$1, cell.$2, type, depth, topScale, brightness);
    }

    // 选中高亮（当前选中类型）
    final Offset sel = _center(controller.cols ~/ 2, controller.rows ~/ 2);
    canvas.drawCircle(
      sel,
      6,
      Paint()..color = AppColors.accent,
    );
  }

  void _drawBlock(
    Canvas canvas,
    int col,
    int row,
    VoxelBlockType type,
    double depth,
    double topScale,
    double brightness,
  ) {
    final Offset c = _center(col, row);
    final double hw = tileW / 2;
    final double hh = tileH / 2;
    final double topHw = hw * topScale;
    final double topHh = hh * topScale;

    // 左面（暗 22%）
    final Path left = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx - hw, c.dy + hh)
      ..lineTo(c.dx - hw, c.dy + hh + depth)
      ..lineTo(c.dx, c.dy + depth)
      ..close();
    canvas.drawPath(left, Paint()..color = _darken(type.color, 0.22));

    // 右面（暗 38%）
    final Path right = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx + hw, c.dy + hh)
      ..lineTo(c.dx + hw, c.dy + hh + depth)
      ..lineTo(c.dx, c.dy + depth)
      ..close();
    canvas.drawPath(right, Paint()..color = _darken(type.color, 0.38));

    // 顶面（按节拍缩放的菱形）
    final Path top = Path()
      ..moveTo(c.dx, c.dy - topHh)
      ..lineTo(c.dx + topHw, c.dy)
      ..lineTo(c.dx, c.dy + topHh)
      ..lineTo(c.dx - topHw, c.dy)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.fill
        ..color = _shade(type.color, brightness),
    );
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _darken(type.color, 0.5),
    );

    // 顶面符号（字号随脉冲缩放）
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: type.glyph,
        style: TextStyle(
          fontSize: tileH * 0.7 * topScale,
          color: AppColors.onAccent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  Offset _center(int col, int row) => Offset(
        (col - row) * tileW / 2 + offsetX,
        (col + row) * tileH / 2 + offsetY,
      );

  Path _diamond(Offset c) {
    final double hw = tileW / 2;
    final double hh = tileH / 2;
    return Path()
      ..moveTo(c.dx, c.dy - hh)
      ..lineTo(c.dx + hw, c.dy)
      ..lineTo(c.dx, c.dy + hh)
      ..lineTo(c.dx - hw, c.dy)
      ..close();
  }

  Color _darken(Color c, double factor) => Color.lerp(c, Colors.black, factor)!;

  /// 亮度调制：b≤1 向黑压暗、b>1 向白提亮（上限 0.3），保对比度不丢失。
  Color _shade(Color c, double b) => b <= 1
      ? Color.lerp(Colors.black, c, b)!
      : Color.lerp(c, Colors.white, (b - 1).clamp(0.0, 0.3))!;

  @override
  bool shouldRepaint(covariant _VoxelPainter oldDelegate) =>
      oldDelegate.controller != controller ||
      oldDelegate.offsetX != offsetX ||
      oldDelegate.offsetY != offsetY ||
      oldDelegate.controller.vizVersion != controller.vizVersion;
}
