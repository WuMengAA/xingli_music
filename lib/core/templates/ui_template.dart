import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 标准页面模板库（cl08）
/// ════════════════════════════════════════════════════════════════════════
///
/// 设计原则：**模板只管布局与样式，内容（文字/图片/数据）是独立层**。
/// - [UiTemplate] 定义三套标准页面骨架（液态玻璃 / M3 卡片 / 杂志编辑）；
/// - [TemplateTokens] 提供模板的样式令牌（圆角/间距/字号/列表风格）；
/// - 页面渲染用「模板骨架 + 填充数据」，换模板不换数据
///   → 「文字和图片、内容仅做单独层」。
///
/// 选择后持久化（设置 → 界面模板 → 模板工坊），作为以后所有页面的
/// 标准模板；新页面按所选模板的令牌构建布局。
enum UiTemplate {
  glass(
    '液态玻璃',
    '毛玻璃卡片 · 胶囊按钮 · 克制动效',
    Icons.blur_on_rounded,
  ),
  m3(
    'M3 卡片',
    'Material 3 · 卡片分层 · 水波纹',
    Icons.grid_view_rounded,
  ),
  magazine(
    '杂志编辑',
    '大标题 · 通栏头图 · 编辑推荐感',
    Icons.menu_book_rounded,
  );

  const UiTemplate(this.label, this.subtitle, this.icon);

  /// 模板名（设置页 / 模板工坊）。
  final String label;

  /// 一句话说明。
  final String subtitle;

  /// 展示图标。
  final IconData icon;

  /// 模板样式令牌。
  TemplateTokens get tokens => switch (this) {
        UiTemplate.glass => const TemplateTokens(
            cardRadius: 18,
            cardSpacing: 10,
            pagePadding: 16,
            titleSize: 22,
            heroFullBleed: false,
            listStyle: TemplateListStyle.cardGrid,
            accentFill: true,
          ),
        UiTemplate.m3 => const TemplateTokens(
            cardRadius: 12,
            cardSpacing: 8,
            pagePadding: 16,
            titleSize: 20,
            heroFullBleed: false,
            listStyle: TemplateListStyle.cardGrid,
            accentFill: false,
          ),
        UiTemplate.magazine => const TemplateTokens(
            cardRadius: 0,
            cardSpacing: 0,
            pagePadding: 20,
            titleSize: 28,
            heroFullBleed: true,
            listStyle: TemplateListStyle.plainRow,
            accentFill: false,
          ),
      };
}

/// 列表条目样式。
enum TemplateListStyle { cardGrid, plainRow }

/// 模板样式令牌（纯布局/视觉参数，不含业务内容）。
@immutable
class TemplateTokens {
  const TemplateTokens({
    required this.cardRadius,
    required this.cardSpacing,
    required this.pagePadding,
    required this.titleSize,
    required this.heroFullBleed,
    required this.listStyle,
    required this.accentFill,
  });

  /// 卡片圆角。
  final double cardRadius;

  /// 卡片间距。
  final double cardSpacing;

  /// 页面横向内边距。
  final double pagePadding;

  /// 大标题字号。
  final double titleSize;

  /// 头图是否通栏（铺满页宽，杂志风）。
  final bool heroFullBleed;

  /// 列表条目样式：卡片网格 / 纯文字行。
  final TemplateListStyle listStyle;

  /// 主按钮/选中态是否实色填充（玻璃模板强调色填充，M3 描边）。
  final bool accentFill;
}
