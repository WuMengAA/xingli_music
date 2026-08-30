import 'dart:ui' show ColorSpace;

import 'package:flutter/painting.dart';

/// ───────────────────────────────────────────────────────────────────────
/// 调色板 —— 忠实移植 liquid-glass-webgl `palettes.ts`（亮/暗双主题）
///
/// 每个值都是直接来自 Kotlin 源码（LiquidToggle.kt、LiquidSlider.kt、
/// LiquidBottomTabs.kt、DialogContent.kt、ControlCenterContent.kt 等）的
/// 每主题颜色，代码注释保留对应关系。
/// ───────────────────────────────────────────────────────────────────────

/// 颜色 [r,g,b] ∈ [0,1] 数值组 → Flutter Color。
Color color3(List<double> rgb, {double alpha = 1.0}) => Color.from(
    alpha: alpha,
    red: rgb[0],
    green: rgb[1],
    blue: rgb[2],
    colorSpace: ColorSpace.sRGB);

/// 颜色 [r,g,b,a] ∈ [0,1] 数值组 → Flutter Color。
Color color4(List<double> rgba) => Color.from(
    alpha: rgba[3],
    red: rgba[0],
    green: rgba[1],
    blue: rgba[2],
    colorSpace: ColorSpace.sRGB);

/// 单主题调色板。
class GlassPalette {
  // HomeContent.kt
  final Color homeContentColor;
  final Color homeSubtitleColor;

  // ToggleContent.kt + LiquidToggle.kt
  final Color toggleAccent;
  final Color toggleTrackOff;
  final Color toggleCardBg;

  // SliderContent.kt + LiquidSlider.kt
  final Color sliderAccent;
  final Color sliderTrackOff;
  final Color sliderCardBg;

  // BottomTabsContent.kt + LiquidBottomTabs.kt
  final Color tabsContentColor;
  final Color tabsAccent;
  final Color tabsContainer;
  final Color tabsTextHalo;

  // DialogContent.kt
  final Color dialogContentColor;
  final Color dialogAccent;
  final Color dialogContainer;
  final Color dialogDim;
  final double dialogBlurRadius;
  final double dialogBrightness;

  // ControlCenterContent.kt
  final Color controlCenterAccent;

  // ProgressiveBlurContent.kt
  final Color progressiveContentColor;
  final Color progressiveTint;
  final double progressiveTintIntensity;

  // AdaptiveLuminanceGlassContent.kt（初始；真实亮度自适应）
  final Color adaptiveContentColor;

  // 返回按钮 / 主题按钮玻璃表面 —— 镜像 tabsContainer
  final Color buttonSurface;

  const GlassPalette({
    required this.homeContentColor,
    required this.homeSubtitleColor,
    required this.toggleAccent,
    required this.toggleTrackOff,
    required this.toggleCardBg,
    required this.sliderAccent,
    required this.sliderTrackOff,
    required this.sliderCardBg,
    required this.tabsContentColor,
    required this.tabsAccent,
    required this.tabsContainer,
    required this.tabsTextHalo,
    required this.dialogContentColor,
    required this.dialogAccent,
    required this.dialogContainer,
    required this.dialogDim,
    required this.dialogBlurRadius,
    required this.dialogBrightness,
    required this.controlCenterAccent,
    required this.progressiveContentColor,
    required this.progressiveTint,
    required this.progressiveTintIntensity,
    required this.adaptiveContentColor,
    required this.buttonSurface,
  });
}

/// 亮色主题（忠实 LIGHT_PALETTE）。
const Color kLightToggleAccent = Color.from(alpha: 1, red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, colorSpace: ColorSpace.sRGB);
const Color kLightSliderAccent = Color.from(alpha: 1, red: 0x00 / 255, green: 0x88 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB);
const Color kLightTabsAccent = Color.from(alpha: 1, red: 0x00 / 255, green: 0x88 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB);
const Color kLightTabsContainer = Color.from(alpha: 0.4, red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, colorSpace: ColorSpace.sRGB);
const Color kLightTrackOff = Color.from(alpha: 0.2, red: 0x78 / 255, green: 0x78 / 255, blue: 0x78 / 255, colorSpace: ColorSpace.sRGB);
const Color kLightCardBg = Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB);
const Color kLightDialogContainer = Color.from(alpha: 0.6, red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, colorSpace: ColorSpace.sRGB);
const Color kLightDialogDim = Color.from(alpha: 0.23, red: 0x29 / 255, green: 0x29 / 255, blue: 0x3A / 255, colorSpace: ColorSpace.sRGB);
const Color kLightTint = Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB);
const Color kLightButtonSurface = Color.from(alpha: 0.3, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB);

/// 暗色主题（忠实 DARK_PALETTE）。
const Color kDarkToggleAccent = Color.from(alpha: 1, red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkSliderAccent = Color.from(alpha: 1, red: 0x00 / 255, green: 0x91 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkTabsAccent = Color.from(alpha: 1, red: 0x00 / 255, green: 0x91 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkTabsContainer = Color.from(alpha: 0.4, red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkTrackOff = Color.from(alpha: 0.36, red: 0x78 / 255, green: 0x78 / 255, blue: 0x80 / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkCardBg = Color.from(alpha: 1, red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkDialogContainer = Color.from(alpha: 0.4, red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkDialogDim = Color.from(alpha: 0.56, red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkTint = Color.from(alpha: 1, red: 0x80 / 255, green: 0x80 / 255, blue: 0x80 / 255, colorSpace: ColorSpace.sRGB);
const Color kDarkButtonSurface = Color.from(alpha: 0.4, red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, colorSpace: ColorSpace.sRGB);

/// 混合色（lib Color.lerp 已内置，这里做不依赖 Theme 的便捷版）。
Color lerpColor(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

/// 主题派发。
enum GlassThemeMode { light, dark }

GlassPalette glassPaletteFor(GlassThemeMode mode) =>
    mode == GlassThemeMode.light ? lightGlassPalette : darkGlassPalette;

const GlassPalette lightGlassPalette = GlassPalette(
  homeContentColor: Color.from(alpha: 1, red: 0, green: 0, blue: 0, colorSpace: ColorSpace.sRGB),
  homeSubtitleColor: Color.from(alpha: 1, red: 0x00 / 255, green: 0x88 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB),
  toggleAccent: kLightToggleAccent,
  toggleTrackOff: kLightTrackOff,
  toggleCardBg: kLightCardBg,
  sliderAccent: kLightSliderAccent,
  sliderTrackOff: kLightTrackOff,
  sliderCardBg: kLightCardBg,
  tabsContentColor: Color.from(alpha: 1, red: 0, green: 0, blue: 0, colorSpace: ColorSpace.sRGB),
  tabsAccent: kLightTabsAccent,
  tabsContainer: kLightTabsContainer,
  tabsTextHalo: Color.from(alpha: 1, red: 0, green: 0, blue: 0, colorSpace: ColorSpace.sRGB),
  dialogContentColor: Color.from(alpha: 1, red: 0, green: 0, blue: 0, colorSpace: ColorSpace.sRGB),
  dialogAccent: Color.from(alpha: 1, red: 0x00 / 255, green: 0x88 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB),
  dialogContainer: kLightDialogContainer,
  dialogDim: kLightDialogDim,
  dialogBlurRadius: 16,
  dialogBrightness: 0.2,
  controlCenterAccent: Color.from(alpha: 1, red: 0x00 / 255, green: 0x88 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB),
  progressiveContentColor: Color.from(alpha: 1, red: 0, green: 0, blue: 0, colorSpace: ColorSpace.sRGB),
  progressiveTint: kLightTint,
  progressiveTintIntensity: 0.8,
  adaptiveContentColor: Color.from(alpha: 1, red: 0, green: 0, blue: 0, colorSpace: ColorSpace.sRGB),
  buttonSurface: kLightButtonSurface,
);

const GlassPalette darkGlassPalette = GlassPalette(
  homeContentColor: Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB),
  homeSubtitleColor: Color.from(alpha: 1, red: 0x00 / 255, green: 0x88 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB),
  toggleAccent: kDarkToggleAccent,
  toggleTrackOff: kDarkTrackOff,
  toggleCardBg: kDarkCardBg,
  sliderAccent: kDarkSliderAccent,
  sliderTrackOff: kDarkTrackOff,
  sliderCardBg: kDarkCardBg,
  tabsContentColor: Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB),
  tabsAccent: kDarkTabsAccent,
  tabsContainer: kDarkTabsContainer,
  tabsTextHalo: Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB),
  dialogContentColor: Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB),
  dialogAccent: Color.from(alpha: 1, red: 0x00 / 255, green: 0x91 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB),
  dialogContainer: kDarkDialogContainer,
  dialogDim: kDarkDialogDim,
  dialogBlurRadius: 8,
  dialogBrightness: 0,
  controlCenterAccent: Color.from(alpha: 1, red: 0x00 / 255, green: 0x91 / 255, blue: 0xFF / 255, colorSpace: ColorSpace.sRGB),
  progressiveContentColor: Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB),
  progressiveTint: kDarkTint,
  progressiveTintIntensity: 0.8,
  adaptiveContentColor: Color.from(alpha: 1, red: 1, green: 1, blue: 1, colorSpace: ColorSpace.sRGB),
  buttonSurface: kDarkButtonSurface,
);