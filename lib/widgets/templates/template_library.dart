import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/templates/template_content.dart';
import '../../core/templates/ui_template.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 模板渲染 + 组件示例（cl08）
/// ════════════════════════════════════════════════════════════════════════
///
/// 同一份 [TemplateContent] 喂给任意模板骨架，换模板不换数据
/// （模板只管布局，文字/图片/内容由数据层填充）。
/// 按模板骨架渲染「标准内容页」示例页（模板工坊全屏预览用）。
class TemplatePagePreview extends StatelessWidget {
  const TemplatePagePreview({super.key, required this.template});

  final UiTemplate template;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final TemplateTokens t = template.tokens;
    final TemplateContent content = kTemplateSampleContent;
    final bool grid = t.listStyle == TemplateListStyle.cardGrid;

    return ColoredBox(
      color: c.bgPage,
      child: ListView(
        padding: EdgeInsets.fromLTRB(t.pagePadding, 16, t.pagePadding, 24),
        children: <Widget>[
          // ── 标题层（文字仅填充） ──
          Text(
            content.title,
            style: context.appText.title.copyWith(
              fontSize: t.titleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(content.subtitle, style: context.appText.bodyMuted),
          const SizedBox(height: 16),
          // ── Hero 头图层 ──
          _HeroCard(template: template),
          const SizedBox(height: 16),
          // ── 列表层 ──
          if (grid)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: t.cardSpacing,
                crossAxisSpacing: t.cardSpacing,
                childAspectRatio: 1.45,
              ),
              itemCount: content.items.length,
              itemBuilder: (BuildContext _, int i) =>
                  _GridCard(item: content.items[i], template: template),
            )
          else
            for (final TemplateContentItem item in content.items)
              _PlainRow(item: item, template: template),
        ],
      ),
    );
  }
}

/// Hero 头图卡（magazine 通栏大卡 / glass·m3 圆角卡）。
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.template});

  final UiTemplate template;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final TemplateTokens t = template.tokens;
    final bool big = t.heroFullBleed;
    return Container(
      height: big ? 140 : 104,
      padding: EdgeInsets.all(big ? 20 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[c.accent, c.accentSoft],
        ),
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Text(
            kTemplateSampleContent.heroTitle,
            style: TextStyle(
              fontSize: big ? 22 : 18,
              fontWeight: FontWeight.w700,
              color: c.onAccent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            kTemplateSampleContent.heroSubtitle,
            style: TextStyle(
              fontSize: 12,
              color: c.onAccent.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

/// 网格卡片（glass：玻璃卡；m3：标准 Card）。
class _GridCard extends StatelessWidget {
  const _GridCard({required this.item, required this.template});

  final TemplateContentItem item;
  final UiTemplate template;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final TemplateTokens t = template.tokens;
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 图片占位层（色块，真实页面换封面图）。
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.accentSoft.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(t.cardRadius * 0.6),
            ),
            child: Icon(Icons.music_note_rounded, color: c.accent),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.appText.trackName,
        ),
        const SizedBox(height: 2),
        Text(
          item.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.appText.caption,
        ),
      ],
    );

    if (template == UiTemplate.glass) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.bgSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(t.cardRadius),
          border: Border.all(color: c.border),
        ),
        child: content,
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      color: c.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }
}

/// 杂志纯文字行（无卡片底，仅下分隔线）。
class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.item, required this.template});

  final TemplateContentItem item;
  final UiTemplate template;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: context.appText.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(item.subtitle, style: context.appText.caption),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: c.iconInactive),
        ],
      ),
    );
  }
}

/// 组件示例区（每套模板的组件变体：主按钮 / 次级按钮 / 卡片 / 标签）。
class ComponentSamples extends StatelessWidget {
  const ComponentSamples({super.key, required this.template});

  final UiTemplate template;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final TemplateTokens t = template.tokens;
    final double radius = t.cardRadius;

    Widget btn(bool primary) {
      final Widget child = Text(
        primary ? '主操作' : '次级操作',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: primary ? c.onAccent : c.textPrimary,
        ),
      );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: primary
              ? (t.accentFill ? c.accent : c.accentSoft)
              : c.bgSurface,
          borderRadius: BorderRadius.circular(radius),
          border: primary ? null : Border.all(color: c.border),
        ),
        child: child,
      );
    }

    Widget sampleCard() {
      final Widget inner = Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(radius * 0.6),
            ),
            child: Icon(Icons.album_rounded, size: 20, color: c.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('示例条目', style: context.appText.trackName),
                const SizedBox(height: 2),
                Text('副标题占位', style: context.appText.caption),
              ],
            ),
          ),
        ],
      );
      if (template == UiTemplate.glass) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.bgSurface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: c.border),
          ),
          child: inner,
        );
      }
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Padding(padding: const EdgeInsets.all(10), child: inner),
      );
    }

    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.bgSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Text(label, style: context.appText.caption),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[btn(true), const SizedBox(width: 10), btn(false)]),
        const SizedBox(height: 12),
        sampleCard(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[chip('标签一'), chip('标签二'), chip('标签三')],
        ),
      ],
    );
  }
}
