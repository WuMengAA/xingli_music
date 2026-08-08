import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/palette.dart';
import '../providers/theme/theme_providers.dart';

/// 调色盘：右上角微光圆点入口。
///
///  - 6 组预设色块 + 自定义色环（Hue 环 + 亮度滑块）
///  - 选中后全自动派生配色（V1.0 1.4）
///  - 响应式面板尺寸
class PalettePanel extends ConsumerStatefulWidget {
  const PalettePanel({super.key});

  @override
  ConsumerState<PalettePanel> createState() => _PalettePanelState();
}

class _PalettePanelState extends ConsumerState<PalettePanel> {
  bool _draggingHue = false;
  double _dragHue = 0;

  @override
  Widget build(BuildContext context) {
    final bool isOpen = ref.watch(paletteOpenProvider);
    final Color primary = ref.watch(effectivePrimaryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── 入口：24×24 微光圆点 ──────────────────────
        GestureDetector(
          onTap: () =>
              ref.read(paletteOpenProvider.notifier).state = !isOpen,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary,
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.6),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),

        // ── 展开面板（由小展开成卡片的动画）─────────────
        if (isOpen)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _buildPanel(context, primary),
            ),
          ),
      ],
    );
  }

  /// 展开面板内容
  Widget _buildPanel(BuildContext context, Color primary) {
    final HSLColor hsl = HSLColor.fromColor(primary);

    return Material(
      color: Colors.transparent,
      child: Container(
          width: _panelWidth(context),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x66101420),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 预设色块 ──────────────────────────
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: palettePresets.map((preset) {
                      final bool selected = preset.color == primary;
                      return GestureDetector(
                        onTap: () {
                          ref.read(primaryColorProvider.notifier).state =
                              preset.color;
                          ref.read(customColorProvider.notifier).state = null;
                        },
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          scale: selected ? 1.08 : 1.0,
                          child: Container(
                            width: _blockSize(context),
                            height: _blockSize(context),
                            decoration: BoxDecoration(
                              color: preset.color,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.1),
                                width: selected ? 1.5 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: preset.color
                                            .withValues(alpha: 0.5),
                                        blurRadius: 12,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                preset.name,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // ── 分割线 ────────────────────────────
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Colors.white12,
                    ),
                  ),

                  // ── 自定义色环 + 亮度滑块 ──────────────
                  Row(
                    children: [
                      // Hue 色环（选色相）
                      GestureDetector(
                        onPanStart: (d) {
                          _draggingHue = true;
                          _dragHue = _hueFromLocal(d.localPosition, 56);
                          _applyHue(_dragHue);
                        },
                        onPanUpdate: (d) {
                          if (!_draggingHue) return;
                          _dragHue = _hueFromLocal(d.localPosition, 56);
                          _applyHue(_dragHue);
                        },
                        onPanEnd: (_) => _draggingHue = false,
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: CustomPaint(
                            painter: _HueRingPainter(
                              hue: hsl.hue,
                              color: primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // 亮度滑块
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '亮度 ${(hsl.lightness * 100).round()}%',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            Slider(
                              value: hsl.lightness.clamp(0.1, 0.9),
                              min: 0.1,
                              max: 0.9,
                              activeColor: primary,
                              inactiveColor: Colors.white12,
                              onChanged: (v) {
                                ref
                                    .read(customColorProvider.notifier)
                                    .state = hsl.withLightness(v).toColor();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Text(
                    '主色驱动全部配色 · 实时派生',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
        ),
      );
  }

  void _applyHue(double hue) {
    final Color cur = ref.read(effectivePrimaryProvider);
    final HSLColor h = HSLColor.fromColor(cur);
    ref.read(customColorProvider.notifier).state =
        h.withHue(hue).toColor();
  }

  /// 环上触点 → 色相（度）
  double _hueFromLocal(Offset local, double radius) {
    final Offset center = Offset(radius, radius);
    final Offset diff = local - center;
    final double angle = atan2(diff.dy, diff.dx);
    return (angle * 180 / pi + 90 + 360) % 360;
  }

  /// 面板宽度（响应式，V1.0 5.2）
  double _panelWidth(BuildContext context) {
    final double w = MediaQuery.of(context).size.width;
    if (w < 400) return w * 0.85;
    if (w < 600) return w * 0.75;
    if (w < 900) return w * 0.55;
    return 320;
  }

  /// 色块尺寸（响应式）
  double _blockSize(BuildContext context) {
    final double w = MediaQuery.of(context).size.width;
    if (w < 400) return 40;
    if (w < 600) return 44;
    return 48;
  }
}

/// Hue 色环画笔
class _HueRingPainter extends CustomPainter {
  final double hue;
  final Color color;
  const _HueRingPainter({required this.hue, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, ring);

    // 当前色相指示点
    final double angle = (hue - 90) * pi / 180;
    final Offset dot = Offset(
      center.dx + cos(angle) * radius,
      center.dy + sin(angle) * radius,
    );
    canvas.drawCircle(
      dot,
      5,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      dot,
      5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HueRingPainter old) =>
      old.hue != hue || old.color != color;
}
