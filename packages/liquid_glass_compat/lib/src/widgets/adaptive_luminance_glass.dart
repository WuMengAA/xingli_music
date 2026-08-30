import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/palette.dart';
import '../core/performance.dart';
import 'glass_surface.dart';

/// ───────────────────────────────────────────────────────────────────────
/// AdaptiveLuminanceGlass —— 自适应亮度玻璃
///
/// 移植 self 版 use-adaptive-luminance.ts + AdaptiveLuminanceGlassContent.kt：
/// - 每 200ms 采样玻璃区域背后的背景（走 RepaintBoundary.toImage，
///   缩小到 5×5 网格，24dp inset）的平均亮度（Rec.709 加权）
/// - 亮度的补间动画：每帧向目标靠近 6%（等价 tween(1000) 的缓动）
/// - 用亮度值反推补偿：背景亮 → 玻璃正文变暗，背景暗 → 正文变亮，
///   同时轻微调整 tint 以获得「玻璃反透」观感（忠实 adaptiveContentColor
///   由 brightness 动态驱动的思路）
///
/// 玻璃容器本身仍复用 [GlassSurface]（G2 圆角 + 模糊 + 高光）。
/// ───────────────────────────────────────────────────────────────────────

class AdaptiveLuminanceGlass extends StatefulWidget {
  /// 玻璃内容（通常是文本，其颜色随亮度变化）。
  final Widget Function(Color contentColor) contentBuilder;

  /// 玻璃圆角。
  final double radius;

  /// 模糊半径。
  final double blur;

  /// 采样间隔（性能预设会覆盖此值）。
  final int? sampleIntervalMs;

  /// 性能预设。
  final GlassPerformancePreset? performancePreset;

  const AdaptiveLuminanceGlass({
    super.key,
    required this.contentBuilder,
    this.radius = 34,
    this.blur = 8,
    this.sampleIntervalMs,
    this.performancePreset,
  });

  @override
  State<AdaptiveLuminanceGlass> createState() => _AdaptiveLuminanceGlassState();
}

class _AdaptiveLuminanceGlassState extends State<AdaptiveLuminanceGlass> {
  final GlobalKey _repaintKey = GlobalKey();
  double _target = 0.5;
  double _displayLuminance = 0.5;
  Timer? _sampleTimer;
  bool _sampling = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final perf = settingsFor(widget.performancePreset ?? kDefaultPerformancePreset);
    final intervalMs = widget.sampleIntervalMs ?? perf.adaptiveLuminanceSampleMs;
    _sampleTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _sampleOnce();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _sampleTimer?.cancel();
    super.dispose();
  }

  Future<void> _sampleOnce() async {
    if (_sampling || _disposed) return;
    _sampling = true;
    try {
      final RenderRepaintBoundary? boundary =
          _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage();
      final ByteData? data = await image.toByteData();
      final int w = image.width;
      final int h = image.height;
      image.dispose();
      if (data == null) return;

      // 5×5 网格平均采样（等价 Kotlin toImageBitmap → scale(5,5) 的平均亮度）。
      double sum = 0;
      int count = 0;
      final int gw = w ~/ 5;
      final int gh = h ~/ 5;
      for (var gy = 0; gy < 5; gy++) {
        for (var gx = 0; gx < 5; gx++) {
          final int px = (gx * gw + gw ~/ 2).clamp(0, w - 1);
          final int py = (gy * gh + gh ~/ 2).clamp(0, h - 1);
          final int idx = (py * w + px) * 4;
          if (idx + 3 < data.lengthInBytes) {
            final double r = data.getUint8(idx) / 255;
            final double g = data.getUint8(idx + 1) / 255;
            final double b = data.getUint8(idx + 2) / 255;
            sum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
            count++;
          }
        }
      }
      if (count > 0) {
        final double lum = sum / count;
        final double scaled = ((lum - 0.5) * 1.6 + 0.5).clamp(0.0, 1.0);
        _target = scaled;
        if (mounted) setState(() {});
      }
    } catch (_) {
      // 采样失败静默（WebGL 版同样 try/catch 忽略）。
    } finally {
      _sampling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 补间动画按帧执行（与 rAF 对齐）：每帧向 _target 靠近 6%。
    if (_displayLuminance != _target) {
      final diff = _target - _displayLuminance;
      if (diff.abs() > 0.001) {
        _displayLuminance += diff * 0.06;
      } else {
        _displayLuminance = _target;
      }
    }

    final GlassPalette palette = glassPaletteFor(
        Theme.of(context).brightness == Brightness.dark
            ? GlassThemeMode.dark
            : GlassThemeMode.light);
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    // 亮度 → 内容色：背景暗（lum 低）→ 内容要亮；反之要暗。
    // 基础色由主题决定，随后用亮度差做补偿。
    final Color base = palette.adaptiveContentColor;
    final double compensate = (_displayLuminance - 0.5) * -0.85; // 反相补偿
    final Color contentColor = Color.lerp(
      base,
      dark ? Colors.white : Colors.black,
      (compensate + 0.5).clamp(0.0, 1.0),
    )!;

    // tint：亮度越低，玻璃底色越深（反透）。
    final Color tint = dark
        ? Color.fromRGBO(18, 18, 18, 0.42 + (1 - _displayLuminance) * 0.18)
        : Color.fromRGBO(250, 250, 250, 0.42 + (1 - _displayLuminance) * 0.18);

    return RepaintBoundary(
      key: _repaintKey,
      child: GlassSurface(
        visuals: GlassVisuals(
          blur: widget.blur,
          tint: tint,
          radius: widget.radius,
          highlightColor: contentColor.withValues(alpha: 0.08),
        ),
        child: widget.contentBuilder(contentColor),
      ),
    );
  }
}