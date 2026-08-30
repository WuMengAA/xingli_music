import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'continuous_curve.dart';

/// ───────────────────────────────────────────────────────────────────────
/// G2 连续曲率圆角 SDF 纹理生成器
///
/// 移植自 martin65536/liquid-glass-webgl 的 `continuous-sdf.ts`：
/// 1. 把 G2 圆角矩形光栅化成 alpha mask（上游用 Canvas2D fill）
/// 2. 用 chamfer 距离变换（3-4-5 核，两遍扫描）算出符号距离场
/// 3. 归一化到 [-1,1]（负 = 内侧，正 = 外侧），存为单通道纹理
///
/// 下游 shader 采样方式与 sdRoundedRect 一致（负内正外、边缘为 0），
/// 但角形是精确的 G2 连续贝塞尔，而非普通圆角。
/// 按 (w, h, radius) 缓存 —— 对话框卡片（固定尺寸）只生成一次。
/// ───────────────────────────────────────────────────────────────────────

/// 从 alpha mask 计算符号距离场（纯 Dart，可单测）。
///
/// [alpha] 长度 texSize²，>128 视为内侧像素。
/// 返回 texSize² 个归一化到 [-1, 1] 的 SDF 值（负内正外）。
/// [refDistancePx] 归一化参考距离（上游用「绘制半径 × scale」）。
List<double> chamferSignedDistanceField(
  List<int> alpha,
  int texSize, {
  required double refDistancePx,
}) {
  const double inf = 1e10;
  final inside = List<double>.filled(texSize * texSize, 0);
  final outside = List<double>.filled(texSize * texSize, 0);

  for (var i = 0; i < texSize * texSize; i++) {
    if (alpha[i] > 128) {
      inside[i] = 0;
      outside[i] = inf;
    } else {
      inside[i] = inf;
      outside[i] = 0;
    }
  }

  // 前向扫描：左上 → 右下（3-4-5 核）
  for (var y = 0; y < texSize; y++) {
    for (var x = 0; x < texSize; x++) {
      final idx = y * texSize + x;
      if (x > 0) {
        inside[idx] = math.min(inside[idx], inside[idx - 1] + 3);
        outside[idx] = math.min(outside[idx], outside[idx - 1] + 3);
      }
      if (y > 0) {
        inside[idx] = math.min(inside[idx], inside[idx - texSize] + 3);
        outside[idx] = math.min(outside[idx], outside[idx - texSize] + 3);
      }
      if (x > 0 && y > 0) {
        inside[idx] = math.min(inside[idx], inside[idx - texSize - 1] + 4);
        outside[idx] = math.min(outside[idx], outside[idx - texSize - 1] + 4);
      }
      if (x < texSize - 1 && y > 0) {
        inside[idx] = math.min(inside[idx], inside[idx - texSize + 1] + 4);
        outside[idx] = math.min(outside[idx], outside[idx - texSize + 1] + 4);
      }
    }
  }
  // 后向扫描：右下 → 左上
  for (var y = texSize - 1; y >= 0; y--) {
    for (var x = texSize - 1; x >= 0; x--) {
      final idx = y * texSize + x;
      if (x < texSize - 1) {
        inside[idx] = math.min(inside[idx], inside[idx + 1] + 3);
        outside[idx] = math.min(outside[idx], outside[idx + 1] + 3);
      }
      if (y < texSize - 1) {
        inside[idx] = math.min(inside[idx], inside[idx + texSize] + 3);
        outside[idx] = math.min(outside[idx], outside[idx + texSize] + 3);
      }
      if (x < texSize - 1 && y < texSize - 1) {
        inside[idx] = math.min(inside[idx], inside[idx + texSize + 1] + 4);
        outside[idx] = math.min(outside[idx], outside[idx + texSize + 1] + 4);
      }
      if (x > 0 && y < texSize - 1) {
        inside[idx] = math.min(inside[idx], inside[idx + texSize - 1] + 4);
        outside[idx] = math.min(outside[idx], outside[idx + texSize - 1] + 4);
      }
    }
  }

  // 合并成符号距离：内侧像素 → sd = inside - outside = 负；外侧正。
  // 除以 3（3-4-5 核的步长权重基准），再按 refDistancePx 归一化到 [-1,1]。
  final sdf = List<double>.filled(texSize * texSize, 0);
  for (var i = 0; i < texSize * texSize; i++) {
    final sd = (inside[i] - outside[i]) / 3.0;
    sdf[i] = (sd / refDistancePx).clamp(-1.0, 1.0).toDouble();
  }
  return sdf;
}

/// 关键帧缓存：同一 (w, h, radius, texSize) 只生成一次。
final Map<String, SdfTexture> _sdfCache = {};

/// 一张 SDF 纹理：单通道 float32 值 + 尺寸。
class SdfTexture {
  final int texSize;
  final List<double> values; // texSize²，[-1,1]，负内正外
  final double radiusPx; // 元素空间内的圆角半径

  const SdfTexture({
    required this.texSize,
    required this.values,
    required this.radiusPx,
  });

  /// 采样（双线性）归一化坐标 (u, v) ∈ [0,1]。
  double sample(double u, double v) {
    final x = u * (texSize - 1);
    final y = v * (texSize - 1);
    final x0 = x.floor().clamp(0, texSize - 1);
    final y0 = y.floor().clamp(0, texSize - 1);
    final x1 = (x0 + 1).clamp(0, texSize - 1);
    final y1 = (y0 + 1).clamp(0, texSize - 1);
    final fx = x - x0;
    final fy = y - y0;
    final v00 = values[y0 * texSize + x0];
    final v10 = values[y0 * texSize + x1];
    final v01 = values[y1 * texSize + x0];
    final v11 = values[y1 * texSize + x1];
    return v00 * (1 - fx) * (1 - fy) +
        v10 * fx * (1 - fy) +
        v01 * (1 - fx) * fy +
        v11 * fx * fy;
  }
}

/// 由 [SdfTexture] 生成 RGBA8 纹理字节（R 通道 = 归一化 SDF [0,255]）。
/// 可与 dart:ui `ImageDescriptor.raw` 搭配生成 FragmentShader 可采样的纹理。
Uint8List sdfToRgba8(SdfTexture tex) {
  final bytes = Uint8List(tex.texSize * tex.texSize * 4);
  for (var i = 0; i < tex.values.length; i++) {
    final v = ((tex.values[i] * 0.5 + 0.5) * 255).round().clamp(0, 255);
    bytes[i * 4] = v;
    bytes[i * 4 + 1] = v;
    bytes[i * 4 + 2] = v;
    bytes[i * 4 + 3] = 255;
  }
  return bytes;
}

/// 生成 G2 圆角矩形的 SDF 纹理。
///
/// [w]/[h] 为元素逻辑尺寸，[radius] 圆角半径（逻辑 px），
/// [texSize] 纹理边长（默认按元素尺寸自适应，范围 256..1024）。
/// alpha mask 用 Flutter Canvas 光栅化 G2 路径（GPU 精确三角化）。
Future<SdfTexture> generateContinuousCurvatureSdf({
  required double w,
  required double h,
  required double radius,
  int? texSizeOverride,
}) async {
  final texSize = texSizeOverride ??
      math.min(1024, math.max(256, (math.max(w, h) * 1).round()));
  final key = '$w,$h,$radius,$texSize';
  final cached = _sdfCache[key];
  if (cached != null) return cached;

  final maxDim = math.max(w, h);
  final aspectW = w / maxDim;
  final aspectH = h / maxDim;

  // 光栅化 G2 圆角路径到 texSize² 画布，留 4px margin 供外侧距离。
  final margin = 4;
  final drawW = (texSize - 2 * margin) * aspectW;
  final drawH = (texSize - 2 * margin) * aspectH;
  final offsetX = (texSize - drawW) / 2;
  final offsetY = (texSize - drawH) / 2;
  final scale = drawW / w;
  final drawRadius = radius * scale;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final path = continuousCurvatureRoundedRectPath(drawW, drawH, drawRadius);
  canvas.translate(offsetX, offsetY);
  canvas.drawPath(path, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(texSize, texSize);
  final byteData = await image.toByteData();
  image.dispose();

  // 提取 alpha mask（RGBA → 单通道）
  final alpha = List<int>.filled(texSize * texSize, 0);
  if (byteData != null) {
    for (var i = 0; i < texSize * texSize; i++) {
      alpha[i] = byteData.getUint8(i * 4 + 3);
    }
  }

  final values = chamferSignedDistanceField(alpha, texSize,
      refDistancePx: drawRadius);
  final tex = SdfTexture(texSize: texSize, values: values, radiusPx: radius);
  _sdfCache[key] = tex;
  return tex;
}

/// 测试辅助：清空 SDF 缓存。
void clearSdfCache() => _sdfCache.clear();