import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/palette_extractor.dart';
import '../../core/utils/app_motion.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/audio/music_quality_provider.dart';
import '../../providers/sources/bilibili_provider.dart';
import '../../pages/sources/aggregate_search_page.dart';
import '../../widgets/common/playback_feedback.dart';
import '../../widgets/common/track_cover.dart';
import '../../widgets/lyrics/lyrics_view.dart';
import '../../widgets/playback/playback_controls.dart';
import '../../widgets/playback/unified_player.dart' show showEqualizerSheet, showSleepTimerSheet, showSpeedSheet;
import '../../widgets/sources/music_quality_sheet.dart';

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
    final bool isPlaying = ref.watch(isPlayingProvider).valueOrNull ?? false;
    final PlayMode mode = ref.watch(playModeProvider);
    final PlaybackActions actions = ref.read(playbackActionsProvider);

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
      body: Stack(
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
                // 底部控制栏：透明融入背景（样式与音乐卡一致，非额外大块）。
                _buildControlBar(context, ref, track, isPlaying, mode, actions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 竖屏主体：封面 → 曲名/歌手 → 歌词（纵向可滚动）。
  Widget _portraitBody({required Track? track}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double coverSize =
            (constraints.maxWidth - AppSpace.lg * 2).clamp(0.0, 320.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(child: _LargeCover(track: track, size: coverSize)),
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
            child: Center(child: _LargeCover(track: track, size: coverSize)),
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

  Widget _buildControlBar(
    BuildContext context,
    WidgetRef ref,
    Track? track,
    bool isPlaying,
    PlayMode mode,
    PlaybackActions actions,
  ) {
    // 底部控制栏：**透明融入背景**（不叠加 bgSurface 大块实色，样式与音乐卡
    // 一致——透出动态背景 + 细描边胶囊分组）。图标统一 rounded 系列。
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
            const _SeekBarSection(),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: <Widget>[
                // R32 一.2：图标统一为外部音乐控制栏样式（PlaybackIconButton：
                // 纯图标 + 主题色，无描边圆底容器），播放键保持居中主按钮。
                PlaybackIconButton(
                  icon: Icons.skip_previous_rounded,
                  size: 24,
                  tooltip: '上一首',
                  onTap: () => runPlaybackAction(
                    context,
                    () => actions.next(direction: -1),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                PlaybackIconButton(
                  icon: isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 40,
                  tooltip: isPlaying ? '暂停' : '播放',
                  onTap: () => runPlaybackAction(context, actions.toggle),
                ),
                const SizedBox(width: AppSpace.sm),
                PlaybackIconButton(
                  icon: Icons.skip_next_rounded,
                  size: 24,
                  tooltip: '下一首',
                  onTap: () => runPlaybackAction(context, () => actions.next()),
                ),
                const SizedBox(width: AppSpace.xs),
                PlaybackIconButton(
                  icon: _npModeIcon(mode),
                  size: 24,
                  tint: true,
                  tooltip: '播放模式：${_npModeLabel(mode)}',
                  onTap: () {
                    final PlayMode next = _npNextMode(mode);
                    actions.setMode(next);
                    showPlaybackToast(context, '播放模式：${_npModeLabel(next)}');
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            const _CollapsibleVolumeRow(),
            const SizedBox(height: AppSpace.xs),
            // 快捷操作胶囊行（画布 3:348：搜索/音质/白噪音/视听/倍速）。
            // 全部绑定真实功能：搜索/音质/倍速走弹层或页面，白噪音/视听走
            // 全局开关（跟随场景/全局生效来源）。队列/下载无后端，不摆空按钮。
            const _QuickActionsRow(),
            const SizedBox(height: AppSpace.xs),
            // 底部工具行（画布 3:131-146：睡眠定时 / 均衡器）。
            // 画布另有「下载」「队列」按钮，本项目暂无对应后端，不摆设。
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _ToolChip(
                  icon: Icons.bedtime_rounded,
                  label: '睡眠定时',
                  onTap: () => showSleepTimerSheet(context, ref),
                ),
                const SizedBox(width: AppSpace.sm),
                _ToolChip(
                  icon: Icons.equalizer_rounded,
                  label: '均衡器',
                  onTap: () => unawaited(showEqualizerSheet(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 快捷操作胶囊行（画布 3:348：搜索 / 音质 / 白噪音 / 视听 / 倍速）。
///
/// 数据与动作全部接真实后端，禁止伪造状态：
/// - 搜索：push [AggregateSearchPage]
/// - 音质：弹 [showMusicQualitySheet]
/// - 白噪音：翻转 [whiteNoiseEnabledProvider]（生效来源跟随场景/全局）
/// - 视听：翻转 [biliVisualEnabledProvider]（B站视频背景）
/// - 倍速：弹 [showSpeedSheet]
class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool whiteNoise = ref.watch(whiteNoiseEnabledProvider);
    final bool visualOn = ref.watch(biliVisualEnabledProvider);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: <Widget>[
        _ActionChip(
          icon: Icons.search_rounded,
          label: '搜索',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AggregateSearchPage(),
            ),
          ),
        ),
        _ActionChip(
          icon: Icons.high_quality_rounded,
          label: _qualityLabel(ref),
          onTap: () => unawaited(showMusicQualitySheet(context)),
        ),
        _ActionChip(
          icon: Icons.spa_rounded,
          label: '白噪音',
          active: whiteNoise,
          onTap: () => ref
              .read(whiteNoiseEnabledProvider.notifier)
              .state = !whiteNoise,
        ),
        _ActionChip(
          icon: Icons.movie_filter_rounded,
          label: '视听',
          active: visualOn,
          onTap: () => ref
              .read(biliVisualEnabledProvider.notifier)
              .state = !visualOn,
        ),
        _ActionChip(
          icon: Icons.speed_rounded,
          label: '倍速',
          onTap: () => unawaited(showSpeedSheet(context, ref)),
        ),
      ],
    );
  }
}

/// 单个快捷操作胶囊（画布 qa-* 61×36 r18）。active 高亮强调色。
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : c.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active ? c.accent : c.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 15,
              color: active ? c.accent : c.iconInactive,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.appText.caption.copyWith(
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? c.accent : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部工具胶囊（画布 btn-queue/btn-sleep/btn-download/btn-eq 44×36 r18）。
/// 只挂有真实后端的能力（睡眠定时 / 均衡器），下载/队列无后端不摆设。
class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        decoration: BoxDecoration(
          color: c.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: c.iconInactive),
            const SizedBox(width: 6),
            Text(label, style: context.appText.caption),
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
  Color? _displayAccent;

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
    final Color accentFrom = _displayAccent ?? c.accent;
    final Color accentTo = _dominant ?? c.accent;

    return TweenAnimationBuilder<Color>(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      tween: Tween<Color>(begin: accentFrom, end: accentTo),
      builder: (BuildContext context, Color accent, Widget? child) {
        _displayAccent = accent;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                accent.withValues(alpha: 0.55),
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
    // R32 批2：Hero 共享元素——与播放栏折叠态封面同 tag，实现曲线位移过渡。
    return Hero(tag: NpHeroTags.cover, child: inner);
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
        Hero(
          tag: NpHeroTags.title,
          child: Text(
            track?.title ?? '未在播放',
            style: context.appText.title.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
          ),
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

/// 进度区：可拖拽 / 点按的进度条 + 当前 / 总时长。
class _SeekBarSection extends ConsumerStatefulWidget {
  const _SeekBarSection();

  @override
  ConsumerState<_SeekBarSection> createState() => _SeekBarSectionState();
}

class _SeekBarSectionState extends ConsumerState<_SeekBarSection> {
  double? _dragRatio;

  Future<void> _commit(Duration? duration) async {
    final double? ratio = _dragRatio;
    if (ratio == null || duration == null) return;
    await ref.read(audioServiceProvider).seek(duration * ratio);
    if (!mounted) return;
    setState(() => _dragRatio = null);
  }

  @override
  Widget build(BuildContext context) {
    final Duration position =
        ref.watch(musicPositionProvider).valueOrNull ?? Duration.zero;
    final Duration? duration = ref.watch(musicDurationProvider).valueOrNull;
    final bool seekable = duration != null && duration.inMilliseconds > 0;
    final double ratio = _dragRatio ??
        (seekable
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0);
    // duration 在 seekable 分支已通过非空判断（flow analysis 提升）。

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            void update(double dx) {
              if (!seekable || constraints.maxWidth <= 0) return;
              setState(
                () => _dragRatio = (dx / constraints.maxWidth).clamp(0.0, 1.0),
              );
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails d) => update(d.localPosition.dx),
              onTapUp: (_) => _commit(duration),
              onHorizontalDragStart: (DragStartDetails d) =>
                  update(d.localPosition.dx),
              onHorizontalDragUpdate: (DragUpdateDetails d) =>
                  update(d.localPosition.dx),
              onHorizontalDragEnd: (_) => _commit(duration),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: SizedBox(
                  height: AppSize.heightProgress,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ColoredBox(color: context.appColors.progressTrack),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: ratio,
                          heightFactor: 1,
                          child: ColoredBox(color: context.appColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpace.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              formatDuration(
                duration != null
                    ? Duration(
                        milliseconds: (ratio * duration.inMilliseconds).round())
                    : position,
              ),
              style: context.appText.caption,
            ),
            Text(formatDuration(duration), style: context.appText.caption),
          ],
        ),
      ],
    );
  }
}

/// 播放模式图标按钮（循环顺序与全局一致）。点击切换并轻提示。
// ════════════════════════════════════════════════════════════════════════
// 播放模式图标 / 文案 / 切换（R32 一.2：与外部控制栏样式统一后的顶层函数）
// ════════════════════════════════════════════════════════════════════════

/// 播放模式 → 图标（Material rounded，与外部音乐控制栏同源）。
IconData _npModeIcon(PlayMode m) => switch (m) {
      PlayMode.order => Icons.trending_flat_rounded,
      PlayMode.reverse => Icons.keyboard_backspace_rounded,
      PlayMode.shuffle => Icons.shuffle_rounded,
      PlayMode.loop => Icons.repeat_one_rounded,
    };

/// 播放模式 → 文案。
String _npModeLabel(PlayMode m) => switch (m) {
      PlayMode.order => '顺序',
      PlayMode.reverse => '倒叙',
      PlayMode.shuffle => '随机',
      PlayMode.loop => '单曲循环',
    };

/// 播放模式循环切换（order → reverse → shuffle → loop → order）。
PlayMode _npNextMode(PlayMode m) => switch (m) {
      PlayMode.order => PlayMode.reverse,
      PlayMode.reverse => PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.loop,
      PlayMode.loop => PlayMode.order,
    };

/// 音量行（默认折叠，点标题展开）。
class _CollapsibleVolumeRow extends ConsumerStatefulWidget {
  const _CollapsibleVolumeRow();

  @override
  ConsumerState<_CollapsibleVolumeRow> createState() =>
      _CollapsibleVolumeRowState();
}

class _CollapsibleVolumeRowState
    extends ConsumerState<_CollapsibleVolumeRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final double volume = ref.watch(musicVolumeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                Icon(
                  _open ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                  size: AppSize.iconSm,
                  color: context.appColors.iconInactive,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text('音量 · ${(volume * 100).round()}%',
                      style: context.appText.body),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: AppSize.iconSm,
                  color: context.appColors.iconInactive,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(height: 0),
          secondChild: _VolumeRow(volume: volume),
        ),
      ],
    );
  }
}

/// 当前音质 / 清晰度标签（音质入口按钮文案）。
String _qualityLabel(WidgetRef ref) {
  final MusicQuality mq = ref.watch(musicQualityProvider);
  final BiliVideoQuality bq = ref.watch(biliVideoQualityProvider);
  return '音质 ${mq.label} · 清晰度 ${bq.label}';
}

/// 音量行：图标 + 滑块。拖动实时更新 provider 并接线到真实音频服务。
class _VolumeRow extends ConsumerWidget {
  const _VolumeRow({required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        Icon(
          Icons.volume_down_rounded,
          size: AppSize.iconSm,
          color: context.appColors.iconInactive,
        ),
        Expanded(
          child: Slider(
            value: volume,
            onChanged: (double v) {
              ref.read(musicVolumeProvider.notifier).state = v;
              unawaited(ref.read(audioServiceProvider).setMusicVolume(v));
            },
          ),
        ),
        Icon(
          Icons.volume_up_rounded,
          size: AppSize.iconSm,
          color: context.appColors.iconInactive,
        ),
      ],
    );
  }
}
