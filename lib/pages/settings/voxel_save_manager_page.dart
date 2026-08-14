/// ════════════════════════════════════════════════════════════════════════
/// 世界存档管理器（R26p）：主页设置里的专属界面，覆盖完整存档生命周期——
/// 新建（另存为 / 空白世界）、恢复（同一存档多个备份可分别恢复）、
/// 导出分享、重命名、删除（含全部备份）、导入。
///
/// 与游戏内「存档管理」弹层共享同一套 [voxel_save] 文件函数；恢复时把目标数据
/// 写入自动存档并带种子 push [VoxelWorld3DPage]，打开即完整加载（地形按种子重生）。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'dart:io' show Directory, File, FileSystemEntity;
import 'dart:math' show Random;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../widgets/voxel/voxel_save.dart';
import 'package:path_provider/path_provider.dart';
import '../../widgets/voxel/voxel_world.dart';
import '../../widgets/voxel/voxel_world_view3d.dart' show VoxelWorld3DPage;
import '../../widgets/notification/app_notify.dart';

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
    if (mounted) appNotify(context, msg);
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

  /// 新建对话框：名称 + **自定义种子**（数字，留空随机）+ cl29 世界选项
  /// （作弊 / 结构 / 浮空岛）。返回 (名称, 种子, 选项)。
  Future<(String, int, WorldOptions)?> _askNewSave(String title, String nameHint) async {
    final TextEditingController n = TextEditingController();
    final TextEditingController s = TextEditingController();
    // R28：新建存档默认关闭作弊与浮空岛（用户要求），结构默认开。
    bool cheats = false;
    bool structures = true;
    bool floating = false;
    final (String, int, WorldOptions)? res =
        await showDialog<(String, int, WorldOptions)>(
      context: context,
      builder: (BuildContext dctx) => StatefulBuilder(
        builder: (BuildContext dctx2, StateSetter set) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: n,
                autofocus: true,
                decoration: InputDecoration(hintText: nameHint, isDense: true),
                onSubmitted: (String v) => Navigator.of(dctx).pop(
                  (
                    v.trim(),
                    int.tryParse(s.text.trim()) ?? Random().nextInt(1 << 30),
                    WorldOptions(
                        cheats: cheats,
                        structures: structures,
                        floatingIslands: floating),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: s,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '世界种子（数字，留空随机）',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许作弊'),
                subtitle: const Text('开启后游戏内可切换生存 / 创造'),
                value: cheats,
                onChanged: (bool v) => set(() => cheats = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('生成结构'),
                subtitle: const Text('沙漠沙堡等确定性结构'),
                value: structures,
                onChanged: (bool v) => set(() => structures = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('浮空岛'),
                subtitle: const Text('悬空草顶石核团块'),
                value: floating,
                onChanged: (bool v) => set(() => floating = v),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(
                (
                  n.text.trim(),
                  int.tryParse(s.text.trim()) ?? Random().nextInt(1 << 30),
                  WorldOptions(
                      cheats: cheats,
                      structures: structures,
                      floatingIslands: floating),
                ),
              ),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    n.dispose();
    s.dispose();
    return res;
  }

  String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 新建存档：全新**随机或自定义种子**空白世界（不再复制当前存档——想备份
  /// 请用「备份当前世界」；想立即进新世界用「新建空白世界」）。
  Future<void> _newSave() async {
    final (String, int, WorldOptions)? r =
        await _askNewSave('新建存档', '存档名称（留空自动命名）');
    if (r == null || !mounted) return;
    final String name = r.$1;
    final int seed = r.$2;
    final WorldOptions opt = r.$3;
    final Map<String, dynamic> data = freshWorldSave(seed, opt);
    final String finalName =
        name.isEmpty ? '世界 ${_fmt(DateTime.now())}' : name;
    try {
      await writeManualSave(data, finalName);
      _snack('已新建存档「$finalName」（种子 $seed）');
    } catch (_) {
      _snack('新建失败');
    }
    await _refresh();
  }

  /// 新建空白世界：全新种子 + 立即进入。
  Future<void> _newBlankWorld() async {
    final (String, int, WorldOptions)? r =
        await _askNewSave('新建空白世界', '世界名称（留空自动命名）');
    if (r == null || !mounted) return;
    final String name = r.$1;
    final int seed = r.$2;
    final WorldOptions opt = r.$3;
    final Map<String, dynamic> data = freshWorldSave(seed, opt);
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
    _snack('已进入空白世界「$finalName」（种子 $seed）');
    // R28：作弊关 → 强制生存（不允许创造）；作弊开 → 默认创造（游戏内可切生存）。
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoxelWorld3DPage(
          seed: seed,
          options: opt,
          survival: !opt.cheats,
        ),
      ),
    );
  }

  /// R26r15：备份=快照「当前正在运行的世界」（自动存档），**不切换**世界——
  /// 备份后仍运行原存档，需手动在列表点「进入」才读取该备份。备份落到当前世界
  /// 所属存档（_meta.parent 优先，否则最近手动存档，否则新建「我的世界」），
  /// 保证「备份的备份还是备份」（平铺、不套娃）。这是唯一的备份入口，与游戏内
  /// 「备份当前世界」语义/文案完全一致。
  Future<void> _backupCurrent() async {
    final Map<String, dynamic>? cur = await readVoxelSave();
    String? parentId;
    if (cur != null &&
        cur['_meta'] is Map &&
        (cur['_meta'] as Map)['parent'] is String) {
      parentId = (cur['_meta'] as Map)['parent'] as String;
    }
    // 解析目标存档：优先当前世界所属父存档，否则最近手动存档，否则新建。
    String? targetId;
    if (parentId != null && (await readManualSave(parentId)) != null) {
      targetId = parentId;
    } else if (_saves.isNotEmpty) {
      targetId = _saves.first.id;
    }
    if (cur == null) {
      if (targetId == null) {
        // 既无运行世界也无存档：新建一个「我的世界」并备份。
        final Map<String, dynamic> data =
            freshWorldSave(VoxelWorld.defaultSeed);
        final String id = await writeManualSave(data, '我的世界');
        await createBackup(id);
        await _refresh();
        _snack('已新建并备份「我的世界」');
        return;
      }
      // 有存档但无运行世界：退化为快照最近存档。
      final Map<String, dynamic>? snap = await readManualSave(targetId);
      if (snap == null) {
        _snack('当前没有正在运行的世界可备份');
        return;
      }
      await createBackup(targetId);
      await _refresh();
      _snack('已备份当前世界 · 在列表点「进入」可读取');
      return;
    }
    await createBackup(targetId!);
    await _refresh();
    _snack('已备份当前世界 · 在列表点「进入」可读取');
  }

  /// 恢复（进入）某存档 / 备份：写入自动存档 + 带种子打开世界。
  Future<void> _enter(Map<String, dynamic>? data, String label) async {
    if (data == null || !mounted) {
      _snack('存档损坏，无法恢复');
      return;
    }
    // Bug④（#375）：写自动存档失败（存储满 / 权限 / 文件损坏）不能再向上抛，
    // 否则安卓「进入存档」即未捕获崩溃。降级为提示并仍允许进世界（世界自身
    // 的 30s 周期存档会再尝试落盘，玩家可正常游玩）。
    try {
      await writeVoxelSave(data);
    } catch (e) {
      debugPrint('[voxel-save] 进入存档前写盘失败: $e');
      _snack('存档写入失败，仍可进入（自动存档稍后重试）');
    }
    final dynamic wj = data['world'];
    final int seed = (wj is Map && wj['seed'] is int)
        ? wj['seed'] as int
        : VoxelWorld.defaultSeed;
    // cl29：从存档 world JSON 取回新建世界选项（作弊 / 结构 / 浮空岛）。
    final WorldOptions opt = WorldOptions.fromJson(wj is Map ? wj['options'] : null);
    if (!mounted) return;
    _snack('正在进入「$label」');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => VoxelWorld3DPage(
        seed: seed,
        options: opt,
        // R28：作弊关 → 强制生存（不允许创造）；作弊开 → 默认创造。
        survival: !opt.cheats,
        // R26fx：恢复玩家状态（位置/视角/编辑层/背包）——不再每次重置摄像头。
        initialSaveData: data,
      )),
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

  /// cl29：存档「更多 > 详细」——展示当前世界的基本信息 + 高级信息。
  Future<void> _showDetails(VoxelManualSaveMeta s) async {
    final Map<String, dynamic>? data = await readManualSave(s.id);
    if (!mounted) return;
    final dynamic wj = data?['world'];
    final Map<String, dynamic> w =
        wj is Map<String, dynamic> ? wj : <String, dynamic>{};
    final WorldOptions o = WorldOptions.fromJson(w['options']);
    final int seed = (w['seed'] is int) ? w['seed'] as int : VoxelWorld.defaultSeed;
    final int sizeX = (w['sizeX'] is int) ? w['sizeX'] as int : 0;
    final int sizeZ = (w['sizeZ'] is int) ? w['sizeZ'] as int : 0;
    final int maxY = (w['maxY'] is int) ? w['maxY'] as int : 0;
    final int waterLevel =
        (w['waterLevel'] is int) ? w['waterLevel'] as int : 0;
    final int edits = (w['edits'] is List) ? (w['edits'] as List).length : 0;
    final int lights = (w['lights'] is List) ? (w['lights'] as List).length : 0;
    final List<VoxelManualSaveMeta> bks =
        _backups[s.id] ?? <VoxelManualSaveMeta>[];
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext bctx) => ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          Text(s.name, style: context.appText.subtitle),
          const SizedBox(height: AppSpace.xs),
          Text('创建于 ${_fmt(s.createdAt)} · ${bks.length} 个备份',
              style: context.appText.artist),
          const SizedBox(height: AppSpace.md),
          Text('基本信息', style: context.appText.body),
          const SizedBox(height: AppSpace.xs),
          _InfoRow('世界种子', '$seed'),
          _InfoRow('地图尺寸', '$sizeX × $sizeZ'),
          _InfoRow('高度上限', '$maxY'),
          _InfoRow('水位', '$waterLevel'),
          _InfoRow('作弊', o.cheats ? '开启' : '关闭'),
          _InfoRow('结构生成', o.structures ? '开启' : '关闭'),
          _InfoRow('浮空岛', o.floatingIslands ? '开启' : '关闭'),
          const SizedBox(height: AppSpace.md),
          Text('高级信息', style: context.appText.body),
          const SizedBox(height: AppSpace.xs),
          _InfoRow('玩家编辑方块', '$edits'),
          _InfoRow('发光方块', '$lights'),
          _InfoRow('存档版本', '${data?['v'] ?? '—'}'),
        ],
      ),
    );
  }

  /// cl42·⑤：列出可作为「存档背景 / 缩略图」的取景照片。
  ///
  /// 只收 `captures/` 下**同名 .json 快照（seed+机位）存在的** PNG——
  /// 即体素世界拍照取景生成的场景照片，排除其它杂项 PNG，避免入口混入
  /// 无关截图。新→旧排序。
  Future<List<File>> _listScenePhotos() async {
    final Directory dir = await getApplicationSupportDirectory();
    final Directory capDir = Directory('${dir.path}/captures');
    final List<File> files = <File>[];
    if (await capDir.exists()) {
      await for (final FileSystemEntity e in capDir.list()) {
        if (e is! File) continue;
        final String p = e.path;
        if (!p.toLowerCase().endsWith('.png')) continue;
        // 仅保留带配对快照的场景照片，过滤掉非取景 PNG。
        final String jsonPath =
            p.replaceFirst(RegExp(r'\.png$', caseSensitive: false), '.json');
        if (await File(jsonPath).exists()) files.add(e as File);
      }
    }
    files.sort((File a, File b) => b.path.compareTo(a.path)); // 新→旧
    return files;
  }

  /// cl29·③：选场景截图 PNG 当存档背景；'__clear__' 清除；返回 null 取消。
  Future<void> _pickBackground(VoxelManualSaveMeta s) async {
    final List<File> files = await _listScenePhotos();
    final String? picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _BackgroundPicker(files: files, current: s.background),
    );
    if (picked == null) return;
    final String? path = picked == '__clear__' ? null : picked;
    await setSaveBackground(s.id, path);
    await _refresh();
    _snack(path == null ? '已清除背景' : '已设置场景截图为背景');
  }

  /// R26skel：选场景截图 PNG 当存档缩略图（1:1 128×128 前置显示）；
  /// '__clear__' 清除；返回 null 取消。
  Future<void> _pickThumbnail(VoxelManualSaveMeta s) async {
    final List<File> files = await _listScenePhotos();
    final String? picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _BackgroundPicker(
        files: files,
        current: s.thumbnail,
        title: '选择场景截图作为缩略图（1:1 128×128）',
      ),
    );
    if (picked == null) return;
    final String? path = picked == '__clear__' ? null : picked;
    await setSaveThumbnail(s.id, path);
    await _refresh();
    _snack(path == null ? '已清除缩略图' : '已设置场景截图为缩略图');
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
          Tooltip(
            message: '快照正在运行的世界（不切换，需手动「进入」读取）',
            child: TextButton.icon(
              onPressed: _backupCurrent,
              icon: const Icon(Icons.backup_outlined, size: 18),
              label: const Text('备份当前世界'),
            ),
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
                      onExport: () => _exportSave(s.id, s.name),
                      onDetails: () => _showDetails(s),
                      onSetBackground: () => _pickBackground(s),
                      onSetThumbnail: () => _pickThumbnail(s),
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
    required this.onExport,
    required this.onRename,
    required this.onDelete,
    required this.onDetails,
    required this.onSetBackground,
    required this.onSetThumbnail,
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
  final VoidCallback onExport;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onDetails;
  final VoidCallback onSetBackground;
  final VoidCallback onSetThumbnail;
  final Future<void> Function(String, String) onEnterBackup;
  final Future<void> Function(String, String) onExportBackup;
  final Future<void> Function(String) onDeleteBackup;
  final String Function(DateTime) fmt;

  @override
  Widget build(BuildContext context) {
    final String? bg = save.background;
    final String? thumb = save.thumbnail ?? save.background;
    return Container(
      decoration: BoxDecoration(
        color: bg != null ? Colors.black45 : context.appColors.bgSurface,
        borderRadius: AppRadius.brLg,
        image: bg != null
            ? DecorationImage(
                image: FileImage(File(bg)),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.42),
                  BlendMode.darken,
                ),
              )
            : null,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // R26skel：存档缩略图 1:1 128×128，前置显示。
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 128,
                  height: 128,
                  child: thumb != null && File(thumb).existsSync()
                      ? Image.file(
                          File(thumb),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _ThumbPlaceholder(),
                        )
                      : const _ThumbPlaceholder(),
                ),
              ),
              const SizedBox(width: AppSpace.md),
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
                    const SizedBox(height: 2),
                    Text(
                      save.lastSavedAt == null
                          ? '最近保存：—'
                          : '最近保存：${fmt(save.lastSavedAt!)}',
                      style: context.appText.artist.copyWith(
                        color: context.appColors.accent,
                      ),
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
              _Chip(icon: Icons.share_outlined, label: '导出', onTap: onExport),
              _Chip(icon: Icons.edit_outlined, label: '重命名', onTap: onRename),
              _Chip(icon: Icons.delete_outline, label: '删除', onTap: onDelete),
              _Chip(icon: Icons.info_outline, label: '详细', onTap: onDetails),
              _Chip(icon: Icons.image_outlined, label: '背景', onTap: onSetBackground),
              _Chip(icon: Icons.crop_square, label: '缩略图', onTap: onSetThumbnail),
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

/// R26skel：存档缩略图占位（无缩略图时显示图标）。
class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.appColors.bgSurfaceSunken,
      child: Center(
        child: Icon(
          Icons.public_rounded,
          size: 36,
          color: context.appColors.textTertiary,
        ),
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

/// 详情行（标签 + 值），用于「更多 > 详细」面板。
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: context.appText.artist)),
            Text(value, style: context.appText.body),
          ],
        ),
      );
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
          TextButton(onPressed: onEnter, child: const Text('进入')),
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

/// cl29·③：场景截图选择网格（作存档背景 / 缩略图）。点缩略图选其路径，点「清除」清空。
class _BackgroundPicker extends StatelessWidget {
  const _BackgroundPicker({required this.files, this.current, this.title});

  final List<File> files;
  final String? current;

  /// R26skel：标题（背景 / 缩略图可不同文案）。
  final String? title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Text(
                title ?? '选择场景截图作为背景',
                style: context.appText.body,
              ),
            ),
            if (files.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.md,
                  0,
                  AppSpace.md,
                  AppSpace.lg,
                ),
                child: Text(
                  '暂无截图，进入 3D 世界拍照取景后可在此选用。',
                  style: context.appText.artist,
                ),
              ),
            if (files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpace.sm,
                  crossAxisSpacing: AppSpace.sm,
                  children: <Widget>[
                    for (final File f in files)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(f.path),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              child: Image.file(f, fit: BoxFit.cover),
                            ),
                            if (current == f.path)
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: context.appColors.accent,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                              ),
                          ],
                        ),
                      ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop('__clear__'),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: context.appColors.border),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.block,
                                  color: context.appColors.iconPrimary),
                              const SizedBox(height: 4),
                              Text('清除', style: context.appText.artist),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.md),
          ],
        ),
      ),
    );
  }
}
