import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/notification_event.dart';
import '../../models/scene.dart';
import '../../models/track.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/scene/scene_providers.dart';
import '../../providers/session/session_providers.dart';
import '../../providers/settings/notification_providers.dart';
import '../../widgets/common/playback_feedback.dart';
import '../../widgets/common/track_cover.dart';

/// 通知中心（v2 M6 · P0-M6-1 三区块合一）。
///
/// ① 运行状态：后台播放 / 锁屏控件 / 通知栏 3 个开关；
/// ② 播放媒体与控制：封面 + 歌名/歌手 + 播放暂停/上一首/下一首 + 进度条；
/// ③ 场景状态：当前场景 + 音景开关 + 场景快捷切换 chips。
///
/// **P0-M6-2 硬约束**：播放态只读 `isPlayingProvider` / `nowPlayingProvider`
/// / `musicPositionProvider` / `musicDurationProvider`；动作只走
/// `playbackActionsProvider`（延续 v1 C6/C7），禁止本地 UI 状态推断。
/// 横屏（P2-M1-7）：② 与 ③ 并排双列。
class NotificationCenter extends ConsumerWidget {
  const NotificationCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape = width >= AppSize.landscapeBreakpoint;

    final Widget statusCard = _StatusCard();
    final Widget mediaCard = _MediaCard();
    final Widget sceneCard = _SceneCard();
    final Widget logCard = const _EventLogCard();

    if (landscape) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          statusCard,
          const SizedBox(height: AppSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: mediaCard),
              const SizedBox(width: AppSpace.md),
              Expanded(child: sceneCard),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          logCard,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        statusCard,
        const SizedBox(height: AppSpace.md),
        mediaCard,
        const SizedBox(height: AppSpace.md),
        sceneCard,
        const SizedBox(height: AppSpace.md),
        logCard,
      ],
    );
  }
}

/// 卡片外壳。
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        // R16：通知卡底色跟随主题
        color: context.appColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.appColors.border),
      ),
      child: Material(
        // ListTile 需要在 DecoratedBox 内部找到最近 Material 祖先。
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: AppTextStyles.subtitle),
            const SizedBox(height: AppSpace.sm),
            child,
          ],
        ),
      ),
    );
  }
}

/// ① 运行状态（3 开关）。
class _StatusCard extends ConsumerWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool background = ref.watch(backgroundPlayProvider);
    final bool lockScreen = ref.watch(lockScreenProvider);
    final bool notificationBar = ref.watch(notificationBarProvider);

    return _Card(
      title: '运行状态',
      child: Column(
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('后台播放', style: AppTextStyles.body),
            subtitle: const Text('切到其它 App 时继续播放', style: AppTextStyles.artist),
            value: background,
            onChanged: (bool v) =>
                ref.read(backgroundPlayProvider.notifier).state = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('锁屏控件', style: AppTextStyles.body),
            subtitle: const Text('锁屏显示播放 / 暂停 / 切歌', style: AppTextStyles.artist),
            value: lockScreen,
            onChanged: (bool v) =>
                ref.read(lockScreenProvider.notifier).state = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('通知栏', style: AppTextStyles.body),
            subtitle: const Text('在通知栏常驻音乐卡片', style: AppTextStyles.artist),
            value: notificationBar,
            onChanged: (bool v) =>
                ref.read(notificationBarProvider.notifier).state = v,
          ),
        ],
      ),
    );
  }
}

/// ② 播放媒体与控制（真实流绑定，C6/C7）。
class _MediaCard extends ConsumerWidget {
  const _MediaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Track? track = ref.watch(nowPlayingProvider);
    final bool isPlaying =
        ref.watch(isPlayingProvider).valueOrNull ?? false;
    final Duration position =
        ref.watch(musicPositionProvider).valueOrNull ?? Duration.zero;
    final Duration? duration = ref.watch(musicDurationProvider).valueOrNull;
    final PlaybackActions actions = ref.read(playbackActionsProvider);

    final double ratio = (duration != null && duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return _Card(
      title: Terms.nowPlaying,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              TrackCover(track: track, size: AppSize.thumb, radius: AppRadius.sm),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      track?.title ?? '未在播放',
                      style: AppTextStyles.trackName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track?.artist ?? '从曲库挑一首开始',
                      style: AppTextStyles.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: AppSize.heightProgress,
              backgroundColor: AppColors.progressTrack,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              IconButton(
                tooltip: '上一首',
                icon: const Icon(Icons.skip_previous_rounded,
                    color: AppColors.iconPrimary),
                onPressed: () => runPlaybackAction(
                    context, () => actions.next(direction: -1)),
              ),
              IconButton(
                tooltip: isPlaying ? '暂停' : '播放',
                iconSize: 36,
                icon: Icon(
                  isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  color: AppColors.accent,
                ),
                onPressed: () => runPlaybackAction(context, actions.toggle),
              ),
              IconButton(
                tooltip: '下一首',
                icon: const Icon(Icons.skip_next_rounded,
                    color: AppColors.iconPrimary),
                onPressed: () =>
                    runPlaybackAction(context, () => actions.next()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ③ 场景状态 + 快捷切换。
class _SceneCard extends ConsumerWidget {
  const _SceneCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Scene scene = ref.watch(activeSceneProvider);
    final List<Scene> scenes = ref.watch(sceneOrderProvider);
    final int currentIndex = ref.watch(currentSceneIndexProvider);
    final bool soundscapeMuted = ref.watch(soundscapeMutedProvider);

    return _Card(
      title: '场景状态',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Center(
                  child: Text(
                    scene.visual.glyph,
                    style: const TextStyle(
                      fontSize: 20,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(scene.name, style: AppTextStyles.body),
                    Text(
                      soundscapeMuted ? '音景已静音' : '音景播放中',
                      style: AppTextStyles.artist,
                    ),
                  ],
                ),
              ),
              Switch(
                value: !soundscapeMuted,
                onChanged: (bool v) async {
                  await ref.read(audioServiceProvider).setSoundscapeMuted(!v);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text('快捷切换', style: AppTextStyles.caption),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              for (int i = 0; i < scenes.length; i++)
                ChoiceChip(
                  label: Text(scenes[i].name),
                  selected: i == currentIndex,
                  onSelected: (_) {
                    ref.read(currentSceneIndexProvider.notifier).state = i;
                    ref.read(audioServiceProvider).switchSoundscape(scenes[i]);
                    ref
                        .read(recentNotificationsProvider.notifier)
                        .append('切场景', '切换到「${scenes[i].name}」');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ④ 最近通知事件日志（P2-M6-4 · A5 自动记录播放 / 场景事件）。
class _EventLogCard extends ConsumerWidget {
  const _EventLogCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<NotificationEvent> events =
        ref.watch(recentNotificationsProvider);

    return _Card(
      title: '最近事件',
      child: events.isEmpty
          ? const Text('暂无事件记录', style: AppTextStyles.artist)
          : Column(
              children: <Widget>[
                for (final NotificationEvent e in events.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: <Widget>[
                        Text(e.timeLabel, style: AppTextStyles.caption),
                        const SizedBox(width: AppSpace.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(
                                AppRadius.pill),
                          ),
                          child: Text(
                            e.title,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            e.message,
                            style: AppTextStyles.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
