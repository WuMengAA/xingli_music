/// ════════════════════════════════════════════════════════════════════════
/// 星璃世界 · 游戏设置「包厢」（cl42·⑥）
/// ════════════════════════════════════════════════════════════════════════
///
/// 从游戏主菜单「游戏设置」进入的**独立**页，只渲染 `game` 合集（游戏内
/// 快捷设置），不显示其它合集入口、也不跳回全局设置页——消除「游戏设置被
/// 夹在设置页里、与其它合集互相套娃」的问题。带明确返回游戏主菜单的返回键。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings_item_registry.dart';
import '../../core/settings_layout.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/settings_layout_provider.dart';

/// 游戏设置独立页（「包厢」）。
class VoxelGameSettingsPage extends ConsumerWidget {
  const VoxelGameSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SettingsLayout layout = ref.watch(settingsLayoutProvider);
    // 只取 game 合集（找不到则首个），确保只展示游戏类设置。
    SettingCollection? game;
    for (final SettingCollection c in layout.collections) {
      if (c.id == 'game') {
        game = c;
        break;
      }
    }
    game ??= layout.collections.isNotEmpty ? layout.collections.first : null;

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: context.appColors.bgPage,
        foregroundColor: context.appColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('游戏设置', style: context.appText.title),
      ),
      body: game == null
          ? Center(
              child: Text('暂无游戏设置', style: context.appText.bodyMuted),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpace.md),
              children: <Widget>[
                for (final SettingGroup g in game.groups) ...<Widget>[
                  if (g.name.isNotEmpty) ...<Widget>[
                    // 分组标题放大（与全局设置页一致，titleSmall + 加粗）。
                    Text(
                      g.name,
                      style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700) ??
                          context.appText.subtitle,
                    ),
                    const SizedBox(height: 6),
                  ],
                  for (final SettingItem item in g.items) ...<Widget>[
                    buildSettingItem(context, ref, item.id),
                    const Divider(height: 1),
                  ],
                  const SizedBox(height: AppSpace.md),
                ],
              ],
            ),
    );
  }
}
