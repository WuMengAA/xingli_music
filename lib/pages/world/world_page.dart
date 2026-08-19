/// 世界 Tab · 星璃世界入口（精简版）。
///
/// 用户要求（2026-08-19）：只显示 **我的存档 / 开放世界 / 游戏设置** 三个
/// 入口按钮，无需其他装饰。已移除：顶部氛围光晕、右上角「+ 创建」按钮、
/// 存档网格/骨架屏/空态（入口收敛到存档管理页内）。
///
/// 对接入口（必须正确）：
/// - 我的存档 → [VoxelSaveManagerPage]（新建/恢复进入/导出/重命名/删除）
/// - 开放世界 → [VoxelLobbyPage]（联机大厅：创建/加入/局域网）
/// - 游戏设置 → [VoxelGameSettingsPage]（游戏画质/控制/音频设置）
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../pages/settings/voxel_game_settings_page.dart';
import '../../pages/settings/voxel_save_manager_page.dart';
import '../../pages/voxel/voxel_lobby_page.dart';
import '../../widgets/common/page_scaffold.dart';

/// 世界页（底部 Dock「世界」Tab）· 星璃世界入口。
class WorldPage extends ConsumerWidget {
  const WorldPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageScaffold(
      title: Terms.world,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 我的存档 → 完整存档管理器。
              _EntryRow(
                icon: Icons.public_rounded,
                label: '我的存档',
                subtitle: '新建 / 恢复进入 / 导出 / 重命名 / 删除',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VoxelSaveManagerPage(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // 开放世界 → 联机大厅（创建 / 加入 / 局域网）。
              _EntryRow(
                icon: Icons.language_rounded,
                label: '开放世界',
                subtitle: '进入实时体素世界，自由探索与建造',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VoxelLobbyPage(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // 游戏设置 → 独立「包厢」游戏设置页。
              _EntryRow(
                icon: Icons.settings_outlined,
                label: '游戏设置',
                subtitle: '画面 · 操作 · 音频 · 性能偏好设置',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VoxelGameSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 入口行（玻璃卡）：图标 + 标题 + 副标题 + 箭头。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 18),
          decoration: BoxDecoration(
            color: c.bgSurface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: c.border.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  color: c.accent.withValues(alpha: 0.16),
                ),
                child: Icon(icon, size: 24, color: c.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: context.appText.subtitle.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: context.appText.caption.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 24, color: c.iconInactive),
            ],
          ),
        ),
      ),
    );
  }
}
