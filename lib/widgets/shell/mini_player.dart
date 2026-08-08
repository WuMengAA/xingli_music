import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
// `PlayMode` 由 audio_providers.dart 转导出（`export models/play_mode.dart`），
// 这里不再单独 import，避免 unnecessary_import。
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../common/playback_feedback.dart';
import '../common/track_cover.dart';

/// 常驻迷你播放器（架构 §1.4 / PRD P0-D1~D8）
///
/// 由 `AppShell` **唯一实例化**，5 个 Shell 页面共享 —— 这天然满足
/// P0-D1「5 页持续可见」与 V5「位置一致」，无需各页自己摆一个。
///
/// 垂直结构（合计精确 80dp）：
/// ```
/// Column
/// ├ Padding(horizontal: 34) → 进度条 h=8
/// └ SizedBox(h=72) → Row[ Expanded 信息胶囊 | 5 | Expanded 控制胶囊 ]
/// ```
///
/// **防溢出（C10 零容忍）**：控制胶囊内 4 个按钮用 `Expanded` 均分而非固定
/// 36dp，图标再套 `FittedBox(scaleDown)` —— 数学上在任意宽度都不会溢出。
///
/// **播放态唯一真源（P0-D8）**：只允许
/// `ref.watch(isPlayingProvider).valueOrNull ?? false`，
/// 严禁任何 `setState` 本地态推断，否则连点必然错乱。
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.onOpenNowPlaying});

  /// 点击左侧信息胶囊的回调（T05 接入 `NowPlayingPage`；未接入时整块不可点）
  final VoidCallback? onOpenNowPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: AppSize.heightMiniGroup,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSize.progressInset),
            child: _ProgressBar(),
          ),
          SizedBox(
            height: AppSize.heightMiniPill,
            child: Row(
              children: <Widget>[
                Expanded(child: _InfoPill(onTap: onOpenNowPlaying)),
                const SizedBox(width: AppSpace.sm),
                const Expanded(child: _ControlPill()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 进度条
// ═══════════════════════════════════════════════════════════════

/// 8dp 高、完全圆角的播放进度条，支持点击 / 拖拽定位（P1-05）。
///
/// 直播流（`duration == null`）时退化为纯装饰轨道，不响应手势。
class _ProgressBar extends ConsumerStatefulWidget {
  const _ProgressBar();

  @override
  ConsumerState<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends ConsumerState<_ProgressBar> {
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

    return SizedBox(
      height: AppSize.heightProgress,
      child: LayoutBuilder(
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
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: AppColors.progressTrack),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: ratio,
                      heightFactor: 1,
                      child: const ColoredBox(color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 左：信息胶囊
// ═══════════════════════════════════════════════════════════════

class _InfoPill extends ConsumerWidget {
  const _InfoPill({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Track? track = ref.watch(nowPlayingProvider);

    return _Pill(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            TrackCover(
              track: track,
              size: AppSize.thumb,
              radius: 12,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    track?.title ?? '未在播放',
                    style: AppText.trackName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track?.artist ?? '从曲库挑一首开始',
                    style: AppText.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 右：控制胶囊（4 按钮 —— Q1 已裁决）
// ═══════════════════════════════════════════════════════════════

class _ControlPill extends ConsumerWidget {
  const _ControlPill();

  /// 播放模式 → 图标
  static IconData _modeIcon(PlayMode mode) => switch (mode) {
        PlayMode.order => Icons.trending_flat,
        PlayMode.reverse => Icons.keyboard_backspace,
        PlayMode.shuffle => Icons.shuffle,
        PlayMode.loop => Icons.repeat_one,
      };

  /// 播放模式 → 文案（与 `MorePanel` 保持一致）
  static String _modeLabel(PlayMode mode) => switch (mode) {
        PlayMode.order => '顺序',
        PlayMode.reverse => '倒叙',
        PlayMode.shuffle => '随机',
        PlayMode.loop => '单曲循环',
      };

  /// 点击循环：顺序 → 倒叙 → 随机 → 单曲循环 → 顺序
  static PlayMode _nextMode(PlayMode mode) => switch (mode) {
        PlayMode.order => PlayMode.reverse,
        PlayMode.reverse => PlayMode.shuffle,
        PlayMode.shuffle => PlayMode.loop,
        PlayMode.loop => PlayMode.order,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P0-D8：播放态唯一来自流，不做任何本地推断
    final bool isPlaying =
        ref.watch(isPlayingProvider).valueOrNull ?? false;
    final PlayMode mode = ref.watch(playModeProvider);
    final PlaybackActions actions = ref.read(playbackActionsProvider);

    return _Pill(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _ControlButton(
                icon: Icons.skip_previous,
                tooltip: '上一首',
                onTap: () => runPlaybackAction(
                  context,
                  () => actions.next(direction: -1),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ControlButton(
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                tooltip: isPlaying ? '暂停' : '播放',
                onTap: () => runPlaybackAction(context, actions.toggle),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ControlButton(
                icon: Icons.skip_next,
                tooltip: '下一首',
                onTap: () => runPlaybackAction(
                  context,
                  () => actions.next(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _ControlButton(
                icon: _modeIcon(mode),
                tooltip: '播放模式：${_modeLabel(mode)}',
                onTap: () {
                  final PlayMode next = _nextMode(mode);
                  actions.setMode(next);
                  showPlaybackToast(context, '播放模式：${_modeLabel(next)}');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个控制按钮：`Expanded` 宽度 + `FittedBox` 图标，双保险防溢出
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Icon(
              icon,
              size: AppSize.icon,
              color: AppColors.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 胶囊外壳（两侧共用）
// ═══════════════════════════════════════════════════════════════

/// 白底 / r36 / `AppShadow.card` 的胶囊容器。
///
/// `Material(transparency)` 是 `InkWell` 的必需祖先；`ClipRRect` 不需要，
/// 因为 `customBorder` 已把水波纹限制在按钮圆内。
class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadow.cardList,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: child,
        ),
      ),
    );
  }
}
