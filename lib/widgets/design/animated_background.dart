/// ════════════════════════════════════════════════════════════════════════
/// 星璃音乐 · 设计语言背景层（模糊大卡片 + 抽象彩色图形）
/// ════════════════════════════════════════════════════════════════════════
///
/// 用户 2026-09-06 设计指令（简单路线，反"AI 化"）：
///   「一个大卡片背景模糊，然后不同颜色的图形在切换页面时随着页面变化而变化，
///    最多的就是位移，注意组合搭配使用，抽象简单。」
///
/// 实现：
///   - 底层：一块覆盖全屏（留边）的**模糊大卡片** GlassSurface（毛玻璃质感）。
///   - 上层：N 个**抽象彩色图形**（圆角色块），随 `shellPageIndexProvider`
///     切换页面做**位移(translate)为主**、少量缩放/旋转组合，曲线缓动。
///   - 全程 IgnorePointer，纯装饰，不参与命中测试。
///   - 不依赖具体业务色，用一组抽象品牌色，明暗主题自适应。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

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
/// [base] / [dir] 为屏幕尺寸比例（0..1）：目标位置 = (base + dir*page)。
class _ShapeDef {
  final Offset base;
  final Offset dir;
  final double size;
  final int color;
  final double scaleStep; // 每页额外缩放
  final double rotStep; // 每页额外旋转（弧度）
  const _ShapeDef({
    required this.base,
    required this.dir,
    required this.size,
    required this.color,
    this.scaleStep = 0,
    this.rotStep = 0,
  });
}

/// 5 个图形，base/dir 错开 → 切换页面时各自位移不同，组合出"流动"感。
const List<_ShapeDef> _kShapes = <_ShapeDef>[
  _ShapeDef(base: Offset(0.16, 0.22), dir: Offset(0.05, 0.03), size: 220, color: 0, scaleStep: 0.04, rotStep: 0.05),
  _ShapeDef(base: Offset(0.74, 0.16), dir: Offset(-0.04, 0.05), size: 160, color: 1, scaleStep: 0.05, rotStep: -0.04),
  _ShapeDef(base: Offset(0.28, 0.74), dir: Offset(0.06, -0.03), size: 180, color: 2, scaleStep: 0.03, rotStep: 0.06),
  _ShapeDef(base: Offset(0.82, 0.70), dir: Offset(-0.05, -0.04), size: 140, color: 3, scaleStep: 0.06, rotStep: -0.05),
  _ShapeDef(base: Offset(0.50, 0.46), dir: Offset(0.03, 0.06), size: 120, color: 4, scaleStep: 0.04, rotStep: 0.03),
];

/// 设计语言背景层。放在 AppShell 的 Stack 最底层（内容层之下）。
class AnimatedBackground extends ConsumerWidget {
  const AnimatedBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int page = ref.watch(shellPageIndexProvider);
    final Size size = MediaQuery.of(context).size;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color tint = dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.55);
    const Duration dur = Duration(milliseconds: 320);
    const Curve curve = Curves.easeOutCubic;

    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          // —— 模糊大卡片 ——
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GlassSurface(
                visuals: GlassVisuals(blur: 18, radius: 40, tint: tint),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          // —— 抽象彩色图形（随页面位移）——
          for (int i = 0; i < _kShapes.length; i++)
            _ShapeLayer(
              shape: _kShapes[i],
              page: page,
              size: size,
              duration: dur,
              curve: curve,
            ),
        ],
      ),
    );
  }
}

/// 单个图形的位移层（AnimatedPositioned 驱动 translate）。
class _ShapeLayer extends StatelessWidget {
  final _ShapeDef shape;
  final int page;
  final Size size;
  final Duration duration;
  final Curve curve;

  const _ShapeLayer({
    required this.shape,
    required this.page,
    required this.size,
    required this.duration,
    required this.curve,
  });

  @override
  Widget build(BuildContext context) {
    final double left =
        (shape.base.dx + shape.dir.dx * page) * size.width - shape.size / 2;
    final double top =
        (shape.base.dy + shape.dir.dy * page) * size.height - shape.size / 2;
    return AnimatedPositioned(
      duration: duration,
      curve: curve,
      left: left,
      top: top,
      child: _AnimatedBlob(
        size: shape.size,
        color: _kShapeColors[shape.color],
        page: page,
        scaleStep: shape.scaleStep,
        rotStep: shape.rotStep,
        duration: duration,
        curve: curve,
      ),
    );
  }
}

/// 抽象色块本体：缩放/旋转用 AnimatedContainer 做轻微组合动画。
class _AnimatedBlob extends StatelessWidget {
  final double size;
  final Color color;
  final int page;
  final double scaleStep;
  final double rotStep;
  final Duration duration;
  final Curve curve;

  const _AnimatedBlob({
    required this.size,
    required this.color,
    required this.page,
    required this.scaleStep,
    required this.rotStep,
    required this.duration,
    required this.curve,
  });

  @override
  Widget build(BuildContext context) {
    final double scale = 1 + scaleStep * page;
    final double rot = rotStep * page;
    return AnimatedContainer(
      duration: duration,
      curve: curve,
      width: size,
      height: size,
      transform: Matrix4.rotationZ(rot)..scale(scale),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(size * 0.4),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 50,
            spreadRadius: -12,
          ),
        ],
      ),
    );
  }
}
