/// ════════════════════════════════════════════════════════════════════════
/// 星璃世界 · 游戏主菜单页（H1 修订版：独立页，未进入任何存档时显示）
/// ════════════════════════════════════════════════════════════════════════
///
/// 按钮从上到下：**世界存档 / 开放世界 / 游戏设置**（用户确认 E 组：
/// 去掉「新建游戏」；「读取存档」→「世界存档」；「多人联机」→「开放世界」）。
/// - 世界存档 → 完整存档管理器（新建/恢复进入/导出/重命名/删除）。
/// - 开放世界 → 存档选择进入（新建世界入口收敛到存档管理页内）。
/// - 游戏设置 → 游戏画质/控制设置页。
///
/// 进入世界后此页不可再操作（游戏内只有「游戏菜单/暂停菜单」，见
/// `voxel_world_view3d.dart` 的暂停系统）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../pages/settings/settings_page.dart';
import '../../pages/settings/voxel_save_manager_page.dart';
import '../../providers/settings/notification_providers.dart';
import '../../providers/settings/settings_layout_provider.dart';

/// 星璃世界游戏主菜单页。
class VoxelMainMenuPage extends ConsumerWidget {
  const VoxelMainMenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const Color ink = Color(0xFFF2F5FA);
    final Color accent = context.appColors.accent;
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 深色渐变底（与 3D 世界同色调）。
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      accent.withValues(alpha: 0.18),
                      const Color(0xFF0B1220),
                    ],
                    stops: const <double>[0, 0.6],
                  ),
                ),
              ),
            ),
            // 返回（探索页进入时可退出）。
            Positioned(
              top: AppSpace.md,
              left: AppSpace.md,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: ink),
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            // 中央菜单卡。
            Center(
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: const Color(0xCC151D2E),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: const Color(0x40FFFFFF)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Icon(Icons.view_in_ar_rounded,
                            size: 22, color: ink),
                        const SizedBox(width: 8),
                        Text(
                          '星璃世界',
                          style: AppTextStyles.title.copyWith(color: ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    // E2：读取存档 → 世界存档（入口不变，仍是存档管理器）。
                    _MenuButton(
                      icon: Icons.public_rounded,
                      label: '世界存档',
                      accent: accent,
                      ink: ink,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const VoxelSaveManagerPage(),
                        ),
                      ),
                    ),
                    // E3：多人联机 → 开放世界（开发中占位，走全局通知）。
                    _MenuButton(
                      icon: Icons.language_rounded,
                      label: '开放世界',
                      accent: accent,
                      ink: ink,
                      onTap: () => _notify(ref, '开放世界', '开发中，敬请期待'),
                    ),
                    _MenuButton(
                      icon: Icons.settings_outlined,
                      label: '游戏设置',
                      accent: accent,
                      ink: ink,
                      // R26skel：游戏设置 = 全局设置页「游戏」合集（与游戏内
                      // 暂停菜单一致，不再用独立 GameGraphicsPage）。
                      onTap: () {
                        ref.read(layoutSelectedCollectionProvider.notifier).state =
                            'game';
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D 通知：统一走全局通知（右上角 ≤1/3 宽，不占全屏）。
  void _notify(WidgetRef ref, String title, String msg) {
    ref.read(recentNotificationsProvider.notifier).append(title, msg);
  }
}

/// 主菜单行按钮。
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    required this.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color accent;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 13,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: const Color(0x2EFFFFFF)),
            ),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: ink),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(color: ink),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
