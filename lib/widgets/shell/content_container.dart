import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';

/// 内容容器（架构 §1.6 / PRD P0-B1）
///
/// 由 `AppShell` **统一提供且仅提供一次**，包住 `IndexedStack`：
/// `#F5F5F5` 底 / r36 / 水平外边距 14 / 内边距 18。
///
/// ⚠️ 5 个页面**自身不再画容器**，也不再写 `Padding(fromLTRB(*, 60, *, 140))`
/// 之类的手工避让 —— 那是旧 Shell 的遗留，重构后一律由本组件负责。
class ContentContainer extends StatelessWidget {
  const ContentContainer({super.key, required this.child});

  /// 被容器包裹的页面内容（通常是 `IndexedStack`）
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSize.contentMaxWidth,
        ),
        child: Container(
          // 外边距 14dp（[AppSpace.md]）—— 架构 §1.4 / §1.6 与 PRD §10 的明确分工：
          //   · 迷你播放器 / Dock  = 满宽（AppSize.shellEdgeInset，当前 0）
          //   · 内容容器           = 左右各留 14dp
          // 二者**刻意不同源**：满宽的是贴边浮起的操作条，内容容器则要留出呼吸边。
          // ⚠️ 不要图省事把这里也换成 shellEdgeInset —— 那会让内容区直接顶到屏幕
          // 边缘，r36 圆角被裁掉，与设计稿不符。
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
          ),
          padding: const EdgeInsets.all(AppSpace.lg),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: child,
        ),
      ),
    );
  }
}
