import 'dart:async';
import 'dart:math';

import 'audio_service.dart';

/// 音乐反应层（对应规格 Module 3：音频可视化 / 频谱）
///
/// 移动端无法直接使用 Web Audio API 的 AnalyserNode（浏览器专属），
/// 且 V1 设计边界明确「不做频谱条」。本模块提供等价的"音乐反应"能力：
///   - [level]：平滑后的整体能量包络（0~1），驱动粒子呼吸 / 亮度。
///   - [bands]：合成的多频段能量（长度 == [resolution]），供未来可视化扩展。
///   - [smoothing]：类比 AnalyserNode 的 smoothingTimeConstant。
///   - [resolution]：类比 fftSize（频段数量）。
///
/// 数据来源：播放进度 + 时长 + 播放态，经节奏包络模型合成，
/// 让画面随音乐"活"起来，但保持"意境优先"的克制。
class VisualizerService {
  VisualizerService(
    this._audio, {
    this.resolution = 16,
    this.smoothing = 0.8,
  }) {
    _posSub = _audio.positionStream.listen((d) => _pos = d);
    _durSub = _audio.durationStream.listen((d) => _dur = d);
    _playSub = _audio.playingStream.listen((p) => _playing = p);
  }

  final AudioService _audio;

  /// 频段数量（类比 fftSize / 2）
  final int resolution;

  /// 平滑系数（0~1，越大越平滑），类比 smoothingTimeConstant
  final double smoothing;

  final StreamController<double> _levelCtrl = StreamController<double>.broadcast();
  final StreamController<List<double>> _bandsCtrl =
      StreamController<List<double>>.broadcast();

  StreamSubscription<Duration?>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<bool>? _playSub;

  double _level = 0.0;
  bool _playing = false;
  Duration? _pos;
  Duration? _dur;
  Timer? _timer;
  int _tick = 0;

  /// 整体能量包络（0~1）
  Stream<double> get level => _levelCtrl.stream;

  /// 多频段能量（length == [resolution]），low → high 频率
  Stream<List<double>> get bands => _bandsCtrl.stream;

  /// 启动：以 ~20fps 采样合成包络
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _sample());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _sample() {
    _tick++;
    final double target = _rawEnvelope();
    // 指数平滑（类比 smoothingTimeConstant）
    _level = _level * smoothing + target * (1 - smoothing);
    if (!_levelCtrl.isClosed) _levelCtrl.add(_level);
    if (!_bandsCtrl.isClosed) _bandsCtrl.add(_syntheticBands(_level));
  }

  /// 原始能量包络（未平滑）
  double _rawEnvelope() {
    if (!_playing) return 0.0;
    final double progress = (_pos != null && _dur != null && _dur! > Duration.zero)
        ? (_pos!.inMilliseconds / _dur!.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    // 慢：随曲目推进的整体起伏（情绪曲线）
    final double swell = 0.45 + 0.25 * sin(progress * pi * 2);
    // 快：节奏脉冲（约 2Hz，带轻微相位偏移制造"活"的质感）
    final double beat = 0.3 * (0.5 + 0.5 * sin(_tick / 6.0));
    return (swell * 0.6 + beat * 0.4).clamp(0.0, 1.0);
  }

  /// 由整体 level 合成多频段（低频能量高、高频滚降）
  List<double> _syntheticBands(double level) {
    final List<double> out = List<double>.filled(resolution, 0.0);
    for (int i = 0; i < resolution; i++) {
      final double f = i / (resolution - 1);
      // 低频权重高，高频滚降
      final double weight = pow(1 - f, 1.2).toDouble();
      // 频段内轻微抖动，制造"活"的质感
      final double jitter = 0.85 + 0.15 * sin(_tick / 3.0 + i);
      out[i] = (level * weight * jitter).clamp(0.0, 1.0);
    }
    return out;
  }

  void dispose() {
    stop();
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _levelCtrl.close();
    _bandsCtrl.close();
  }
}
