import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/theme/theme_skins.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/experiment.dart';
import '../../pages/explore/experiments/equalizer_page.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../providers/settings/notification_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/settings/settings_ui_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../providers/theme/theme_providers.dart';
import '../../services/audio/audio_service.dart';
import '../../services/permission_service.dart';
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
          // R16：容器底色跟随主题
          color: context.appColors.bgSurfaceSunken,
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

/// 左侧 52dp 竖向分类导航栏（Master · v3 分组）。
///
/// 按 [SettingsGroup] 分 5 组渲染：每组顶部小标（分组标题 + 图标），
/// 组内是该组包含的 SettingsSection tile。点击 tile 仍按原 SettingsSection
/// 切换详情（保留搜索/详情逻辑）。
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
    return Container(
      width: AppSize.rail,
      // R16：左侧分类栏底色跟随主题
      color: context.appColors.bgSurfaceSunken,
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          for (final SettingsGroup g in SettingsGroup.values) ...<Widget>[
            _GroupHeader(group: g),
            for (final SettingsSection s in g.sections)
              // P1-02：搜索未命中该分类时弱化（保留槽位，避免误以为页面损坏）
              _CategoryTile(
                section: s,
                selected: s == selected,
                dimmed: !matches.contains(s),
                onTap: () => onSelect(s),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }
}

/// 分组小标：图标 + 2 字标题（v3 整理新增）。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final SettingsGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xs,
        AppSpace.xs,
        AppSpace.xs,
        AppSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(group.icon, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            group.label,
            style: AppTextStyles.tileLabel.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ],
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
              // R16：选中紫/未选中底色跟随主题
              color: selected ? context.appColors.accent : context.appColors.bgSurfaceSunken,
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
      case SettingsSection.appearance:
        return const _AppearanceDetail();
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
    final BalanceMode balance = ref.watch(balanceModeProvider);

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
        // R15：音量均衡（高保真 / 普通）
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('音量均衡', style: AppTextStyles.body),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                children: <Widget>[
                  for (final BalanceMode m in BalanceMode.values)
                    ChoiceChip(
                      label: Text(m == BalanceMode.hifi ? '高保真' : '普通'),
                      selected: balance == m,
                      onSelected: (_) {
                        ref.read(balanceModeProvider.notifier).state = m;
                        unawaited(
                            ref.read(audioServiceProvider).setBalanceMode(m));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                balance == BalanceMode.hifi
                    ? '保留原始动态，无任何增益处理'
                    : '响度归一化 + 轻度压缩，低音量内容更清晰',
                style: AppTextStyles.artist,
              ),
            ],
          ),
        ),
        // R7/R8：EQ 入口（R16：跟随全局主题）
        _EntryRow(
          icon: Icons.graphic_eq_rounded,
          title: '均衡器（10 段）',
          subtitle: '31Hz ~ 16kHz · 7 组预设 · Android 真 EQ',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const EqualizerPage(),
            ),
          ),
        ),
        // 低端设备优化：性能模式（Wear OS / 低端机发热控制）
        _PerformanceModeSection(),
      ],
    );
  }
}

/// 性能模式设置（低端设备优化 · 三档视觉开销）。
///
/// 省电：关噪点 + 关玻璃模糊（降发热最明显）；
/// 均衡（默认）：噪点 + 低模糊；流畅：全特效。
class _PerformanceModeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PerformanceMode mode = ref.watch(performanceModeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bolt_rounded,
                  size: AppSize.iconSm, color: AppColors.iconPrimary),
              const SizedBox(width: AppSpace.sm),
              const Text('性能模式', style: AppTextStyles.body),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            children: <Widget>[
              for (final PerformanceMode m in PerformanceMode.values)
                ChoiceChip(
                  label: Text(switch (m) {
                    PerformanceMode.powerSave => '省电',
                    PerformanceMode.balanced => '均衡',
                    PerformanceMode.smooth => '流畅',
                  }),
                  selected: mode == m,
                  onSelected: (_) {
                    ref.read(performanceModeProvider.notifier).state = m;
                  },
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            switch (mode) {
              PerformanceMode.powerSave =>
                '省电：关闭噪点与玻璃模糊，动画最快，发热最低（手表推荐）',
              PerformanceMode.balanced =>
                '均衡：保留噪点与低强度玻璃模糊，兼顾观感与发热',
              PerformanceMode.smooth =>
                '流畅：全特效（噪点 + 满强度玻璃模糊）',
            },
            style: AppTextStyles.artist,
          ),
        ],
      ),
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
          // R16：移除 kLightTheme 强制包裹，子页跟随全局明暗主题
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ServerSettingsPage(),
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
              // R16：移除 kLightTheme 强制包裹，跟随全局明暗主题
              builder: (_) => const SceneEditorPage(sceneId: 'rain'),
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
              builder: (_) => const CustomSceneListPage(),
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
              builder: (_) => const VoxelSoundEditorPage(),
            ),
          ),
        ),
      ],
    );
  }
}

/// ④ 通知中心（v2 M6 三区块）+ R13 权限申请 / R14 说明。
class _NotificationDetail extends ConsumerWidget {
  const _NotificationDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailScaffold(
      title: SettingsSection.notification.title,
      children: <Widget>[
        // R13：权限申请入口（不依赖 adb）
        _EntryRow(
          icon: Icons.shield_outlined,
          title: '权限与授权',
          subtitle: '申请通知 / 存储 / 媒体读取权限（Android 13+ 分级）',
          onTap: () async {
            final bool ok = await PermissionService.requestAll();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok ? '权限已全部授予' : '部分权限未授予，已打开系统设置'),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpace.sm),
        // R14：静默通知说明
        const Text(
          '通知栏为静默常驻媒体通知（无声音无震动），播放中持续显示，'
          '暂停时不消失，可随时控制播放。',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: AppSpace.md),
        // 后台播放开关：关闭后不注册后台媒体服务（无通知栏常驻），
        // 切后台可能被系统回收播放 —— 省电 / 低端设备推荐关闭
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('后台播放', style: AppTextStyles.body),
          subtitle: const Text('关闭后不常驻通知栏，节省后台资源（重启生效）', style: AppTextStyles.artist),
          value: ref.watch(backgroundPlayProvider),
          onChanged: (bool v) {
            ref.read(backgroundPlayProvider.notifier).state = v;
          },
        ),
        const SizedBox(height: AppSpace.sm),
        const NotificationCenter(),
      ],
    );
  }
}

/// ⑤ 关于：应用名与版本号（P0-F6 / R18-R20）。
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
                    '版本 ${AppVersion.display}',
                    style: AppTextStyles.bodyMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        const _InfoRow(label: '应用名称', value: SettingsPage.appName),
        _InfoRow(label: '版本号', value: AppVersion.display),
        _InfoRow(label: '阶段', value: AppVersion.stage.label),
        _InfoRow(label: '语义版本', value: AppVersion.semver),
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
      // R16：入口行卡片底色跟随主题
      color: context.appColors.bgCard,
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


/// 外观：主题（明暗 / 跟随系统）+ 皮肤（R16）。
class _AppearanceDetail extends ConsumerWidget {
  const _AppearanceDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String mode = ref.watch(themeModeNameProvider);
    final String skinId = ref.watch(themeSkinProvider);

    return _DetailScaffold(
      title: SettingsSection.appearance.title,
      children: <Widget>[
        const Text('主题模式', style: AppTextStyles.body),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          children: <Widget>[
            for (final (String v, String label) in <(String, String)>[
              ('system', '跟随系统'),
              ('light', '浅色'),
              ('dark', '深色'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: mode == v,
                onSelected: (_) {
                  ref.read(themeModeNameProvider.notifier).state = v;
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        const Text(
          '浅色/深色主题由官方控件自动适配；深色下场景配色自动降低亮度。',
          style: AppTextStyles.artist,
        ),
        const SizedBox(height: AppSpace.lg),

        const Text('皮肤', style: AppTextStyles.body),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: <Widget>[
            for (final ThemeSkin skin in ThemeSkins.all)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: skin.primary,
                  radius: 8,
                ),
                label: Text(skin.name),
                selected: skinId == skin.id,
                onSelected: (_) {
                  ref.read(themeSkinProvider.notifier).state = skin.id;
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        const Text(
          '皮肤决定主题主强调色（按钮 / 进度条 / 选中态 / Tab 高亮等）。',
          style: AppTextStyles.artist,
        ),
      ],
    );
  }
}
