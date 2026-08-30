/// 关于-版本日志 / 版本更新（cl55）。
///
/// - `showVersionLogSheet`：展示版本日志（自动取最新在前，changelog 每次构建
///   自动补录，天然倒序 = 最新在顶部）。
/// - `showVersionUpdateSheet`：版本更新入口——当前展示当前版本与最近版本信息；
///   真实 OTA 检查（GitHub / 官网 → 下载 → 哈希校验 → 提醒）由 G7 接入，
///   此处保留统一入口（点击即触发检查回调）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    final UpdateChannel ch = ref.read(settingsRepositoryProvider).updateChannel;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
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
                    child: Text(
                      '更新日志（${ch.label}）',
                      style: context.appText.subtitle,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              FutureBuilder<String?>(
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
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (tag != null && tag.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.sm,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accentSoft,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                '最新 $tag',
                                style: context.appText.caption.copyWith(
                                  color: colors.accent,
                                ),
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
            ],
          ),
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
    final UpdateChannel ch = ref.read(settingsRepositoryProvider).updateChannel;
    // 并发：拉取本渠道版本列表；安卓额外检测本机架构（选拆分包）。
    final List<dynamic> res = await Future.wait<dynamic>(<Future<dynamic>>[
      if (_isAndroid) OtaService.detectDeviceAbi(),
      OtaService.instance.listChannelReleases(ch),
    ]);
    if (!mounted) return;
    if (_isAndroid) _abi = res[0] as DeviceAbi;
    _versions = res[_isAndroid ? 1 : 0] as List<OtaTagInfo>;
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

  /// 下载完成后安装（cl74 / cl77：安卓 = 系统安装器；Windows = 解压替换自启。
  /// 分发在 OtaInstall.install 内部，这里只管调）。
  Future<void> _install(String filePath) async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      await OtaInstall.install(filePath);
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
          '${v.notes.isNotEmpty ? v.notes : '前往更新以获取最新体验。'}'
          '${v.hasWindows ? '\n\n（含 Windows 版，下载后自动替换并重启）' : ''}',
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
                            style: context.appText.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (newer)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: Text(
                                '可更新',
                                style: context.appText.caption.copyWith(
                                  color: colors.onAccent,
                                ),
                              ),
                            )
                          else
                            Text(
                              '当前 / 旧版',
                              style: context.appText.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
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
                        Text(
                          '含 hotfix${v.hotfix} 补丁',
                          style: context.appText.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                      if (v.androidAbis.isNotEmpty || v.hasWindows) ...<Widget>[
                        const SizedBox(height: 4),
                        _platformMarkers(v),
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

  /// 平台/架构标记（安卓·arm64 / 安卓·arm32 / Windows·x64），展示该版本含哪些包。
  Widget _platformMarkers(OtaTagInfo v) {
    final AppThemeColors colors = context.appColors;
    final List<Widget> chips = <Widget>[];
    if (v.androidAbis.contains(DeviceAbi.arm64)) {
      chips.add(_platChip('安卓·arm64', colors.accent));
    }
    if (v.androidAbis.contains(DeviceAbi.arm32)) {
      chips.add(_platChip('安卓·arm32', colors.accent));
    }
    if (v.hasWindows) {
      final String wa = v.windowsArches.isNotEmpty
          ? v.windowsArches.join('/')
          : 'x64';
      chips.add(_platChip('Windows·$wa', const Color(0xFF5B8DEF)));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _platChip(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.withOpacity(0.35), width: 1),
      ),
      child: Text(label, style: context.appText.caption.copyWith(color: c)),
    );
  }

  /// 弹确认框后启动下载（按本机架构选拆分包）。
  Future<void> _maybeDownload(OtaTagInfo v) async {
    final bool? ok = await _confirmUpdate(context, v);
    if (ok == true && mounted) {
      ref.read(otaDownloadProvider.notifier).start(v.tag, abi: _abi);
    }
  }

  /// 自动下载安装安卓 / Windows 电脑版均支持（cl77 电脑版 OTA）。
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 主按钮动作：检查 → 下载选中版本 → 安装 / 重试。
  void _onPrimary(OtaDownloadState dl) {
    if (dl.isDone) {
      _install(dl.filePath);
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
    final String abiLabel = _abi == DeviceAbi.arm32
        ? 'arm32 (armeabi-v7a)'
        : 'arm64 (arm64-v8a)';
    final OtaTagInfo? sel = _selectedVersion;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
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
                      style: context.appText.subtitle.copyWith(
                        color: colors.accent,
                      ),
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
                      // R32 一.5：去固定灰蓝，改语义色（深浅主题自适应）。
                      Icon(Icons.memory, size: 18, color: colors.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isAndroid
                              ? '安卓适配：$abiLabel，自动匹配安装包'
                              : '电脑版适配：Windows·x64，自动下载更新包并替换',
                          style: context.appText.body,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          _isAndroid ? '自动选包' : '自动更新',
                          style: context.appText.caption.copyWith(
                            color: colors.accent,
                          ),
                        ),
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
                  child: Text('当前渠道暂无可下载版本', style: context.appText.bodyMuted),
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
                            style: context.appText.subtitle.copyWith(
                              color: colors.accent,
                            ),
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.accent,
                          ),
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
                            style: context.appText.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          // R32 一.5：去固定灰蓝，改语义色（深浅主题自适应）。
                          Icon(
                            Icons.cloud_download_outlined,
                            size: 14,
                            color: colors.textTertiary,
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
                      // R32 一.5：去固定 iOS 绿，改 success 语义色。
                      Icon(Icons.check_circle, color: colors.success, size: 20),
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
                      // R32 一.5：去固定 iOS 红，改 danger 语义色。
                      Icon(Icons.error_outline, color: colors.danger, size: 20),
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
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
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
                '连接 GitHub Releases 自动获取安装包；安卓按本机架构（arm64/arm32）'
                '自动选对应拆分包，Windows 电脑版自动下载更新包；'
                '下载后校验 SHA-256 哈希，通过才提示安装；'
                '支持后台下载（可关闭本页，完成后通知你）。'
                'Windows 版安装后自动替换并重启。',
                style: context.appText.artist,
              ),
            ],
          ),
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
