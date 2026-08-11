/// 场景页弹层三选项逐个点击复现（Windows 真实桌面）。
///
/// 用户报告：点场景页右上角按钮 → 弹层显示后约 1 秒崩，且「开始打开→已关闭」
/// 打点齐全 → 怀疑崩溃发生在点了弹层选项（配色面板/沉浸画布/首页）之后。
/// 本测试三个用例各自点击一个选项并停留数秒，定位崩溃路径。
///
/// 运行：flutter test integration_test/scene_sheet_options_test.dart -d windows
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/app.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  // 忽略启动必现的 EventChannel FormatException 噪音（同 scene_glow_button_test）。
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('FormatException')) return;
    oldOnError?.call(details);
  };
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[prefsProvider.overrideWithValue(prefs)],
      child: const StelarithMusicApp(),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
}

/// 打开弹层，点击 [option]，停留 [hold] 秒观察是否崩溃。
Future<void> _tapOption(WidgetTester tester, String option,
    {Duration hold = const Duration(seconds: 3)}) async {
  final Finder glow = find.byIcon(Icons.grid_view_rounded);
  expect(glow, findsWidgets, reason: '场景页右上角按钮应存在');
  await tester.tap(glow.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 600));

  final Finder opt = find.text(option);
  expect(opt, findsWidgets, reason: '弹层应包含「$option」');
  await tester.tap(opt.first, warnIfMissed: false);
  await tester.pump(hold); // 停留数秒：若此处 native 崩，进程消失/测试失败
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('弹层 → 配色面板 3 秒不崩', (WidgetTester tester) async {
    await _pumpApp(tester);
    await _tapOption(tester, '配色面板');
  });

  testWidgets('弹层 → 沉浸画布 3 秒不崩', (WidgetTester tester) async {
    await _pumpApp(tester);
    await _tapOption(tester, '沉浸画布');
  });

  testWidgets('弹层 → 首页 3 秒不崩', (WidgetTester tester) async {
    await _pumpApp(tester);
    await _tapOption(tester, '首页');
  });
}
