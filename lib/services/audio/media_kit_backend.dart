/// ════════════════════════════════════════════════════════════════════════
/// media_kit（libmpv）后端（S2）
/// ════════════════════════════════════════════════════════════════════════
///
/// 全格式兼容 / Hi-Res / 无缝播放（gapless）——替换 just_audio 的
/// 目标后端。支持远程 URI 带请求头（网易云 CDN 等）。
///
/// ⚠️ 稳定性（R22）：构造**只**做 ensureInitialized + 建流控制器，
/// **不创建 Player**——Player 延迟到首次 open/play 才创建。原因：构造
/// 发生在 audioServiceProvider 求值（UI 首帧），若 libmpv 初始化异常，
/// 同步抛错会让整个 ProviderScope 崩 → 安卓黑屏。延迟创建后即使 media_kit
/// 不可用，app 照常启动，仅播放时报错（被 AudioService 兜住）。
library;

import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../log_service.dart';
import 'music_backend.dart';

/// 基于 media_kit（libmpv）的实现。
class MediaKitBackend implements MusicBackend {
  MediaKitBackend() {
    // 构造容错：初始化失败不抛（播放时才会失败并报错）。
    try {
      MediaKit.ensureInitialized();
    } catch (e) {
      _initError = 'MediaKit.ensureInitialized: $e';
    }
    _stateCtrl = StreamController<MusicEngineState>.broadcast();
    _positionCtrl = StreamController<Duration?>.broadcast();
    _durationCtrl = StreamController<Duration?>.broadcast();
  }

  /// media_kit 初始化错误（非空 = 引擎不可用，open 时抛中文异常）。
  String? _initError;

  Player? _player;
  bool _streamsReady = false;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerLog>? _logSub;
  StreamController<MusicEngineState>? _stateCtrl;
  StreamController<Duration?>? _positionCtrl;
  StreamController<Duration?>? _durationCtrl;

  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;

  /// 初始化失败时抛出可展示异常（AudioService 会兜住）。
  Never _throwInitError() {
    throw StateError(_initError ?? 'media_kit 播放引擎不可用');
  }

  Player _ensurePlayer() {
    if (_initError != null) _throwInitError();
    final Player? existing = _player;
    if (existing != null) return existing;
    // info 级 mpv 日志（含音频输出 ao 初始化）转发到 app.log——
    // R23c 双端无声（playing=true/volume=0.29/pos 走但仍听不到）
    // 需要看 libmpv 的 ao 初始化是否失败。
    final Player p = Player(
      configuration: PlayerConfiguration(logLevel: MPVLogLevel.info),
    );
    _player = p;
    _attachStreams(p);
    // Player 创建前的 setVolume 是 no-op（_player == null）——把缓存的
    // 音量补设回去，避免"音量设置丢失"导致的无声（R23 安卓实测 media_kit
    // 可播放但无声音，音量链路是头号嫌疑）。
    if (_lastVolume >= 0) {
      unawaited(p.setVolume(_lastVolume));
    }
    return p;
  }

  void _attachStreams(Player p) {
    if (_streamsReady) return;
    _streamsReady = true;
    final StreamController<MusicEngineState> stateCtrl = _stateCtrl!;
    final StreamController<Duration?> posCtrl = _positionCtrl!;
    final StreamController<Duration?> durCtrl = _durationCtrl!;

    void emit() {
      final MusicProcess proc = _buffering
          ? MusicProcess.loading
          : _completed
              ? MusicProcess.completed
              : MusicProcess.ready;
      stateCtrl.add(MusicEngineState(processing: proc, playing: _playing));
    }

    _playingSub = p.stream.playing.listen((bool v) {
      _playing = v;
      emit();
    });
    _bufferingSub = p.stream.buffering.listen((bool v) {
      _buffering = v;
      emit();
    });
    _completedSub = p.stream.completed.listen((bool v) {
      _completed = v;
      emit();
    });
    _positionSub = p.stream.position.listen((Duration d) {
      posCtrl.add(d);
    });
    _durationSub = p.stream.duration.listen((Duration? d) {
      durCtrl.add(d);
    });
    // libmpv 日志（PlayerLog 流）→ app.log：音频输出(ao)/解码错误定位。
    _logSub = p.stream.log.listen((PlayerLog l) {
      LogService.instance.d('mpv', l.toString());
    });
    // 初始快照
    emit();
  }

  @override
  bool get playing {
    final Player? p = _player;
    return p == null ? false : p.state.playing;
  }

  @override
  double get volume {
    final Player? p = _player;
    return p == null ? 0.7 : p.state.volume;
  }

  @override
  Stream<MusicEngineState> get stateStream => _stateCtrl!.stream;

  @override
  Stream<Duration?> get positionStream => _positionCtrl!.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtrl!.stream;

  @override
  Future<void> openUri(Uri uri, {Map<String, String>? headers}) async {
    final Player p = _ensurePlayer();
    await p.open(Media(uri.toString(), httpHeaders: headers));
    LogService.instance
        .i('audio', 'media_kit open: ${_redactUri(uri.toString())}');
  }

  @override
  Future<void> openUrl(String url, {Map<String, String>? headers}) async {
    final Player p = _ensurePlayer();
    await p.open(Media(url, httpHeaders: headers));
    LogService.instance.i('audio', 'media_kit open: ${_redactUri(url)}');
  }

  @override
  Future<void> openPath(String path) async {
    final Player p = _ensurePlayer();
    // libmpv 需要标准 URI：裸路径（尤其 Windows 反斜杠路径）转 file:///。
    // 否则文件打不开 → 播放器无输出（R23c 双端无声的头号嫌疑）。
    final String uri = path.startsWith('file://') ||
            path.startsWith('http://') ||
            path.startsWith('https://')
        ? path
        : Uri.file(path).toString();
    await p.open(Media(uri));
    LogService.instance.i('audio', 'media_kit open: ${_redactUri(uri)}');
  }

  String _redactUri(String uri) {
    final int q = uri.indexOf('?');
    return q < 0 ? uri : '${uri.substring(0, q)}?<redacted>';
  }

  @override
  Future<void> play() async {
    final Player p = _ensurePlayer();
    await p.play();
    // 诊断：播放 1 秒后记录引擎真实状态（无声排查用）。
    unawaited(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      LogService.instance.i(
        'audio',
        'media_kit 1s后: playing=${p.state.playing} '
        'volume=${p.state.volume} pos=${p.state.position}',
      );
    }());
  }

  @override
  Future<void> pause() async {
    final Player? p = _player;
    if (p != null) await p.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    final Player? p = _player;
    if (p != null) await p.seek(position);
  }

  /// 最近一次设置的音量（0~1）；Player 创建后补设，防止创建前 no-op 丢音量。
  double _lastVolume = -1;

  @override
  Future<void> setVolume(double volume) async {
    _lastVolume = volume;
    final Player? p = _player;
    if (p != null) await p.setVolume(volume);
  }

  @override
  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _bufferingSub?.cancel();
    await _completedSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _logSub?.cancel();
    await _stateCtrl?.close();
    await _positionCtrl?.close();
    await _durationCtrl?.close();
    final Player? p = _player;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {
        // 引擎已坏时 dispose 也可能抛，忽略
      }
    }
  }
}
