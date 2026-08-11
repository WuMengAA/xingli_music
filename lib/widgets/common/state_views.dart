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
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('重试'),
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
