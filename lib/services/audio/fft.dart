import 'dart:math' as math;
import 'dart:typed_data';

/// 原地迭代 radix-2 Cooley-Tukey FFT。
///
/// [re]/[im] 长度必须为 2 的幂（不足调用方负责零填充）。
/// 计算结果（复数频谱）写回同一数组。
void fftRadix2(Float64List re, Float64List im) {
  final int n = re.length;
  if (n <= 1) return;

  // 位反转置换
  int j = 0;
  for (int i = 1; i < n; i++) {
    int bit = n >> 1;
    while (j & bit != 0) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;
    if (i < j) {
      final double tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final double ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  // 蝶形运算
  for (int len = 2; len <= n; len <<= 1) {
    final double ang = -2.0 * math.pi / len;
    final double wpr = math.cos(ang);
    final double wpi = math.sin(ang);
    final int halfLen = len ~/ 2;
    for (int i = 0; i < n; i += len) {
      double wr = 1.0;
      double wi = 0.0;
      for (int k = 0; k < halfLen; k++) {
        final int a = i + k;
        final int b = a + halfLen;
        final double xr = re[b] * wr - im[b] * wi;
        final double xi = re[b] * wi + im[b] * wr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final double nwr = wr * wpr - wi * wpi;
        final double nwi = wr * wpi + wi * wpr;
        wr = nwr;
        wi = nwi;
      }
    }
  }
}
