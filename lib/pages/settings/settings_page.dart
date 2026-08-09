import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_theme.dart';
import '../../core/theme/light_tokens.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/settings/settings_ui_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../widgets/shell/app_search_bar.dart';
import 'scene_editor_page.dart';
import 'server_settings_page.dart';

/// 设置页 · Master-Detail（主内容，背景/控制栏由 AppShell 提供）
///
/// 依据 `docs/PRD_UI_重构.md` §F 与 `docs/API_CONTRACT_FROZEN.md`：
///
/// - **P0-F1** 内容区一张设置卡片：圆角 24dp、底色 `#EEEEEE`（[AppColors.bgSurfaceSunken]）。
/// - **P0-F2** 卡片左侧 52dp 竖向分类栏（master），内含 5 个 48×76dp 分类
///   tile（26dp 图标在上、文字标签在下、间距 4dp、圆角 18dp）；右侧为详情区（detail）。
/// - **P0-F3** 点击 tile → 右侧详情切换；tile 置选中态（紫底白图标，沿用 Dock 规范）。
/// - **P0-F6** 「关于」分类展示应用名与版本号。
///
/// **五大分类按 Q5 已授权功能性重映射**（非设计稿原分类名）：
/// ① 播放 / ② 音源 / ③ 场景 / ④ 通知 / ⑤ 关于。
///
/// **一票否决项**：
/// - **R12** `ServerSettingsPage` 必须从设置页可达（音源分类入口行 `push` 整页）。
/// - **R13** `SceneEditorPage` 必须从设置页可达（场景分类入口行 `push` 整页，
///   构造需 `sceneId`，沿用旧值 `'rain'`）。
/// 两个大页面均**不内联**进详情区，仅在详情区放入口行 + `Navigator.push` 打开整页，
/// 可达性即达标。它们为旧深色主题，push 时用 [kLightTheme] 包一层低成本浅色化。
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 顶部搜索栏（.placeholder = 「搜索设置项」，P0-C1）
        AppSearchBar(
          hintText: '搜索设置项',
          query: query,
          onChanged: (String v) =>
              ref.read(searchQueryProvider(ShellPage.settings).notifier).state =
                  v,
        ),
        const SizedBox(height: 12),

        // 设置卡片：左 52dp 竖栏 + 右详情区（P0-F1 / F2）
        Expanded(
          child: Container(
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
        ),
      ],
    );
  }
}

/// 左侧 52dp 竖向分类导航栏（Master）。
///
/// 内含 5 个 [SettingsSection] tile，竖排；tile 间距 4dp、尺寸 48×76dp、圆角 18dp。
/// 选中 tile 复用 Dock 规范：紫底（[AppColors.accent]）+ 白图标
/// （[AppColors.iconOnAccent]）+ 紫字（[AppColors.textAccent]）。
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
              // 未命中搜索时整体降透明，但保留可点（P1-02）
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
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        Text(title, style: AppTextStyles.title),
        const SizedBox(height: AppSpace.lg),
        ...children,
      ],
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
          '管理外部流媒体与本地音源：Stelarith 服务器、局域网 Subsonic、'
          '本地目录与公开电台。',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: AppSpace.md),
        _EntryRow(
          icon: Icons.dns_outlined,
          title: '服务器与音源',
          subtitle: 'Stelarith-Admin / 局域网 Subsonic / 本地目录 / 电台',
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

/// ③ 场景：入口行 → 整页 `SceneEditorPage` + 配色 + 心情（R13）。
class _SceneDetail extends ConsumerWidget {
  const _SceneDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _DetailScaffold(
      title: SettingsSection.scene.title,
      children: <Widget>[
        const Text('调色盘：将在场景页右上角微光圆点提供（后续阶段）。', style: AppTextStyles.bodyMuted),
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
        const SizedBox(height: AppSpace.md),
        const Text(
          '心情：在「场景」Tab 选择雨夜 / 极光 / 壁炉等情绪，联动配色与音景。',
          style: AppTextStyles.bodyMuted,
        ),
      ],
    );
  }
}

/// ④ 通知：后台播放、锁屏控件、通知栏。
class _NotificationDetail extends ConsumerWidget {
  const _NotificationDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool background = ref.watch(_backgroundPlayProvider);
    final bool lockScreen = ref.watch(_lockScreenProvider);
    final bool notification = ref.watch(_notificationBarProvider);

    return _DetailScaffold(
      title: SettingsSection.notification.title,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('后台播放', style: AppTextStyles.body),
          subtitle: const Text('切到其它 App 时继续播放', style: AppTextStyles.artist),
          value: background,
          onChanged: (bool v) =>
              ref.read(_backgroundPlayProvider.notifier).state = v,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('锁屏控件', style: AppTextStyles.body),
          subtitle: const Text('锁屏显示播放 / 暂停 / 切歌', style: AppTextStyles.artist),
          value: lockScreen,
          onChanged: (bool v) =>
              ref.read(_lockScreenProvider.notifier).state = v,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('通知栏', style: AppTextStyles.body),
          subtitle: const Text('在通知栏常驻音乐卡片', style: AppTextStyles.artist),
          value: notification,
          onChanged: (bool v) =>
              ref.read(_notificationBarProvider.notifier).state = v,
        ),
      ],
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

// ─────────────────────────────────────────────────────────────────────────
// 通知分类的本地开关（UI 状态）。既有音频模块一（audio_service / audio_session）
// 已提供后台播放与锁屏能力；此处仅承载设置项的开合态，待音频层暴露 Provider
// 后可一行替换为真实真源，不影响本页结构。
// ─────────────────────────────────────────────────────────────────────────
final StateProvider<bool> _backgroundPlayProvider = StateProvider<bool>(
  (Ref ref) => true,
);
final StateProvider<bool> _lockScreenProvider = StateProvider<bool>(
  (Ref ref) => true,
);
final StateProvider<bool> _notificationBarProvider = StateProvider<bool>(
  (Ref ref) => true,
);
