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
import '../../services/log_service.dart';
import '../../services/ota_service.dart';
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

/// 版本更新面板：当前版本 + 检查更新（G7 已接入真实 OTA）。
class _VersionUpdatePanel extends ConsumerStatefulWidget {
  const _VersionUpdatePanel();

  @override
  ConsumerState<_VersionUpdatePanel> createState() =>
      _VersionUpdatePanelState();
}

class _VersionUpdatePanelState extends ConsumerState<_VersionUpdatePanel> {
  bool _checking = false;
  bool _downloading = false;

  /// G7：检查 GitHub Releases → 有更新 → 询问/直接下载 → 哈希校验 → 提示。
  Future<void> _check() async {
    setState(() {
      _checking = true;
      _downloading = false;
    });
    final OtaCheckResult r = await OtaService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() => _checking = false);

    if (!r.hasUpdate || r.latestTag.isEmpty) {
      appNotify(context, '当前已是最新版本：${AppVersion.display}');
      return;
    }
    // 有更新：hotfix 直接下载；普通版本先确认。
    final bool go = r.isHotfix ||
        (await _confirmUpdate(context, r)) == true;
    if (!go || !mounted) return;
    await _download(r.latestTag);
  }

  Future<bool?> _confirmUpdate(BuildContext context, OtaCheckResult r) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text(
          '最新版本 ${r.latestTag}（当前 ${AppVersion.display}）\n\n'
          '${r.releaseNotes.isNotEmpty ? r.releaseNotes : '前往更新以获取最新体验。'}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _download(String tag) async {
    setState(() => _downloading = true);
    try {
      // 下载 + SHA-256 校验（服务内部完成）。
      final String apkPath = await OtaService.instance.downloadAndVerify(tag);
      if (!mounted) return;
      setState(() => _downloading = false);
      appNotify(context, '新版本已下载并通过校验：$tag');
      LogService.instance.i(
          'ota', '更新包已就绪（校验通过）: $apkPath（安装器接入见后续）');
    } on OtaException catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      appNotify(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      appNotify(context, '更新失败：$e');
    }
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
                icon: _checking || _downloading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.system_update_alt_rounded, size: 18),
                label: Text(
                  _downloading
                      ? '下载并校验中…'
                      : (_checking ? '检查中…' : '检查更新'),
                ),
                onPressed: (_checking || _downloading) ? null : _check,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '连接 GitHub Releases 自动获取安装包，下载后校验 SHA-256 哈希，'
              '通过才提示安装；hotfix 版本直接下载。',
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
