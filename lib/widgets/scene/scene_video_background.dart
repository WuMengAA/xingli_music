/// ════════════════════════════════════════════════════════════════════════
/// B站视频 · 场景背景（R26skel-b4）
/// ════════════════════════════════════════════════════════════════════════
///
/// 当当前播放曲目来自 B站视频源（`sourceId == 'bilibili'`）时，把该视频的
/// **画面流**作为场景/播放器背景实时播放（默认静音——背景只听主播放器的
/// 音乐，视频画面随音乐一起播）。非 B站曲目 / 解析失败 / 平台不支持时
/// 回退到 [fallback]（通常是体素场景背景）。
///
/// ⚠️ **仅在场景页/播放器背景使用，绝不接入 3D 游戏**（用户明确要求
/// 「不在游戏中放视频」）。本组件不依赖游戏任何渲染管线。
///
/// 静音策略：背景视频 Player 独立于 AudioService 的音乐播放器，`setVolume(0)`
/// 只作用于背景视频自身，不影响主音乐音量。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/music_quality_provider.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../services/audio/sources/bilibili/bilibili_source.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant SceneVideoBackground old) {
    super.didUpdateWidget(old);
    if (old.fallback != widget.fallback) {
      // fallback 变化（如切场景）不打断视频；仅在有需要时重查。
    }
  }

  @override
  Widget build(BuildContext context) {
    // 曲目变化（B站 ↔ 其它 / 停止）→ 同步背景视频。
    ref.listen<Track?>(nowPlayingProvider, (Track? _, Track? t) => _sync());
    if (!_videoReady || _failed) return widget.fallback;
    final VideoController? c = _controller;
    if (c == null) return widget.fallback;
    return Video(controller: c, fit: BoxFit.cover);
  }

  /// 按当前曲目同步背景视频：B站曲目 → 播画面（静音）；否则停止回退。
  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final Track? t = ref.read(nowPlayingProvider);
      final String? bvid =
          (t != null && t.sourceId == BilibiliSource.kSourceId)
              ? BilibiliSource.bvidOf(t)
              : null;
      if (bvid == null) {
        await _teardown();
        if (mounted) setState(() {
          _videoReady = false;
          _failed = false;
        });
        return;
      }
      // 已在播同一 bvid → 不动。
      if (_player != null && _currentBvid == bvid) return;
      await _teardown();
      if (!mounted) return;
      setState(() {
        _videoReady = false;
        _failed = false;
      });
      try {
        MediaKit.ensureInitialized();
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
            .resolveVideoUrl(bvid, qualityIndex: qIdx);
        if (!mounted) return;
        final Player p = Player();
        final VideoController vc = VideoController(p);
        await p.open(Media(
          url,
          httpHeaders: const <String, String>{
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.bilibili.com/',
          },
        ));
        // 默认静音：只影响背景视频，不动主音乐音量。
        await p.setVolume(0.0);
        await p.play();
        _currentBvid = bvid;
        _player = p;
        _controller = vc;
        if (!mounted) {
          await _teardown();
          return;
        }
        setState(() => _videoReady = true);
      } catch (e) {
        // 解析/播放失败 → 回退背景，不抛不崩。
        await _teardown();
        if (mounted) setState(() => _failed = true);
      }
    } finally {
      _syncing = false;
    }
  }

  String? _currentBvid;

  Future<void> _teardown() async {
    _currentBvid = null;
    // VideoController 生命周期挂在 Player 上：dispose Player 即清理。
    _controller = null;
    final Player? p = _player;
    _player = null;
    if (p != null) {
      try {
        await p.dispose();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
