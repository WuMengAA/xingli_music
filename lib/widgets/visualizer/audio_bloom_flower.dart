/// ════════════════════════════════════════════════════════════════════════
/// 音频反应花（2026-09-15 播放器主题）
/// ════════════════════════════════════════════════════════════════════════
///
/// 主页沉浸式播放器的「花漾中心件」——与 [ReactorVisualizer]（频谱网格）并列的
/// 第二视觉主题。数据同源复用 [visualizerBandsProvider]（16 段合成能量）与
/// [visualizerLevelProvider]（0~1 能量包络），用 `CustomPaint` 渲染一朵从中心
/// 放射的音频反应花：花瓣长度随音域（频谱）生长，整体随能量包络轻轻脉冲。
///
/// 颜色跟随当前皮肤 accent，整体透明度偏低（默认 0.22），保证不盖过前景文字 /
/// 歌词与唱片封面。加载中 / 出错时渲染静态柔光花，始终保留中心装饰存在感。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/audio/visualizer_providers.dart';

/// 静默态（未播放 / 加载中 / 出错）的静态花瓣能量：低而柔，保留「花存在感」。
const List<double> _kIdleBands = <double>[
  0.16, 0.22, 0.18, 0.14, 0.20,
  0.16, 0.22, 0.18, 0.14, 0.20,
];

/// 音频反应花：随音乐脉冲生长的放射状花瓣中心件。
class AudioBloomFlower extends ConsumerWidget {
  const AudioBloomFlower({super.key, this.opacity = 0.22});

  /// 整体透明度（避免盖过前景文字 / 歌词 / 唱片）。
  final double opacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<double> levelAsync = ref.watch(visualizerLevelProvider);
    final AsyncValue<List<double>> bandsAsync =
        ref.watch(visualizerBandsProvider);
    final AppThemeColors c = context.appColors;

    // 解析为具体值；加载中 / 出错时回落到静态柔光花，保证花始终在场。
    final List<double> bands = bandsAsync.when(
      data: (List<double> v) => v,
      loading: () => _kIdleBands,
      error: (_, __) => _kIdleBands,
    );
    final double level = levelAsync.when(
      data: (double v) => v,
      loading: () => 0.0,
      error: (_, __) => 0.0,
    );

    return RepaintBoundary(
      child: CustomPaint(
        painter: _FlowerPainter(bands, level, c.accent, opacity),
        isComplex: true,
        willChange: true,
      ),
    );
  }
}

/// 花瓣画笔：居中的放射状花朵（花瓣随音域生长 + 随能量脉冲），含柔光花心。
class _FlowerPainter extends CustomPainter {
  _FlowerPainter(this.bands, this.level, this.accent, this.opacity);

  final List<double> bands;
  final double level;
  final Color accent;
  final double opacity;

  /// 花瓣数量（清晰读作一朵花，而非柱状条）。
  static const int _petals = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double minSide = math.min(size.width, size.height);

    // 整体随能量包络轻轻脉冲（0.9 ~ 1.15 倍）。
    final double scale = 0.9 + level.clamp(0.0, 1.0) * 0.25;
    final double baseLen = minSide * 0.16 * scale; // 花瓣静长
    final double amp = minSide * 0.20 * scale; // 音域响应幅度

    // —— 柔光花心：低透明度径向晕，托住整朵花 ——
    final Paint glow = Paint()
      ..color = accent.withValues(alpha: opacity * 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, minSide * 0.05);
    canvas.drawCircle(Offset(cx, cy), baseLen * 0.65, glow);

    // —— 花瓣：从中心向外的叶形（贝塞尔）放射 ——
    for (int i = 0; i < _petals; i++) {
      final double angle = (math.pi * 2 * i / _petals) - math.pi / 2;
      final double v =
          bands.isNotEmpty ? bands[i % bands.length].clamp(0.0, 1.0) : 0.0;
      final double len = baseLen + v * amp;
      final double alpha = opacity * (0.4 + 0.6 * v);
      final Paint p = Paint()
        ..color = accent.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      // 叶形花瓣：从花心 (0,0) 经两侧控制点弯向瓣尖 (0, len)。
      final Path petal = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(baseLen * 0.5, len * 0.4, 0, len)
        ..quadraticBezierTo(-baseLen * 0.5, len * 0.4, 0, 0);
      canvas.drawPath(petal, p);
      canvas.restore();
    }

    // —— 花心点缀：随能量的小实心核，强化「中心件」存在感 ——
    final double core = baseLen * (0.28 + 0.12 * level.clamp(0.0, 1.0));
    final Paint corePaint = Paint()
      ..color = accent.withValues(alpha: opacity * 0.8);
    canvas.drawCircle(Offset(cx, cy), core, corePaint);
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.bands != bands || old.level != level || old.opacity != opacity;
}
