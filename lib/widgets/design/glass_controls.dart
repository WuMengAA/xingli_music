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
  return Colors.white.withValues(alpha: dark ? 0.20 : 0.6);
}

/// 1px 细描边色（跟随明暗主题）。
Color _hairline(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return Colors.white.withValues(alpha: dark ? 0.22 : 0.5);
}

/// 下拉弹出面板底色：浮层之上，通透优先但**不牺牲可读性**——
/// 原生 [DropdownButton] 的菜单无法插入 BackdropFilter，故用高不透明度
/// 底色 + 圆角模拟玻璃面板，选中项高亮由 DropdownButton 自身保证。
Color _menuFill(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? const Color(0xFF1B1D22).withValues(alpha: 0.94)
      : Colors.white.withValues(alpha: 0.96);
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

/// 玻璃图标按钮（替代 IconButton）。
///
/// 语义与 IconButton 对齐：**默认 48dp 触控区**（无障碍底线，不缩），
/// 保留 [tooltip] 与 Ink 点击响应（不用 GestureDetector 退化）。
/// 与 [XGlassButton] 同理**不做背景模糊**——按钮级 BackdropFilter 是
/// saveLayer，调用点上百处时代价极高；透明填充 + 细描边足够表达玻璃感。
///
/// [selected] 为 true 时填充加强（用于「当前视图 / 已启用」等选中态）。
class XGlassIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final double? size;
  final double? radius;
  final Color? tint;
  final Color? color;

  const XGlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.selected = false,
    this.size,
    this.radius,
    this.tint,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final double s = size ?? 48;
    final double r = radius ?? 14;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fill = tint ??
        (selected
            ? Colors.white.withValues(alpha: dark ? 0.34 : 0.82)
            : _surfaceFill(context, null));
    final Color line = _hairline(context);
    final Widget inner = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: line, width: 1),
      ),
      child: Center(
        child: color == null
            ? icon
            : IconTheme.merge(data: IconThemeData(color: color), child: icon),
      ),
    );
    Widget btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(r),
        splashFactory: NoSplash.splashFactory,
        child: inner,
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    return SizedBox(width: s, height: s, child: btn);
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

/// 玻璃下拉框（替代 DropdownButton）。
///
/// 输入态：半透明填充 + 1px 细描边 + 圆角，去掉原生下划线，保留下拉箭头。
/// 弹出面板：圆角 + 高不透明玻璃底（数量少、可读优先），选中项高亮交给
/// 原生 DropdownButton。参数与原生对齐，调用点可直接换名替换。
class XGlassDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;
  final Widget? disabledHint;
  final bool isExpanded;
  final double? radius;
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final double iconSize;

  const XGlassDropdown({
    super.key,
    this.value,
    required this.items,
    this.onChanged,
    this.hint,
    this.disabledHint,
    this.isExpanded = true,
    this.radius,
    this.tint,
    this.padding,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final double r = radius ?? 12;
    final Color fill = _surfaceFill(context, tint);
    final Color line = _hairline(context);
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: line, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          hint: hint,
          disabledHint: disabledHint,
          isExpanded: isExpanded,
          iconSize: iconSize,
          borderRadius: BorderRadius.circular(r),
          dropdownColor: _menuFill(context),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
