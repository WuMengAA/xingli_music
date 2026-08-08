import 'package:flutter/material.dart';

/// 由用户主色全自动派生出的完整配色
///
/// 规则见 V1.0 规范 1.4：
///  - 背景：主色压暗至亮度 < 15%
///  - 卡片底色：饱和度 30%、亮度 25%、透明度 0.12
///  - 卡片边框：白色 0.06
///  - 粒子色：亮度 70%、饱和度 80%、透明度 0.15~0.35
///  - 强调色：色相 +30°（邻近色）
///  - 高亮色：色相 -20°、亮度 85%
///  - 文字色：#F8F4ED（固定）
class DerivedPalette {
  final Color primary;
  final Color background;
  final Color card;
  final Color particle;
  final Color accent;
  final Color highlight;
  static const Color text = Color(0xFFF8F4ED);

  const DerivedPalette({
    required this.primary,
    required this.background,
    required this.card,
    required this.particle,
    required this.accent,
    required this.highlight,
  });

  /// 从主色派生全部角色
  factory DerivedPalette.from(Color primary) {
    final HSLColor hsl = HSLColor.fromColor(primary);

    // 背景：压暗到亮度 < 15%
    final Color background =
        hsl.withLightness(hsl.lightness * 0.12).toColor();

    // 卡片底色：饱和度 30%、亮度 25%
    final Color card = hsl
        .withSaturation(0.30)
        .withLightness(0.25)
        .toColor();

    // 粒子色：亮度 70%、饱和度 80%
    final Color particle = hsl
        .withSaturation(0.80)
        .withLightness(0.70)
        .toColor();

    // 强调色：色相 +30°
    final Color accent = hsl
        .withHue((hsl.hue + 30.0) % 360.0)
        .withSaturation(0.65)
        .withLightness(0.55)
        .toColor();

    // 高亮色：色相 -20°、亮度 85%
    final Color highlight = hsl
        .withHue((hsl.hue - 20.0 + 360.0) % 360.0)
        .withSaturation(0.70)
        .withLightness(0.85)
        .toColor();

    return DerivedPalette(
      primary: primary,
      background: background,
      card: card,
      particle: particle,
      accent: accent,
      highlight: highlight,
    );
  }

  /// 心情叠加（V1.0 1.5）：不超过 ±15° 的细微表达
  DerivedPalette withMood(String moodKind) {
    if (moodKind == 'calm' || moodKind.isEmpty) return this;

    final HSLColor h = HSLColor.fromColor(primary);
    switch (moodKind) {
      case 'warm': // 愉悦：色相 +10°
        return DerivedPalette.from(
          h.withHue((h.hue + 10.0) % 360.0).toColor(),
        );
      case 'dim': // 低落：饱和度 -15%
        return DerivedPalette.from(
          h.withSaturation((h.saturation - 0.15).clamp(0.0, 1.0)).toColor(),
        );
      case 'bright': // 兴奋：亮度 +10%
        return DerivedPalette.from(
          h.withLightness((h.lightness + 0.10).clamp(0.0, 1.0)).toColor(),
        );
      default:
        return this;
    }
  }
}

/// 6 组预设主色（V1.0 1.2）
class PalettePreset {
  final String name;
  final Color color;
  const PalettePreset(this.name, this.color);
}

const List<PalettePreset> palettePresets = [
  PalettePreset('星夜', Color(0xFF4A3A8A)), // 冷紫，深邃
  PalettePreset('暮色', Color(0xFFC0764A)), // 暖橙，沉静
  PalettePreset('雨雾', Color(0xFF6A7A8A)), // 灰蓝，清冷
  PalettePreset('森林', Color(0xFF3A6A4A)), // 深绿，静谧
  PalettePreset('壁炉', Color(0xFF8A3A2A)), // 暗红，温暖
  PalettePreset('极光', Color(0xFF2A8A7A)), // 青绿，通透
];
