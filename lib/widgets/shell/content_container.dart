import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import '../liquid_glass.dart';

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
    return Padding(
      // 四边等距外边距（露出圆角）。
      padding: const EdgeInsets.all(AppSpace.md),
      child: LiquidGlass(
        radius: 28,
        style: GlassStyle.frosted,
        // 全屏铺满：去掉 maxWidth 限制，内容区占满可用宽度/高度。
        // 不显式传 tint/borderColor —— 由 LiquidGlass 内部回退到
        // context.appColors.glassTint / glassBorder（随皮肤主色派生），
        // 实现「配色不写死、可切换皮肤」；毛玻璃质感主要由背景模糊提供。
        child: child,
      ),
    );
  }
}
