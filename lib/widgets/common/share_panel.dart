/// ════════════════════════════════════════════════════════════════════════
/// 分享面板（预设组件 · Task #520）
/// ════════════════════════════════════════════════════════════════════════
///
/// 还原 Ardot 设计 `sheet-分享`（3:518 / 3:519）：
///   - 顶部抓手小条 + 标题「分享」
///   - 一行分享渠道（微信 / QQ / 链接 / 系统，设计默认 4 个，可任意数量）
///   - 底部「取消」按钮
///
/// 外观完全跟随主题 / 皮肤：玻璃用 [LiquidGlass]，所有颜色取自 `context.appColors`，
/// 不写死任何品牌色。点击某个渠道会以该 [ShareChannel] 关闭面板。
///
/// 用法：
/// ```dart
/// final ShareChannel? picked = await SharePanel.show(
///   context: context,
///   channels: <ShareChannel>[
///     ShareChannel(icon: Icons.wechat_outlined, label: '微信'),
///     ShareChannel(icon: Icons.link, label: '链接'),
///   ],
/// );
/// ```
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../widgets/liquid_glass.dart';

/// 一个分享渠道（图标 + 文案）。
class ShareChannel {
  const ShareChannel({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 分享面板（底部弹层）。
class SharePanel extends StatelessWidget {
  const SharePanel({
    super.key,
    this.title = '分享',
    required this.channels,
    this.cancelLabel = '取消',
    this.onCancel,
  });

  final String title;
  final List<ShareChannel> channels;
  final String cancelLabel;

  /// 取消回调（点击取消按钮后触发，先于 pop）。
  final VoidCallback? onCancel;

  /// 以模态底部弹层展示，返回被点击的 [ShareChannel]，取消则为 `null`。
  static Future<ShareChannel?> show({
    required BuildContext context,
    String title = '分享',
    required List<ShareChannel> channels,
    String cancelLabel = '取消',
    bool isDismissible = true,
  }) {
    final AppThemeColors colors = context.appColors;
    return showModalBottomSheet<ShareChannel?>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: colors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      builder: (BuildContext ctx) => SharePanel(
        title: title,
        channels: channels,
        cancelLabel: cancelLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return LiquidGlass(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(child: _Grabber(colors: colors)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: channels
                .map((ShareChannel c) => _ChannelTile(colors: colors, channel: c))
                .toList(),
          ),
          const SizedBox(height: 16),
          _CancelButton(colors: colors, label: cancelLabel, onTap: onCancel),
        ],
      ),
    );
  }
}

/// 顶部抓手小条。
class _Grabber extends StatelessWidget {
  const _Grabber({required this.colors});
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) => Container(
        width: 60,
        height: 5,
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

/// 单个分享渠道磁贴（64×78）。
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.colors, required this.channel});

  final AppThemeColors colors;
  final ShareChannel channel;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).pop(channel),
      child: SizedBox(
        width: 64,
        height: 78,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.bgSurface,
                border: Border.all(color: colors.border, width: 1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(channel.icon, size: 24, color: colors.iconPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              channel.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底部「取消」按钮（描边药丸，非强调色）。
class _CancelButton extends StatelessWidget {
  const _CancelButton({
    required this.colors,
    required this.label,
    this.onTap,
  });

  final AppThemeColors colors;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.bgSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.border, width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          onTap?.call();
          Navigator.of(context).pop();
        },
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
