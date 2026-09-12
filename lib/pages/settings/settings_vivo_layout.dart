import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings_item_registry.dart';
import '../../core/settings_layout.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/settings_layout_provider.dart';
import 'package:xingli_music/widgets/design/glass_controls.dart';

/// 计算每个设置 id 的「规范合集」：同名 id 只在它**首次出现**的合集里渲染，
/// 其余合集里的重复入口在 [SettingsVivoLayout] 中隐藏（去重）。
/// 判定：先按布局合集顺序取首个；若同名 id 在多个合集出现，取 [SettingItemDef.priority]
/// 更高的合集作为规范入口（高频设置优先保留其入口）。
Map<String, String> _canonicalCollectionByItem(SettingsLayout layout) {
  final Map<String, String> canonical = <String, String>{};
  final Map<String, int> bestPriority = <String, int>{};
  for (final SettingCollection c in layout.collections) {
    for (final SettingGroup g in c.groups) {
      for (final SettingItem item in g.items) {
        final int p = kSettingItemRegistry[item.id]?.priority ?? 0;
        final String? existing = canonical[item.id];
        if (existing == null || p > (bestPriority[item.id] ?? 0)) {
          canonical[item.id] = c.id;
          bestPriority[item.id] = p;
        }
      }
    }
  }
  return canonical;
}

/// 某设置项是否命中搜索词：匹配 标题 + 副标题 + 关键词 + 同义词
/// （布局项与注册表项都会参与），统一小写后做包含判断。
bool _itemMatchesQuery(SettingItem item, String query) {
  final SettingItemDef? def = kSettingItemRegistry[item.id];
  final List<String> parts = <String>[
    item.title,
    item.subtitle,
    if (def != null) def.title,
    if (def != null) def.subtitle,
    ...? def?.keywords,
    ...? def?.aliases,
  ];
  final String haystack = parts.map((String s) => s.toLowerCase()).join(' ');
  return haystack.contains(query);
}

/// vivo 式设置布局：左侧分类导航 + 右侧内容区（大卡片分区）。
///
/// 数据来自 [settingsLayoutProvider]（默认 [kDefaultSettingsLayout]，可经
/// 设置布局编辑器拖拽自定义），右侧按「选中合集 → 组 → 项」渲染，
/// 每项由 [buildSettingItem] 按 id 构建（registry 驱动，与游戏设置包厢一致）。
///
/// - **横屏 / 宽屏**：左侧竖向导航条（固定宽）+ 右侧可滚动内容区；
/// - **竖屏 / 窄屏**：顶部横向导航条（可横滑）+ 下方可滚动内容区。
class SettingsVivoLayout extends ConsumerStatefulWidget {
  const SettingsVivoLayout({super.key});

  @override
  ConsumerState<SettingsVivoLayout> createState() =>
      _SettingsVivoLayoutState();
}

class _SettingsVivoLayoutState extends ConsumerState<SettingsVivoLayout> {
  /// 设置搜索词（P0-C1/P1-02：内容容器顶部胶囊搜索栏，过滤设置项）。
  final TextEditingController _queryCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsLayout layout = ref.watch(settingsLayoutProvider);
    final String selectedId =
        ref.watch(layoutSelectedCollectionProvider);

    final List<SettingCollection> collections = layout.collections;
    if (collections.isEmpty) {
      return Center(
        child: Text('暂无设置分类', style: context.appText.bodyMuted),
      );
    }

    SettingCollection? selected;
    for (final SettingCollection c in collections) {
      if (c.id == selectedId) {
        selected = c;
        break;
      }
    }
    selected ??= collections.first;

    final bool wide =
        MediaQuery.sizeOf(context).width >= AppSize.landscapeBreakpoint;

    final Widget content = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NavRail(
                collections: collections,
                selectedId: selected.id,
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: _CollectionContent(collection: selected),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _NavStrip(
                collections: collections,
                selectedId: selected.id,
              ),
              const SizedBox(height: AppSpace.md),
              Expanded(
                child: _CollectionContent(collection: selected),
              ),
            ],
          );

    final String q = _query.trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsSearchBar(
          controller: _queryCtrl,
          onChanged: (String v) => setState(() => _query = v),
        ),
        const SizedBox(height: AppSpace.sm),
        Expanded(
          child: q.isEmpty
              ? content
              : _SearchResultsView(query: q, onClear: _clearSearch),
        ),
      ],
    );
  }

  void _clearSearch() {
    _queryCtrl.clear();
    setState(() => _query = '');
  }
}

/// 设置页顶部胶囊搜索栏（P0-C1：全宽、离顶紧凑、过滤当前页设置项）。
class _SettingsSearchBar extends StatelessWidget {
  const _SettingsSearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: context.appText.body,
        decoration: InputDecoration(
          hintText: '搜索设置项',
          hintStyle: context.appText.bodyMuted,
          prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary),
          suffixIcon: controller.text.isEmpty
              ? null
              : XGlassIconButton(
                icon: Icon(Icons.close_rounded, color: c.textSecondary),
                onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                tooltip: '清除',
              ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// 搜索结果：跨全部合集匹配的设置项（P1-02 数据驱动，零写死）。
class _SearchResultsView extends ConsumerWidget {
  const _SearchResultsView({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsLayout layout = ref.watch(settingsLayoutProvider);
    final AppThemeColors c = context.appColors;

    // 搜索匹配：标题 + 副标题 + 关键词 + 同义词（见 [_itemMatchesQuery]）。
    // 同名 id 只保留首个命中（去重），命中结果按 priority 降序、再按标题排，
    // 高频设置排在最前（确定性）。
    final List<(SettingCollection, SettingGroup, SettingItem, int)> ranked =
        <(SettingCollection, SettingGroup, SettingItem, int)>[];
    final Set<String> seen = <String>{};
    for (final SettingCollection collection in layout.collections) {
      for (final SettingGroup group in collection.groups) {
        for (final SettingItem item in group.items) {
          if (seen.contains(item.id)) continue; // 同名 id 去重，仅首个入口
          if (!_itemMatchesQuery(item, query)) continue;
          seen.add(item.id);
          final int p = kSettingItemRegistry[item.id]?.priority ?? 0;
          ranked.add((collection, group, item, p));
        }
      }
    }
    ranked.sort((a, b) {
      final int cmp = b.$4.compareTo(a.$4);
      if (cmp != 0) return cmp;
      return a.$3.title.toLowerCase().compareTo(b.$3.title.toLowerCase());
    });
    final List<(SettingCollection, SettingGroup, SettingItem)> hits =
        ranked.map((t) => (t.$1, t.$2, t.$3)).toList();

    if (hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off_rounded, size: 40, color: c.textSecondary),
            const SizedBox(height: 10),
            Text(
              '未找到与「$query」相关的设置项',
              style: context.appText.bodyMuted,
            ),
          ],
        ),
      );
    }

    final String? currentId =
        ref.watch(layoutSelectedCollectionProvider);

    return ListView(
      padding: const EdgeInsets.only(
        bottom: AppSpace.lg,
        right: AppSpace.md,
      ),
      children: <Widget>[
        for (final hit in hits) ...<Widget>[
          Container(
            margin: const EdgeInsets.only(bottom: AppSpace.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: c.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                buildSettingItem(context, ref, hit.$3.id),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, top: 2),
                  child: Text(
                    '在 ${hit.$1.name} · ${hit.$2.name} 中',
                    style: context.appText.bodyMuted.copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        Center(
          child: XGlassButton(
            onPressed: () {
              if (currentId != null && currentId.isNotEmpty) {
                ref.read(layoutSelectedCollectionProvider.notifier).state =
                    currentId;
              }
              onClear();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                Icon(Icons.arrow_back_rounded, size: 16),
                SizedBox(width: 8),
                Text('返回设置'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 横屏左侧竖向导航条（分类合集）。
class _NavRail extends ConsumerWidget {
  const _NavRail({required this.collections, required this.selectedId});

  final List<SettingCollection> collections;
  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    return Container(
      width: 168,
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.border),
      ),
      child: ListView(
        children: <Widget>[
          for (final SettingCollection col in collections)
            _NavTile(
              label: col.name,
              selected: col.id == selectedId,
              onTap: () => ref
                  .read(layoutSelectedCollectionProvider.notifier)
                  .state = col.id,
            ),
        ],
      ),
    );
  }
}

/// 竖屏顶部横向导航条（分类合集，可横滑）。
class _NavStrip extends ConsumerWidget {
  const _NavStrip({required this.collections, required this.selectedId});

  final List<SettingCollection> collections;
  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: Row(
        children: <Widget>[
          for (final SettingCollection col in collections) ...<Widget>[
            _NavChip(
              label: col.name,
              selected: col.id == selectedId,
              onTap: () => ref
                  .read(layoutSelectedCollectionProvider.notifier)
                  .state = col.id,
            ),
            const SizedBox(width: AppSpace.xs),
          ],
        ],
      ),
    );
  }
}

/// 竖向导航条目（横屏）。
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 10,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: selected ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    label,
                    style: context.appText.body.copyWith(
                      color: selected ? c.accent : c.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 横向导航芯片（竖屏）。
class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Material(
      color: selected ? c.accent : c.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? c.accent : c.border,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: context.appText.body.copyWith(
              color: selected ? c.onAccent : c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧内容区：选中合集的各组卡片（项由 registry 构建）。
class _CollectionContent extends ConsumerWidget {
  const _CollectionContent({required this.collection});

  final SettingCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    if (collection.groups.isEmpty) {
      return Center(
        child: Text('暂无设置内容', style: context.appText.bodyMuted),
      );
    }
    // 跨合集去重：同名 id 只在规范合集里渲染，其余合集的重复入口隐藏，
    // 避免「同一设置出现在多处」（如 图形后端 / 特效 在「个性」与「游戏」重复列出）。
    final SettingsLayout layout = ref.watch(settingsLayoutProvider);
    final Map<String, String> canonical = _canonicalCollectionByItem(layout);
    return ListView(
      padding: const EdgeInsets.only(
        bottom: AppSpace.lg,
        right: AppSpace.md,
      ),
      children: <Widget>[
        for (final SettingGroup group in collection.groups) ...<Widget>[
          if (group.name.isNotEmpty) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.md,
                AppSpace.xs,
                AppSpace.md,
                AppSpace.sm,
              ),
              child: Text(
                group.name,
                style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700) ??
                    context.appText.subtitle,
              ),
            ),
          ],
          Container(
            margin: const EdgeInsets.only(bottom: AppSpace.md),
            decoration: BoxDecoration(
              color: c.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final SettingItem item in group.items) ...<Widget>[
                      if (canonical[item.id] != collection.id)
                        const SizedBox.shrink()
                      else ...<Widget>[
                        buildSettingItem(context, ref, item.id),
                        if (item != group.items.last)
                          const Divider(height: 1),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
