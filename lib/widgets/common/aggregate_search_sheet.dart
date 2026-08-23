/// ════════════════════════════════════════════════════════════════════════
/// 聚合搜索弹层（预设组件 · Task #519）
/// ════════════════════════════════════════════════════════════════════════
///
/// 还原 Ardot 设计 `sheet-聚合搜索`（3:536 / 3:537）：
///   - 顶部抓手小条 + 圆角搜索输入框
///   - 一行可切换标签（设计默认 歌曲 / 歌单 / 用户）
///   - 结果区（由调用方通过 [body] 注入，典型为若干 [AggregateResultTile]）
///
/// 外观完全跟随主题 / 皮肤：玻璃用 [LiquidGlass]，所有颜色取自 `context.appColors`，
/// 不写死任何品牌色。搜索词与选中标签通过回调上抛，便于调用方用 Riverpod Provider
/// 驱动结果列表。
///
/// 用法：
/// ```dart
/// await AggregateSearchSheet.show(
///   context: context,
///   tabs: const <String>['歌曲', '歌单', '用户'],
///   onQueryChanged: (q) => ref.read(searchQueryProvider.notifier).set(q),
///   onTabChanged: (i) => ref.read(searchTabProvider.notifier).set(i),
///   body: const _SearchResults(), // 自行 Consumer 渲染结果
/// );
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../widgets/liquid_glass.dart';

/// 聚合搜索底部弹层。
class AggregateSearchSheet extends StatefulWidget {
  const AggregateSearchSheet({
    super.key,
    this.hint = '搜索歌曲、歌单、用户',
    required this.tabs,
    this.initialTabIndex = 0,
    this.onQueryChanged,
    this.onTabChanged,
    this.body,
  });

  /// 搜索框占位文案。
  final String hint;

  /// 标签列表（设计默认 3 个：歌曲 / 歌单 / 用户）。
  final List<String> tabs;

  /// 初始选中标签下标。
  final int initialTabIndex;

  /// 搜索词变化回调。
  final ValueChanged<String>? onQueryChanged;

  /// 选中标签变化回调。
  final ValueChanged<int>? onTabChanged;

  /// 结果区内容（由调用方注入，通常是一个 [Consumer]）。
  final Widget? body;

  /// 以模态底部弹层展示。
  static Future<T?> show<T>({
    required BuildContext context,
    String hint = '搜索歌曲、歌单、用户',
    required List<String> tabs,
    int initialTabIndex = 0,
    ValueChanged<String>? onQueryChanged,
    ValueChanged<int>? onTabChanged,
    Widget? body,
    bool isDismissible = true,
  }) {
    final AppThemeColors colors = context.appColors;
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: colors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      builder: (BuildContext ctx) => AggregateSearchSheet(
        hint: hint,
        tabs: tabs,
        initialTabIndex: initialTabIndex,
        onQueryChanged: onQueryChanged,
        onTabChanged: onTabChanged,
        body: body,
      ),
    );
  }

  @override
  State<AggregateSearchSheet> createState() => _AggregateSearchSheetState();
}

class _AggregateSearchSheetState extends State<AggregateSearchSheet> {
  late int _tab;
  final TextEditingController _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTabIndex.clamp(0, widget.tabs.length - 1);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return LiquidGlass(
      radius: AppRadius.xl,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(child: _Grabber(colors: colors)),
          const SizedBox(height: 12),
          _SearchField(
            colors: colors,
            hint: widget.hint,
            controller: _ctrl,
            onChanged: widget.onQueryChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: widget.tabs
                .asMap()
                .entries
                .map(
                  (MapEntry<int, String> e) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: e.key < widget.tabs.length - 1 ? 10 : 0,
                      ),
                      child: _TabChip(
                        colors: colors,
                        label: e.value,
                        selected: e.key == _tab,
                        onTap: () {
                          if (e.key == _tab) return;
                          setState(() => _tab = e.key);
                          widget.onTabChanged?.call(e.key);
                        },
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (widget.body != null) ...<Widget>[
            const SizedBox(height: 12),
            widget.body!,
          ],
        ],
      ),
    );
  }
}

/// 顶部抓手小条。
class _Grabber extends StatelessWidget {
  const _Grabber({required this.colors});
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) => Container(
        width: 60,
        height: 5,
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

/// 搜索输入框。
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.colors,
    required this.hint,
    required this.controller,
    this.onChanged,
  });

  final AppThemeColors colors;
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border.all(color: colors.border, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: colors.textPrimary),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 14, color: colors.textTertiary),
          prefixIcon: Icon(Icons.search, size: 18, color: colors.iconInactive),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 40),
        ),
      ),
    );
  }
}

/// 标签药丸（选中=强调色实心，未选=表面色描边）。
class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.colors,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppThemeColors colors;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.accent : colors.bgSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? colors.accent : colors.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: selected ? colors.onAccent : colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 聚合搜索结果行（320×48，圆角描边磁贴）。
///
/// [leading] 通常为封面/头像；[trailing] 可为时长、箭头等附加信息。
class AggregateResultTile extends StatelessWidget {
  const AggregateResultTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return Material(
      color: colors.bgSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border, width: 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
