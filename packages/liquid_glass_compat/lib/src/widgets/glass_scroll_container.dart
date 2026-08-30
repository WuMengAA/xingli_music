import 'package:flutter/material.dart';

import '../core/performance.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassScrollContainer —— 液态玻璃滚动容器（懒 / 非懒）
///
/// 对应 liquid-glass-webgl 的 ScrollContainerContent.kt 与
/// LazyScrollContainerContent.kt（build-scroll-container.ts / lazy 变体）：
/// - 非懒（normal）：普通 Column 一次性构建全部子项（内存换性能上限）
/// - 懒（lazy）：ListView.builder 只构建视口内子项（省内存，
///   默认由性能预设决定：省电档 → lazy，均衡/流畅 → normal）
/// [childBuilder] 返回每个玻璃槽位（通常配 GlassCard）。
/// ───────────────────────────────────────────────────────────────────────

class GlassScrollContainer extends StatelessWidget {
  /// 项数（非懒时需给出，懒时可以只给 [itemCount]）。
  final int itemCount;

  /// 每项构建器。
  final IndexedWidgetBuilder itemBuilder;

  /// 每项之间的间距。
  final double spacing;

 /// 懒加载强制开关（null → 跟随 [performancePreset]）。
  final bool? lazy;

  /// 性能预设（决定懒/非懒默认）。
  final GlassPerformancePreset? performancePreset;

  const GlassScrollContainer({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 12,
    this.lazy,
    this.performancePreset,
  });

  @override
  Widget build(BuildContext context) {
    final GlassPerformanceSettings perf =
        settingsFor(performancePreset ?? kDefaultPerformancePreset);
    final bool useLazy = lazy ?? perf.lazyScrollByDefault;

    if (useLazy) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        itemBuilder: (context, i) {
          final Widget item = itemBuilder(context, i);
          if (i == itemCount - 1) return item;
          return Column(
            children: [item, SizedBox(height: spacing)],
          );
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            itemBuilder(context, i),
            if (i != itemCount - 1) SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }
}

/// 懒加载专用（强制 ListView.builder，性能预设只影响缓存区大小）。
class GlassLazyScrollContainer extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;

  const GlassLazyScrollContainer({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        final Widget item = itemBuilder(context, i);
        if (i == itemCount - 1) return item;
        return Column(children: [item, SizedBox(height: spacing)]);
      },
    );
  }
}