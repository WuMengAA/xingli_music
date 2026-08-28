/// ════════════════════════════════════════════════════════════════════════
/// 顶部 / 底部磨砂边条（批3 #580 · A）
/// ════════════════════════════════════════════════════════════════════════
///
/// 浮于内容区上缘（顶部状态栏下方）与下缘（Dock 上方）的磨砂条边：
///   - 不透明度跟随 [pageScrollBlurProvider] —— 随活动页滚动淡入/淡出
///     （「滑动模糊过渡」），停在页面顶/底部时条边自然消失、视图干净；
///   - 外缘用渐变遮罩羽化（[ShaderMask]），内容滑入/滑出边缘被磨砂柔化，
///     避免硬切边（「上下方模糊」）；
///   - tint / 模糊强度跟随主题语义色与全局性能模式（省电跳过模糊，仅留极淡描边）。
///
/// 调用方负责用 `Positioned` 把它钉在内容区上/下缘（见 [AppShell]）。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/settings/performance_providers.dart';
import 'scroll_blur.dart';

/// 顶部 / 底部磨砂边条。
class FrostEdgeBar extends ConsumerWidget {
  const FrostEdgeBar({
    super.key,
    required this.top,
  });

  /// `true` = 顶部边（外缘在上，羽化朝向状态栏）；
  /// `false` = 底部边（外缘在下，羽化朝向 Dock）。
  final bool top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double progress = ref.watch(pageScrollBlurProvider);
    // 停在页面顶/底部（progress≈0）时不渲染，保持视图干净。
    if (progress <= 0.001) return const SizedBox.shrink();

    final PerformanceMode perf = ref.watch(performanceModeProvider);
    final double blur = ref.watch(glassBlurProvider);
    final bool blurOn = perf != PerformanceMode.performance && blur > 0;
    final AppThemeColors c = context.appColors;

    // 毛玻璃底：模糊 + 玻璃语义 tint（跟随皮肤主色派生）。
    final Widget base = Container(color: c.glassTint);
    final Widget blurred = blurOn
        ? ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: base,
            ),
          )
        : base;

    // 外缘羽化：顶部条边「上缘透明 → 下缘实」；底部条边「下缘透明 → 上缘实」。
    final Widget feathered = ShaderMask(
      shaderCallback: (Rect rect) {
        final Alignment begin =
            top ? Alignment.topCenter : Alignment.bottomCenter;
        final Alignment end =
            top ? Alignment.bottomCenter : Alignment.topCenter;
        return LinearGradient(
          begin: begin,
          end: end,
          colors: const <Color>[
            Color(0x00000000),
            Color(0xFF000000),
          ],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: blurred,
    );

    // 随滚动淡入/淡出（滑动模糊过渡）。
    return Opacity(
      opacity: progress,
      child: IgnorePointer(child: feathered),
    );
  }
}

/// 常驻 Dock 顶部羽化模糊带（批3 #580 · B）。
///
/// 与 [FrostEdgeBar] 不同：它**不依赖滚动**，始终以极淡强度浮于 Dock 正上方，
/// 让内容滑入 Dock 区域时自然羽化（「上下方模糊」的「下」侧），Dock 与内容
/// 之间无硬边。性能模式（[PerformanceMode.performance]）/ 模糊强度为 0 时退化为
/// 仅渐变描边、跳过 [BackdropFilter]，零额外开销。
///
/// 调用方用 `Positioned` 钉在 Dock 上方（见 [AppShell]）。
class DockTopFeather extends ConsumerWidget {
  const DockTopFeather({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PerformanceMode perf = ref.watch(performanceModeProvider);
    final double blur = ref.watch(glassBlurProvider);
    final bool blurOn = perf != PerformanceMode.performance && blur > 0;
    final AppThemeColors c = context.appColors;

    // 顶透明 → 底实玻璃 tint 的渐变，使羽化方向朝向 Dock。
    final Widget base = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            c.glassTint.withValues(alpha: 0),
            c.glassTint,
          ],
        ),
      ),
    );
    final Widget blurred = blurOn
        ? ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: blur * 0.6,
                sigmaY: blur * 0.6,
              ),
              child: base,
            ),
          )
        : base;

    return IgnorePointer(child: blurred);
  }
}

/// 底部 Dock 融合磨砂边（批3 #580 · A+B 合并）。
///
/// 合并原 [FrostEdgeBar(top: false)]（滚动驱动磨砂）与 [DockTopFeather]
/// （常驻羽化）为**单个** [BackdropFilter]：
///  - 未滚动：常驻极淡羽化（等同原 [DockTopFeather]，blur*0.6 + 0.85 可见度），
///    Dock 与内容之间无硬边；
///  - 滚动：模糊强度线性增强到满强度（等同原 [FrostEdgeBar]），内容滑入 Dock 自然羽化；
///  - 外缘 [ShaderMask] 羽化朝向 Dock（上缘透明 → 下缘实）。
/// 省去原「底边磨砂 + 顶部羽化」两层重叠模糊采样，切 Tab / 滑动时底部只做一次全宽高斯模糊。
/// 因 [IndexedStack] 全页保活（C11/P0-B10），此层只钉在 Dock 上方、不参与页面重建。
class DockBlendEdge extends ConsumerWidget {
  const DockBlendEdge({super.key});

  /// 常驻模糊强度基准（等同原 [DockTopFeather] 的 blur*0.6）。
  static const double _featherBlur = 0.6;

  /// 常驻可见度基准（贴近原 [DockTopFeather] 满可见，避免 Dock 硬边）。
  static const double _featherOpacity = 0.85;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double progress = ref.watch(pageScrollBlurProvider);
    final PerformanceMode perf = ref.watch(performanceModeProvider);
    final double blur = ref.watch(glassBlurProvider);
    final bool blurOn = perf != PerformanceMode.performance && blur > 0;
    final AppThemeColors c = context.appColors;

    // 模糊强度：常驻基准 → 滚动满强度（原两层的强度区间完全覆盖）。
    final double effBlur = _featherBlur + (1 - _featherBlur) * progress;
    final double sigma = blur * effBlur;
    // 可见度：常驻基准 → 滚动满（停在顶/底时仍保留 Dock 羽化，不刺眼）。
    final double opacity = _featherOpacity + (1 - _featherOpacity) * progress;

    final Widget base = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            c.glassTint.withValues(alpha: 0),
            c.glassTint,
          ],
        ),
      ),
    );
    final Widget blurred = blurOn
        ? ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: base,
            ),
          )
        : base;

    // 外缘羽化：上缘透明 → 下缘实，羽化方向朝向 Dock。
    final Widget feathered = ShaderMask(
      shaderCallback: (Rect rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0x00000000), Color(0xFF000000)],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: blurred,
    );

    return Opacity(
      opacity: opacity,
      child: IgnorePointer(child: feathered),
    );
  }
}
