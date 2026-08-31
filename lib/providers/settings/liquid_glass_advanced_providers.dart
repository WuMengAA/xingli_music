/// ════════════════════════════════════════════════════════════════════════
/// 液态玻璃 · 高级调节（premium 真折射参数）
/// ════════════════════════════════════════════════════════════════════════
///
/// 与「标准模式」严格分离：
///   - **标准模式**（[GlassStyle.frosted] + [GlassQuality.standard]）保持
///     现状零改动——用户认为"标准模式下液态玻璃刚刚好完美"；
///   - **高级调节**仅影响显式使用 [GlassStyle.liquid]（premium 真折射路径，
///     即播放控制栏等玻璃焦点）的参数，通过本组 provider 覆盖默认值。
///
/// 所有 provider 默认 `null` = 跟随 [LiquidGlass] 构造默认参数，因此
/// 不开「高级调节」时标准路径与现状完全一致、零污染。用户只在独立的高级
/// 调节页（设置→…→液态玻璃高级调节）显式改动后，参数才覆盖 premium 档。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 折射强度覆盖（0~20，映射 refractiveIndex）；null = 跟随默认。
final liquidRefractionProvider = StateProvider<double?>((ref) => null);

/// 色散强度覆盖（0~4，映射 chromaticAberration）；null = 跟随默认。
final liquidDispersionProvider = StateProvider<double?>((ref) => null);

/// 玻璃厚度（premium 折射体厚度，约 14~48）；null = 跟随默认 34。
final liquidThicknessProvider = StateProvider<double?>((ref) => null);

/// 色差强度（premium 彩虹边缘，0~0.3）；null = 跟随默认。
final liquidChromaticAberrationProvider =
    StateProvider<double?>((ref) => null);

/// 辉光强度（0~1）；null = 跟随默认 0.7。
final liquidGlowProvider = StateProvider<double?>((ref) => null);

/// Fresnel 边缘强度（0~2）；null = 跟随默认 1.2。
final liquidFresnelProvider = StateProvider<double?>((ref) => null);

/// 环境光边缘强度（0~0.5）；null = 跟随默认 0.2。
final liquidAmbientRimProvider = StateProvider<double?>((ref) => null);

/// 一键恢复默认（全部清回 null）。
void resetLiquidGlassAdvanced(WidgetRef ref) {
  ref.read(liquidRefractionProvider.notifier).state = null;
  ref.read(liquidDispersionProvider.notifier).state = null;
  ref.read(liquidThicknessProvider.notifier).state = null;
  ref.read(liquidChromaticAberrationProvider.notifier).state = null;
  ref.read(liquidGlowProvider.notifier).state = null;
  ref.read(liquidFresnelProvider.notifier).state = null;
  ref.read(liquidAmbientRimProvider.notifier).state = null;
}

/// 是否有任一高级参数被显式覆盖（高级调节已启用）。
bool isLiquidGlassAdvancedEnabled(WidgetRef ref) {
  return ref.read(liquidRefractionProvider) != null ||
      ref.read(liquidDispersionProvider) != null ||
      ref.read(liquidThicknessProvider) != null ||
      ref.read(liquidChromaticAberrationProvider) != null ||
      ref.read(liquidGlowProvider) != null ||
      ref.read(liquidFresnelProvider) != null ||
      ref.read(liquidAmbientRimProvider) != null;
}
