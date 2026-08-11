/// ════════════════════════════════════════════════════════════════════════
/// 液态玻璃 · 背景捕获（LiquidGlassCapture）
/// ════════════════════════════════════════════════════════════════════════
///
/// AppShell 的背景层（渐变 + 噪点）包在一个 [RepaintBoundary] 里，
/// 捕获成 [ui.Image] 快照，通过 InheritedWidget 共享给所有 LiquidGlass。
///
/// 折射/色散 shader 需要采样"玻璃背后的内容"，因此必须有这张背景图。
/// 背景是静态的（渐变+噪点），捕获一次即可；首帧后自动完成。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 捕获层：包住背景，提供 [ui.Image] 快照。
class LiquidGlassCapture extends StatefulWidget {
  const LiquidGlassCapture({super.key, required this.child});

  final Widget child;

  @override
  State<LiquidGlassCapture> createState() => _LiquidGlassCaptureState();

  /// 从 context 读取背景快照（无则 null）。
  static ui.Image? maybeOf(BuildContext context) {
    final _LiquidGlassCaptureScope? scope =
        context.dependOnInheritedWidgetOfExactType<_LiquidGlassCaptureScope>();
    return scope?.image;
  }
}

class _LiquidGlassCaptureState extends State<LiquidGlassCapture> {
  final GlobalKey _boundaryKey = GlobalKey();
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
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
