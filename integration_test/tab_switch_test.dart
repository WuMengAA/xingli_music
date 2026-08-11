import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/app.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';

/// 复现用户报告：从「设置」切回「场景」崩溃。
///
/// 注意：场景页的 VoxelSceneBackground 有常驻 Ticker（每帧重绘），
/// 因此全程禁用 pumpAndSettle，改用显式 pump 推进时间。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('设置↔场景 tab 反复切换 5 次不崩溃', (WidgetTester tester) async {
    // 已知噪音：启动时插件 EventChannel 推一条编码损坏消息（FormatException），
    // 真实 app 由全局捕获吞掉，测试环境显式过滤。
    final void Function(FlutterErrorDetails)? oldOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('FormatException')) return;
      oldOnError?.call(details);
    };

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          prefsProvider.overrideWithValue(prefs),
        ],
        child: const StelarithMusicApp(),
      ),
    );
    // 启动帧 + 首帧渲染稳定
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    for (int i = 0; i < 5; i++) {
      // ① 切到设置 tab（Dock 第 4 项）
      await tester.tap(find.text('设置').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // ② 切回场景 tab（Dock 第 1 项）
      await tester.tap(find.text('场景').first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    // 存活判定：Dock 仍在
    expect(find.text('设置'), findsWidgets,
        reason: '5 轮 tab 切换后 app 存活');
  });
}
