/// R26 回归测试：3D 世界页视口修复。
///
/// 背景：`_viewport` 曾被声明为 `Size.zero` 且从未赋值 → `_onTick` 里
/// `_viewport.isEmpty` 恒真 → buildFrame 永不执行 → 帧恒为 empty，
/// 画面只剩天空+云（用户反馈「3D 渲染不出来」根因）。
///
/// 修复：build 用 LayoutBuilder 从实际布局约束写入 `_viewport`。
/// 本测试 pump 真实 3D 页并推进若干帧，验证渲染/勾子无异常。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/providers/storage/storage_providers.dart';
import '../lib/widgets/voxel/voxel_world_view3d.dart';

void main() {
  testWidgets('3D 世界页：推进多帧后无 paint/tick 异常', (tester) async {
    // 固定表面尺寸，保证布局约束为有限值（非测试环境默认 800x600 也无妨）。
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[prefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: VoxelWorld3DPage(),
        ),
      ),
    );

    // 推进多帧：让 ticker 跑 buildFrame、图集异步构建完成。
    for (int i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull,
        reason: '3D 世界页渲染/勾子出现异常（viewport 修复应保证 buildFrame 正常执行）');
  });

  testWidgets('进入生存模式后相机俯仰归位为水平（R26g 灰色滤镜修复）', (tester) async {
    // 背景：初始 overview 相机 pitch ≈ -78°（垂直俯视）；此前 _enterWorld 只改
    // position 不动 pitch → 第一人称持续朝下看满屏灰地面（用户反馈「生存模式
    // 被套上灰色滤镜、无法关闭」）。修复：进入第一人称时归位 pitch = -0.15。
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[prefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          // H1r2：autoStart 直入生存（主菜单已独立成页，世界内不再有模式菜单）。
          home: VoxelWorld3DPage(autoStart: true, survival: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final dynamic viewState = tester.state(find.byType(VoxelWorldView3D));
    final double pitchBefore = viewState.debugCameraPitch as double;
    // R26m：初始相机已从 overview（-78° 垂直俯视）改为世界中心第一人称
    // （pitch -0.15）——去掉俯视预览，不再有「满屏灰地面」的前提。
    expect(pitchBefore, closeTo(-0.15, 0.01),
        reason: '初始应为第一人称水平略俯视（R26m 去 overview）');

    await tester.pump(const Duration(milliseconds: 100));

    final double pitchAfter = viewState.debugCameraPitch as double;
    expect(pitchAfter, closeTo(-0.15, 0.01),
        reason: '进入生存（第一人称）后俯仰保持水平略俯视，不朝下看地面');
    expect(tester.takeException(), isNull);
  });
}
