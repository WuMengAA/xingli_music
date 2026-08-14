/// ════════════════════════════════════════════════════════════════════════
/// UI 编辑器 · 自动纠错规则引擎
/// ════════════════════════════════════════════════════════════════════════
///
/// 对可编辑节点树（[UiNode]）跑一组设计/可访问性规则，产出问题列表。
/// 编辑器把问题列表展示在纠错面板，点击可定位到对应节点。
///
/// 规则清单（当前内置）：
///   1. 文本对比度（WCAG 相对亮度，AA 正文 4.5:1 / 大字 3:1）
///   2. 子元素溢出父容器（尺寸估算）
///   3. 间距一致性（gap/padding 偏离 4dp 网格 + 常用刻度）
///   4. 自由定位元素重叠（x/y 矩形相交）
///   5. 空容器（无子节点且无显式尺寸）
///   6. 按钮无文本且无图标（点击无意义）
///   7. 字号过小（< 10）
///   8. 节点名缺失 / 默认占位名
library;

import 'dart:math' as math;

import 'ui_editor_model.dart';

/// 问题严重度。
enum UiIssueSeverity {
  info,
  warning,
  error,
}

/// 一条纠错问题。
class UiIssue {
  const UiIssue({
    required this.severity,
    required this.message,
    this.nodeId,
    this.nodeName,
    this.fix,
  });

  final UiIssueSeverity severity;
  final String message;
  final String? nodeId;
  final String? nodeName;

  /// 修复建议（一句话）。
  final String? fix;

  String get severityLabel => switch (severity) {
        UiIssueSeverity.error => '错误',
        UiIssueSeverity.warning => '警告',
        UiIssueSeverity.info => '提示',
      };
}

// ─────────────────────────────────────────────────────────────────────────
// 颜色工具
// ─────────────────────────────────────────────────────────────────────────

/// 相对亮度（WCAG 2.1）：sRGB → linear → L。
double _relativeLuminance(int argb) {
  double ch(num v) {
    final double s = v.toDouble() / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
}

/// 对比度（1~21）。
double contrastRatio(int a, int b) {
  final double la = _relativeLuminance(a);
  final double lb = _relativeLuminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 取节点的有效背景色：自身 color（或渐变平均色）→ 向上找容器 → 默认深色底。
int _effectiveBg(UiNode node, UiNode root, int fallback) {
  // 渐变：用起止色平均色做背景（保守估算）。
  final int? gs = parseHexColor(node.gradientStart);
  final int? ge = parseHexColor(node.gradientEnd);
  if (gs != null && ge != null) {
    int mix(int a, int b) {
      int ch(int x, int y) => ((x >> 24 & 0xFF) + (y >> 24 & 0xFF)) ~/ 2;
      int cl(int x, int y) => ((x >> 16 & 0xFF) + (y >> 16 & 0xFF)) ~/ 2;
      int cm(int x, int y) => ((x >> 8 & 0xFF) + (y >> 8 & 0xFF)) ~/ 2;
      int c0(int x, int y) => ((x & 0xFF) + (y & 0xFF)) ~/ 2;
      return (ch(a, b) << 24) | (cl(a, b) << 16) | (cm(a, b) << 8) | c0(a, b);
    }

    return mix(gs, ge);
  }
  final int? own = parseHexColor(node.color);
  if (own != null) return own;
  // 向上遍历找最近的带色祖先。
  UiNode? cur = node;
  while (cur != null) {
    final int? c = parseHexColor(cur.color);
    if (c != null) return c;
    final int? cg = parseHexColor(cur.gradientStart);
    final int? ce = parseHexColor(cur.gradientEnd);
    if (cg != null && ce != null) return (cg + ce) ~/ 2; // 祖先渐变：平均色
    cur = _parentOf(root, cur.id);
  }
  return fallback;
}

UiNode? _parentOf(UiNode root, String childId) {
  UiNode? found;
  root.walk((UiNode n) {
    if (n.children.any((UiNode c) => c.id == childId)) found = n;
  });
  return found;
}

// ─────────────────────────────────────────────────────────────────────────
// 规则引擎
// ─────────────────────────────────────────────────────────────────────────

/// 4dp 网格 + 常用刻度（AppSpace 体系）。
const List<double> _goodGaps = <double>[4, 5, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48];

/// 对整棵树跑规则，返回问题列表（按严重度降序）。
List<UiIssue> runUiRules(UiNode root) {
  final List<UiIssue> issues = <UiIssue>[];
  root.walk((UiNode n) {
    issues.addAll(_checkNode(n, root));
  });
  issues.sort((UiIssue a, UiIssue b) => b.severity.index - a.severity.index);
  return issues;
}

List<UiIssue> _checkNode(UiNode n, UiNode root) {
  final List<UiIssue> out = <UiIssue>[];
  final int bg = _effectiveBg(n, root, 0xFF121218);

  // 1. 文本对比度（WCAG AA）。
  if (n.type == UiNodeType.text || n.type == UiNodeType.button) {
    final String? fgHex = n.textColor ?? (n.type == UiNodeType.button ? '#F2F2F7' : null);
    if (fgHex != null) {
      final int fg = parseHexColor(fgHex) ?? 0xFFF2F2F7;
      final double cr = contrastRatio(fg, bg);
      final double need = n.fontSize >= 18 ? 3.0 : 4.5;
      if (cr < need) {
        out.add(UiIssue(
          severity: UiIssueSeverity.error,
          message: '「${n.name}」文本对比度 ${cr.toStringAsFixed(2)}:1 < ${need.toStringAsFixed(1)}:1（WCAG AA）',
          nodeId: n.id,
          nodeName: n.name,
          fix: '提高文本亮度或加深背景，或换用主题语义色 context.appColors.textPrimary',
        ));
      }
    }
  }

  // 2. 子元素溢出估算。
  if (n.type == UiNodeType.container && n.children.isNotEmpty && n.width != null) {
    double used = 0;
    for (final UiNode c in n.children) {
      used += _estimateWidth(c, n);
      used += n.gap;
    }
    if (used > 0 && n.width! > 0 && used - n.gap > n.width! * 1.15) {
      out.add(UiIssue(
        severity: UiIssueSeverity.warning,
        message: '「${n.name}」子元素估算总宽 ${used.toStringAsFixed(0)} 超过容器 ${n.width!.toStringAsFixed(0)}',
        nodeId: n.id,
        nodeName: n.name,
        fix: '改用 Wrap / 减小 gap / 加大容器宽度，或把文本改 Expanded 自动省略',
      ));
    }
  }

  // 3. 间距一致性（gap / padding 偏离 4dp 刻度）。
  if (!_goodGaps.contains(n.gap) && n.gap > 0) {
    out.add(UiIssue(
      severity: UiIssueSeverity.info,
      message: '「${n.name}」间距 gap=${n.gap.toStringAsFixed(1)} 偏离 4dp 网格',
      nodeId: n.id,
      nodeName: n.name,
      fix: '改为 4/8/12/16/18/24 等刻度（AppSpace 体系）',
    ));
  }
  if (!_goodGaps.contains(n.padding) && n.padding > 0) {
    out.add(UiIssue(
      severity: UiIssueSeverity.info,
      message: '「${n.name}」内边距 padding=${n.padding.toStringAsFixed(1)} 偏离 4dp 网格',
      nodeId: n.id,
      nodeName: n.name,
      fix: '改为 AppSpace 刻度（md=14 / lg=18 / xl=36）',
    ));
  }

  // 4. 自由定位重叠。
  if (n.x != null && n.y != null) {
    final double w = n.width ?? 80;
    final double h = n.height ?? 40;
    root.walk((UiNode o) {
      if (o == n || o.x == null || o.y == null) return;
      final double ow = o.width ?? 80;
      final double oh = o.height ?? 40;
      final bool overlap = n.x! < o.x! + ow && n.x! + w > o.x! && n.y! < o.y! + oh && n.y! + h > o.y!;
      if (overlap) {
        out.add(UiIssue(
          severity: UiIssueSeverity.warning,
          message: '「${n.name}」与「${o.name}」重叠',
          nodeId: n.id,
          nodeName: n.name,
          fix: '拖开两个节点，或用 Flex 布局替代自由定位',
        ));
      }
    });
  }

  // 5. 空容器。
  if (n.type == UiNodeType.container && n.children.isEmpty && n.width == null && n.height == null) {
    out.add(UiIssue(
      severity: UiIssueSeverity.warning,
      message: '「${n.name}」是空容器（无子节点且无显式尺寸）',
      nodeId: n.id,
      nodeName: n.name,
      fix: '拖入子节点，或删除该容器',
    ));
  }

  // 6. 按钮无文本且无图标。
  if (n.type == UiNodeType.button && n.text.isEmpty && (n.icon == null || n.icon!.isEmpty)) {
    out.add(UiIssue(
      severity: UiIssueSeverity.warning,
      message: '「${n.name}」按钮没有文本也没有图标',
      nodeId: n.id,
      nodeName: n.name,
      fix: '添加 label 或 icon（可访问性）',
    ));
  }

  // 7. 字号过小。
  if ((n.type == UiNodeType.text || n.type == UiNodeType.button) && n.fontSize < 10) {
    out.add(UiIssue(
      severity: UiIssueSeverity.warning,
      message: '「${n.name}」字号 ${n.fontSize.toStringAsFixed(1)} 过小（<10）',
      nodeId: n.id,
      nodeName: n.name,
      fix: '正文建议 ≥14（AppTextStyles.body）',
    ));
  }

  // 8. 节点名缺失 / 默认占位名。
  if (n.name.isEmpty || n.name == n.id) {
    out.add(UiIssue(
      severity: UiIssueSeverity.info,
      message: '节点「${n.id}」没有可读名称',
      nodeId: n.id,
      nodeName: n.name,
      fix: '在属性面板为节点命名（便于定位与导出）',
    ));
  }

  return out;
}

/// 估算子节点宽度（溢出检查用；文本按字号×字符数估算）。
double _estimateWidth(UiNode c, UiNode parent) {
  switch (c.type) {
    case UiNodeType.text:
      return math.min(c.text.length * c.fontSize * 0.62, 240);
    case UiNodeType.icon:
      return c.iconSize + 4;
    case UiNodeType.button:
      final double w = c.text.isNotEmpty ? c.text.length * c.fontSize * 0.62 + 40 : 48;
      return math.min(w, 280);
    case UiNodeType.spacer:
      return c.width ?? 0;
    case UiNodeType.container:
      if (c.width != null) return c.width!;
      double inner = 0;
      for (final UiNode cc in c.children) {
        inner += _estimateWidth(cc, c) + c.gap;
      }
      return math.min(inner - c.gap + c.padding * 2, 300);
  }
}
