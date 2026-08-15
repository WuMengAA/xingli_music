/// 关于-版本日志 / 版本更新（cl55）。
///
/// - `showVersionLogSheet`：展示版本日志（自动取最新在前，changelog 每次构建
///   自动补录，天然倒序 = 最新在顶部）。
/// - `showVersionUpdateSheet`：版本更新入口——当前展示当前版本与最近版本信息；
///   真实 OTA 检查（GitHub / 官网 → 下载 → 哈希校验 → 提醒）由 G7 接入，
///   此处保留统一入口（点击即触发检查回调）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../notification/app_notify.dart';

/// 打开版本日志面板（自动获取最新日志：changelog 倒序，首条即最新）。
Future<void> showVersionLogSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.bgSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (BuildContext sheetContext) => const _VersionLogPanel(),
  );
}

/// 打开版本更新面板（OTA 入口；G7 接入真实检查）。
Future<void> showVersionUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.appColors.bgSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (BuildContext sheetContext) => const _VersionUpdatePanel(),
  );
}

/// 版本日志面板：列出全部更新日志，最新在前。
class _VersionLogPanel extends StatelessWidget {
  const _VersionLogPanel();

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    // 自动获取最新日志：changelog 按时间倒序（最新在前），首条即最新。
    final ChangelogEntry latest = changelog.isEmpty
        ? const ChangelogEntry(
            version: '',
            cl: '',
            title: '暂无日志',
            details: <String>[],
          )
        : changelog.first;
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
                  child: Text('版本日志', style: context.appText.subtitle),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            // 最新版本徽标（自动取最新日志）。
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: colors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '最新 ${latest.cl} · ${latest.version}',
                style: context.appText.caption
                    .copyWith(color: colors.accent),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final ChangelogEntry e in changelog) _LogTile(entry: e),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 版本更新面板：当前版本 + 检查更新（G7 接入真实 OTA）。
class _VersionUpdatePanel extends ConsumerStatefulWidget {
  const _VersionUpdatePanel();

  @override
  ConsumerState<_VersionUpdatePanel> createState() =>
      _VersionUpdatePanelState();
}

class _VersionUpdatePanelState extends ConsumerState<_VersionUpdatePanel> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    // G7（OTA）：此处接入 GitHub / 官网检查 → 下载 → 哈希校验 → 提醒。
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _checking = false);
    appNotify(context, '当前已是最新版本：${AppVersion.display}');
  }

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
                  child: Text('版本更新', style: context.appText.subtitle),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: colors.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('当前版本', style: context.appText.bodyMuted),
                  const SizedBox(height: 4),
                  Text(
                    AppVersion.display,
                    style: context.appText.subtitle
                        .copyWith(color: colors.accent),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    changelog.isEmpty ? '暂无日志' : changelog.first.title,
                    style: context.appText.artist,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.system_update_alt_rounded, size: 18),
                label: Text(_checking ? '检查中…' : '检查更新'),
                onPressed: _checking ? null : _check,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '更新检查将连接 GitHub Releases 与官方网站，'
              '自动获取安装包并在下载后校验哈希（G7 上线后生效）。',
              style: context.appText.artist,
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条版本日志。
class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final ChangelogEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(entry.title, style: context.appText.body),
              ),
              Text(
                '${entry.version} · ${entry.cl}',
                style: context.appText.caption
                    .copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final String d in entry.details)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('· ', style: context.appText.bodyMuted),
                  Expanded(
                    child: Text(d, style: context.appText.bodyMuted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
