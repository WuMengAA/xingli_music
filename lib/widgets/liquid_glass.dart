/// ════════════════════════════════════════════════════════════════════════
/// 玻璃容器（平面抽象风格 · 标准 BackdropFilter 透明模糊）
/// ════════════════════════════════════════════════════════════════════════
///
/// 2026-09-06 方向修正：原 [liquid_glass_widgets] / [liquid_glass_compat] 的
/// WebGL 折射实现在真机到处出现显示 bug、压根不可用。本件改写为**标准
/// [BackdropFilter] 透明模糊 + 半透明填充 + 1px 细描边 + 圆角**的可靠玻璃，
/// 跨平台零显示问题、渲染稳定、性能可控。
///
/// 公共构造参数保持不变，30+ 调用点零改动；[style]/[refraction]/[dispersion]/
/// [forceGlass] 仅保留以兼容调用点，平面抽象风格下统一走 frosted 透明模糊。
library;

import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme_colors.dart';
import '../providers/settings/performance_providers.dart';

/// 默认模糊强度（px）。跟随性能模式在 [LiquidGlass] 内可调。
const double _kGlassBlur = 16;

/// 模糊面积守卫阈值（占整屏面积比例）。
///
/// 每个 [BackdropFilter] 都会分配一块与自身裁剪区域等大的离屏纹理
///（saveLayer）：整屏面板 1080×2400 ≈ 10MB，多个叠加就会把 GPU 内存推高、
///并在切页/滚动时反复分配回收造成卡顿。当其渲染面积超过整屏的该比例时，
///直接退化为纯半透明卡（无模糊），只给真实浮动小卡/中等面板保留毛玻璃。
///真实卡片（几十~几百 px）远小于阈值，视觉角色不受影响。
const double _kMaxGlassBlurAreaRatio = 0.5;

/// 玻璃风格（保留枚举以兼容调用点；平面抽象风格下仅 [GlassStyle.frosted] 生效）。
enum GlassStyle {
  /// 经典毛玻璃：背景模糊 + 半透明 + 细描边。
  frosted,

  /// 保留兼容位（原液态玻璃 premium 路径）。
  liquid,
}

/// 玻璃容器。
class LiquidGlass extends ConsumerStatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 20,
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

  /// 毛玻璃模糊强度（px）。为 `null` 时由全局性能模式决定
  ///（省电关闭模糊、均衡 16、流畅 22），低端设备切「省电」即时降发热。
  final double? blur;

  /// 毛玻璃半透明叠加色。为 `null` 时跟随主题语义色 [AppThemeColors.glassTint]
  ///（由皮肤主色派生，很透）。
  final Color? tint;

  /// 毛玻璃描边色。为 `null` 时跟随主题语义色 [AppThemeColors.glassBorder]。
  final Color? borderColor;

  /// 折射强度（保留兼容位，平面抽象风格下不生效）。
  final double refraction;

  /// 色散强度（保留兼容位，平面抽象风格下不生效）。
  final double dispersion;

  /// 内容内边距。
  final EdgeInsetsGeometry padding;

  /// 原生极简模式下的白名单放行（保留兼容位）。平面抽象风格下始终渲染玻璃。
  final bool forceGlass;

  @override
  ConsumerState<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends ConsumerState<LiquidGlass> {
  @override
  Widget build(BuildContext context) {
    final PerformanceMode perf = ref.watch(performanceModeProvider);
    final AppThemeColors colors = context.appColors;

    // 模糊强度：调用方覆盖 > 主题默认 > 全局常量；省电档强制关闭模糊。
    double blur = widget.blur ?? _kGlassBlur;
    if (perf == PerformanceMode.performance) blur = 0;
    blur = blur.clamp(0, 32);

    final Color tint = widget.tint ?? colors.glassTint;
    final Color border = widget.borderColor ?? colors.glassBorder;

    final Widget inner = Padding(padding: widget.padding, child: widget.child);

    // 无模糊时的纯半透明卡（无 saveLayer，零离屏纹理开销）。
    final Widget noBlur = Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: border, width: 1),
      ),
      child: inner,
    );

    if (blur <= 0.5) {
      // 省电档：纯半透明卡（无模糊，仍可靠渲染）。
      return noBlur;
    }

    // 面积守卫：超大面板（接近整屏）的 [BackdropFilter] 会分配整屏离屏纹理，
    // 多个叠加会撑爆 GPU 内存。超过阈值时退化为纯半透明卡，仅给真实浮动
    // 小卡/中等面板保留毛玻璃（见 [_kMaxGlassBlurAreaRatio]）。
    final Size screen = MediaQuery.sizeOf(context);
    return LayoutBuilder(
      builder: (BuildContext c, BoxConstraints constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        final bool huge =
            w.isFinite && h.isFinite && (w * h) > screen.width * screen.height * _kMaxGlassBlurAreaRatio;
        if (huge) return noBlur;

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(widget.radius),
                border: Border.all(color: border, width: 1),
              ),
              child: inner,
            ),
          ),
        );
      },
    );
  }
}
