import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/paths.dart';

import '../../models/track.dart';
import 'audio_providers.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/envelope_analyzer.dart';
import '../../services/audio/envelope_cache.dart';
import '../../services/audio/music_envelope.dart';

/// 当前曲目（随切换更新）。
final currentTrackProvider = StreamProvider<Track?>((ref) =>
    ref.watch(audioServiceProvider).trackStream);

/// 当前曲目本地文件路径（仅 `file://` 可离线分析；流媒体/网络 → null → 降级合成）。
final currentTrackLocalPathProvider = Provider<String?>((ref) {
  final Track? t =
      ref.watch(currentTrackProvider).value ?? ref.watch(audioServiceProvider).currentTrack;
  if (t == null) return null;
  final Uri? u = Uri.tryParse(t.uri);
  if (u?.scheme != 'file') return null;
  return u!.toFilePath();
});

/// 当前曲目的 [MusicEnvelope]（异步分析 + 磁盘缓存）。
///
/// 流媒体/无 ffmpeg/解码失败 → 返回 null，调用方应降级到合成 [VisualizerService]。
final currentEnvelopeProvider = FutureProvider<MusicEnvelope?>((ref) async {
  final String? path = ref.watch(currentTrackLocalPathProvider);
  if (path == null || !File(path).existsSync()) return null;
  final Directory docs = await appDataDir();
  final EnvelopeCache cache = EnvelopeCache(docs);
  try {
    return await cache.getOrAnalyze(path);
  } on EnvelopeUnavailable {
    return null;
  }
});

/// 按播放进度从 [MusicEnvelope] 采样 bands/beat（真实数据），供 2.5D 渲染消费。
///
/// 镜像 [VisualizerService] 的驱动方式，但数据来自离线预分析而非合成。
class EnvelopePlaybackSampler {
  EnvelopePlaybackSampler(this._audio, this._envelope) {
    _posSub = _audio.positionStream.listen((d) => _pos = d);
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) => _emit());
  }

  final AudioService _audio;
  final MusicEnvelope _envelope;
  Duration? _pos;
  Timer? _tick;
  StreamSubscription<Duration?>? _posSub;
  final StreamController<List<double>> _bandsCtrl = StreamController<List<double>>.broadcast();
  final StreamController<double> _beatCtrl = StreamController<double>.broadcast();

  Stream<List<double>> get bands => _bandsCtrl.stream;
  Stream<double> get beat => _beatCtrl.stream;

  void _emit() {
    final double ms = (_pos?.inMilliseconds ?? 0).toDouble();
    if (!_bandsCtrl.isClosed) _bandsCtrl.add(_envelope.sampleBands(ms));
    if (!_beatCtrl.isClosed) _beatCtrl.add(_envelope.sampleBeat(ms));
  }

  void dispose() {
    _tick?.cancel();
    _posSub?.cancel();
    _bandsCtrl.close();
    _beatCtrl.close();
  }
}

/// 当前曲目的播放采样器（envelope 就绪时创建，离页自动释放）。
/// null 表示当前无可用真实包络（流媒体/未分析）→ 上层降级合成源。
final envelopeSamplerProvider = Provider<EnvelopePlaybackSampler?>((ref) {
  final MusicEnvelope? env = ref.watch(currentEnvelopeProvider).value;
  if (env == null) return null;
  final AudioService audio = ref.watch(audioServiceProvider);
  final EnvelopePlaybackSampler s = EnvelopePlaybackSampler(audio, env);
  ref.onDispose(s.dispose);
  return s;
});
