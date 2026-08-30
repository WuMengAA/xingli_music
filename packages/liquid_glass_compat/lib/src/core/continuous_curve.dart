import 'dart:math' as math;
import 'dart:ui';

/// ───────────────────────────────────────────────────────────────────────
/// G2 连续曲率圆角（Continuous Curvature Rounded Rectangle）
///
/// 移植自 martin65536/liquid-glass-webgl 的 `continuous-curve.ts`，
/// 上游移植自 Kyant0/AndroidLiquidGlass 的
/// `ContinuousCurvatureRoundedRectangleCornerBuilder.kt`。
///
/// 每个角由 3 段三次贝塞尔（20 个控制点）构成，保持 *G2 连续*——
/// 曲率在所有接合处都连续，而不只是切线连续。这就是玻璃胶囊体
/// 看起来「对」的原因：相比朴素圆角矩形（只有 G1/切线连续）没有
/// 可见的曲率突变。
/// ───────────────────────────────────────────────────────────────────────

class ContinuousCurvatureRoundedRectangleCornerBuilder {
  static const double _sqrt2 = 1.4142135623730951;
  static const double _fracPi4 = 0.7853981633974483;
  static const double _frac1Sqrt2 = 0.7071067811865476;

  final double extendedFraction;
  final double arcFraction;

  // 预计算的三角度量
  late final double _theta;
  late final double _cos;
  late final double _sin;
  late final double _cot;
  late final double _cos2;
  late final double _sin2;
  late final double _cos3;
  late final double _sin3;
  late final double _k0;
  late final double _k1;
  late final double _k2;
  late final double _k3;

  ContinuousCurvatureRoundedRectangleCornerBuilder({
    this.extendedFraction = 2.0 / 3.0,
    this.arcFraction = 0.5,
  }) {
    _theta = (1.0 - arcFraction) * _fracPi4;
    _cos = math.cos(_theta);
    _sin = math.sin(_theta);
    _cot = 1.0 / math.tan(_theta);
    _cos2 = _cos * _cos;
    _sin2 = _sin * _sin;
    _cos3 = _cos2 * _cos;
    _sin3 = _sin2 * _sin;

    final cos = _cos, sin = _sin, cot = _cot;
    final cos2 = _cos2, sin2 = _sin2, cos3 = _cos3, sin3 = _sin3;

    _k0 = 27.0 * (_sqrt2 - 6.0 * cos + 6.0 * _sqrt2 * cos2 - 4.0 * cos3) * cot +
        2.0 * sin * (-9.0 + 2.0 * (_sqrt2 - 2.0 * sin) * sin3 +
            2.0 * _sqrt2 * cos * (9.0 + sin2) - 2.0 * cos2 * (9.0 + 2.0 * sin2));

    _k1 = -81.0 * (-2.0 + _sqrt2 + 4.0 * (-1.0 + _sqrt2) * cos +
            2.0 * (-2.0 + _sqrt2) * cos2) * cot -
        4.0 * sin * (-9.0 + 9.0 * _sqrt2 + _sqrt2 * sin3 +
            (-2.0 + _sqrt2) * cos * (9.0 + sin2));

    _k2 = 9.0 * (9.0 * (-4.0 + 3.0 * _sqrt2 + (-6.0 + 4.0 * _sqrt2) * cos) * cot +
        (-6.0 + 4.0 * _sqrt2) * sin);

    _k3 = 27.0 * (10.0 - 6.0 * _sqrt2 + (-6.0 + 4.0 * _sqrt2) * cos);
  }

  /// 单实根三次方程求解（Cardano 法）
  double _solveCubicSingle(double a, double b, double c, double d) {
    final f = ((3.0 * c) / a - (b * b) / (a * a)) / 3.0;
    final g = ((2.0 * b * b * b) / (a * a * a) -
            (9.0 * b * c) / (a * a) +
            (27.0 * d) / a) /
        27.0;
    final h = (g * g) / 4.0 + (f * f * f) / 27.0;
    final sqrtH = math.sqrt(h);
    return _cbrt(-g / 2.0 + sqrtH) + _cbrt(-g / 2.0 - sqrtH) - b / (3.0 * a);
  }

  /// 降次四次方程单实根求解（Ferrari 化简）
  double _solveDepressedQuarticSingle(double p, double q, double r) {
    final b = -p / 2.0;
    final c = -r;
    final d = (r * p) / 2.0 - (q * q) / 8.0;
    final f = (3.0 * c - b * b) / 3.0;
    final g = (2.0 * b * b * b - 9.0 * b * c + 27.0 * d) / 27.0;
    final rVal = math.sqrt((-f * f * f) / 27.0);
    final phi = math.acos(-g / (2.0 * rVal));
    final y = 2.0 * math.sqrt(-f / 3.0) * math.cos(phi / 3.0);
    final z = y - b / 3.0;
    final u = math.sqrt(2.0 * z - p);
    return (u - math.sqrt(u * u - 4.0 * (z + q / (2.0 * u)))) / 2.0;
  }

  static double _cbrt(double v) =>
      (v < 0 ? -math.pow(-v, 1.0 / 3.0) : math.pow(v, 1.0 / 3.0)).toDouble();

  /// 等边角（宽高方向的圆角占比一致）的三段贝塞尔控制点
  List<double> _buildEvenCornerBezierPoints(double t) {
    final k = extendedFraction * t;
    final kappa = _solveCubicSingle(
        _k3, _k2, _k1 + 8.0 * (-k) * _sin3 * _sin, _k0);

    final x3 = _frac1Sqrt2 + (-_frac1Sqrt2 + _sin) / kappa;
    final y3 = 1.0 - _frac1Sqrt2 + (_frac1Sqrt2 - _cos) / kappa;
    final x2 = x3 - y3 * _cot;
    final x1 = x2 - (1.5 * kappa * y3 * y3) / _sin3;
    final x0 = -k;

    final x6 = 1.0 - y3;
    final y6 = 1.0 - x3;
    final y7 = 1.0 - x2;
    final y8 = 1.0 - x1;
    final y9 = 1.0 - x0;

    final a = 1.5 * kappa;
    final g = _cos2 - _sin2;
    final x36 = x6 - x3;
    final y36 = y6 - y3;
    final c = -(_cos * y36 - _sin * x36);
    final lambda = (-g + math.sqrt(g * g - 4.0 * a * c)) / (2.0 * a);
    final x4 = x3 + lambda * _cos;
    final y4 = y3 + lambda * _sin;
    final x5 = x6 - lambda * _sin;
    final y5 = y6 - lambda * _cos;

    return [x0, 0.0, x1, 0.0, x2, 0.0, x3, y3, x4, y4, x5, y5, x6, y6, 1.0, y7, 1.0, y8, 1.0, y9];
  }

  /// 不等边角（宽高方向圆角占比不同）的控制点
  List<double> _buildUnevenCornerBezierPoints(double tH, double tV) {
    final kH = extendedFraction * tH;
    final kV = extendedFraction * tV;

    final kappa3 = _solveCubicSingle(_k3, _k2, _k1 + 8.0 * (-kH) * _sin3 * _sin, _k0);
    final kappa6 = _solveCubicSingle(_k3, _k2, _k1 + 8.0 * (-kV) * _sin3 * _sin, _k0);

    final x3 = _frac1Sqrt2 + (-_frac1Sqrt2 + _sin) / kappa3;
    final y3 = 1.0 - _frac1Sqrt2 + (_frac1Sqrt2 - _cos) / kappa3;
    final x2 = x3 - y3 * _cot;
    final x1 = x2 - (1.5 * kappa3 * y3 * y3) / _sin3;
    final x0 = -kH;

    final x3p = _frac1Sqrt2 + (-_frac1Sqrt2 + _sin) / kappa6;
    final y3p = 1.0 - _frac1Sqrt2 + (_frac1Sqrt2 - _cos) / kappa6;
    final x2p = x3p - y3p * _cot;
    final x1p = x2p - (1.5 * kappa6 * y3p * y3p) / _sin3;
    final x0p = -kV;
    final x6 = 1.0 - y3p;
    final y6 = 1.0 - x3p;
    final y7 = 1.0 - x2p;
    final y8 = 1.0 - x1p;
    final y9 = 1.0 - x0p;

    final a = 1.5 * kappa3;
    final b = 1.5 * kappa6;
    final g = _cos2 - _sin2;
    final x36 = x6 - x3;
    final y36 = y6 - y3;
    final c = -(_cos * y36 - _sin * x36);
    final d = _sin * y36 - _cos * x36;
    final p = 2.0 * (d / b);
    final q = (g * g * g) / (a * b * b);
    final r = (a * d * d + c * g * g) / (a * b * b);
    final lambda6 = _solveDepressedQuarticSingle(p, q, r);
    final lambda3 = (-d - b * lambda6 * lambda6) / g;
    final x4 = x3 + lambda3 * _cos;
    final y4 = y3 + lambda3 * _sin;
    final x5 = x6 - lambda6 * _sin;
    final y5 = y6 - lambda6 * _cos;

    return [x0, 0.0, x1, 0.0, x2, 0.0, x3, y3, x4, y4, x5, y5, x6, y6, 1.0, y7, 1.0, y8, 1.0, y9];
  }

  /// 返回一个角的 20 个贝塞尔控制点（10 对 x,y）。
  /// [tW] = （宽/2 - r）/ r 被 clamp 到 [0,1]，[tV] 同理。
  List<double> getCornerBezierPoints(double tW, double tV) {
    final i = tW == 0.0 ? 0 : (tW == 1.0 ? 1 : -1);
    final j = tV == 0.0 ? 0 : (tV == 1.0 ? 1 : -1);
    if (i >= 0 && j >= 0) {
      if (i == 0 && j == 0) return _buildEvenCornerBezierPoints(0.0);
      if (i == 1 && j == 1) return _buildEvenCornerBezierPoints(1.0);
      return _buildUnevenCornerBezierPoints(i == 1 ? 1.0 : 0.0, j == 1 ? 1.0 : 0.0);
    }
    return _buildUnevenCornerBezierPoints(
        tW.clamp(0.0, 1.0).toDouble(), tV.clamp(0.0, 1.0).toDouble());
  }
}

/// 构建 G2 连续曲率圆角矩形 [Path]，中心位于 (w/2, h/2)。
/// 忠实移植 `continuousCurvatureRoundedRectanglePath()`（RoundedRectangleOutline.kt）。
Path continuousCurvatureRoundedRectPath(double w, double h, double radius) {
  final builder = ContinuousCurvatureRoundedRectangleCornerBuilder();
  final r = radius.toDouble();
  final tW = ((w * 0.5 - r) / r).clamp(0.0, 1.0).toDouble();
  final tH = ((h * 0.5 - r) / r).clamp(0.0, 1.0).toDouble();
  final p = builder.getCornerBezierPoints(tW, tH);

  final path = Path();

  void corner1() {
    // 右上角 (x=w-r, y=0)
    final x = w - r, y = 0.0;
    path.moveTo(x + p[0] * r, y + p[1] * r);
    path.cubicTo(x + p[2] * r, y + p[3] * r, x + p[4] * r, y + p[5] * r, x + p[6] * r, y + p[7] * r);
    path.cubicTo(x + p[8] * r, y + p[9] * r, x + p[10] * r, y + p[11] * r, x + p[12] * r, y + p[13] * r);
    path.cubicTo(x + p[14] * r, y + p[15] * r, x + p[16] * r, y + p[17] * r, x + p[18] * r, y + p[19] * r);
  }

  void corner2() {
    // 右下角 (x=w-r, y=h)
    final x = w - r, y = h;
    path.lineTo(x + p[18] * r, y - p[19] * r);
    path.cubicTo(x + p[16] * r, y - p[17] * r, x + p[14] * r, y - p[15] * r, x + p[12] * r, y - p[13] * r);
    path.cubicTo(x + p[10] * r, y - p[11] * r, x + p[8] * r, y - p[9] * r, x + p[6] * r, y - p[7] * r);
    path.cubicTo(x + p[4] * r, y - p[5] * r, x + p[2] * r, y - p[3] * r, x + p[0] * r, y - p[1] * r);
  }

  void corner3() {
    // 左下角 (x=r, y=h)
    final x = r, y = h;
    path.lineTo(x - p[0] * r, y - p[1] * r);
    path.cubicTo(x - p[2] * r, y - p[3] * r, x - p[4] * r, y - p[5] * r, x - p[6] * r, y - p[7] * r);
    path.cubicTo(x - p[8] * r, y - p[9] * r, x - p[10] * r, y - p[11] * r, x - p[12] * r, y - p[13] * r);
    path.cubicTo(x - p[14] * r, y - p[15] * r, x - p[16] * r, y - p[17] * r, x - p[18] * r, y - p[19] * r);
  }

  void corner4() {
    // 左上角 (x=r, y=0)
    final x = r, y = 0.0;
    path.lineTo(x - p[18] * r, y + p[19] * r);
    path.cubicTo(x - p[16] * r, y + p[17] * r, x - p[14] * r, y + p[15] * r, x - p[12] * r, y + p[13] * r);
    path.cubicTo(x - p[10] * r, y + p[11] * r, x - p[8] * r, y + p[9] * r, x - p[6] * r, y + p[7] * r);
    path.cubicTo(x - p[4] * r, y + p[5] * r, x - p[2] * r, y + p[3] * r, x - p[0] * r, y + p[1] * r);
  }

  corner1();
  corner2();
  corner3();
  corner4();
  path.close();
  return path;
}