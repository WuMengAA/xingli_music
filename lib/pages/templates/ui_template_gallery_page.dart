/// ════════════════════════════════════════════════════════════════════════
/// UI 模板画廊 —— 资产【控件预览、界面预览】
/// ════════════════════════════════════════════════════════════════════════
///
/// 把 [kUiTemplates] 全部模板做成画廊：
///   · 分类标签过滤（页面级 / 区块级 / 控件级）+ 关键词搜索
///   · 卡片实时预览（直接 build 渲染，所见即所得）
///   · 点击卡片 → 底部弹层：大预览 + 「在编辑器中打开」（以模板起步）
///     + 「复制节点 JSON」（可固化为资产 / 粘贴到别处）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/ui_editor_model.dart';
import '../../core/ui_templates.dart';
import 'ui_editor_page.dart';
import '../../widgets/notification/app_notify.dart';

/// 模板画廊页。
class UiTemplateGalleryPage extends StatefulWidget {
  const UiTemplateGalleryPage({super.key});

  @override
  State<UiTemplateGalleryPage> createState() => _UiTemplateGalleryPageState();
}

class _UiTemplateGalleryPageState extends State<UiTemplateGalleryPage> {
  UiTemplateCategory? _filter;
  String _query = '';

  List<UiTemplate> get _visible => kUiTemplates.where((UiTemplate t) {
        final bool byCat = _filter == null || t.category == _filter;
        final String q = _query.trim().toLowerCase();
        final bool byQuery = q.isEmpty ||
            t.name.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q) ||
            t.tags.any((String tag) => tag.toLowerCase().contains(q));
        return byCat && byQuery;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final List<UiTemplate> visible = _visible;
    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        title: const Text('UI 模板库'),
        backgroundColor: context.appColors.bgSurface,
        actions: <Widget>[
          IconButton(
            tooltip: '打开 UI 编辑器（从空白起步）',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const UiEditorPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 搜索 + 分类过滤。
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, 0),
            child: TextField(
              onChanged: (String v) => setState(() => _query = v),
              style: context.appText.body,
              decoration: InputDecoration(
                hintText: '搜索模板（名称 / 描述 / 标签）',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: context.appColors.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 10),
            child: Row(
              children: <Widget>[
                _filterChip(context, null, '全部'),
                for (final UiTemplateCategory c in UiTemplateCategory.values)
                  _filterChip(context, c, c.label),
              ],
            ),
          ),
          // 模板网格。
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text('没有匹配的模板', style: context.appText.bodyMuted),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(AppSpace.md, 4, AppSpace.md, AppSpace.xl),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 320,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (BuildContext c, int i) =>
                        _TemplateCard(template: visible[i], onOpen: () => _open(c, visible[i])),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(BuildContext context, UiTemplateCategory? cat, String label) {
    final bool sel = _filter == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => setState(() => _filter = cat),
        selectedColor: context.appColors.accent.withValues(alpha: 0.25),
        backgroundColor: context.appColors.bgSurface,
        labelStyle: context.appText.caption,
      ),
    );
  }

  Future<void> _open(BuildContext context, UiTemplate t) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) => _TemplateDetailSheet(template: t),
    );
  }
}

/// 模板卡片：顶部实时预览，下方名称/分类/描述。
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onOpen});
  final UiTemplate template;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final Color surface = context.appColors.bgSurface;
    final Color border = context.appColors.border;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 预览区（固定高度，黑色底衬托发光/深色模板）。
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFF0B1220),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                  child: Center(
                    child: OverflowBox(
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        child: template.build(context),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            template.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.appText.body.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.appColors.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            template.category.label.replaceFirst('级', '').replaceFirst(' ·', ''),
                            style: context.appText.caption.copyWith(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      template.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.appText.artist.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模板详情底部弹层：大预览 + 起步 / 复制 JSON。
class _TemplateDetailSheet extends StatelessWidget {
  const _TemplateDetailSheet({required this.template});
  final UiTemplate template;

  @override
  Widget build(BuildContext context) {
    final Color surface = context.appColors.bgSurface;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: context.appColors.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(template.name, style: context.appText.title),
                      const SizedBox(height: 2),
                      Text(template.description, style: context.appText.artist),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '复制节点 JSON',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () {
                    final String json = UiNode.container(
                      'root',
                      template.name,
                      gap: 12,
                      children: template.nodes(),
                    ).toJsonString();
                    // 复制到剪贴板 + 本地提示（走全局 toast 通道由调用方统一）。
                    Clipboard.setData(ClipboardData(text: json));
                    Navigator.of(context).pop();
                    appNotify(context, '已复制「${template.name}」节点 JSON');
                  },
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Container(
                constraints: const BoxConstraints(minHeight: 220),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                padding: const EdgeInsets.all(14),
                child: template.build(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.appColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('以「${'模板'}」起步，进入编辑器'),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UiEditorPage(initialTemplate: template),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
