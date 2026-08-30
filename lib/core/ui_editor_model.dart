/// ════════════════════════════════════════════════════════════════════════
/// UI 编辑器 · 可编辑节点树模型（与模板库 / 纠错引擎共用）
/// ════════════════════════════════════════════════════════════════════════
///
/// 使命：把「界面」拆成一棵可编辑的 `UiNode` 树 —— 每个节点代表一个
/// 可拖拽、可改属性的 UI 元素。模板库（ui_templates.dart）提供「起步素材」
/// （把现有优质界面拆解成模板，模板可展开成节点树进编辑器），编辑器
/// （ui_editor_page.dart）负责「实时编辑 + 预览」，规则引擎
/// （ui_editor_rules.dart）负责「自动纠错」。
///
/// 设计哲学（与 settings_layout 一致）：数据驱动 —— 树可 JSON 序列化，
/// 可随资产分发，可被编辑器修改后固化。
library;

import 'dart:convert';

import 'package:flutter/material.dart'
    show Alignment, Color, IconData, Icons, LinearGradient, Offset;

/// 节点类型（决定渲染形态与可用属性）。
enum UiNodeType {
  /// 容器：可含子节点，有 layout/gap/padding/color/cornerRadius/border。
  container,

  /// 文本：text/fontSize/fontWeight/color。
  text,

  /// 按钮：text/icon/color/accent（点击态）。
  button,

  /// 图标：icon/color/size。
  icon,

  /// 占位间距：height。
  spacer,
}

/// 布局方向（容器用）。
enum UiLayout {
  horizontal,
  vertical,
  wrap,
}

/// 对齐（容器用，映射 primaryAxisAlignItems 语义）。
enum UiAlign {
  min,
  center,
  max,
  spaceBetween,
}

/// 一个可编辑 UI 节点。
class UiNode {
  UiNode({
    required this.id,
    required this.type,
    required this.name,
    this.layout = UiLayout.vertical,
    this.align = UiAlign.min,
    this.gap = 8,
    this.padding = 0,
    this.cornerRadius = 0,
    this.width,
    this.height,
    this.color,
    this.gradientStart,
    this.gradientEnd,
    this.gradientDirection = 'down',
    this.borderColor,
    this.accentColor,
    this.textColor,
    this.text = '',
    this.fontSize = 14,
    this.fontWeight = '400',
    this.icon,
    this.iconSize = 20,
    this.children = const <UiNode>[],
    this.x,
    this.y,
    // cl45：自由定位（root Stack 画布）、预览动画、可点击反馈。
    this.freePos = false,
    this.anim = 'none',
    this.tappable = false,
  });

  /// 全局唯一 id（编辑器选中/定位用；拖入时重新赋值新 id）。
  String id;

  final UiNodeType type;

  /// 显示名（资产面板 / 属性面板用）。
  String name;

  UiLayout layout;
  UiAlign align;
  double gap;
  double padding;
  double cornerRadius;

  /// 尺寸：null = 自适应内容。
  double? width;
  double? height;

  /// 填充色（容器/按钮背景）。
  String? color;

  /// 渐变起止色（非空即启用渐变填充，替代 color 作背景）。
  String? gradientStart;
  String? gradientEnd;

  /// 渐变方向：down / up / left / right / diagonal。
  String gradientDirection = 'down';

  /// 边框色。
  String? borderColor;

  /// 强调色（按钮底 / 图标底）。
  String? accentColor;

  /// 文本色。
  String? textColor;

  String text;
  double fontSize;
  String fontWeight;

  /// 图标名（Material Icons 的 codePoint 十六进制，如 'e145'=add）。
  String? icon;
  double iconSize;

  List<UiNode> children;

  /// 自由定位（画布用 Stack 定位）。
  double? x;
  double? y;

  /// cl45：自由定位模式（root 容器开 → 画布用 Stack + Positioned(x,y) 渲染）。
  bool freePos;

  /// cl45：预览动画：none / fade（淡入）/ scale（缩放）。
  String anim;

  /// cl45：可点击（预览里点击有高亮反馈，演示事件交互）。
  bool tappable;

  // ── 便利构造 ──────────────────────────────────────────

  static UiNode container(
    String id,
    String name, {
    UiLayout layout = UiLayout.vertical,
    double gap = 8,
    double padding = 0,
    double radius = 0,
    String? color,
    String? gradientStart,
    String? gradientEnd,
    String gradientDirection = 'down',
    String? border,
    List<UiNode> children = const <UiNode>[],
    double? width,
    double? height,
    UiAlign align = UiAlign.min,
  }) =>
      UiNode(
        id: id,
        type: UiNodeType.container,
        name: name,
        layout: layout,
        align: align,
        gap: gap,
        padding: padding,
        cornerRadius: radius,
        color: color,
        gradientStart: gradientStart,
        gradientEnd: gradientEnd,
        gradientDirection: gradientDirection,
        borderColor: border,
        children: children,
        width: width,
        height: height,
      );

  static UiNode txt(
    String id,
    String name,
    String content, {
    double size = 14,
    String weight = '400',
    String color = '#E8E8F2',
  }) =>
      UiNode(
        id: id,
        type: UiNodeType.text,
        name: name,
        text: content,
        fontSize: size,
        fontWeight: weight,
        textColor: color,
      );

  static UiNode button(
    String id,
    String name,
    String label, {
    String? icon,
    String accent = '#9B7BFF',
    String color = '#1C1C26',
    String? gradientStart,
    String? gradientEnd,
    String gradientDirection = 'down',
  }) =>
      UiNode(
        id: id,
        type: UiNodeType.button,
        name: name,
        text: label,
        icon: icon,
        accentColor: accent,
        color: color,
        gradientStart: gradientStart,
        gradientEnd: gradientEnd,
        gradientDirection: gradientDirection,
        cornerRadius: 18,
        padding: 12,
      );

  static UiNode iconNode(
    String id,
    String name,
    String icon, {
    String color = '#F2F2F7',
    double size = 20,
  }) =>
      UiNode(
        id: id,
        type: UiNodeType.icon,
        name: name,
        icon: icon,
        textColor: color,
        iconSize: size,
      );

  static UiNode spacer(String id, String name, {double height = 12}) =>
      UiNode(
        id: id,
        type: UiNodeType.spacer,
        name: name,
        height: height,
      );

  // ── 树遍历 ──────────────────────────────────────────

  /// 深度优先遍历（含自身）。
  void walk(void Function(UiNode) fn) {
    fn(this);
    for (final UiNode c in children) {
      c.walk(fn);
    }
  }

  /// 按 id 找节点（含自身）。
  UiNode? find(String nodeId) {
    if (id == nodeId) return this;
    for (final UiNode c in children) {
      final UiNode? r = c.find(nodeId);
      if (r != null) return r;
    }
    return null;
  }

  /// 返回替换后的新树（不可变式更新，编辑器 setState 用）。
  ///
  /// cl45：改为**递归** + clone 实现——原实现只替换直接子节点、且手工重建
  /// 会丢掉新增字段（深层选中改属性失效 / 字段丢失的潜伏 bug）。
  UiNode replace(String nodeId, UiNode newNode) {
    if (id == nodeId) return newNode;
    final UiNode c = clone();
    c.children = <UiNode>[
      for (final UiNode child in children)
        child.id == nodeId ? newNode : child.replace(nodeId, newNode),
    ];
    return c;
  }

  /// cl45：深拷贝并**重写整棵子树的所有 id**（粘贴用，保证全局唯一）。
  UiNode remapIds() {
    final UiNode c = clone();
    c.id = 'n${DateTime.now().microsecondsSinceEpoch}_${c.hashCode.abs()}';
    if (c.children.isNotEmpty) {
      c.children = c.children.map((UiNode e) => e.remapIds()).toList();
    }
    return c;
  }

  // ── 序列化 ──────────────────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'name': name,
        'layout': layout.name,
        'align': align.name,
        'gap': gap,
        'padding': padding,
        'cornerRadius': cornerRadius,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (color != null) 'color': color,
        if (gradientStart != null) 'gradientStart': gradientStart,
        if (gradientEnd != null) 'gradientEnd': gradientEnd,
        if (gradientDirection != 'down') 'gradientDirection': gradientDirection,
        if (borderColor != null) 'borderColor': borderColor,
        if (accentColor != null) 'accentColor': accentColor,
        if (textColor != null) 'textColor': textColor,
        if (text.isNotEmpty) 'text': text,
        'fontSize': fontSize,
        'fontWeight': fontWeight,
        if (icon != null) 'icon': icon,
        'iconSize': iconSize,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (freePos) 'freePos': true,
        if (anim != 'none') 'anim': anim,
        if (tappable) 'tappable': true,
        if (children.isNotEmpty)
          'children': children.map((UiNode n) => n.toJson()).toList(),
      };

  static UiNode fromJson(Map<String, dynamic> j) => UiNode(
        id: j['id'] as String,
        type: UiNodeType.values.firstWhere(
          (UiNodeType t) => t.name == j['type'],
          orElse: () => UiNodeType.container,
        ),
        name: j['name'] as String? ?? j['id'] as String,
        layout: UiLayout.values.firstWhere(
          (UiLayout t) => t.name == j['layout'],
          orElse: () => UiLayout.vertical,
        ),
        align: UiAlign.values.firstWhere(
          (UiAlign t) => t.name == j['align'],
          orElse: () => UiAlign.min,
        ),
        gap: (j['gap'] as num?)?.toDouble() ?? 8,
        padding: (j['padding'] as num?)?.toDouble() ?? 0,
        cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 0,
        width: (j['width'] as num?)?.toDouble(),
        height: (j['height'] as num?)?.toDouble(),
        color: j['color'] as String?,
        gradientStart: j['gradientStart'] as String?,
        gradientEnd: j['gradientEnd'] as String?,
        gradientDirection: j['gradientDirection'] as String? ?? 'down',
        borderColor: j['borderColor'] as String?,
        accentColor: j['accentColor'] as String?,
        textColor: j['textColor'] as String?,
        text: j['text'] as String? ?? '',
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 14,
        fontWeight: j['fontWeight'] as String? ?? '400',
        icon: j['icon'] as String?,
        iconSize: (j['iconSize'] as num?)?.toDouble() ?? 20,
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        freePos: j['freePos'] == true,
        anim: j['anim'] as String? ?? 'none',
        tappable: j['tappable'] == true,
        children: (j['children'] as List<dynamic>? ?? const <dynamic>[])
            .map((dynamic e) => UiNode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String toJsonString() => const JsonEncoder.withIndent('  ')
      .convert(toJson());

  /// 深拷贝（编辑时隔离，避免共享同一实例树）。
  UiNode clone() => fromJson(toJson());
}

/// 解析十六进制颜色字符串（'#RRGGBB' / 'RRGGBB'）为 int 颜色。
/// 非法输入返回 null（上层回退默认色）。
int? parseHexColor(String? hex) {
  if (hex == null) return null;
  String h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final int? v = int.tryParse(h, radix: 16);
  return v;
}

/// 模板用到的 MaterialIcons 十六进制 codePoint → const 图标。
///
/// 渲染字形由 codePoint 决定（fontFamily: MaterialIcons），与字段名无关；
/// 使用 const 字段可让 release 图标树摇（tree-shake-icons）正常工作——
/// 禁止运行时构造非 const IconData。未收录的 codePoint 交由上层回退图标。
const Map<String, IconData> kTemplateIconByHex = <String, IconData>{
  'e036': Icons.nine_mp,
  'e042': Icons.account_box,
  'e050': Icons.add_circle_outline,
  'e05e': Icons.add_to_photos,
  'e145': Icons.cast_connected,
  'e147': Icons.catching_pokemon,
  'e161': Icons.child_friendly,
  'e242': Icons.event_seat,
  'e251': Icons.extension_off,
  'e2c7': Icons.forward_5,
  'e567': Icons.search,
  'e5d2': Icons.sort,
  'e5d8': Icons.spa,
  'e7c4': Icons.backup_sharp,
  'e80b': Icons.brightness_low_sharp,
  'e80e': Icons.browser_not_supported_sharp,
  'e86c': Icons.cloud_circle_sharp,
  'e896': Icons.coronavirus_sharp,
  'e8b8': Icons.delete_sharp,
  'e8e0': Icons.disabled_by_default_sharp,
  'e8e8': Icons.do_not_disturb_off_sharp,
  'e8f4': Icons.done_outline_sharp,
};

/// 解析 Material 图标名（十六进制 codePoint，如 'e145'）。返回 IconData 或 null。
IconData? resolveIcon(String? name, {double? size}) {
  if (name == null || name.isEmpty) return null;
  return kTemplateIconByHex[name.toLowerCase()];
}

/// 编辑器画布坐标（保留给自由定位节点）。
class UiCanvasPoint {
  const UiCanvasPoint(this.x, this.y);
  final double x;
  final double y;
  Offset toOffset() => Offset(x, y);
}

// ─────────────────────────────────────────────────────────────────────────
// 渐变
// ─────────────────────────────────────────────────────────────────────────

/// 取节点的线性渐变（起止色都有效才返回）；否则 null。
LinearGradient? gradientOf(UiNode n) {
  final int? s = parseHexColor(n.gradientStart);
  final int? e = parseHexColor(n.gradientEnd);
  if (s == null || e == null) return null;
  final (Alignment, Alignment) dir = switch (n.gradientDirection) {
    'up' => (Alignment.bottomCenter, Alignment.topCenter),
    'left' => (Alignment.centerRight, Alignment.centerLeft),
    'right' => (Alignment.centerLeft, Alignment.centerRight),
    'diagonal' => (Alignment.topLeft, Alignment.bottomRight),
    _ => (Alignment.topCenter, Alignment.bottomCenter),
  };
  return LinearGradient(
    begin: dir.$1,
    end: dir.$2,
    colors: <Color>[Color(s), Color(e)],
  );
}

// ─────────────────────────────────────────────────────────────────────────
// 预设备色方案（UI 编辑器「预设配色」）
// ─────────────────────────────────────────────────────────────────────────

/// 一套预设备色方案：语义角色 → 色值（可一键套用到节点树）。
class UiPalette {
  const UiPalette({
    required this.id,
    required this.name,
    required this.bg,
    required this.surface,
    required this.accent,
    required this.accentSoft,
    required this.text,
    required this.textMuted,
  });

  final String id;
  final String name;

  /// 画布/页面底色。
  final String bg;

  /// 容器/卡片表面色。
  final String surface;

  /// 主强调色（按钮/发光/选中）。
  final String accent;

  /// 强调淡底（chip/高亮背景）。
  final String accentSoft;

  /// 主文本色。
  final String text;

  /// 次要文本色。
  final String textMuted;
}

/// 内置预设备色方案（编辑器中一键套用）。
const List<UiPalette> kUiPalettes = <UiPalette>[
  UiPalette(
    id: 'violet',
    name: '紫罗兰',
    bg: '#12121A',
    surface: '#1E1E2C',
    accent: '#9B7BFF',
    accentSoft: '#2A2440',
    text: '#F2F2F7',
    textMuted: '#B8B8C8',
  ),
  UiPalette(
    id: 'ocean',
    name: '深海',
    bg: '#0C1626',
    surface: '#14233B',
    accent: '#3FA9F5',
    accentSoft: '#1B3350',
    text: '#EAF4FF',
    textMuted: '#9DB8D4',
  ),
  UiPalette(
    id: 'forest',
    name: '森林',
    bg: '#0F1A12',
    surface: '#18291B',
    accent: '#4CD964',
    accentSoft: '#1F3A26',
    text: '#EEF7EF',
    textMuted: '#A8C4AD',
  ),
  UiPalette(
    id: 'sunset',
    name: '日落',
    bg: '#1E1216',
    surface: '#2E1A20',
    accent: '#FF7A6E',
    accentSoft: '#45222A',
    text: '#FFF0EC',
    textMuted: '#D9B4AD',
  ),
  UiPalette(
    id: 'lava',
    name: '熔岩',
    bg: '#1C0F0A',
    surface: '#2C180E',
    accent: '#FF9F45',
    accentSoft: '#452515',
    text: '#FFF3E4',
    textMuted: '#DBB694',
  ),
  UiPalette(
    id: 'aurora',
    name: '极光',
    bg: '#0C1418',
    surface: '#15242A',
    accent: '#5EEAD4',
    accentSoft: '#1C3A3C',
    text: '#EAFBF8',
    textMuted: '#9CC9C2',
  ),
];

/// 按语义角色给单个节点换色（返回新节点；不可变）。
UiNode _restyle(UiNode n, UiPalette p) {
  final UiNode c = n.clone();
  switch (n.type) {
    case UiNodeType.container:
      // 有渐变 → 保持渐变角色；否则表面色。
      if (c.gradientStart != null || c.gradientEnd != null) {
        c.gradientStart = p.surface;
        c.gradientEnd = p.bg;
      } else {
        c.color = p.surface;
      }
    case UiNodeType.button:
      c.accentColor = p.accent;
    case UiNodeType.text:
      c.textColor = p.text;
    case UiNodeType.icon:
      c.textColor = p.textMuted;
    case UiNodeType.spacer:
      break;
  }
  return c;
}

/// 一键套用预设备色到节点树。
///
/// `nodeId` 非空 → 只重设该节点子树；null → 整个画布根（root 背景用 [UiPalette.bg]）。
UiNode applyPalette(UiNode root, UiPalette p, {String? nodeId}) {
  final UiNode? target = nodeId == null ? root : root.find(nodeId);
  if (target == null) return root;

  UiNode rebuild(UiNode n) {
    UiNode out = _restyle(n, p);
    // 根容器：底色用 bg（页面级）。
    if (identical(n, target) && n.type == UiNodeType.container && nodeId == null) {
      out = out.clone()
        ..color = p.bg
        ..gradientStart = null
        ..gradientEnd = null;
    }
    if (out.children.isNotEmpty) {
      out = out.clone();
      out.children = out.children.map(rebuild).toList();
    }
    return out;
  }

  return nodeId == null ? rebuild(root) : root.replace(nodeId, rebuild(target));
}

// ─────────────────────────────────────────────────────────────────────────
// 一体成型全局预设（配色 + 圆角 + 间距 + 字号 一次到位；细节去属性面板）
// ─────────────────────────────────────────────────────────────────────────

/// 一体成型预设：语义配色 + 圆角档 + 间距档 + 字号档。
class UiPreset {
  const UiPreset({
    required this.id,
    required this.name,
    required this.palette,
    required this.radius,
    required this.gap,
    required this.padding,
    required this.fontSize,
    required this.description,
  });

  final String id;
  final String name;
  final UiPalette palette;

  /// 统一圆角（容器/按钮）。
  final double radius;

  /// 统一间距 gap。
  final double gap;

  /// 统一内边距 padding。
  final double padding;

  /// 统一正文字号（文本/按钮）。
  final double fontSize;

  final String description;
}

/// 内置一体成型预设。
final List<UiPreset> kUiPresets = <UiPreset>[
  UiPreset(
    id: 'violet_standard',
    name: '紫罗兰·标准',
    palette: kUiPalettes[0],
    radius: 18,
    gap: 12,
    padding: 14,
    fontSize: 14,
    description: '默认观感：紫罗兰配色 + 标准圆角/间距',
  ),
  UiPreset(
    id: 'ocean_compact',
    name: '深海·紧凑',
    palette: kUiPalettes[1],
    radius: 10,
    gap: 8,
    padding: 10,
    fontSize: 12,
    description: '信息密集：深海配色 + 小圆角/紧凑间距',
  ),
  UiPreset(
    id: 'aurora_spacious',
    name: '极光·宽松',
    palette: kUiPalettes[5],
    radius: 24,
    gap: 16,
    padding: 18,
    fontSize: 15,
    description: '呼吸感：极光配色 + 大圆角/宽松间距',
  ),
  UiPreset(
    id: 'lava_round',
    name: '熔岩·圆润',
    palette: kUiPalettes[4],
    radius: 28,
    gap: 14,
    padding: 16,
    fontSize: 16,
    description: '温暖醒目：熔岩配色 + 特大圆角',
  ),
];

/// 把一体成型预设套到节点树（配色 + 圆角 + 间距 + 字号）。
///
/// `nodeId` 非空 → 只套该节点子树；null → 整个画布。
UiNode applyPreset(UiNode root, UiPreset p, {String? nodeId}) {
  final UiNode colored = applyPalette(root, p.palette, nodeId: nodeId);
  final UiNode? target = nodeId == null ? colored : colored.find(nodeId);
  if (target == null) return colored;

  UiNode restyle(UiNode n) {
    final UiNode c = n.clone();
    if (c.type == UiNodeType.container) {
      c.cornerRadius = p.radius;
      c.gap = p.gap;
      c.padding = c.padding > 0 ? p.padding : c.padding;
    }
    if (c.type == UiNodeType.button) {
      c.cornerRadius = p.radius;
      c.fontSize = p.fontSize;
      c.padding = p.padding;
    }
    if (c.type == UiNodeType.text) {
      c.fontSize = p.fontSize;
    }
    if (c.children.isNotEmpty) {
      c.children = c.children.map(restyle).toList();
    }
    return c;
  }

  if (nodeId == null) return restyle(colored);
  return colored.replace(nodeId, restyle(target));
}

// ─────────────────────────────────────────────────────────────────────────
// 节点移动（画布内拖拽）
// ─────────────────────────────────────────────────────────────────────────

/// 把 [nodeId] 从树中移除 → 插入 [targetContainerId] 的 children 末尾。
/// 目标容器不存在 / 节点是目标容器自身 → 返回原树。
UiNode moveNode(UiNode root, String nodeId, String targetContainerId) {
  if (nodeId == targetContainerId) return root;
  final UiNode? node = root.find(nodeId);
  final UiNode? target = root.find(targetContainerId);
  if (node == null || target == null) return root;
  if (target.type != UiNodeType.container) return root;

  // 先移除 node。
  UiNode remove(UiNode n) {
    final UiNode c = n.clone();
    c.children = c.children
        .where((UiNode x) => x.id != nodeId)
        .map(remove)
        .toList();
    return c;
  }

  final UiNode removed = remove(root);
  // 目标容器被移除后的新 id 节点上追加 node。
  UiNode append(UiNode n) {
    final UiNode c = n.clone();
    if (c.id == targetContainerId) {
      c.children = <UiNode>[...c.children, node];
    } else {
      c.children = c.children.map(append).toList();
    }
    return c;
  }

  return append(removed);
}

/// 在 [parentId] 容器的 children 内移动 [childId] 到 [newIndex]（0=最前）。
UiNode reorderChild(UiNode root, String parentId, String childId, int newIndex) {
  UiNode moveIn(UiNode n) {
    if (n.id == parentId && n.type == UiNodeType.container) {
      final List<UiNode> kids = <UiNode>[
        for (final UiNode c in n.children)
          if (c.id != childId) c,
      ];
      final UiNode? child = n.children
          .where((UiNode c) => c.id == childId)
          .firstOrNull;
      if (child == null) return n;
      final int idx = newIndex.clamp(0, kids.length);
      kids.insert(idx, child);
      final UiNode c = n.clone();
      c.children = kids;
      return c;
    }
    final UiNode c = n.clone();
    c.children = c.children.map(moveIn).toList();
    return c;
  }

  return moveIn(root);
}
