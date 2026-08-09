import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/light_tokens.dart';
import '../../../models/scene.dart';
import '../../../providers/explore/sensor_providers.dart';
import '../../../providers/scene/scene_providers.dart';
import '../../../widgets/common/page_scaffold.dart';
import '../../../widgets/common/state_chip.dart';

/// 实验 F · 传感器（v2 M2 · P0-M2-3，Q5 已裁决：仅光线 + 加速度）。
///
/// - 光线 lux（Android 有值；其余平台 null → 「当前设备不支持」）；
/// - 场景亮度遮罩联动（lux 越低 → 遮罩越深）；
/// - 摇一摇切换场景（加速度，带开关）。
/// 隐私说明并入本页（P1-M2-6，本地处理不上传）。
class SensorPage extends ConsumerWidget {
  const SensorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double? lux = ref.watch(lightLuxProvider).valueOrNull;
    final bool lightSupported = lux != null;
    final bool shakeEnabled = ref.watch(shakeSceneEnabledProvider);
    final Scene scene = ref.watch(activeSceneProvider);
    final String? message = ref.watch(shakeSceneMessageProvider);
    final double mask = ref.watch(sceneBrightnessMaskProvider);

    // 启用摇一摇联动时激活监听 provider
    if (shakeEnabled) {
      ref.watch(shakeSceneLinkProvider);
    }

    return Scaffold(
      backgroundColor: AppColors.bgPage,
      body: SafeArea(
        child: PageScaffold(
          title: '传感器',
          actions: const <Widget>[
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: StateChip(tone: ChipTone.experimenting, label: '实验'),
            ),
          ],
          body: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              const Text(
                '隐私说明：光线与加速度数据全部在本机处理，用于场景联动，'
                '不会上传到任何服务器。',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSpace.md),

              // ── 光线 ─────────────────────────────────────
              _SensorCard(
                icon: Icons.light_mode_rounded,
                title: '环境光',
                value: lightSupported
                    ? '${lux.round()} lux'
                    : '当前设备不支持',
                subtitle: lightSupported
                    ? '亮度遮罩 ${(mask * 100).round()}%（越低越暗）'
                    : 'light 传感器仅 Android 支持',
              ),
              const SizedBox(height: AppSpace.md),

              // ── 摇一摇 ───────────────────────────────────
              _SensorCard(
                icon: Icons.vibration_rounded,
                title: '摇一摇切场景',
                value: shakeEnabled ? '已开启' : '已关闭',
                subtitle: '摇动手机切换到下一场景',
                trailing: Switch(
                  value: shakeEnabled,
                  onChanged: (bool v) {
                    ref.read(shakeSceneEnabledProvider.notifier).state = v;
                    if (v) {
                      ref.read(shakeSceneMessageProvider.notifier).state =
                          '摇一摇已开启：摇动手机切换场景';
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpace.md),

              // 当前场景
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.bgSurfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.landscape_rounded,
                        color: AppColors.accent),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        '当前场景：${scene.name}',
                        style: AppTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ),

              if (message != null) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                Text(message, style: AppTextStyles.caption),
              ],

              const SizedBox(height: AppSpace.lg),
              Text(
                '提示：桌面端无法读取传感器数据，请在 Android 真机上体验。',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 传感器信息卡。
class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: AppSize.icon, color: AppColors.accent),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: AppTextStyles.body),
                Text(value, style: AppTextStyles.subtitle),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.artist),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
