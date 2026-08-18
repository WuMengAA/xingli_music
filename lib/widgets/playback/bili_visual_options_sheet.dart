/// 视听结合 · 子选项弹层（cl48）
///
/// 长按音乐卡上的「视听」按钮打开，调节背景视频的
/// **模糊 / 进度同步 / 变速适配** 三个开关（默认：模糊关、同步开、变速关）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/sources/bilibili_provider.dart';

/// 打开视听结合子选项底部弹层。
void showBiliVisualOptionsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _BiliVisualOptionsContent(),
  );
}

class _BiliVisualOptionsContent extends ConsumerWidget {
  const _BiliVisualOptionsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool blur = ref.watch(biliVisualBlurProvider);
    final bool sync = ref.watch(biliVisualSyncProvider);
    final bool tempo = ref.watch(biliVisualTempoAdaptProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.sm,
            ),
            child: Text('视频背景', style: context.appText.body),
          ),
          _Row(
            '背景模糊',
            '视频背景叠加少量模糊（默认关）',
            blur,
            (bool v) => ref.read(biliVisualBlurProvider.notifier).state = v,
          ),
          _Row(
            '进度同步',
            '视频画面跟随音乐播放进度（默认开）',
            sync,
            (bool v) => ref.read(biliVisualSyncProvider.notifier).state = v,
          ),
          _Row(
            '自动校准',
            '时长相差过大时实时同步进度（默认关）',
            tempo,
            (bool v) =>
                ref.read(biliVisualTempoAdaptProvider.notifier).state = v,
          ),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.sub, this.value, this.onChanged);

  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: context.appText.body),
      subtitle: Text(sub, style: context.appText.artist),
      value: value,
      activeColor: context.appColors.accent,
      onChanged: onChanged,
    );
  }
}
