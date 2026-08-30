import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_compat/liquid_glass_compat.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('组件 smoke', () {
    testWidgets('GlassCard 可渲染且包含子内容', (tester) async {
      await tester.pumpWidget(_wrap(const GlassCard(child: Text('hello'))));
      expect(find.text('hello'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('GlassButton 点击回调', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(GlassButton(
        child: const Text('go'),
        onPressed: () => taps++,
      )));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('GlassToggle 切换回调', (tester) async {
      var switched = false;
      await tester.pumpWidget(_wrap(GlassToggle(
        value: false,
        onChanged: (_) => switched = true,
      )));
      await tester.tap(find.byType(GlassToggle));
      await tester.pumpAndSettle();
      expect(switched, isTrue);
    });

    testWidgets('GlassSlider 变更回调', (tester) async {
      double? last;
      await tester.pumpWidget(_wrap(SizedBox(
        width: 240,
        child: GlassSlider(value: 0.5, onChanged: (v) => last = v),
      )));
      await tester.pumpAndSettle();
      expect(last, isNull);
    });

    testWidgets('GlassDock 渲染 N 个 tab', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 360,
        child: GlassDock(
          items: const [
            GlassDockItem(icon: Icons.home, selectedIcon: Icons.home, label: 'A'),
            GlassDockItem(icon: Icons.search, selectedIcon: Icons.search, label: 'B'),
            GlassDockItem(icon: Icons.person, selectedIcon: Icons.person, label: 'C'),
          ],
          selectedIndex: 0,
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('GlassScrollContainer 懒/非懒渲染项数一致', (tester) async {
      Widget build({required bool lazy}) {
        return _wrap(SizedBox(
          height: 300,
          child: GlassScrollContainer(
            itemCount: 5,
            lazy: lazy,
            itemBuilder: (_, i) => GlassCard(child: Text('item $i')),
          ),
        ));
      }

      await tester.pumpWidget(build(lazy: false));
      await tester.pumpAndSettle();
      expect(find.text('item 0'), findsOneWidget);

      await tester.pumpWidget(build(lazy: true));
      await tester.pumpAndSettle();
      expect(find.text('item 0'), findsOneWidget);
    });

    testWidgets('GlassProgressiveBlur 渲染 label', (tester) async {
      await tester.pumpWidget(_wrap(const SizedBox(
        width: 320,
        child: GlassProgressiveBlur(label: 'alpha-masked progressive blur'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('alpha-masked progressive blur'), findsOneWidget);
    });
  });
}