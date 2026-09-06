import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/providers/shell/shell_providers.dart';
import 'package:xingli_music/widgets/design/animated_background.dart';

void main() {
  testWidgets('AnimatedBackground 渲染并对页面切换作出反应（不崩溃）',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        shellPageIndexProvider.overrideWith((ref) => 0),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: AnimatedBackground()),
        ),
      ),
    );
    expect(find.byType(AnimatedBackground), findsOneWidget);

    // 切换到不同页面，背景应重新构建并平滑过渡，不抛异常。
    container.read(shellPageIndexProvider.notifier).state = 3;
    await tester.pumpAndSettle();

    expect(find.byType(AnimatedBackground), findsOneWidget);
  });
}
