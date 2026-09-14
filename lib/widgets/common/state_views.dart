import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';

/// 状态视图统一容器：空间够就居中，空间不够就可滚动。
///
/// 加载 / 错误 / 空态过去都是 `Center(child: Column(...))`，一旦父容器高度
/// 很矮（如 800×500 横屏下曲库正文只剩 35dp）就会 RenderFlex overflow。
/// 这里用「ConstrainedBox(minHeight) + SingleChildScrollView」的标准写法：
/// 高度充足时表现与居中完全一致，高度不足时降级为可滚动而非报错。
class _StateViewFrame extends StatelessWidget {
  const _StateViewFrame({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

/// 加载态视图（v2 M3 · P1-M3-6 三件套统一）。
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = '加载中…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _StateViewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircularProgressIndicator(color: context.appColors.accent),
          const SizedBox(height: AppSpace.md),
          Text(
            label,
            style: AppTextStyles.bodyMuted.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 错误态视图（含重试按钮）。
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _StateViewFrame(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: context.appColors.danger,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            message,
            style: AppTextStyles.bodyMuted.copyWith(
              color: context.appColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.lg),
          OutlinedButton(
            onPressed: onRetry,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.refresh_rounded, size: 18),
                SizedBox(width: 8),
                Text('重试'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 非全屏错误条：聚合 / 列表页「单源失败、其余正常」时在结果列表顶部展示
/// 一条可重试的错误提示，不阻断其余内容渲染。配色沿用 [ErrorView]（systemRed）。
///
/// 与 [ErrorView] 的区别：条状、非全屏、可与结果列表共存（[ErrorView] 会整体
/// 替换内容）。典型场景：聚合搜索「全部」筛选下网易云登录失效 / 403，B站结果
/// 仍要展示，仅顶部冒一条错误条 + 重试。
class SourceErrorBar extends StatelessWidget {
  const SourceErrorBar({
    super.key,
    required this.sourceLabel,
    required this.message,
    required this.onRetry,
    this.authFail = false,
    this.onLogin,
  });

  /// 失败源的名字（如「网易云」「B站」「网易云歌单」）。
  final String sourceLabel;

  /// 用户可读的失败原因（已由调用方转成中文）。
  final String message;

  /// 重试回调（失效 provider 使其重取首批）。
  final VoidCallback onRetry;

  /// 是否为登录失效类错误：是则按钮文案换成「去登录」并回调 [onLogin]。
  final bool authFail;

  /// 登录失效时点的登录入口（[authFail] 为 true 时使用）。
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$sourceLabel 加载失败：$message',
              style: context.appText.artist.copyWith(color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: authFail ? onLogin : onRetry,
            child: Text(authFail ? '去登录' : '重试'),
          ),
        ],
      ),
    );
  }
}

/// 空态视图（含可选操作按钮）。
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateViewFrame(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.music_off_rounded,
            size: 40,
            color: context.appColors.textTertiary,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            title,
            style: AppTextStyles.subtitle.copyWith(
              color: context.appColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            message,
            style: AppTextStyles.bodyMuted.copyWith(
              color: context.appColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: AppSpace.lg),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
