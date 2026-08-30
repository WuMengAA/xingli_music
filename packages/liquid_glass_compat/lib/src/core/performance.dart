/// ───────────────────────────────────────────────────────────────────────
/// 性能预设 —— 省电 / 均衡 / 流畅
///
/// 对应 Xingli 应用的「性能模式」概念（PerformanceMode），并映射到
/// liquid-glass-webgl 的渲染开关：模糊半径、降采样、SDF 纹理分辨率、
/// 懒加载滚动容器的启用策略。
/// ───────────────────────────────────────────────────────────────────────
library;

/// 性能预设。
enum GlassPerformancePreset {
  /// 省电：关闭/大幅降低模糊与折射，SDF 用最低分辨率，滚动默认懒加载
  powerSave,

  /// 均衡：中等模糊 + 降采样，SDF 中分辨率（默认）
  balanced,

  /// 流畅：完整模糊半径、SDF 高分辨率，滚动默认非懒加载（全部渲染）
  smooth,
}

/// 一档预设的量化参数。
class GlassPerformanceSettings {
  /// 玻璃背景模糊半径缩放系数（相对设计值）。
  final double blurScale;

  /// 模糊降采样等级（1 = 不降采样，2 = 半分辨率两遍）。
  final int blurDownsample;

  /// 是否启用折射（edge refraction）。
  final bool refractionEnabled;

  /// 是否启用色差。
  final bool chromaticAberrationEnabled;

  /// SDF 纹理解析度上限。
  final int sdfMaxSize;

  /// 滚动容器默认是否懒加载。
  final bool lazyScrollByDefault;

  /// 自适应亮度采样间隔（毫秒）。
  final int adaptiveLuminanceSampleMs;

  /// 是否启用高光（highlight pass）。
  final bool highlightEnabled;

  const GlassPerformanceSettings({
    required this.blurScale,
    required this.blurDownsample,
    required this.refractionEnabled,
    required this.chromaticAberrationEnabled,
    required this.sdfMaxSize,
    required this.lazyScrollByDefault,
    required this.adaptiveLuminanceSampleMs,
    required this.highlightEnabled,
  });
}

/// 各预设的默认参数（对齐 liquid-glass-webgl 的 Settings 默认值）。
const GlassPerformanceSettings kPowerSaveSettings = GlassPerformanceSettings(
  blurScale: 0.25,
  blurDownsample: 4,
  refractionEnabled: false,
  chromaticAberrationEnabled: false,
  sdfMaxSize: 256,
  lazyScrollByDefault: true,
  adaptiveLuminanceSampleMs: 500,
  highlightEnabled: false,
);

const GlassPerformanceSettings kBalancedSettings = GlassPerformanceSettings(
  blurScale: 0.6,
  blurDownsample: 2,
  refractionEnabled: true,
  chromaticAberrationEnabled: true,
  sdfMaxSize: 512,
  lazyScrollByDefault: false,
  adaptiveLuminanceSampleMs: 250,
  highlightEnabled: true,
);

const GlassPerformanceSettings kSmoothSettings = GlassPerformanceSettings(
  blurScale: 1.0,
  blurDownsample: 1,
  refractionEnabled: true,
  chromaticAberrationEnabled: true,
  sdfMaxSize: 1024,
  lazyScrollByDefault: false,
  adaptiveLuminanceSampleMs: 150,
  highlightEnabled: true,
);

GlassPerformanceSettings settingsFor(GlassPerformancePreset preset) {
  switch (preset) {
    case GlassPerformancePreset.powerSave:
      return kPowerSaveSettings;
    case GlassPerformancePreset.balanced:
      return kBalancedSettings;
    case GlassPerformancePreset.smooth:
      return kSmoothSettings;
  }
}

/// 上下文默认值（无显式 preset 时的兜底）。
const GlassPerformancePreset kDefaultPerformancePreset = GlassPerformancePreset.balanced;