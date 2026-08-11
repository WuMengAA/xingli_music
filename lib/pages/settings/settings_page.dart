import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../providers/settings/performance_providers.dart';
import '../../providers/settings/settings_ui_providers.dart';
import '../../providers/shell/shell_providers.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/theme/theme_providers.dart';
import '../../services/audio/audio_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_chip.dart';
import '../../widgets/notification/notification_center.dart';
import '../../widgets/shell/app_search_bar.dart';
import '../../widgets/settings/llm_settings_sheet.dart';
import '../../widgets/settings/log_upload_sheet.dart';
import '../../widgets/sources/netease_login_sheet.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';
import 'scene_editor_page.dart';
import '../scene/custom_scene_list_page.dart';
import '../scene/voxel_sound_editor_page.dart';
import '../sources/netease_search_page.dart';
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

/// 左侧 52dp 竖向分类导航栏（Master · R21 重组）。
///
/// 按 [SettingsGroup] 分 7 组渲染：每组顶部小标（分组标题 + 图标），
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
            const SizedBox(height: 4),
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
        3,
      ),
      child: Row(
        children: <Widget>[
          Icon(group.icon, size: 13, color: context.appColors.textTertiary),
          const SizedBox(width: 4),
          // 分组标题长度可变（如「播放与音源」5 字），而 rail 固定 52dp、
          // 去掉左右 padding 后仅剩 44dp：必须 Flexible + 省略号兜底，
          // 否则窄屏/横屏下 Row 会 RenderFlex overflow。
          Flexible(
            child: Text(
              group.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: context.appText.tileLabel.copyWith(
                color: context.appColors.textTertiary,
                fontSize: 11,
              ),
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
        ? context.appColors.onAccent
        : context.appColors.iconInactive;
    final Color labelColor = selected
        ? context.appColors.accent
        : context.appColors.textSecondary;

    return SizedBox(
      width: AppSize.tileWidth,
      // v3 分组后 rail 多出 5 个分组小标，tile 由 76 收到 64；
      // 仍 ≥ Material 48dp 最小触控高度，勿再压缩。
      height: 64,
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
                color: selected ? context.appColors.accent : context.appColors.border,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Opacity(
              opacity: dimmed ? 0.4 : 1.0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(section.icon, size: 24, color: iconColor),
                  const SizedBox(height: 3),
                  Text(
                    section.label,
                    style: context.appText.tileLabel.copyWith(color: labelColor),
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
      case SettingsSection.audio:
        return const _AudioDetail();
      case SettingsSection.visual:
        return const _VisualDetail();
      case SettingsSection.notification:
        return const _NotificationDetail();
      case SettingsSection.experiment:
        return const _ExperimentDetail();
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
    return Material(
      // ListTile 需要在 DecoratedBox 内部找到最近 Material 祖先，
      // 否则「ListTile background color or ink splashes may be invisible」。
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: <Widget>[
          Text(title, style: context.appText.title),
          const SizedBox(height: AppSpace.lg),
          ...children,
        ],
      ),
    );
  }
}

/// 基础·音频：音量、静音、播放模式、音景 + 音源入口（R22 用户定版结构）。
class _AudioDetail extends ConsumerWidget {
  const _AudioDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double volume = ref.watch(musicVolumeProvider);
    final bool muted = ref.watch(musicMutedProvider);
    final double sVolume = ref.watch(soundscapeVolumeProvider);
    final bool sMuted = ref.watch(soundscapeMutedProvider);
    final double master = ref.watch(masterVolumeProvider);
    final double sfx = ref.watch(sfxVolumeProvider);
    // #167：白噪音取「生效来源」（跟随场景 / 全局播放）
    final WhiteNoiseState wnState = ref.watch(effectiveWhiteNoiseProvider);
    final bool wnFollows = ref.watch(whiteNoiseFollowsSceneProvider);
    final double world = ref.watch(worldSfxVolumeProvider);
    final double uiCue = ref.watch(uiCueVolumeProvider);
    final PlayMode mode = ref.watch(playModeProvider);
    final BalanceMode balance = ref.watch(balanceModeProvider);
    final NeteaseAuthState netease = ref.watch(neteaseAuthProvider);

    return _DetailScaffold(
      title: SettingsSection.audio.title,
      children: <Widget>[
        // ── 主音量（R23i：全局整体音量，乘所有通道）──
        _SliderRow(
          label: '主音量',
          concept: '所有分类的总输出',
          value: master,
          onChanged: (double v) {
            ref.read(masterVolumeProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setMasterVolume(v));
          },
        ),
        // ── 音乐（#170：规范分类名）──
        _SliderRow(
          label: AudioCategory.music.label,
          concept: AudioCategory.music.concept,
          value: volume,
          onChanged: (double v) {
            ref.read(musicVolumeProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setMusicVolume(v));
            unawaited(ref
                .read(audioServiceProvider)
                .playCategoryCue(AudioCategory.music));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('静音', style: context.appText.body),
          subtitle: Text('暂停音乐输出', style: context.appText.artist),
          value: muted,
          onChanged: (bool v) {
            ref.read(musicMutedProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setMusicMuted(v));
          },
        ),
        _PlayModeRow(mode: mode),
        _SliderRow(
          label: AudioCategory.soundscape.label,
          concept: AudioCategory.soundscape.concept,
          value: sVolume,
          onChanged: (double v) {
            ref.read(soundscapeVolumeProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setSoundscapeVolume(v));
            unawaited(ref
                .read(audioServiceProvider)
                .playCategoryCue(AudioCategory.soundscape));
          },
        ),
        // R23i：音效（SFX）通道音量
        _SliderRow(
          label: AudioCategory.sfx.label,
          concept: AudioCategory.sfx.concept,
          value: sfx,
          onChanged: (double v) {
            ref.read(sfxVolumeProvider.notifier).state = v;
            unawaited(ref.read(audioServiceProvider).setSfxVolume(v));
            unawaited(ref
                .read(audioServiceProvider)
                .playCategoryCue(AudioCategory.sfx));
          },
        ),
        // #170：世界空间音效通道音量
        _SliderRow(
          label: AudioCategory.worldSpatial.label,
          concept: AudioCategory.worldSpatial.concept,
          value: world,
          onChanged: (double v) {
            ref.read(worldSfxVolumeProvider.notifier).state = v;
            unawaited(ref
                .read(audioServiceProvider)
                .playCategoryCue(AudioCategory.worldSpatial));
          },
        ),
        // #170：提示音通道音量
        _SliderRow(
          label: AudioCategory.uiCue.label,
          concept: AudioCategory.uiCue.concept,
          value: uiCue,
          onChanged: (double v) {
            ref.read(uiCueVolumeProvider.notifier).state = v;
            unawaited(ref
                .read(audioServiceProvider)
                .playCategoryCue(AudioCategory.uiCue));
          },
        ),
        // #167：白噪音——独立通道，来源可选「跟随场景 / 全局播放」
        _SliderRow(
          label: AudioCategory.whiteNoise.label,
          concept: AudioCategory.whiteNoise.concept,
          value: wnState.volume,
          onChanged: (double v) {
            if (wnFollows) {
              unawaited(saveSceneWhiteNoise(ref, volume: v));
            } else {
              ref.read(whiteNoiseVolumeProvider.notifier).state = v;
            }
            unawaited(ref
                .read(audioServiceProvider)
                .playCategoryCue(AudioCategory.whiteNoise));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('白噪音跟随场景', style: context.appText.body),
          subtitle: Text(
            wnFollows
                ? '每个场景独立记忆白噪音开关与音量，换场景自动切换'
                : '全局播放：忽略场景设置，所有场景共用同一份白噪音',
            style: context.appText.artist,
          ),
          value: wnFollows,
          onChanged: (bool v) {
            ref.read(whiteNoiseFollowsSceneProvider.notifier).state = v;
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('白噪音', style: context.appText.body),
          subtitle: Text(
            wnFollows ? '开关写入当前场景' : '独立白噪音通道，叠加在音乐/背景声之上',
            style: context.appText.artist,
          ),
          value: wnState.on,
          onChanged: (bool v) {
            if (wnFollows) {
              unawaited(saveSceneWhiteNoise(ref, on: v));
            } else {
              ref.read(whiteNoiseEnabledProvider.notifier).state = v;
            }
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('背景声静音', style: context.appText.body),
          subtitle: Text('暂停场景背景声（音景）输出', style: context.appText.artist),
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
              Text('音量均衡', style: context.appText.body),
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
                style: context.appText.artist,
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
        const SizedBox(height: AppSpace.lg),

        // ── 音源 ──
        Text('音源', style: context.appText.body),
        const SizedBox(height: AppSpace.xs),
        Text(
          '管理外部流媒体与本地音源：${Terms.server}、局域网 Subsonic、'
          '本地目录与公开电台。',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.sm),
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
        const SizedBox(height: AppSpace.sm),
        _EntryRow(
          icon: Icons.cloud_outlined,
          title: '网易云音乐',
          subtitle: netease.isLoggedIn
              ? '已登录：${netease.account?.nickname ?? '网易云用户'}'
              : '未登录 · 应用内登录 / 粘贴 Cookie',
          onTap: () => showNeteaseLoginSheet(context),
        ),
        const SizedBox(height: AppSpace.sm),
        _EntryRow(
          icon: Icons.search_rounded,
          title: '网易云搜索',
          subtitle: '登录后搜索并在线播放网易云曲库',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NeteaseSearchPage(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 基础·画面：外观 + 场景 + 游戏 + 性能（R22 用户定版结构）。
class _VisualDetail extends ConsumerWidget {
  const _VisualDetail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String mode = ref.watch(themeModeNameProvider);
    final String skinId = ref.watch(themeSkinProvider);
    final PerformanceMode perf = ref.watch(performanceModeProvider);
    final FpsLimit fps = ref.watch(fpsLimitProvider);
    final EngineBackend backend = ref.watch(engineBackendProvider);
    final bool vulkanOk = ref.watch(vulkanSupportedProvider);
    final bool noise = ref.watch(noiseEnabledProvider);
    final double blur = ref.watch(glassBlurProvider);
    final bool bg = ref.watch(bgAnimationEnabledProvider);
    final bool liquid = ref.watch(liquidGlassEnabledProvider);

    return _DetailScaffold(
      title: SettingsSection.visual.title,
      children: <Widget>[
        // ═══ 外观 ═══
        Text('外观', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.xs),
        Text('主题模式', style: context.appText.body),
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
        Text(
          '浅色/深色主题由官方控件自动适配；深色下场景配色自动降低亮度。',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.lg),

        Text('皮肤', style: context.appText.body),
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
        Text(
          '皮肤决定主题主强调色（按钮 / 进度条 / 选中态 / Tab 高亮等）。',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.lg),

        Text('界面密度', style: context.appText.body),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          children: <Widget>[
            for (final UiDensity d in UiDensity.values)
              ChoiceChip(
                label: Text(d.label),
                selected: ref.watch(uiDensityProvider) == d,
                onSelected: (_) {
                  ref.read(uiDensityProvider.notifier).state = d;
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          '紧凑模式缩小 Dock、自动折叠次要面板，屏显更多内容。',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.lg),

        // ═══ 场景 ═══
        Text('场景', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.xs),
        _EntryRow(
          icon: Icons.auto_awesome_outlined,
          title: '场景编辑器',
          subtitle: '编辑自定义场景 · 导出场景包',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
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
        const SizedBox(height: AppSpace.lg),

        // ═══ 游戏 ═══
        Text('游戏', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.xs),
        _EntryRow(
          icon: Icons.view_in_ar_rounded,
          title: '3D 体素世界',
          subtitle: '进入 3D 视图 · 世界内空间音效 · AI 体素小人',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const VoxelWorld3DPage(),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        _EntryRow(
          icon: Icons.graphic_eq_rounded,
          title: '世界音效设置',
          subtitle: '水 / 风 / 叶 / 鸟 四轨 · 随机位变化的空间音效',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const VoxelSoundEditorPage(),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),

        // ═══ 性能与质量（预设）═══
        Text('性能与质量', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.xs),
        Text(
          '预设一键应用：性能（特效关 / 24fps）· 质量（特效全开 / 60fps）；'
          '下方可单独覆盖。',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.xs,
          children: <Widget>[
            for (final PerformanceMode m in PerformanceMode.values)
              ChoiceChip(
                label: Text(m == PerformanceMode.performance ? '性能优先' : '质量优先'),
                selected: perf == m,
                onSelected: (_) => _applyPerformancePreset(ref, m),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        // ── 播放引擎（S2 · media_kit 迁移）──
        Text('播放引擎', style: context.appText.body),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          children: <Widget>[
            for (final MusicEngine e in MusicEngine.values)
              ChoiceChip(
                label: Text(e.label),
                selected: ref.watch(musicEngineProvider) == e,
                onSelected: (_) {
                  ref.read(musicEngineProvider.notifier).state = e;
                },
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'just_audio：默认，Android 真 EQ；media_kit：全格式 / Hi-Res / '
          '无缝播放（EQ 走模拟层）· 切换即时生效',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.sm),
        Text('帧率限制', style: context.appText.body),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.xs,
          children: <Widget>[
            for (final FpsLimit f in FpsLimit.values)
              ChoiceChip(
                label: Text('${f.value} FPS'),
                selected: fps == f,
                onSelected: (_) {
                  ref.read(fpsLimitProvider.notifier).state = f;
                },
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '限制体素动画 / 可视化刷新率：24 最低耗、120 最流畅（低端机建议 24）。',
          style: context.appText.artist,
        ),
        const SizedBox(height: AppSpace.sm),

        // ── 体素区块 / LOD（R23m：16×16 区块，视距与 LOD 可调）──
        _ChunkStepperRow(
          label: '视距',
          value: ref.watch(viewDistanceChunksProvider),
          min: 2,
          max: 12,
          hint: '区块（1 区块 = 16 格），默认 4',
          onChanged: (int v) =>
              ref.read(viewDistanceChunksProvider.notifier).state = v,
        ),
        _ChunkStepperRow(
          label: 'LOD 起始',
          value: ref.watch(lodStartChunksProvider),
          min: 0,
          max: 6,
          hint: '距相机多少区块外开始降精度，默认 2',
          onChanged: (int v) =>
              ref.read(lodStartChunksProvider.notifier).state = v,
        ),
        _ChunkStepperRow(
          label: 'LOD 步长',
          value: ref.watch(lodStepChunksProvider),
          min: 1,
          max: 4,
          hint: '每 N 区块降一级精度（步长 ×2），默认 1',
          onChanged: (int v) =>
              ref.read(lodStepChunksProvider.notifier).state = v,
        ),
        const SizedBox(height: AppSpace.sm),

        // ── 图形后端（Windows）──
        if (!kIsWeb && Platform.isWindows) ...<Widget>[
          Text('图形后端', style: context.appText.body),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            children: <Widget>[
              for (final EngineBackend e in EngineBackend.values)
                ChoiceChip(
                  label: Text(e.label),
                  selected: backend == e,
                  // Vulkan 引擎不支持 → 灰显不可选（R22）
                  onSelected: (e == EngineBackend.impellerVulkan && !vulkanOk)
                      ? null
                      : (_) {
                          ref.read(engineBackendProvider.notifier).state = e;
                        },
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Vulkan 引擎暂不支持（Windows Impeller 仅 DX11）· 切换后重启生效',
            style: context.appText.artist,
          ),
          const SizedBox(height: AppSpace.xs),
          // 当前实际生效后端（main.cpp 启动时写入）
          ref.watch(engineBackendActiveProvider).when(
                data: (String v) => Text(
                  '当前生效：${engineBackendLabel(v)}（上次启动确定）',
                  style: context.appText.artist,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
          const SizedBox(height: AppSpace.sm),
        ],

        // ── 特效开关组 ──
        Text('特效', style: context.appText.body),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('噪点纹理', style: context.appText.body),
          subtitle: Text(noise ? '开' : '关（跟随档位或手动）',
              style: context.appText.artist),
          value: noise,
          onChanged: (bool v) {
            ref.read(noiseOverrideProvider.notifier).state = v;
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('玻璃模糊', style: context.appText.body),
          subtitle: Text(blur > 0 ? '强度 $blur' : '关', style: context.appText.artist),
          value: blur > 0,
          onChanged: (bool v) {
            ref.read(glassBlurOverrideProvider.notifier).state = v ? 12 : 0;
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('背景动画', style: context.appText.body),
          subtitle: Text(bg ? '开' : '关', style: context.appText.artist),
          value: bg,
          onChanged: (bool v) {
            ref.read(bgAnimationOverrideProvider.notifier).state = v;
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('液态玻璃（折射）', style: context.appText.body),
          subtitle: Text(liquid ? '开' : '关', style: context.appText.artist),
          value: liquid,
          onChanged: (bool v) {
            ref.read(liquidGlassOverrideProvider.notifier).state = v;
          },
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
        Text(
          '通知栏为静默常驻媒体通知（无声音无震动），播放中持续显示，'
          '暂停时不消失，可随时控制播放。',
          style: context.appText.bodyMuted,
        ),
        const SizedBox(height: AppSpace.md),
        // 后台播放 / 锁屏控件 / 通知栏 三个开关由 NotificationCenter 的
        // 「运行状态」卡统一承载，此处不要重复渲染（曾出现两组同名开关）。
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
                color: context.appColors.accentSoft,
                borderRadius: AppRadius.brMd,
              ),
              child: Icon(
                Icons.graphic_eq_rounded,
                size: 28,
                color: context.appColors.accent,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(SettingsPage.appName, style: context.appText.subtitle),
                  const SizedBox(height: 2),
                  Text(
                    '版本 ${AppVersion.display}',
                    style: context.appText.bodyMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        const _InfoRow(label: '应用名称', value: SettingsPage.appName),
        _InfoRow(label: '版本号', value: AppVersion.display),
        _InfoRow(label: '版本代号', value: AppVersion.brand),
        _InfoRow(
          label: '构建次数',
          value: '今日第 ${AppVersion.buildCount} 次（cl${AppVersion.buildCount.toString().padLeft(2, '0')}）',
        ),
        _InfoRow(label: '阶段', value: AppVersion.stage.label),
        _InfoRow(label: '语义版本', value: AppVersion.semver),
        const _InfoRow(label: '开源协议', value: 'MIT'),
        const SizedBox(height: AppSpace.lg),
        _EntryRow(
          icon: Icons.cloud_upload_outlined,
          title: '日志上报',
          subtitle: '把已脱敏日志发到自建日志服务（默认关闭）',
          onTap: () => showLogUploadSheet(context),
        ),
        const SizedBox(height: AppSpace.lg),
        Text('日志与开源信息见项目仓库 README。', style: context.appText.bodyMuted),
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
        _EntryRow(
          icon: Icons.smart_toy_outlined,
          title: '大模型设置',
          subtitle: '接入 OpenAI 兼容大模型（AI 陪伴优先 LLM 回复）',
          onTap: () => showLlmSettingsSheet(context),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: <Widget>[
            Text('同意状态', style: context.appText.body),
            const Spacer(),
            StateChip(
              tone: consent.agreed ? ChipTone.ok : ChipTone.retired,
              label: consent.agreed ? '已同意' : '未同意',
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          '同意后可在「探索」页进入实验；传感器 / 心情数据本地处理不上传。',
          style: context.appText.artist,
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
        Text('逐项启停', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.sm),
        for (final ExperimentItem item in items)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(item.name, style: context.appText.body),
            subtitle: Text(
              item.statusLabel,
              style: context.appText.artist,
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
    this.concept,
  });

  final String label;

  /// #170：概念小字（一句话说明这类声音是什么），为空则不显示。
  final String? concept;

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: context.appText.body),
              if (concept != null) ...<Widget>[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    concept!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
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
          Text('播放模式', style: context.appText.body),
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
              Icon(icon, size: AppSize.iconSm, color: context.appColors.iconPrimary),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: context.appText.body),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.appText.artist),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: AppSize.iconSm,
                color: context.appColors.iconInactive,
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
          Text(label, style: context.appText.bodyMuted),
          Text(value, style: context.appText.body),
        ],
      ),
    );
  }
}




/// 应用性能预设（R22）：切档位时若帧率仍是另一档位的默认值则联动切换；
/// 手动改过的帧率保留。特效默认跟随档位（override 为 null）。
void _applyPerformancePreset(WidgetRef ref, PerformanceMode m) {
  ref.read(performanceModeProvider.notifier).state = m;
  final FpsLimit current = ref.read(fpsLimitProvider);
  final FpsLimit otherDefault = m == PerformanceMode.performance
      ? FpsLimit.fps60
      : FpsLimit.fps24;
  if (current == otherDefault) {
    ref.read(fpsLimitProvider.notifier).state = defaultFpsFor(m);
  }
}

/// 区块参数行（R23m）：- / 值 / + 步进 + 说明。
class _ChunkStepperRow extends StatelessWidget {
  const _ChunkStepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String hint;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(label, style: context.appText.body),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                visualDensity: VisualDensity.compact,
                color: context.appColors.iconInactive,
                onPressed: value > min ? () => onChanged(value - 1) : null,
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: context.appText.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                visualDensity: VisualDensity.compact,
                color: context.appColors.iconInactive,
                onPressed: value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
          Text(hint, style: context.appText.artist),
        ],
      ),
    );
  }
}
