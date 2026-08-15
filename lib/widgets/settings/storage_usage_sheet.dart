/// 存储占用展示面板（cl54-G6）：设置-关于-存储。
///
/// 点击后异步统计应用各目录占用（文档/支持/临时），底部面板展示
/// 分类明细 + 总计；统计期间显示加载态，失败降级提示。
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../services/storage_usage_service.dart';

/// 打开存储占用底部面板。
Future<void> showStorageUsageSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.bgSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (BuildContext sheetContext) => const _StorageUsagePanel(),
  );
}

class _StorageUsagePanel extends StatelessWidget {
  const _StorageUsagePanel();

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.md,
          AppSpace.md,
          AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('存储占用', style: context.appText.subtitle),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            FutureBuilder<StorageUsage>(
              future: collectStorageUsage(),
              builder: (BuildContext context,
                  AsyncSnapshot<StorageUsage> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpace.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || snapshot.data == null) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpace.md),
                    child: Text(
                      '统计失败：${snapshot.error ?? '未知错误'}',
                      style: context.appText.artist
                          .copyWith(color: colors.danger),
                    ),
                  );
                }
                final StorageUsage usage = snapshot.data!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 总计
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: colors.bgCard,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.storage_rounded,
                              size: 22, color: colors.accent),
                          const SizedBox(width: 10),
                          Text('总计占用', style: context.appText.body),
                          const Spacer(),
                          Text(
                            usage.totalHuman,
                            style: context.appText.body
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    for (final StorageUsageEntry e in usage.entries) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(e.label, style: context.appText.bodyMuted),
                          ),
                          Text(e.human, style: context.appText.body),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                    ],
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      '仅统计应用自身目录；系统媒体库曲目不计入。',
                      style: context.appText.artist,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
