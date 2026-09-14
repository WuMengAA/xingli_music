/// ════════════════════════════════════════════════════════════════════════
/// 主页 · 沉浸播放器（2026-09-14 重构）
/// ════════════════════════════════════════════════════════════════════════
///
/// 取代原 [HomeSceneContent] 的「场景卡堆」为主页主体。用户需求：
/// ① 取消独立「正在播放页」（整页 [NowPlayingPage] 入口保留给游戏内 HUD /
///    扩展场景，主页直接承载播放器）；
/// ② 封面 + 歌词移入主页 —— 做成 Apple Music / 网易云风格的沉浸播放器：
///    全屏封面动态背景 + 大唱片封面（播放旋转）+ 曲名/歌手 + 频谱 + 歌词
///    + 完整控制栏。
///
/// 场景切换降级为「右上角入口」——点开弹出场景选择浮窗（复用 [SceneCardStack]），
/// 不再占主页主体。切场景仅切换音景层与视觉，不中断当前音乐（R5）。
///
/// 复用 [UnifiedPlayer] 的公开构建辅助（[buildTransportRow] / [buildVolumePanel]
/// / [buildBottomActions] / [ProgressSlider]），保证双端视觉一致、零重复逻辑。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../core/utils/palette_extractor.dart';
import '../../../models/track.dart';
import '../../../models/scene.dart';
import '../../../models/track_stats.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/stats/track_stats_providers.dart';
import '../../../providers/scene/scene_providers.dart';
import '../../../providers/session/session_providers.dart';
import '../../../providers/shell/shell_providers.dart';
import '../../../widgets/common/track_cover.dart';
import '../../../widgets/lyrics/lyrics_view.dart';
import '../../../widgets/visualizer/spectrum_bars.dart';
import '../../../widgets/visualizer/reactor_visualizer.dart';
import '../../../widgets/card_stack.dart';
import 'unified_player.dart';

/// 主页沉浸播放器（常驻 [IndexedStack] 第 0 页）。
class HomeImmersivePlayer extends ConsumerStatefulWidget {
  const HomeImmersivePlayer({super.key});

  @override
  ConsumerState<HomeImmersivePlayer> createState() =>
      _HomeImmersivePlayerState();
}

class _HomeImmersivePlayerState extends ConsumerState<HomeImmersivePlayer>
    with SingleTickerProviderStateMixin {
  bool _volOpen = false;
  late final AnimationController _coverSpin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    if (ref.read(isPlayingProvider).valueOrNull ?? false) _coverSpin.repeat();
  }

  @override
  void dispose() {
    _coverSpin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Track? track = ref.watch(nowPlayingProvider);
    // 播放态切换时启停唱片旋转；暂停即平滑停转，省 CPU。
    ref.listen<AsyncValue<bool>>(isPlayingProvider, (_, AsyncValue<bool> next) {
      final bool playing = next.valueOrNull ?? false;
      if (playing && !_coverSpin.isAnimating) {
        _coverSpin.repeat();
      } else if (!playing && _coverSpin.isAnimating) {
        _coverSpin.stop();
      }
    });

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 动态背景：封面提色渐变（半透，让下层视频/几何透出）。
        Positioned.fill(child: _PlayerDynamicBackground(track: track)),
        // 音效反应堆：随音乐脉冲的网格柱阵 + 流星（主题⑦·唱片+反应堆）。
        const Positioned.fill(child: ReactorVisualizer(opacity: 0.4)),
        // 前景内容（安全区 + 布局）。
        SafeArea(
          child: Column(
            children: <Widget>[
              // 顶部：问候 + 品牌 + 场景入口。诉求⑧：滚动时随顶栏一起淡出折叠。
              AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: ref.watch(topBarAutoHideProvider) ? 0.0 : 1.0,
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.topCenter,
                  child: ref.watch(topBarAutoHideProvider)
                      ? const SizedBox.shrink()
                      : _HomeTopBar(onOpenScenes: _showSceneSheet),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext c, BoxConstraints bc) {
                    final bool landscape =
                        bc.maxWidth >= bc.maxHeight * 1.1;
                    if (landscape) {
                      return _landscapeBody(track: track, maxHeight: bc.maxHeight);
                    }
                    return _portraitBody(track: track);
                  },
                ),
              ),
              // 底部控制栏（复用 UnifiedPlayer 公开 builder）。
              _HomeControlBar(
                volOpen: _volOpen,
                onToggleVol: () => setState(() => _volOpen = !_volOpen),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 竖屏主体：大唱片 → 曲名/歌手 → 频谱 → 歌词。
  Widget _portraitBody({required Track? track}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: AppSpace.sm),
          Center(child: _DiscCover(track: track, spin: _coverSpin, size: 240)),
          const SizedBox(height: AppSpace.lg),
          _TrackTitle(track: track),
          const SizedBox(height: AppSpace.sm),
          const SpectrumBars(height: 44),
          const SizedBox(height: AppSpace.md),
          LyricsView(height: 220),
        ],
      ),
    );
  }

  /// 横屏主体：左封面、右信息 + 歌词。
  Widget _landscapeBody({required Track? track, required double maxHeight}) {
    final double coverSize = (maxHeight * 0.6).clamp(160.0, 320.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: coverSize + AppSpace.sm,
            child: Center(
              child: _DiscCover(
                track: track,
                spin: _coverSpin,
                size: coverSize,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TrackTitle(track: track, alignLeft: true),
                const SizedBox(height: AppSpace.xs),
                const SpectrumBars(height: 36),
                const SizedBox(height: AppSpace.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext c, BoxConstraints bc) =>
                        LyricsView(height: bc.maxHeight),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出场景选择浮窗（复用 [SceneCardStack]，场景切换降级为入口）。
  Future<void> _showSceneSheet() async {
    final List<Scene> scenes = ref.read(sceneOrderProvider);
    final int activeIndex = ref.read(currentSceneIndexProvider);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text('场景', style: context.appText.title),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: SceneCardStack(
                    scenes: scenes,
                    currentIndex: activeIndex,
                    onLongPress: () => Navigator.of(sheetCtx).pop(),
                    onSceneChanged: (int i) {
                      HapticFeedback.lightImpact();
                      ref.read(currentSceneIndexProvider.notifier).state = i;
                      final Scene scene = scenes[i];
                      unawaited(
                        ref.read(audioServiceProvider).switchSoundscape(scene),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 背景动态配色层（封面提色渐变 + 封面模糊 + 顶部暗化）。
class _PlayerDynamicBackground extends ConsumerStatefulWidget {
  const _PlayerDynamicBackground({required this.track});

  final Track? track;

  @override
  ConsumerState<_PlayerDynamicBackground> createState() =>
      _PlayerDynamicBackgroundState();
}

class _PlayerDynamicBackgroundState extends ConsumerState<_PlayerDynamicBackground> {
  Color? _dominant;
  Color? _prevAccent;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  @override
  void didUpdateWidget(covariant _PlayerDynamicBackground old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) _extract();
  }

  Future<void> _extract() async {
    final Color? c = await PaletteExtractor.dominantOf(widget.track);
    if (mounted && c != null) setState(() => _dominant = c);
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final Color a = _dominant ?? c.accent;

    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: ColorTween(begin: _prevAccent ?? c.accent, end: a),
      onEnd: () => _prevAccent = a,
      builder: (BuildContext context, Color? accent, Widget? child) {
        final Color col = accent ?? c.accent;
        // 半透明提色渐变：**让下层 B站视频背景 + 几何浮动透出**，封面以
        // 前景唱片形式展示（诉求②④⑤⑥ 和谐共存）。仅作氛围，不挡视频/几何。
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                col.withValues(alpha: 0.30),
                c.bgPage.withValues(alpha: 0.5),
              ],
              stops: const <double>[0, 0.7],
            ),
          ),
          // 顶部/底部压暗，保证文字与控制栏可读。
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x44000000),
                  Colors.transparent,
                  Colors.transparent,
                  Color(0x55000000),
                ],
                stops: <double>[0, 0.18, 0.7, 1],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 大唱片封面（黑胶质感）：圆形封面 + 中心轴孔 + 播放时旋转。
class _DiscCover extends StatelessWidget {
  const _DiscCover({
    required this.track,
    required this.spin,
    required this.size,
  });

  final Track? track;
  final Animation<double> spin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final bool hasImage = track != null &&
        ((track!.coverPath?.isNotEmpty ?? false) ||
            (track!.coverUrl?.isNotEmpty ?? false));
    final Widget inner = hasImage
        ? TrackCover(track: track, size: size, radius: size / 2)
        : Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[c.accentSoft, c.accent],
              ),
            ),
            child: Center(
              child: Icon(
                Icons.music_note_rounded,
                size: size * 0.36,
                color: c.onAccent,
              ),
            ),
          );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 唱片底盘（黑胶外环）。
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.85),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          // 旋转封面（带圆形裁切）。
          AnimatedBuilder(
            animation: spin,
            child: Padding(
              padding: EdgeInsets.all(size * 0.06),
              child: ClipOval(child: inner),
            ),
            builder: (BuildContext context, Widget? child) => Transform.rotate(
              angle: spin.value * 2 * math.pi,
              child: child,
            ),
          ),
          // 中心轴孔。
          Container(
            width: size * 0.12,
            height: size * 0.12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.bgPage,
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 曲名 + 歌手（空曲目引导文案）。
class _TrackTitle extends StatelessWidget {
  const _TrackTitle({required this.track, this.alignLeft = false});

  final Track? track;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final TextAlign align = alignLeft ? TextAlign.left : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          track?.title ?? '星璃 · 无限音乐空间',
          style: context.appText.title.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          track?.artist ?? '从曲库挑一首开始',
          style: context.appText.body.copyWith(color: Colors.white70),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ],
    );
  }
}

/// 主页顶部条：问候 + 品牌 + 场景入口。
class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({required this.onOpenScenes});

  final VoidCallback onOpenScenes;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final String greet = _greeting(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  greet,
                  style: context.appText.caption.copyWith(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '星璃音乐',
                  style: context.appText.title.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // 场景入口（原场景卡堆降级为小入口）。
          Material(
            color: Colors.white.withValues(alpha: 0.12),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onOpenScenes,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting(DateTime now) {
    final int h = now.hour;
    if (h >= 5 && h < 11) return '早安，新的一天听点什么？';
    if (h >= 11 && h < 14) return '午安，听点什么？';
    if (h >= 14 && h < 18) return '下午好，听点什么？';
    if (h >= 18 && h < 23) return '晚上好，听点什么？';
    return '夜深了，听点什么？';
  }
}

/// 主页底部控制栏：复用 [UnifiedPlayer] 公开 builder，视觉与全屏页一致。
class _HomeControlBar extends ConsumerStatefulWidget {
  const _HomeControlBar({
    required this.volOpen,
    required this.onToggleVol,
  });

  final bool volOpen;
  final VoidCallback onToggleVol;

  @override
  ConsumerState<_HomeControlBar> createState() => _HomeControlBarState();
}

class _HomeControlBarState extends ConsumerState<_HomeControlBar> {
  @override
  Widget build(BuildContext context) {
    final WidgetRef ref = this.ref;
    final bool whiteNoise = ref.watch(whiteNoiseEnabledProvider);
    final Track? now = ref.watch(nowPlayingProvider);
    final String favKey = now == null
        ? ''
        : trackKeyOf(now.title, now.artist, now.sourceId);
    final bool isFav = favKey.isEmpty
        ? false
        : (ref.watch(isFavoriteProvider(favKey)).value ?? false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          buildVolumePanel(ref, widget.volOpen),
          const SizedBox(height: AppSpace.xs),
          ProgressSlider(
            onSeek: (double v) => unawaited(
              ref.read(audioServiceProvider).seek(
                Duration(milliseconds: v.round()),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          buildTransportRow(
            context,
            ref,
            fullscreen: false,
            volOpen: widget.volOpen,
            onToggleVol: widget.onToggleVol,
            lyricsOpen: false,
            onToggleLyrics: () {},
            isFav: isFav,
            onToggleFav: () {
              if (now == null) return;
              unawaited(toggleFavoriteTrack(ref, now));
            },
          ),
          const SizedBox(height: AppSpace.sm),
          buildBottomActions(
            context,
            ref,
            whiteNoise: whiteNoise,
            onToggleWhiteNoise: () => ref
                .read(whiteNoiseEnabledProvider.notifier)
                .state = !whiteNoise,
          ),
        ],
      ),
    );
  }
}