/// ════════════════════════════════════════════════════════════════════════
/// 自适应布局工具（UI 自适应：横竖屏单独适配 + 手表等怪分辨率适配）
/// ════════════════════════════════════════════════════════════════════════
///
/// 分层阈值（按 MediaQuery 尺寸判定）：
///  - **横屏**：宽 ≥ [landscapeBreakpoint]（600dp，沿用 AppSize token）
///  - **紧凑（小屏/手表）**：宽 < [compactBreakpoint]（320dp）→ 极简模式
///  - **大屏**：宽 ≥ [largeBreakpoint]（800dp）→ 可展开更丰富布局
///
/// 用法：
/// ```dart
/// final rl = ResponsiveLayout.of(context);
/// if (rl.isCompact) ...          // 手表/小屏：隐藏 Dock 标签、强制折叠
/// if (rl.isLandscape) ...        // 横屏布局
/// if (rl.isLarge) ...            // 大屏：内容更宽松
/// ```
library;

import 'package:flutter/widgets.dart';

import '../theme/light_tokens.dart';

/// 自适应布局判定（一次性读取，避免多处重复 MediaQuery）。
class ResponsiveLayout {
  const ResponsiveLayout({
    required this.width,
    required this.height,
  });

  factory ResponsiveLayout.of(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    return ResponsiveLayout(width: size.width, height: size.height);
  }

  final double width;
  final double height;

  /// 紧凑断点（< 320dp：手表/极小屏）。
  static const double compactBreakpoint = 320;

  /// 大屏断点（≥ 800dp）。
  static const double largeBreakpoint = 800;

  /// 是否横屏（宽 ≥ 600dp，沿用 AppSize.landscapeBreakpoint）。
  bool get isLandscape => width >= AppSize.landscapeBreakpoint;

  /// 是否紧凑/小屏（< 320dp：手表、极小屏）。
  bool get isCompact => width < compactBreakpoint;

  /// 是否大屏（≥ 800dp：平板横屏、桌面）。
  bool get isLarge => width >= largeBreakpoint;

  /// 短边（竖屏宽 / 横屏高），用于判定"空间不足"。
  double get shortSide => width < height ? width : height;

  /// 空间是否紧张（短边 < 360dp → 各组件应自动折叠收窄）。
  bool get isTight => shortSide < 360;

  /// Dock 是否显示文字标签（紧凑屏只显示图标）。
  bool get dockShowLabels => !isCompact && width >= 240;

  /// Dock 最大宽度（横屏收窄居中；紧凑屏几乎满宽）。
  double get dockMaxWidth =>
      isCompact ? width : (isLandscape ? AppSize.landscapeDockMaxWidth : width);

  /// 播放器是否默认折叠（空间紧张时折叠，节省纵向空间）。
  bool get playerCollapsedByDefault => isTight || isCompact;

  /// 场景卡缩放系数（小屏缩小、大屏放大）。
  double get cardScale =>
      isCompact ? 0.85 : (isLarge ? 1.12 : 1.0);
}
