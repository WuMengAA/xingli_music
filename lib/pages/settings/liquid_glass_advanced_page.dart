/// ════════════════════════════════════════════════════════════════════════
/// 液态玻璃 · 高级调节（premium 真折射参数微调）
/// ════════════════════════════════════════════════════════════════════════
///
/// 与标准模式严格分离：标准档（[GlassStyle.frosted] / standard）零改动；
/// 本页只调 premium 真折射路径（[GlassStyle.liquid]，即播放控制栏等玻璃
/// 焦点）的参数。所有滑杆默认跟随 [LiquidGlass] 构造默认值，仅在用户显式
/// 改动后生效；「恢复默认」一键清空回 null（回到标准完美状态）。
///
/// 挂载在 设置→关于→开发者工具（与性能基准页并列）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/liquid_glass_advanced_providers.dart';

/// 液态玻璃高级调节页。
class LiquidGlassAdvancedPage extends ConsumerWidget {
  const LiquidGlassAdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.appColors.bgSurfaceSunken,
      appBar: AppBar(
        backgroundColor: context.appColors.bgSurface,
        foregroundColor: context.appColors.textPrimary,
        title: Text('液态玻璃 · 高级调节', style: context.appText.subtitle),
        elevation: 0,
        actions: <Widget>[
          TextButton(
            onPressed: () => resetLiquidGlassAdvanced(ref),
            child: const Text('恢复默认'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          const SizedBox(height: AppSpace.lg),

          // ═══ 实时预览 ═══
          _Card(
            title: '实时预览（premium 真折射）',
            child: SizedBox(
              height: 150,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            context.appColors.accent.withValues(alpha: 0.55),
                            context.appColors.accent
                                .withValues(alpha: 0.25),
                            context.appColors.bgPage,
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Text(
                          'STELARITH',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: AdaptiveGlass(
                        shape: LiquidRoundedSuperellipse(
                          borderRadius: 22,
                        ),
                        quality: GlassQuality.premium,
                        settings: _advancedSettings(ref),
                        child: const Center(
                          child: Text(
                            'GLASS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),

          _Card(
            title: '折射与色散',
            child: Column(
              children: <Widget>[
                _SliderRow(
                  label: '折射强度',
                  value: ref.watch(liquidRefractionProvider) ?? 8,
                  min: 0,
                  max: 20,
                  display: (v) => v.toStringAsFixed(0),
                  onChanged: (v) => ref
                      .read(liquidRefractionProvider.notifier)
                      .state = v,
                ),
                _SliderRow(
                  label: '色散强度',
                  value: ref.watch(liquidDispersionProvider) ?? 1.6,
                  min: 0,
                  max: 4,
                  display: (v) => v.toStringAsFixed(1),
                  onChanged: (v) => ref
                      .read(liquidDispersionProvider.notifier)
                      .state = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          _Card(
            title: '材质',
            child: Column(
              children: <Widget>[
                _SliderRow(
                  label: '厚度',
                  value: ref.watch(liquidThicknessProvider) ?? 34,
                  min: 14,
                  max: 48,
                  display: (v) => v.toStringAsFixed(0),
                  onChanged: (v) =>
                      ref.read(liquidThicknessProvider.notifier).state = v,
                ),
                _SliderRow(
                  label: '色差（彩虹边）',
                  value: ref.watch(liquidChromaticAberrationProvider) ??
                      0.096,
                  min: 0,
                  max: 0.3,
                  display: (v) => v.toStringAsFixed(3),
                  onChanged: (v) => ref
                      .read(liquidChromaticAberrationProvider.notifier)
                      .state = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),

          _Card(
            title: '光照',
            child: Column(
              children: <Widget>[
                _SliderRow(
                  label: '辉光',
                  value: ref.watch(liquidGlowProvider) ?? 0.7,
                  min: 0,
                  max: 1,
                  display: (v) => v.toStringAsFixed(2),
                  onChanged: (v) =>
                      ref.read(liquidGlowProvider.notifier).state = v,
                ),
                _SliderRow(
                  label: 'Fresnel 边缘',
                  value: ref.watch(liquidFresnelProvider) ?? 1.2,
                  min: 0,
                  max: 2,
                  display: (v) => v.toStringAsFixed(1),
                  onChanged: (v) =>
                      ref.read(liquidFresnelProvider.notifier).state = v,
                ),
                _SliderRow(
                  label: '环境光边',
                  value: ref.watch(liquidAmbientRimProvider) ?? 0.2,
                  min: 0,
                  max: 0.5,
                  display: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => ref
                      .read(liquidAmbientRimProvider.notifier)
                      .state = v,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            '提示：以上仅影响「液态玻璃（折射）」启用处的 premium 真折射'
            '（播放控制栏等玻璃焦点）；标准模式毛玻璃不受影响。',
            style: context.appText.caption.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 组装当前高级参数（未覆盖处用 liquid_glass.dart 的 premium 默认）。
  LiquidGlassSettings _advancedSettings(WidgetRef ref) {
    return LiquidGlassSettings(
      blur: 18,
      glassColor: Colors.white.withValues(alpha: 0.10),
      thickness: ref.watch(liquidThicknessProvider) ?? 34,
      refractiveIndex: (1 + ((ref.watch(liquidRefractionProvider) ?? 8) /
              100) *
          2.5).clamp(1.0, 1.6),
      chromaticAberration:
          ref.watch(liquidChromaticAberrationProvider) ?? 0.096,
      saturation: 1.4,
      glowIntensity: ref.watch(liquidGlowProvider) ?? 0.7,
      fresnelStrength: ref.watch(liquidFresnelProvider) ?? 1.2,
      ambientRim: ref.watch(liquidAmbientRimProvider) ?? 0.2,
      shadowElevation: 1.0,
      whitenStrength: 0.0,
      edgeAbsorption: 0.0,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.appColors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: context.appText.subtitle),
          const SizedBox(height: AppSpace.xs),
          child,
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(label, style: context.appText.body),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            display(value),
            textAlign: TextAlign.end,
            style: context.appText.caption.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
