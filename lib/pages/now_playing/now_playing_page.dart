import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/utils/palette_extractor.dart';
import '../../core/utils/app_motion.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../models/track_stats.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/stats/track_stats_providers.dart';
import '../../pages/sources/aggregate_search_page.dart';
import '../../widgets/common/track_cover.dart';
import '../../widgets/lyrics/lyrics_view.dart';
import '../../widgets/playback/unified_player.dart';

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
class NowPlayingPage extends ConsumerWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Track? track = ref.watch(nowPlayingProvider);

    return Scaffold(
      // 背景动态配色：由封面模糊层 + 主题色渐变组成（见 _DynamicBackground），
      // 页内不再叠加整块实色。
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: context.appColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          tooltip: '收起',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(Terms.playing, style: context.appText.title),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: '聚合搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AggregateSearchPage(),
              ),
            ),
          ),
        ],
      ),
      body: Hero(
        // R32 批3：整卡放大过渡——与播放栏紧凑卡同 tag，点开时整页主体
        // 随播放卡放大（覆盖整屏），封面/歌词内部的独立 Hero 继续提供
        // 位移细节；同一 tag 两端（播放卡↔整页）配对成共享元素动画。
        tag: NpHeroTags.card,
        child: Stack(
          children: <Widget>[
            // ── 背景动态配色层（封面模糊 + 主题渐变 + 底部压暗）──
            Positioned.fill(child: _DynamicBackground(track: track)),
            // ── 前景内容层 ──
            SafeArea(
              top: false,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final bool landscape =
                            constraints.maxWidth >= constraints.maxHeight;
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
                  // 底部控制栏：直接复用音乐控制栏的控件样式（unified_player
                  // 的 buildTransportRow / ProgressSlider / buildVolumePanel /
                  // buildBottomActions），整屏与卡完全一致，不另设计。
                  const _NpControlBar(),
                ],
              ),
            ),
          ],
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
                child: _BreathingCover(
                  child: _LargeCover(track: track, size: coverSize),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              _TrackInfo(track: track),
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
              child: _BreathingCover(
                child: _LargeCover(track: track, size: coverSize),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          // 右：信息 + 歌词（歌词撑满剩余高度）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TrackInfo(track: track, alignLeft: true),
                const SizedBox(height: AppSpace.sm),
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


/// 背景动态配色层。
///
/// 组合（自上而下）：
/// 1. **封面提色渐变**：实时提取封面主色（[PaletteExtractor]）→ 主色渐变
///    铺底，切曲时 [TweenAnimationBuilder] 平滑过渡；叠封面模糊层（sigma 24，
///    性价比档）作为氛围，让背景主色随封面自然变化。
/// 2. **动态粒子**：[ParticleLayer] 随音乐能量/节拍飘动（自定义 Ticker，
///    不污染 build 树）。
/// 3. **光源遮罩**：顶部 radial 光晕（accent 派生）模拟「封面光源」，
///    增强层次；底部压暗 scrim 保证控制栏文字可读。
class _DynamicBackground extends ConsumerStatefulWidget {
  const _DynamicBackground({required this.track});

  final Track? track;

  @override
  ConsumerState<_DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends ConsumerState<_DynamicBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  /// 当前曲目封面提取的主色（R32 一.4）；未提取到则回退 accent。
  Color? _dominant;

  /// 上一帧实际显示的主色（供 [TweenAnimationBuilder] 作平滑过渡起点）。
  /// 仅在动画 [onEnd] 时更新，绝不写在 build 内（避免 build 期状态写入
  /// 触发的重建/无限循环）。
  Color? _prevAccent;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  @override
  void didUpdateWidget(covariant _DynamicBackground old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) _extract();
  }

  Future<void> _extract() async {
    final Color? c = await PaletteExtractor.dominantOf(widget.track);
    if (mounted && c != null) setState(() => _dominant = c);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final Track? t = widget.track;
    final bool hasImage = t != null &&
        ((t.coverUrl?.isNotEmpty ?? false) || (t.coverPath?.isNotEmpty ?? false));
    // R32 一.4：提色渐变。begin=上一帧显示色，end=提取主色（未提取到用 accent
    // 兜底），切曲时 700ms easeOutCubic 平滑过渡；提取完成后再自然过渡到新色。
    final Color accentFrom = _prevAccent ?? c.accent;
    final Color accentTo = _dominant ?? c.accent;

    return TweenAnimationBuilder<Color?>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: ColorTween(begin: accentFrom, end: accentTo),
      // 仅在动画结束后落定「上一帧主色」，供下次切曲作平滑起点；
      // 不写在 builder 内，避免 build 期写入状态导致重建/无限循环。
      onEnd: () {
        _prevAccent = accentTo;
      },
      builder: (BuildContext context, Color? accent, Widget? child) {
        final Color a = accent ?? c.accent;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                a.withValues(alpha: 0.55),
                c.bgPage,
              ],
              stops: const <double>[0, 0.7],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // ① 封面提色渐变：模糊 + 轻微提亮，背景主色随封面变化。
              if (hasImage)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Transform.scale(
                    scale: 1.4,
                    child: ColorFiltered(
                      // 提色：压暗 + 提饱和，让封面主色渗入背景而非整图清晰呈现。
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.9, 0, 0, 0, 0, //
                        0, 0.9, 0, 0, 0, //
                        0, 0, 0.9, 0, 0, //
                        0, 0, 0, 0.75, 0, //
                      ]),
                      child: _CoverImage(track: t, fit: BoxFit.cover),
                    ),
                  ),
                ),
              // ② 动态粒子（随播放能量/节拍）。
              Positioned.fill(child: ParticleLayer(pulse: _pulse)),
              // ③ 光源遮罩：顶部 radial 光晕（封面光源感）。
              Positioned(
                top: -80,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 300,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.4),
                        radius: 0.9,
                        colors: <Color>[
                          c.accent.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 底部压暗：保证控制栏文字可读。
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Color(0x55000000),
                    ],
                    stops: <double>[0.55, 1],
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

/// 动态粒子背景层：随 [pulse]（3s 循环）缓慢漂浮的发光圆点，
/// 数量/大小跟随画面宽度自适应，纯 CustomPaint 不污染 build 树。
class ParticleLayer extends StatelessWidget {
  const ParticleLayer({super.key, required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _ParticlePainter(pulse.value),
          isComplex: true,
          willChange: true,
        );
      },
    );
  }
}

/// 粒子画笔：固定种子生成一组粒子，按 [t]（0..1 循环）漂移 + 呼吸。
class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    final int n = (size.width / 18).clamp(8, 40).round();
    for (int i = 0; i < n; i++) {
      // 伪随机（固定种子，避免每帧跳动）。
      final double seed = (i * 2654435761) % 10000 / 10000;
      final double seed2 = (i * 40503) % 10000 / 10000;
      final double x =
          (seed * size.width + t * size.width * 0.12) % size.width;
      final double y =
          (seed2 * size.height - t * size.height * 0.2) % size.height;
      final double r = 1.2 + seed2 * 2.2;
      final double alpha = 0.10 + 0.14 * (0.5 + 0.5 * (t + seed) % 1);
      paint.color = const Color(0xFFFFFFFF).withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}

/// 封面图（网络 / 本地 / 降级）。供 [TrackCover] 与背景模糊层复用。
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.track, this.fit = BoxFit.cover});

  final Track track;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final String? url = track.coverUrl;
    final String? path = track.coverPath;
    final Widget fallback = ColoredBox(
      color: c.accentSoft,
      child: Icon(Icons.music_note_rounded, size: 64, color: c.accent),
    );
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (BuildContext c2, Widget child, ImageChunkEvent? p) =>
            p == null ? child : fallback,
      );
    }
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: fit,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}

/// 大封面：有封面图 → [TrackCover]（含加载失败降级）；无图 → accent 渐变占位。
class _LargeCover extends StatelessWidget {
  const _LargeCover({required this.track, required this.size});

  final Track? track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Track? t = track;
    final bool hasImage = t != null &&
        ((t.coverPath?.isNotEmpty ?? false) ||
            (t.coverUrl?.isNotEmpty ?? false));
    final Widget inner = hasImage
        ? TrackCover(track: t, size: size, radius: AppRadius.lg)
        : ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                context.appColors.accentSoft,
                context.appColors.accent,
              ],
            ),
          ),
          child: Center(
            child: Icon(
              Icons.music_note_rounded,
              size: size * 0.4,
              color: context.appColors.onAccent,
            ),
          ),
        ),
      ),
    );
    // R32 批3：整卡 Hero 已覆盖封面/标题的位移（外层 body 包 npCard 放大），
    // 此处不再单独包封面 Hero，避免嵌套 Hero 双飞冲突。
    // cl04：封面浮起阴影（iOS 唱片感 + WinUI shadow 层级）。
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: inner,
    );
  }
}

/// 全屏封面呼吸动效（cl04）：播放时封面极轻微呼吸（±1.5%，6s 正弦），
/// 暂停即平滑归位——「有温度的活感」，不喧宾夺主。
class _BreathingCover extends ConsumerStatefulWidget {
  const _BreathingCover({required this.child});

  final Widget child;

  @override
  ConsumerState<_BreathingCover> createState() => _BreathingCoverState();
}

class _BreathingCoverState extends ConsumerState<_BreathingCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool playing = ref.watch(isPlayingProvider).valueOrNull ?? false;
    if (playing) {
      _ctrl.repeat();
    } else {
      _ctrl.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        // 正弦呼吸 ±1.5%，整周期回落到 1.0。
        final double s = 1 + 0.015 * math.sin(_ctrl.value * math.pi * 2);
        return Transform.scale(scale: s, child: child);
      },
    );
  }
}

/// 歌名 + 歌手（空曲目时展示引导文案）。
///
/// [alignLeft]：横屏布局下左对齐（默认居中，竖屏用）。
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.track, this.alignLeft = false});

  final Track? track;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    final TextAlign align =
        alignLeft ? TextAlign.left : TextAlign.center;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          track?.title ?? '未在播放',
          style: context.appText.title.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          track?.artist ?? '从曲库挑一首开始',
          style: context.appText.bodyMuted,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
        ),
      ],
    );
  }
}

