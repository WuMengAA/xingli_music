import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/app.dart';
import 'package:xingli_music/providers/color_memory/color_memory_providers.dart';

void main() {
  testWidgets('应用启动并渲染音乐空间主页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const StelarithMusicApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
