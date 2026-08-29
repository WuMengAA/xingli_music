import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/terms/naming_dict.dart';
import '../../widgets/common/page_scaffold.dart';
import 'settings_vivo_layout.dart';

/// 设置页（vivo 式左导航 + 右内容排版）。
///
/// 数据来自设置布局模型 [settings_vivo_layout.dart]：左侧（或竖屏顶部）为
/// 分类合集导航，右侧按「选中合集 → 组 → 项」渲染大卡片分区；每项由设置项
/// 注册表按 id 构建，支持用户拖拽自定义布局。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 应用展示名（P0-F6）。
  static const String appName = '星璃音乐空间';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageScaffold(
      title: Terms.tabSettings,
      body: const SettingsVivoLayout(),
    );
  }
}
