import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassCard —— 液态玻璃卡片
///
/// 忠实移植 liquid-glass-webgl `build-dialog.ts` / 主页卡片的视觉：
/// 默认大圆角（16dp，可覆写）、背景模糊 + 半透明着色 + 高光带，
/// 内容由 [child] 提供。性能预设控制模糊开关。
/// ───────────────────────────────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget? child;
  final EdgeInsetsGeometry padding;

  /// 圆角半径（逻辑 px，默认 16；胶囊传 double.infinity）。
  final double radius;

  /// 背景模糊半径。
  final double blur;

  /// 表面色调（null → 主题默认）。
  final Color? tint;

  /// 高光带颜色。
  final Color? highlightColor;

  /// 细描边（默认主题对比色 hairline）。
  final Color? borderColor;

  /// 是否可交互（true → 包 GestureDetector，onTap 生效）。
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 16,
    this.blur = 8,
    this.tint,
    this.highlightColor,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color highlight = highlightColor ??
        (dark ? const Color(0x28FFFFFF) : const Color(0x1AFFFFFF));
    final Color border = borderColor ??
        (dark ? const Color(0x26FFFFFF) : const Color(0x14000000));

    final Widget glass = GlassSurface(
      visuals: GlassVisuals(
        blur: blur,
        tint: tint,
        radius: radius,
        highlightColor: highlight,
        borderColor: border,
      ),
      padding: padding,
      child: child ?? const SizedBox.shrink(),
    );

    if (onTap == null) return glass;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: glass,
    );
  }
}