import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/palette.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassProgressiveBlur —— 渐进模糊带
///
/// 忠实移植 liquid-glass-webgl `build-progressive-blur.ts` +
/// ProgressiveBlurContent.kt：
/// - 一条全宽 128dp 高的模糊带，背景模糊强度沿纵向从「无」渐变到
///   「满」（alpha-masked progressive blur）
/// - tint：亮主题白色 0.8，暗主题 #808080 0.8（tintIntensity = 0.8）
/// - 文字用 progressiveContentColor（亮黑 / 暗白），可选 halo（文字阴影）
///
/// Flutter 实现：把模糊带切成 N 层，每层 BackdropFilter 的 sigma 沿
/// 纵向线性递增，遮罩逐层裁剪 —— 等价于 WebGL 的多次模糊 + alpha mask。
/// [bands] 越多，渐变越平滑（性能与质量折中；默认 6，性能档 3）。
/// ───────────────────────────────────────────────────────────────────────

/// 渐进模糊带。
class GlassProgressiveBlur extends StatelessWidget {
  /// 宽度（默认撑满父容器）。
  final double? width;

  /// 高度（忠实 128dp）。
  final double height;

  /// 最大模糊半径（带底部的模糊强度）。
  final double maxBlur;

  /// 渐变分段数。
  final int bands;

  /// 是否把文字叠在带上。
  final String? label;

  /// label 样式覆盖。
  final TextStyle? labelStyle;

  /// tint 覆盖（null → 主题 progressiveTint × tintIntensity）。
  final Color? tint;

  /// tint 强度（忠实 0.8）。
  final double tintIntensity;

  const GlassProgressiveBlur({
    super.key,
    this.width,
    this.height = 128,
    this.maxBlur = 12,
    this.bands = 6,
    this.label,
    this.labelStyle,
    this.tint,
    this.tintIntensity = 0.8,
  });

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = glassPaletteFor(
        Theme.of(context).brightness == Brightness.dark
            ? GlassThemeMode.dark
            : GlassThemeMode.light);
    final Color resolvedTint =
        (tint ?? palette.progressiveTint).withValues(alpha: tintIntensity);
    final Color contentColor = palette.progressiveContentColor;

    // 各带的 blur sigma：0 → maxBlur 线性递增。
    // 每层只占 bandH 高度（Positioned 精确分层），
    // 叠起来等价 WebGL 的多次模糊 + alpha mask。
    final List<Widget> bandsWidgets = [];
    final double bandH = (height / bands).clamp(1.0, height);
    for (var i = 0; i < bands; i++) {
      final double sigma = maxBlur * (i + 0.5) / bands;
      bandsWidgets.add(
        Positioned(
          top: i * bandH,
          height: bandH,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
      );
    }

    Widget band = Stack(
      children: [
        ...bandsWidgets,
        // tint 叠层。
        Positioned.fill(child: Container(color: resolvedTint)),
      ],
    );

    if (label != null) {
      band = Stack(
        fit: StackFit.passthrough,
        children: [
          band,
          Positioned.fill(
            child: Center(
              child: Text(
                label!,
                textAlign: TextAlign.center,
                style: (labelStyle ?? const TextStyle(fontSize: 16))
                    .copyWith(
                        color: contentColor,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: band,
    );
  }
}