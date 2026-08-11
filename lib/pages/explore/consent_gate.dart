import '../../core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../providers/explore/experiment_providers.dart';

/// 实验同意 Gate（v2 M2 · P0-M2-1，方案 A 已裁决）。
///
/// - 未同意：全屏 Gate 卡片（实验性 / 可能不稳定 / 数据用途 / 可随时退出）。
/// - 「同意并进入」→ `agree()` 持久化，父级重建为实验列表。
/// - 「暂不参与」→ 只读条款 + 「再次进入」按钮（页面可见性保留，Q2-A）。
class ConsentGate extends ConsumerWidget {
  const ConsentGate({super.key});

  /// 隐私说明（P1-M2-6 / Q5 已裁决：传感器 / 心情数据本地处理，不上传）。
  static const String privacyNote =
      '隐私说明：传感器（光线 / 加速度）与心情问卷数据全部在本机处理，'
      '不会上传到任何服务器；如需上传会先征得你的二次授权。';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: context.appColors.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.appColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.science_rounded,
                size: 48,
                color: context.appColors.accent,
              ),
              const SizedBox(height: AppSpace.md),
              Text('探索实验室', style: context.appText.title),
              const SizedBox(height: AppSpace.sm),
              Text(
                '这里是实验场所',
                style: context.appText.subtitle.copyWith(color: context.appColors.accent),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                '这里的实验功能仍在打磨中：\n'
                '· 可能不稳定，界面随时调整\n'
                '· 数据仅用于本地个性化，不会上传\n'
                '· 你可以在设置「实验」中随时撤销同意',
                style: context.appText.bodyMuted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                privacyNote,
                style: context.appText.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpace.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () =>
                      ref.read(experimentConsentProvider.notifier).agree(),
                  child: const Text('同意并进入'),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextButton(
                onPressed: () => _showReadOnly(context, ref),
                child: Text('暂不参与', style: context.appText.body),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 方案 A：暂不参与 → 只读条款 + 再次进入按钮。
  void _showReadOnly(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('暂不参与', style: context.appText.subtitle),
                const SizedBox(height: AppSpace.md),
                Text(
                  '你选择了暂不参与实验。你可以随时重新进入：\n\n'
                  '· 实验功能仍处于开发阶段，可能不稳定；\n'
                  '· 数据（传感器 / 心情）全部本地处理，不上传；\n'
                  '· 同意状态保存在本机，可在设置「实验」中撤销。',
                  style: context.appText.bodyMuted,
                ),
                const SizedBox(height: AppSpace.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('再次进入'),
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(Terms.cancel, style: context.appText.body),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
