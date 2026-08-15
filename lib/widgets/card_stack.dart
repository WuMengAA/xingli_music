import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scene.dart';
import '../core/motion/motion.dart';
import '../models/track.dart';
import '../providers/audio/audio_providers.dart';
import 'app_icon.dart';
import 'liquid_glass.dart';

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
    this.onLongPress,
  });

  /// cl46-E：长按卡片 = 打开当前场景的详细 / 个性编辑。
  final VoidCallback? onLongPress;

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
            onLongPress: widget.onLongPress,
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
  final VoidCallback? onLongPress;

  const _SceneCard({
    super.key,
    required this.scene,
    required this.nowPlaying,
    required this.isPlaying,
    required this.pressed,
    required this.onPressStart,
    required this.onPressEnd,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double scale = _responsiveScale(context);

    final Gradient gradient = _backgroundGradient();
    // 卡片背景为深色渐变，文字仅在本 widget 内覆盖为浅色以保障对比度
    // （不动全局 theme，配色面板保存的也是深色渐变，二者保持一致）。
    const Color lightText = Color(0xFFF5F5FA);
    final Color lightMuted = Colors.white.withValues(alpha: 0.78);

    final double cardW = MediaQuery.of(context).size.width * 0.94;
    final double cardH = cardW * 9 / 16;
    return Center(
      child: SizedBox(
        // cl46-E：中间场景卡片默认 16:9（与音画比例一致，视觉更稳定）。
        width: cardW,
        height: cardH,
        // 液态玻璃场景卡片：高透明玻璃 + 场景渐变叠加
        child: LiquidGlass(
          radius: 16,

          child: Container(
            // 场景渐变叠加在玻璃之上（深色渐变保证文字对比度）
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Card(
            // 透明 Card，让 Container 的渐变透过；投影由外层 Container 提供
            color: Colors.transparent,
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              onTapDown: (_) => onPressStart(),
              onTapUp: (_) => onPressEnd(),
              onTapCancel: onPressEnd,
              onLongPress: onLongPress,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                // R1 适配：横屏矮高度下卡片被压缩时用 FittedBox(scaleDown)
                // 整体等比缩小而非溢出；内部固定间距（不用 Spacer，避免
                // 无界高度断言崩溃）。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 320,
                      maxWidth: 420,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部：场景名 + 氛围词 + 聚合搜索入口
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(scene.icon,
                                size: 18, color: scene.visual.accent),
                            const SizedBox(width: 8),
                            Text(
                              scene.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: 18 * scale,
                                color: lightText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                scene.mood,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scene.visual.accent
                                      .withValues(alpha: 0.6),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const Spacer(),
                            // cl46-E：去掉搜索 / 音质入口（迁移到个性编辑与播放卡片）。
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 场景描述
                        Text(
                          scene.desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: lightMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // 中部：曲目名（锚点）
                        Text(
                          nowPlaying?.title ?? scene.track,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 26 * scale,
                            color: lightText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 艺术家
                        Text(
                          nowPlaying?.artist ?? scene.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: lightMuted,
                          ),
                        ),
                        const SizedBox(height: 14),
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
            ),
          ),
        ),
      ),
    );
  }

  /// 计算卡片背景渐变（深色，与配色面板场景背景一致）。
  ///
  /// 优先级：
  /// 1. scene.bgTop / scene.bgBottom 非空 → 使用配色面板保存的覆盖色；
  /// 2. 否则若 visual.gradientColors 非空 → 使用场景内置深色渐变；
  /// 3. 兜底 → 中性深色渐变，避免卡片在缺数据时露出纯白底。
  Gradient _backgroundGradient() {
    if (scene.bgTop != null && scene.bgBottom != null) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[scene.bgTop!, scene.bgBottom!],
      );
    }
    final List<Color> colors = scene.visual.gradientColors;
    if (colors.isNotEmpty) {
      final List<double> stops = scene.visual.stops;
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: stops.length == colors.length ? stops : null,
      );
    }
    // 兜底：中性深色渐变
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF1A1A2E), Color(0xFF0F1020)],
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
