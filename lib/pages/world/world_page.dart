/// 世界 Tab · 星璃世界入口。
///
/// 视觉对齐画布「Screen · 星璃世界」(3:194)：
/// 顶部氛围光晕 + 标题 + 创建按钮 → 「我的存档」2×2 玻璃卡网格（**真实存档**）
/// → 「开放世界」入口行 → 「游戏设置」入口行。
///
/// 2026-08-18 cl03：移除画布占位的四张**硬编码示例存档**（星河群岛/霓虹都市/…
/// 均为假数据、不可删、挤占「存档创建」），改为读取真实手动存档
/// （[listManualSaves]）；无存档时显示空态引导创建，不再伪造世界列表。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../pages/settings/voxel_game_settings_page.dart';
import '../../pages/settings/voxel_save_manager_page.dart';
import '../../pages/voxel/voxel_lobby_page.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/liquid_glass.dart';
import '../../widgets/voxel/voxel_save.dart';
import '../../core/terms/naming_dict.dart';

/// 世界页（底部 Dock「世界」Tab）。
class WorldPage extends ConsumerStatefulWidget {
  const WorldPage({super.key});

  @override
  ConsumerState<WorldPage> createState() => _WorldPageState();
}

class _WorldPageState extends ConsumerState<WorldPage> {
  Future<List<VoxelManualSaveMeta>>? _savesFuture;

  @override
  void initState() {
    super.initState();
    _savesFuture = listManualSaves();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;

    // 创建按钮（80×40，强调色描边玻璃按钮）。
    final Widget createButton = InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoxelSaveManagerPage()),
      ),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 80,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 1),
        ),
        child: Text(
          '+ 创建',
          style: context.appText.button.copyWith(color: accent),
        ),
      ),
    );

    return PageScaffold(
      title: Terms.world,
      actions: <Widget>[createButton],
      body: Stack(
        children: <Widget>[
          // 氛围光晕（装饰，跟随主题强调色，非整页背景）。
          Positioned(
            top: -20,
            left: 100,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.14),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _sectionLabel(context, '我的存档'),
                const SizedBox(height: 12),
                FutureBuilder<List<VoxelManualSaveMeta>>(
                  future: _savesFuture,
                  builder:
                      (BuildContext context,
                          AsyncSnapshot<List<VoxelManualSaveMeta>> snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return _skeletonGrid(context);
                    }
                    final List<VoxelManualSaveMeta> saves =
                        snap.data ?? const <VoxelManualSaveMeta>[];
                    if (saves.isEmpty) return _emptyState(context);
                    return GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 15,
                      childAspectRatio: 165 / 200,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: <Widget>[
                        for (final VoxelManualSaveMeta s in saves)
                          _WorldCard(
                            save: s,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const VoxelSaveManagerPage(),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),
                _sectionLabel(context, '开放世界'),
                const SizedBox(height: 12),
                _EntryRow(
                  icon: Icons.language_rounded,
                  title: '开放世界',
                  subtitle: '进入实时体素世界，自由探索与建造',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const VoxelLobbyPage()),
                  ),
                ),
                const SizedBox(height: 28),
                _sectionLabel(context, '游戏设置'),
                const SizedBox(height: 12),
                _EntryRow(
                  icon: Icons.settings_outlined,
                  title: '游戏设置',
                  subtitle: '画面·操作·音频·性能偏好设置',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const VoxelGameSettingsPage(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 加载中的 2×2 骨架占位（保持版式不跳动）。
  static Widget _skeletonGrid(BuildContext context) {
    final Color accent = context.appColors.accent;
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 15,
      childAspectRatio: 165 / 200,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: <Widget>[
        for (int i = 0; i < 4; i++)
          LiquidGlass(
            radius: 20,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: accent.withValues(alpha: 0.08),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 14,
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: accent.withValues(alpha: 0.10),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: accent.withValues(alpha: 0.08),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 无存档空态：引导创建，不再伪造世界列表。
  static Widget _emptyState(BuildContext context) {
    final Color accent = context.appColors.accent;
    final Color muted = context.appColors.textSecondary;
    return LiquidGlass(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: <Widget>[
          Icon(Icons.public_rounded, size: 40, color: accent.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            '还没有存档',
            style: context.appText.subtitle.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            '点右上角「+ 创建」新建一个世界',
            textAlign: TextAlign.center,
            style: context.appText.caption.copyWith(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  /// 区块小标题（15 / w600，跟随主题主文字色）。
  static Text _sectionLabel(BuildContext context, String text) => Text(
        text,
        style: context.appText.subtitle.copyWith(fontSize: 15),
      );
}

/// 世界存档玻璃卡（165×200）：封面 + 名称 + 最近保存时间（真实存档数据）。
class _WorldCard extends StatelessWidget {
  const _WorldCard({required this.save, required this.onTap});

  final VoxelManualSaveMeta save;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    final Color accentSoft = context.appColors.accentSoft;
    final Color muted = context.appColors.textSecondary;
    final DateTime t = save.lastSavedAt ?? save.createdAt;
    return LiquidGlass(
      radius: 20,
      padding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 封面占位（强调色渐变，跟随主题）。
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: <Color>[accent, accentSoft],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                save.name,
                style: context.appText.subtitle.copyWith(fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                _relTime(t),
                style: context.appText.caption.copyWith(fontSize: 11, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前 / 日期。
  static String _relTime(DateTime t) {
    final Duration d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    if (d.inDays < 7) return '${d.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

/// 入口行（345×96 玻璃卡）：图标 + 标题 + 副标题 + 箭头。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    final Color tertiary = context.appColors.textTertiary;
    return LiquidGlass(
      radius: 18,
      padding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accent.withValues(alpha: 0.16),
                ),
                child: Icon(icon, size: 24, color: accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: context.appText.subtitle.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: context.appText.caption.copyWith(fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 24, color: tertiary),
            ],
          ),
        ),
      ),
    );
  }
}
