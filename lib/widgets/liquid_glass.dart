/// ════════════════════════════════════════════════════════════════════════
/// Liquid Glass 玻璃容器（双模式）
/// ════════════════════════════════════════════════════════════════════════
///
/// 支持两种风格：
///  - [GlassStyle.frosted] 经典毛玻璃：背景模糊 + 半透明 + 细描边（默认，统一不诡异）
///  - [GlassStyle.liquid]  液态玻璃：折射 + 色散（FragmentShader，Dock 栏专用，待精调）
library;

import 'dart:async' show Timer;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme_colors.dart';
import '../providers/settings/performance_providers.dart';
import '../providers/shell/liquid_glass_capture_provider.dart';

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
  /// 经典毛玻璃：背景模糊 + 半透明 + 细描边。
  frosted,

  /// 液态玻璃：折射 + 色散（FragmentShader），Dock 栏专用，待精调。
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

  /// 折射强度（仅 [GlassStyle.liquid]，0~20）。
  final double refraction;

  /// 色散强度（仅 [GlassStyle.liquid]，0~4）。
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
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    if (widget.style == GlassStyle.liquid) _load();
  }

  Future<void> _load() async {
    try {
      final ui.FragmentProgram p = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      if (mounted) setState(() => _program = p);
    } catch (e) {
      debugPrint('liquid_glass shader load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 液态玻璃开关（R21 效果选配）：关闭时走毛玻璃路径。
    // R20 期间 Windows 禁用 FragmentShader 的降级已随无障碍桥崩溃
    // 根治（ExcludeSemantics）而还原——各平台均可使用液态玻璃。
    // 原生极简模式：默认直通内容（见 [kNativeMinimal]）；仅白名单
    // （[forceGlass]）的核心浮层恢复玻璃，构成「极简基底 + 玻璃焦点」。
    if (kNativeMinimal && !widget.forceGlass) {
      return Padding(padding: widget.padding, child: widget.child);
    }
    final bool liquidOn = ref.watch(liquidGlassEnabledProvider);
    if (widget.style == GlassStyle.liquid && liquidOn) {
      return _buildLiquid(context);
    }
    return _buildFrosted(context);
  }

  /// 毛玻璃：BackdropFilter 模糊 + 半透明 tint + 细描边。
  ///
  /// 开销跟随全局性能模式：
  ///   - 省电：blur=0（跳过 BackdropFilter）+ tint 减淡（半透明效果关闭）
  ///   - 均衡/流畅：按档位模糊，保留半透明
  Widget _buildFrosted(BuildContext context) {
    final PerformanceMode perf = ref.watch(performanceModeProvider);
    // R20 期间 Windows 强制 blur=0 的降级已随无障碍桥崩溃根治而还原，
    // 模糊强度完全跟随全局性能体系（glassBlurProvider / 手动覆盖）。
    final double blur = widget.blur ?? ref.watch(glassBlurProvider);
    final double radius = widget.radius;
    // 主题语义色兜底：tint/borderColor 未显式传入时跟随皮肤主色 / 边框色，
    // 实现「配色不写死、可切换皮肤」——毛玻璃随明暗主题与 6 套配色同步变化。
    final AppThemeColors colors = context.appColors;
    final Color resolvedTint = widget.tint ?? colors.glassTint;
    final Color resolvedBorder = widget.borderColor ?? colors.glassBorder;
    // 性能档把半透明叠加减到接近 0（关闭一切半透明效果）
    final Color tint = perf == PerformanceMode.performance
        ? resolvedTint.withValues(alpha: resolvedTint.a * 0.15)
        : resolvedTint;
    final Widget child = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: resolvedBorder, width: 1),
      ),
      child: widget.child,
    );
    if (blur <= 0) {
      // 省电模式：跳过 BackdropFilter（模糊是全屏采样，开销最大）
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: _ThrottledBackdrop(
        blur: blur,
        // P7·#507：模糊采样率封顶（默认 24 FPS），避免高帧率下每帧重采高斯。
        fps: ref.watch(blurFpsProvider),
        // 隔离：把玻璃内容放进独立图层（RepaintBoundary）。
        // 否则内容区内的逐帧重绘（歌词滚动 / 进度条 tick / Dock 指示器
        // AnimatedContainer / 页面滚动）会污染 BackdropFilter 所在图层，
        // 迫使每帧对整片背景重新采样 + 高斯模糊——这是中低端机 UI 卡顿的
        // 主因之一（ContentContainer 的毛玻璃铺满整屏，影响最大）。
        // 隔离后模糊层只在背景（AppShell 玻璃层 / 场景背景，二者本身已各自
        // RepaintBoundary 化）变化时重算，内容动画不再连累模糊，视觉零变化。
        child: RepaintBoundary(child: child),
      ),
    );
  }

  /// 液态玻璃（折射 + 色散，FragmentShader）。Dock 栏专用，待精调。
  Widget _buildLiquid(BuildContext context) {
    final ui.Image? bg = LiquidGlassCapture.maybeOf(context);
    final Widget content = Padding(padding: widget.padding, child: widget.child);

    if (bg == null || _program == null) {
      // 背景快照或 shader 未就绪：退回纯内容（测试/首帧）。
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          // 底层：折射 + 色散的背景。
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RefractionPainter(
                  program: _program!,
                  background: bg,
                  radius: widget.radius,
                  refraction: widget.refraction,
                  dispersion: widget.dispersion,
                ),
              ),
            ),
          ),
          // 上层：玻璃内容。
          content,
        ],
      ),
    );
  }
}

/// 用 FragmentShader 绘制折射 + 色散背景。
class _RefractionPainter extends CustomPainter {
  _RefractionPainter({
    required this.program,
    required this.background,
    required this.radius,
    required this.refraction,
    required this.dispersion,
  });

  final ui.FragmentProgram program;
  final ui.Image background;
  final double radius;
  final double refraction;
  final double dispersion;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.FragmentShader shader = program.fragmentShader();
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, radius)
      ..setFloat(3, refraction)
      ..setFloat(4, dispersion)
      ..setImageSampler(0, background);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _RefractionPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.radius != radius ||
      oldDelegate.refraction != refraction ||
      oldDelegate.dispersion != dispersion;
}

/// 毛玻璃模糊层（P7·#507）：以 [fps] 上限封顶 [BackdropFilter] 的背景重采样率。
///
/// 背景（AppShell 玻璃层 / 场景背景）逐帧变化时，BackdropFilter 会每帧对整片
/// 背景重采高斯模糊——高帧率（60/120）下是中低端机 UI 卡顿主因。本层用独立
/// [RepaintBoundary] 包裹 BackdropFilter，并以定时器按 [fps] 驱动其重绘，
/// 将「模糊采样率」封顶在 fps（默认 24），避免每帧重采样。当背景静止时仍按
/// fps 节拍重绘一次（开销恒定且远小于 60fps 全量采样）。
class _ThrottledBackdrop extends StatefulWidget {
  const _ThrottledBackdrop({
    required this.blur,
    required this.fps,
    required this.child,
  });

  /// 模糊强度（sigma）。
  final double blur;

  /// 重采样帧率上限（0 = 不限制，直接走普通 BackdropFilter）。
  final int fps;

  /// 被模糊的内容（应已自行 RepaintBoundary 隔离）。
  final Widget child;

  @override
  State<_ThrottledBackdrop> createState() => _ThrottledBackdropState();
}

class _ThrottledBackdropState extends State<_ThrottledBackdrop> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    final int fps = widget.fps;
    if (fps > 0) {
      _timer = Timer.periodic(
        Duration(milliseconds: (1000 / fps).round().clamp(1, 1000)),
        (_) {
          if (mounted) setState(() {}); // 触发模糊层重绘（重采样背景）。
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant _ThrottledBackdrop old) {
    super.didUpdateWidget(old);
    if (old.fps != widget.fps || old.blur != widget.blur) _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: widget.child,
      ),
    );
  }
}
