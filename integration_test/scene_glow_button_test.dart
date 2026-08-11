/// 场景页右上角按钮闪退复现（Windows 桌面真实运行）。
///
/// 目的：用户报告「点击场景页右上角第一个按钮（微光圆点）→ app 闪退且无日志」。
/// 本测试在真实 Windows 桌面窗口里启动 app、自动点击该按钮，判断：
///   - 若点击后 app 崩溃 → 测试进程异常退出/失败（可拿到崩溃信息）；
///   - 若未崩溃且出现打点日志 → 说明该按钮本身不崩，问题在别处（或已修复）。
///
/// 运行：flutter test integration_test/scene_glow_button_test.dart -d windows
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/app.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('点击场景页右上角按钮不崩溃', (WidgetTester tester) async {
    // 已知噪音：启动时 audioplayers/just_audio 的 EventChannel 事件流会推一条
    // 编码损坏的消息（FormatException，offset 234 固定）。真实 app 由 main()
    // 的全局捕获吞掉；测试环境没有全局捕获，这里显式忽略该噪音，聚焦点击。
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('FormatException')) return;
      oldOnError?.call(details);
    };

    // 真实 Windows 设备上获取 SharedPreferences 并注入（prefsProvider 必须 override）。
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          prefsProvider.overrideWithValue(prefs),
        ],
        child: const StelarithMusicApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // 找到右上角微光圆点（Icons.grid_view_rounded）
    final Finder glow = find.byIcon(Icons.grid_view_rounded);
    expect(glow, findsWidgets, reason: '场景页右上角按钮应存在');

    // 点击（真实命中测试：可能触发 native 渲染崩溃）
    await tester.tap(glow.first, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));

    // 弹层应出现「首页 / 沉浸画布 / 配色面板」三选项
    expect(find.text('沉浸画布'), findsWidgets,
        reason: '点击后应弹出入口选择层（未崩）');

    // 关闭弹层，收尾
    if (find.text('首页').evaluate().isNotEmpty) {
      await tester.tap(find.text('首页').first);
      await tester.pumpAndSettle();
    }
  });
}
