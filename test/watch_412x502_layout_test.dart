import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/app.dart';
import 'package:xingli_music/providers/color_memory/color_memory_providers.dart';
import 'package:xingli_music/providers/explore/experiment_providers.dart';
import 'package:xingli_music/providers/library/library_view_providers.dart';
import 'package:xingli_music/providers/shell/shell_providers.dart';

/// Wear OS 手表 412×502 小屏布局诊断。
///
/// 1. 逐屏 pump，收集 RenderFlex 溢出报错并定位到源码行；
/// 2. 扫描可点击控件实际热区，报告 < 44dp 的控件及其 creator chain。
void main() {
  const Size kWatch = Size(412, 502);

  List<String> overflowErrors = <String>[];

  Future<ProviderContainer> pumpWatch(WidgetTester tester) async {
    tester.view.physicalSize = kWatch;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final void Function(FlutterErrorDetails)? original = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final String msg = details.exceptionAsString();
      if (msg.contains('overflowed')) {
        final String full = details.toString();
        final RegExp re = RegExp(r'error-causing widget was:\s*\n\s*(\S+)');
        final Match? m = re.firstMatch(full);
        overflowErrors.add('$msg  ←  ${m?.group(1) ?? '?'}');
      }
    };
    addTearDown(() => FlutterError.onError = original);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[prefsProvider.overrideWithValue(prefs)],
        child: const StelarithMusicApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    return ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
  }

  Future<void> goToPage(
    WidgetTester tester,
    ProviderContainer c,
    int page,
  ) async {
    c.read(shellPageIndexProvider.notifier).state = page;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  const Map<int, String> pageNames = <int, String>{
    ShellPage.scene: '场景页',
    ShellPage.library: '曲库页',
    ShellPage.explore: '探索页',
    ShellPage.settings: '设置页',
    ShellPage.home: '首页',
  };

  void report(String scope) {
    if (overflowErrors.isEmpty) return;
    debugPrint('【$scope】');
    for (final String s in overflowErrors.toSet()) {
      debugPrint('  - $s');
    }
  }

  testWidgets('412×502 逐屏溢出扫描', (WidgetTester tester) async {
    final ProviderContainer c = await pumpWatch(tester);
    // 放行探索页同意闸门，让真正的实验列表参与扫描
    c.read(experimentConsentProvider.notifier).agree();

    debugPrint('\n===== 412×502 溢出报告 =====');
    for (final MapEntry<int, String> e in pageNames.entries) {
      overflowErrors = <String>[];
      await goToPage(tester, c, e.key);
      await tester.pump();
      report(e.value);
    }

    // 曲库页三种视图逐一扫描
    for (final LibraryViewStyle s in LibraryViewStyle.values) {
      overflowErrors = <String>[];
      await goToPage(tester, c, ShellPage.library);
      c.read(libraryViewStyleProvider.notifier).setStyle(s);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      report('曲库页 · ${s.name}');
    }
    debugPrint('===== 报告结束 =====\n');
  });

  testWidgets('412×502 热区扫描（<44dp）', (WidgetTester tester) async {
    final ProviderContainer c = await pumpWatch(tester);
    c.read(experimentConsentProvider.notifier).agree();

    debugPrint('\n===== 412×502 热区报告 =====');
    for (final MapEntry<int, String> e in pageNames.entries) {
      await goToPage(tester, c, e.key);

      final Set<String> small = <String>{};
      for (final Element el in find
          .byWidgetPredicate(
              (Widget w) => w is InkWell || w is IconButton || w is InkResponse)
          .evaluate()) {
        final RenderObject? ro = el.renderObject;
        if (ro is! RenderBox || !ro.hasSize) continue;
        final Size s = ro.size;
        if (s.isEmpty) continue;
        if (s.width < 44 || s.height < 44) {
          small.add(
            '${s.width.toStringAsFixed(1)}×${s.height.toStringAsFixed(1)}  '
            '${el.debugGetCreatorChain(4)}',
          );
        }
      }
      if (small.isNotEmpty) {
        debugPrint('【${e.value}】');
        for (final String s in small) {
          debugPrint('  - $s');
        }
      }
    }
    debugPrint('===== 报告结束 =====\n');
  });
}
