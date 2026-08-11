import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../theme/theme_switch_button.dart';

/// 统一页面模板（v2 M1 · P0-M1-1）
///
/// 依据 `docs/ARCHITECTURE_V2_增量.md` §3.2.1：
/// - **竖屏**（默认，沿用 v1）：标题行（[context.appText.title]）→ 可选搜索栏(40)
///   → 内容区（弹性）。
/// - **横屏**（宽 ≥ `AppSize.landscapeBreakpoint`）：可选 `leadingPanel`
///   （左信息/导航栏，≤ 360dp）+ 右侧内容区；搜索栏位于右内容区顶部。
///
/// 5 个 Shell 页与全屏路由页（实验页 / 编辑器 / 通知中心子页）统一接入，
/// 消灭各页自行拼标题 / 搜索 / 内容区的重复实现。
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.search,
    this.leadingPanel,
    this.actions,
    this.onBack,
    required this.body,
  });

  /// 页面标题（一律取 [Terms.*]，见 `core/terms/naming_dict.dart`）。
  final String title;

  /// 可选搜索栏（通常为 [AppSearchBar]），横屏时置于右侧内容区顶部。
  final Widget? search;

  /// 横屏时左侧信息 / 导航栏（≤ 360dp）；竖屏忽略。
  final Widget? leadingPanel;

  /// 标题行右侧的操作区（如场景页右上角微光圆点）。
  final List<Widget>? actions;

  /// 可选返回回调：非空时标题前渲染返回按钮（全屏路由页用）。
  final VoidCallback? onBack;

  /// 内容区（弹性，页面内部自行重排）。
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape =
        width >= AppSize.landscapeBreakpoint;

    // 桌面无系统返回键：不传 onBack 但能返回时自动补返回按钮（否则页面关不掉）。
    final VoidCallback? back = onBack ??
        (Navigator.of(context).canPop()
            ? () => Navigator.of(context).maybePop()
            : null);

    final Widget header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (back != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.xs),
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.arrow_back_rounded,
                size: AppSize.iconSm,
                color: context.appColors.textSecondary,
              ),
              onPressed: back,
            ),
          ),
        Expanded(
          child: Text(
            title,
            // R16：标题色跟随主题
            style: context.appText.title.copyWith(
              color: context.appColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actions != null) ...actions!,
        // 全局主题切换（右上角）：所有 PageScaffold 页面统一出现，
        // 切换主题模式 + 皮肤，即时全局生效并持久化。
        const ThemeSwitchButton(),
      ],
    );

    final Widget rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        header,
        if (search != null) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          search!,
        ],
        const SizedBox(height: AppSpace.md),
        Expanded(child: body),
      ],
    );

    // ── 横屏：左栏（≤360dp）+ 右侧内容区 ──────────────────
    if (landscape && leadingPanel != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SizedBox(
              width: (width * 0.34).clamp(240.0, 360.0),
              child: leadingPanel,
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(child: rightColumn),
        ],
      );
    }

    // ── 竖屏（默认）：标题 → 搜索 → 内容 ──────────────────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        header,
        if (search != null) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          search!,
        ],
        const SizedBox(height: AppSpace.md),
        Expanded(child: body),
      ],
    );
  }
}
