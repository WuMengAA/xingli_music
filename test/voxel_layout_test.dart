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

    // ③ R26h：视角切换收进右上角芯片列（顶部），不再是屏幕下半部大按钮。
    // 「UI 不挤在顶部一条」的回归保障 = ①占满全屏 + ④ D-pad 在下半部。
    // 这里验证顶栏芯片（菜单/相机/2.5D画布/更多）仍在屏幕顶部区域。
    final Finder chip = find.text('菜单');
    if (chip.evaluate().isNotEmpty) {
      expect(tester.getCenter(chip.first).dy, lessThan(screenH / 2),
          reason: '顶栏芯片应位于屏幕上半部（R26h 设计）');
    }

    // ④ 动作键（右下 2×2 攻击/放置/蹲/跳）与摇杆（左下）在屏幕下半部
    // （R26skel-b3：旧 D-pad 拆为独立动作键；左下方是 FP/TP 摇杆）。
    final Finder action = find.byIcon(Icons.flash_on_rounded);
    if (action.evaluate().isNotEmpty) {
      expect(tester.getCenter(action.first).dy, greaterThan(screenH / 2),
          reason: '动作键应位于屏幕下半部');
    }
    final Finder jump = find.byIcon(Icons.arrow_upward_rounded);
    if (jump.evaluate().isNotEmpty) {
      expect(tester.getCenter(jump.first).dy, greaterThan(screenH / 2),
          reason: '跳跃键应位于屏幕下半部');
    }
  });
}
