import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../app_icon.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 统一播放控制按钮（MiniPlayer / ControlBar / ScenePlaybackPanel 共用）
/// ════════════════════════════════════════════════════════════════════════
///
/// 解决「各页播放控制器不统一」：三处原先分别用
///  - MiniPlayer：Material 线性图标 + `iconPrimary`
///  - ControlBar：自定义 SVG 图标集（AppIcon）+ `colorScheme`
///  - ScenePlaybackPanel：混合 Material 实心/线性图标 + 硬编码浅色常量
///
/// 现在统一收敛到本按钮：
///  - 图标源：优先 `AppIcon`（星璃 SVG 包）承载核心传输键（prev/play/next/
///    volume）；AppIcon 未覆盖的语义键（如播放模式）仍走 `IconData`。
///  - 颜色：默认 `context.appColors.iconPrimary`（明暗自适应）；`active` 时
///    改用品牌紫 `accent`；均可通过 [color] 显式覆盖。
///  - 可选圆形 tint 背景（[tint]），用于场景页的小圆钮组。
///
/// 取色约定：业务代码统一调用，不要再手写 `Color(0x...)`.
class PlaybackIconButton extends StatelessWidget {
  const PlaybackIconButton({
    super.key,
    this.svgName,
    this.icon,
    required this.onTap,
    this.color,
    this.size = 26,
    this.tooltip,
    this.active = false,
    this.tint = false,
    this.tintColor,
    this.disabled = false,
    this.fit = false,
  }) : assert(svgName != null || icon != null,
            'PlaybackIconButton 必须提供 svgName 或 icon 之一');

  /// 星璃 SVG 图标名（AppIcons.*），优先级高于 [icon]。
  final String? svgName;

  /// Material 图标（用于 AppIcon 未覆盖的语义键，如播放模式）。
  final IconData? icon;

  final VoidCallback? onTap;

  /// 显式颜色；不传则走 [active] ? accent : iconPrimary。
  final Color? color;

  /// 图标边长（AppIcon/Icon 共用）。
  final double size;

  final String? tooltip;

  /// 激活态：图标变品牌紫 + 可选 tint 背景高亮。
  final bool active;

  /// 是否绘制圆形 tint 背景。
  final bool tint;

  /// 自定义 tint 背景色（active 默认 accentSoft，inactive 默认 iconInactive 14%）。
  final Color? tintColor;

  final bool disabled;

  /// 图标套 FittedBox(scaleDown)，防窄容器溢出（MiniPlayer 控制胶囊用）。
  final bool fit;

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ??
        (active ? context.appColors.accent : context.appColors.iconPrimary);

    Widget iconChild = svgName != null
        ? AppIcon(svgName!, size: size, color: resolved)
        : Icon(icon, size: size, color: resolved);

    if (fit) {
      iconChild = FittedBox(fit: BoxFit.scaleDown, child: iconChild);
    }

    Widget btn = InkWell(
      onTap: disabled ? null : onTap,
      customBorder: const CircleBorder(),
      child: Center(child: iconChild),
    );

    if (tint) {
      final Color bg = active
          ? (tintColor ?? context.appColors.accentSoft)
          : (tintColor ?? context.appColors.iconInactive.withValues(alpha: 0.14));
      btn = Container(
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: btn,
      );
    }

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// 播放传输行：统一 `MainAxisAlignment.spaceEvenly` 的横向控件布局。
///
/// [children] 由调用方传入（已是 `PlaybackIconButton` 等），本组件只负责
/// 对齐与基础间距，确保三处播放器的控制行观感一致。
class PlaybackTransportRow extends StatelessWidget {
  const PlaybackTransportRow({
    super.key,
    required this.children,
    this.spacing = 6,
    this.mainAxisAlignment = MainAxisAlignment.spaceEvenly,
  });

  final List<Widget> children;
  final double spacing;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      children: <Widget>[
        for (int i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: spacing),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}
