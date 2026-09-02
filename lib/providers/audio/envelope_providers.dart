import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/paths.dart';

import '../../models/track.dart';
import 'audio_providers.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/envelope_analyzer.dart';
import '../../services/audio/envelope_cache.dart';
import '../../services/audio/music_envelope.dart';

/// 褰撳墠鏇茬洰锛堥殢鍒囨崲鏇存柊锛夈€?
final currentTrackProvider = StreamProvider<Track?>((ref) =>
    ref.watch(audioServiceProvider).trackStream);

/// 褰撳墠鏇茬洰鏈湴鏂囦欢璺緞锛堜粎 `file://` 鍙绾垮垎鏋愶紱娴佸獟浣?缃戠粶 鈫?null 鈫?闄嶇骇鍚堟垚锛夈€?
final currentTrackLocalPathProvider = Provider<String?>((ref) {
  final Track? t =
      ref.watch(currentTrackProvider).value ?? ref.watch(audioServiceProvider).currentTrack;
  if (t == null) return null;
  final Uri? u = Uri.tryParse(t.uri);
  if (u?.scheme != 'file') return null;
  return u!.toFilePath();
});

/// 褰撳墠鏇茬洰鐨?[MusicEnvelope]锛堝紓姝ュ垎鏋?+ 纾佺洏缂撳瓨锛夈€?
///
/// 娴佸獟浣?鏃?ffmpeg/瑙ｇ爜澶辫触 鈫?杩斿洖 null锛岃皟鐢ㄦ柟搴旈檷绾у埌鍚堟垚 [VisualizerService]銆?
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

/// 鎸夋挱鏀捐繘搴︿粠 [MusicEnvelope] 閲囨牱 bands/beat锛堢湡瀹炴暟鎹級锛屼緵 2.5D 娓叉煋娑堣垂銆?
///
/// 闀滃儚 [VisualizerService] 鐨勯┍鍔ㄦ柟寮忥紝浣嗘暟鎹潵鑷绾块鍒嗘瀽鑰岄潪鍚堟垚銆?
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

/// 褰撳墠鏇茬洰鐨勬挱鏀鹃噰鏍峰櫒锛坋nvelope 灏辩华鏃跺垱寤猴紝绂婚〉鑷姩閲婃斁锛夈€?
/// null 琛ㄧず褰撳墠鏃犲彲鐢ㄧ湡瀹炲寘缁滐紙娴佸獟浣?鏈垎鏋愶級鈫?涓婂眰闄嶇骇鍚堟垚婧愩€?
final envelopeSamplerProvider = Provider<EnvelopePlaybackSampler?>((ref) {
  final MusicEnvelope? env = ref.watch(currentEnvelopeProvider).value;
  if (env == null) return null;
  final AudioService audio = ref.watch(audioServiceProvider);
  final EnvelopePlaybackSampler s = EnvelopePlaybackSampler(audio, env);
  ref.onDispose(s.dispose);
  return s;
});

