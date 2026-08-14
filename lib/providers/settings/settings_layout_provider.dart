/// ════════════════════════════════════════════════════════════════════════
/// 设置布局 Provider：加载 / 修改 / 持久化自定义布局
/// ════════════════════════════════════════════════════════════════════════
///
/// 数据流：
///   1. 冷启动读 `assets/settings_layout.json`（若打包了自定义资产）→ 否则用
///      [kDefaultSettingsLayout]（代码内嵌默认）。
///   2. 编辑器（settings_organizer_page）修改 [settingsLayoutProvider]。
///   3. 「导出资产」把当前布局写成 JSON 字符串 → 开发者粘贴为
///      `assets/settings_layout.json` → 重新构建即随包分发（跨设备传播）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/settings_layout.dart';

/// 当前生效的设置布局（默认 = 代码内嵌）。
final StateProvider<SettingsLayout> settingsLayoutProvider =
    StateProvider<SettingsLayout>((Ref ref) => kDefaultSettingsLayout);

/// 布局驱动视图中当前选中的合集 id（默认首个）。
final StateProvider<String> layoutSelectedCollectionProvider =
    StateProvider<String>((Ref ref) => 'audio');

/// 是否已加载资产覆盖（冷启动异步加载完成前为 false，UI 显示默认不闪跳）。
final StateProvider<bool> settingsLayoutLoadedProvider =
    StateProvider<bool>((Ref ref) => false);

/// 冷启动：尝试读 `assets/settings_layout.json` 覆盖默认布局。
Future<void> loadSettingsLayoutAsset(WidgetRef ref) async {
  try {
    final String raw = await rootBundle.loadString('assets/settings_layout.json');
    if (raw.trim().isEmpty) return;
    final dynamic parsed = const JsonDecoder().convert(raw);
    if (parsed is Map<String, dynamic>) {
      final SettingsLayout layout = SettingsLayout.fromJson(parsed);
      if (layout.collections.isNotEmpty) {
        ref.read(settingsLayoutProvider.notifier).state = layout;
      }
    }
  } catch (_) {
    // 资产缺失/损坏 → 保持默认布局（开发者未打包自定义布局的正常路径）。
  } finally {
    ref.read(settingsLayoutLoadedProvider.notifier).state = true;
  }
}

/// 导出当前布局为 JSON 资产内容（开发者粘贴到 assets/settings_layout.json）。
String exportSettingsLayoutJson(SettingsLayout layout) => layout.encode();

/// 新建合集（返回 id）。
String newCollectionId() => 'col_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

/// 新建组（返回 id）。
String newGroupId() => 'grp_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
