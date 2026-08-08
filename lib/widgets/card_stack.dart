import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scene.dart';
import '../core/motion/motion.dart';
import '../models/track.dart';
import '../providers/audio/audio_providers.dart';
import 'app_icon.dart';

/// 场景卡片（主视觉单元）
///
/// 全部使用官方控件：Card + InkWell + LinearProgressIndicator，
/// 文字走 Theme，观感统一跟随主色。
class SceneCardStack extends StatefulWidget {
  final List<Scene> scenes;
  final int currentIndex;
  final Track? nowPlaying;
  final bool isPlaying;
  final void Function(int) onSceneChanged;

  const SceneCardStack({
    super.key,
    required this.scenes,
    required this.currentIndex,
    this.nowPlaying,
    this.isPlaying = false,
    required this.onSceneChanged,
  });

  @override
  State<SceneCardStack> createState() => _SceneCardStackState();
}

class _SceneCardStackState extends State<SceneCardStack> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.scenes.isEmpty) return const SizedBox.shrink();
    final Scene current =
        widget.scenes[widget.currentIndex.clamp(0, widget.scenes.length - 1)];

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300 &&
            widget.currentIndex < widget.scenes.length - 1) {
          widget.onSceneChanged(widget.currentIndex + 1);
        } else if (details.primaryVelocity! > 300 && widget.currentIndex > 0) {
          widget.onSceneChanged(widget.currentIndex - 1);
        }
      },
      child: AnimatedScale(
        scale: _pressed ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Motion.gentle,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          switchInCurve: Motion.gentle,
          switchOutCurve: Motion.calm,
          transitionBuilder: (child, animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _SceneCard(
            key: ValueKey(current.id),
            scene: current,
            nowPlaying: widget.nowPlaying,
            isPlaying: widget.isPlaying,
            pressed: _pressed,
            onPressStart: () => setState(() => _pressed = true),
            onPressEnd: () => setState(() => _pressed = false),
          ),
        ),
      ),
    );
  }
}

/// 单张场景卡片（官方 Card）
class _SceneCard extends StatelessWidget {
  final Scene scene;
  final Track? nowPlaying;
  final bool isPlaying;
  final bool pressed;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  const _SceneCard({
    super.key,
    required this.scene,
    required this.nowPlaying,
    required this.isPlaying,
    required this.pressed,
    required this.onPressStart,
    required this.onPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double scale = _responsiveScale(context);

    return Center(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.78,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTapDown: (_) => onPressStart(),
            onTapUp: (_) => onPressEnd(),
            onTapCancel: onPressEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部：场景名 + 氛围词
                  Row(
                    children: [
                      AppIcon(scene.icon,
                          size: 18, color: scene.visual.accent),
                      const SizedBox(width: 8),
                      Text(
                        scene.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 18 * scale,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          scene.mood,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scene.visual.accent.withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 场景描述
                  Text(
                    scene.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  // 中部：曲目名（锚点）
                  Text(
                    nowPlaying?.title ?? scene.track,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 26 * scale,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 艺术家
                  Text(
                    nowPlaying?.artist ?? scene.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const Spacer(),
                  // 底部：官方进度条（独立订阅，局部刷新）
                  _TrackProgress(
                    color: scene.visual.accent,
                    isPlaying: isPlaying,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _responsiveScale(BuildContext context) {
    final double w = MediaQuery.of(context).size.width;
    if (w < 400) return 0.9;
    if (w > 800) return 1.1;
    return 1.0;
  }
}

/// 播放进度（官方 LinearProgressIndicator，独立订阅位置流）
class _TrackProgress extends ConsumerWidget {
  final Color color;
  final bool isPlaying;

  const _TrackProgress({required this.color, required this.isPlaying});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Duration? pos = ref.watch(musicPositionProvider).valueOrNull;
    final Duration? dur = ref.watch(musicDurationProvider).valueOrNull;
    final double value = (pos != null && dur != null && dur > Duration.zero)
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      children: [
        Expanded(
          child: LinearProgressIndicator(
            value: isPlaying ? value : 0,
            minHeight: 2,
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
