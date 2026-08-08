import 'package:flutter/material.dart';

/// 星璃 · 视觉规则集
///
/// 所有颜色、尺寸、动画参数集中在这里。
/// 改一个值全局生效；场景可通过 [SceneVisual] 覆盖部分参数。
///
/// 设计原则：
/// - 颜色用「关系」而非固定色值：背景由情绪权重 + 场景基础色混合生成
/// - 布局用「视觉权重」驱动：调一个权重，卡片尺寸与间距整体变化
/// - 动画用「感觉」描述：曲线与时长按手感自由调整
abstract final class DesignTokens {
  // ══════════════ 一、颜色关系 ══════════════

  /// 强调色：只出现在按钮、选中、滑动指示
  static const Color accent = Color(0xFF9B7BFF);

  /// 高亮色：只在「当前播放 / 当前选中」状态出现
  static const Color highlight = Color(0xFFF5D98F);

  /// 情绪 → 混色：当前情绪权重（0..1）决定与场景基础色的混合比例
  static const Map<String, Color> moodColors = {
    'calm': Color(0xFF4A3B8C), // 平静 → 偏紫
    'warm': Color(0xFF7A5BBF), // 温暖 → 偏粉紫
    'bright': Color(0xFF2B2D6B), // 明亮 → 偏蓝
    'dim': Color(0xFF1A103C), // 沉静 → 偏深紫
  };

  /// 情绪混合强度上限（避免过度染色）
  static const double moodBlendMax = 0.5;

  // ══════════════ 二、布局逻辑 ══════════════

  /// 卡片宽度 = 屏幕宽 × (minRatio ~ maxRatio)，由视觉权重在区间内插值
  static const double cardWidthMinRatio = 0.65;
  static const double cardWidthMaxRatio = 0.80;

  /// 卡片高度不超过屏幕高度的 50%
  static const double cardMaxHeightRatio = 0.50;

  /// 统一圆角体系（场景可微调）
  static const double radiusUnit = 18;

  /// 基础间距（视觉呼吸感）
  static const double spacingUnit = 12;

  // ══════════════ 三、动画感觉 ══════════════

  /// 场景切换：有弹性，但不弹跳过度
  static const Duration sceneSwitch = Duration(milliseconds: 600);
  static const Curve switchCurve = Curves.easeOutCubic;

  /// 颜色变化：场景切换时 1.8s 平滑过渡
  static const Duration colorBlend = Duration(milliseconds: 1800);

  /// 反馈：轻微、不过度
  static const Duration feedback = Duration(milliseconds: 150);

  // ══════════════ 颜色计算工具 ══════════════

  /// 有记忆的渐变色：把一组颜色整体做色相偏移（度）
  ///
  /// 偏移方向由使用行为记忆决定，偏移量含会话抖动，
  /// 因此永远不会两次看到完全相同的配色。
  static List<Color> shiftHue(List<Color> colors, double degrees) {
    if (degrees.abs() < 0.5) return colors;
    return colors.map((c) {
      final HSLColor hsl = HSLColor.fromColor(c);
      return hsl
          .withHue((hsl.hue + degrees) % 360.0)
          .toColor();
    }).toList();
  }

  /// 背景色 = 场景基础色与情绪色按权重混合
  static List<Color> blendGradient(
    List<Color> sceneColors,
    Color moodColor,
    double moodWeight,
  ) {
    final double t = moodWeight.clamp(0.0, 1.0) * moodBlendMax;
    return sceneColors
        .map((c) => Color.lerp(c, moodColor, t) ?? c)
        .toList();
  }

  /// 卡片底色 = 背景色 + 亮度偏移 + 透明度偏移（同色系分层）
  static Color cardSurface(Color background) =>
      Color.lerp(background, Colors.white, 0.06)!.withValues(alpha: 0.92);

  /// 卡片文字色：与背景形成足够对比，不依赖固定值
  static Color onSurface(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? Colors.white
          : const Color(0xFF1A103C);
}
