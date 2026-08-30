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

    // MediaKitBackend 构造用 Future() 延后 ensureInitialized（避免首帧卡死），
    // 测试结束前推进时间让该定时器触发，否则报「Timer is still pending」。
    await tester.pump(const Duration(seconds: 1));
  });
}
