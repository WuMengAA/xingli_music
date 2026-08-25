/// ════════════════════════════════════════════════════════════════════════
/// Liquid Glass 玻璃容器（全量迁移到 liquid_glass_widgets）
/// ════════════════════════════════════════════════════════════════════════
///
/// 自研 FragmentShader 折射 + BackdropFilter 毛玻璃已全量替换为成品库
/// [liquid_glass_widgets] 的 [AdaptiveGlass]（0.29.8，MIT）。[AdaptiveGlass]
/// 是**渲染器无关**的：Impeller 下走真折射 shader（iOS 26 质感），Skia/web
/// 下自动回落轻量 2D shader，最终还有 FakeGlass 兜底——**绝不静默不渲染**。
///
/// 公共 API（[LiquidGlass] 构造参数）保持不变，调用点（20+ 处）零改动：
/// 仅 [forceGlass] 白名单（Dock 栏、音乐控制栏）走真玻璃，其余在
/// [kNativeMinimal] 下保持原生极简直通（仅 padding）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/theme/app_theme_colors.dart';
import '../providers/settings/performance_providers.dart';

/// ── 原生极简模式总开关（R27 风格转向，R32 白名单化）────────────────────
///
/// `true` 时全站 [LiquidGlass] 调用（30 余处）默认退化为**纯内容直通**：
/// 去除半透明叠加色（tint）、细描边（border）、背景模糊（BackdropFilter）
/// 与圆角裁切，仅保留 `padding`。
///
/// 设计依据：以「极简主义」为视觉基底 —— 不使用背景卡片 / 边框 / 任何带容器
/// 边界的装饰元素，改由留白、排版层级与系统原生控件区分内容区块；极光渐变
/// 降为清淡氛围主题层。
///
/// **白名单放行**：R32 起少数「核心浮层」经 [LiquidGlass.forceGlass] 显式
/// 恢复玻璃质感（Dock 栏、音乐控制栏）——类似 Windows 11 / iOS 的玻璃焦点，
/// 基底保持原生极简，仅这两处浮层带玻璃。改回 `false` 即可整体回滚到
/// 极光玻璃全站风格。
const bool kNativeMinimal = true;

/// 玻璃风格。
enum GlassStyle {
  /// 经典毛玻璃：背景模糊 + 半透明 + 细描边（默认，统一不诡异）。
  frosted,

  /// 液态玻璃：折射 + 色散（[AdaptiveGlass] premium 路径，Dock 栏用，待精调）。
  liquid,
}

/// 玻璃容器。
class LiquidGlass extends ConsumerStatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.style = GlassStyle.frosted,
    this.blur,
    this.tint,
    this.borderColor,
    this.refraction = 5,
    this.dispersion = 1.2,
    this.padding = EdgeInsets.zero,
    this.forceGlass = false,
  });

  /// 玻璃内容。
  final Widget child;

  /// 圆角半径。
  final double radius;

  /// 玻璃风格；默认 [GlassStyle.frosted]（毛玻璃）。
  final GlassStyle style;

  /// 毛玻璃模糊强度（仅 [GlassStyle.frosted]）。
  ///
  /// 为 `null` 时由全局性能模式决定（省电=0 / 均衡=12 / 流畅=20），
  /// 低端设备切「省电」可即时关闭模糊、明显降发热。
  final double? blur;

  /// 毛玻璃半透明叠加色（仅 [GlassStyle.frosted]）。
  ///
  /// 为 `null` 时跟随主题语义色 [AppThemeColors.glassTint]
  /// （由皮肤主色派生，不写死白色）。
  final Color? tint;

  /// 毛玻璃描边色（仅 [GlassStyle.frosted]）。
  ///
  /// 为 `null` 时跟随主题语义色 [AppThemeColors.glassBorder]。
  final Color? borderColor;

  /// 折射强度（仅 [GlassStyle.liquid]，0~20），映射 refractiveIndex。
  final double refraction;

  /// 色散强度（仅 [GlassStyle.liquid]，0~4），映射 chromaticAberration。
  final double dispersion;

  /// 内容内边距。
  final EdgeInsetsGeometry padding;

  /// 原生极简模式下的白名单放行（R32）。
  ///
  /// `true` 时即使全局 [kNativeMinimal] 开启，本处仍渲染玻璃效果。
  /// 仅「核心浮层」使用（Dock 栏、音乐控制栏），其余 30 余处保持默认直通。
  final bool forceGlass;

  @override
  ConsumerState<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends ConsumerState<LiquidGlass> {
  @override
  Widget build(BuildContext context) {
    // 原生极简模式：默认直通内容（见 [kNativeMinimal]）；仅白名单
    // （[forceGlass]）的核心浮层恢复玻璃，构成「极简基底 + 玻璃焦点」。
    if (kNativeMinimal && !widget.forceGlass) {
      return Padding(padding: widget.padding, child: widget.child);
    }

    // 全量迁移到 liquid_glass_widgets：[AdaptiveGlass] 渲染器无关——
    // Impeller 走真折射 shader（iOS 26 质感），Skia/web 自动回落轻量 shader，
    // 最终 FakeGlass 兜底，绝不静默不渲染。
    final bool liquid = widget.style == GlassStyle.liquid;
    final PerformanceMode perf = ref.watch(performanceModeProvider);
    final double blur = widget.blur ?? ref.watch(glassBlurProvider);
    final AppThemeColors colors = context.appColors;
    final Color resolvedTint = widget.tint ?? colors.glassTint;
    final Color resolvedBorder = widget.borderColor ?? colors.glassBorder;

    // 性能档把半透明叠加减到接近 0（关闭一切半透明效果）。
    final Color tint = perf == PerformanceMode.performance
        ? resolvedTint.withValues(alpha: resolvedTint.a * 0.15)
        : resolvedTint;

    final LiquidGlassSettings settings = LiquidGlassSettings(
      // frost：直接对应模糊像素（典型 2~8）；省电档 blur=0 → 纯透无模糊。
      blur: blur,
      // glassColor：alpha 即着色强度，跟随皮肤主色派生语义色。
      glassColor: tint,
      // depth：液态玻璃更厚（折射更明显），毛玻璃偏薄。
      thickness: liquid ? 34 : 14,
      // refractiveIndex：液态玻璃按 refraction 映射（1 + v/100*0.2），
      // 毛玻璃给极弱折射（接近纯模糊）。
      refractiveIndex: liquid
          ? (1 + (widget.refraction / 100) * 0.2).clamp(1.0, 1.6)
          : 1.05,
      // chromaticAberration：色散（4 * v/100），液态玻璃明显、毛玻璃几乎无。
      chromaticAberration: liquid ? (widget.dispersion / 100) * 4 : 0.012,
      saturation: 1.4,
      glowIntensity: liquid ? 0.6 : 0.4,
      fresnelStrength: 1.0,
      ambientRim: liquid ? 0.15 : 0.0,
      shadowElevation: 1.0,
      whitenStrength: 0.0,
      edgeAbsorption: 0.0,
    );

    Widget glass = AdaptiveGlass(
      shape: LiquidRoundedSuperellipse(borderRadius: widget.radius),
      // liquid 走 premium 真折射；frosted 走 standard 轻量路径（更省）。
      quality: liquid ? GlassQuality.premium : GlassQuality.standard,
      settings: settings,
      child: Padding(padding: widget.padding, child: widget.child),
    );

    // 保留此前需要的细描边（borderColor 非透明时叠加 1px hairline）。
    // 多数调用（含 Dock）borderColor 透明 → 不进此分支，由 lib 自身边缘光替代。
    if (resolvedBorder.a > 0) {
      glass = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: resolvedBorder, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: glass,
        ),
      );
    }
    return glass;
  }
}
