import '../../core/theme/app_theme_colors.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/local_dir_config.dart';
import '../../models/server_config.dart';
import '../../models/source_health.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/local_dir_providers.dart';
import '../../providers/audio/server_config_provider.dart';
import '../../providers/audio/source_health_providers.dart';
import '../../services/music_sources/radio_source.dart';
import '../../services/music_sources/subsonic_source.dart';
import '../../widgets/common/state_chip.dart';
import '../../widgets/notification/app_notify.dart';

/// 音源管理页（v2 M4 · P0-M4-1 ~ P0-M4-3 瘦身重写）。
///
/// 原 `ServerSettingsPage`（515 行）中的**非音源区块**（全局播放 / 粒子 /
/// 关于 / 高级）已全部迁出，本页只做纯音源管理：
/// 三组卡片 = **本地目录 / 自建服务器（Subsonic）/ 公开电台**。
///
/// R12 保持：设置页「音源」分类单入口 → push 本页。
/// 音源条目健康状态用 [StateChip] 展示（P1-M4-4，连接中 / 正常 / 失败 +
/// 上次测试时间）。
class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  final TextEditingController _dirCtrl = TextEditingController();

  @override
  void dispose() {
    _dirCtrl.dispose();
    super.dispose();
  }

  Future<void> _addDir() async {
    final String p = _dirCtrl.text.trim();
    if (p.isEmpty) return;
    await ref.read(localDirConfigsProvider.notifier).add(p);
    _dirCtrl.clear();
    _invalidateLibrary();
  }

  void _invalidateLibrary() {
    ref.invalidate(musicLibraryProvider);
    ref.invalidate(effectiveMusicLibraryProvider);
  }

  Future<void> _toggleDir(LocalDirConfig d, bool v) async {
    await ref.read(localDirConfigsProvider.notifier).setEnabled(d.path, v);
    _invalidateLibrary();
  }

  Future<void> _removeDir(LocalDirConfig d) async {
    await ref.read(localDirConfigsProvider.notifier).remove(d.path);
    ref.read(sourceHealthProvider.notifier).remove(d.path);
    _invalidateLibrary();
  }

  Future<void> _testServer(ServerConfig c) async {
    final SourceHealthNotifier health =
        ref.read(sourceHealthProvider.notifier);
    health.startTest(c.name);
    final bool ok = c.type == SourceType.subsonic
        ? await SubsonicSource(c).testConnection()
        : await RadioSource(tags: c.tags, sourceId: c.name).testConnection();
    if (ok) {
      health.markOk(c.name);
    } else {
      health.markFailed(c.name, detail: '连接失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<LocalDirConfig> dirs = ref.watch(localDirConfigsProvider);
    final List<ServerConfig> configs = ref.watch(serverConfigsProvider);
    final List<ServerConfig> servers =
        configs.where((ServerConfig c) => c.type == SourceType.subsonic).toList();
    final List<ServerConfig> radios =
        configs.where((ServerConfig c) => c.type == SourceType.radio).toList();

    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: context.appColors.bgPage,
        foregroundColor: context.appColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.appColors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(Terms.source, style: context.appText.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          // ── 本地目录 ──────────────────────────────────────
          _GroupCard(
            title: '本地目录',
            icon: Icons.folder_rounded,
            addLabel: '添加目录',
            onAdd: () => _showAddDirSheet(),
            children: <Widget>[
              if (dirs.isEmpty)
                const _EmptyHint('尚未添加本地目录'),
              for (final LocalDirConfig d in dirs) _dirTile(d),
            ],
          ),
          const SizedBox(height: AppSpace.lg),

          // ── 自建服务器（Subsonic）────────────────────────
          _GroupCard(
            title: '${Terms.server}（Subsonic）',
            icon: Icons.storage_rounded,
            addLabel: '添加${Terms.server}',
            onAdd: () => _showServerSheet(null),
            children: <Widget>[
              if (servers.isEmpty)
                const _EmptyHint('尚未配置自建服务器'),
              for (final ServerConfig c in servers) _serverTile(c),
            ],
          ),
          const SizedBox(height: AppSpace.lg),

          // ── 公开电台 ─────────────────────────────────────
          _GroupCard(
            title: '公开电台',
            icon: Icons.radio_rounded,
            addLabel: '添加电台',
            onAdd: () => _showRadioSheet(null),
            children: <Widget>[
              if (radios.isEmpty)
                const _EmptyHint('尚未配置公开电台'),
              for (final ServerConfig c in radios) _serverTile(c),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
        ],
      ),
    );
  }

  // ── 本地目录 ─────────────────────────────────────────────

  Future<void> _showAddDirSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('添加本地目录', style: context.appText.subtitle),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: _dirCtrl,
                  style: context.appText.body,
                  decoration: InputDecoration(
                    labelText: '如 d:/Music/我的音乐',
                    labelStyle: context.appText.hint,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                // 系统文件管理器选取目录（桌面 Windows 原生对话框 /
                // Android SAF DocumentsUI；选完回填输入框）
                OutlinedButton.icon(
                  onPressed: () => _pickDir(sheetContext),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text('浏览…', style: context.appText.button),
                ),
                const SizedBox(height: AppSpace.md),
                FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _addDir();
                  },
                  child: const Text(Terms.add),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 弹出系统文件选择器选目录，回填 [_dirCtrl]。
  ///
  /// - 桌面（Windows / Linux / macOS）：返回真实文件系统路径，直接用。
  /// - Android：file_picker 走 SAF 返回 `content://.../tree/<docId>` URI，
  ///   解码成真实路径（`primary:Music` → `/storage/emulated/0/Music`），
  ///   供 [LocalDirMusicSource] 的 `Directory(path)` 扫描；解码失败提示手动输入。
  Future<void> _pickDir(BuildContext sheetContext) async {
    final String? picked = await FilePicker.getDirectoryPath();
    if (picked == null || !sheetContext.mounted) return; // 用户取消
    final String path = _toRealPath(picked);
    if (path.isEmpty) {
      appNotify(sheetContext, '该目录无法转换为本地路径，请手动输入');
      return;
    }
    _dirCtrl.text = path;
  }

  /// 把 file_picker 返回值转成可扫描的真实路径。
  ///
  /// - 普通路径原样返回。
  /// - SAF tree URI（`content://com.android.externalstorage.documents/tree/
  ///   primary%3AMusic`）解码为 `/storage/emulated/0/Music`；`home%3A...`
  ///   与其它 document provider 无法映射时返回空串。
  static String _toRealPath(String picked) {
    if (!picked.startsWith('content://')) return picked;

    final Uri? uri = Uri.tryParse(picked);
    final String? tree = uri?.pathSegments
        .where((String s) => s.isNotEmpty)
        .last; // 例: primary%3AMusic
    if (tree == null) return '';
    final String doc = Uri.decodeComponent(tree);
    if (doc.startsWith('primary:')) {
      return '/storage/emulated/0/${doc.substring('primary:'.length)}';
    }
    return ''; // home: / SD 卡等无法简单映射 → 提示手动输入
  }

  Widget _dirTile(LocalDirConfig d) {
    return _EntryTile(
      icon: Icons.folder_outlined,
      title: d.path,
      subtitle: '已启用' ,
      switchValue: d.enabled,
      onSwitch: (bool v) => _toggleDir(d, v),
      onEdit: null,
      onDelete: () => _removeDir(d),
      onTest: null,
    );
  }

  // ── 服务器 / 电台 ────────────────────────────────────────

  Future<void> _showServerSheet(ServerConfig? editing) =>
      _showServerConfigSheet(editing, isRadio: false);

  Future<void> _showRadioSheet(ServerConfig? editing) =>
      _showServerConfigSheet(editing, isRadio: true);

  Future<void> _showServerConfigSheet(ServerConfig? editing,
      {required bool isRadio}) async {
    final TextEditingController nameCtrl =
        TextEditingController(text: editing?.name ?? '');
    final TextEditingController urlCtrl =
        TextEditingController(text: editing?.baseUrl ?? '');
    final TextEditingController userCtrl =
        TextEditingController(text: editing?.user ?? '');
    final TextEditingController pwdCtrl =
        TextEditingController(text: editing?.password ?? '');
    final TextEditingController tagsCtrl =
        TextEditingController(text: (editing?.tags ?? const ['ambient']).join(', '));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpace.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  editing != null ? '编辑${isRadio ? '电台' : '服务器'}' : '新增${isRadio ? '电台' : '服务器'}',
                  style: context.appText.subtitle,
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: nameCtrl,
                  style: context.appText.body,
                  decoration: InputDecoration(
                    labelText: '名称（唯一标识）',
                    labelStyle: context.appText.hint,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                if (!isRadio) ...<Widget>[
                  TextField(
                    controller: urlCtrl,
                    style: context.appText.body,
                    decoration: InputDecoration(
                      labelText: '服务器地址（http://IP:4533）',
                      labelStyle: context.appText.hint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextField(
                    controller: userCtrl,
                    style: context.appText.body,
                    decoration: InputDecoration(
                      labelText: '用户名',
                      labelStyle: context.appText.hint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  TextField(
                    controller: pwdCtrl,
                    obscureText: true,
                    style: context.appText.body,
                    decoration: InputDecoration(
                      labelText: '密码',
                      labelStyle: context.appText.hint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...<Widget>[
                  TextField(
                    controller: tagsCtrl,
                    style: context.appText.body,
                    decoration: InputDecoration(
                      labelText: '标签（逗号分隔，如 ambient, jazz）',
                      labelStyle: context.appText.hint,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          final ServerConfig cfg = _buildServerConfig(
                            editing: editing,
                            isRadio: isRadio,
                            name: nameCtrl.text.trim(),
                            url: urlCtrl.text.trim(),
                            user: userCtrl.text.trim(),
                            password: pwdCtrl.text,
                            tags: tagsCtrl.text,
                          );
                          _testServer(cfg);
                        },
                        child: const Text(Terms.testConnection),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          final ServerConfig cfg = _buildServerConfig(
                            editing: editing,
                            isRadio: isRadio,
                            name: nameCtrl.text.trim(),
                            url: urlCtrl.text.trim(),
                            user: userCtrl.text.trim(),
                            password: pwdCtrl.text,
                            tags: tagsCtrl.text,
                          );
                          await ref
                              .read(serverConfigsProvider.notifier)
                              .addOrUpdate(cfg);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                          _invalidateLibrary();
                        },
                        child: Text(editing != null ? Terms.save : Terms.add),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ServerConfig _buildServerConfig({
    required ServerConfig? editing,
    required bool isRadio,
    required String name,
    required String url,
    required String user,
    required String password,
    required String tags,
  }) {
    final List<String> tagList = tags
        .split(',')
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
    return ServerConfig(
      type: isRadio ? SourceType.radio : SourceType.subsonic,
      name: name,
      baseUrl: url,
      user: user,
      password: password,
      enabled: editing?.enabled ?? true,
      tags: tagList.isNotEmpty ? tagList : const ['ambient'],
    );
  }

  Widget _serverTile(ServerConfig c) {
    final SourceHealth health =
        ref.watch(sourceHealthProvider.select((Map<String, SourceHealth> m) =>
            m[c.name] ?? const SourceHealth(status: SourceHealthStatus.unknown)));

    return _EntryTile(
      icon: c.type == SourceType.subsonic
          ? Icons.storage_outlined
          : Icons.radio_outlined,
      title: c.name,
      subtitle: c.type == SourceType.subsonic
          ? (c.baseUrl.isEmpty ? '未填地址' : c.baseUrl)
          : '标签：${c.tags.join(', ')}',
      health: health,
      switchValue: c.enabled,
      onSwitch: (bool v) =>
          ref.read(serverConfigsProvider.notifier).setEnabled(c.name, v),
      onEdit: () => c.type == SourceType.subsonic
          ? _showServerSheet(c)
          : _showRadioSheet(c),
      onDelete: () async {
        await ref.read(serverConfigsProvider.notifier).remove(c.name);
        ref.read(sourceHealthProvider.notifier).remove(c.name);
        _invalidateLibrary();
      },
      onTest: () => _testServer(c),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 小组件
// ─────────────────────────────────────────────────────────────────────────

/// 音源分组卡片（P0-M4-2）。
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.icon,
    required this.addLabel,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String addLabel;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: context.appColors.bgSurfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: AppSize.iconSm, color: context.appColors.iconPrimary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(title, style: context.appText.subtitle),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: Text(addLabel),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          ...children,
        ],
      ),
    );
  }
}

/// 音源条目行：开关 / 编辑 / 删除 / 测试连接 + 健康 StateChip。
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.switchValue,
    required this.onSwitch,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
    this.health,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool switchValue;
  final ValueChanged<bool> onSwitch;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTest;
  final SourceHealth? health;

  @override
  Widget build(BuildContext context) {
    final SourceHealth? h = health;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: AppSize.iconSm, color: context.appColors.textTertiary),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title,
                        style: context.appText.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(subtitle,
                        style: context.appText.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Switch(value: switchValue, onChanged: onSwitch),
            ],
          ),
          Row(
            children: <Widget>[
              if (h != null) ...<Widget>[
                StateChip(tone: _toneOf(h.status), label: h.statusLabel),
                const SizedBox(width: AppSpace.xs),
                Text('上次 ${h.lastTestedLabel}',
                    style: context.appText.caption),
              ],
              const Spacer(),
              if (onEdit != null)
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: context.appColors.textTertiary),
                  onPressed: onEdit,
                ),
              if (onTest != null)
                IconButton(
                  icon: Icon(Icons.network_check_rounded,
                      size: 18, color: context.appColors.textTertiary),
                  tooltip: Terms.testConnection,
                  onPressed: onTest,
                ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: context.appColors.danger),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  ChipTone _toneOf(SourceHealthStatus status) => switch (status) {
        SourceHealthStatus.connecting => ChipTone.connecting,
        SourceHealthStatus.ok => ChipTone.ok,
        SourceHealthStatus.failed => ChipTone.failed,
        SourceHealthStatus.unknown => ChipTone.retired,
      };
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Text(text, style: context.appText.bodyMuted),
    );
  }
}
