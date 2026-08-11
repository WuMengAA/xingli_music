import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 场景音景生成器：程序化合成氛围声（雨/森林/壁炉/海浪…）
///
/// 生成 16bit PCM WAV（22050Hz 单声道，30 秒循环），
/// 写入应用文档目录，之后随场景循环播放。
/// 不依赖任何版权素材——所有声音由算法实时生成。
class SoundscapeGenerator {
  static const int sampleRate = 22050;

  /// 生成逻辑版本号：改合成算法时 +1，避免旧缓存文件生效
  static const int version = 2;

  /// 循环淡入淡出时长（秒）：首尾各一段包络，循环时不突兀
  static const double loopFadeSeconds = 2.0;

  /// 获取某场景的音景文件路径（缓存已生成的文件，无则生成）
  ///
  /// 合成在后台 isolate（compute）执行，不阻塞主线程/UI。
  static Future<String> ensureSceneSoundscape(String sceneId) async {
    final File file = await _fileFor(sceneId);
    if (await file.exists()) return file.path;

    final Uint8List wav = await compute(_synthesizeToWav, sceneId);
    await file.writeAsBytes(wav, flush: true);
    return file.path;
  }

  /// 白噪音文件（R4：全局白噪音开关用，独立于场景音景）
  ///
  /// 30 秒纯白噪声 + 首尾淡入淡出，独立文件，可叠加在音乐之上。
  static Future<String> ensureWhiteNoise() async {
    const String id = '__whitenoise__';
    final File file = await _fileFor(id);
    if (await file.exists()) return file.path;
    final Uint8List wav = await compute(_synthesizeWhiteNoise, 0);
    await file.writeAsBytes(wav, flush: true);
    return file.path;
  }

  /// compute 入口：白噪声合成（后台 isolate）
  static Uint8List _synthesizeWhiteNoise(int _) {
    final Random rng = Random(7);
    final int n = sampleRate * 30;
    final List<double> buf = List<double>.filled(n, 0);
    double prev = 0;
    for (int i = 0; i < n; i++) {
      // 轻微低通滤波让白噪声更柔和（不再是刺耳的纯白）
      final double white = rng.nextDouble() * 2 - 1;
      prev = white - prev * 0.35;
      buf[i] = prev * 0.7;
    }
    // 循环包络
    final int fadeLen = (sampleRate * loopFadeSeconds).round();
    for (int i = 0; i < fadeLen && i < buf.length; i++) {
      buf[i] *= i / fadeLen;
    }
    for (int i = buf.length - 1; i > buf.length - 1 - fadeLen && i >= 0; i--) {
      buf[i] *= (buf.length - 1 - i) / fadeLen;
    }
    // 归一化
    double peak = 0;
    for (final double v in buf) {
      if (v.abs() > peak) peak = v.abs();
    }
    final double gain = peak > 0 ? 0.8 / peak : 1.0;
    return _encodeWav(
        buf.map((v) => (v * gain * 32767).round().clamp(-32768, 32767)).toList());
  }

  /// compute 入口：合成 + 编码为 WAV（在后台 isolate 运行）
  static Uint8List _synthesizeToWav(String sceneId) {
    final List<int> samples = _synthesize(sceneId);
    return _encodeWav(samples);
  }

  /// 后台预生成全部场景音景（不阻塞 UI；文件已存在则跳过）
  static Future<void> preGenerateAll(List<String> sceneIds) async {
    for (final String id in sceneIds) {
      try {
        await ensureSceneSoundscape(id);
      } catch (_) {
        // 单个场景生成失败不影响其余
      }
    }
  }

  static Future<File> _fileFor(String sceneId) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/soundscape_v${version}_$sceneId.wav');
  }

  /// 按场景合成 PCM 采样（-32768..32767）
  static List<int> _synthesize(String sceneId) {
    final Random rng = Random(42);
    final int n = sampleRate * 30; // 30 秒
    final List<double> buf = List<double>.filled(n, 0);

    switch (sceneId) {
      case 'rain':
        _addRain(buf, rng);
      case 'forest':
        _addWind(buf, rng, 0.35);
        _addBirds(buf, rng);
      case 'fireplace':
        _addFire(buf, rng);
      case 'dusk':
        _addWind(buf, rng, 0.25);
        _addChime(buf, rng);
      case 'snow':
        _addHiss(buf, rng, 0.12);
      case 'ocean':
        _addWaves(buf, rng);
      case 'starnight':
      default:
        _addDrone(buf);
        _addTwinkle(buf, rng);
    }

    // 循环包络：首尾淡入淡出，循环播放时无"接头"突兀
    final int fadeLen = (sampleRate * loopFadeSeconds).round();
    for (int i = 0; i < fadeLen && i < buf.length; i++) {
      buf[i] *= i / fadeLen;
    }
    for (int i = buf.length - 1; i > buf.length - 1 - fadeLen && i >= 0; i--) {
      buf[i] *= (buf.length - 1 - i) / fadeLen;
    }

    // 归一化到 0.85 峰值，避免削波
    double peak = 0;
    for (final double v in buf) {
      if (v.abs() > peak) peak = v.abs();
    }
    final double gain = peak > 0 ? 0.85 / peak : 1.0;
    return buf.map((v) => (v * gain * 32767).round().clamp(-32768, 32767)).toList();
  }

  // ── 合成器 ───────────────────────────────────────────

  /// 雨：高通白噪声 + 随机滴答
  static void _addRain(List<double> buf, Random rng) {
    double prev = 0;
    for (int i = 0; i < buf.length; i++) {
      // 高通一阶滤波（削减低频，得到"雨声"质感）
      final double white = rng.nextDouble() * 2 - 1;
      prev = white - prev * 0.92;
      buf[i] += prev * 0.5;
      // 偶尔雨滴
      if (rng.nextDouble() < 0.0004) {
        for (int k = 0; k < 200 && i + k < buf.length; k++) {
          buf[i + k] += (rng.nextDouble() * 2 - 1) * 0.6 * (1 - k / 200);
        }
      }
    }
  }

  /// 风：低频布朗噪声（slow drift）
  static void _addWind(List<double> buf, Random rng, double gain) {
    double brown = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      brown = (brown + 0.02 * white) / 1.02;
      // 用慢速 LFO 调制风的大小
      final double lfo = 0.6 + 0.4 * sin(i / sampleRate * 2 * pi * 0.08);
      buf[i] += brown * gain * lfo * 4;
    }
  }

  /// 鸟鸣：随机频率上滑音
  static void _addBirds(List<double> buf, Random rng) {
    for (int t = 0; t < 12; t++) {
      final int start = rng.nextInt(buf.length - sampleRate);
      final double f0 = 2500 + rng.nextDouble() * 2000;
      final int len = 120 + rng.nextInt(180);
      for (int k = 0; k < len && start + k < buf.length; k++) {
        final double f = f0 + (rng.nextDouble() - 0.5) * 800;
        buf[start + k] += sin(2 * pi * f * k / sampleRate) * 0.08;
      }
    }
  }

  /// 壁炉：低频底噪 + 噼啪爆裂
  static void _addFire(List<double> buf, Random rng) {
    double brown = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      brown = (brown + 0.02 * white) / 1.02;
      buf[i] += brown * 2.5;
      // 噼啪：随机短爆
      if (rng.nextDouble() < 0.0025) {
        final int len = 8 + rng.nextInt(24);
        for (int k = 0; k < len && i + k < buf.length; k++) {
          buf[i + k] += (rng.nextDouble() * 2 - 1) * 0.5 * (1 - k / len);
        }
      }
    }
  }

  /// 黄昏风铃：稀疏高音
  static void _addChime(List<double> buf, Random rng) {
    for (int t = 0; t < 6; t++) {
      final int start = rng.nextInt(buf.length - sampleRate);
      final double f = 900 + rng.nextDouble() * 600;
      for (int k = 0; k < sampleRate; k++) {
        if (start + k >= buf.length) break;
        final double decay = exp(-k / (sampleRate * 0.8));
        buf[start + k] += sin(2 * pi * f * k / sampleRate) * 0.1 * decay;
        buf[start + k] += sin(2 * pi * f * 2.01 * k / sampleRate) * 0.04 * decay;
      }
    }
  }

  /// 雪：极轻的高频嘶声
  static void _addHiss(List<double> buf, Random rng, double gain) {
    double prev = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      prev = white - prev * 0.8;
      buf[i] += prev * gain;
    }
  }

  /// 海浪：布朗噪声 + 慢速波浪包络
  static void _addWaves(List<double> buf, Random rng) {
    double brown = 0;
    for (int i = 0; i < buf.length; i++) {
      final double white = rng.nextDouble() * 2 - 1;
      brown = (brown + 0.015 * white) / 1.015;
      final double t = i / sampleRate;
      // 8 秒一个浪周期
      final double wave = pow(max(0, sin(t * 2 * pi / 8)), 3).toDouble();
      buf[i] += brown * 3 * (0.25 + wave);
    }
  }

  /// 星夜：低沉双音和弦
  static void _addDrone(List<double> buf) {
    for (int i = 0; i < buf.length; i++) {
      final double t = i / sampleRate;
      buf[i] += sin(2 * pi * 55 * t) * 0.05;
      buf[i] += sin(2 * pi * 55.5 * t) * 0.05;
      buf[i] += sin(2 * pi * 110 * t) * 0.02;
    }
  }

  /// 星夜：稀疏闪光音
  static void _addTwinkle(List<double> buf, Random rng) {
    for (int t = 0; t < 8; t++) {
      final int start = rng.nextInt(buf.length - 5000);
      final double f = 1200 + rng.nextDouble() * 3000;
      for (int k = 0; k < 3000 && start + k < buf.length; k++) {
        final double decay = exp(-k / 800.0);
        buf[start + k] += sin(2 * pi * f * k / sampleRate) * 0.05 * decay;
      }
    }
  }

  // ── WAV 编码 ─────────────────────────────────────────

  /// 编码为 16bit PCM 单声道 WAV
  static Uint8List _encodeWav(List<int> samples) {
    final ByteData data = ByteData(44 + samples.length * 2);

    void writeStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    data.setUint32(16, 16, Endian.little); // PCM chunk size
    data.setUint16(20, 1, Endian.little); // PCM format
    data.setUint16(22, 1, Endian.little); // mono
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    data.setUint16(32, 2, Endian.little); // block align
    data.setUint16(34, 16, Endian.little); // bits per sample
    writeStr(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
