import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/palette.dart';
import '../core/spring.dart';
import 'glass_surface.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassToggle —— 液态玻璃开关
///
/// 忠实移植 liquid-glass-webgl `build-toggle.ts` + LiquidToggle.kt：
/// - 轨道：56×32dp 胶囊（cornerRadius = 16），轨道底色忠实 toggleTrackOff，
///   开启时用 accent 色的半透明表面
/// - knob：24×24 正圆，位移用临界阻尼弹簧（spring(1f, 1000f)），
///   scaleX（spring(0.6f, 250f)）/ scaleY（spring(0.7f, 250f)）欠阻尼，
///   拖拽速度弹簧（spring(0.5f, 300f)）
/// - 按压缩放用欠阻尼通用弹簧（ζ=0.5）
/// ───────────────────────────────────────────────────────────────────────

class GlassToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 尺寸（高度 × 宽度倍数）。
  final Size size;

  /// 自定义 accent 色（null → 主题 toggleAccent）。
  final Color? accentColor;

  /// 模糊半径。
  final double blur;

  const GlassToggle({
    super.key,
    required this.value,
    this.onChanged,
    this.size = const Size(56, 32),
    this.accentColor,
    this.blur = 8,
  });

  @override
  State<GlassToggle> createState() => _GlassToggleState();
}

class _GlassToggleState extends State<GlassToggle>
    with SingleTickerProviderStateMixin {
  // knob 位移（临界阻尼）
  final SpringCritical1D _valueSpring =
      SpringCritical1D(omegaN: kToggleValueOmegaN);
  // knob 缩放（欠阻尼）
  double _scaleX = 1, _scaleY = 1;
  double _scaleXVel = 0, _scaleYVel = 0;
  // 按下（整体缩放）
  final Spring1D _pressSpring = Spring1D(
      omegaN: math.sqrt(kToggleVelocityK), dampingRatio: kToggleVelocityDampingRatio);
  bool _pressed = false;
  bool _dragging = false;

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _valueSpring.value = widget.value ? 1 : 0;
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(GlassToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_dragging) {
      _startTick();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _startTick() {
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (!_ticker.isActive) return;
    final dt = _last == Duration.zero ? (1 / 60.0) : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;

    final target = widget.value ? 1.0 : 0.0;
    final moving = _valueSpring.step(target, dt);
    final sx = springStepUnderdamped(_scaleX, _scaleXVel, 1.0, dt,
        omegaN: kToggleScaleXOmegaN, dampingRatio: kToggleScaleXDampingRatio);
    _scaleX = sx.value;
    _scaleXVel = sx.velocity;
    final sy = springStepUnderdamped(_scaleY, _scaleYVel, 1.0, dt,
        omegaN: kToggleScaleYOmegaN, dampingRatio: kToggleScaleYDampingRatio);
    _scaleY = sy.value;
    _scaleYVel = sy.velocity;
    final pressTarget = _pressed ? 0.92 : 1.0;
    final press = _pressSpring.step(pressTarget - 1.0, dt) || moving;

    if (mounted) setState(() {});
    if (!press && !moving && (_scaleX - 1).abs() < kSpringThreshold) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  void _setValue(bool v) {
    widget.onChanged?.call(v);
    _startTick();
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = glassPaletteFor(
        Theme.of(context).brightness == Brightness.dark
            ? GlassThemeMode.dark
            : GlassThemeMode.light);
    final Color accent = widget.accentColor ?? palette.toggleAccent;
    final bool on = widget.value;

    final Size s = widget.size;
    final double trackW = s.width;
    final double trackH = s.height;
    final double knobD = trackH - 8; // 24dp at 32dp height
    final double padX = 4;

    final double maxOffset = trackW - padX * 2 - knobD; // 24
    final double knobOffset = _valueSpring.value * maxOffset;
    final bool dark =
        Theme.of(context).brightness == Brightness.dark;

    // 轨道：accent 半透明（on）或 trackOff 底色（off），并叠毛玻璃。
    final Color trackFill = on
        ? accent.withValues(alpha: 0.85)
        : palette.toggleTrackOff;
    final Widget track = Container(
      width: trackW,
      height: trackH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(trackH / 2),
        color: trackFill,
      ),
    );

    // knob。
    final Widget knob = Transform.translate(
      offset: Offset(knobOffset, 0),
      child: Transform.scale(
        scaleX: _scaleX,
        scaleY: _scaleY,
        child: Container(
          width: knobD,
          height: knobD,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dark
                ? const Color(0xFF1C1C1E)
                : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );

    final Widget body = Stack(
      alignment: Alignment.centerLeft,
      children: [
        GlassSurface(
          visuals: GlassVisuals(blur: widget.blur, radius: trackH / 2),
          child: track,
        ),
        Positioned(
          left: padX,
          child: knob,
        ),
      ],
    );

    return Semantics(
      toggled: on,
      label: 'toggle',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          setState(() => _pressed = true);
          _startTick();
        },
        onTapUp: (d) {
          setState(() => _pressed = false);
          _setValue(!widget.value);
        },
        onTapCancel: () {
          setState(() => _pressed = false);
          _startTick();
        },
        onHorizontalDragStart: (_) {
          _dragging = true;
          setState(() => _pressed = true);
          _startTick();
        },
        onHorizontalDragUpdate: (d) {
          final double frac = (d.localPosition.dx - padX) / maxOffset;
          final bool nowOn = frac > 0.5;
          if (nowOn != widget.value) widget.onChanged?.call(nowOn);
          _valueSpring.value = frac.clamp(0.0, 1.0).toDouble();
        },
        onHorizontalDragEnd: (_) {
          _dragging = false;
          setState(() => _pressed = false);
          _setValue(fracToBool(_valueSpring.value));
        },
        onHorizontalDragCancel: () {
          _dragging = false;
          setState(() => _pressed = false);
          _setValue(widget.value);
        },
        child: Transform.scale(
          scale: _pressSpring.value + 1.0,
          child: body,
        ),
      ),
    );
  }

  bool fracToBool(double f) => f > 0.5;
}