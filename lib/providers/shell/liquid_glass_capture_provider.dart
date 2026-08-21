/// ════════════════════════════════════════════════════════════════════════
/// 液态玻璃 · 背景捕获（LiquidGlassCapture）
/// ════════════════════════════════════════════════════════════════════════
///
/// AppShell 的背景层（渐变 + 噪点）包在一个 [RepaintBoundary] 里，
/// 捕获成 [ui.Image] 快照，通过 InheritedWidget 共享给所有 LiquidGlass。
///
/// 折射/色散 shader 需要采样"玻璃背后的内容"，因此必须有这张背景图。
/// 背景会随主题（深浅）/皮肤主色变化，故每次切换主题/皮肤后需重捕获，
/// 否则液态玻璃折射采样到的仍是旧背景（#583 老 bug：右上角切换深浅/颜色
/// 后玻璃失效）。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme/theme_providers.dart';

/// 捕获层：包住背景，提供 [ui.Image] 快照。
class LiquidGlassCapture extends ConsumerStatefulWidget {
  const LiquidGlassCapture({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LiquidGlassCapture> createState() => _LiquidGlassCaptureState();

  /// 从 context 读取背景快照（无则 null）。
  static ui.Image? maybeOf(BuildContext context) {
    final _LiquidGlassCaptureScope? scope =
        context.dependOnInheritedWidgetOfExactType<_LiquidGlassCaptureScope>();
    return scope?.image;
  }
}

class _LiquidGlassCaptureState extends ConsumerState<LiquidGlassCapture> {
  final GlobalKey _boundaryKey = GlobalKey();
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  /// 主题/皮肤变化后，等一帧让新背景完成绘制再重捕获快照。
  void _scheduleRecapture() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    final RenderObject? ro = _boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    try {
      final ui.Image img = await ro.toImage();
      if (mounted) setState(() => _image = img);
    } catch (_) {
      // 捕获失败（测试环境等）静默降级
    }
  }

  @override
  Widget build(BuildContext context) {
    // #583：主题模式 / 皮肤主色变化会改变背景渐变，重捕获快照，
    // 保证液态玻璃折射采样到的背景与当前主题一致（切换深浅/颜色后玻璃不失效）。
    ref.listen(themeModeProvider, (_, __) => _scheduleRecapture());
    ref.listen(themeSkinColorProvider, (_, __) => _scheduleRecapture());
    return _LiquidGlassCaptureScope(
      image: _image,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: widget.child,
      ),
    );
  }
}

class _LiquidGlassCaptureScope extends InheritedWidget {
  const _LiquidGlassCaptureScope({required this.image, required super.child});

  final ui.Image? image;

  @override
  bool updateShouldNotify(covariant _LiquidGlassCaptureScope oldWidget) =>
      oldWidget.image != image;
}
