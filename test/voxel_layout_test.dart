/// 竖屏布局实测：VoxelWorld3DPage 必须占满全屏，控件各就各位
/// （R23c 用户反馈"UI 全挤在屏幕上方一条，下面 9/10 黑屏"）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xingli_music/core/theme/app_theme_colors.dart';
import 'package:xingli_music/core/theme/light_theme.dart';
import 'package:xingli_music/providers/storage/storage_providers.dart';
import 'package:xingli_music/widgets/voxel/voxel_world_view3d.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('VoxelWorld3DPage 竖屏：占满视口 + 控件位置正确', (tester) async {
    // 竖屏手机：1080×2400 @2.75x → 逻辑 392×873
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: kLightTheme.copyWith(
            extensions: <ThemeExtension<dynamic>>[AppThemeColors.light],
          ),
          home: const VoxelWorld3DPage(),
        ),
      ),
    );
    // 让 Ticker / 首帧稳定
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    final double screenH = 2400 / 2.75;
    final double screenW = 1080 / 2.75;

    // ① 页面必须占满全屏（排除"只给顶部一条空间"）
    final Size scaffold = tester.getSize(find.byType(Scaffold));
    expect(scaffold.width, closeTo(screenW, 1), reason: '页面宽度应占满全屏');
    expect(scaffold.height, closeTo(screenH, 1), reason: '页面高度应占满全屏');

    // ② 返回按钮在顶部
    final Finder back = find.byIcon(Icons.arrow_back);
    if (back.evaluate().isNotEmpty) {
      expect(tester.getCenter(back).dy, lessThan(120),
          reason: '返回按钮应在屏幕顶部');
    }

    // 调试：输出各层尺寸
    debugPrint('DBG Scaffold=${tester.getSize(find.byType(Scaffold))}');
    debugPrint(
        'DBG 3DView=${tester.getSize(find.byType(VoxelWorldView3D).first)}');
    for (final Element e in find.text('2.5D').evaluate()) {
      debugPrint('DBG 2.5D rect=${tester.getRect(find.byWidget(e.widget))}');
    }

    // ③ 视角切换 chips（2.5D/俯瞰/第一人称）在屏幕下半部
    final Finder chip = find.text('2.5D');
    if (chip.evaluate().isNotEmpty) {
      expect(tester.getCenter(chip.first).dy, greaterThan(screenH / 2),
          reason: '视角切换应位于屏幕下半部（不应挤在顶部）');
    }

    // ④ D-pad 在屏幕下半部
    final Finder dpad = find.byIcon(Icons.keyboard_arrow_up_rounded);
    if (dpad.evaluate().isNotEmpty) {
      expect(tester.getCenter(dpad.first).dy, greaterThan(screenH / 2),
          reason: 'D-pad 应位于屏幕下半部');
    }
  });
}
