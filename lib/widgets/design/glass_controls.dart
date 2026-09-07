/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 玻璃控件模板（设计基准件 · 平面抽象 / 标准 BackdropFilter）
/// ════════════════════════════════════════════════════════════════════════
///
/// 2026-09-06 方向修正：原封装自 [liquid_glass_compat] 的 WebGL 按钮/滑块/
/// 开关在真机到处有显示 bug、不可用。现统一改写为**标准 [BackdropFilter]
/// 透明模糊 + 半透明填充 + 1px 细描边 + 圆角**的可靠玻璃件，作为后续所有
/// 交互控件的基准——新增交互一律用这些，不再裸写 Material 控件。
///
/// 替换原则（API 保持不变，调用点零改动）：
///   FilledButton/TextButton/ElevatedButton/OutlinedButton → [XGlassButton]
///   Slider                                 → [XGlassSlider]（原生 Slider，支持任意 min/max + divisions）
///   Switch                                 → [XGlassToggle]
///   装饰性卡片                              → [XGlassCard]
library;

import 'package:flutter/material.dart';
import 'dart:ui';

/// 统一玻璃模糊强度（px）。
const double _kGlassBlur = 14;
const double _kGlassRadius = 16;

/// 半透明填充：深色主题更透、浅色主题略实；[tint] 非空时直接用。
Color _surfaceFill(BuildContext context, Color? tint) {
  if (tint != null) return tint;
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return Colors.white.withValues(alpha: dark ? 0.12 : 0.6);
}

/// 1px 细描边色（跟随明暗主题）。
Color _hairline(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return Colors.white.withValues(alpha: dark ? 0.16 : 0.5);
}

/// 玻璃按钮（替代 FilledButton / TextButton / ElevatedButton / OutlinedButton）。
class XGlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final double? radius;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  const XGlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.fullWidth = false,
    this.radius,
    this.tint,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final double r = radius ?? _kGlassRadius;
    final Color fill = _surfaceFill(context, tint);
    final Color line = _hairline(context);
    // 内存：按钮**不做背景模糊**。每个 BackdropFilter 都是一个 saveLayer，
    // 而按钮面积小、模糊几乎看不出来，但调用点有 150+ 处，同时存在时代价极高
    // （省电与内存目标 <100MB 的关键一刀）。透明填充 + 细描边已足够表达玻璃感；
    // 需要真模糊的浮层/卡片请用 XGlassCard / LiquidGlass。
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(r),
          splashFactory: NoSplash.splashFactory,
          child: Container(
            padding:
                padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: line, width: 1),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// 玻璃滑块（替代 Slider，支持任意 min/max + divisions 吸附）。
///
/// 直接封装原生 [Slider]，可靠且语义一致；[divisions] 保留刻度吸附，
/// [accentColor] 映射到 [Slider.activeColor]。
class XGlassSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final Color? accentColor;
  final double? blur;

  const XGlassSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.accentColor,
    this.blur,
  });

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      activeColor: accentColor ?? Theme.of(context).colorScheme.primary,
      onChanged: onChanged,
    );
  }
}

/// 玻璃开关（替代 Switch）。
class XGlassToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? accentColor;
  final double? blur;

  const XGlassToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.accentColor,
    this.blur,
  });

  @override
  Widget build(BuildContext context) => Switch(
        value: value,
        onChanged: onChanged,
        activeColor: accentColor ?? Theme.of(context).colorScheme.primary,
      );
}

/// 玻璃卡片（装饰 / 可点击容器）。
class XGlassCard extends StatelessWidget {
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final Color? tint;
  final Color? borderColor;
  final VoidCallback? onTap;

  const XGlassCard({
    super.key,
    this.child,
    this.padding,
    this.radius,
    this.tint,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double r = radius ?? 18;
    final Color fill = tint ?? _surfaceFill(context, null);
    final Color line = borderColor ?? _hairline(context);
    final Widget box = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: line, width: 1),
      ),
      child: child,
    );
    final Widget blurred = ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _kGlassBlur, sigmaY: _kGlassBlur),
        child: box,
      ),
    );
    if (onTap == null) return blurred;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(r),
          splashFactory: NoSplash.splashFactory,
          child: box,
        ),
      ),
    );
  }
}
