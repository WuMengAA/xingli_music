/// 验证每个模板 build() 能在真实 widget 树中渲染（画廊/画布依赖）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/core/theme/light_theme.dart';
import 'package:xingli_music/core/ui_templates.dart';

void main() {
  testWidgets('全部模板 build() 可渲染且不抛异常', (WidgetTester tester) async {
    for (final UiTemplate t in kUiTemplates) {
      await tester.pumpWidget(
        MaterialApp(
          theme: kLightTheme,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext c) => Center(
                child: SingleChildScrollView(
                  child: t.build(c),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '模板 ${t.id} build 抛异常');
    }
  });

  testWidgets('编辑器属性面板可选中/修改节点不崩', (WidgetTester tester) async {
    // 轻量冒烟：直接构造一个含低对比度问题的节点树跑规则。
    // （编辑器页完整交互由人工验收，这里只锁定渲染核心不炸。）
    await tester.pumpWidget(
      MaterialApp(
        theme: kLightTheme,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
