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
}
