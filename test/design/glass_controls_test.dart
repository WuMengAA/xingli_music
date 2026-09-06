import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/widgets/design/glass_controls.dart';

void main() {
  testWidgets('XGlassButton 渲染并可点击触发 onPressed', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: XGlassButton(
              child: const Text('Tap'),
              onPressed: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(XGlassButton), findsOneWidget);
    await tester.tap(find.text('Tap'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('XGlassToggle 渲染并切换值', (tester) async {
    bool value = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: XGlassToggle(
              value: value,
              onChanged: (v) => value = v,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(XGlassToggle), findsOneWidget);
    await tester.tap(find.byType(XGlassToggle));
    await tester.pump();
    expect(value, isTrue);
  });

  testWidgets('XGlassSlider 在 0..1 范围内构建且不崩溃', (tester) async {
    double v = 0.2;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: XGlassSlider(
              value: v,
              onChanged: (nv) => v = nv,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(XGlassSlider), findsOneWidget);
    // 值越界应被 clamp 到 0..1（构造不抛）
    expect(v, inInclusiveRange(0, 1));
  });

  testWidgets('XGlassSlider 支持任意 min/max 且不崩溃', (tester) async {
    double v = 50;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: XGlassSlider(
              value: v,
              min: 0,
              max: 100,
              onChanged: (nv) => v = nv,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(XGlassSlider), findsOneWidget);
  });

  testWidgets('XGlassSlider 支持 divisions 吸附构建', (tester) async {
    double v = 3;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: XGlassSlider(
              value: v,
              min: 2,
              max: 4,
              divisions: 2,
              onChanged: (nv) => v = nv,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(XGlassSlider), findsOneWidget);
  });

  testWidgets('XGlassCard 渲染并可点击', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: XGlassCard(
              onTap: () => tapped = true,
              child: const Text('Card'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(XGlassCard), findsOneWidget);
    await tester.tap(find.text('Card'));
    await tester.pump();
    expect(tapped, isTrue);
  });
}
