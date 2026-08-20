import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';

/// 内容容器（架构 §1.6 / PRD P0-B1）
///
/// 由 `AppShell` **统一提供且仅提供一次**，包住 `IndexedStack`。
/// R26r21b：**全屏圆角毛玻璃表面** —— 四边等距留白 + 全屏铺满的 frosted
/// 面板（背景模糊 + 半透明 + 细描边 + 圆角），页面内容直接浮在这层玻璃上；
/// 不再限 maxWidth（内容区全屏铺满），不再由各页自备表面。
class ContentContainer extends StatelessWidget {
  const ContentContainer({super.key, required this.child});

  /// 被容器包裹的页面内容（通常是 `IndexedStack`）
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // R27 原生极简：去玻璃表面（无 tint / border / 模糊 / 圆角裁切），
    // 仅保留四边留白，内容直接浮在场景背景上，靠留白与排版区分层级。
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: child,
    );
  }
}
