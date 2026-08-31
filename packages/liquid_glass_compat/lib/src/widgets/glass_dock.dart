import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/palette.dart';
import '../core/spring.dart';
import '../core/performance.dart';
import 'glass_surface.dart';

/// ───────────────────────────────────────────────────────────────────────
/// GlassDock —— 液态玻璃底部标签栏
///
/// 忠实移植 liquid-glass-webgl `build-bottom-tabs.ts` + LiquidBottomTabs.kt：
/// - 容器：整条 64dp 高胶囊（cornerRadius = 32 = 64/2，TABS 宽减去 36dp×2 边距），
///   tabsContainer 半透明玻璃表面 + 模糊
/// - 内容：56dp 高（减 4dp padding），tab 等分，选中 tab 有「指示器胶囊」：
///   56×tabW 玻璃胶囊，随 x 移动（临界阻尼弹簧），忠实
///   dampedDragAnimation + panelOffset
/// - 每 tab：flight 图标 + 标签，内容色 tabsContentColor，
///   active 用 tabsAccent 色
/// - 可选 SDF 连续曲率指示器（useContinuousSdf，默认开 → 忠实
///   capsuleShape on）
/// ───────────────────────────────────────────────────────────────────────

/// Dock item 描述。
class GlassDockItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const GlassDockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class GlassDock extends StatefulWidget {
  final List<GlassDockItem> items;

  /// 当前选中下标；`null` = 全部未选中（隐藏页全灰契约，见 Xingli
  /// `AppDock`：Home 隐藏页 / 沉浸画布下 4 个 Tab 一致渲染未选中态）。
  final int? selectedIndex;
  final ValueChanged<int>? onSelected;

  /// 容器胶囊高度（忠实 64dp）。
  final double containerHeight;

  /// 边距（左右各 36dp，忠实 TABS_PAD）。
  final double horizontalPadding;

  /// 模糊半径。
  final double blur;

  /// accent 色（null → 主题 tabsAccent）。
  final Color? accentColor;

  /// 性能预设（null → 默认均衡）。
  final GlassPerformancePreset? performancePreset;

  /// 是否显示文字标签（false → 只留图标，紧凑屏/手表用）。
  final bool showLabels;

  const GlassDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    this.onSelected,
    this.containerHeight = 64,
    this.horizontalPadding = 36,
    this.blur = 8,
    this.accentColor,
    this.performancePreset,
    this.showLabels = true,
  });

  @override
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock> with TickerProviderStateMixin {
  // 指示器 x 位移（临界阻尼，忠实 dampedDragAnimation）。
  double _indicatorFrac = 0;
  double _indicatorVel = 0;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _indicatorFrac = (widget.selectedIndex ?? 0).toDouble();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(GlassDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) _startTick();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _startTick() {
    _last = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (!_ticker.isActive) return;
    final dt = _last == Duration.zero ? (1 / 60.0) : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    // null（隐藏页全灰）时归位到首 Tab，但 active 判定全 false → 视觉全灰。
    final target = (widget.selectedIndex ?? 0).toDouble();
    final r = springStepCritical(_indicatorFrac, _indicatorVel, target, dt,
        omegaN: kToggleValueOmegaN);
    _indicatorFrac = r.value;
    _indicatorVel = r.velocity;
    if (mounted) setState(() {});
    if ((_indicatorFrac - target).abs() < kSpringThreshold) {
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
    final Color accent = widget.accentColor ?? palette.tabsAccent;
    final int count = widget.items.length;

    return LayoutBuilder(builder: (context, constraints) {
      final double available = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : 360.0;
      final double barW = available - 2 * widget.horizontalPadding;
      final double tabW = (barW - 8) / count; // 8 = 4dp 每侧 padding
      final double contentH = widget.containerHeight - 8; // 56

      // 玻璃容器（胶囊）。
      final Widget container = GlassSurface(
        visuals: GlassVisuals(
          blur: widget.blur,
          tint: palette.tabsContainer,
          radius: widget.containerHeight / 2,
          highlightColor: dark ? const Color(0x2EFFFFFF) : const Color(0x1FFFFFFF),
          borderColor: dark ? const Color(0x22FFFFFF) : const Color(0x12000000),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          height: contentH,
          width: barW,
          child: Row(
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: _DockTab(
                    item: widget.items[i],
                    active: widget.selectedIndex == i,
                    accent: accent,
                    contentColor: palette.tabsContentColor,
                    showLabels: widget.showLabels,
                    onTap: widget.onSelected == null ? null : () => widget.onSelected!(i),
                  ),
                ),
            ],
          ),
        ),
      );

      // 指示器：56dp 高 × tabW 宽的玻璃胶囊，x 随弹簧移动。
      // 忠实 LiquidBottomTabs.kt：indicator 是 56dp 胶囊（cornerRadius=28），
      // 用 G2 连续曲率角（capsuleShape on → useContinuousSdf）。
      final double indicatorW = tabW - 8; // padding(horizontal=4dp) 收窄
      final double x = widget.horizontalPadding + 4 + _indicatorFrac * tabW;

      final Widget indicator = Stack(
        children: [
          container,
          Positioned(
            left: x,
            top: 4,
            width: indicatorW,
            height: contentH,
            child: GlassSurface(
              visuals: GlassVisuals(
                blur: widget.blur * 0.5,
                tint: accent.withValues(alpha: dark ? 0.34 : 0.22),
                radius: contentH / 2,
                highlightColor: accent.withValues(alpha: 0.18),
              ),
            ),
          ),
        ],
      );

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
        child: indicator,
      );
    });
  }
}

class _DockTab extends StatelessWidget {
  final GlassDockItem item;
  final bool active;
  final Color accent;
  final Color contentColor;
  final bool showLabels;
  final VoidCallback? onTap;

  const _DockTab({
    required this.item,
    required this.active,
    required this.accent,
    required this.contentColor,
    required this.showLabels,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor = active ? accent : contentColor.withValues(alpha: 0.55);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? item.selectedIcon : item.icon,
              size: 22, color: iconColor),
          if (showLabels) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: iconColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}