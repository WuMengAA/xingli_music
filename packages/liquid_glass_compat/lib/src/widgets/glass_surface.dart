import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/continuous_curve.dart';
import '../core/performance.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassSurface —— 液态玻璃通用底层
///
/// 把 liquid-glass-webgl 的元素渲染管线浓缩成 Flutter widget：
/// 1. G2 连续曲率圆角路径裁剪（忠实 G2 角形，非朴素圆角）
/// 2. BackdropFilter 背景模糊（可分离模糊的 Flutter 等价，性能按预设缩放）
/// 3. 半透明着色（tint）+ 可选饱和度提升（liquid-glass-webgl 用
///    saturation=1.4，Flutter 用 ColorFilter.matrix 模拟）
/// 4. 顶部细高光带（忠实 highlight tintColor + 渐变边缘）
/// 5. 可选边缘折射占位（真实折射在 Xingli 走 fragment shader，这里保留
///    API 位，折射强度经 [refraction] 透传给 shader 接入层）
///
/// 这是本包所有组件的共同地基：Card / Button / Toggle / Slider / Dialog
/// / Dock / ProgressiveBlur 全部复用。
/// ───────────────────────────────────────────────────────────────────────

/// 玻璃渲染的主视觉参数。
class GlassVisuals {
  /// 背景模糊半径（逻辑 px；性能预设会按 blurScale 缩放）。
  final double blur;

  /// 表面着色（alpha 即着色强度）。null → 由主题派生。
  final Color? tint;

  /// 圆角半径（逻辑 px）。G2 曲线忠实 Kotlin。
  final double radius;

  /// 折射强度 0~1（透传给 shader 接入层；标准路径忽略）。
  final double refraction;

  /// 色差强度 0~1（同上）。
  final double dispersion;

  /// 饱和度（默认 1.4，对齐 liquid-glass-webgl）。
  final double saturation;

  /// 是否跳过整个模糊（性能档）。
  final bool disableBlur;

  /// 高光带颜色（null = 关闭高光）。
  final Color? highlightColor;

  /// 细描边颜色（null = 关闭描边）。
  final Color? borderColor;

  const GlassVisuals({
    this.blur = 8,
    this.tint,
    this.radius = 0,
    this.refraction = 0,
    this.dispersion = 0,
    this.saturation = 1.4,
    this.disableBlur = false,
    this.highlightColor,
    this.borderColor,
  });
}

/// 由主题 + 性能预设解析最终的视觉效果。
GlassVisuals resolveVisuals(
  GlassVisuals visuals,
  GlassPerformanceSettings perf,
  ThemeData theme,
) {
  final Color tint = visuals.tint ??
      (theme.brightness == Brightness.dark
          ? const Color(0x66222222)
          : const Color(0x66FFFFFF));
  return GlassVisuals(
    blur: visuals.disableBlur ? 0 : visuals.blur * perf.blurScale,
    tint: tint,
    radius: visuals.radius,
    refraction: perf.refractionEnabled ? visuals.refraction : 0,
    dispersion: perf.chromaticAberrationEnabled ? visuals.dispersion : 0,
    saturation: visuals.saturation,
    disableBlur: visuals.disableBlur || perf.blurScale <= 0,
    highlightColor: perf.highlightEnabled ? visuals.highlightColor : null,
    borderColor: visuals.borderColor,
  );
}

/// 液态玻璃表面 widget。
///
/// [child] 内容会被铺在玻璃之上；玻璃自身只负责「背景层」——
/// 一致性对齐 liquid-glass-webgl 的 DrawGlassElement 阶段。
class GlassSurface extends StatelessWidget {
  final Widget? child;
  final GlassVisuals visuals;
  final GlassPerformanceSettings? perf;
  final EdgeInsetsGeometry? padding;
  final ShapeBorder? shape; // 自定义形状（null → G2 圆角矩形）

  const GlassSurface({
    super.key,
    this.child,
    this.visuals = const GlassVisuals(),
    this.perf,
    this.padding,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GlassPerformanceSettings p = perf ?? settingsFor(kDefaultPerformancePreset);
    final GlassVisuals v = resolveVisuals(visuals, p, theme);

    Path makePath(Size size) {
      if (shape != null) {
        return shape!.getOuterPath(Offset.zero & size);
      }
      final double r = v.radius == double.infinity
          ? size.shortestSide / 2
          : v.radius;
      return continuousCurvatureRoundedRectPath(size.width, size.height, r);
    }

    Widget layer = child ?? const SizedBox.shrink();
    if (padding != null) {
      layer = Padding(padding: padding!, child: layer);
    }

    // 背景模糊（BackdropFilter ⇔ WebGL 可分离高斯模糊）。
    if (v.blur > 0) {
      layer = ClipPath(
        clipper: _PathClipper(makePath),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: v.blur, sigmaY: v.blur),
          child: layer,
        ),
      );
    }

    // 着色 + 饱和度。用 ColorFiltered 模拟 saturation 提升
    // （liquid-glass-webgl 的 saturation pass）。
    final ColorFilter? tintFilter = _buildSaturationFilter(v);
    if (tintFilter != null) {
      layer = ClipPath(
        clipper: _PathClipper(makePath),
        child: ColorFiltered(colorFilter: tintFilter, child: layer),
      );
    }

    // 玻璃填充层（半透明表面本身）—— 叠加在背景之上。
    layer = Stack(
      fit: StackFit.passthrough,
      children: [
        ClipPath(
          clipper: _PathClipper(makePath),
          child: CustomPaint(
            painter: _GlassFillPainter(
              color: v.tint ?? Colors.transparent,
              highlight: v.highlightColor,
              radius: v.radius,
            ),
          ),
        ),
        layer,
      ],
    );

    // 细描边（忠实 borderColor hairline）。
    if (v.borderColor != null && v.borderColor!.a > 0) {
      layer = CustomPaint(
        painter: _GlassBorderPainter(makePath, v.borderColor!),
        child: layer,
      );
    }

    return layer;
  }

  ColorFilter? _buildSaturationFilter(GlassVisuals v) {
    // saturation 提升 ⇔ 标准饱和度矩阵。
    // liquid-glass-webgl 的 saturation 是精准的颜色饱和度矩阵；
    // Flutter 侧用标准饱和度矩阵近似。
    final double s = v.saturation;
    if ((s - 1.0).abs() < 0.01) return null;
    final double r = 0.2126, g = 0.7152, b = 0.0722;
    final double sr = (1 - s) * r, sg = (1 - s) * g, sb = (1 - s) * b;
    final List<double> matrix = [
      sr + s, sg, sb, 0, 0,
      sr, sg + s, sb, 0, 0,
      sr, sg, sb + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    return ColorFilter.matrix(matrix);
  }
}

class _PathClipper extends CustomClipper<Path> {
  final Path Function(Size) builder;
  _PathClipper(this.builder);

  @override
  Path getClip(Size size) => builder(size);

  @override
  bool shouldReclip(_PathClipper oldClipper) => true;
}

/// 半透明填充 + 顶部高光带绘制器。
class _GlassFillPainter extends CustomPainter {
  final Color color;
  final Color? highlight;
  final double radius;

  _GlassFillPainter({required this.color, this.highlight, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = continuousCurvatureRoundedRectPath(
        size.width, size.height, radius == double.infinity ? size.shortestSide / 2 : radius);

    // 填充。
    if (color.a > 0) {
      canvas.drawPath(path, Paint()..color = color);
    }

    // 顶部高光带：忠实 liquid-glass-webgl 的 highlight pass
    // （渐变从高光色 → 透明，覆盖顶部 1/4）。
    if (highlight != null && highlight!.a > 0) {
      final Rect bounds = path.getBounds();
      final Rect band = Rect.fromLTWH(
          bounds.left, bounds.top, bounds.width, bounds.height * 0.28);
      final Paint gradient = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            highlight!.withValues(alpha: highlight!.a * 0.55),
            highlight!.withValues(alpha: 0),
          ],
        ).createShader(band);
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(band, gradient);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GlassFillPainter old) =>
      old.color != color || old.highlight != highlight || old.radius != radius;
}

class _GlassBorderPainter extends CustomPainter {
  final Path Function(Size) builder;
  final Color color;
  _GlassBorderPainter(this.builder, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      builder(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_GlassBorderPainter old) => old.color != color;
}