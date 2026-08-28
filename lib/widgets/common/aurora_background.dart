import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 光效 + 图形动态背景（cl05）。
///
/// **非粒子**：由「光斑（radial 渐变光晕）+ 几何图形（圆环 / 光线）」组成，
/// 随时间缓慢漂移、呼吸、旋转——背景的「光与形」在流动。
/// 深色底上使用效果最佳（OOBE / 全屏沉浸页）。
///
/// 用法：`Positioned.fill(child: AuroraBackground(accent: accent))`。
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({
    super.key,
    this.accent,
    this.ambient = const Color(0xFF0B1220),
  });

  /// 主光色（光斑 / 圆环 / 光线的派生源色）；缺省取主题 primary。
  final Color? accent;

  /// 底色（深色底默认）。
  final Color ambient;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  /// 10s 长周期循环，所有元素共用同一时间轴。
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? _) => CustomPaint(
        size: Size.infinite,
        painter: _LightShapePainter(
          accent: accent,
          ambient: widget.ambient,
          t: _ctrl.value,
        ),
      ),
    );
  }
}

/// 光效 + 图形画笔：光斑漂移呼吸 + 圆环旋转 + 光线流动。
class _LightShapePainter extends CustomPainter {
  _LightShapePainter({
    required this.accent,
    required this.ambient,
    required this.t,
  });

  final Color accent;
  final Color ambient;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect full = Offset.zero & size;

    // ── 底色：深色 + 底部向 accent 轻微泛光 ──
    canvas.drawRect(
      full,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[ambient, Color.lerp(ambient, accent, 0.08)!],
        ).createShader(full),
    );

    // ── 光效：3 个光斑（radial 光晕，各自漂移 + 呼吸）──
    _blob(
      canvas,
      Offset(w * (0.18 + 0.55 * _sin(t, 1.0)), h * 0.22),
      size.shortestSide * 0.34,
      accent,
      0.30 + 0.10 * _sin(t, 3.0),
    );
    _blob(
      canvas,
      Offset(w * (0.82 + 0.18 * _cos(t, 1.4)), h * 0.72),
      size.shortestSide * 0.40,
      const Color(0xFF4A6CFF),
      0.16 + 0.06 * _sin(t, 2.2),
    );
    _blob(
      canvas,
      Offset(w * (0.5 + 0.30 * _sin(t, 0.7)), h * (0.95 + 0.10 * _cos(t, 1.9))),
      size.shortestSide * 0.30,
      accent,
      0.12 + 0.05 * _sin(t, 2.6),
    );

    // ── 图形：同心圆环（缺口旋转 + 中心漂移）──
    final Offset ringCenter = Offset(
      w * (0.5 + 0.12 * _sin(t, 0.5)),
      h * (0.5 + 0.12 * _cos(t, 0.7)),
    );
    final double ringR = size.shortestSide * (0.34 + 0.03 * _sin(t, 1.1));
    canvas.save();
    canvas.translate(ringCenter.dx, ringCenter.dy);
    canvas.rotate(t * math.pi * 2);
    // 外环（accent，带缺口 → 有「转」的动感）。
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: ringR),
      0,
      math.pi * 1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent.withValues(alpha: 0.22 + 0.10 * _sin(t, 2.4)),
    );
    // 内环（冷白细环）。
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: ringR * 0.78),
      math.pi,
      math.pi * 1.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.10 + 0.06 * _sin(t, 1.6)),
    );
    canvas.restore();

    // ── 图形：一条流动光线（正弦扫过，accent 微光）──
    final double lx = w * (0.2 + 0.6 * _sin(t, 0.35));
    final Path path = Path()
      ..moveTo(lx, 0)
      ..cubicTo(lx + 60, h * 0.4, lx - 40, h * 0.6, lx + 40, h);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: 0.10 + 0.08 * _sin(t, 1.8)),
    );
  }

  double _sin(double t, double freq) => math.sin(t * math.pi * 2 * freq);
  double _cos(double t, double freq) => math.cos(t * math.pi * 2 * freq);

  /// 画一个 radial 渐变光斑（中心实 → 边缘透明）。
  void _blob(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double alpha,
  ) {
    final Paint p = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          color.withValues(alpha: alpha.clamp(0.0, 1.0)),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, p);
  }

  @override
  bool shouldRepaint(covariant _LightShapePainter old) =>
      old.t != t || old.accent != accent || old.ambient != ambient;
}
