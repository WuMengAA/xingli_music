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
  StreamSubscription<String>? _errorSub;
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
    //
    // R26skel-b3：音频专用配置——`vo: null` 关闭视频输出管线。
    // 原因：星璃是纯音频 App，Player 默认会初始化视频输出（EGL/Surface），
    // 在部分 Android 设备（尤其无 GPU 加速/省电模式）上这是闪退与无声的
    // 头号来源；`vo: null` 让 libmpv 完全跳过视频解码/渲染，只留音频。
    // 同时 `Player()` 构造包 try/catch：原生构造失败不再直接崩（无保护
    // 的原生崩溃会闪退整个 App），转成可展示的中文错误由 AudioService 兜住。
    Player p;
    try {
      p = Player(
        configuration: PlayerConfiguration(
          logLevel: MPVLogLevel.info,
          vo: null, // 纯音频：关视频输出（Android 闪退/无声防御）
        ),
      );
    } catch (e) {
      _initError = 'media_kit 解码器创建失败: $e';
      _throwInitError();
    }
    _player = p;
    _attachStreams(p);
    // Player 创建前的 setVolume 是 no-op（_player == null）——把缓存的
    // 音量补设回去，避免"音量设置丢失"导致的无声（R23 安卓实测 media_kit
    // 可播放但无声音，音量链路是头号嫌疑）。
    // R27：[_lastVolume] 按 [MusicBackend] 契约是 0~1，转成 media_kit 的 0~100。
    if (_lastVolume >= 0) {
      unawaited(p.setVolume(_lastVolume * 100.0));
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
    // R26skel-b3：解码/输出错误（如 CDN 403、流损坏）→ 错误级日志 + 状态流
    // 暴露。此前错误只出现在 mpv info 日志里，UI 无感知；现统一记录。
    _errorSub = p.stream.error.listen((String msg) {
      LogService.instance.e('mpv', 'media_kit 播放错误: $msg');
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
    // media_kit 的音量语义是 0~100（百分比），而 [MusicBackend] 契约是 0~1；
    // 读回时 ÷100 转回 0~1，与 just_audio 后端语义一致（R27 修复「无声」）。
    return p == null ? 0.7 : (p.state.volume / 100.0).clamp(0.0, 1.0);
  }

  @override
  Stream<MusicEngineState> get stateStream => _stateCtrl!.stream;

  @override
  Stream<Duration?> get positionStream => _positionCtrl!.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtrl!.stream;

  /// 销毁当前 Player（open 失败后调用：坏状态不再复用，下次 open 重建）。
  ///
  /// R26skel-b3：media_kit 一个 Player 在 open 失败（403/流损坏/解码错）后
  /// 会残留坏状态，后续 open 也失败甚至崩；重置后每次失败都从干净状态重试。
  Future<void> _resetPlayer() async {
    await _playingSub?.cancel();
    await _bufferingSub?.cancel();
    await _completedSub?.cancel();
    await _errorSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _logSub?.cancel();
    _playingSub = null;
    _bufferingSub = null;
    _completedSub = null;
    _errorSub = null;
    _positionSub = null;
    _durationSub = null;
    _logSub = null;
    _streamsReady = false;
    final Player? p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {
        // 引擎已坏时 dispose 也可能抛，忽略
      }
    }
    _playing = false;
    _buffering = false;
    _completed = false;
    _stateCtrl?.add(MusicEngineState(
        processing: MusicProcess.idle, playing: false));
  }

  @override
  Future<void> openUri(Uri uri, {Map<String, String>? headers}) async {
    final Player p = _ensurePlayer();
    try {
      await p.open(Media(uri.toString(), httpHeaders: headers));
    } catch (e) {
      LogService.instance.e('audio', 'media_kit open 失败: $e');
      await _resetPlayer();
      rethrow; // AudioService 兜住 → playErrorStream 中文提示
    }
    LogService.instance
        .i('audio', 'media_kit open: ${_redactUri(uri.toString())}');
  }

  @override
  Future<void> openUrl(String url, {Map<String, String>? headers}) async {
    final Player p = _ensurePlayer();
    try {
      await p.open(Media(url, httpHeaders: headers));
    } catch (e) {
      LogService.instance.e('audio', 'media_kit open 失败: $e');
      await _resetPlayer();
      rethrow;
    }
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
    try {
      await p.open(Media(uri));
    } catch (e) {
      LogService.instance.e('audio', 'media_kit open 失败: $e');
      await _resetPlayer();
      rethrow;
    }
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
        'volume=${p.state.volume}%（意图 ${(_lastVolume * 100).round()}%）'
        ' pos=${p.state.position}',
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
    // R27：media_kit 音量语义是 0~100（百分比），而 [MusicBackend] 契约是 0~1。
    // 入参按契约是 0~1，这里 ×100 转成 media_kit 期望的百分比，否则 0.7 会被当成
    // 0.7% → 几乎无声（用户反馈「media_kit 无声」真凶）。
    if (p != null) await p.setVolume(volume * 100.0);
  }

  /// I（均衡器）：Windows 真 DSP——mpv `af` 滤镜链。
  ///
  /// media_kit 的 `Player.platform` 是公开的原生 `PlatformPlayer`，其
  /// `setProperty(property, value)` 直接走 libmpv `mpv_set_property_string`。
  /// 有 Player 且平台为原生 → 设 `af`；否则返回 false（回退模拟层）。
  @override
  Future<bool> setEqualizerFilter(String afFilter) async {
    final Player? p = _player;
    final PlatformPlayer? pp = p?.platform;
    if (pp == null) return false;
    try {
      final dynamic native = pp; // NativePlayer.setProperty（各平台原生实现）
      await native.setProperty('af', afFilter);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _bufferingSub?.cancel();
    await _completedSub?.cancel();
    await _errorSub?.cancel();
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
