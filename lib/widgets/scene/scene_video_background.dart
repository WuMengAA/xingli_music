/// ════════════════════════════════════════════════════════════════════════
/// B站视频 · 场景背景（R26skel-b4 / cl48 重构）
/// ════════════════════════════════════════════════════════════════════════
///
/// 当「视听结合」开关开启时，按**当前曲目名**自动搜 B站视频，把其
/// **画面流**作为场景/播放器背景实时播放（默认静音——背景只听主播放器的
/// 音乐，视频画面随音乐一起播）。无匹配 / 解析失败 / 关闭开关时
/// 回退到 [fallback]（通常是体素场景背景）。
///
/// ⚠️ **仅在场景背景层使用，绝不接入 3D 游戏**（用户明确要求
/// 「不在游戏中放视频」）。本组件不依赖游戏任何渲染管线。
///
/// ### cl48 新增能力
/// - **模糊**：`biliVisualBlurProvider`（默认关）——对背景视频叠加少量模糊。
/// - **进度同步**：`biliVisualSyncProvider`（默认开）——视频画面跟随主音乐
///   播放进度（漂移超阈值即校正）。
/// - **变速适配**：`biliVisualTempoAdaptProvider`（默认关）——视频与音乐时长
///   相差过大时，实时调整视频速率使其与音乐同步推进。
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/music_quality_provider.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../services/audio/sources/bilibili/bilibili_api.dart';

/// B站视频场景背景。
///
/// 包一层 [fallback]：B站视频未就绪/不可用时显示 fallback（体素背景等）。
class SceneVideoBackground extends ConsumerStatefulWidget {
  const SceneVideoBackground({super.key, required this.fallback});

  /// 视频不可用时的回退背景（体素取景 / 渐变等）。
  final Widget fallback;

  @override
  ConsumerState<SceneVideoBackground> createState() =>
      _SceneVideoBackgroundState();
}

class _SceneVideoBackgroundState extends ConsumerState<SceneVideoBackground> {
  Player? _player;
  VideoController? _controller;
  bool _videoReady = false;
  bool _failed = false;
  bool _syncing = false;

  /// 当前搜索的曲目 key（防过期：切歌后旧请求结果直接丢弃）。
  String? _currentKey;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    // 周期性校正：进度同步 + 变速适配（默认 500ms）。
    _syncTimer = Timer.periodic(const Duration(milliseconds: 500), _onTick);
    // cl53-F6：跟随音乐播放状态——暂停时视频暂停，播放时继续，停止则回退。
    _playingSub = ref.read(audioServiceProvider).playingStream.listen(
          _onPlayingChanged,
        );
  }

  StreamSubscription<bool>? _playingSub;

  void _onPlayingChanged(bool playing) {
    if (!mounted || !_videoReady || _player == null) return;
    final Player p = _player!;
    if (playing) {
      unawaited(p.play());
    } else {
      unawaited(p.pause());
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _playingSub?.cancel();
    _playingSub = null;
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 曲目变化 → 同步背景视频。
    ref.listen<Track?>(nowPlayingProvider, (Track? _, Track? __) => _sync());
    // 开关变化 → 立即重算（开启匹配当前曲 / 关闭停播）。
    ref.listen<bool>(biliVisualEnabledProvider,
        (bool? _, bool __) => _sync());

    final bool blur = ref.watch(biliVisualBlurProvider);
    if (!_videoReady || _failed) return widget.fallback;
    final VideoController? c = _controller;
    if (c == null) return widget.fallback;
    Widget video = Video(controller: c, fit: BoxFit.cover);
    if (blur) {
      // 少许模糊（默认关闭），让背景画面更柔和、不喧宾夺主。
      video = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: video,
      );
    }
    return video;
  }

  /// 按当前曲目同步背景视频：开启 + 有曲目 → 按歌名搜 B站播画面（静音）；
  /// 否则停止回退。
  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final bool enabled = ref.read(biliVisualEnabledProvider);
      final Track? t = ref.read(nowPlayingProvider);
      if (!enabled || t == null) {
        await _teardown();
        if (mounted) {
          setState(() {
            _videoReady = false;
            _failed = false;
          });
        }
        return;
      }
      final String key = '${t.title}|${t.artist}';
      // 已在播同一曲目 → 不动。
      if (key == _currentKey && _player != null) return;
      await _teardown();
      if (!mounted) return;
      setState(() {
        _videoReady = false;
        _failed = false;
        _currentKey = key;
      });
      try {
        MediaKit.ensureInitialized();
        final BilibiliApi api = ref.read(bilibiliApiProvider);
        // 按歌名搜公开接口（未登录也可），取首个匹配。
        final List<BiliVideoLite> vids =
            await api.searchVideos(t.title, pageSize: 5);
        if (!mounted || key != _currentKey) return;
        if (vids.isEmpty) {
          if (mounted) setState(() => _failed = true);
          return;
        }
        final BiliVideoQuality bq = ref.read(biliVideoQualityProvider);
        // 清晰度档 → DASH 档位索引（0=最高；smooth 取最低=大索引被 api 夹到末档）。
        final int qIdx = switch (bq) {
          BiliVideoQuality.auto || BiliVideoQuality.uhd4k => 0,
          BiliVideoQuality.ultra => 1,
          BiliVideoQuality.hd => 2,
          BiliVideoQuality.smooth => 16,
        };
        final String url = await ref
            .read(bilibiliSourceProvider)
            .resolveVideoUrl(vids.first.bvid, qualityIndex: qIdx);
        if (!mounted || key != _currentKey) return;
        final Player p = Player();
        final VideoController vc = VideoController(p);
        await p.open(Media(
          url,
          httpHeaders: const <String, String>{
            'User-Agent': kBilibiliUserAgent,
            'Referer': 'https://www.bilibili.com/',
          },
        ));
        // 默认静音：只影响背景视频，不动主音乐音量。
        await p.setVolume(0.0);
        await p.play();
        _currentKey = key;
        _player = p;
        _controller = vc;
        if (!mounted) {
          await _teardown();
          return;
        }
        setState(() => _videoReady = true);
      } catch (_) {
        // 解析/播放失败 → 回退背景，不抛不崩。
        await _teardown();
        if (mounted) setState(() => _failed = true);
      }
    } finally {
      _syncing = false;
    }
  }

  /// 周期性校正：进度同步 + 变速适配。
  void _onTick(Timer _) {
    if (!mounted || !_videoReady || _player == null) return;
    final Player p = _player!;
    final bool sync = ref.read(biliVisualSyncProvider);
    final bool tempo = ref.read(biliVisualTempoAdaptProvider);
    if (sync) {
      final Duration? musicPos = ref.read(musicPositionProvider).value;
      if (musicPos != null) {
        final Duration vPos = p.state.position;
        // 漂移超 600ms 才校正，避免频繁 seek 造成卡顿/抖动。
        if ((vPos - musicPos).inMilliseconds.abs() > 600) {
          unawaited(p.seek(musicPos));
        }
      }
    }
    if (tempo) {
      final Duration vDur = p.state.duration;
      final Duration? mDur = ref.read(musicDurationProvider).value;
      if (mDur != null &&
          vDur.inSeconds > 0 &&
          mDur.inSeconds > 0) {
        // 时长相差 > 5s 才调速，避免轻微差异引发速率抖动。
        if ((vDur - mDur).inSeconds.abs() > 5) {
          final double rate =
              (vDur.inMilliseconds / mDur.inMilliseconds).clamp(0.5, 2.0);
          unawaited(p.setRate(rate));
        } else {
          unawaited(p.setRate(1.0));
        }
      }
    } else if (p.state.rate != 1.0) {
      // 关闭变速适配时确保速率回归正常。
      unawaited(p.setRate(1.0));
    }
  }

  Future<void> _teardown() async {
    _currentKey = null;
    // VideoController 生命周期挂在 Player 上：dispose Player 即清理。
    _controller = null;
    final Player? p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.setRate(1.0);
      } catch (_) {}
      try {
        await p.dispose();
      } catch (_) {}
    }
  }
}
