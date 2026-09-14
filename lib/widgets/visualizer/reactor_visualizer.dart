/// ════════════════════════════════════════════════════════════════════════
/// 音效反应堆可视化（2026-09-14 播放器主题）
/// ════════════════════════════════════════════════════════════════════════
///
/// 用户主题诉求⑦「唱片 + 音效反应堆」的视觉之一。参考 Steam 创意工坊
/// Wallpaper Engine 主题（React/Three.js/GLSL，160×160 网格柱条随 FFT 脉冲
/// + 流星），但 **Flutter 直接复刻**（Web 技术栈无法嵌入），用 `CustomPaint`
/// 渲染随音乐能量脉冲的柱阵 + 低频涟漪 + 高频流星。
///
/// 数据源复用 [visualizerBandsProvider]（16 段合成能量，非真实 FFT 但随播放
/// 活起来，契合「意境优先」）。颜色跟随当前皮肤 accent（10 色主题在 Wallpaper
/// 端，App 端先用 accent 派生，后续可扩展主题切换）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/audio/visualizer_providers.dart';

/// 音效反应堆：随音乐脉冲的网格柱阵 + 流星。
class ReactorVisualizer extends ConsumerWidget {
  const ReactorVisualizer({super.key, this.opacity = 0.45});

  /// 整体透明度（避免盖过前景文字/歌词）。
  final double opacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<double>> bands = ref.watch(visualizerBandsProvider);
    final AppThemeColors c = context.appColors;
    return RepaintBoundary(
      child: bands.when(
        data: (List<double> vals) => CustomPaint(
          painter: _ReactorPainter(vals, c.accent, opacity),
          isComplex: true,
          willChange: true,
        ),
        // 加载中 / 出错时不再「凭空消失」（此前直接 SizedBox.shrink，与
        // SpectrumBars 的静态占位不一致，主页开场会短暂空窗）：统一渲染
        // 低而平的静态柱阵，保留反应堆存在感。
        loading: () => CustomPaint(
          painter: _ReactorPainter(_kIdleBands, c.accent, opacity * 0.55),
          isComplex: true,
        ),
        error: (_, __) => CustomPaint(
          painter: _ReactorPainter(_kIdleBands, c.accent, opacity * 0.55),
          isComplex: true,
        ),
      ),
    );
  }
}

/// 静默态（未播放 / 加载中 / 出错）的静态柱阵：低而平，保留「反应堆存在感」。
const List<double> _kIdleBands = <double>[
  0.14, 0.22, 0.18, 0.12, 0.16, 0.20, 0.13, 0.10,
  0.10, 0.13, 0.20, 0.16, 0.12, 0.18, 0.22, 0.14,
];

/// 反应堆画笔：对称网格柱阵（从中心向两侧脉冲）+ 低频涟漪 + 高频流星。
class _ReactorPainter extends CustomPainter {
  _ReactorPainter(this.vals, this.accent, this.opacity);

  final List<double> vals;
  final Color accent;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = vals.length; // 16 段
    if (n == 0) return;
    final double gap = math.max(2.0, size.width * 0.012);
    final double colW = (size.width - gap * (n - 1)) / n;
    final double maxH = size.height * 0.55;
    final double centerY = size.height * 0.62; // 柱阵中心（略偏下，上留空间给流星）

    // —— 网格柱阵：从中心行向上下对称脉冲（反应堆"能量场"感）——
    for (int i = 0; i < n; i++) {
      final double v = vals[i].clamp(0.0, 1.0);
      final double h = (3 + v * maxH) / 2; // 半高，对称
      final double x = i * (colW + gap);
      final double alpha = (0.35 + 0.65 * v) * opacity;
      final Paint p = Paint()..color = accent.withValues(alpha: alpha);
      // 上柱
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - h, colW, h),
          Radius.circular(colW * 0.5),
        ),
        p,
      );
      // 下柱（对称镜像）
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY, colW, h),
          Radius.circular(colW * 0.5),
        ),
        p,
      );
    }

    // —— 低频涟漪：低段能量强时，中心地面扩散一圈光晕 ——
    final double low = (vals.first + vals[1]) / 2;
    if (low > 0.25) {
      final Paint ripple = Paint()
        ..color = accent.withValues(alpha: (low - 0.25) * 0.4 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(
        Offset(size.width / 2, centerY),
        size.width * 0.2 + low * size.width * 0.3,
        ripple,
      );
    }

    // —— 高频流星：高段能量强时，随机落点溅射粒子（伪随机固定种子）——
    final double high = (vals[n - 1] + vals[n - 2]) / 2;
    if (high > 0.5) {
      final int sparks = (high * 6).round();
      final Paint spark = Paint()..color = accent.withValues(alpha: 0.6 * opacity);
      for (int s = 0; s < sparks; s++) {
        final double seed = (s * 92821) % 10000 / 10000;
        final double sx = seed * size.width;
        final double sy = (math.sin(seed * 99) * 0.5 + 0.5) * size.height * 0.4;
        canvas.drawCircle(Offset(sx, sy), 1.5 + high * 2, spark);
      }
    }
  }

  @override
  bool shouldRepaint(_ReactorPainter old) => old.vals != vals;
}
