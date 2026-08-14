import 'dart:typed_data';

/// 曲目音乐包络（离线预分析产物）。
///
/// 按帧存储「多频段能量」+「节拍强度」，供 2.5D 可视化按播放位置采样驱动。
/// 由 [EnvelopeAnalyzer] 经 ffmpeg 解码 + FFT 生成；二进制序列化后按曲目缓存。
///
/// 数据布局（行优先）：
///   `bands` 长度 == [frameCount] × [bandCount]，第 f 帧频段 = `bands[f*bandCount + b]`。
///   `beat`  长度 == [frameCount]，第 f 帧节拍强度 0~1。
class MusicEnvelope {
  const MusicEnvelope({
    required this.durationMs,
    required this.fps,
    required this.bandCount,
    required this.bands,
    required this.beat,
  });

  /// 曲目时长（ms）。
  final double durationMs;

  /// 采样帧率（帧/秒）。
  final int fps;

  /// 频段数量（低频→高频）。
  final int bandCount;

  /// 多频段能量，行优先，值 0~1。
  final Float32List bands;

  /// 节拍强度，0~1。
  final Float32List beat;

  int get frameCount => beat.length;

  /// 帧间隔（ms）。
  double get frameMs => 1000.0 / fps;

  /// 按播放位置（ms）采样多频段能量（线性插值），返回长度 [bandCount] 的列表。
  List<double> sampleBands(double ms) {
    final double pos = ms.clamp(0.0, durationMs);
    final double f = pos / frameMs;
    final int i0 = f.floor().clamp(0, frameCount - 1);
    final int i1 = (i0 + 1).clamp(0, frameCount - 1);
    final double t = (f - i0).clamp(0.0, 1.0);
    final List<double> out = List<double>.filled(bandCount, 0.0);
    for (int b = 0; b < bandCount; b++) {
      final double v0 = bands[i0 * bandCount + b];
      final double v1 = bands[i1 * bandCount + b];
      out[b] = v0 + (v1 - v0) * t;
    }
    return out;
  }

  /// 按播放位置（ms）采样节拍强度（线性插值），0~1。
  double sampleBeat(double ms) {
    final double pos = ms.clamp(0.0, durationMs);
    final double f = pos / frameMs;
    final int i0 = f.floor().clamp(0, frameCount - 1);
    final int i1 = (i0 + 1).clamp(0, frameCount - 1);
    final double t = (f - i0).clamp(0.0, 1.0);
    return beat[i0] + (beat[i1] - beat[i0]) * t;
  }

  /// 当前整体能量（所有频段均值，0~1），驱动亮度/呼吸。
  double sampleLevel(double ms) {
    final List<double> b = sampleBands(ms);
    if (b.isEmpty) return 0.0;
    double s = 0.0;
    for (final double v in b) {
      s += v;
    }
    return s / b.length;
  }

  // ── 紧凑二进制序列化（缓存用）─────────────────────────
  // 头部：durationMs(f64) | fps(i32) | bandCount(i32) | frameCount(i32)
  // 主体：bands(frameCount*bandCount × f32) | beat(frameCount × f32)
  Uint8List encode() {
    final int fc = frameCount;
    final ByteData bd = ByteData(24 + (fc * bandCount + fc) * 4);
    bd.setFloat64(0, durationMs, Endian.little);
    bd.setInt32(8, fps, Endian.little);
    bd.setInt32(12, bandCount, Endian.little);
    bd.setInt32(16, fc, Endian.little);
    int off = 24;
    for (int i = 0; i < fc * bandCount; i++) {
      bd.setFloat32(off, bands[i], Endian.little);
      off += 4;
    }
    for (int i = 0; i < fc; i++) {
      bd.setFloat32(off, beat[i], Endian.little);
      off += 4;
    }
    return bd.buffer.asUint8List(0, off);
  }

  /// 仅接受合法格式；损坏/版本不符返回 null（不抛）。
  static MusicEnvelope? decode(Uint8List bytes) {
    try {
      if (bytes.lengthInBytes < 24) return null;
      final ByteData bd = ByteData.sublistView(bytes);
      final double durationMs = bd.getFloat64(0, Endian.little);
      final int fps = bd.getInt32(8, Endian.little);
      final int bandCount = bd.getInt32(12, Endian.little);
      final int fc = bd.getInt32(16, Endian.little);
      final int need = 24 + (fc * bandCount + fc) * 4;
      if (fps <= 0 || bandCount <= 0 || fc <= 0) return null;
      if (bytes.lengthInBytes < need) return null;
      int off = 24;
      final Float32List bands = Float32List(fc * bandCount);
      for (int i = 0; i < fc * bandCount; i++) {
        bands[i] = bd.getFloat32(off, Endian.little);
        off += 4;
      }
      final Float32List beat = Float32List(fc);
      for (int i = 0; i < fc; i++) {
        beat[i] = bd.getFloat32(off, Endian.little);
        off += 4;
      }
      return MusicEnvelope(
        durationMs: durationMs,
        fps: fps,
        bandCount: bandCount,
        bands: bands,
        beat: beat,
      );
    } catch (_) {
      return null;
    }
  }
}
