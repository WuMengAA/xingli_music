import 'dart:math';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// 粒子运动风格（按场景派生）
enum ParticleMotion {
  floatUp,
  rainDown,
  snowDown,
  emberUp,
  bubbleUp,
}

/// 场景粒子层
///
/// 性能优化：批量 drawPoints 绘制（每帧 3 次调用），
/// 闪烁用整体呼吸系数（一次 sin），替代每粒子 sin + 逐个 drawCircle。
class SceneParticles extends StatefulWidget {
  final Color color;
  final int seed;
  final ParticleMotion motion;
  /// 音乐能量（0~1）。为 null 时不随音乐变化；非 null 时亮度/大小随音乐呼吸。
  final double? level;

  const SceneParticles({
    super.key,
    required this.color,
    required this.seed,
    this.motion = ParticleMotion.floatUp,
    this.level,
  });

  @override
  State<SceneParticles> createState() => _SceneParticlesState();
}

class _SceneParticlesState extends State<SceneParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    _stars = _spawn();
  }

  @override
  void didUpdateWidget(covariant SceneParticles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed ||
        oldWidget.motion != widget.motion) {
      _stars = _spawn();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_Star> _spawn() {
    final Random rng = Random(widget.seed);
    // 数量 60~100（兼顾氛围与性能）
    final int count = 60 + rng.nextInt(41);

    return List.generate(count, (i) {
      // 大小归到 3 档（2/3.5/5px），便于分桶批量绘制
      final int sizeTier = rng.nextInt(3);
      final double size = [2.0, 3.5, 5.0][sizeTier];
      final double opacity = [0.10, 0.17, 0.25][sizeTier];
      final double twinkle = rng.nextDouble() * 2 * pi;

      double vx, vy;
      switch (widget.motion) {
        case ParticleMotion.rainDown:
          final double angle = (rng.nextDouble() - 0.5) * 0.6;
          vx = sin(angle) * (1.0 + rng.nextDouble());
          vy = 1.5 + rng.nextDouble() * 1.5;
        case ParticleMotion.snowDown:
          vx = (rng.nextDouble() - 0.5) * 0.8;
          vy = 0.4 + rng.nextDouble() * 0.4;
        case ParticleMotion.emberUp:
          vx = (rng.nextDouble() - 0.5) * 0.6;
          vy = -(0.8 + rng.nextDouble() * 1.2);
        case ParticleMotion.bubbleUp:
          vx = (rng.nextDouble() - 0.5) * 0.3;
          vy = -(0.3 + rng.nextDouble() * 0.4);
        case ParticleMotion.floatUp:
          vx = (rng.nextDouble() - 0.5) * 0.4;
          vy = -(0.2 + rng.nextDouble() * 0.4);
      }

      return _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        vx: vx,
        vy: vy,
        size: size,
        opacity: opacity,
        twinkle: twinkle,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size.infinite,
              painter: _ParticlePainter(
                stars: _stars,
                progress: _controller.value,
                color: widget.color,
                level: widget.level,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Star {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double size;
  final double opacity;
  final double twinkle;
  const _Star({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.opacity,
    required this.twinkle,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Star> stars;
  final double progress;
  final Color color;
  final double? level;

  const _ParticlePainter({
    required this.stars,
    required this.progress,
    required this.color,
    required this.level,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 按大小分 3 桶，一次 drawPoints 批量绘制（大幅减少调用开销）
    final List<Offset> small = [];
    final List<Offset> medium = [];
    final List<Offset> large = [];

    for (final _Star s in stars) {
      double y = (s.y + progress * s.vy) % 1.0;
      if (y < 0) y += 1.0;
      double x = (s.x + progress * s.vx) % 1.0;
      if (x < 0) x += 1.0;
      final Offset p = Offset(x * size.width, y * size.height);

      if (s.size <= 2.5) {
        small.add(p);
      } else if (s.size <= 4.0) {
        medium.add(p);
      } else {
        large.add(p);
      }
    }

    // 整体呼吸（一次 sin）
    final double breathe =
        0.85 + 0.15 * sin(progress * 2 * pi * 4 + 1.0);

    final double energy = level ?? 0.0;
    void drawBucket(List<Offset> pts, double radius, double alpha) {
      if (pts.isEmpty) return;
      canvas.drawPoints(
        PointMode.points,
        pts,
        Paint()
          ..color = color.withValues(
            alpha: (alpha * breathe * (0.6 + 0.4 * energy)).clamp(0.0, 0.35),
          )
          ..strokeWidth = radius * 2 * (1.0 + 0.15 * energy)
          ..strokeCap = StrokeCap.round,
      );
    }

    drawBucket(small, 1.0, 0.10);
    drawBucket(medium, 1.75, 0.17);
    drawBucket(large, 2.5, 0.25);
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.stars != stars ||
      oldDelegate.color != color ||
      oldDelegate.level != level;
}
