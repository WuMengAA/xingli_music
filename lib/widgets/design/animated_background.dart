/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 设计语言背景层（极淡渐变 + 抽象彩色图形 · 平面抽象 / 更透）
/// ════════════════════════════════════════════════════════════════════════
///
/// 2026-09-06 设计指令（简单路线，反"AI 化"、反"液态玻璃 bug"）：
///   「一个大卡片背景模糊，然后不同颜色的图形在切换页面时随着页面变化而变化，
///    最多的就是位移，注意组合搭配使用，抽象简单。」+ 背景要更透明、平面抽象。
///
/// 2026-09-14 增强（诉求⑥·几何随意浮动）：
///   抽象图形除切页位移外，新增**持续自由浮动**（各图形不同相位正弦漂移），
///   让背景"活"起来、而非仅切页时位移。全程 IgnorePointer，纯装饰。
///
/// 实现（不再用 GlassSurface / WebGL 折射，纯常规 widget）：
///   - 底层：一块**极淡对角渐变**氛围层（alpha 0.06~0.10），不挡内容、更透。
///   - 上层：N 个**抽象彩色图形**（圆角色块，alpha 0.20）。位置 = 切页位移
///     (base + dir*page) + 持续自由浮动(drift)；大小/旋转随页面与浮动轻微变化。
///   - 不依赖具体业务色，用一组抽象品牌色，明暗主题自适应。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/shell/shell_providers.dart';

/// 抽象图形调色板（简单、克制）。
const List<Color> _kShapeColors = <Color>[
  Color(0xFF8B5CF6), // 紫
  Color(0xFFF59E0B), // 琥珀
  Color(0xFF14B8A6), // 青
  Color(0xFFEC4899), // 粉
  Color(0xFF3B82F6), // 蓝
];

/// 单个抽象图形的静态定义。
/// [base] / [dir] 为屏幕尺寸比例（0..1）：切页目标位置 = (base + dir*page)。
/// [scaleStep]/[rotStep] 每切一页的额外缩放/旋转；[driftAmp]/[driftPhase]
/// 控制持续自由浮动的幅度与相位（错开 → 各图形浮动不同步）。
class _ShapeDef {
  const _ShapeDef({
    required this.base,
    required this.dir,
    required this.size,
    required this.color,
    this.scaleStep = 0,
    this.rotStep = 0,
    this.driftAmp = 12,
    this.driftPhase = 0,
  });

  final Offset base;
  final Offset dir;
  final double size;
  final int color;
  final double scaleStep;
  final double rotStep;
  final double driftAmp;
  final double driftPhase;
}

/// 5 个图形，base/dir 错开 → 切页各自位移不同；driftPhase 错开 → 持续浮动不同步。
const List<_ShapeDef> _kShapes = <_ShapeDef>[
  _ShapeDef(base: Offset(0.16, 0.22), dir: Offset(0.05, 0.03), size: 220, color: 0, scaleStep: 0.04, rotStep: 0.05, driftAmp: 16, driftPhase: 0.0),
  _ShapeDef(base: Offset(0.74, 0.16), dir: Offset(-0.04, 0.05), size: 160, color: 1, scaleStep: 0.05, rotStep: -0.04, driftAmp: 12, driftPhase: 1.3),
  _ShapeDef(base: Offset(0.28, 0.74), dir: Offset(0.06, -0.03), size: 180, color: 2, scaleStep: 0.03, rotStep: 0.06, driftAmp: 18, driftPhase: 2.5),
  _ShapeDef(base: Offset(0.82, 0.70), dir: Offset(-0.05, -0.04), size: 140, color: 3, scaleStep: 0.06, rotStep: -0.05, driftAmp: 10, driftPhase: 3.7),
  _ShapeDef(base: Offset(0.50, 0.46), dir: Offset(0.03, 0.06), size: 120, color: 4, scaleStep: 0.04, rotStep: 0.03, driftAmp: 14, driftPhase: 5.0),
];

/// 设计语言背景层。放在 AppShell 的 Stack 最底层（内容层之下）。
class AnimatedBackground extends ConsumerStatefulWidget {
  const AnimatedBackground({super.key});

  @override
  ConsumerState<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends ConsumerState<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  /// 持续自由浮动驱动（慢周期，低 CPU 占用）。
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int page = ref.watch(shellPageIndexProvider);
    final Size size = MediaQuery.of(context).size;
    const Duration dur = Duration(milliseconds: 320);
    const Curve curve = Curves.easeOutCubic;

    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (BuildContext context, Widget? _) {
            final double t = _ctrl.value; // 0..1 循环
            return Stack(
              children: <Widget>[
                // —— 极淡对角渐变氛围（更透、平面抽象）——
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          _kShapeColors[0].withValues(alpha: 0.10),
                          _kShapeColors[4].withValues(alpha: 0.06),
                        ],
                      ),
                    ),
                  ),
                ),
                // —— 抽象彩色图形（切页位移 + 持续自由浮动）——
                for (int i = 0; i < _kShapes.length; i++)
                  _ShapeLayer(
                    shape: _kShapes[i],
                    page: page,
                    size: size,
                    t: t,
                    duration: dur,
                    curve: curve,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 单个图形的位移层：切页位移（AnimatedPositioned）+ 持续自由浮动（drift）。
class _ShapeLayer extends StatelessWidget {
  final _ShapeDef shape;
  final int page;
  final Size size;
  final double t;
  final Duration duration;
  final Curve curve;

  const _ShapeLayer({
    required this.shape,
    required this.page,
    required this.size,
    required this.t,
    required this.duration,
    required this.curve,
  });

  @override
  Widget build(BuildContext context) {
    // 切页位移（保留原交互手感）。
    final double pageLeft =
        (shape.base.dx + shape.dir.dx * page) * size.width - shape.size / 2;
    final double pageTop =
        (shape.base.dy + shape.dir.dy * page) * size.height - shape.size / 2;
    // 持续自由浮动：各图形不同相位的正弦/余弦漂移（诉求⑥·随意浮动）。
    final double driftX = math.sin(t * 2 * math.pi + shape.driftPhase) * shape.driftAmp;
    final double driftY =
        math.cos(t * 2 * math.pi + shape.driftPhase * 1.3) * shape.driftAmp;
    return AnimatedPositioned(
      duration: duration,
      curve: curve,
      left: pageLeft + driftX,
      top: pageTop + driftY,
      child: _AnimatedBlob(
        size: shape.size,
        color: _kShapeColors[shape.color],
        scale: 1 + shape.scaleStep * page,
        rot: shape.rotStep * page +
            math.sin(t * 2 * math.pi + shape.driftPhase) * 0.06,
        duration: duration,
        curve: curve,
      ),
    );
  }
}

/// 抽象色块本体：缩放/旋转用 AnimatedContainer 做轻微组合动画；平面抽象、轻光。
class _AnimatedBlob extends StatelessWidget {
  final double size;
  final Color color;
  final double scale;
  final double rot;
  final Duration duration;
  final Curve curve;

  const _AnimatedBlob({
    required this.size,
    required this.color,
    required this.scale,
    required this.rot,
    required this.duration,
    required this.curve,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: size,
      height: size,
      transform: Matrix4.rotationZ(rot)..scale(scale),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(size * 0.45),
        // 平面抽象：仅极轻柔光，不再重阴影。
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 40,
            spreadRadius: -20,
          ),
        ],
      ),
    );
  }
}
