/// ════════════════════════════════════════════════════════════════════════
/// 世界存档管理器（R26p）：主页设置里的专属界面，覆盖完整存档生命周期——
/// 新建（另存为 / 空白世界）、恢复（同一存档多个备份可分别恢复）、
/// 导出分享、重命名、删除（含全部备份）、导入。
///
/// 与游戏内「存档管理」弹层共享同一套 [voxel_save] 文件函数；恢复时把目标数据
/// 写入自动存档并带种子 push [VoxelWorld3DPage]，打开即完整加载（地形按种子重生）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:io' show File;
import 'dart:math' show Random;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../widgets/voxel/voxel_save.dart';
import '../../widgets/voxel/voxel_world.dart';
import '../../widgets/voxel/voxel_world_view3d.dart' show VoxelWorld3DPage;

/// 世界存档管理器页。
class VoxelSaveManagerPage extends StatefulWidget {
  const VoxelSaveManagerPage({super.key});

  @override
  State<VoxelSaveManagerPage> createState() => _VoxelSaveManagerPageState();
}

class _VoxelSaveManagerPageState extends State<VoxelSaveManagerPage> {
  List<VoxelManualSaveMeta> _saves = <VoxelManualSaveMeta>[];
  final Map<String, List<VoxelManualSaveMeta>> _backups =
      <String, List<VoxelManualSaveMeta>>{};
  final Set<String> _expanded = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final List<VoxelManualSaveMeta> saves = await listManualSaves();
    final Map<String, List<VoxelManualSaveMeta>> bk =
        <String, List<VoxelManualSaveMeta>>{};
    for (final VoxelManualSaveMeta s in saves) {
      bk[s.id] = await listBackups(s.id);
    }
    if (mounted) {
      setState(() {
        _saves = saves;
        _backups.clear();
        _backups.addAll(bk);
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _askName(String title, String hint, [String initial = '']) async {
    final TextEditingController c = TextEditingController(text: initial);
    final String? res = await showDialog<String>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: hint, isDense: true),
          onSubmitted: (String v) => Navigator.of(dctx).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(c.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    c.dispose();
    return res;
  }

  Future<bool> _confirm(String title, String content) async {
    final bool? r = await showDialog<bool>(
      context: context,
      builder: (BuildContext dctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return r == true;
  }

  String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 新建存档：把「当前正在游玩的世界」另存为命名存档（无则生成空白世界）。
  Future<void> _newSave() async {
    final String? name = await _askName('新建存档', '存档名称（留空自动命名）');
    if (name == null || !mounted) return;
    final Map<String, dynamic>? cur = await readVoxelSave();
    final Map<String, dynamic> data =
        cur ?? freshWorldSave(VoxelWorld.defaultSeed);
    final String finalName =
        name.isEmpty ? '世界 ${_fmt(DateTime.now())}' : name;
    try {
      await writeManualSave(data, finalName);
      _snack('已新建存档「$finalName」');
    } catch (_) {
      _snack('新建失败');
    }
    await _refresh();
  }

  /// 新建空白世界：全新种子 + 立即进入。
  Future<void> _newBlankWorld() async {
    final String? name = await _askName('新建空白世界', '世界名称（留空自动命名）');
    if (name == null || !mounted) return;
    final int seed = Random().nextInt(1 << 30);
    final Map<String, dynamic> data = freshWorldSave(seed);
    final String finalName =
        name.isEmpty ? '空白世界 ${_fmt(DateTime.now())}' : name;
    String? id;
    try {
      id = await writeManualSave(data, finalName);
      await writeVoxelSave(data);
    } catch (_) {
      _snack('新建失败');
      return;
    }
    if (!mounted) return;
    _snack('已进入空白世界「$finalName」');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VoxelWorld3DPage(seed: seed)),
    );
  }

  /// 备份当前世界到最近一个存档（无存档则先建「我的世界」）。
  Future<void> _backupCurrent() async {
    if (_saves.isEmpty) {
      final Map<String, dynamic> data =
          await readVoxelSave() ?? freshWorldSave(VoxelWorld.defaultSeed);
      final String id = await writeManualSave(data, '我的世界');
      await createBackup(id);
    } else {
      await createBackup(_saves.first.id);
    }
    await _refresh();
    _snack('已备份当前世界');
  }

  /// 恢复（进入）某存档 / 备份：写入自动存档 + 带种子打开世界。
  Future<void> _enter(Map<String, dynamic>? data, String label) async {
    if (data == null || !mounted) {
      _snack('存档损坏，无法恢复');
      return;
    }
    await writeVoxelSave(data);
    final dynamic wj = data['world'];
    final int seed = (wj is Map && wj['seed'] is int)
        ? wj['seed'] as int
        : VoxelWorld.defaultSeed;
    if (!mounted) return;
    _snack('正在进入「$label」');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VoxelWorld3DPage(seed: seed)),
    );
  }

  Future<void> _enterSave(String id, String name) async {
    final Map<String, dynamic>? data = await readManualSave(id);
    await _enter(data, name);
  }

  Future<void> _enterBackup(String bakId, String name) async {
    final List<String> parts = bakId.split('|');
    if (parts.length != 2) return;
    final Map<String, dynamic>? data = await readBackup(parts[0], parts[1]);
    await _enter(data, name);
  }

  Future<void> _exportSave(String id, String name) async {
    try {
      final File f = await manualSaveFile(id);
      if (!await f.exists()) {
        _snack('文件不存在');
        return;
      }
      await Share.shareXFiles(
        <XFile>[XFile(f.path)],
        subject: name,
        text: '星璃音乐 · 体素世界存档「$name」',
      );
    } catch (_) {
      _snack('导出失败');
    }
  }

  Future<void> _exportBackup(String bakId, String name) async {
    final List<String> parts = bakId.split('|');
    if (parts.length != 2) return;
    try {
      final File f = await backupFile(parts[0], parts[1]);
      if (!await f.exists()) {
        _snack('文件不存在');
        return;
      }
      await Share.shareXFiles(
        <XFile>[XFile(f.path)],
        subject: name,
        text: '星璃音乐 · 体素世界备份「$name」',
      );
    } catch (_) {
      _snack('导出失败');
    }
  }

  Future<void> _import() async {
    final FilePickerResult? res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    final String? path = res?.files.single.path;
    if (path == null || !mounted) return;
    final String? id = await importSave(File(path));
    if (id == null) {
      _snack('导入失败：文件不是有效存档');
      return;
    }
    await _refresh();
    _snack('已导入存档');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.bgSurfaceSunken,
      appBar: AppBar(
        backgroundColor: context.appColors.bgSurface,
        foregroundColor: context.appColors.textPrimary,
        title: Text('世界存档', style: context.appText.subtitle),
        elevation: 0,
        actions: <Widget>[
          TextButton.icon(
            onPressed: _backupCurrent,
            icon: const Icon(Icons.backup_outlined, size: 18),
            label: const Text('备份'),
          ),
          TextButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: const Text('导入'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSave,
        icon: const Icon(Icons.add),
        label: const Text('新建存档'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _saves.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.save_outlined,
                            size: 48, color: context.appColors.textTertiary),
                        const SizedBox(height: AppSpace.sm),
                        Text('暂无存档', style: context.appText.body),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          '点右下「新建存档」把当前世界存为命名存档；'
                          '或「+ 新建空白世界」开新地图。',
                          style: context.appText.artist,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  itemCount: _saves.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpace.md),
                  itemBuilder: (BuildContext ctx, int i) {
                    final VoxelManualSaveMeta s = _saves[i];
                    final List<VoxelManualSaveMeta> bks =
                        _backups[s.id] ?? <VoxelManualSaveMeta>[];
                    final bool expanded = _expanded.contains(s.id);
                    return _SaveCard(
                      save: s,
                      backups: bks,
                      expanded: expanded,
                      onToggle: () => setState(() {
                        if (expanded) {
                          _expanded.remove(s.id);
                        } else {
                          _expanded.add(s.id);
                        }
                      }),
                      onEnter: () => _enterSave(s.id, s.name),
                      onBackup: () async {
                        await createBackup(s.id);
                        await _refresh();
                        _snack('已备份到「${s.name}」');
                      },
                      onExport: () => _exportSave(s.id, s.name),
                      onRename: () async {
                        final String? n =
                            await _askName('重命名存档', '新名称', s.name);
                        if (n == null || n.isEmpty || !mounted) return;
                        await renameManualSave(s.id, n);
                        await _refresh();
                        _snack('已重命名为「$n」');
                      },
                      onDelete: () async {
                        final bool ok = await _confirm(
                          '删除存档',
                          '确定删除「${s.name}」及其 ${bks.length} 个备份？此操作不可恢复。',
                        );
                        if (!ok || !mounted) return;
                        await deleteSaveWithBackups(s.id);
                        _expanded.remove(s.id);
                        await _refresh();
                        _snack('已删除「${s.name}」');
                      },
                      onEnterBackup: _enterBackup,
                      onExportBackup: _exportBackup,
                      onDeleteBackup: (String bakId) async {
                        final List<String> p = bakId.split('|');
                        if (p.length != 2) return;
                        await deleteBackup(p[0], p[1]);
                        await _refresh();
                        _snack('已删除该备份');
                      },
                      fmt: _fmt,
                    );
                  },
                ),
    );
  }
}

/// 单个存档卡片。
class _SaveCard extends StatelessWidget {
  const _SaveCard({
    required this.save,
    required this.backups,
    required this.expanded,
    required this.onToggle,
    required this.onEnter,
    required this.onBackup,
    required this.onExport,
    required this.onRename,
    required this.onDelete,
    required this.onEnterBackup,
    required this.onExportBackup,
    required this.onDeleteBackup,
    required this.fmt,
  });

  final VoxelManualSaveMeta save;
  final List<VoxelManualSaveMeta> backups;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEnter;
  final VoidCallback onBackup;
  final VoidCallback onExport;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final Future<void> Function(String, String) onEnterBackup;
  final Future<void> Function(String, String) onExportBackup;
  final Future<void> Function(String) onDeleteBackup;
  final String Function(DateTime) fmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.bgSurface,
        borderRadius: AppRadius.brLg,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(save.name, style: context.appText.body),
                    const SizedBox(height: 2),
                    Text(
                      '${fmt(save.createdAt)} · ${backups.length} 个备份',
                      style: context.appText.artist,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onEnter,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('进入'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: <Widget>[
              _Chip(icon: Icons.backup_outlined, label: '备份', onTap: onBackup),
              _Chip(icon: Icons.share_outlined, label: '导出', onTap: onExport),
              _Chip(icon: Icons.edit_outlined, label: '重命名', onTap: onRename),
              _Chip(icon: Icons.delete_outline, label: '删除', onTap: onDelete),
              if (backups.isNotEmpty)
                _Chip(
                  icon: expanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  label: expanded ? '收起备份' : '展开备份',
                  onTap: onToggle,
                ),
            ],
          ),
          if (expanded && backups.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            const Divider(),
            const SizedBox(height: AppSpace.xs),
            Text('备份（可分别恢复）', style: context.appText.artist),
            const SizedBox(height: AppSpace.xs),
            for (final VoxelManualSaveMeta b in backups)
              _BackupTile(
                backup: b,
                onEnter: () => onEnterBackup(b.id, b.name),
                onExport: () => onExportBackup(b.id, b.name),
                onDelete: () => onDeleteBackup(b.id),
                fmt: fmt,
              ),
          ],
        ],
      ),
    );
  }
}

/// 操作小药丸。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: context.appColors.border),
          borderRadius: AppRadius.brMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: context.appColors.iconPrimary),
            const SizedBox(width: 4),
            Text(label, style: context.appText.body),
          ],
        ),
      ),
    );
  }
}

/// 备份行。
class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.backup,
    required this.onEnter,
    required this.onExport,
    required this.onDelete,
    required this.fmt,
  });

  final VoxelManualSaveMeta backup;
  final VoidCallback onEnter;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final String Function(DateTime) fmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.history, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(fmt(backup.createdAt), style: context.appText.body),
          ),
          TextButton(onPressed: onEnter, child: const Text('恢复')),
          TextButton(onPressed: onExport, child: const Text('导出')),
          TextButton(
            onPressed: onDelete,
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
