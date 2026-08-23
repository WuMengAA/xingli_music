import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../providers/sources/netease_provider.dart';
import '../sources/netease_login_sheet.dart';

/// 网易云登录态失效引导（区别于纯网络错误）。
///
/// 直接在此弹出登录 sheet，登录成功/失败后刷新 auth 与指定 provider，
/// 让上层页面回到正常数据态或重新进入本引导。用于每日推荐 / 漫游等
/// 强依赖登录的网易云页面。
class NeteaseAuthExpiredHint extends ConsumerWidget {
  const NeteaseAuthExpiredHint({
    super.key,
    required this.onRefreshed,
  });

  /// 用户点击重登并关闭 sheet 后触发（用于 invalidate 数据 provider）。
  final void Function(WidgetRef ref) onRefreshed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeColors c = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.login_rounded, size: 40, color: c.iconInactive),
            const SizedBox(height: 16),
            Text('网易云登录已失效', style: context.appText.subtitle),
            const SizedBox(height: 6),
            Text(
              '重新登录后即可继续获取推荐内容',
              style: context.appText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: () async {
                await showNeteaseLoginSheet(context);
                if (!context.mounted) return;
                ref.invalidate(neteaseAuthProvider);
                onRefreshed(ref);
              },
              child: const Text('重新登录'),
            ),
          ],
        ),
      ),
    );
  }
}
