/// UI 模板库 + 节点树 + 纠错引擎测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/core/ui_editor_model.dart';
import 'package:xingli_music/core/ui_editor_rules.dart';
import 'package:xingli_music/core/ui_templates.dart';

void main() {
  group('UiNode 节点树', () {
    test('JSON 序列化往返一致', () {
      final UiNode root = UiNode.container(
        'root',
        '测试',
        layout: UiLayout.vertical,
        gap: 12,
        padding: 16,
        color: '#1C1C26',
        radius: 24,
        children: <UiNode>[
          UiNode.txt('t1', '标题', '你好', size: 18, weight: '700', color: '#F2F2F7'),
          UiNode.button('b1', '按钮', '点击', icon: 'e145', accent: '#9B7BFF'),
          UiNode.container(
            'sub',
            '子容器',
            layout: UiLayout.horizontal,
            children: <UiNode>[
              UiNode.iconNode('ic', '图标', 'e8b8', color: '#F2F2F7'),
            ],
          ),
        ],
      );
      final UiNode back = UiNode.fromJson(root.toJson());
      expect(back.id, 'root');
      expect(back.children.length, 3);
      expect(back.children[1].type, UiNodeType.button);
      expect(back.find('ic')?.icon, 'e8b8');
      expect(back.toJsonString(), root.toJsonString());
    });

    test('find / replace / clone', () {
      final UiNode root = UiNode.container('root', '根', children: <UiNode>[
        UiNode.txt('a', 'A', '文本'),
      ]);
      expect(root.find('a')?.text, '文本');
      final UiNode replaced = root.replace('a', UiNode.txt('a', 'A', '改后'));
      expect(replaced.find('a')?.text, '改后');
      expect(root.find('a')?.text, '文本', reason: '原树不可变');
      final UiNode cloned = root.clone();
      expect(cloned.toJsonString(), root.toJsonString());
    });

    test('渐变字段序列化往返 + gradientOf', () {
      final UiNode root = UiNode.container(
        'root',
        '渐变容器',
        gradientStart: '#2A2440',
        gradientEnd: '#151D2E',
        gradientDirection: 'diagonal',
      );
      final UiNode back = UiNode.fromJson(root.toJson());
      expect(back.gradientStart, '#2A2440');
      expect(back.gradientEnd, '#151D2E');
      expect(back.gradientDirection, 'diagonal');
      expect(gradientOf(back), isNotNull);
      // 无效渐变（只填一端）→ null。
      final UiNode half = UiNode.container('r2', '半渐变', gradientStart: '#2A2440');
      expect(gradientOf(half), isNull);
    });

    test('applyPalette 一键换色（整树 + 子树）', () {
      final UiNode root = UiNode.container(
        'root',
        '根',
        color: '#111111',
        children: <UiNode>[
          UiNode.container('c1', '容器', color: '#222222', children: <UiNode>[
            UiNode.txt('t1', '文本', 'hi', color: '#333333'),
            UiNode.button('b1', '按钮', '点', accent: '#444444'),
          ]),
        ],
      );
      // 整树套用海洋配色。
      final UiNode ocean = applyPalette(root, kUiPalettes[1]);
      expect(ocean.color, '#0C1626', reason: '根容器用 bg');
      expect(ocean.find('c1')?.color, '#14233B', reason: '容器用 surface');
      expect(ocean.find('t1')?.textColor, '#EAF4FF', reason: '文本用 text');
      expect(ocean.find('b1')?.accentColor, '#3FA9F5', reason: '按钮用 accent');
      // 子树套用（仅改 c1 子树）。
      final UiNode sub = applyPalette(root, kUiPalettes[2], nodeId: 'c1');
      expect(sub.color, '#111111', reason: '根不受影响');
      expect(sub.find('c1')?.color, '#18291B');
      expect(sub.find('t1')?.textColor, '#EEF7EF');
    });

    test('applyPreset 一体成型（配色+圆角+间距+字号）', () {
      final UiNode root = UiNode.container(
        'root',
        '根',
        color: '#111111',
        radius: 0,
        gap: 0,
        children: <UiNode>[
          UiNode.container('c1', '容器', color: '#222222', radius: 0, gap: 0, children: <UiNode>[
            UiNode.txt('t1', '文本', 'hi', color: '#333333', size: 20),
            UiNode.button('b1', '按钮', '点', accent: '#444444'),
          ]),
        ],
      );
      final UiNode preset = applyPreset(root, kUiPresets[1]); // 深海·紧凑
      expect(preset.color, '#0C1626');
      expect(preset.cornerRadius, 10);
      expect(preset.gap, 8);
      expect(preset.find('c1')?.cornerRadius, 10);
      expect(preset.find('c1')?.gap, 8);
      expect(preset.find('t1')?.fontSize, 12, reason: '文本字号统一');
      expect(preset.find('b1')?.accentColor, '#3FA9F5');
      expect(preset.find('b1')?.fontSize, 12);
    });

    test('moveNode 跨容器移动 + 目标自身不变', () {
      final UiNode root = UiNode.container(
        'root',
        '根',
        children: <UiNode>[
          UiNode.container('a', 'A', children: <UiNode>[
            UiNode.txt('t1', 'T1', 'hi'),
          ]),
          UiNode.container('b', 'B', children: <UiNode>[
            UiNode.txt('t2', 'T2', 'yo'),
          ]),
        ],
      );
      // t1 → b。
      final UiNode moved = moveNode(root, 't1', 'b');
      expect(moved.find('a')?.children.any((UiNode c) => c.id == 't1'), isFalse);
      expect(moved.find('b')?.children.any((UiNode c) => c.id == 't1'), isTrue);
      // 目标自身 → 原树。
      expect(moveNode(root, 't1', 't1').toJsonString(), root.toJsonString());
    });

    test('reorderChild 容器内排序', () {
      final UiNode root = UiNode.container(
        'root',
        '根',
        children: <UiNode>[
          UiNode.txt('a', 'A', 'a'),
          UiNode.txt('b', 'B', 'b'),
          UiNode.txt('c', 'C', 'c'),
        ],
      );
      final UiNode re = reorderChild(root, 'root', 'c', 0);
      expect(re.children.first.id, 'c');
      expect(re.children.map((UiNode n) => n.id).toList(), <String>['c', 'a', 'b']);
    });
  });

  group('纠错规则引擎', () {
    test('低对比度文本报错（WCAG AA）', () {
      final UiNode root = UiNode.container('root', '根', color: '#FFFFFF', children: <UiNode>[
        UiNode.txt('a', '文本', '白色底上的白字', color: '#FFFFFF'),
      ]);
      final List<UiIssue> issues = runUiRules(root);
      expect(issues.any((UiIssue i) => i.message.contains('对比度')), isTrue);
    });

    test('高对比度文本不报错', () {
      final UiNode root = UiNode.container('root', '根', color: '#121218', children: <UiNode>[
        UiNode.txt('a', '文本', '深底白字', color: '#F2F2F7'),
      ]);
      final List<UiIssue> issues = runUiRules(root);
      expect(issues.any((UiIssue i) => i.message.contains('对比度')), isFalse);
    });

    test('渐变容器上的低对比度文本报错（平均色背景）', () {
      final UiNode root = UiNode.container(
        'root',
        '渐变容器',
        gradientStart: '#FFFFFF',
        gradientEnd: '#FFFFFF',
        children: <UiNode>[
          UiNode.txt('a', '文本', '白渐变上的白字', color: '#FFFFFF'),
        ],
      );
      final List<UiIssue> issues = runUiRules(root);
      expect(issues.any((UiIssue i) => i.message.contains('对比度')), isTrue);
    });

    test('空容器警告', () {
      final UiNode root = UiNode.container('root', '根', children: <UiNode>[
        UiNode.container('empty', '空容器'),
      ]);
      final List<UiIssue> issues = runUiRules(root);
      expect(issues.any((UiIssue i) => i.message.contains('空容器')), isTrue);
    });

    test('按钮无文本无图标警告', () {
      final UiNode root = UiNode.container('root', '根', children: <UiNode>[
        UiNode.button('b', '按钮', ''),
      ]);
      final List<UiIssue> issues = runUiRules(root);
      expect(issues.any((UiIssue i) => i.message.contains('没有文本也没有图标')), isTrue);
    });

    test('间距偏离 4dp 网格提示', () {
      final UiNode root = UiNode.container('root', '根', gap: 7, children: <UiNode>[
        UiNode.txt('a', 'A', 'x'),
        UiNode.txt('b', 'B', 'y'),
      ]);
      final List<UiIssue> issues = runUiRules(root);
      expect(issues.any((UiIssue i) => i.message.contains('偏离 4dp 网格')), isTrue);
    });
  });

  group('UI 模板库', () {
    test('模板数量 ≥ 15，覆盖三分类', () {
      expect(kUiTemplates.length, greaterThanOrEqualTo(15));
      expect(
        kUiTemplates.map((UiTemplate t) => t.category).toSet(),
        containsAll(<UiTemplateCategory>[
          UiTemplateCategory.page,
          UiTemplateCategory.block,
          UiTemplateCategory.control,
        ]),
      );
    });

    test('每个模板 id 唯一且能生成节点树', () {
      final Set<String> ids = <String>{};
      for (final UiTemplate t in kUiTemplates) {
        expect(ids.add(t.id), isTrue, reason: '模板 id 重复: ${t.id}');
        final List<UiNode> nodes = t.nodes();
        expect(nodes, isNotEmpty, reason: '模板 ${t.id} 无节点树');
        expect(nodes.first.id, isNotEmpty);
      }
    });

    test('模板节点树可 JSON 序列化往返', () {
      for (final UiTemplate t in kUiTemplates) {
        final UiNode root = UiNode.container('root', t.name, children: t.nodes());
        final UiNode back = UiNode.fromJson(root.toJson());
        expect(back.children.length, t.nodes().length, reason: '模板 ${t.id}');
      }
    });
  });
}
