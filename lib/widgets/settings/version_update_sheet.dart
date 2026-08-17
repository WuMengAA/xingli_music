/// 关于-版本日志 / 版本更新（cl55）。
///
/// - `showVersionLogSheet`：展示版本日志（自动取最新在前，changelog 每次构建
///   自动补录，天然倒序 = 最新在顶部）。
/// - `showVersionUpdateSheet`：版本更新入口——当前展示当前版本与最近版本信息；
///   真实 OTA 检查（GitHub / 官网 → 下载 → 哈希校验 → 提醒）由 G7 接入，
///   此处保留统一入口（点击即触发检查回调）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/settings/ota_download_provider.dart';
import '../../providers/settings/settings_persistence_providers.dart';
import '../../services/ota_service.dart';
import '../../services/ota_install.dart';
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

/// 版本日志面板：展示启动时拉取并缓存的网络更新日志（当前渠道），
/// 无缓存（首次 / 离线）时给出提示。
class _VersionLogPanel extends ConsumerStatefulWidget {
  const _VersionLogPanel();

  @override
  ConsumerState<_VersionLogPanel> createState() => _VersionLogPanelState();
}

class _VersionLogPanelState extends ConsumerState<_VersionLogPanel> {
  Future<String?>? _notesFuture;
  Future<String?>? _tagFuture;

  @override
  void initState() {
    super.initState();
    _notesFuture = OtaService.cachedNotes();
    _tagFuture = OtaService.cachedNotesTag();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    final UpdateChannel ch =
        ref.read(settingsRepositoryProvider).updateChannel;
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
                  child: Text('更新日志（${ch.label}）',
                      style: context.appText.subtitle),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Flexible(
              child: FutureBuilder<String?>(
                future: _notesFuture,
                builder: (BuildContext c, AsyncSnapshot<String?> snap) {
                  final String? notes = snap.data;
                  if (notes == null || notes.trim().isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: colors.bgCard,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Text(
                        '暂无更新日志。联网启动应用后会自动获取当前渠道'
                        '（${ch.label}）的最新日志并保存本地。',
                        style: context.appText.bodyMuted,
                      ),
                    );
                  }
                  return FutureBuilder<String?>(
                    future: _tagFuture,
                    builder: (BuildContext c2, AsyncSnapshot<String?> tagSnap) {
                      final String? tag = tagSnap.data;
                      return ListView(
                        shrinkWrap: true,
                        children: <Widget>[
                          if (tag != null && tag.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.sm,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accentSoft,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '最新 $tag',
                                style: context.appText.caption
                                    .copyWith(color: colors.accent),
                              ),
                            ),
                          const SizedBox(height: AppSpace.sm),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpace.md),
                            decoration: BoxDecoration(
                              color: colors.bgCard,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: SelectableText(
                              notes,
                              style: context.appText.body,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
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
  bool _installing = false;

  /// 检测到的本机架构（OTA 自动选对应拆分包）。
  DeviceAbi _abi = DeviceAbi.arm64;

  /// 检查后列出的本渠道所有版本（倒序，最新在前）。
  List<OtaTagInfo> _versions = <OtaTagInfo>[];

  /// 当前选中的版本下标（默认 0 = 最新）。
  int _selected = 0;

  /// 是否已检查过（决定是否展示版本列表）。
  bool _checked = false;

  /// G7：检查 GitHub Releases（当前渠道）→ 列出全部版本供多选 →
  /// 按本机架构选对应拆分包下载 →（后台）哈希校验 → 提示。
  Future<void> _check() async {
    setState(() => _checking = true);
    final UpdateChannel ch =
        ref.read(settingsRepositoryProvider).updateChannel;
    // 并发：检测架构 + 拉取本渠道版本列表。
    final List<dynamic> res = await Future.wait<dynamic>(
      <Future<dynamic>>[
        OtaService.detectDeviceAbi(),
        OtaService.instance.listChannelReleases(ch),
      ],
    );
    if (!mounted) return;
    _abi = res[0] as DeviceAbi;
    _versions = res[1] as List<OtaTagInfo>;
    _selected = 0;
    setState(() {
      _checking = false;
      _checked = true;
    });

    if (_versions.isEmpty) {
      appNotify(context, '当前渠道（${ch.label}）暂无可下载版本');
    }
  }

  /// 选中版本是否比当前更新。
  bool _isNewer(OtaTagInfo v) =>
      v.newerThanCurrent(_currentDateKey, AppVersion.buildCount);

  static int get _currentDateKey =>
      AppVersion.year * 10000 + AppVersion.month * 100 + AppVersion.day;

  OtaTagInfo? get _selectedVersion =>
      _versions.isNotEmpty ? _versions[_selected] : null;

  /// 下载完成后调系统安装器安装（cl74：此前整条安装链路缺失，下载完无入口）。
  Future<void> _install(String apkPath) async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      await OtaInstall.install(apkPath);
    } on OtaException catch (e) {
      if (mounted) appNotify(context, e.message);
    } catch (e) {
      if (mounted) appNotify(context, '安装失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<bool?> _confirmUpdate(BuildContext context, OtaTagInfo v) {
    final bool newer = _isNewer(v);
    return showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(newer ? '发现新版本' : '安装此版本？'),
        content: Text(
          '${v.tag}（当前 ${AppVersion.display}）\n\n'
          '${v.notes.isNotEmpty ? v.notes : '前往更新以获取最新体验。'}',
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

  /// 版本选择项（点按 / Radio 切换；选中高亮）。
  Widget _buildVersionTile(int index, OtaTagInfo v) {
    final AppThemeColors colors = context.appColors;
    final bool selected = index == _selected;
    final bool newer = _isNewer(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: selected ? colors.accentSoft : colors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => setState(() => _selected = index),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? colors.accent : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            v.tag,
                            style: context.appText.body
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          if (newer)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text('可更新',
                                  style: context.appText.caption
                                      .copyWith(color: Colors.white)),
                            )
                          else
                            Text('当前 / 旧版',
                                style: context.appText.caption
                                    .copyWith(color: colors.textSecondary)),
                        ],
                      ),
                      if (v.notes.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          v.notes.split('\n').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.appText.artist,
                        ),
                      ],
                      if (v.hotfix != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text('含 hotfix${v.hotfix} 补丁',
                            style: context.appText.caption
                                .copyWith(color: colors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                Radio<int>(
                  value: index,
                  groupValue: _selected,
                  activeColor: colors.accent,
                  onChanged: (int? i) =>
                      setState(() => _selected = i ?? _selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 弹确认框后启动下载（按本机架构选拆分包）。
  Future<void> _maybeDownload(OtaTagInfo v) async {
    final bool? ok = await _confirmUpdate(context, v);
    if (ok == true && mounted) {
      ref.read(otaDownloadProvider.notifier).start(v.tag, abi: _abi);
    }
  }

  /// 主按钮动作：检查 → 下载选中版本 → 安装 / 重试。
  void _onPrimary(OtaDownloadState dl) {
    if (dl.isDone) {
      _install(dl.apkPath);
      return;
    }
    if (dl.isDownloading || _checking || _installing) return;
    if (_checked) {
      final OtaTagInfo? v = _selectedVersion;
      if (v != null) {
        _maybeDownload(v);
        return;
      }
    }
    _check();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeColors colors = context.appColors;
    // cl61：订阅全局下载状态（后台下载，本页只负责展示）。
    final OtaDownloadState dl = ref.watch(otaDownloadProvider);
    final String abiLabel =
        _abi == DeviceAbi.arm32 ? 'arm32 (armeabi-v7a)' : 'arm64 (arm64-v8a)';
    final OtaTagInfo? sel = _selectedVersion;
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
                    '更新渠道：${ref.read(settingsRepositoryProvider).updateChannel.label}',
                    style: context.appText.artist,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
            // ── 本机架构指示（OTA 自动选对应拆分包）──
            if (_checked) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: colors.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.memory, size: 18,
                        color: Color(0xFF9AA3B2)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '本机适配：$abiLabel，自动匹配安装包',
                        style: context.appText.body,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.accentSoft,
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text('自动选包',
                          style: context.appText.caption
                              .copyWith(color: colors.accent)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            // ── 多版本选择列表（默认最新，可改选历史版本）──
            if (_checked && _versions.isNotEmpty) ...<Widget>[
              Text('选择版本（默认最新）', style: context.appText.subtitle),
              const SizedBox(height: AppSpace.sm),
              ..._versions.asMap().entries.map(
                    (MapEntry<int, OtaTagInfo> e) =>
                        _buildVersionTile(e.key, e.value),
                  ),
              const SizedBox(height: AppSpace.md),
            ] else if (_checked) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: colors.bgCard,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  '当前渠道暂无可下载版本',
                  style: context.appText.bodyMuted,
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            // ── 下载进度 / 网速 / 后台提示（cl61）──
            if (dl.isDownloading) ...<Widget>[
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
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '正在下载 ${dl.tag} …',
                            style: context.appText.body,
                          ),
                        ),
                        Text(
                          '${(dl.fraction * 100).toStringAsFixed(1)}%',
                          style: context.appText.subtitle
                              .copyWith(color: colors.accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: dl.fraction,
                        minHeight: 6,
                        backgroundColor: colors.accentSoft,
                        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      children: <Widget>[
                        Text(
                          '${_fmtBytes(dl.receivedBytes)} / '
                          '${_fmtBytes(dl.totalBytes)}',
                          style: context.appText.caption,
                        ),
                        const Spacer(),
                        Text(
                          _fmtSpeed(dl.speedBytesPerSec),
                          style: context.appText.caption
                              .copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.cloud_download_outlined,
                          size: 14,
                          color: Color(0xFF9AA3B2),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '后台下载中，可关闭本页，完成后通知你',
                            style: context.appText.artist,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (dl.isDone) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.check_circle,
                        color: Color(0xFF34C759), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${dl.tag} 已下载并通过 SHA-256 校验，可安装更新',
                        style: context.appText.body,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (dl.isError) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.error_outline,
                        color: Color(0xFFFF3B30), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dl.error ?? '更新失败',
                        style: context.appText.bodyMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: (_checking || _installing || dl.isDownloading)
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        dl.isDone
                            ? Icons.install_mobile_rounded
                            : Icons.system_update_alt_rounded,
                        size: 18,
                      ),
                label: Text(
                  dl.isDone
                      ? (_installing ? '安装中…' : '安装更新')
                      : (dl.isDownloading
                          ? '下载中…'
                          : (_checking
                              ? '检查中…'
                              : (_checked
                                  ? (dl.isError
                                      ? '重试下载'
                                      : (sel != null
                                          ? '下载 ${sel.tag}'
                                          : '检查更新'))
                                  : '检查更新'))),
                ),
                onPressed: (_checking || dl.isDownloading || _installing)
                    ? null
                    : () => _onPrimary(dl),
              ),
            ),
            if (dl.isDone) ...<Widget>[
              const SizedBox(height: AppSpace.xs),
              Center(
                child: TextButton(
                  onPressed: () =>
                      ref.read(otaDownloadProvider.notifier).reset(),
                  child: const Text('选择其他版本'),
                ),
              ),
            ],
            const SizedBox(height: AppSpace.xs),
            Text(
              '连接 GitHub Releases 自动获取安装包；按本机架构（arm64/arm32）'
              '自动选对应拆分包，下载后校验 SHA-256 哈希，通过才提示安装；'
              '支持后台下载（可关闭本页，完成后通知你）。',
              style: context.appText.artist,
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtBytes(int b) => b >= 1048576
      ? '${(b / 1048576).toStringAsFixed(1)} MB'
      : '${(b / 1024).toStringAsFixed(0)} KB';

  static String _fmtSpeed(double bs) => bs >= 1048576
      ? '${(bs / 1048576).toStringAsFixed(1)} MB/s'
      : '${(bs / 1024).toStringAsFixed(0)} KB/s';
}
