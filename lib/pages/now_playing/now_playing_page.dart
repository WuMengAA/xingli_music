import '../../core/theme/app_theme_colors.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/utils/format.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/audio/music_quality_provider.dart';
import '../../pages/sources/aggregate_search_page.dart';
import '../../widgets/common/playback_feedback.dart';
import '../../widgets/common/track_cover.dart';
import '../../widgets/sources/music_quality_sheet.dart';

/// 完整播放页（架构 §5 T05 / PRD P1-04、P1-05、P1-10、P1-12）
///
/// 由 `MiniPlayer` 左胶囊点击打开（`AppShell` 中接入 `Navigator.push`）。
/// 浅色扁平化页面，取色一律走 [AppColors] / [AppTextStyles]，
/// 禁止任何颜色十六进制字面量与暗色画布资产（门禁 C1 / V2）。
///
/// 数据源全部来自既有 provider（唯一真源，禁止本地 setState 推断播放态）：
/// - [nowPlayingProvider] 当前曲目
/// - [isPlayingProvider] 播放 / 暂停（Stream，永远与引擎一致）
/// - [musicPositionProvider] / [musicDurationProvider] 进度
/// - [playModeProvider] 播放模式
/// - [musicVolumeProvider] 音量
/// - [playbackActionsProvider] 播放动作唯一入口（返回值经 SnackBar 消费）
///
/// 窄屏兜底（P1-10）：整页放在 [SingleChildScrollView] 内，任意高度 / 320dp
/// 窄屏都不会溢出；封面尺寸由 [LayoutBuilder] 按可用宽度派生。
class NowPlayingPage extends ConsumerWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Track? track = ref.watch(nowPlayingProvider);
    final bool isPlaying =
        ref.watch(isPlayingProvider).valueOrNull ?? false;
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
        title: Text('正在播放', style: context.appText.title),
        actions: <Widget>[
          // R26skel-b6：音乐面板上的聚合搜索入口。
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
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // 封面 = 可用宽度减去左右内边距，封顶 320dp（P1-10 窄屏自适应）
            final double coverSize =
                (constraints.maxWidth - AppSpace.lg * 2).clamp(0.0, 320.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: AppSpace.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(child: _LargeCover(track: track, size: coverSize)),
                  const SizedBox(height: AppSpace.lg),
                  _TrackInfo(track: track),
                  const SizedBox(height: AppSpace.lg),
                  const _SeekBarSection(),
                  const SizedBox(height: AppSpace.lg),
                  _ControlsRow(
                    isPlaying: isPlaying,
                    mode: mode,
                    actions: actions,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  // R26skel-b6：音乐面板音质/清晰度入口（点开改）。
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: () => showMusicQualitySheet(context),
                      icon: const Icon(Icons.high_quality_rounded, size: 16),
                      label: Text(
                        _qualityLabel(ref),
                        style: context.appText.caption,
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  const _CollapsibleVolumeRow(),
                ],
              ),
            );
          },
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
    // 主色渐变占位（派生自 context.appColors.accent，不引动态主题）
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
              colors: <Color>[context.appColors.accentSoft, context.appColors.accent],
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

/// 进度区：可拖拽 / 点按的进度条 + 当前 / 总时长（P1-05）。
///
/// 直播流（`duration == null`）退化为纯装饰轨道，不响应手势（与 MiniPlayer
/// 同款策略）。拖拽中显示临时比例，松手后经 [audioServiceProvider.seek] 提交。
class _SeekBarSection extends ConsumerStatefulWidget {
  const _SeekBarSection();

  @override
  ConsumerState<_SeekBarSection> createState() => _SeekBarSectionState();
}

class _SeekBarSectionState extends ConsumerState<_SeekBarSection> {
  /// 拖拽中的临时比例；`null` = 未拖拽，跟随播放流
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
    final bool seekable =
        duration != null && duration.inMilliseconds > 0;
    final double ratio = _dragRatio ??
        (seekable
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0);

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
                        milliseconds:
                            (ratio * duration.inMilliseconds).round())
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

/// 4 个控制按钮：上一首 / 播放暂停 / 下一首 / 播放模式（P1-04）。
///
/// 所有动作走 [runPlaybackAction]，返回值（空串 = 成功）统一 SnackBar 消费。
/// 播放模式循环顺序与 `MiniPlayer` / `MorePanel` 完全一致。
class _ControlsRow extends StatelessWidget {
  const _ControlsRow({
    required this.isPlaying,
    required this.mode,
    required this.actions,
  });

  final bool isPlaying;
  final PlayMode mode;
  final PlaybackActions actions;

  static IconData _modeIcon(PlayMode m) => switch (m) {
        PlayMode.order => Icons.trending_flat,
        PlayMode.reverse => Icons.keyboard_backspace,
        PlayMode.shuffle => Icons.shuffle,
        PlayMode.loop => Icons.repeat_one,
      };

  static String _modeLabel(PlayMode m) => switch (m) {
        PlayMode.order => '顺序',
        PlayMode.reverse => '倒叙',
        PlayMode.shuffle => '随机',
        PlayMode.loop => '单曲循环',
      };

  static PlayMode _nextMode(PlayMode m) => switch (m) {
        PlayMode.order => PlayMode.reverse,
        PlayMode.reverse => PlayMode.shuffle,
        PlayMode.shuffle => PlayMode.loop,
        PlayMode.loop => PlayMode.order,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _ControlButton(
          icon: Icons.skip_previous,
          tooltip: '上一首',
          onTap: () => runPlaybackAction(
            context,
            () => actions.next(direction: -1),
          ),
        ),
        _ControlButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          tooltip: isPlaying ? '暂停' : '播放',
          primary: true,
          onTap: () => runPlaybackAction(context, actions.toggle),
        ),
        _ControlButton(
          icon: Icons.skip_next,
          tooltip: '下一首',
          onTap: () => runPlaybackAction(context, () => actions.next()),
        ),
        _ControlButton(
          icon: _modeIcon(mode),
          tooltip: '播放模式：${_modeLabel(mode)}',
          onTap: () {
            final PlayMode next = _nextMode(mode);
            actions.setMode(next);
            showPlaybackToast(context, '播放模式：${_modeLabel(next)}');
          },
        ),
      ],
    );
  }
}

/// 单个控制按钮：主按钮（播放/暂停）accent 圆底放大，其余浅底常规尺寸。
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final double size = primary ? 64 : 48;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary ? context.appColors.accent : context.appColors.bgControl,
          ),
          child: Icon(
            icon,
            size: primary ? 32 : AppSize.icon,
            color: primary ? context.appColors.onAccent : context.appColors.iconPrimary,
          ),
        ),
      ),
    );
  }
}

/// 音量行（R26skel-b6：默认折叠，点标题展开）。
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
                Icon(_open ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    size: AppSize.iconSm, color: context.appColors.iconInactive),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text('音量 · ${(volume * 100).round()}%',
                      style: context.appText.body),
                ),
                Icon(_open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: AppSize.iconSm, color: context.appColors.iconInactive),
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

/// R26skel-b6：当前音质/清晰度标签（音乐面板入口按钮文案）。
String _qualityLabel(WidgetRef ref) {
  final MusicQuality mq = ref.watch(musicQualityProvider);
  final BiliVideoQuality bq = ref.watch(biliVideoQualityProvider);
  return '音质 ${mq.label} · 清晰度 ${bq.label}';
}

/// 音量行：图标 + 滑块。拖动实时更新 provider 并接线到真实音频服务（R10）。
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
