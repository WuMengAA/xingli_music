import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:just_audio/just_audio.dart';

import '../../models/scene.dart';
import '../../models/track.dart';
import '../log_service.dart';
import 'ambient_soundscape_service.dart';
import 'just_audio_backend.dart';
import 'media_kit_backend.dart';
import 'music_backend.dart';
import 'soundscape_generator.dart';

/// 解析出的可直接播放地址 + 请求头（交给后端 `AudioSource.uri`）。
class ResolvedStream {
  const ResolvedStream(this.url,
      [this.headers = const <String, String>{}, this.requiresMediaKit = false]);

  final String url;
  final Map<String, String> headers;

  /// 该曲源是否需要 media_kit 后端（④ #392：网易云·B站 CDN 流路由用）。
  final bool requiresMediaKit;
}

/// 占位 uri → 真实地址的解析器。返回 null 表示无需解析（走默认本地路径逻辑）。
typedef StreamResolver = Future<ResolvedStream?> Function(Track track);

/// 判断 uri 是否为真实本地文件路径（可用 openPath 打开）。
///
/// - `http(s)` → 远程（openUrl）；
/// - `file://` → 本地文件（剥离 scheme 后 openPath）；
/// - 其它 scheme（netease:///bili:// 等占位符）→ 非本地文件，
///   解析失败时必须判加载失败，绝不能以文件路径打开（原生层会崩）。
bool _isLocalFilePath(String uri) {
  if (uri.startsWith('http')) return false;
  if (uri.startsWith('file://')) return true;
  if (uri.contains('://')) return false;
  return true;
}

/// 播放地址解析失败（消息已翻译为可直接展示的中文，如「网易云登录已失效」）。
class StreamResolveException implements Exception {
  const StreamResolveException(this.message);

  final String message;

  @override
  String toString() => 'StreamResolveException: $message';
}

/// 显式播放状态机：用单一权威模型替代零散 flag 拼凑，
/// 杜绝「加载中误触 / 状态错乱」类竞态。
enum PlaybackState { idle, loading, playing, paused }

/// 声音分类（#170）：全局唯一规范分类，UI 文案 / 日志 tag / 文档三处同名。
///
/// 命名规范见 `docs/音效处理逻辑与分类方案.md` 第 5 节，禁止再起别名
/// （如「白噪」「空间音效」）。每类都有独立音量控制与代表性反馈音。
enum AudioCategory {
  /// 音乐：曲库主播放通道（`_music`，可 EQ）。
  music('音乐', '曲库主播放，可 EQ 调音', 'music'),

  /// 背景声（音景）：场景环境音，双播放器交叉淡化。
  soundscape('背景声', '场景环境底色，随场景切换', 'soundscape'),

  /// 白噪音：均匀底噪，独立循环通道。
  whiteNoise('白噪音', '均匀掩蔽环境杂音', 'whiteNoise'),

  /// 音效：一次性事件音（挖 / 放 / 交互）。
  sfx('音效', '交互瞬时反馈音', 'sfx'),

  /// 世界空间音效：3D 世界内随机位定位的环境音。
  worldSpatial('世界空间音效', '随机位变化的定位环境音', 'world'),

  /// 提示音：界面操作反馈音。
  uiCue('提示音', '界面操作确认提示', 'uiCue');

  const AudioCategory(this.label, this.concept, this.tag);

  /// 规范中文名（UI 展示用，禁止混用别名）。
  final String label;

  /// 一句话概念说明（UI 小字标签用）。
  final String concept;

  /// 日志 tag / 反馈音缓存文件名（小写英文）。
  final String tag;
}

/// 音量均衡模式（R15）：高保真 / 普通。
enum BalanceMode {
  /// 高保真：关闭一切增益处理，保留原始动态范围。
  hifi,

  /// 普通：响度归一化 + 轻度压缩（低音量内容更易听清）。
  normal,
}

/// 音频服务：音乐播放（just_audio）+ 场景音景（双播放器交叉淡入淡出）
/// + 白噪音（独立播放器）。
///
/// - 播放状态由 just_audio 真实状态流驱动（[playingStream]），UI 不手动标记
/// - 淡入淡出不阻塞 UI：切歌先恢复/播放，音量渐变为后台任务
/// - 音景：程序生成 WAV 随场景循环；换场景双播放器 crossfade
/// - 音景/白噪音播放器使用 `mixWithOthers` 焦点（R3 修复）：
///   不再请求独占音频焦点，因此切换场景不会打断正在播放的音乐
class AudioService {
  /// v2 EQ：允许外部装配 `AudioPipeline(androidAudioEffects: [eq])`。
  /// 仅 Android 生效（非 Android 传入 null 走默认管线）。
  /// S2：音乐后端可注入（默认 just_audio；传 [MediaKitBackend] 切 media_kit）。
  /// ④ #392/#393：双后端并存——just_audio（默认）+ media_kit（全格式 /
  /// 网易云·B站 CDN 流）。按曲源 [MusicSource.requiresMediaKit] 或全局引擎
  /// 开关路由到对应后端，由 [_switchBackend] 在切歌时抉择。
  AudioService({AudioPipeline? musicPipeline, bool useMediaKit = false})
      : _useMediaKitGlobal = useMediaKit,
        _justAudioBackend =
            JustAudioBackend(audioPipeline: musicPipeline ?? AudioPipeline()),
        _mediaKitBackend = MediaKitBackend() {
    _activeSc = _scA;
    // R3 修复：环境音/音景播放器不抢焦点，避免打断音乐。
    // 注意：_sfx 是 just_audio 播放器，跟随音乐会话，无需（也不能）设置
    // audioplayers 的 AudioContext。
    final ap.AudioContext noFocus = ap.AudioContextConfig(
      focus: ap.AudioContextConfigFocus.mixWithOthers,
    ).build();
    unawaited(_safe(() => _scA.setAudioContext(noFocus)));
    unawaited(_safe(() => _scB.setAudioContext(noFocus)));
    unawaited(_safe(() => _wn.setAudioContext(noFocus)));
    unawaited(_safe(() => _cue.setAudioContext(noFocus)));

    // 绑定初始活跃后端（just_audio / media_kit）的派生流。
    _bindBackend(useMediaKit ? _mediaKitBackend : _justAudioBackend);
  }

  /// 全局是否走 media_kit（设置→播放引擎 = media_kit）。
  final bool _useMediaKitGlobal;

  /// just_audio 后端（默认；Android 真 EQ、稳定）。
  final JustAudioBackend _justAudioBackend;

  /// media_kit（libmpv）后端：全格式 / 网易云·B站 CDN 流 / Hi-Res。
  final MediaKitBackend _mediaKitBackend;

  /// 当前活跃后端（路由结果）。所有引擎调用统一走它。
  late MusicBackend _activeBackend;

  /// I（均衡器）：暴露当前音乐后端（Windows 分支按类型选 mpv 滤镜引擎）。
  MusicBackend get backend => _activeBackend;

  /// cl46 自动播放：曲目自然播放完成时触发（由 AutoPlayTracker 挂接）。
  void Function()? onCompleted;

  /// 派生流控制器：后端切换时改绑，UI（StreamProvider）无需重新订阅。
  final StreamController<PlaybackState> _stateCtrl =
      StreamController<PlaybackState>.broadcast();
  final StreamController<bool> _playingCtrl =
      StreamController<bool>.broadcast();
  final StreamController<Duration?> _positionCtrl =
      StreamController<Duration?>.broadcast();
  final StreamController<Duration?> _durationCtrl =
      StreamController<Duration?>.broadcast();

  /// 曲目自然播放完成流：供睡眠定时「当前曲目结束」模式监听。
  final StreamController<void> _completedCtrl =
      StreamController<void>.broadcast();
  Stream<void> get trackCompletedStream => _completedCtrl.stream;

  /// 活跃后端状态流订阅（[_bindBackend] 切换，dispose 时取消）。
  StreamSubscription<MusicEngineState>? _stateSub;
  StreamSubscription<Duration?>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  /// 绑定活跃后端的派生流（取消旧订阅、改挂新后端）。
  /// 构造函数与 [_switchBackend] 都会调用。
  void _bindBackend(MusicBackend backend) {
    _stateSub?.cancel();
    _stateSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    _durationSub?.cancel();
    _durationSub = null;

    _activeBackend = backend;
    _stateSub = backend.stateStream.listen((MusicEngineState s) {
      LogService.instance.d(
          'audio', 'playerState: ${s.processing} playing=${s.playing}');
      _stateCtrl.add(_toPlaybackState(s));
      _playingCtrl.add(s.playing);
      // cl46 自动播放：自然播放完成（completed 且非手动暂停）。
      if (s.processing == MusicProcess.completed && !s.playing) {
        onCompleted?.call();
        _completedCtrl.add(null);
      }
    });
    _positionSub = backend.positionStream.listen(_positionCtrl.add);
    _durationSub = backend.durationStream.listen(_durationCtrl.add);
  }

  /// 切换到另一后端：先暂停旧后端（防双音轨叠播），重绑派生流，
  /// 并立即推 loading 态让 UI 进入加载中。④ 路由核心。
  void _switchBackend(MusicBackend target) {
    if (target == _activeBackend) return;
    unawaited(_safe(() => _activeBackend.pause(), tag: 'switchPausePrev'));
    _bindBackend(target);
    _stateCtrl.add(PlaybackState.loading);
    _playingCtrl.add(false);
  }

  /// 引擎状态 → 播放状态机（与原 stateStream 派生逻辑一致）。
  static PlaybackState _toPlaybackState(MusicEngineState s) {
    if (s.processing == MusicProcess.loading) return PlaybackState.loading;
    if (!s.playing) {
      return s.processing == MusicProcess.idle
          ? PlaybackState.idle
          : PlaybackState.paused;
    }
    return PlaybackState.playing;
  }

  /// 一次性事件音效播放器（「我的世界」主题音效调度用）
  final AudioPlayer _sfx = AudioPlayer();

  /// 双音景播放器：交叉淡入淡出用
  final ap.AudioPlayer _scA = ap.AudioPlayer();
  final ap.AudioPlayer _scB = ap.AudioPlayer();

  /// 白噪独立播放器（R23i）：循环播程序合成白噪 wav，叠加在音乐/音景之上。
  final ap.AudioPlayer _wn = ap.AudioPlayer();

  /// 分类反馈音播放器（#170）：调整某分类音量时播一声代表性短音。
  ///
  /// 独立于 [_sfx]（游戏事件音效），避免抢占「我的世界」音效调度器的播放器。
  final ap.AudioPlayer _cue = ap.AudioPlayer();

  /// 当前正在发声的音景播放器
  late ap.AudioPlayer _activeSc;

  Track? _currentTrack;
  Track? get currentTrack => _currentTrack;

  /// 当前曲目变化流：供系统媒体控件（锁屏/通知栏）同步媒体项
  final StreamController<Track?> _trackCtrl = StreamController<Track?>.broadcast();
  Stream<Track?> get trackStream => _trackCtrl.stream;

  /// 播放地址解析失败提示流（如「网易云登录已失效，请重新登录」），UI 可订阅展示。
  final StreamController<String> _playErrorCtrl = StreamController<String>.broadcast();
  Stream<String> get playErrorStream => _playErrorCtrl.stream;

  /// 占位 uri → 真实播放地址 + 请求头的解析器（由 Riverpod 层注入）。
  StreamResolver? _streamResolver;

  /// 注入解析器：把 `netease://song/<id>` 这类占位符解析成可播放的 HTTPS 地址，
  /// 并为 CDN 请求附加源提供的请求头。
  void setStreamResolver(StreamResolver? resolver) => _streamResolver = resolver;

  /// 音乐是否在播放（just_audio 真实状态）
  bool get musicPlaying => _activeBackend.playing;

  String? _activeSoundscapeId;

  /// 当前目标音量（心情可调；R12 初始 0.7）
  double _musicVol = 0.7;
  double _scVol = 0.25;

  /// 主音量（Master，R23i）：全局整体音量，所有通道输出 × master。
  double _masterVol = 1.0;
  double get masterVolume => _masterVol;

  /// 倍速（R26skel：播放体验优化）。1.0 = 原速，范围 0.25~4.0。
  double _musicSpeed = 1.0;
  double get musicSpeed => _musicSpeed;

  /// 睡眠定时「本曲结束」模式生效时为 true：抑制 cl46 自动播放的自动续播，
  /// 使当前曲自然完成后仅暂停、不切下一首（#486）。
  bool _suppressAutoAdvance = false;
  bool get suppressAutoAdvance => _suppressAutoAdvance;
  void setSuppressAutoAdvance(bool v) {
    if (_suppressAutoAdvance == v) return;
    _suppressAutoAdvance = v;
    LogService.instance.i('audio', '抑制自动续播: $v');
  }

  /// 音效（SFX）通道音量（R23i：独立于音乐/背景/白噪，默认 0.5）。
  double _sfxVol = 0.5;
  double get sfxVolume => _sfxVol;

  /// 白噪通道音量（R23i：独立于音景音量，默认 0.3）。
  double _wnVol = 0.3;
  double get whiteNoiseVolume => _wnVol;

  /// 世界空间音效通道音量（#170：3D 世界定位环境音，默认 0.6）。
  ///
  /// 实际增益由 `WorldAudioEngine.setGlobalVolume` 施加（体素视图订阅
  /// `worldSfxVolumeProvider` 后下发），此处仅作为权威记忆值供各处读取。
  double _worldVol = 0.6;
  double get worldSfxVolume => _worldVol;

  /// 提示音通道音量（#170：界面操作反馈音，默认 0.5）。
  double _uiCueVol = 0.5;
  double get uiCueVolume => _uiCueVol;

  /// 白噪音开关（R23i：独立通道，不再控制场景音景）。
  bool _whiteNoiseOn = false;
  bool get whiteNoiseOn => _whiteNoiseOn;

  /// 白噪 wav 是否已加载（懒加载一次，循环播放）。
  bool _wnLoaded = false;

  /// 音量均衡模式（R15，默认普通）
  BalanceMode _balanceMode = BalanceMode.normal;
  BalanceMode get balanceMode => _balanceMode;

  /// 显式播放状态机（权威模型，内部逻辑与 UI 都以它为准）
  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;

  /// 状态流：由活跃后端真实状态派生，UI 永远与引擎一致（④ 后端切换不断流）。
  Stream<PlaybackState> get stateStream => _stateCtrl.stream.distinct();

  /// 音景切换请求序号：快速切换时只执行最新一次
  int _scSeq = 0;

  /// 音乐淡入淡出序号：同一 player 的并发淡入互相让位（R20 修静音）。
  ///
  /// 背景：切歌时旧曲淡出与新曲淡入**并发写同一个 volume**，旧淡出的最后一拍
  /// `setVolume(0)` 会把新曲音量也压成 0 → 表现为"必须点一下音量才有声"。
  /// 每次新淡入自增序号，旧淡入在每步检查，被取代立即退出。
  int _fadeSeq = 0;

  /// 音乐加载序号：快速切歌时旧加载在 setAudioSource 前让位（R20 修闪退）。
  ///
  /// 背景：just_audio 并发 setAudioSource（上一首未加载完就切下一首）在部分
  /// 平台偶发崩溃；被取代的加载直接放弃，不触碰播放器。
  int _loadSeq = 0;

  /// R27（安卓切歌防闪退）：服务已销毁标记。销毁后任何切歌/播放请求立即放弃，
  /// 不再触碰已释放的播放器（否则在安卓上触发原生层崩溃闪退）。
  bool _disposed = false;

  /// 真实播放状态流（驱动 UI，状态永远跟引擎一致）
  Stream<bool> get playingStream => _playingCtrl.stream.distinct();

  /// 播放位置流（用于进度反馈）
  Stream<Duration?> get positionStream => _positionCtrl.stream;

  /// 曲目时长流
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  // ── 音乐播放 ───────────────────────────────────────

  // ── 日志脱敏（P-1）─────────────────────────────────
  //
  // 播放 uri 常携带凭据（`?token=...&cookie=...`、Subsonic 的 `t=`/`s=`），
  // 本地路径则含真实用户名（`C:\Users\张三\Music\...`）。这些内容一旦进入
  // app.log 就是明文长期留存的隐私泄漏，因此所有涉敏日志一律先过 [_redact]。

  /// 脱敏 uri / 文件路径，供日志输出使用。
  ///
  /// - 远端 URL：只保留 `scheme://host/path`，**整个 query 与 fragment**
  ///   替换为 `<redacted>`（不逐个挑 token —— 白名单式剥离才不会漏）；
  ///   userInfo（`user:pass@`）一并抹去。
  /// - 本地路径：只保留最后一级文件名，上层目录（含用户名）替换为 `…/`。
  /// - 空值返回 `<null>`，永不抛异常（日志路径必须绝对安全）。
  static String _redact(String? s) {
    if (s == null || s.isEmpty) return '<null>';
    try {
      final Uri u = Uri.parse(s);
      if (u.hasScheme && u.scheme != 'file' && u.host.isNotEmpty) {
        final String tail =
            (u.hasQuery || u.hasFragment) ? '?<redacted>' : '';
        return '${u.scheme}://${u.host}${u.path}$tail';
      }
    } catch (_) {
      // 非法 URI：按本地路径处理
    }
    return _redactPath(s);
  }

  /// 本地路径脱敏：仅保留文件名，隐去所有上级目录（用户名在其中）。
  static String _redactPath(String s) {
    final String norm = s.replaceAll('\\', '/');
    final int i = norm.lastIndexOf('/');
    if (i < 0) return s;
    return '…/${norm.substring(i + 1)}';
  }

  /// 安全执行 just_audio 操作：捕获所有异常并记日志，绝不向上抛。
  ///
  /// Wear OS / 精简系统上 just_audio 的 `play()/pause()/setVolume()`
  /// 可能抛 `PlatformException`（音频输出未就绪、焦点被拒等），
  /// 未捕获的 async 异常会直接闪退（「播放音乐就闪退」根因）。
  /// 所有引擎调用一律经本方法兜底，失败静默降级、状态机照常推进。
  static Future<void> _safe(Future<void> Function() op,
      {String tag = 'audio'}) async {
    try {
      await op();
    } catch (e, st) {
      LogService.instance.w('audio', '$tag 操作失败: $e\n$st');
    }
  }

  /// 播放音乐：立即切换并播放，淡入淡出后台进行（不阻塞 UI）
  ///
  /// 全程维护显式状态机：进入即 [loading]，每个出口都落到确定状态，
  /// 保证并发切歌 / 快速暂停时状态永远可预测。
  Future<void> playMusic(Track track, {Duration fade = const Duration(seconds: 3)}) async {
    // 同一曲目：直接续播。先恢复目标音量再 play —— 防止上一条淡出
    // 残留（volume=0）导致"点了播放却没声音，必须拖一下音量才有声"。
    if (_currentTrack?.uri == track.uri) {
      _state = PlaybackState.playing;
      await _safe(
        () => _activeBackend.setVolume(_musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol),
        tag: '续播音量',
      );
      await _safe(() => _activeBackend.play(), tag: '续播');
      return;
    }

    final int seq = ++_loadSeq;
    if (_disposed) return;
    final Track? prevTrack = _currentTrack; // #396：加载失败回退用
    LogService.instance.i('audio',
        '播放: ${track.title} [${track.sourceId}] uri=${_redact(track.uri)}');

    // 进入加载态（在 await 期间状态即 loading，togglePlay 会忽略）
    _state = PlaybackState.loading;
    // #396：进入加载态即把歌名推到通知栏/锁屏，避免「歌名滞后到加载成功
    // 才显示」（用户反馈安卓通知栏歌名更新不及时的根因）。
    _trackCtrl.add(track);
    final Future<void> load = _prepareMusic(track, seq);
    if (_activeBackend.playing) {
      // 快速淡出旧曲（后台，与加载并行）
      unawaited(_fadeMusic(1.0, 0.0, fade ~/ 2));
    }
    await load;

    // 加载失败：通知栏回退到上一首（仍有声或至少保持上一首信息），
    // 不显示「没播出来的那首」（#396）。
    if (_currentTrack == null) {
      _currentTrack = prevTrack;
      _trackCtrl.add(prevTrack);
      _state = prevTrack != null ? PlaybackState.playing : PlaybackState.idle;
      return;
    }
    // 加载期间已被更新的切歌请求取代：让位，自身不再发声
    if (seq != _loadSeq || _currentTrack!.uri != track.uri) {
      _state = PlaybackState.paused;
      return;
    }

    // 若处于静音状态，淡入到 0（保持静音），否则淡入到当前音量
    final double target = _musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol;
    // 作废在途旧曲淡出：playMusic 直接 setVolume 不走 _fadeMusic，旧淡出不会因
    // _fadeSeq 被取代而退出，必须显式作废，否则其末步 setVolume(0) 会在 ~1.5s 后
    // 把刚起播的新曲静音（用户反馈"播 1 秒后静音，须拖主音量恢复"，cl41 修复）。
    _cancelFades();
    // 直接落到目标音量再播放：规避部分 Android 解码器「先设 0 再 play」会锁死
    // 静音、必须手动拖一下音量才有声的问题（用户反馈「须拖动主音量才有声」）。
    await _safe(() => _activeBackend.setVolume(target), tag: 'setVolume');
    await _ensureSpeedOnPlay();
    await _safe(() => _activeBackend.play(), tag: 'play');
    _state = PlaybackState.playing;
    LogService.instance.i('audio', '播放开始: ${track.title}');
  }

  Future<void> _prepareMusic(Track track, int seq) async {
    // 占位符（如 netease://song/<id>，非 http、非本地文件）先经解析器
    // 换成真实播放地址；本地文件/直连 http 不解析，走下方默认分支。
    ResolvedStream? resolved;
    if (_streamResolver != null && !track.uri.startsWith('http')) {
      try {
        final ResolvedStream? r = await _streamResolver!(track)
            .timeout(const Duration(seconds: 20));
        if (r != null && r.url.startsWith('http')) {
          resolved = r;
        }
      } on TimeoutException {
        // 解析超时（网络/接口卡住）：判加载失败，不进播放器、不回落 openPath，
        // 避免 UI 长时间卡在 loading（用户反馈「播放容易卡死」）。
        _currentTrack = null;
        _playErrorCtrl.add('播放地址解析超时，请稍后重试');
        LogService.instance.e('audio', '解析播放地址超时: ${track.title}');
        return;
      } on StreamResolveException catch (e) {
        // 解析失败（未登录/无版权/会员/网络）：推可展示提示，不进播放器。
        _currentTrack = null;
        _playErrorCtrl.add(e.message);
        LogService.instance.e('audio', '解析播放地址失败: ${track.title} -> ${e.message}');
        return;
      } catch (e) {
        LogService.instance.e('audio',
            '解析播放地址异常: ${track.title} uri=${_redact(track.uri)} -> $e');
        // 其它异常兜底：回落到默认分支（本地文件路径等），不阻断流程。
      }
    }

    // resolved 解析结果：提取 url + 请求头（供下方 open 分支使用）。
    final String? resolvedUrl = resolved?.url;
    final Map<String, String> headers = resolved?.headers ?? const <String, String>{};

    // 等待解析期间已有更新的切歌请求：直接让位，不触碰播放器
    // （避免并发 setAudioSource 在部分平台崩溃，R20）。
    if (seq != _loadSeq) return;
    // R27（安卓切歌防闪退）：服务已销毁则放弃，避免触碰已释放播放器。
    if (_disposed) return;

    // ④ #392/#393：按曲源是否需要 media_kit 选定后端。
    // 全局 media_kit 开启，或曲源声明 requiresMediaKit（网易云·B站 CDN 流
    // just_audio 无法解码、media_kit 可解）→ 走 media_kit；其余走 just_audio。
    final bool needsMk = resolved?.requiresMediaKit ?? false;
    final MusicBackend target =
        (_useMediaKitGlobal || needsMk) ? _mediaKitBackend : _justAudioBackend;
    _switchBackend(target);

    try {
      // R27：open 调用再套一层 _safe——安卓 just_audio / media_kit 在快速切歌时
      // 偶发 PlatformException（音频焦点被拒 / 解码器未就绪），直接吞掉并视为
      // 加载失败（_currentTrack 保持 null → playMusic 回落 idle），绝不向上抛闪退。
      if (resolvedUrl != null) {
        // 远程 CDN 带源请求头（网易云 UA/Referer），避免 403。
        await _safe(() => _activeBackend.openUri(Uri.parse(resolvedUrl), headers: headers),
            tag: 'openUri');
      } else if (track.isRemote) {
        await _safe(() => _activeBackend.openUrl(track.uri), tag: 'openUrl');
      } else if (_isLocalFilePath(track.uri)) {
        // 真实本地文件路径（含 file://）：剥离 scheme 后正常打开。
        final String path = track.uri.startsWith('file://')
            ? Uri.parse(track.uri).toFilePath()
            : track.uri;
        await _safe(() => _activeBackend.openPath(path), tag: 'openPath');
      } else {
        // 占位符（netease:///bili:// 等）解析失败却落到这里：绝不以文件路径
        // 打开非法 URI（原生层不可捕获崩溃）。判加载失败，回落 idle。
        LogService.instance.e('audio',
            '占位符解析失败，未打开: ${track.title} uri=${_redact(track.uri)}');
        _currentTrack = null;
        return;
      }
      if (_disposed) return;
      _currentTrack = track;
      _trackCtrl.add(_currentTrack);
      // T12 CUE 分轨：加载后从 INDEX 01 起点开始播（seek 到 cueStartMs）。
      final int cueStart = track.cueStartMs ?? 0;
      if (cueStart > 0) {
        await _safe(
          () => _activeBackend.seek(Duration(milliseconds: cueStart)),
          tag: 'cueSeek',
        );
      }
      LogService.instance.i('audio', '加载成功: ${track.title}');
    } catch (e) {
      // 注意：异常文本本身常内嵌完整 uri（just_audio 会把 source 塞进
      // PlatformException.message），故连异常一起过 [_redact] 的兜底层
      // （LogService 写盘前扫描），此处再显式给出脱敏 uri 便于定位。
      LogService.instance.e('audio',
          '加载失败: ${track.title} uri=${_redact(track.uri)} -> $e');
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
        await _safe(() => _activeBackend.pause(), tag: 'pause');
        _state = PlaybackState.paused;
        LogService.instance.i('audio', '暂停');
        break;
      case PlaybackState.paused:
        // 先恢复目标音量再 play（防止残留淡出把音量压成 0）。
        _cancelFades();
        await _safe(
          () => _activeBackend.setVolume(_musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol),
          tag: '音量恢复',
        );
        await _ensureSpeedOnPlay();
        await _safe(() => _activeBackend.play(), tag: 'play');
        _state = PlaybackState.playing;
        LogService.instance.i('audio', '继续播放');
        break;
    }
  }

  /// 跳转播放位置（进度条拖动 seek）
  Future<void> seek(Duration position) async {
    await _safe(() => _activeBackend.seek(position), tag: 'seek');
  }

  /// 仅暂停（系统媒体控件「暂停」用，不切换状态为其它）
  Future<void> pauseOnly() async {
    if (_state == PlaybackState.playing) {
      await _safe(() => _activeBackend.pause(), tag: 'pauseOnly');
      _state = PlaybackState.paused;
      LogService.instance.i('audio', '暂停（系统/打断）');
    }
  }

  /// 仅续播（系统媒体控件「播放」用）
  Future<void> resume() async {
    if (_state == PlaybackState.paused) {
      // 先恢复目标音量（防止残留淡出静音，R20）。
      _cancelFades();
      await _safe(
        () => _activeBackend.setVolume(_musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol),
        tag: '音量恢复',
      );
      await _ensureSpeedOnPlay();
      await _safe(() => _activeBackend.play(), tag: 'resume');
      _state = PlaybackState.playing;
      LogService.instance.i('audio', '续播（系统）');
    }
  }

  /// 临时压低/恢复音量（音频焦点被其它应用 duck 时用，不改变记忆音量）
  Future<void> setDuck(bool ducked) async {
    if (_activeBackend.playing) {
      await _safe(
        () => _activeBackend.setVolume(
            ducked ? 0.15 * _masterVol : (_musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol)),
        tag: 'setDuck',
      );
    }
  }

  /// 播放一次性事件音效（短音效，叠加在音乐/音景之上）。
  /// 「我的世界」主题音效调度器调用。
  /// R23i：输出音量 = 单次音量 × 音效通道 × 主音量。
  Future<void> playSfx(String path, {double volume = 0.25}) async {
    try {
      await _sfx.setVolume((volume * _sfxVol * _masterVol).clamp(0.0, 1.0));
      await _sfx.setAudioSource(AudioSource.file(path), preload: true);
      await _sfx.play();
      // 原实现 `path.split('/').last` 在 Windows 反斜杠路径下等于原样输出，
      // 会把 `C:\Users\<真实用户名>\...` 写进 app.log —— 统一改走 _redact。
      LogService.instance.i('audio', 'SFX: ${_redact(path)}');
    } catch (e) {
      LogService.instance.w('audio', 'SFX 播放失败: ${_redact(path)} -> $e');
    }
  }

  /// 停止事件音效（离开「我的世界」主题时调用）
  Future<void> stopSfx() async {
    try {
      await _sfx.stop();
    } catch (_) {}
  }

  // ── 白噪音（R4 语义修正：控制当前场景音景）──────────

  /// 白噪音开关（R23i：独立通道，不再控制场景音景）。
  ///
  /// 开：独立白噪播放器循环播程序合成白噪 wav，叠加在音乐/音景之上；
  /// 关：暂停白噪播放器。场景音景由「背景声」开关独立控制，互不影响。
  Future<void> setWhiteNoise(bool on) async {
    if (_whiteNoiseOn == on) return;
    _whiteNoiseOn = on;
    try {
      if (on) {
        await _wn.setReleaseMode(ap.ReleaseMode.loop);
        if (!_wnLoaded) {
          final String path = await SoundscapeGenerator.ensureWhiteNoise();
          await _wn.setSource(ap.DeviceFileSource(path));
          _wnLoaded = true;
        }
        await _wn.setVolume(_wnVol * _masterVol);
        await _wn.resume();
      } else {
        await _wn.pause();
      }
    } catch (e) {
      LogService.instance.w('audio', '白噪音播放失败 -> $e');
    }
    LogService.instance.i('audio', '白噪音: ${on ? '开' : '关'}');
  }

  /// 设置白噪音音量（R23i：独立通道音量，不再映射音景）。
  Future<void> setWhiteNoiseVolume(double v) async {
    _wnVol = v.clamp(0.0, 1.0);
    if (_whiteNoiseOn) {
      await _safe(() => _wn.setVolume(_wnVol * _masterVol), tag: 'setWnVol');
    }
  }

  /// 主音量（Master，R23i）：全局整体音量，所有通道输出 × master。
  Future<void> setMasterVolume(double v) async {
    _masterVol = v.clamp(0.0, 1.0);
    LogService.instance.i('audio', '主音量: ${(_masterVol * 100).round()}%');
    if (_activeBackend.playing) {
      await _safe(
        () => _activeBackend.setVolume(
            _musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol),
        tag: 'setMasterVolume_music',
      );
    }
    if (_activeSoundscapeId != null) {
      await _safe(
        () => _activeSc.setVolume(_scMuted ? 0.0 : _scVol * _masterVol),
        tag: 'setMasterVolume_sc',
      );
    }
    if (_whiteNoiseOn) {
      await _safe(
        () => _wn.setVolume(_wnVol * _masterVol),
        tag: 'setMasterVolume_wn',
      );
    }
  }

  /// 倍速播放（R26skel：播放体验优化）。[rate] = 1.0 为原速，0.25~4.0。
  ///
  /// 仅在播放中即时下发；未播放时只记忆，下次 [playMusic]/[resume] 自动套用。
  /// 后端切换（[MusicBackend] 会重置为 1.0）也由播放时 [_ensureSpeedOnPlay] 补偿。
  Future<void> setMusicSpeed(double rate) async {
    _musicSpeed = rate.clamp(0.25, 4.0);
    LogService.instance.i('audio', '倍速: ${_musicSpeed}x');
    if (_activeBackend.playing) {
      await _safe(() => _activeBackend.setSpeed(_musicSpeed), tag: 'setMusicSpeed');
    }
  }

  /// 播放/续播时套用倍速的单一入口（#483：收口 playMusic / togglePlay / resume）。
  ///
  /// 后端切换（[MusicBackend] 会重置为 1.0）也由播放时这里补偿。三处起播/续播
  /// 调用点统一走 [_ensureSpeedOnPlay]，避免遗漏或重复实现。
  Future<void> _ensureSpeedOnPlay() =>
      _safe(() => _activeBackend.setSpeed(_musicSpeed), tag: 'applySpeed');

  /// 音效（SFX）通道音量（R23i：独立于音乐/背景/白噪）。
  Future<void> setSfxVolume(double v) async {
    _sfxVol = v.clamp(0.0, 1.0);
    LogService.instance.i('audio', '音效音量: ${(_sfxVol * 100).round()}%');
  }

  /// 世界空间音效通道音量（#170）。
  ///
  /// 仅记忆权威值；真正的增益下发在体素视图内由 `WorldAudioEngine` 完成
  /// （引擎实例随 3D 视图创建/销毁，服务层不持有它）。
  Future<void> setWorldSfxVolume(double v) async {
    _worldVol = v.clamp(0.0, 1.0);
    LogService.instance.i('world', '世界空间音效音量: ${(_worldVol * 100).round()}%');
  }

  /// 提示音通道音量（#170：界面操作反馈音）。
  Future<void> setUiCueVolume(double v) async {
    _uiCueVol = v.clamp(0.0, 1.0);
    LogService.instance.i('uiCue', '提示音音量: ${(_uiCueVol * 100).round()}%');
  }

  // ── 分类反馈音（#170）─────────────────────────────

  /// 上次反馈音时间：拖动滑块会高频触发，节流避免叠成噪音。
  DateTime _lastCue = DateTime.fromMillisecondsSinceEpoch(0);

  /// 播放某分类的**代表性反馈音**（#170：调整该分类音量时的听觉确认）。
  ///
  /// 音量按「该分类自身的通道音量 × 主音量」计算 —— 用户拖动白噪音滑块时
  /// 听到的 shhh 就是调整后的真实响度，所听即所得。
  /// 节流 220ms：连续拖动只出声一次，不会糊成一片。
  Future<void> playCategoryCue(AudioCategory cat) async {
    final DateTime now = DateTime.now();
    if (now.difference(_lastCue).inMilliseconds < 220) return;
    _lastCue = now;

    // 该分类自身音量作为反馈音响度（所听即所得）。
    final double channel = switch (cat) {
      AudioCategory.music => _musicVol,
      AudioCategory.soundscape => _scVol,
      AudioCategory.whiteNoise => _wnVol,
      AudioCategory.sfx => _sfxVol,
      AudioCategory.worldSpatial => _worldVol,
      AudioCategory.uiCue => _uiCueVol,
    };
    final double vol = (channel * _masterVol).clamp(0.0, 1.0);
    if (vol <= 0.001) return; // 静音时不必出声

    try {
      final String path = await SoundscapeGenerator.ensureCategoryCue(cat.tag);
      await _cue.setReleaseMode(ap.ReleaseMode.stop);
      await _cue.setVolume(vol);
      await _cue.play(ap.DeviceFileSource(path));
    } catch (e) {
      LogService.instance.w('audio', '${cat.label}反馈音播放失败 -> $e');
    }
  }

  // ── 音量均衡（R15）───────────────────────────────

  /// 设置均衡模式：高保真（原始动态）/ 普通（响度归一化 + 轻压缩）。
  Future<void> setBalanceMode(BalanceMode mode) async {
    if (_balanceMode == mode) return;
    _balanceMode = mode;
    // 立即以新模式重算当前音量（若在播放）
    if (_activeBackend.playing) {
      await _safe(
        () => _activeBackend.setVolume(_musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol),
        tag: 'setBalanceVolume',
      );
    }
  }

  /// 应用均衡模式的最终输出音量。
  ///
  /// - 高保真：原样返回；
  /// - 普通：轻度压缩 + 响度归一化（`0.35v + 0.65·v^0.6`，低音量更清晰）。
  double _effectiveVolume(double v) {
    if (_balanceMode == BalanceMode.hifi) return v.clamp(0.0, 1.0);
    final double clamped = v.clamp(0.0, 1.0);
    return (0.35 * clamped + 0.65 * pow(clamped, 0.6)).clamp(0.0, 1.0);
  }

  // ── 场景音景（双播放器 crossfade） ─────────────────

  /// 切换场景音景：新音景淡入与旧音景淡出并行，无突兀。
  ///
  /// R3：音景播放器已用 `mixWithOthers` 焦点，切换场景**不会**打断音乐。
  Future<void> switchSoundscape(Scene scene) async {
    final String sceneId = scene.id;
    final int seq = ++_scSeq;
    if (_activeSoundscapeId == sceneId) return;

    LogService.instance.i('audio', '切换音景: $sceneId');

    // R23g：优先用用户素材片段（assets/audio，AssetSource）；
    // 素材无映射 → 回退 Minecraft 环境音 / 程序合成。
    final String? asset = AmbientSoundscapeService.assetFor(scene);
    String? path;
    if (asset == null) {
      try {
        // 1) 优先用 Minecraft 真实环境音（或用户自定义音景文件）
        final String? ambient =
            await AmbientSoundscapeService.ambientPathFor(scene);
        if (ambient != null) {
          path = ambient;
          LogService.instance.i(
              'audio', '音景使用 Minecraft 环境音: ${_redact(path)}');
        } else {
          // 2) 无匹配则程序合成
          path = await SoundscapeGenerator.ensureSceneSoundscape(sceneId);
        }
      } catch (e) {
        LogService.instance.e('audio', '音景生成失败: $sceneId -> $e');
        return;
      }
    } else {
      LogService.instance.i('audio', '音景使用素材: $asset');
    }
    // 期间又有更新的请求，放弃本次
    if (seq != _scSeq) return;

    final ap.AudioPlayer next = _activeSc == _scA ? _scB : _scA;
    final ap.AudioPlayer prev = _activeSc;

    try {
      await next.setReleaseMode(ap.ReleaseMode.loop);
      if (asset != null) {
        await next.setSource(ap.AssetSource(asset));
      } else {
        await next.setSource(ap.DeviceFileSource(path!));
      }
      await next.setVolume(0.0);
      await next.resume();

      // 并行：新淡入，旧淡出（后台，不阻塞切换）。
      // R23i：旧播放器从当前实际音量淡出（可能已被 master 缩放）。
      await Future.wait([
        _fadeSoundscape(next, 0.0, _scMuted ? 0.0 : _scVol * _masterVol, const Duration(seconds: 3)),
        _fadeSoundscape(prev, prev.volume, 0.0, const Duration(seconds: 3)),
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
      // R23i：音景不再受白噪开关控制（背景/白噪已独立）。
    } catch (_) {
      // 音景失败不影响主流程；同样清理本次 next，防止孤儿。
      // 注意：必须经 _safe 兜底 —— 裸 unawaited 的 Future 若失败会变成
      // 未捕获异步异常（Wear OS 上 stop() 可能抛 PlatformException）。
      unawaited(_safe(() => next.stop(), tag: 'switchSoundscapeCleanup'));
    }
  }

  // ── 独立声音设置：音乐声 / 背景声 分离 ───────────────

  /// 音乐声目标音量（0.0~1.0，R12 默认 0.7 = 70%）
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
    final double out = _musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol;
    if (_activeBackend.playing) {
      await _safe(() => _activeBackend.setVolume(out), tag: 'setMusicVolume');
    }
  }

  /// 音乐声静音切换
  Future<void> setMusicMuted(bool m) async {
    _musicMuted = m;
    LogService.instance.i('audio', '音乐声静音: ${m ? '开' : '关'}');
    if (_activeBackend.playing) {
      await _safe(
        () => _activeBackend.setVolume(m ? 0.0 : _effectiveVolume(_musicVol) * _masterVol),
        tag: 'setMusicMuted',
      );
    }
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
      await _safe(
        () => _activeSc.setVolume(_scMuted ? 0.0 : _scVol * _masterVol),
        tag: 'setSoundscapeVolume',
      );
    }
  }

  /// 背景声静音切换
  Future<void> setSoundscapeMuted(bool m) async {
    _scMuted = m;
    LogService.instance.i('audio', '背景声静音: ${m ? '开' : '关'}');
    if (_activeSoundscapeId != null) {
      await _safe(
        () => _activeSc.setVolume(m ? 0.0 : _scVol),
        tag: 'setSoundscapeMuted',
      );
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

    if (_activeBackend.playing) {
      unawaited(_fadeMusic(_activeBackend.volume, _musicMuted ? 0.0 : _effectiveVolume(_musicVol) * _masterVol, const Duration(milliseconds: 1200)));
    }
    if (_activeSoundscapeId != null) {
      unawaited(_fadeSoundscape(_activeSc, _activeSc.volume, _scMuted ? 0.0 : _scVol * _masterVol, const Duration(milliseconds: 1200)));
    }
  }

  // ── 音量渐变工具 ───────────────────────────────────

  /// cl46 自动过渡：快速淡出当前曲（1.5s），供「接近末尾自动切歌」使用。
  /// 下一首经 [playMusic] 播放，自带淡入。
  Future<void> fadeOutMusic() =>
      _fadeMusic(1.0, 0.0, const Duration(milliseconds: 1500));

  Future<void> _fadeMusic(double from, double to, Duration duration) async {
    // 带序号：每次调用自增；被更新的淡入取代时立即退出，避免并发
    // 写 volume 互相覆盖（旧淡出把新曲音量压成 0 的静音 bug，R20）。
    final int seq = ++_fadeSeq;
    const int steps = 16;
    if (duration.inMilliseconds <= 0) {
      await _safe(() => _activeBackend.setVolume(to), tag: 'fadeMusic');
      return;
    }
    final Duration step = duration ~/ steps;
    for (int i = 1; i <= steps; i++) {
      if (seq != _fadeSeq) return; // 已被更新的淡入取代
      await _safe(
        () => _activeBackend.setVolume(from + (to - from) * i / steps),
        tag: 'fadeMusic',
      );
      await Future<void>.delayed(step);
    }
  }

  /// 作废所有在途淡变：让任何正在循环的 [_fadeMusic] 下一次 `seq != _fadeSeq`
  /// 检查即退出。playMusic / 续播 / resume 在直接 setVolume 前务必调用，否则
  /// 旧曲淡出（line 350，操作同一个共享 _music、末步 setVolume(0)）会在后台把刚
  /// 起播的新曲音量压成 0 → "播 1 秒后静音，须拖主音量恢复"（R20 的 _fadeSeq
  /// 守卫因新曲路径不走 _fadeMusic 而从未被触发，故需显式作废）。
  void _cancelFades() => _fadeSeq++;

  Future<void> _fadeSoundscape(ap.AudioPlayer p, double from, double to, Duration duration) async {
    const int steps = 16;
    if (duration.inMilliseconds <= 0) {
      await _safe(() => p.setVolume(to), tag: 'fadeSoundscape');
      return;
    }
    final Duration step = duration ~/ steps;
    for (int i = 1; i <= steps; i++) {
      await _safe(
        () => p.setVolume(from + (to - from) * i / steps),
        tag: 'fadeSoundscape',
      );
      await Future<void>.delayed(step);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _stateCtrl.close();
    await _playingCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _completedCtrl.close();
    await _trackCtrl.close();
    await _playErrorCtrl.close();
    // 双后端都要释放（#393）。
    await _safe(() => _justAudioBackend.dispose(), tag: 'disposeJA');
    await _safe(() => _mediaKitBackend.dispose(), tag: 'disposeMK');
    await _safe(() => _sfx.dispose(), tag: 'disposeSfx');
    await _safe(() => _scA.dispose(), tag: 'disposeScA');
    await _safe(() => _scB.dispose(), tag: 'disposeScB');
    await _safe(() => _wn.dispose(), tag: 'disposeWn');
    await _safe(() => _cue.dispose(), tag: 'disposeCue');
  }
}
