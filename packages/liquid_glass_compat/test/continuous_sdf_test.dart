import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

void main() {
  group('chamferSignedDistanceField', () {
    test('实心方块：内部为负，外部为正', () {
      const n = 32;
      final alpha = List<int>.filled(n * n, 0);
      // 中心 16×16 实心方块。
      for (var y = 8; y < 24; y++) {
        for (var x = 8; x < 24; x++) {
          alpha[y * n + x] = 255;
        }
      }
      final sdf = chamferSignedDistanceField(alpha, n, refDistancePx: 8);
      // 中心深处：强负。
      expect(sdf[16 * n + 16], lessThan(-0.5));
      // 中心更深处比靠近边缘更负（绝对值更大）。
      expect(sdf[15 * n + 16], lessThan(sdf[12 * n + 16]),
          reason: '更深内部应更负');
      // 外部远处：强正。
      expect(sdf[0], greaterThan(0.5));
      // 靠近边缘外部：浅正。
      expect(sdf[6 * n + 16], greaterThan(0.0));
      expect(sdf[26 * n + 16], greaterThan(0.0));
    });

    test('值域严格落在 [-1, 1]', () {
      const n = 24;
      final alpha = List<int>.filled(n * n, 255);
      final sdf = chamferSignedDistanceField(alpha, n, refDistancePx: 4);
      for (final v in sdf) {
        expect(v, greaterThanOrEqualTo(-1.0001));
        expect(v, lessThanOrEqualTo(1.0001));
      }
    });
  });

  group('SdfTexture.sample', () {
    test('双线性采样大致连续', () {
      const n = 8;
      // 半平面 SDF：x<4 → -1，x>=4 → +1。
      final values = List<double>.generate(n * n, (i) {
        final x = i % n;
        return x < 4 ? -1.0 : 1.0;
      });
      final tex = SdfTexture(texSize: n, values: values, radiusPx: 2);
      expect(tex.sample(0.0, 0.5), closeTo(-1.0, 0.6));
      expect(tex.sample(0.9, 0.5), closeTo(1.0, 0.6));
      // 边界附近应在 [-1,1] 之间。
      final mid = tex.sample(0.5, 0.5);
      expect(mid, greaterThanOrEqualTo(-1.0001));
      expect(mid, lessThanOrEqualTo(1.0001));
    });
  });

  group('sdfToRgba8', () {
    test('输出 RGBA8 且 R 通道编码正确', () {
      const n = 6;
      final values = List<double>.filled(n * n, -1.0);
      final tex = SdfTexture(texSize: n, values: values, radiusPx: 2);
      final bytes = sdfToRgba8(tex);
      expect(bytes.length, n * n * 4);
      // 值 -1 → ((-1)*0.5 + 0.5)*255 = 0 → R 通道 0。
      for (var i = 0; i < n * n; i++) {
        expect(bytes[i * 4], 0, reason: 'RGBA R 通道 idx $i');
        expect(bytes[i * 4 + 3], 255);
      }
    });

    test('值 0.8 → 高亮编码', () {
      const n = 4;
      final values = List<double>.filled(n * n, 0.8);
      final tex = SdfTexture(texSize: n, values: values, radiusPx: 2);
      final bytes = sdfToRgba8(tex);
      expect(bytes[0], ((0.8 * 0.5 + 0.5) * 255).round());
    });
  });
}