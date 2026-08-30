import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/palette.dart';
import '../core/spring.dart';
import 'glass_surface.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassSlider —— 液态玻璃滑块
///
/// 忠实移植 liquid-glass-webgl `build-slider.ts` + LiquidSlider.kt：
/// - 轨道：胶囊形玻璃 + trackOff 底色
/// - 已选段：sliderAccent 色（亮 #0088FF / 暗 #0091FF）
/// - knob：24dp 正圆，随拖拽移动（临界阻尼弹簧驱动到目标）
/// - 按下整体缩放用欠阻尼弹簧
/// ───────────────────────────────────────────────────────────────────────

class GlassSlider extends StatefulWidget {
  final double value; // 0..1
  final ValueChanged<double>? onChanged;

  /// 轨道高（默认 56dp 玻璃胶囊）。
  final double height;

  /// knob 直径（默认 24）。
  final double knobSize;

  /// 模糊半径。
  final double blur;

  /// accent 色（null → 主题 sliderAccent）。
  final Color? accentColor;

  const GlassSlider({
    super.key,
    required this.value,
    this.onChanged,
    this.height = 56,
    this.knobSize = 24,
    this.blur = 8,
    this.accentColor,
  });

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> with TickerProviderStateMixin {
  // knob 位移（临界阻尼，匹配 DragValue 的 spring(1f, 1000f)）
  double _knobFrac = 0;
  double _knobVel = 0;
  double _scale = 1.0; // 按下缩放（欠阻尼）
  double _scaleVel = 0;

  bool _dragging = false;
  bool _pressed = false;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _knobFrac = widget.value;
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(GlassSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_dragging) _startTick();
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
    // 拖拽中：直接跟手，不上弹簧；松手后由 value 弹簧归位。
    final double target = _dragging ? _knobFrac : widget.value;
    final sr = springStepCritical(_knobFrac, _knobVel, target, dt,
        omegaN: kToggleValueOmegaN);
    _knobFrac = sr.value;
    _knobVel = sr.velocity;
    final double scaleTarget = _pressed ? 0.9 : 1.0;
    final ss = springStepUnderdamped(_scale, _scaleVel, scaleTarget, dt,
        omegaN: math.sqrt(kToggleVelocityK), dampingRatio: kToggleVelocityDampingRatio);
    _scale = ss.value;
    _scaleVel = ss.velocity;
    if (mounted) setState(() {});
    if ((_knobFrac - target).abs() < kSpringThreshold &&
        (_scale - 1).abs() < kSpringThreshold) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = glassPaletteFor(
        Theme.of(context).brightness == Brightness.dark
            ? GlassThemeMode.dark
            : GlassThemeMode.light);
    final Color accent = widget.accentColor ?? palette.sliderAccent;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    final double trackH = widget.height;
    final double hPad = 12.0;

    return LayoutBuilder(builder: (context, constraints) {
      final double trackW = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : 240.0;
      final double maxOffset = trackW - hPad * 2 - widget.knobSize;
      if (maxOffset <= 0) {
        // 容器太小，退化显示。
        return SizedBox(width: trackW, height: trackH);
      }
      final double knobX = hPad + _knobFrac * maxOffset;

      // 轨道玻璃胶囊（高度可配，56dp 忠实 Kotlin）。
      final Widget track = Stack(
        children: [
          // 底色：trackOff 半透明
          Container(
            width: trackW,
            height: trackH,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(trackH / 2),
              color: palette.sliderTrackOff,
            ),
          ),
          // 已选段：accent
          ClipRRect(
            borderRadius: BorderRadius.circular(trackH / 2),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: ((_knobFrac * trackW) / trackW),
              child: Container(
                width: trackW,
                height: trackH,
                color: accent.withValues(alpha: 0.85),
              ),
            ),
          ),
          // knob
          Positioned(
            left: knobX,
            top: (trackH - widget.knobSize) / 2,
            child: Transform.scale(
              scale: _scale,
              child: Container(
                width: widget.knobSize,
                height: widget.knobSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dark ? const Color(0xFF1C1C1E) : Colors.white,
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
          ),
        ],
      );

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          setState(() => _pressed = true);
          _startTick();
          _updateFromLocal(d.localPosition.dx, maxOffset);
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
          _startTick();
        },
        onTapCancel: () {
          setState(() => _pressed = false);
          _startTick();
        },
        onHorizontalDragStart: (d) {
          _dragging = true;
          setState(() => _pressed = true);
          _startTick();
          _updateFromLocal(d.localPosition.dx, maxOffset);
        },
        onHorizontalDragUpdate: (d) {
          _updateFromLocal(d.localPosition.dx, maxOffset);
          setState(() {});
        },
        onHorizontalDragEnd: (_) {
          _dragging = false;
          setState(() => _pressed = false);
          _startTick();
        },
        onHorizontalDragCancel: () {
          _dragging = false;
          setState(() => _pressed = false);
          _startTick();
        },
        child: GlassSurface(
          visuals: GlassVisuals(blur: widget.blur, radius: trackH / 2),
          child: track,
        ),
      );
    });
  }

  void _updateFromLocal(double dx, double maxOffset) {
    final frac = ((dx - 12) / maxOffset).clamp(0.0, 1.0).toDouble();
    _knobFrac = frac;
    widget.onChanged?.call(frac);
  }
}