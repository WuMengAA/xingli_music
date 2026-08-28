import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scene.dart';
import '../core/motion/motion.dart';
import '../core/theme/app_theme_colors.dart';
import '../core/theme/light_tokens.dart';
import 'app_icon.dart';
import 'liquid_glass.dart';
import '../providers/settings/scene_card_opacity_provider.dart';

/// 场景卡片（主视觉单元）
///
/// 全部使用官方控件：Card + InkWell + LinearProgressIndicator，
/// 文字走 Theme，观感统一跟随主色。
class SceneCardStack extends StatefulWidget {
  final List<Scene> scenes;
  final int currentIndex;
  final void Function(int) onSceneChanged;

  const SceneCardStack({
    super.key,
    required this.scenes,
    required this.currentIndex,
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
    final int n = widget.scenes.length;
    final Scene current =
        widget.scenes[widget.currentIndex.clamp(0, n - 1)];

    // 多卡片堆叠：当前卡之后渲染 2 张预览卡作为卡堆层次，向上错开并缩小，
    // 营造可滑动的卡组(deck)观感（非真实 z 轴，纯视觉层叠）。
    final List<Widget> deck = <Widget>[];
    for (int k = 2; k >= 1; k--) {
      final int idx = widget.currentIndex + k;
      if (idx >= n) continue;
      deck.add(
        IgnorePointer(
          child: Transform.translate(
            offset: Offset(0, -k * 10),
            child: Transform.scale(
              scale: 1 - k * 0.04,
              // #581：取消双模糊、仅不透明卡片堆叠——预览卡不再半透明，
              // 直接以实底错开堆叠，露出卡堆层次。
              child: _SceneCard(
                key: ValueKey('deck-$k-${widget.scenes[idx].id}'),
                scene: widget.scenes[idx],
                pressed: false,
                onPressStart: () {},
                onPressEnd: () {},
                onLongPress: null,
              ),
            ),
          ),
        ),
      );
    }

    // 当前卡（最上层，保留横滑 / 淡入淡出 / 歌词 / 进度等全部交互）。
    final Widget front = AnimatedScale(
      scale: _pressed ? 1.02 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Motion.gentle,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Motion.gentle,
        switchOutCurve: Motion.calm,
        transitionBuilder: (child, animation) {
          // cl03b：切场景带横向方向感——新卡从右 6% 滑入归位、旧卡向左滑出，
          // 与横滑手势的方向直觉一致；纯 Fade 太「软」，6% 位移不喧宾夺主。
          final Animation<Offset> slide = Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: _SceneCard(
          key: ValueKey(current.id),
          scene: current,
          pressed: _pressed,
          onPressStart: () => setState(() => _pressed = true),
          onPressEnd: () => setState(() => _pressed = false),
          onLongPress: widget.onLongPress,
        ),
      ),
    );
    deck.add(front);

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
      child: Stack(
        alignment: Alignment.center,
        children: deck,
      ),
    );
  }
}

/// 单张场景卡片（官方 Card）
class _SceneCard extends ConsumerWidget {
  final Scene scene;
  final bool pressed;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final VoidCallback? onLongPress;

  const _SceneCard({
    super.key,
    required this.scene,
    required this.pressed,
    required this.onPressStart,
    required this.onPressEnd,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final double scale = _responsiveScale(context);

    final bool isLight = theme.brightness == Brightness.light;
    // 文字与背景均跟随主题：浅色主题用浅色玻璃(auroraGradient，由主色派生)
    // + 深色语义字；深色主题用深色场景叠加 + 浅色语义字(appColors.textPrimary
    // 深态即浅字)。不再写死任何色值，满足 C1 硬规则。
    final Gradient gradient =
        isLight ? context.appColors.auroraGradient : _backgroundGradient(context);
    final Color titleColor = context.appColors.textPrimary;
    final Color mutedColor = context.appColors.textSecondary;

    // 场景卡片背景浓度：越低越通透（视频背景透出），越高越实。默认 0.25。
    final double opacity = ref.watch(sceneCardOpacityProvider);

    final double cardW = MediaQuery.of(context).size.width * 0.94;
    final double cardH = cardW * 9 / 16;

    // 元数据列（左半区 / 无歌词时整卡居中显示）。
    // 对齐画布「scene-card-hero」(3:23) 文字层级：SCENE 标签 → 场景名主 →
    // 音景 pill → 切歌预览 → 滑动提示。全部取真实 Scene 字段，不放假数据。
    final Widget metadata = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 「当前场景 · SCENE」标签（画布 3:26，12px 次级）。
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppIcon(scene.icon, size: 14, color: scene.visual.accent),
            const SizedBox(width: 6),
            Text(
              '当前场景 · SCENE',
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: 13 * scale,
                color: mutedColor,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 场景名（画布 3:27，19px Bold 主标题）。
        Text(
          scene.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 22 * scale,
            color: titleColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        // 音景 pill（画布 3:28/3:29：真实 soundscape 描述，空则回退 mood）。
        if (scene.soundscape.isNotEmpty || scene.mood.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.appColors.bgSurface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: context.appColors.border.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Text(
              scene.soundscape.isNotEmpty ? scene.soundscape : scene.mood,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w500,
                color: titleColor,
              ),
            ),
          ),
        const SizedBox(height: 16),
        // 切歌预览（真实 track/artist，画布场景卡之后的歌曲信息）。
        Text(
          scene.track,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 17 * scale,
            color: titleColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          scene.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14 * scale,
            color: mutedColor,
          ),
        ),
        const SizedBox(height: 14),
        // 滑动切换提示（画布 3:30，11px 次级；真实可横滑切换场景）。
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.swipe_left_rounded,
              size: 13 * scale,
              color: mutedColor.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 4),
            Text(
              '滑动切换场景',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 12 * scale,
                color: mutedColor,
              ),
            ),
          ],
        ),
      ],
    );

    return Center(
      child: SizedBox(
        // cl46-E：中间场景卡片默认 16:9（与音画比例一致，视觉更稳定）。
        width: cardW,
        height: cardH,
        // cl06：默认磨砂玻璃 + 配色可叠加（用户需求）——场景渐变在下、
        // 磨砂玻璃（frosted）在上模糊它、实色浓度（provider）叠加，
        // 内容清晰浮于顶层。恢复「玻璃片」质感，不再纯实底。
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 配色叠加层：场景渐变（配色可叠加，磨砂会模糊它）。
              DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
              // 实色浓度叠加层（provider）：1.0 接近实底 / 低值让磨砂透出。
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appColors.bgSurface.withValues(alpha: opacity),
                ),
              ),
              // 磨砂玻璃底（模糊上两层渐变，出玻璃质感）。
              LiquidGlass(
                style: GlassStyle.frosted,
                forceGlass: true,
                radius: 0,
                tint: const Color(0x0AFFFFFF),
                borderColor: const Color(0x26FFFFFF),
                child: const SizedBox.expand(),
              ),
              // 内容（透明 Card + InkWell + metadata，清晰浮于玻璃上）。
              Card(
                color: Colors.transparent,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: InkWell(
                  onTapDown: (_) => onPressStart(),
                  onTapUp: (_) => onPressEnd(),
                  onTapCancel: onPressEnd,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    // 纯场景展示卡：播放控制/歌词全部收敛到全局底部播放器，
                    // 本卡只呈现场景信息（cl03 全局唯一底部播放器）。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 320,
                          maxWidth: 460,
                        ),
                        child: metadata,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
  Gradient _backgroundGradient(BuildContext context) {
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
    // 兜底：语义深色玻璃（跟随主题，不再写死色值）。
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[context.appColors.bgSurface, context.appColors.bgPage],
    );
  }

  static double _responsiveScale(BuildContext context) {
    final double w = MediaQuery.of(context).size.width;
    if (w < 400) return 0.9;
    if (w > 800) return 1.1;
    return 1.0;
  }
}
