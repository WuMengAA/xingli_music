import 'package:flutter/material.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/theme/light_tokens.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 底部悬浮层容器（自适应 · 脱离文档流）
/// ════════════════════════════════════════════════════════════════════════
///
/// 把传入的子组件作为**叠加层（overlay）**锚定在屏幕底部，不再占据任何
/// 文档流空间，从而让承载的播放控件与 dock 栏悬浮于页面内容之上、浑然一体，
/// 下层 5 个 Tab 的布局边界 / 结构 / 占位完全不受影响。
///
/// ### 自适应（按视口尺寸灵活调整大小与位置）
/// - **窄屏（手机竖屏）**：仅留极小左右内边距（[AppSpace.sm]），贴近屏幕边缘，
///   取消过多边角约束，与极光玻璃背景自然融为一体。
/// - **宽屏 / 横屏**：收窄并水平居中（最大宽度对齐 dock，见
///   [ResponsiveLayout.dockMaxWidth] / [AppSize.landscapeDockMaxWidth]），
///   避免在大屏上拉成一条突兀的长条。
///
/// ### 不遮挡关键内容
/// - 跟随系统底部安全区（手势条机型自动上移）与软键盘（键盘弹出时整体抬升）。
/// - 子组件的真实高度由调用方在内容区补等量 `bottom` 预留来规避遮挡
///   （本组件只负责「浮起来 + 自适应」，不含测量逻辑，保持纯组件可单测）。
class ResponsiveFloatingLayer extends StatelessWidget {
  const ResponsiveFloatingLayer({
    super.key,
    required this.child,
    this.bottomGap = 0,
  });

  /// 底部悬浮间隙（iOS26 悬浮 Dock 风格：浮于底部之上，非贴底）。
  /// AppShell 传入约 10~12dp，配合内容区 [AppSize] 预留同步。
  final double bottomGap;

  /// 要悬浮展示的内容（如「播放控件 + dock 栏」纵向堆叠）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ResponsiveLayout rl = ResponsiveLayout.of(context);
    final double keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    // 横向自适应：底部浮层（播放控件 + Dock）始终满宽贴边，符合 iOS TabBar
    // 满宽贴底的直觉（cl13 用户裁决「始终满宽」）。窄屏保留少量安全边距。
    final double sideInset =
        (rl.isLandscape || rl.isLarge) ? 0.0 : AppSpace.sm;
    // 横向自适应：宽屏/横屏收窄并水平居中（对齐 dock 最大宽度），避免拉成
    // 突兀长条；窄屏满宽贴边。原 double.infinity 忽略了 rl.dockMaxWidth。
    final double maxWidth = rl.dockMaxWidth;

    return Positioned(
      left: sideInset,
      right: sideInset,
      // R32：iOS26 悬浮 Dock——抬升到手势条之上再额外离底 gap（浮于底部之上），
      // 软键盘弹出时再叠加键盘高度，整体上浮不遮挡。
      bottom: safeBottom + keyboardInset + bottomGap,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
