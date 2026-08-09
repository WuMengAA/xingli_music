import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:just_audio/just_audio.dart';

import '../../models/scene.dart';
import '../../models/track.dart';
import '../log_service.dart';
import 'ambient_soundscape_service.dart';
import 'soundscape_generator.dart';

/// 显式播放状态机：用单一权威模型替代零散 flag 拼凑，
/// 杜绝「加载中误触 / 状态错乱」类竞态。
enum PlaybackState { idle, loading, playing, paused }

/// 音频服务：音乐播放（just_audio）+ 场景音景（双播放器交叉淡入淡出）。
///
/// - 播放状态由 just_audio 真实状态流驱动（[playingStream]），UI 不手动标记
/// - 淡入淡出不阻塞 UI：切歌先恢复/播放，音量渐变为后台任务
/// - 音景：程序生成 WAV 随场景循环；换场景双播放器 crossfade
class AudioService {
  /// v2 EQ：允许外部装配 `AudioPipeline(androidAudioEffects: [eq])`。
  /// 仅 Android 生效（非 Android 传入 null 走默认管线）。
  AudioService({AudioPipeline? musicPipeline})
      : _music = AudioPlayer(
          audioPipeline: musicPipeline ?? AudioPipeline(),
        ) {
    _activeSc = _scA;
  }

  final AudioPlayer _music;

  /// 一次性事件音效播放器（「我的世界」主题音效调度用）
  final AudioPlayer _sfx = AudioPlayer();

  /// 双音景播放器：交叉淡入淡出用
  final ap.AudioPlayer _scA = ap.AudioPlayer();
  final ap.AudioPlayer _scB = ap.AudioPlayer();

  /// 当前正在发声的音景播放器
  late ap.AudioPlayer _activeSc;

  Track? _currentTrack;
  Track? get currentTrack => _currentTrack;

  /// 当前曲目变化流：供系统媒体控件（锁屏/通知栏）同步媒体项
  final StreamController<Track?> _trackCtrl = StreamController<Track?>.broadcast();
  Stream<Track?> get trackStream => _trackCtrl.stream;

  /// 音乐是否在播放（just_audio 真实状态）
  bool get musicPlaying => _music.playing;

  String? _activeSoundscapeId;

  /// 当前目标音量（心情可调）
  double _musicVol = 0.5;
  double _scVol = 0.25;

  /// 显式播放状态机（权威模型，内部逻辑与 UI 都以它为准）
  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;

  /// 状态流：由 just_audio 真实引擎状态派生，UI 永远与引擎一致
  Stream<PlaybackState> get stateStream =>
      _music.playerStateStream.map((s) {
        if (s.processingState == ProcessingState.loading ||
            s.processingState == ProcessingState.buffering) {
          return PlaybackState.loading;
        }
        if (!s.playing) {
          return s.processingState == ProcessingState.idle
              ? PlaybackState.idle
              : PlaybackState.paused;
        }
        return PlaybackState.playing;
      }).distinct();

  /// 音景切换请求序号：快速切换时只执行最新一次
  int _scSeq = 0;

  /// 真实播放状态流（驱动 UI，状态永远跟引擎一致）
  Stream<bool> get playingStream =>
      _music.playerStateStream.map((s) => s.playing).distinct();

  /// 播放位置流（用于进度反馈）
  Stream<Duration?> get positionStream => _music.positionStream;

  /// 曲目时长流
  Stream<Duration?> get durationStream => _music.durationStream;

  // ── 音乐播放 ───────────────────────────────────────

  /// 播放音乐：立即切换并播放，淡入淡出后台进行（不阻塞 UI）
  ///
  /// 全程维护显式状态机：进入即 [loading]，每个出口都落到确定状态，
  /// 保证并发切歌 / 快速暂停时状态永远可预测。
  Future<void> playMusic(Track track, {Duration fade = const Duration(seconds: 3)}) async {
    // 同一曲目：直接续播
    if (_currentTrack?.uri == track.uri) {
      _state = PlaybackState.playing;
      await _music.play();
      return;
    }

    LogService.instance.i(
        'audio', '播放: ${track.title} [${track.sourceId}] uri=${track.uri}');

    // 进入加载态（在 await 期间状态即 loading，togglePlay 会忽略）
    _state = PlaybackState.loading;
    final Future<void> load = _prepareMusic(track);
    if (_music.playing) {
      // 快速淡出旧曲（后台，与加载并行）
      unawaited(_fadeMusic(1.0, 0.0, fade ~/ 2));
    }
    await load;

    // 加载失败：回到 idle
    if (_currentTrack == null) {
      _state = PlaybackState.idle;
      return;
    }
    // 加载期间已被更新的切歌请求取代：让位，自身不再发声
    if (_currentTrack!.uri != track.uri) {
      _state = PlaybackState.paused;
      return;
    }

    // 若处于静音状态，淡入到 0（保持静音），否则淡入到当前音量
    final double target = _musicMuted ? 0.0 : _musicVol;
    _music.setVolume(0.0);
    await _music.play();
    _state = PlaybackState.playing;
    LogService.instance.i('audio', '播放开始: ${track.title}');
    // 淡入后台执行
    unawaited(_fadeMusic(0.0, target, fade));
  }

  Future<void> _prepareMusic(Track track) async {
    try {
      if (track.isRemote) {
        await _music.setUrl(track.uri);
      } else {
        await _music.setFilePath(track.uri);
      }
      _currentTrack = track;
      _trackCtrl.add(_currentTrack);
      LogService.instance.i('audio', '加载成功: ${track.title}');
    } catch (e) {
      LogService.instance.e('audio', '加载失败: ${track.title} -> $e');
      // 加载失败（文件缺失/网络问题/格式不支持）
      _currentTrack = null;
    }
  }

  /// 暂停 / 继续（即时响应，无等待）
  ///
  /// 以状态机为准：仅在 [playing] / [paused] 时响应；
  /// [idle]（无曲目）与 [loading]（加载中）直接忽略，杜绝误触竞态。
  Future<void> togglePlay() async {
    switch (_state) {
      case PlaybackState.idle:
      case PlaybackState.loading:
        return;
      case PlaybackState.playing:
        await _music.pause();
        _state = PlaybackState.paused;
        LogService.instance.i('audio', '暂停');
        break;
      case PlaybackState.paused:
        await _music.play();
        _state = PlaybackState.playing;
        LogService.instance.i('audio', '继续播放');
        break;
    }
  }

  /// 跳转播放位置（进度条拖动 seek）
  Future<void> seek(Duration position) async {
    try {
      await _music.seek(position);
    } catch (e) {
      LogService.instance.w('audio', 'seek 失败: $e');
    }
  }

  /// 仅暂停（系统媒体控件「暂停」用，不切换状态为其它）
  Future<void> pauseOnly() async {
    if (_state == PlaybackState.playing) {
      await _music.pause();
      _state = PlaybackState.paused;
      LogService.instance.i('audio', '暂停（系统/打断）');
    }
  }

  /// 仅续播（系统媒体控件「播放」用）
  Future<void> resume() async {
    if (_state == PlaybackState.paused) {
      await _music.play();
      _state = PlaybackState.playing;
      LogService.instance.i('audio', '续播（系统）');
    }
  }

  /// 临时压低/恢复音量（音频焦点被其它应用 duck 时用，不改变记忆音量）
  Future<void> setDuck(bool ducked) async {
    if (_music.playing) {
      await _music.setVolume(ducked ? 0.15 : (_musicMuted ? 0.0 : _musicVol));
    }
  }

  /// 播放一次性事件音效（短音效，低音量叠加在音乐/音景之上）。
  /// 「我的世界」主题音效调度器调用。
  Future<void> playSfx(String path, {double volume = 0.25}) async {
    try {
      await _sfx.setVolume(volume);
      await _sfx.setAudioSource(AudioSource.file(path), preload: true);
      await _sfx.play();
      LogService.instance.i('audio', 'SFX: ${path.split('/').last}');
    } catch (e) {
      LogService.instance.w('audio', 'SFX 播放失败: $path -> $e');
    }
  }

  /// 停止事件音效（离开「我的世界」主题时调用）
  Future<void> stopSfx() async {
    try {
      await _sfx.stop();
    } catch (_) {}
  }

  // ── 场景音景（双播放器 crossfade） ─────────────────

  /// 切换场景音景：新音景淡入与旧音景淡出并行，无突兀
  Future<void> switchSoundscape(Scene scene) async {
    final String sceneId = scene.id;
    final int seq = ++_scSeq;
    if (_activeSoundscapeId == sceneId) return;

    LogService.instance.i('audio', '切换音景: $sceneId');

    final String path;
    try {
      // 1) 优先用 Minecraft 真实环境音（或用户自定义音景文件）
      final String? ambient = await AmbientSoundscapeService.ambientPathFor(scene);
      if (ambient != null) {
        path = ambient;
        LogService.instance.i('audio', '音景使用 Minecraft 环境音: $path');
      } else {
        // 2) 无匹配则程序合成
        path = await SoundscapeGenerator.ensureSceneSoundscape(sceneId);
      }
    } catch (e) {
      LogService.instance.e('audio', '音景生成失败: $sceneId -> $e');
      return;
    }
    // 期间又有更新的请求，放弃本次
    if (seq != _scSeq) return;

    final ap.AudioPlayer next = _activeSc == _scA ? _scB : _scA;
    final ap.AudioPlayer prev = _activeSc;

    try {
      await next.setReleaseMode(ap.ReleaseMode.loop);
      await next.setSource(ap.DeviceFileSource(path));
      await next.setVolume(0.0);
      await next.resume();

      // 并行：新淡入，旧淡出（后台，不阻塞切换）
      await Future.wait([
        _fadeSoundscape(next, 0.0, _scMuted ? 0.0 : _scVol, const Duration(seconds: 3)),
        _fadeSoundscape(prev, _scVol, 0.0, const Duration(seconds: 3)),
      ]);

      // 收尾前二次确认：若期间已有更新的切歌请求成为最新，放弃本次提交，
      // 并停掉本次的 next，避免遗留孤儿播放器停在低音量无人接管。
      if (seq != _scSeq) {
        await next.stop();
        return;
      }

      await prev.stop();
      _activeSc = next;
      _activeSoundscapeId = sceneId;
    } catch (_) {
      // 音景失败不影响主流程；同样清理本次 next，防止孤儿
      unawaited(next.stop());
    }
  }

  // ── 独立声音设置：音乐声 / 背景声 分离 ───────────────

  /// 音乐声目标音量（0.0~1.0，默认 0.5 = 50%）
  double get musicVolume => _musicVol;
  bool get musicMuted => _musicMuted;
  bool _musicMuted = false;

  /// 背景声（音景）目标音量（默认 0.35）
  double get soundscapeVolume => _scVol;
  bool get soundscapeMuted => _scMuted;
  bool _scMuted = false;

  /// 日志去重：仅当音量百分比相对上次记录值变化时才写日志，避免拖动滑块时刷屏
  int? _lastLoggedMusicPct;
  int? _lastLoggedScPct;

  /// 设置音乐声音量（即时生效 + 同步目标值）
  Future<void> setMusicVolume(double v) async {
    _musicVol = v.clamp(0.0, 1.0);
    final int pct = (_musicVol * 100).round();
    if (_lastLoggedMusicPct != pct) {
      _lastLoggedMusicPct = pct;
      LogService.instance.i('audio', '音乐声音量: $pct%');
    }
    final double out = _musicMuted ? 0.0 : _musicVol;
    if (_music.playing) await _music.setVolume(out);
  }

  /// 音乐声静音切换
  Future<void> setMusicMuted(bool m) async {
    _musicMuted = m;
    LogService.instance.i('audio', '音乐声静音: ${m ? '开' : '关'}');
    if (_music.playing) await _music.setVolume(m ? 0.0 : _musicVol);
  }

  /// 设置背景声（音景）音量（即时生效 + 同步目标值）
  Future<void> setSoundscapeVolume(double v) async {
    _scVol = v.clamp(0.0, 1.0);
    final int pct = (_scVol * 100).round();
    if (_lastLoggedScPct != pct) {
      _lastLoggedScPct = pct;
      LogService.instance.i('audio', '背景声音量: $pct%');
    }
    if (_activeSoundscapeId != null) {
      await _activeSc.setVolume(_scMuted ? 0.0 : _scVol);
    }
  }

  /// 背景声静音切换
  Future<void> setSoundscapeMuted(bool m) async {
    _scMuted = m;
    LogService.instance.i('audio', '背景声静音: ${m ? '开' : '关'}');
    if (_activeSoundscapeId != null) {
      await _activeSc.setVolume(m ? 0.0 : _scVol);
    }
  }

  // ── 心情 → 声音强度 ────────────────────────────────

  /// 根据心情调整音乐/音景音量（平滑渐变，后台执行）
  Future<void> setMoodIntensity({
    required double music,
    required double soundscape,
  }) async {
    _musicVol = music;
    _scVol = soundscape;

    if (_music.playing) {
      unawaited(_fadeMusic(_music.volume, _musicMuted ? 0.0 : _musicVol, const Duration(milliseconds: 1200)));
    }
    if (_activeSoundscapeId != null) {
      unawaited(_fadeSoundscape(_activeSc, _activeSc.volume, _scMuted ? 0.0 : _scVol, const Duration(milliseconds: 1200)));
    }
  }

  // ── 音量渐变工具 ───────────────────────────────────

  Future<void> _fadeMusic(double from, double to, Duration duration) async {
    const int steps = 16;
    if (duration.inMilliseconds <= 0) {
      _music.setVolume(to);
      return;
    }
    final Duration step = duration ~/ steps;
    for (int i = 1; i <= steps; i++) {
      _music.setVolume(from + (to - from) * i / steps);
      await Future<void>.delayed(step);
    }
  }

  Future<void> _fadeSoundscape(ap.AudioPlayer p, double from, double to, Duration duration) async {
    const int steps = 16;
    if (duration.inMilliseconds <= 0) {
      await p.setVolume(to);
      return;
    }
    final Duration step = duration ~/ steps;
    for (int i = 1; i <= steps; i++) {
      await p.setVolume(from + (to - from) * i / steps);
      await Future<void>.delayed(step);
    }
  }

  Future<void> dispose() async {
    await _trackCtrl.close();
    await _music.dispose();
    await _sfx.dispose();
    await _scA.dispose();
    await _scB.dispose();
  }
}
