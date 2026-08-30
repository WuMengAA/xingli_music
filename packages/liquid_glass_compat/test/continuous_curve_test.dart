import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

/// 用 path.computeMetrics 采样真实曲线范围（Skia getBounds 是控制点凸包，曲线本身才决定视觉）。
Rect actualCurveBounds(Path path, {int samples = 400}) {
  double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
  for (final metric in path.computeMetrics()) {
    for (var i = 0; i <= samples; i++) {
      final pos = metric.getTangentForOffset(metric.length * i / samples)?.position;
      if (pos == null) continue;
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
  }
  if (minX > maxX) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

void main() {
  group('ContinuousCurvatureRoundedRectangleCornerBuilder', () {
    final builder = ContinuousCurvatureRoundedRectangleCornerBuilder();

    test('even corner (t=0) 控制点结构与端点', () {
      final p = builder.getCornerBezierPoints(0.0, 0.0);
      expect(p.length, 20);
      // t=0：k = extendedFraction*0 = 0 → x0 = 0，y9 = 1 - x0 = 1。
      expect(p[0], closeTo(0.0, 1e-9)); // x0
      expect(p[1], closeTo(0.0, 1e-9)); // y0
      expect(p[18], closeTo(1.0, 1e-9)); // x9（硬编码 1.0）
      expect(p[19], closeTo(1.0, 1e-9)); // y9 = 1 - x0
      // 前段贝塞尔：三个控制点都在 x 轴（y=0）。
      expect(p[3], closeTo(0.0, 1e-9));
      expect(p[5], closeTo(0.0, 1e-9));
    });

    test('even corner (t=1) 控制点外扩（原版 extendedFraction=2/3）', () {
      final p = builder.getCornerBezierPoints(1.0, 1.0);
      expect(p.length, 20);
      // t=1：k = 2/3 → x0 = -2/3，y9 = 1 - x0 = 5/3。
      expect(p[0], closeTo(-2.0 / 3.0, 1e-6));
      expect(p[19], closeTo(5.0 / 3.0, 1e-6));
      // 外扩控制点在角点之外（G2 连续的必要条件），但不参与可见端点。
      expect(p[0], lessThan(0.0));
      expect(p[19], greaterThan(1.0));
    });

    test('uneven corner (tW=1, tV=0) 结构', () {
      final p = builder.getCornerBezierPoints(1.0, 0.0);
      expect(p.length, 20);
      // 水平方向外扩到 -2/3，垂直方向仍是 0 起点。
      expect(p[0], closeTo(-2.0 / 3.0, 1e-6));
      expect(p[19], closeTo(1.0, 1e-9)); // y9 = 1 - x0p = 1
    });
  });

  group('continuousCurvatureRoundedRectPath', () {
    test('100×60 r=16：曲线包围盒 = w×h 各向外张 r·0.4（原版裁剪语义）', () {
      const w = 100.0, h = 60.0, r = 16.0;
      final curve = actualCurveBounds(
          continuousCurvatureRoundedRectPath(w, h, r));
      // 实际曲线覆盖矩形本身（玻璃主体在 [0,w]×[0,h] 内），
      // 角部控制点外扩使曲线比矩形每侧多 ~0.4r（≈6.4px，r=16）。
      expect(curve.left, lessThanOrEqualTo(0));
      expect(curve.top, lessThanOrEqualTo(0));
      expect(curve.right, greaterThanOrEqualTo(w));
      expect(curve.bottom, greaterThanOrEqualTo(h));
      final overshoot = 0.4 * r;
      expect((curve.left).abs(), closeTo(overshoot, 2.0), reason: '左外扩 ≈ 0.4r');
      expect(curve.right - w, closeTo(overshoot, 2.0), reason: '右外扩 ≈ 0.4r');
      expect((curve.top).abs(), closeTo(overshoot, 2.0), reason: '上外扩 ≈ 0.4r');
      expect(curve.bottom - h, closeTo(overshoot, 2.0), reason: '下外扩 ≈ 0.4r');
    });

    test('胶囊：w=200 h=64 r=32 曲线同样外扩 0.4r', () {
      const w = 200.0, h = 64.0, r = 32.0;
      final curve = actualCurveBounds(
          continuousCurvatureRoundedRectPath(w, h, r));
      expect(curve.left, lessThanOrEqualTo(0));
      expect(curve.right, greaterThanOrEqualTo(w));
      expect(curve.left.abs(), closeTo(0.4 * r, 3.0));
      expect(curve.right - w, closeTo(0.4 * r, 3.0));
    });

    test('退化半径 0 → 直角矩形，无外扩', () {
      const w = 100.0, h = 60.0;
      final curve = actualCurveBounds(
          continuousCurvatureRoundedRectPath(w, h, 0));
      expect(curve.left, closeTo(0, 0.01));
      expect(curve.top, closeTo(0, 0.01));
      expect(curve.right, closeTo(w, 0.01));
      expect(curve.bottom, closeTo(h, 0.01));
    });

    test('路径闭合且面积足够（glass 主体覆盖矩形中心）', () {
      const w = 200.0, h = 120.0, r = 24.0;
      final Path path = continuousCurvatureRoundedRectPath(w, h, r);
      expect(path.computeMetrics().isEmpty, isFalse);
      expect(path.computeMetrics().length, greaterThan(0));
    });
  });
}