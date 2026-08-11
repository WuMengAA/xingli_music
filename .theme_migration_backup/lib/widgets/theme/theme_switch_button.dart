import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/theme/theme_skins.dart';
import '../../providers/theme/theme_providers.dart';
import '../liquid_glass.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 全局主题切换按钮（右上角）
/// ════════════════════════════════════════════════════════════════════════
///
/// 挂在 [PageScaffold] 标题行右侧 → 所有 Shell 页 / 全屏路由页统一出现。
///
/// - 视觉：40dp 毛玻璃圆钮（与 Dock / 统一播放器同为 frosted 语言），
///   图标随当前主题模式变化：跟随系统 / 浅色 / 深色。
/// - 交互：点按弹出底部面板，可切主题模式（跟随系统 / 浅色 / 深色）
///   与皮肤（6 套，见 [ThemeSkins.all]），改动即时全局生效并持久化
///   （themeModeNameProvider / themeSkinProvider 自带 prefs 同步）。
class ThemeSwitchButton extends ConsumerWidget {
  const ThemeSwitchButton({super.key});

  /// 图标随当前模式变化，一眼看出当前状态。
  static IconData _iconFor(String mode) {
    return switch (mode) {
      'light' => Icons.light_mode_outlined,
      'dark' => Icons.dark_mode_outlined,
      _ => Icons.brightness_auto_outlined,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String mode = ref.watch(themeModeNameProvider);

    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.xs),
      child: SizedBox(
        width: AppSize.touchMin,
        height: AppSize.touchMin,
        child: LiquidGlass(
          radius: 24,
          style: GlassStyle.frosted,
          // blur 跟随全局性能模式
          tint: const Color(0x0DFFFFFF),
          borderColor: const Color(0x1AFFFFFF),
          child: IconButton(
            tooltip: '主题',
            onPressed: () => _showThemeSheet(context),
            icon: Icon(
              _iconFor(mode),
              size: AppSize.iconSm,
              color: context.appColors.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }

  /// 底部面板：主题模式 + 皮肤（逻辑与设置页「外观」一致）。
  Future<void> _showThemeSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim.withValues(alpha: 0.45),
      builder: (BuildContext ctx) => const _ThemeSheet(),
    );
  }
}

/// 底部面板内容（ConsumerWidget，改动即时全局生效）。
class _ThemeSheet extends ConsumerWidget {
  const _ThemeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String mode = ref.watch(themeModeNameProvider);
    final String skinId = ref.watch(themeSkinProvider);

    return Container(
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 顶部小把手（视觉提示可下滑关闭）
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.appColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            const Text('主题模式', style: AppTextStyles.body),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.xs,
              children: <Widget>[
                for (final (String v, String label) in <(String, String)>[
                  ('system', '跟随系统'),
                  ('light', '浅色'),
                  ('dark', '深色'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: mode == v,
                    onSelected: (_) {
                      ref.read(themeModeNameProvider.notifier).state = v;
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            const Text(
              '浅色/深色主题由官方控件自动适配；深色下场景配色自动降低亮度。',
              style: AppTextStyles.artist,
            ),
            const SizedBox(height: AppSpace.lg),
            const Text('皮肤', style: AppTextStyles.body),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: <Widget>[
                for (final ThemeSkin skin in ThemeSkins.all)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: skin.primary,
                      radius: 8,
                    ),
                    label: Text(skin.name),
                    selected: skinId == skin.id,
                    onSelected: (_) {
                      ref.read(themeSkinProvider.notifier).state = skin.id;
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            const Text(
              '皮肤决定主题主强调色（按钮 / 进度条 / 选中态 / Tab 高亮等）。',
              style: AppTextStyles.artist,
            ),
          ],
        ),
      ),
    );
  }
}
