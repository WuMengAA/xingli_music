/// ════════════════════════════════════════════════════════════════════════
/// Liquid Glass 玻璃容器（双模式）
/// ════════════════════════════════════════════════════════════════════════
///
/// 支持两种风格：
///  - [GlassStyle.frosted] 经典毛玻璃：背景模糊 + 半透明 + 细描边（默认，统一不诡异）
///  - [GlassStyle.liquid]  液态玻璃：折射 + 色散（FragmentShader，Dock 栏专用，待精调）
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings/performance_providers.dart';
import '../providers/shell/liquid_glass_capture_provider.dart';

/// 玻璃风格。
enum GlassStyle {
  /// 经典毛玻璃：背景模糊 + 半透明 + 细描边。
  frosted,

  /// 液态玻璃：折射 + 色散（FragmentShader），Dock 栏专用，待精调。
  liquid,
}

/// 玻璃容器。
class LiquidGlass extends ConsumerStatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.style = GlassStyle.frosted,
    this.blur,
    this.tint = const Color(0x22FFFFFF),
    this.borderColor = const Color(0x33FFFFFF),
    this.refraction = 5,
    this.dispersion = 1.2,
    this.padding = EdgeInsets.zero,
  });

  /// 玻璃内容。
  final Widget child;

  /// 圆角半径。
  final double radius;

  /// 玻璃风格；默认 [GlassStyle.frosted]（毛玻璃）。
  final GlassStyle style;

  /// 毛玻璃模糊强度（仅 [GlassStyle.frosted]）。
  ///
  /// 为 `null` 时由全局性能模式决定（省电=0 / 均衡=12 / 流畅=20），
  /// 低端设备切「省电」可即时关闭模糊、明显降发热。
  final double? blur;

  /// 毛玻璃半透明叠加色（仅 [GlassStyle.frosted]）。
  final Color tint;

  /// 毛玻璃描边色（仅 [GlassStyle.frosted]）。
  final Color borderColor;

  /// 折射强度（仅 [GlassStyle.liquid]，0~20）。
  final double refraction;

  /// 色散强度（仅 [GlassStyle.liquid]，0~4）。
  final double dispersion;

  /// 内容内边距。
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends ConsumerState<LiquidGlass> {
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    if (widget.style == GlassStyle.liquid) _load();
  }

  Future<void> _load() async {
    try {
      final ui.FragmentProgram p = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      if (mounted) setState(() => _program = p);
    } catch (e) {
      debugPrint('liquid_glass shader load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == GlassStyle.liquid) {
      return _buildLiquid(context);
    }
    // 毛玻璃：BackdropFilter 模糊 + 半透明 tint + 细描边。
    // 开销跟随全局性能模式：
    //   - 省电：blur=0（跳过 BackdropFilter）+ tint 减淡（半透明效果关闭）
    //   - 均衡/流畅：按档位模糊，保留半透明
    final PerformanceMode perf = ref.watch(performanceModeProvider);
    final double blur = widget.blur ?? ref.watch(glassBlurProvider);
    final double radius = widget.radius;
    // 省电模式把半透明叠加减到接近 0（用户要求：关闭一切半透明效果）
    final Color tint = perf == PerformanceMode.powerSave
        ? widget.tint.withValues(alpha: widget.tint.a * 0.15)
        : widget.tint;
    final Widget child = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: widget.borderColor, width: 1),
      ),
      child: widget.child,
    );
    if (blur <= 0) {
      // 省电模式：跳过 BackdropFilter（模糊是全屏采样，开销最大）
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }

  /// 液态玻璃（折射 + 色散，FragmentShader）。Dock 栏专用，待精调。
  Widget _buildLiquid(BuildContext context) {
    final ui.Image? bg = LiquidGlassCapture.maybeOf(context);
    final Widget content = Padding(padding: widget.padding, child: widget.child);

    if (bg == null || _program == null) {
      // 背景快照或 shader 未就绪：退回纯内容（测试/首帧）。
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          // 底层：折射 + 色散的背景。
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RefractionPainter(
                  program: _program!,
                  background: bg,
                  radius: widget.radius,
                  refraction: widget.refraction,
                  dispersion: widget.dispersion,
                ),
              ),
            ),
          ),
          // 上层：玻璃内容。
          content,
        ],
      ),
    );
  }
}

/// 用 FragmentShader 绘制折射 + 色散背景。
class _RefractionPainter extends CustomPainter {
  _RefractionPainter({
    required this.program,
    required this.background,
    required this.radius,
    required this.refraction,
    required this.dispersion,
  });

  final ui.FragmentProgram program;
  final ui.Image background;
  final double radius;
  final double refraction;
  final double dispersion;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.FragmentShader shader = program.fragmentShader();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, radius)
      ..setFloat(3, refraction)
      ..setFloat(4, dispersion)
      ..setImageSampler(0, background);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _RefractionPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.radius != radius ||
      oldDelegate.refraction != refraction ||
      oldDelegate.dispersion != dispersion;
}
