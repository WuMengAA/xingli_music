import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_theme.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/experiment.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../providers/settings/settings_ui_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_chip.dart';
import '../../widgets/notification/notification_center.dart';
import '../../widgets/shell/app_search_bar.dart';
import 'scene_editor_page.dart';
import '../scene/custom_scene_list_page.dart';
import '../scene/voxel_sound_editor_page.dart';
import 'server_settings_page.dart';

/// 设置页 · Master-Detail（v2 M1 接入 PageScaffold；M4/M6/M2 分类更新）。
///
/// 六分类（v2 A1 已裁决新增第 6 槽「实验」）：
/// ① 播放 / ② 音源 / ③ 场景 / ④ 通知中心 / ⑤ 关于 / ⑥ 实验。
///
/// **一票否决项**：
/// - **R12** `ServerSettingsPage` 必须从设置页可达（音源分类入口行 `push` 整页）。
/// - **R13** `SceneEditorPage` 必须从设置页可达（场景分类入口行 `push` 整页）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 应用展示名（P0-F6）。
  static const String appName = '星璃音乐空间';

  /// 应用版本号（P0-F6）。与 `pubspec.yaml` 的 `version` 保持同步。
  static const String appVersion = '0.1.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String query = ref.watch(searchQueryProvider(ShellPage.settings));
    final SettingsSection section = ref.watch(settingsSectionProvider);
    final List<SettingsSection> matches = ref.watch(
      settingsSectionMatchesProvider,
    );

    return PageScaffold(
      title: '设置',
      search: AppSearchBar(
        hintText: '搜索设置项',
        query: query,
        onChanged: (String v) =>
            ref.read(searchQueryProvider(ShellPage.settings).notifier).state = v,
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurfaceSunken,
          borderRadius: AppRadius.brLg,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ── Master：左侧竖向分类导航栏 ─────────────
            _CategoryRail(
              selected: section,
              matches: matches,
              onSelect: (SettingsSection s) =>
                  ref.read(settingsSectionProvider.notifier).state = s,
            ),

            // ── Detail：右侧详情区 ─────────────────────
            Expanded(child: _SectionDetail(section: section)),
          ],
        ),
      ),
    );
  }
}

/// 左侧 52dp 竖向分类导航栏（Master）。
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.selected,
    required this.matches,
    required this.onSelect,
  });

  final SettingsSection selected;
  final List<SettingsSection> matches;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<SettingsSection> items = SettingsSection.values;
    return Container(
      width: AppSize.rail,
      color: AppColors.bgRail,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpace.xs),
        itemBuilder: (BuildContext context, int i) {
          final SettingsSection s = items[i];
          final bool isSelected = s == selected;
          // P1-02：搜索未命中该分类时弱化（保留槽位，避免误以为页面损坏）
          final bool dimmed = !matches.contains(s);
          return Align(
            alignment: Alignment.center,
            child: _CategoryTile(
              section: s,
              selected: isSelected,
              dimmed: dimmed,
              onTap: () => onSelect(s),
            ),
          );
        },
      ),
    );
  }
}

/// 单个分类 tile（48×76dp）：26dp 图标在上、文字标签在下。
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.section,
    required this.selected,
    this.dimmed = false,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = selected
        ? AppColors.iconOnAccent
        : AppColors.iconInactive;
    final Color labelColor = selected
        ? AppColors.textAccent
        : AppColors.textSecondary;

    return SizedBox(
      width: AppSize.tileWidth,
      height: AppSize.tileHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brMd,
          child: AnimatedContainer(
            duration: AppMotion.tab,
            curve: AppMotion.ease,
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : AppColors.bgTile,
              borderRadius: AppRadius.brMd,
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.borderDefault,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Opacity(
              opacity: dimmed ? 0.4 : 1.0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(section.icon, size: AppSize.icon, color: iconColor),
                  const SizedBox(height: 6),
                  Text(
                    section.label,
                    style: AppTextStyles.tileLabel.copyWith(color: labelColor),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧详情区（Detail）：按当前分类渲染不同内容。
class _SectionDetail extends StatelessWidget {
  const _SectionDetail({required this.section});

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case SettingsSection.playback:
        return const _PlaybackDetail();
      case SettingsSection.source:
        return const _SourceDetail();
      case SettingsSection.scene:
        return const _SceneDetail();
      case SettingsSection.notification:
        return const _NotificationDetail();
      case SettingsSection.about:
        return const _AboutDetail();
      case SettingsSection.experiment:
        return const _ExperimentDetail();
    }
  }
}

/// 详情区标题 + 列表通用骨架。
class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      // ListTile 需要在 DecoratedBox 内部找到最近 Material 祖先，
      // 否则「ListTile background color or ink splashes may be invisible」。
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          Text(title, style: AppTextStyles.title),
          const SizedBox(height: AppSpace.lg),
          ...children,
        ],
      ),
    );
  }
}

/// ① 播放：音量、静音、播放模式、音景音量。
class _PlaybackDetail extends ConsumerWidget {
  const _PlaybackDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double volume = ref.watch(musicVolumeProvider);
    final bool muted = ref.watch(musicMutedProvider);
    final double sVolume = ref.watch(soundscapeVolumeProvider);
    final bool sMuted = ref.watch(soundscapeMutedProvider);
    final PlayMode mode = ref.watch(playModeProvider);

    return _DetailScaffold(
      title: SettingsSection.playback.title,
      children: <Widget>[
        _SliderRow(
          label: '音量',
          value: volume,
          onChanged: (double v) {
            ref.read(musicVolumeProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setMusicVolume(v));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('静音', style: AppTextStyles.body),
          subtitle: const Text('暂停音乐输出', style: AppTextStyles.artist),
          value: muted,
          onChanged: (bool v) {
            ref.read(musicMutedProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setMusicMuted(v));
          },
        ),
        _PlayModeRow(mode: mode),
        _SliderRow(
          label: '音景音量',
          value: sVolume,
          onChanged: (double v) {
            ref.read(soundscapeVolumeProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setSoundscapeVolume(v));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('音景静音', style: AppTextStyles.body),
          subtitle: const Text('暂停环境音景输出', style: AppTextStyles.artist),
          value: sMuted,
          onChanged: (bool v) {
            ref.read(soundscapeMutedProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setSoundscapeMuted(v));
          },
        ),
      ],
    );
  }
}

/// ② 音源：入口行 → 整页 `ServerSettingsPage`（R12）。
class _SourceDetail extends ConsumerWidget {
  const _SourceDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailScaffold(
      title: SettingsSection.source.title,
      children: <Widget>[
        const Text(
          '管理外部流媒体与本地音源：${Terms.server}、局域网 Subsonic、'
          '本地目录与公开电台。',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: AppSpace.md),
        _EntryRow(
          icon: Icons.dns_outlined,
          title: '${Terms.server}与${Terms.source}',
          subtitle: '本地目录 / Subsonic / 公开电台 分组管理',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              // 低成本浅色化：用全局浅色主题包一层（不改动页面内部实现）
              builder: (_) =>
                  Theme(data: kLightTheme, child: const ServerSettingsPage()),
            ),
          ),
        ),
      ],
    );
  }
}

/// ③ 场景：入口行 → 整页 `SceneEditorPage` + 自定义场景 + 配色（R13）。
class _SceneDetail extends ConsumerWidget {
  const _SceneDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailScaffold(
      title: SettingsSection.scene.title,
      children: <Widget>[
        const Text(
          '自定义场景与配色：在场景页右上角微光圆点进入配色面板。',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: AppSpace.md),
        _EntryRow(
          icon: Icons.auto_awesome_outlined,
          title: '场景编辑器',
          subtitle: '编辑自定义场景 · 导出场景包',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Theme(
                data: kLightTheme,
                // R13：场景编辑器必须可达；构造需要 sceneId，沿用旧值 'rain'
                child: const SceneEditorPage(sceneId: 'rain'),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        _EntryRow(
          icon: Icons.collections_bookmark_outlined,
          title: '自定义场景管理',
          subtitle: '列出 / 新建 / 编辑自定义场景（含默认 BGM 选曲）',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Theme(
                data: kLightTheme,
                child: const CustomSceneListPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        _EntryRow(
          icon: Icons.grid_view_rounded,
          title: '2.5D 音效编辑器',
          subtitle: '类我的世界：摆放音效块，试听并保存独立音效层',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Theme(
                data: kLightTheme,
                child: const VoxelSoundEditorPage(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ④ 通知中心（v2 M6 三区块）。
class _NotificationDetail extends ConsumerWidget {
  const _NotificationDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailScaffold(
      title: SettingsSection.notification.title,
      children: const <Widget>[NotificationCenter()],
    );
  }
}

/// ⑤ 关于：应用名与版本号（P0-F6）。
class _AboutDetail extends StatelessWidget {
  const _AboutDetail();

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: SettingsSection.about.title,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: AppRadius.brMd,
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                size: 28,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(SettingsPage.appName, style: AppTextStyles.subtitle),
                  const SizedBox(height: 2),
                  Text(
                    '版本 ${SettingsPage.appVersion}',
                    style: AppTextStyles.bodyMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        const _InfoRow(label: '应用名称', value: SettingsPage.appName),
        const _InfoRow(label: '版本号', value: SettingsPage.appVersion),
        const _InfoRow(label: '开源协议', value: 'MIT'),
        const SizedBox(height: AppSpace.lg),
        const Text('日志与开源信息见项目仓库 README。', style: AppTextStyles.bodyMuted),
      ],
    );
  }
}

/// ⑥ 实验管理（v2 M2 · P1-M2-5 / A1 已裁决新增第 6 槽）。
class _ExperimentDetail extends ConsumerWidget {
  const _ExperimentDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExperimentConsent consent = ref.watch(experimentConsentProvider);
    final List<ExperimentItem> items = ref.watch(experimentsProvider);

    return _DetailScaffold(
      title: SettingsSection.experiment.title,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('同意状态', style: AppTextStyles.body),
            const Spacer(),
            StateChip(
              tone: consent.agreed ? ChipTone.ok : ChipTone.retired,
              label: consent.agreed ? '已同意' : '未同意',
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        const Text(
          '同意后可在「探索」页进入实验；传感器 / 心情数据本地处理不上传。',
          style: AppTextStyles.artist,
        ),
        const SizedBox(height: AppSpace.md),
        // 撤销同意
        OutlinedButton.icon(
          onPressed: consent.agreed
              ? () async {
                  await ref.read(experimentConsentProvider.notifier).revoke();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已撤销同意，退出全部实验')),
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('撤销同意'),
        ),
        const SizedBox(height: AppSpace.lg),
        Text('逐项启停', style: AppTextStyles.subtitle),
        const SizedBox(height: AppSpace.sm),
        for (final ExperimentItem item in items)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(item.name, style: AppTextStyles.body),
            subtitle: Text(
              item.statusLabel,
              style: AppTextStyles.artist,
            ),
            value: consent.isEnabled(item),
            onChanged: (bool v) => ref
                .read(experimentConsentProvider.notifier)
                .setEnabled(item.id, v),
          ),
      ],
    );
  }
}

/// 详情区：滑块行（音量类）。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppTextStyles.body),
          Slider(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 详情区：播放模式选择器（顺序 / 倒序 / 随机 / 单曲循环）。
class _PlayModeRow extends ConsumerWidget {
  const _PlayModeRow({required this.mode});

  final PlayMode mode;

  static const List<PlayMode> _order = <PlayMode>[
    PlayMode.order,
    PlayMode.reverse,
    PlayMode.shuffle,
    PlayMode.loop,
  ];

  static String _label(PlayMode m) => switch (m) {
        PlayMode.order => '顺序',
        PlayMode.reverse => '倒序',
        PlayMode.shuffle => '随机',
        PlayMode.loop => '单曲循环',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('播放模式', style: AppTextStyles.body),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            children: <Widget>[
              for (final PlayMode m in _order)
                ChoiceChip(
                  label: Text(_label(m)),
                  selected: m == mode,
                  onSelected: (_) =>
                      ref.read(playbackActionsProvider).setMode(m),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 详情区：入口行（点击整页 push，用于 R12 / R13）。
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
    return Material(
      color: AppColors.bgCard,
      borderRadius: AppRadius.brMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brMd,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: <Widget>[
              Icon(icon, size: AppSize.iconSm, color: AppColors.iconPrimary),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTextStyles.body),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.artist),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: AppSize.iconSm,
                color: AppColors.iconInactive,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情区：键值信息行（关于页用）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: AppTextStyles.bodyMuted),
          Text(value, style: AppTextStyles.body),
        ],
      ),
    );
  }
}
