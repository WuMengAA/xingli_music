/// ════════════════════════════════════════════════════════════════════════
/// 空间音效 · 合成引擎（SpatialSynth）
/// ════════════════════════════════════════════════════════════════════════
///
/// 统一噪音合成：为 [SpatialTrack] 合成 16bit PCM WAV（22050Hz 单声道），
/// 按音轨 id 区分声源类型：
///  - `water`      ：水方块流动（低频水流 + 偶发水泡）
///  - `fireplace`  ：篝火持久音（低频底噪 + 随机噼啪）
///  - `furnace`    ：熔炉持久音（低频嗡鸣 + 偶发咕噜）
///  - `wind`/`rain`/`cave`：沿用场景合成器同款风格（复用算法）
///
/// 输出为单声道 PCM，由 [SpatialMixer] 按声道布局混入左右声道。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 合成器：生成某音轨的 PCM 采样（-32768..32767）。
class SpatialSynth {
  static const int sampleRate = 22050;

  /// 每轨默认时长（秒），循环播放。
  static const double seconds = 24;

  /// 按合成 id 生成 PCM。
  ///
  /// [seed] 保证同 id 每次结果一致（可缓存）。
  static Uint8List synthesizeWav(String synthId, {int seed = 0}) {
    final math.Random rng = math.Random(seed * 31 + synthId.hashCode);
    final int n = (sampleRate * seconds).round();
    final List<double> buf = List<double>.filled(n, 0);

    switch (synthId) {
      case 'water':
        _water(buf, rng);
      case 'fireplace':
        _fireplace(buf, rng);
      case 'furnace':
        _furnace(buf, rng);
      case 'rain':
        _rain(buf, rng);
      case 'wind':
        _wind(buf, rng);
      case 'cave':
        _cave(buf, rng);
      default:
        _water(buf, rng);
    }

    _loopEnvelope(buf);
    return _encodeWav(_normalize(buf));
  }

  // ── 合成器 ───────────────────────────────────────────

  /// 水：低频水流 + 偶发水泡（松软流动感）。
  static void _water(List<double> buf, math.Random rng) {
    double brown = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      brown = (brown + 0.03 * white) / 1.03;
      final double t = i / sampleRate;
      final double ripple = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 0.35);
      buf[i] += brown * 2.2 * (0.4 + ripple * 0.6);
      // 偶发水泡
      if (rng.nextDouble() < 0.0006) {
        for (int k = 0; k < 120 && i + k < buf.length; k++) {
          buf[i + k] += (rng.nextDouble() * 2 - 1) * 0.18 * (1 - k / 120);
        }
      }
    }
  }

  /// 篝火：低频底噪 + 随机噼啪。
  static void _fireplace(buf, math.Random rng) {
    double brown = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      brown = (brown + 0.02 * white) / 1.02;
      buf[i] += brown * 2.5;
      if (rng.nextDouble() < 0.0035) {
        final int len = 6 + rng.nextInt(20);
        for (int k = 0; k < len && i + k < buf.length; k++) {
          buf[i + k] += (rng.nextDouble() * 2 - 1) * 0.5 * (1 - k / len);
        }
      }
    }
  }

  /// 熔炉：低频嗡鸣 + 偶发咕噜。
  static void _furnace(buf, math.Random rng) {
    for (int i = 0; i < buf.length; i++) {
      final double t = i / sampleRate;
      // 55Hz 基底 + 轻微失谐
      buf[i] += math.sin(2 * math.pi * 55 * t) * 0.12;
      buf[i] += math.sin(2 * math.pi * 55.3 * t) * 0.08;
      buf[i] += math.sin(2 * math.pi * 110 * t) * 0.04;
      // 偶发咕噜（低频脉冲）
      if (rng.nextDouble() < 0.0012) {
        final int len = 200 + rng.nextInt(300);
        for (int k = 0; k < len && i + k < buf.length; k++) {
          final double env = math.sin(math.pi * k / len);
          buf[i + k] += math.sin(2 * math.pi * 40 * k / sampleRate) * 0.15 * env;
        }
      }
    }
  }

  /// 雨：高通白噪。
  static void _rain(buf, math.Random rng) {
    double prev = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      prev = white - prev * 0.92;
      buf[i] += prev * 0.5;
    }
  }

  /// 风：低频布朗噪声。
  static void _wind(buf, math.Random rng) {
    double brown = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      brown = (brown + 0.02 * white) / 1.02;
      final double lfo = 0.6 + 0.4 * math.sin(i / sampleRate * 2 * math.pi * 0.08);
      buf[i] += brown * 0.35 * lfo * 4;
    }
  }

  /// 洞穴：低沉双音。
  static void _cave(buf, math.Random rng) {
    for (int i = 0; i < buf.length; i++) {
      final double t = i / sampleRate;
      buf[i] += math.sin(2 * math.pi * 55 * t) * 0.05;
      buf[i] += math.sin(2 * math.pi * 55.5 * t) * 0.05;
    }
  }

  // ── 工具 ───────────────────────────────────────────

  static void _loopEnvelope(List<double> buf) {
    final int fade = (sampleRate * 1.5).round();
    for (int i = 0; i < fade && i < buf.length; i++) {
      buf[i] *= i / fade;
    }
    for (int i = buf.length - 1; i > buf.length - 1 - fade && i >= 0; i--) {
      buf[i] *= (buf.length - 1 - i) / fade;
    }
  }

  static List<int> _normalize(List<double> buf) {
    double peak = 0;
    for (final double v in buf) {
      if (v.abs() > peak) peak = v.abs();
    }
    final double gain = peak > 0 ? 0.8 / peak : 1.0;
    return buf
        .map((v) => (v * gain * 32767).round().clamp(-32768, 32767))
        .toList();
  }

  static Uint8List _encodeWav(List<int> samples) {
    final ByteData data = ByteData(44 + samples.length * 2);
    void writeStr(int o, String s) {
      for (int i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    writeStr(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (int i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
