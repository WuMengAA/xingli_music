/// OOBE 布局冒烟测试（R33 改版走查）：桌面/窄屏尺寸下逐页渲染，断言无布局溢出。
///
/// 覆盖 0 品牌 → 5 账号 共 6 页（第 6 页加载页会触发真实扫描/平台通道，
/// 不在 widget 测试内执行）。RenderFlex overflow 在 debug 模式会抛异常，
/// takeException() 即捕获。prefsProvider 需显式 override（shared_preferences mock）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/l10n/app_localizations.dart';
import 'package:xingli_music/pages/oobe/oobe_page.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';

Widget _app(SharedPreferences prefs) => ProviderScope(
      overrides: <Override>[prefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OobePage(),
      ),
    );

void main() {
  testWidgets('OOBE 改版：1280×800 下前 6 页渲染无溢出', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_app(prefs));
    // 等品牌页徽章动画首帧 + 条款拉取（网络挂起不阻塞，用兜底文案）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: '第 0 页 品牌页有异常');

    // 依次滑到第 1~5 页（品牌页徽章无限动画 → 不用 pumpAndSettle，固定时长 pump）。
    for (int i = 1; i <= 5; i++) {
      await tester.drag(find.byType(PageView), const Offset(-900, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull, reason: '第 $i 页有异常');
    }
  });

  testWidgets('OOBE 改版：窄屏 360×720 下品牌页无溢出', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(360, 720));
    await tester.pumpWidget(_app(prefs));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: '窄屏品牌页有异常');
  });
}