import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/templates/ui_template.dart';
import '../../providers/ui/template_provider.dart';
import '../../widgets/templates/template_library.dart';

/// 模板工坊（cl08）：展示几套标准页面模板 + 组件示例，选择后作为
/// 以后所有页面的标准模板。模板只管布局，文字/图片内容由数据层填充。
class TemplateGalleryPage extends ConsumerWidget {
  const TemplateGalleryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UiTemplate current = ref.watch(templateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('界面模板')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            '选择一套标准模板，作为以后所有页面的默认样式。'
            '模板只定义布局与样式，文字和图片内容由单独的数据层填充——'
            '换模板不换内容。',
            style: context.appText.bodyMuted,
          ),
          const SizedBox(height: 16),
          for (final UiTemplate t in UiTemplate.values) ...<Widget>[
            _TemplateCard(
              template: t,
              selected: current == t,
              onPreview: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(t.label)),
                      body: TemplatePagePreview(template: t),
                    ),
                  ),
                );
              },
              onSelect: () {
                ref.read(templateProvider.notifier).set(t);
              },
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Text(
            '组件示例 · ${current.label}',
            style: context.appText.subtitle,
          ),
          const SizedBox(height: 4),
          Text(
            '以下组件将随所选模板统一（圆角 / 填充 / 列表风格）。',
            style: context.appText.caption,
          ),
          const SizedBox(height: 12),
          ComponentSamples(template: current),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 单套模板卡片：信息 + 选中态 + 预览 / 设为标准。
class _TemplateCard extends ConsumerWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onPreview,
    required this.onSelect,
  });

  final UiTemplate template;
  final bool selected;
  final VoidCallback onPreview;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? c.accentSoft.withValues(alpha: 0.5) : c.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: selected ? c.accent : c.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? c.accent : c.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  template.icon,
                  size: 19,
                  color: selected ? c.onAccent : c.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      template.label,
                      style: context.appText.subtitle.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      template.subtitle,
                      style: context.appText.caption,
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 20, color: c.accent),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: onPreview,
                  child: const Text('预览'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onSelect,
                  child: Text(selected ? '已设为标准' : '设为标准'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
