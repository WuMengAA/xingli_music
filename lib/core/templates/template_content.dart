import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 模板内容层（cl08）
/// ════════════════════════════════════════════════════════════════════════
///
/// 内容与模板完全解耦：同一份 [TemplateContent] 数据喂给任意模板骨架，
/// 换模板不换数据。真实页面接入时用业务数据填充同一模型即可；
/// 模板工坊用 [kTemplateSampleContent] 作填充示例（文字仅占位）。
@immutable
class TemplateContent {
  const TemplateContent({
    required this.title,
    required this.subtitle,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.items,
  });

  /// 页面大标题。
  final String title;

  /// 页面副标题。
  final String subtitle;

  /// 头图主文案。
  final String heroTitle;

  /// 头图副文案。
  final String heroSubtitle;

  /// 条目列表。
  final List<TemplateContentItem> items;
}

@immutable
class TemplateContentItem {
  const TemplateContentItem({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

/// 模板工坊示例数据（文字均为填充占位，图片用主题色块代替）。
const TemplateContent kTemplateSampleContent = TemplateContent(
  title: '场景歌单',
  subtitle: '为每个场景挑选恰好的音乐',
  heroTitle: '今日精选',
  heroSubtitle: '戴上耳机，进入你的音乐世界',
  items: <TemplateContentItem>[
    TemplateContentItem(title: '雨夜书房', subtitle: '雨声 · 白噪音 · 轻音乐'),
    TemplateContentItem(title: '极光草原', subtitle: '氛围电子 · 环境音'),
    TemplateContentItem(title: '深海漫游', subtitle: '器乐 · 后摇 · 沉浸'),
    TemplateContentItem(title: '森林晨光', subtitle: '鸟鸣 · 民谣 · 原声'),
    TemplateContentItem(title: '星际漂流', subtitle: '合成器 · 太空氛围'),
    TemplateContentItem(title: '篝火营地', subtitle: '民谣 · 手风琴 · 温暖'),
  ],
);
