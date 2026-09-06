/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 玻璃控件模板（设计基准件）
/// ════════════════════════════════════════════════════════════════════════
///
/// 用户 2026-09-06 要求：玻璃皮肤必须覆盖**全 app 控件**，而非仅 dock。
/// `liquid_glass_compat` 已提供 GlassButton/GlassSlider/GlassToggle/GlassCard
/// 等现成控件，这里只做一层**轻量模板封装**，统一圆角/模糊/配色默认值，
/// 作为接下来所有开发的基准件——新增交互一律用这些，不再裸写 Material 控件。
///
/// 替换原则：
///   FilledButton/TextButton/ElevatedButton/OutlinedButton → [XGlassButton]
///   Slider                                 → [XGlassSlider]  (值范围 0..1)
///   Switch                                 → [XGlassToggle]
///   装饰性卡片                              → [XGlassCard]
library;

import 'package:flutter/material.dart';
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

/// 统一玻璃参数（基准值，后续集中调一处即可全局生效）。
const double _kGlassBlur = 8;
const double _kGlassRadius = 16;

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
  Widget build(BuildContext context) => GlassButton(
        child: child,
        onPressed: onPressed,
        fullWidth: fullWidth,
        radius: radius ?? _kGlassRadius,
        blur: _kGlassBlur,
        tint: tint,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
}

/// 玻璃滑块（替代 Slider，支持任意 min/max + divisions 吸附，内部映射到玻璃控件的 0..1）。
///
/// 注意：[GlassSlider] 本体只接受 0..1 连续值、无 `divisions`/`label`，
/// 这里在模板层把 [divisions] 吸附回传（保证设置项仍按刻度对齐），[label]
/// 由调用方自行用文本展示（如 _VolSlider 的百分比）。
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
    final double span = max > min ? max - min : 1;
    final double t = ((value - min) / span).clamp(0, 1);
    return GlassSlider(
      value: t,
      onChanged: onChanged == null
          ? null
          : (double nv) {
              if (divisions != null && divisions! > 1) {
                nv = (nv * divisions!).round() / divisions!;
              }
              onChanged!(min + nv * span);
            },
      accentColor: accentColor,
      blur: blur ?? _kGlassBlur,
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
  Widget build(BuildContext context) => GlassToggle(
        value: value,
        onChanged: onChanged,
        accentColor: accentColor,
        blur: blur ?? _kGlassBlur,
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
  Widget build(BuildContext context) => GlassCard(
        child: child,
        padding: padding ?? const EdgeInsets.all(16),
        radius: radius ?? 18,
        blur: _kGlassBlur,
        tint: tint,
        borderColor: borderColor,
        onTap: onTap,
      );
}
