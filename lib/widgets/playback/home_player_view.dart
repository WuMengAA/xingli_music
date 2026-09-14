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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_colors.dart';
import '../../../core/theme/light_tokens.dart';
import '../../../models/track.dart';
import '../../../models/scene.dart';
import '../../../models/track_stats.dart';
import '../../../providers/audio/audio_providers.dart';
import '../../../providers/stats/track_stats_providers.dart';
import '../../../providers/scene/scene_providers.dart';
import '../../../providers/session/session_providers.dart';
import '../../../providers/shell/shell_providers.dart';
import '../../../widgets/lyrics/lyrics_view.dart';
import '../../../widgets/visualizer/spectrum_bars.dart';
import '../../../widgets/visualizer/reactor_visualizer.dart';
import '../../../widgets/card_stack.dart';
import 'immersive_player_visuals.dart';
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

    return ImmersiveSurface(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 动态背景（与整页正在播放共用 ImmersiveBackground；主页让下层视频透出）。
          Positioned.fill(
            child: ImmersiveBackground(track: track, videoThrough: true),
          ),
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
                      final bool landscape = bc.maxWidth >= bc.maxHeight * 1.1;
                      if (landscape) {
                        return _landscapeBody(
                          track: track,
                          maxHeight: bc.maxHeight,
                        );
                      }
                      return _portraitBody(track: track);
                    },
                  ),
                ),
                // 播放失败时常驻的错误 + 重试提示（与正在播放页共用同一组件）。
                const PlaybackErrorBanner(),
                // 底部控制栏（复用 UnifiedPlayer 公开 builder）。
                _HomeControlBar(
                  volOpen: _volOpen,
                  onToggleVol: () => setState(() => _volOpen = !_volOpen),
                ),
              ],
            ),
          ),
        ],
      ),
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
          Center(child: ImmersiveDiscCover(track: track, spin: _coverSpin, size: 240)),
          const SizedBox(height: AppSpace.lg),
          ImmersiveTrackTitle(track: track),
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
              child: ImmersiveDiscCover(
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
                ImmersiveTrackTitle(track: track, alignLeft: true),
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
                    shadows: kImmersiveTextShadow,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '星璃音乐',
                  style: context.appText.title.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: kImmersiveTextShadow,
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
            // 主页已是全屏沉浸形态：用 fullscreen:true 隐藏冗余的歌词钮
            // （歌词本就内联常显），并把播放键/侧键放大到与全屏页一致的
            // 40/28，消除「全屏界面用紧凑控件」的不一致。
            fullscreen: true,
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