import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/spring.dart';
import 'glass_surface.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassButton —— 液态玻璃按钮
///
/// 忠实移植：
/// - liquid-glass-webgl `build-buttons.ts` 的按钮视觉
/// - 按压缩放用欠阻尼弹簧（ζ=0.5，matches LiquidButton.kt 的
///   DampedDragAnimation scale），松手回弹带超调
/// - 高光带（highlight tintColor）跟随主题
/// ───────────────────────────────────────────────────────────────────────

/// 玻璃按钮。
class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  /// 圆角半径（默认胶囊，radius = ∞ 时按最短边 /2）。
  final double radius;

  /// 模糊半径。
  final double blur;

  /// 表面色调（null → 主题默认）。
  final Color? tint;

  /// 高光带颜色（默认跟随主题亮暗）。
  final Color? highlightColor;

  /// 按下缩放目标（默认 0.96，对齐原生果冻感）。
  final double pressedScale;

  /// 是否禁用。
  final bool enabled;

  /// 是否铺满父容器宽度。
  final bool fullWidth;

  /// 内边距。
  final EdgeInsetsGeometry padding;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.radius = double.infinity,
    this.blur = 8,
    this.tint,
    this.highlightColor,
    this.pressedScale = 0.96,
    this.enabled = true,
    this.fullWidth = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  final Spring1D _pressSpring = Spring1D(
      omegaN: math.sqrt(kSpringK), dampingRatio: kSpringDampingRatio);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_ticker.isActive) return;
    final dt = _last == Duration.zero
        ? (1 / 60.0)
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final target = _pressed ? (1 - widget.pressedScale) : 0.0;
    final moving = _pressSpring.step(target, dt);
    if (mounted) setState(() {});
    if (!moving) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  void _startTick() {
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color highlight = widget.highlightColor ??
        (dark ? const Color(0x33FFFFFF) : const Color(0x22FFFFFF));

    final Widget content = GlassSurface(
      visuals: GlassVisuals(
        blur: widget.blur,
        tint: widget.tint,
        radius: widget.radius,
        highlightColor: highlight,
      ),
      padding: widget.padding,
      child: DefaultTextStyle.merge(
        style: theme.textTheme.labelLarge?.copyWith(
          color: dark ? Colors.white : Colors.black,
          fontWeight: FontWeight.w600,
        ),
        child: widget.child,
      ),
    );

    final Widget scaled = Transform.scale(
      scale: 1.0 - _pressSpring.value,
      child: content,
    );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled
            ? (_) {
                setState(() => _pressed = true);
                _startTick();
              }
            : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                _startTick();
              }
            : null,
        onTapCancel: widget.enabled
            ? () {
                setState(() => _pressed = false);
                _startTick();
              }
            : null,
        onTap: widget.enabled ? widget.onPressed : null,
        child: widget.fullWidth ? SizedBox(width: double.infinity, child: scaled) : scaled,
      ),
    );
  }
}