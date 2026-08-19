import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/utils/format.dart';
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
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: context.appColors.bgPage,
        foregroundColor: context.appColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
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
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            // 中部：封面 + 曲名 + 歌词（可滚动）
            Expanded(
              child: LayoutBuilder(
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
              ),
            ),
            // 底部固定控制栏（仿画布：主操作 FilledButton + 次操作 OutlinedButton）
            _buildControlBar(context, ref, track, isPlaying, mode, actions),
          ],
        ),
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
    final AppThemeColors c = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.lg,
      ),
      decoration: BoxDecoration(
        color: c.bgSurface.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(
            color: c.border.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
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
                OutlinedButton.icon(
                  onPressed: () => runPlaybackAction(
                    context,
                    () => actions.next(direction: -1),
                  ),
                  icon: const Icon(Icons.skip_previous, size: 20),
                  label: const Text('上一首'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => runPlaybackAction(context, actions.toggle),
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 22,
                    ),
                    label: Text(isPlaying ? '暂停' : '播放'),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                OutlinedButton.icon(
                  onPressed: () =>
                      runPlaybackAction(context, () => actions.next()),
                  icon: const Icon(Icons.skip_next, size: 20),
                  label: const Text('下一首'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: AppSpace.xs),
                _ModeIconButton(mode: mode, actions: actions),
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
    if (hasImage) {
      return TrackCover(track: t, size: size, radius: AppRadius.lg);
    }
    return ClipRRect(
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
              Icons.music_note,
              size: size * 0.4,
              color: context.appColors.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}

/// 歌名 + 歌手（空曲目时展示引导文案）。
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          track?.title ?? '未在播放',
          style: context.appText.title.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          track?.artist ?? '从曲库挑一首开始',
          style: context.appText.bodyMuted,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
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
class _ModeIconButton extends ConsumerWidget {
  const _ModeIconButton({required this.mode, required this.actions});

  final PlayMode mode;
  final PlaybackActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(
        _modeIcon(mode),
        size: 22,
        color: context.appColors.iconPrimary,
      ),
      tooltip: '播放模式：${_modeLabel(mode)}',
      onPressed: () {
        final PlayMode next = _nextMode(mode);
        actions.setMode(next);
        showPlaybackToast(context, '播放模式：${_modeLabel(next)}');
      },
    );
  }

  IconData _modeIcon(PlayMode m) => switch (m) {
        PlayMode.order => Icons.trending_flat,
        PlayMode.reverse => Icons.keyboard_backspace,
        PlayMode.shuffle => Icons.shuffle,
        PlayMode.loop => Icons.repeat_one,
      };

  String _modeLabel(PlayMode m) => switch (m) {
        PlayMode.order => '顺序',
        PlayMode.reverse => '倒叙',
        PlayMode.shuffle => '随机',
        PlayMode.loop => '单曲循环',
      };

  PlayMode _nextMode(PlayMode m) => switch (m) {
        PlayMode.order => PlayMode.reverse,
        PlayMode.reverse => PlayMode.shuffle,
        PlayMode.shuffle => PlayMode.loop,
        PlayMode.loop => PlayMode.order,
      };
}

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
          Icons.volume_down,
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
          Icons.volume_up,
          size: AppSize.iconSm,
          color: context.appColors.iconInactive,
        ),
      ],
    );
  }
}
