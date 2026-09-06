/// ════════════════════════════════════════════════════════════════════════
/// 背景捕获层（兼容占位）
/// ════════════════════════════════════════════════════════════════════════
///
/// 2026-09-06 方向修正：液态玻璃（liquid_glass_widgets）的折射需要背景快照，
/// 现已全面改用标准 BackdropFilter 透明模糊，不再需要背景捕获。本件改为纯
/// 透传包装，保持 AppShell 调用点不变。
library;

import 'package:flutter/widgets.dart';

/// 透传包装（原 LiquidGlassCapture）。
class LiquidGlassCapture extends StatelessWidget {
  const LiquidGlassCapture({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
