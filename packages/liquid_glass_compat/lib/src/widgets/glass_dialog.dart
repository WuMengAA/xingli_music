import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/palette.dart';
import '../core/spring.dart';
import 'glass_button.dart';
import 'glass_surface.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassDialog —— 液态玻璃对话框
///
/// 忠实移植 liquid-glass-webgl `build-dialog.ts` + DialogContent.kt：
/// - 背景 dim（dialogDim 色，亮 0x293A3A 23% / 暗 0x121212 56%）
/// - 卡片：dialogContainer 半透明表面 + 背景模糊（dialogBlurRadius）
/// - 大圆角（34dp）使用 G2 连续曲率角 —— 用 [continuousCurvatureRoundedRectPath]
///   精确裁切（等价于上游从 G2 SDF 纹理采样的角形）
/// - 弹簧弹出：临界阻尼入场（spring(1f, 1000f)）
/// - 标题区用 dialogAccent 分隔线，正文用 dialogContentColor，操作按钮
///   用 GlassButton
/// ───────────────────────────────────────────────────────────────────────

/// 对话框操作按钮描述。
class GlassDialogAction {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  const GlassDialogAction(this.label, {this.onPressed, this.primary = false});
}

/// 显示一个液态玻璃对话框（模态）。
Future<void> showGlassDialog(
  BuildContext context, {
  required String title,
  required Widget content,
  List<GlassDialogAction> actions = const [],
  double width = 320,
  double radius = 34,
  double? blur,
  bool dismissible = true,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, anim1, anim2) {
      final palette = glassPaletteFor(
          Theme.of(context).brightness == Brightness.dark
              ? GlassThemeMode.dark
              : GlassThemeMode.light);
      return GlassDialog(
        title: title,
        content: content,
        actions: actions,
        width: width,
        radius: radius,
        blur: blur ?? palette.dialogBlurRadius,
      );
    },
    transitionBuilder: (context, anim, secondary, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}

/// 对话框主体（无模态壳）。
class GlassDialog extends StatefulWidget {
  final String title;
  final Widget content;
  final List<GlassDialogAction> actions;
  final double width;
  final double radius;
  final double blur;

  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.width = 320,
    this.radius = 34,
    this.blur = 8,
  });

  @override
  State<GlassDialog> createState() => _GlassDialogState();
}

class _GlassDialogState extends State<GlassDialog>
    with SingleTickerProviderStateMixin {
  final Spring1D _spring = Spring1D(
      omegaN: kToggleValueOmegaN, dampingRatio: 0.5); // 欠阻尼轻微弹入
  bool _entered = false;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_ticker.isActive) return;
    if (!_entered) {
      _entered = true;
      return; // 首帧跳弹簧热启动
    }
    final dt = _last == Duration.zero ? (1 / 60.0) : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final moving = _spring.step(1.0, dt);
    if (mounted) setState(() {});
    if (!moving) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette palette = glassPaletteFor(
        Theme.of(context).brightness == Brightness.dark
            ? GlassThemeMode.dark
            : GlassThemeMode.light);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final TextStyle titleStyle = Theme.of(context)
        .textTheme
        .titleLarge!
        .copyWith(
            color: palette.dialogContentColor, fontWeight: FontWeight.w700);
    final Color border = dark ? const Color(0x26FFFFFF) : const Color(0x14000000);
    final Color highlight = dark ? const Color(0x28FFFFFF) : const Color(0x1AFFFFFF);

    final double scale = _spring.value.clamp(0.6, 1.0);

    return Center(
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: widget.width,
          child: GlassSurface(
            visuals: GlassVisuals(
              blur: widget.blur,
              tint: palette.dialogContainer,
              radius: widget.radius,
              highlightColor: highlight,
              borderColor: border,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(widget.title, style: titleStyle),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: DefaultTextStyle(
                    style: TextStyle(
                        color: palette.dialogContentColor.withValues(alpha: 0.85),
                        height: 1.5),
                    child: widget.content,
                  ),
                ),
                if (widget.actions.isNotEmpty) ...[
                  Container(height: 1, color: border),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (final action in widget.actions)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GlassButton(
                              blur: 0, // 对话框内按钮不重复模糊
                              radius: widget.radius * 0.4,
                              onPressed: action.onPressed,
                              child: Text(action.label,
                                  style: TextStyle(
                                      color: action.primary == true
                                          ? palette.dialogAccent
                                          : palette.dialogContentColor,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}