/// ════════════════════════════════════════════════════════════════════════
/// 设置布局 · 图形化整理器（开发者自定义）
/// ════════════════════════════════════════════════════════════════════════
///
/// 所见即所得地拖拽排布设置布局：
///   - 左侧「可用项池」：当前布局中所有设置项，长按可拖。
///   - 右侧「合集 → 组 → 项」树：拖拽排序、跨组/跨合集移动。
///   - 支持：新建合集 / 新建组 / 重命名 / 删除组 / 导出资产 JSON。
///   - 「导出资产」把当前布局序列化为 JSON → 开发者粘贴到
///     `assets/settings_layout.json` → 重新构建随包分发（跨设备传播）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/settings_layout.dart';
import '../../core/settings_item_registry.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/settings_layout_provider.dart';
import '../../widgets/notification/app_notify.dart';

class SettingsOrganizerPage extends ConsumerWidget {
  const SettingsOrganizerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsLayout layout = ref.watch(settingsLayoutProvider);
    // 可用项池 = 注册表全部设置项（不只是布局里已有的），拖入右侧组即添加；
    // 已用项带 ✔ 标记。
    final Set<String> usedIds = layout.allItems.map((SettingItem i) => i.id).toSet();
    final List<SettingItem> pool = <SettingItem>[
      for (final String id in kSettingItemRegistry.keys)
        SettingItem(
          id: id,
          title: kSettingItemRegistry[id]?.title ?? id,
          kind: layout.allItems
              .where((SettingItem i) => i.id == id)
              .map((SettingItem i) => i.kind)
              .firstOrNull ??
              SettingKind.entry,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置整理器'),
        actions: <Widget>[
          IconButton(
            tooltip: '导出资产 JSON（粘贴到 assets/settings_layout.json）',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => _export(context, ref, layout),
          ),
          IconButton(
            tooltip: '新建合集',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _addCollection(context, ref, layout),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 左侧：可用项池 ──
          SizedBox(
            width: 180,
            child: Container(
              color: context.appColors.bgSurface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.sm),
                    child: Text(
                      '可用设置项（${pool.length} 项 · 长按拖入右侧）',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        for (final SettingItem item in pool)
                          _DraggableItem(
                            item: item,
                            // 池 = 只读来源：拖走不移除（组 DragTarget 负责添加）。
                            inPool: true,
                            used: usedIds.contains(item.id),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── 右侧：合集树（合集卡可拖动排序）──
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(AppSpace.md),
              buildDefaultDragHandles: false,
              itemCount: layout.collections.length,
              onReorder: (int a, int b) =>
                  _reorderCollections(ref, layout, a, b),
              itemBuilder: (BuildContext context, int ci) {
                final SettingCollection c = layout.collections[ci];
                return ReorderableDragStartListener(
                  key: ValueKey<String>('col_${c.id}'),
                  index: ci,
                  child: _CollectionCard(
                    collection: c,
                    index: ci,
                    layout: layout,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 导出资产 ──────────────────────────────────────────
  Future<void> _export(
      BuildContext context, WidgetRef ref, SettingsLayout layout) async {
    final String json = exportSettingsLayoutJson(layout);
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    appNotify(context, '布局 JSON 已复制到剪贴板 → 粘贴到 assets/settings_layout.json');
  }

  Future<void> _addCollection(
      BuildContext context, WidgetRef ref, SettingsLayout layout) async {
    final TextEditingController c = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('新建合集'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '合集名称（如：机制）'),
          onSubmitted: (String v) => Navigator.of(dctx).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(c.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        ...layout.collections,
        SettingCollection(id: newCollectionId(), name: name),
      ],
    );
  }

  /// 合集拖动排序。
  void _reorderCollections(
      WidgetRef ref, SettingsLayout layout, int a, int b) {
    final List<SettingCollection> cols = <SettingCollection>[...layout.collections];
    if (a < 0 || a >= cols.length || b < 0 || b > cols.length) return;
    final SettingCollection moved = cols.removeAt(a);
    cols.insert((b > a ? b - 1 : b).clamp(0, cols.length), moved);
    ref.read(settingsLayoutProvider.notifier).state =
        SettingsLayout(collections: cols);
  }

  /// 从布局中移除某设置项（拖出池 = 从原位置移除）。
  void _removeItem(WidgetRef ref, SettingsLayout layout, SettingItem item) {
    final List<SettingCollection> cols = <SettingCollection>[
      for (final SettingCollection c in layout.collections)
        SettingCollection(
          id: c.id,
          name: c.name,
          groups: <SettingGroup>[
            for (final SettingGroup g in c.groups)
              SettingGroup(
                id: g.id,
                name: g.name,
                items: <SettingItem>[
                  for (final SettingItem i in g.items)
                    if (i.id != item.id) i,
                ],
              ),
          ],
        ),
    ];
    ref.read(settingsLayoutProvider.notifier).state =
        SettingsLayout(collections: cols);
  }
}

/// 可拖拽的设置项（左侧池 / 右侧组内复用）。
class _DraggableItem extends StatelessWidget {
  const _DraggableItem({
    required this.item,
    this.onMoved,
    this.inPool = false,
    this.used = false,
  });

  final SettingItem item;

  /// 拖拽结束回调（把项从原位置移除）；null = 保留原位置。
  final void Function(SettingItem)? onMoved;

  /// 处于左侧可用池（只读来源，拖走不移除）。
  final bool inPool;

  /// 池内该项是否已在布局中（显示 ✔）。
  final bool used;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<SettingItem>(
      data: item,
      feedback: Material(
        color: Colors.transparent,
        child: Chip(
          label: Text(item.title),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      ),
      onDragEnd: (_) => onMoved?.call(item),
      childWhenDragging: Opacity(opacity: 0.3, child: _tile(context)),
      child: _tile(context),
    );
  }

  Widget _tile(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(_icon(), size: 18),
        title: Text(item.title,
            style: Theme.of(context).textTheme.bodySmall),
        subtitle: item.subtitle.isEmpty
            ? (inPool ? Text(used ? '✓ 已在布局' : '点击拖入右侧', style: Theme.of(context).textTheme.labelSmall) : null)
            : Text(item.subtitle,
                style: Theme.of(context).textTheme.labelSmall),
        trailing: inPool && used
            ? Icon(Icons.check_circle, size: 14, color: Theme.of(context).colorScheme.primary)
            : null,
      );

  IconData _icon() => switch (item.kind) {
        SettingKind.entry => Icons.chevron_right_rounded,
        SettingKind.slider => Icons.tune_rounded,
        SettingKind.chips => Icons.sell_outlined,
        SettingKind.toggle => Icons.toggle_on_outlined,
        SettingKind.block => Icons.dashboard_customize_outlined,
      };
}

/// 右侧合集卡（含组列表 + 组内项拖拽）。
class _CollectionCard extends ConsumerWidget {
  const _CollectionCard({
    required this.collection,
    required this.index,
    required this.layout,
  });

  final SettingCollection collection;
  final int index;
  final SettingsLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      color: context.appColors.bgSurface,
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(collection.name,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: '重命名合集',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () => _renameCollection(context, ref),
                ),
                IconButton(
                  tooltip: '新建组',
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () => _addGroup(context, ref),
                ),
                IconButton(
                  tooltip: '删除合集',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: () => _deleteCollection(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (int gi = 0; gi < collection.groups.length; gi++)
              _GroupCard(
                collection: collection,
                group: collection.groups[gi],
                groupIndex: gi,
                layout: layout,
              ),
            // 组间拖拽目标：把设置项拖到合集末尾 = 追加到新组（简化：追加最后一组）。
            DragTarget<SettingItem>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) =>
                  _appendToLastGroup(ref, details.data),
              builder: (BuildContext context, List<Object?> _, __) =>
                  Container(
                height: 40,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: context.appColors.border,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '拖设置项到这里 = 追加到「${collection.groups.isEmpty ? '（空合集）' : collection.groups.last.name}」',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            // 组拖拽目标：把整组拖到本合集（移到末尾）。
            DragTarget<SettingGroup>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) => _moveGroupInto(ref, details.data),
              builder: (BuildContext context, List<Object?> _, __) => Container(
                height: 32,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: context.appColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '拖「组」到这里 = 移入「${collection.name}」',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameCollection(BuildContext context, WidgetRef ref) async {
    final TextEditingController c =
        TextEditingController(text: collection.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('重命名合集'),
        content: TextField(controller: c, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(c.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (final SettingCollection c in cur.collections)
          c.id == collection.id ? c.copyWith(name: name) : c,
      ],
    );
  }

  /// 把整组从原合集移除 → 添加到本合集末尾（跨合集移动）。
  void _moveGroupInto(WidgetRef ref, SettingGroup group) {
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    if (cur.collections.any((SettingCollection c) =>
        c.id == collection.id && c.groups.any((SettingGroup g) => g.id == group.id))) {
      return; // 已在目标合集
    }
    final List<SettingCollection> cols = <SettingCollection>[
      for (final SettingCollection c in cur.collections)
        c.copyWith(groups: <SettingGroup>[
          for (final SettingGroup g in c.groups)
            if (g.id != group.id) g,
        ]),
    ];
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (final SettingCollection c in cols)
          c.id == collection.id
              ? c.copyWith(groups: <SettingGroup>[...c.groups, group])
              : c,
      ],
    );
  }

  Future<void> _addGroup(BuildContext context, WidgetRef ref) async {    final TextEditingController c = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('新建组'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '组名（如：性能与质量）'),
          onSubmitted: (String v) => Navigator.of(dctx).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(c.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    final List<SettingCollection> cols = <SettingCollection>[
      for (int i = 0; i < cur.collections.length; i++)
        if (i == index)
          SettingCollection(
            id: collection.id,
            name: collection.name,
            groups: <SettingGroup>[
              ...collection.groups,
              SettingGroup(id: newGroupId(), name: name),
            ],
          )
        else
          cur.collections[i],
    ];
    ref.read(settingsLayoutProvider.notifier).state =
        SettingsLayout(collections: cols);
  }

  void _deleteCollection(BuildContext context, WidgetRef ref) {
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (int i = 0; i < cur.collections.length; i++)
          if (i != index) cur.collections[i],
      ],
    );
  }

  void _appendToLastGroup(WidgetRef ref, SettingItem item) {
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    if (cur.collections.length <= index) return;
    final SettingCollection c = cur.collections[index];
    if (c.groups.isEmpty) return;
    final int gi = c.groups.length - 1;
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (int i = 0; i < cur.collections.length; i++)
          if (i == index)
            SettingCollection(
              id: c.id,
              name: c.name,
              groups: <SettingGroup>[
                for (int g = 0; g < c.groups.length; g++)
                  if (g == gi)
                    SettingGroup(
                      id: c.groups[g].id,
                      name: c.groups[g].name,
                      items: <SettingItem>[
                        ...c.groups[g].items.where((SettingItem x) => x.id != item.id),
                        item,
                      ],
                    )
                  else
                    c.groups[g],
              ],
            )
          else
            cur.collections[i],
      ],
    );
  }
}

/// 组卡（组内项可拖拽排序 + 删除组 + 重命名）。
class _GroupCard extends ConsumerWidget {
  const _GroupCard({
    required this.collection,
    required this.group,
    required this.groupIndex,
    required this.layout,
  });

  final SettingCollection collection;
  final SettingGroup group;
  final int groupIndex;
  final SettingsLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LongPressDraggable<SettingGroup>(
      data: group,
      feedback: Material(
        color: Colors.transparent,
        child: Chip(
          avatar: const Icon(Icons.drag_indicator, size: 14),
          label: Text('移动组：${group.name}'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      ),
      // onDragEnd 不移除：目标合集 DragTarget 负责「移入」，源保留直到成功接收。
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.appColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.drag_indicator, size: 14, color: Theme.of(context).colorScheme.outline),
                // 组内排序（合集内上移/下移）。
                IconButton(
                  tooltip: '组上移',
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _moveGroup(ref, -1),
                ),
                IconButton(
                  tooltip: '组下移',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _moveGroup(ref, 1),
                ),
                Expanded(
                  child: Text(group.name,
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                IconButton(
                  tooltip: '重命名组',
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => _rename(context, ref),
                ),
                IconButton(
                  tooltip: '删除组',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => _delete(ref),
                ),
              ],
            ),
            // 组内项：ReorderableListView（拖拽排序）+ 每项可拖出（长按拖走）。
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: group.items.length,
              onReorder: (int a, int b) => _reorder(ref, a, b),
              itemBuilder: (BuildContext context, int i) {
                final SettingItem item = group.items[i];
                return DragTarget<SettingItem>(
                  key: ValueKey<String>('${collection.id}_${group.id}_${item.id}'),
                  onWillAcceptWithDetails: (_) => true,
                  onAcceptWithDetails: (details) =>
                      _moveInto(ref, details.data, i),
                  builder: (BuildContext context, List<Object?> _, __) =>
                      _DraggableItem(item: item),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 在合集内上移/下移组（delta = ±1）。用 group.id 定位（防 index 漂移）。
  void _moveGroup(WidgetRef ref, int delta) {
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    final SettingCollection? col = cur.collections
        .where((SettingCollection c) => c.id == collection.id)
        .firstOrNull;
    if (col == null) return;
    final List<SettingGroup> groups = <SettingGroup>[...col.groups];
    final int i = groups.indexWhere((SettingGroup g) => g.id == group.id);
    if (i < 0) return;
    final int target = (i + delta).clamp(0, groups.length - 1);
    if (target == i) return;
    final SettingGroup g = groups.removeAt(i);
    groups.insert(target, g);
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (final SettingCollection c in cur.collections)
          c.id == collection.id ? c.copyWith(groups: groups) : c,
      ],
    );
  }

  void _rename(BuildContext context, WidgetRef ref) async {
    final TextEditingController c = TextEditingController(text: group.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: const Text('重命名组'),
        content: TextField(controller: c, autofocus: true),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(c.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    _updateGroup(ref, name: name);
  }

  void _delete(WidgetRef ref) {
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (final SettingCollection c in cur.collections)
          if (c.id == collection.id)
            SettingCollection(
              id: c.id,
              name: c.name,
              groups: <SettingGroup>[
                for (int g = 0; g < c.groups.length; g++)
                  if (g != groupIndex) c.groups[g],
              ],
            )
          else
            c,
      ],
    );
  }

  void _reorder(WidgetRef ref, int a, int b) {
    final List<SettingItem> items = <SettingItem>[...group.items];
    if (a < 0 || a >= items.length || b < 0 || b > items.length) return;
    final SettingItem moved = items.removeAt(a);
    final int insert = b > a ? b - 1 : b;
    items.insert(insert.clamp(0, items.length), moved);
    _updateGroup(ref, items: items);
  }

  /// 把拖入的 item 放到本组 index 位置（从原位置移除后插入）。
  void _moveInto(WidgetRef ref, SettingItem item, int index) {
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    // 先从全布局移除该 item。
    final List<SettingCollection> cols = <SettingCollection>[
      for (final SettingCollection c in cur.collections)
        SettingCollection(
          id: c.id,
          name: c.name,
          groups: <SettingGroup>[
            for (final SettingGroup g in c.groups)
              SettingGroup(
                id: g.id,
                name: g.name,
                items: <SettingItem>[
                  for (final SettingItem i in g.items)
                    if (i.id != item.id) i,
                ],
              ),
          ],
        ),
    ];
    // 再插入本组 index。
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (final SettingCollection c in cols)
          if (c.id == collection.id)
            SettingCollection(
              id: c.id,
              name: c.name,
              groups: <SettingGroup>[
                for (int g = 0; g < c.groups.length; g++)
                  if (g == groupIndex)
                    SettingGroup(
                      id: c.groups[g].id,
                      name: c.groups[g].name,
                      items: <SettingItem>[
                        for (int i = 0; i < c.groups[g].items.length; i++)
                          if (i == index) item,
                          ...c.groups[g].items.where((SettingItem x) => x.id != item.id),
                      ],
                    )
                  else
                    c.groups[g],
              ],
            )
          else
            c,
      ],
    );
  }

  void _updateGroup(WidgetRef ref, {String? name, List<SettingItem>? items}) {
    final SettingsLayout cur = ref.read(settingsLayoutProvider);
    ref.read(settingsLayoutProvider.notifier).state = SettingsLayout(
      collections: <SettingCollection>[
        for (final SettingCollection c in cur.collections)
          if (c.id == collection.id)
            SettingCollection(
              id: c.id,
              name: c.name,
              groups: <SettingGroup>[
                for (int g = 0; g < c.groups.length; g++)
                  if (g == groupIndex)
                    SettingGroup(
                      id: group.id,
                      name: name ?? group.name,
                      items: items ?? group.items,
                    )
                  else
                    c.groups[g],
              ],
            )
          else
            c,
      ],
    );
  }
}
