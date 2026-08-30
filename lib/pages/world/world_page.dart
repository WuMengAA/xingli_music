/// 世界 Tab · 星璃世界入口。
///
/// 用户要求：世界首页直接把「重点端上来」——除了三个入口按钮，主体直接
/// **内嵌渲染存档列表**：列出全部存档（手动存档 + 仅自动检查点的世界），
/// 每个显示名称 + 最近保存时间 + 备份数，点击卡片直接进 [VoxelWorld3DPage]
/// （种子/选项从存档 world JSON 恢复）；完整管理（新建/恢复/导出/重命名/
/// 删除/备份/回滚/缩略图/背景）走顶部「我的存档」→ [VoxelSaveManagerPage]。
///
/// 对接入口（必须正确）：
/// - 我的存档 → [VoxelSaveManagerPage]（新建/恢复进入/导出/重命名/删除）
/// - 存档卡片 → [VoxelWorld3DPage]（seed/options/saveId/initialSaveData）
/// - 开放世界 → [VoxelLobbyPage]（联机大厅：创建/加入/局域网）
/// - 游戏设置 → [VoxelGameSettingsPage]（游戏画质/控制/音频设置）
library;

import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../pages/settings/voxel_game_settings_page.dart';
import '../../pages/settings/voxel_save_manager_page.dart';
import '../../pages/social/station_lobby_page.dart';
import '../../pages/voxel/voxel_lobby_page.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/notification/app_notify.dart';
import '../../widgets/voxel/voxel_save.dart';
import '../../widgets/voxel/voxel_world.dart';
import '../../widgets/voxel/voxel_world_view3d.dart' show VoxelWorld3DPage;

/// 存档快捷列表条目：存档元数据 + 备份数。
class _SaveEntry {
  const _SaveEntry(this.save, this.backupCount);

  final VoxelManualSaveMeta save;
  final int backupCount;
}

/// 世界页（底部 Dock「世界」Tab）· 星璃世界入口。
class WorldPage extends ConsumerStatefulWidget {
  const WorldPage({super.key});

  @override
  ConsumerState<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends ConsumerState<WorldPage> {
  late Future<List<_SaveEntry>> _savesFuture;

  @override
  void initState() {
    super.initState();
    _savesFuture = _loadSaves();
  }

  /// 手动存档 + 仅自动检查点，统一入口（与存档管理器同一数据源 [listAllSaves]）。
  Future<List<_SaveEntry>> _loadSaves() async {
    final List<VoxelManualSaveMeta> saves = await listAllSaves();
    final List<_SaveEntry> out = <_SaveEntry>[];
    for (final VoxelManualSaveMeta s in saves) {
      int backups = 0;
      try {
        backups = (await listBackups(s.id)).length;
      } catch (_) {
        // 备份枚举失败不阻塞列表
      }
      out.add(_SaveEntry(s, backups));
    }
    return out;
  }

  String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 直接进入某存档的世界（种子 / 选项从存档 world JSON 恢复，与管理器一致）。
  Future<void> _enterSave(VoxelManualSaveMeta s) async {
    // #511：优先本存档 id 检查点（最新自动进度），缺失回退手动存档。
    final Map<String, dynamic>? data =
        await readVoxelSaveForId(s.id) ?? await readManualSave(s.id);
    if (data == null) {
      if (mounted) appNotify(context, '存档损坏，无法恢复');
      return;
    }
    final dynamic wj = data['world'];
    final int seed = (wj is Map && wj['seed'] is int)
        ? wj['seed'] as int
        : VoxelWorld.defaultSeed;
    final WorldOptions opt =
        WorldOptions.fromJson(wj is Map ? wj['options'] : null);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoxelWorld3DPage(
          seed: seed,
          options: opt,
          survival: false,
          initialSaveData: data,
          saveId: s.id,
        ),
      ),
    );
    // 返回后刷新列表（进入世界会写自动检查点，最近保存时间 / 备份可能变化）。
    if (mounted) {
      setState(() {
        _savesFuture = _loadSaves();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: Terms.worldTitle,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            children: <Widget>[
              // 我的存档 → 完整存档管理器。
              _EntryRow(
                icon: Icons.public_rounded,
                label: Terms.manualSave,
                subtitle: '新建 / 恢复进入 / 导出 / 重命名 / 删除',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VoxelSaveManagerPage(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // 存档快捷列表：直接内嵌渲染，重点端上来。
              _buildSaveSection(),
              const SizedBox(height: AppSpace.md),
              // 开放世界 → 联机大厅（创建 / 加入 / 局域网）。
              _EntryRow(
                icon: Icons.language_rounded,
                label: Terms.freeExplore,
                subtitle: '进入实时体素世界，自由探索与建造',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VoxelLobbyPage(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // 电台 → 电台房大厅（cl15：创建/加入，公开/私密+模式+房间号）。
              _EntryRow(
                icon: Icons.radio_rounded,
                label: '电台',
                subtitle: '创建校园广播 / 一起听电台，或加入公开房间',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StationLobbyPage(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // 游戏设置 → 独立「包厢」游戏设置页。
              _EntryRow(
                icon: Icons.settings_outlined,
                label: Terms.worldRules,
                subtitle: '画面 · 操作 · 音频 · 性能偏好设置',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VoxelGameSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 存档快捷列表区块：加载中 / 空态 / 卡片列表。
  Widget _buildSaveSection() {
    return FutureBuilder<List<_SaveEntry>>(
      future: _savesFuture,
      builder: (
        BuildContext context,
        AsyncSnapshot<List<_SaveEntry>> snap,
      ) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final List<_SaveEntry> entries = snap.data ?? <_SaveEntry>[];
        if (entries.isEmpty) {
          return const _EmptySavesHint();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpace.xs,
                bottom: AppSpace.xs,
              ),
              child: Text(
                '最近存档（${entries.length}）',
                style: context.appText.caption.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ),
            for (final _SaveEntry e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _QuickSaveCard(
                  entry: e,
                  fmt: _fmt,
                  onEnter: () => _enterSave(e.save),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 入口行（玻璃卡）：图标 + 标题 + 副标题 + 箭头。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 18),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  color: c.accent.withValues(alpha: 0.16),
                ),
                child: Icon(icon, size: 24, color: c.accent),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  label,
                  style: context.appText.subtitle.copyWith(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 24, color: c.iconInactive),
            ],
          ),
        ),
      ),
    );
  }
}

/// 存档快捷卡片：缩略图 + 名称 + 最近保存时间 + 备份数，点击直接进入世界。
class _QuickSaveCard extends StatelessWidget {
  const _QuickSaveCard({
    required this.entry,
    required this.fmt,
    required this.onEnter,
  });

  final _SaveEntry entry;
  final String Function(DateTime) fmt;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    final VoxelManualSaveMeta s = entry.save;
    final DateTime recent = s.lastSavedAt ?? s.createdAt;
    final String? thumb = s.thumbnail ?? s.background;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEnter,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            color: c.bgSurface.withValues(alpha: 0.6),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: <Widget>[
              // 缩略图（缺省回退背景图；都没有用图标占位）。
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: thumb != null && File(thumb).existsSync()
                      ? Image.file(
                          File(thumb),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _thumbPlaceholder(c),
                        )
                      : _thumbPlaceholder(c),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      s.name,
                      style: context.appText.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '最近保存：${fmt(recent)} · ${entry.backupCount} 个备份',
                      style: context.appText.artist.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.play_circle_fill_rounded, size: 28, color: c.accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder(AppThemeColors c) {
    return Container(
      color: c.bgSurfaceSunken,
      child: Center(
        child: Icon(
          Icons.public_rounded,
          size: 24,
          color: c.textTertiary,
        ),
      ),
    );
  }
}

/// 无存档空态：友好引导去上方「我的存档」新建。
class _EmptySavesHint extends StatelessWidget {
  const _EmptySavesHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.lg,
        horizontal: AppSpace.md,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        color: context.appColors.bgSurfaceSunken.withValues(alpha: 0.6),
        border: Border.all(color: context.appColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.save_outlined,
            size: 36,
            color: context.appColors.textTertiary,
          ),
          const SizedBox(height: AppSpace.sm),
          Text('暂无存档', style: context.appText.body),
          const SizedBox(height: AppSpace.xs),
          Text(
            '点上方「我的存档」新建存档，或在存档管理页新建空白世界',
            style: context.appText.artist,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
