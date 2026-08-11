import 'dart:math';

import 'package:flutter/material.dart';

/// 极微弱噪点纹理（V1.0 3.1）：透明度 3%
///
/// 叠加在主背景上，增加一点质感但不打扰。
class NoiseTexture extends StatelessWidget {
  final int seed;
  const NoiseTexture({super.key, this.seed = 7});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _NoisePainter(seed: seed),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  final int seed;
  const _NoisePainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final Random rng = Random(seed);
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03);

    // 稀疏噪点：约每 4000px² 一个
    final int count = (size.width * size.height / 4000).round().clamp(200, 2000);
    for (int i = 0; i < count; i++) {
      final Offset p = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      final double r = 0.3 + rng.nextDouble() * 0.7;
      canvas.drawCircle(p, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => old.seed != seed;
}
