import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'music_envelope.dart';

/// 离线音频分析不可用（无 ffmpeg / 解码失败 / 流媒体）→ 调用方应降级到合成 [VisualizerService]。
class EnvelopeUnavailable implements Exception {
  const EnvelopeUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'EnvelopeUnavailable: $reason';
}

/// 离线音频包络分析器。
///
/// 用 ffmpeg 将音频解码为 raw Int16 PCM → Dart 侧分帧加窗 → radix-2 FFT →
/// 对数分布频段能量 + 低频通量节拍检测 → [MusicEnvelope]。
/// 结果由 [EnvelopeCache] 按曲目路径哈希缓存，跨会话复用。
class EnvelopeAnalyzer {
  const EnvelopeAnalyzer({
    this.bandCount = 16,
    this.fps = 24,
    this.sampleRate = 22050,
    this.fftSize = 1024,
  });

  final int bandCount;
  final int fps;
  final int sampleRate;
  final int fftSize;

  /// 解码并分析单个音频文件。
  ///
  /// [ffmpegPath] 可显式传入；为空则运行时解析（PATH / `where`）。
  /// 流媒体（非本地文件）不应调用本方法 —— 由上层判断后降级。
  Future<MusicEnvelope> analyze(String filePath, {String? ffmpegPath}) async {
    final File f = File(filePath);
    if (!f.existsSync()) {
      throw EnvelopeUnavailable('文件不存在: $filePath');
    }
    final String ff = ffmpegPath ?? await _resolveFfmpeg();
    if (ff.isEmpty) {
      throw const EnvelopeUnavailable('ffmpeg 不可用');
    }
    final ProcessResult res = await Process.run(ff, <String>[
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      filePath,
      '-f',
      's16le',
      '-ac',
      '1',
      '-ar',
      sampleRate.toString(),
      '-vn',
      'pipe:1',
    ], stdoutEncoding: null);
    if (res.exitCode != 0) {
      throw EnvelopeUnavailable('ffmpeg 退出码 ${res.exitCode}');
    }
    final Uint8List pcm = res.stdout as Uint8List;
    if (pcm.lengthInBytes < 4) {
      throw const EnvelopeUnavailable('解码输出为空');
    }
    return _analyzePcm(pcm, sampleRate);
  }

  MusicEnvelope _analyzePcm(Uint8List pcmBytes, int sr) {
    final int sampleCount = pcmBytes.lengthInBytes ~/ 2;
    final Int16List pcm = Int16List(sampleCount);
    final ByteData bd = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < sampleCount; i++) {
      pcm[i] = bd.getInt16(i * 2, Endian.little);
    }
    final double durationMs = sampleCount / sr * 1000.0;
    final int frameCount =
        math.max(1, (durationMs / 1000.0 * fps).round());
    final int hop = math.max(1, (sr / fps).round());
    final int half = fftSize ~/ 2;
    final int binHz = sr ~/ fftSize;

    // 频段边界（对数分布 20Hz ~ sr/2）
    final double minF = 20.0;
    final double maxF = sr / 2.0;
    final List<double> bandEdges = List<double>.generate(bandCount + 1, (i) {
      return minF * math.pow(maxF / minF, i / bandCount);
    });

    // 每帧原始频段能量（两遍：先采集，再按每频段全局最大值归一化）
    final List<List<double>> bandRaw =
        List<List<double>>.generate(frameCount, (_) => List<double>.filled(bandCount, 0.0));
    final List<double> lowEnergy = List<double>.filled(frameCount, 0.0);

    final Float64List re = Float64List(fftSize);
    final Float64List im = Float64List(fftSize);
    final Float64List mag = Float64List(half);

    for (int f = 0; f < frameCount; f++) {
      final int start =
          (f * hop).clamp(0, math.max(0, sampleCount - fftSize));
      for (int i = 0; i < fftSize; i++) {
        final int idx = start + i;
        final double s = idx < sampleCount ? pcm[idx] / 32768.0 : 0.0;
        final double w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (fftSize - 1));
        re[i] = s * w;
        im[i] = 0.0;
      }
      fftRadix2(re, im);
      for (int k = 0; k < half; k++) {
        final double m = math.sqrt(re[k] * re[k] + im[k] * im[k]);
        mag[k] = m;
      }
      for (int b = 0; b < bandCount; b++) {
        final int k0 = (bandEdges[b] / binHz).floor().clamp(0, half - 1);
        final int k1 =
            (bandEdges[b + 1] / binHz).ceil().clamp(k0 + 1, half);
        double e = 0.0;
        for (int k = k0; k < k1; k++) {
          e += mag[k];
        }
        e /= (k1 - k0);
        bandRaw[f][b] = e;
      }
      // 低频能量（节拍代理：前两段的能量和）
      final int lowK1 = (bandEdges[2] / binHz).ceil().clamp(1, half);
      double low = 0.0;
      for (int k = 0; k < lowK1; k++) {
        low += mag[k];
      }
      lowEnergy[f] = low;
    }

    // 每频段全局最大值 → 归一化（相对该曲目该频段的最强帧 = 1）
    final List<double> bandMax = List<double>.filled(bandCount, 1e-9);
    for (int f = 0; f < frameCount; f++) {
      for (int b = 0; b < bandCount; b++) {
        if (bandRaw[f][b] > bandMax[b]) bandMax[b] = bandRaw[f][b];
      }
    }
    final Float32List bands = Float32List(frameCount * bandCount);
    for (int f = 0; f < frameCount; f++) {
      for (int b = 0; b < bandCount; b++) {
        final double norm = bandRaw[f][b] / bandMax[b];
        bands[f * bandCount + b] = math.pow(norm, 0.6).toDouble().clamp(0.0, 1.0);
      }
    }
    _smoothBands(bands, frameCount, bandCount);

    // 节拍：低频能量正向通量 + 自适应峰值归一化
    final Float32List beat = _detectBeats(lowEnergy);

    return MusicEnvelope(
      durationMs: durationMs,
      fps: fps,
      bandCount: bandCount,
      bands: bands,
      beat: beat,
    );
  }

  /// 低频能量 → 节拍脉冲（0~1 的 onset 尖峰）。
  Float32List _detectBeats(List<double> low) {
    final int n = low.length;
    final Float32List flux = Float32List(n);
    for (int f = 1; f < n; f++) {
      flux[f] = math.max(0.0, low[f] - low[f - 1]);
    }
    // 自适应运行最大值（慢衰减）→ 归一化
    final Float32List beat = Float32List(n);
    double runMax = 1e-6;
    for (int f = 0; f < n; f++) {
      runMax = math.max(runMax * 0.98, flux[f]);
      beat[f] = (flux[f] / runMax).clamp(0.0, 1.0);
    }
    // 轻微时间平滑（3 帧）
    final Float32List out = Float32List(n);
    for (int f = 0; f < n; f++) {
      double s = 0.0;
      int c = 0;
      for (int k = f - 1; k <= f + 1; k++) {
        if (k >= 0 && k < n) {
          s += beat[k];
          c++;
        }
      }
      out[f] = s / c;
    }
    return out;
  }

  /// 频段能量时间维平滑（每频段独立，小窗口）减少抖动。
  void _smoothBands(Float32List bands, int frameCount, int bandCount) {
    final Float32List tmp = Float32List.fromList(bands);
    for (int b = 0; b < bandCount; b++) {
      for (int f = 0; f < frameCount; f++) {
        double s = 0.0;
        int c = 0;
        for (int k = f - 1; k <= f + 1; k++) {
          if (k >= 0 && k < frameCount) {
            s += tmp[k * bandCount + b];
            c++;
          }
        }
        bands[f * bandCount + b] = s / c;
      }
    }
  }

  /// 运行时解析 ffmpeg 可执行文件路径。找不到返回空串（由调用方降级）。
  static Future<String> _resolveFfmpeg() async {
    // 1) 直接尝试 PATH
    try {
      final ProcessResult r = await Process.run('ffmpeg', <String>['-version']);
      if (r.exitCode == 0) return 'ffmpeg';
    } catch (_) {
      // 命令不存在，继续
    }
    // 2) Windows: where 查找（含 WinGet Links）
    try {
      final ProcessResult r = await Process.run('where', <String>['ffmpeg']);
      if (r.exitCode == 0) {
        final String out = (r.stdout as String).trim();
        if (out.isNotEmpty) return out.split(RegExp(r'[\r\n]')).first.trim();
      }
    } catch (_) {
      // ignore
    }
    return '';
  }
}
