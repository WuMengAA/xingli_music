import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/utils/app_motion.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../pages/explore/experiments/equalizer_page.dart';
import '../../pages/sources/aggregate_search_page.dart';
import '../../widgets/lyrics/lyrics_view.dart';
import '../../widgets/playback/immersive_player_visuals.dart';
import '../../widgets/playback/unified_player.dart';
import '../../widgets/visualizer/reactor_visualizer.dart';
import '../../widgets/visualizer/spectrum_bars.dart';

/// 整页正在播放（#552：从零重建）。
///
/// 取代 [UnifiedPlayer] 的透明 Overlay 全屏播放——用户反馈「不要简简单单的透明
/// 背景」。点击音乐卡信息区（[MusicCard] 默认 `onOpenNowPlaying`）即 `Navigator.push`
/// 至此整页。
///
/// ### 布局（底部控制栏仿 [voxel_canvas_page]）
/// - 顶部：返回（收起）+ 标题「正在播放」。
/// - 中部：大封面 + 曲名 + 歌手 + 歌词（可滚动）。
/// - **底部固定控制栏**：主操作 FilledButton（播放 / 暂停，占满）+ 次操作
///   OutlinedButton（上一首 / 下一首）+ 播放模式切换；其上为进度条、其下为
///   可折叠音量 + 音质入口。
///
/// 数据源全部来自既有 provider（唯一真源，禁止本地 setState 推断播放态）：
/// - [nowPlayingProvider] 当前曲目
/// - [isPlayingProvider] 播放 / 暂停（永远与引擎一致）
/// - [musicPositionProvider] / [musicDurationProvider] 进度
/// - [playModeProvider] 播放模式
/// - [musicVolumeProvider] 音量
/// - [playbackActionsProvider] 播放动作唯一入口（返回值经 toast 消费）
class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  /// 封面唱片旋转（24s/圈），与主页沉浸播放器一致；暂停即停转省 CPU。
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    if (ref.read(isPlayingProvider).valueOrNull ?? false) _spin.repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Track? track = ref.watch(nowPlayingProvider);
    // 播放态切换时启停唱片旋转；暂停即平滑停转，省 CPU。
    ref.listen<AsyncValue<bool>>(isPlayingProvider, (_, AsyncValue<bool> next) {
      final bool playing = next.valueOrNull ?? false;
      if (playing && !_spin.isAnimating) {
        _spin.repeat();
      } else if (!playing && _spin.isAnimating) {
        _spin.stop();
      }
    });

    // ImmersiveSurface：把前景语义色切到「深色面」，使曲名/歌词/控件自动变浅色，
    // 与主页沉浸播放器**同一套视觉**（消除换页换皮）。
    return ImmersiveSurface(
      child: Scaffold(
        // 固定深色基座：与 [ImmersiveBackground] 的渐变基色同族。此处**不能**用
        // 透明——AppBar 条带不在 body 的 Stack 内，透明会让它与下方渐变之间出现
        // 一条底色不一致的横向断层。
        backgroundColor: const Color(0xFF0A0A12),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: context.appColors.textPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: '收起',
          ),
          title: Text(Terms.playing, style: context.appText.title),
          actions: <Widget>[
            // 均衡器一级入口（B 版毕业，2026-09-13）：真 EQ（Android 真滤波 /
            // Windows mpv DSP），从实验区毕业到播放器页直达。
            IconButton(
              icon: const Icon(Icons.graphic_eq_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const EqualizerPage()),
              ),
              tooltip: '音效均衡器',
            ),
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AggregateSearchPage(),
                ),
              ),
              tooltip: '聚合搜索',
            ),
          ],
        ),
        body: Hero(
          // R32 批3：整卡放大过渡——与播放栏紧凑卡同 tag，点开时整页主体
          // 随播放卡放大（覆盖整屏）。
          tag: NpHeroTags.card,
          child: Stack(
            children: <Widget>[
              // ── 背景：与主页共用 ImmersiveBackground（无视频透出 → 模糊封面底衬）──
              Positioned.fill(child: ImmersiveBackground(track: track)),
              // ── 音效反应堆（与主页一致，此前整页只有纯装饰粒子）──
              const Positioned.fill(child: ReactorVisualizer(opacity: 0.35)),
              // ── 前景内容层 ──
              SafeArea(
                top: false,
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          // 横屏阈值与主页对齐（×1.1）——消除两端进入横屏的临界差。
                          final bool landscape =
                              constraints.maxWidth >= constraints.maxHeight * 1.1;
                          // 横屏：封面在左、歌词在右；竖屏：封面→信息→歌词纵向。
                          if (landscape) {
                            return _landscapeBody(
                              track: track,
                              maxHeight: constraints.maxHeight,
                            );
                          }
                          return _portraitBody(track: track);
                        },
                      ),
                    ),
                    // 播放失败时常驻的错误 + 重试提示（与主页播放卡共用同一组件）。
                    const PlaybackErrorBanner(),
                    // 底部控制栏：复用 unified_player 的控件（在 ImmersiveSurface
                    // 内自动取深色面配色），整屏与卡/主页完全一致。
                    const _NpControlBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 竖屏主体：封面 → 曲名/歌手 → 歌词（纵向可滚动）。
  Widget _portraitBody({required Track? track}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double coverSize =
            (constraints.maxWidth - AppSpace.lg * 2).clamp(0.0, 380.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: ImmersiveDiscCover(
                  track: track,
                  spin: _spin,
                  size: coverSize.clamp(160.0, 320.0),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              ImmersiveTrackTitle(track: track),
              const SizedBox(height: AppSpace.sm),
              const SpectrumBars(height: 48),
              const SizedBox(height: AppSpace.lg),
              const LyricsView(),
            ],
          ),
        );
      },
    );
  }

  /// 横屏主体：封面在左（占 ~40%），右侧信息 + 歌词（占 ~60%）。
  Widget _landscapeBody({required Track? track, required double maxHeight}) {
    final double coverSize = (maxHeight - AppSpace.md * 2).clamp(0.0, 300.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 左：封面
          SizedBox(
            width: coverSize + AppSpace.sm,
            child: Center(
              child: ImmersiveDiscCover(
                track: track,
                spin: _spin,
                size: coverSize.clamp(160.0, 320.0),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          // 右：信息 + 歌词（歌词撑满剩余高度）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ImmersiveTrackTitle(track: track, alignLeft: true),
                const SizedBox(height: AppSpace.xs),
                const SpectrumBars(height: 40),
                SizedBox(height: AppSpace.sm),
                // 歌词自适应剩余高度（横屏下不再固定 160）。
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints c) {
                      return LyricsView(height: c.maxHeight);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 全屏播放页底部控制栏。
///
/// 直接复用音乐控制栏（[UnifiedPlayer]）的公开控件样式，保证双端视觉一致、
/// 不另设计：
/// - [buildTransportRow]：音量开关键 +（全屏态不显示歌词钮）+ 上一首/播放/
///   下一首/模式/收藏，与紧凑卡完全同源。
/// - [ProgressSlider]：主题感知进度条（自包含拖拽态）。
/// - [buildVolumePanel]：展开时显示六大音量分类面板。
/// - [buildBottomActions]：搜索/音质/白噪音/视听/音效/倍速/睡眠定时。
class _NpControlBar extends ConsumerStatefulWidget {
  const _NpControlBar();

  @override
  ConsumerState<_NpControlBar> createState() => _NpControlBarState();
}

class _NpControlBarState extends ConsumerState<_NpControlBar> {
  bool _volOpen = false;

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
        AppSpace.xs,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 音量面板（进度条上方，与音乐控制栏一致）。
            Consumer(
              builder: (BuildContext c, WidgetRef r, _) =>
                  buildVolumePanel(r, _volOpen),
            ),
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
              fullscreen: true,
              volOpen: _volOpen,
              onToggleVol: () => setState(() => _volOpen = !_volOpen),
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
      ),
    );
  }
}

