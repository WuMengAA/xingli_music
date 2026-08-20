import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_version.dart';
import '../../core/terms/naming_dict.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../core/theme/theme_skins.dart';
import '../../models/experiment.dart';
import '../../pages/explore/experiments/equalizer_page.dart';
import '../../providers/audio/audio_providers.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../providers/explore/experiment_providers.dart';
import '../../providers/settings/settings_persistence_providers.dart';
import '../../providers/settings/performance_providers.dart';
import '../../providers/sources/netease_provider.dart';
import '../../providers/theme/theme_providers.dart';
import '../../repositories/settings_repository.dart';
import '../../services/audio/audio_service.dart';
import '../../services/ota_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/common/page_scaffold.dart';
import '../../widgets/common/state_chip.dart';
import '../../widgets/notification/app_notify.dart';
import '../../widgets/notification/notification_center.dart';
import '../../widgets/settings/llm_settings_sheet.dart';
import '../../widgets/settings/log_upload_sheet.dart';
import '../../widgets/settings/version_update_sheet.dart';
import '../../widgets/sources/netease_login_sheet.dart';
import '../scene/custom_scene_list_page.dart';
import 'scene_editor_page.dart';
import 'server_settings_page.dart';
import 'voxel_game_settings_page.dart';

/// 设置页（v2 画布重构 · 匹配 Ardot「Screen · 设置」3:288）。
///
/// 单栏滚动 + 五张毛玻璃分组卡：**音频 / 画面 / 通知中心 / 实验 / 关于**，
/// 卡片顺序与画布 y 轴一致（音频 → 画面 → 通知中心 → 实验 → 关于）。
///
/// 画布仅给到分组与入口行的层级示意，实际业务控件（滑块 / 选择器 /
/// 开关 / 入口）全部保留并落入对应分组，provider 接线不变。
///
/// **一票否决项（保留）**：
/// - **R12** `ServerSettingsPage` 从「音源」入口 `push` 整页可达。
/// - **R13** `SceneEditorPage` 从「场景」入口 `push` 整页可达。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  /// 应用展示名（P0-F6）。
  static const String appName = '星璃音乐空间';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageScaffold(
      title: Terms.tabSettings,
      // 主题切换由 PageScaffold 内 ThemeSwitchButton 统一提供。
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _GroupCard(
              icon: Icons.music_note_rounded,
              title: Terms.groupAudio,
              content: _AudioContent(),
            ),
            const SizedBox(height: AppSpace.lg),
            const _GroupCard(
              icon: Icons.palette_rounded,
              title: Terms.groupVisual,
              content: _VisualContent(),
            ),
            const SizedBox(height: AppSpace.lg),
            const _GroupCard(
              icon: Icons.notifications_rounded,
              title: Terms.notificationCenter,
              content: _NotificationContent(),
            ),
            const SizedBox(height: AppSpace.lg),
            const _GroupCard(
              icon: Icons.science_rounded,
              title: Terms.groupLab,
              content: _ExperimentContent(),
            ),
            const SizedBox(height: AppSpace.lg),
            const _GroupCard(
              icon: Icons.info_rounded,
              title: Terms.groupAbout,
              content: _AboutContent(),
            ),
            const SizedBox(height: AppSpace.lg),
          ],
        ),
      ),
    );
  }
}

/// 毛玻璃分组卡（设置「大分类」）：强调色图标 + 标题 + 业务内容。
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.icon, required this.title, required this.content});

  final IconData icon;
  final String title;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final AppThemeColors c = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Material(
        // SwitchListTile / InkWell 需要最近 Material 祖先，否则 ink 不可见。
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 大分类头：强调色圆底图标 + 标题，视觉上区分各大类。
            Row(
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: AppRadius.brMd,
                  ),
                  child: Icon(icon, size: 17, color: c.accent),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    title,
                    style: context.appText.subtitle.copyWith(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            content,
          ],
        ),
      ),
    );
  }
}

/// 分组·音频：主音量、其他音量折叠、音量均衡、均衡器、音源、网易云、播放引擎。
class _AudioContent extends ConsumerWidget {
  const _AudioContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double master = ref.watch(masterVolumeProvider);
    final BalanceMode balance = ref.watch(balanceModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        // ── 其他音量（R26r21：折叠；主音量外置在上方）──
        const _OtherVolumesFold(),
        // R15：声音效果（高质量 / 标准）
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('声音效果', style: context.appText.body),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                children: <Widget>[
                  for (final BalanceMode m in BalanceMode.values)
                    ChoiceChip(
                      label: Text(m == BalanceMode.hifi ? '高质量' : '标准'),
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
                    ? '保留原始声音，不加任何处理'
                    : '自动平衡音量，小声内容更清晰',
                style: context.appText.artist,
              ),
            ],
          ),
        ),
        // R7/R8：EQ 入口（R16：跟随全局主题）
        _EntryRow(
          icon: Icons.graphic_eq_rounded,
          title: '音效',
          subtitle: '低音到高音 · 多组预设 · 随设备生效',
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
        // R26r28：#279 设置整合 —— 网易云登录态直接在设置页管理。
        const _NeteaseSourceTile(),
        const SizedBox(height: AppSpace.lg),

        // ── 播放方式（R26c：从「画面 → 性能与质量」移入「音频」区）──
        // 播放方式属于音频范畴，与画面性能无关；与上方音量/音源同组。
        Text('播放方式', style: context.appText.body),
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
          '默认：稳定兼容；增强：更多格式与高音质 · 切换即时生效',
          style: context.appText.artist,
        ),
      ],
    );
  }
}

/// 分组·画面：外观 + 密度 + 场景 + 游戏 + 性能与质量 + 特效。
class _VisualContent extends ConsumerWidget {
  const _VisualContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String mode = ref.watch(themeModeNameProvider);
    final String skinId = ref.watch(themeSkinProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        const SizedBox(height: AppSpace.lg),

        // ═══ 游戏设置（统一入口，跳转游戏「包厢」）═══
        // B1：机制 / 画质等游戏相关设置全部收敛进「游戏设置」独立页，
        // 此处仅留一个跳转入口，消除与主设置页的重复与套娃。
        _EntryRow(
          icon: Icons.games_outlined,
          title: '游戏设置',
          subtitle: '画质 · 机制 · 世界音效 · 存档 · 游戏 UI 大小',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const VoxelGameSettingsPage(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 分组·通知中心（v2 M6 三区块）+ R13 权限申请 / R14 说明。
class _NotificationContent extends ConsumerWidget {
  const _NotificationContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // R13：权限申请入口（不依赖 adb）
        _EntryRow(
          icon: Icons.shield_outlined,
          title: '权限与授权',
          subtitle: '申请通知 / 存储 / 媒体读取权限（Android 13+ 分级）',
          onTap: () async {
            final bool ok = await PermissionService.requestAll();
            if (!context.mounted) return;
            appNotify(context, ok ? '权限已全部授予' : '部分权限未授予，已打开系统设置');
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

/// 分组·关于：应用名与版本号（P0-F6 / R18-R20）。
class _AboutContent extends ConsumerWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        // 关于：应用简介（用户 2026-08-16 要求「关于页写清关于/版本/仓库」）。
        Text('关于', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.md),
        Text(
          '星璃音乐（Stelarith）是一个随音乐与心情变化的沉浸式个人音乐空间：'
          '场景无限滑动、画面随曲目流转。开源、本地优先、持续迭代。',
          style: context.appText.bodyMuted,
        ),
        const SizedBox(height: AppSpace.lg),
        const _InfoRow(label: '应用名称', value: SettingsPage.appName),
        _InfoRow(label: '版本号', value: AppVersion.display),
        _InfoRow(label: '版本代号', value: AppVersion.brand),
        _InfoRow(
          label: '今日累计构建',
          value: '${AppVersion.buildCount} 次 · ${AppVersion.display}',
        ),
        _InfoRow(label: '更新渠道', value: AppVersion.channel.label),
        _InfoRow(label: '语义版本', value: AppVersion.semver),
        const _InfoRow(label: '开源协议', value: 'MIT'),
        const SizedBox(height: AppSpace.sm),
        // cl04：恢复「版本更新 / 版本日志 / 更新渠道」入口（画布设置必备项）。
        _EntryRow(
          icon: Icons.system_update_alt_rounded,
          title: '版本更新',
          subtitle: '检查 GitHub 与官方网站是否有新版本',
          onTap: () => showVersionUpdateSheet(context),
        ),
        const SizedBox(height: AppSpace.sm),
        _EntryRow(
          icon: Icons.history_rounded,
          title: '版本日志',
          subtitle: '查看历史更新日志（最新在前）',
          onTap: () => showVersionLogSheet(context),
        ),
        const SizedBox(height: AppSpace.sm),
        _EntryRow(
          icon: Icons.layers_outlined,
          title: '更新渠道',
          subtitle:
              '${ref.read(settingsRepositoryProvider).updateChannel.label} · 切换后重启生效',
          onTap: () => _pickChannel(context, ref),
        ),
        const SizedBox(height: AppSpace.lg),
        // cl59：GitHub 仓库（含分支标注）。
        _EntryRow(
          icon: Icons.code_rounded,
          title: 'GitHub 仓库',
          subtitle: 'github.com/WuMengAA/xingli_music · 分支 main（发布主分支）',
          onTap: () => _copyRepo(context),
        ),
        const SizedBox(height: AppSpace.lg),
        Text('更新日志', style: context.appText.subtitle),
        const SizedBox(height: AppSpace.md),
        FutureBuilder<String?>(
          future: OtaService.cachedNotes(),
          builder: (BuildContext c, AsyncSnapshot<String?> snap) {
            final String? notes = snap.data;
            if (notes == null || notes.trim().isEmpty) {
              return Text(
                '暂无日志：联网启动后自动获取（${AppVersion.channel.label} 渠道）',
                style: context.appText.bodyMuted,
              );
            }
            return Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: SelectableText(notes, style: context.appText.body),
            );
          },
        ),
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

  /// cl59：复制 GitHub 仓库地址。
  void _copyRepo(BuildContext context) {
    appNotify(context, '已复制仓库地址：github.com/WuMengAA/xingli_music');
  }

  /// cl04：更新渠道切换（Beta 稳定 / Alpha 尝鲜；写渠道 + 待重启标记）。
  Future<void> _pickChannel(BuildContext context, WidgetRef ref) async {
    final SettingsRepository repo = ref.read(settingsRepositoryProvider);
    final UpdateChannel current = repo.updateChannel;
    final UpdateChannel? picked = await showModalBottomSheet<UpdateChannel>(
      context: context,
      backgroundColor: context.appColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('更新渠道', style: context.appText.subtitle),
                  const SizedBox(height: 4),
                  Text(
                    '渠道决定 OTA 更新来源与更新日志；切换后重启生效',
                    style: context.appText.caption,
                  ),
                ],
              ),
            ),
            for (final UpdateChannel ch in UpdateChannel.values)
              RadioListTile<UpdateChannel>(
                title: Text(ch.label),
                subtitle: Text(
                  ch == UpdateChannel.beta ? '较稳定，默认推荐' : '尝鲜，功能更新更早',
                ),
                value: ch,
                groupValue: current,
                onChanged: (_) => Navigator.of(c).pop(ch),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await repo.setUpdateChannel(picked);
    await repo.setChannelSwitchPending(true);
    if (context.mounted) {
      appNotify(context, '已切换到 ${picked.label} 渠道，重启后生效并进入升级引导');
    }
  }
}

/// 分组·实验管理（v2 M2 · P1-M2-5 / A1 已裁决新增第 6 槽）。
class _ExperimentContent extends ConsumerWidget {
  const _ExperimentContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExperimentConsent consent = ref.watch(experimentConsentProvider);
    final List<ExperimentItem> items = ref.watch(experimentsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                    appNotify(context, '已撤销同意，退出全部实验');
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
  const _PlayModeRow();

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
    final PlayMode mode = ref.watch(playModeProvider);
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
      // 原生极简（R27）：去掉整行背卡填充，仅保留 InkWell 点击反馈。
      type: MaterialType.transparency,
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

/// 设置页「音源」分组里的网易云入口（R26r28：#279 设置整合）。
///
/// 未登录 → 点按打开登录面板；已登录 → 显示昵称并提供「退登」。
class _NeteaseSourceTile extends ConsumerWidget {
  const _NeteaseSourceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NeteaseAuthState na = ref.watch(neteaseAuthProvider);
    return Material(
      // 原生极简（R27）：去掉整行背卡填充，仅保留 InkWell 点击反馈。
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: () async {
          if (na.isLoggedIn) {
            final bool? confirm = await showDialog<bool>(
              context: context,
              builder: (BuildContext d) => AlertDialog(
                title: const Text('退出网易云登录'),
                content: const Text('退出后无法在搜索页在线播放网易云歌曲。'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(d, true),
                    child: const Text('退登'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await ref.read(neteaseAuthProvider.notifier).logout();
            }
          } else {
            await showNeteaseLoginSheet(context);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: <Widget>[
              Icon(Icons.cloud_outlined,
                  size: AppSize.iconSm, color: context.appColors.iconPrimary),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('网易云音乐', style: context.appText.body),
                    const SizedBox(height: 2),
                    Text(
                      na.isLoggedIn
                          ? '已登录：${na.account?.nickname ?? '网易云用户'}'
                          : '未登录，点此登录后可在搜索页在线播放',
                      style: context.appText.artist,
                    ),
                  ],
                ),
              ),
              if (na.isLoggedIn)
                TextButton(
                  onPressed: () async {
                    await ref.read(neteaseAuthProvider.notifier).logout();
                  },
                  child: const Text('退登'),
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




/// R26r21：音频区「其他音量」折叠组（主音量外置；其余 5 通道 + 静音/播放模式/
/// 白噪音/背景声静音收进此组，点标题展开/收起，默认收起）。
class _OtherVolumesFold extends ConsumerStatefulWidget {
  const _OtherVolumesFold();

  @override
  ConsumerState<_OtherVolumesFold> createState() => _OtherVolumesFoldState();
}

class _OtherVolumesFoldState extends ConsumerState<_OtherVolumesFold> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final double volume = ref.watch(musicVolumeProvider);
    final bool muted = ref.watch(musicMutedProvider);
    final double sVolume = ref.watch(soundscapeVolumeProvider);
    final double sfx = ref.watch(sfxVolumeProvider);
    final double world = ref.watch(worldSfxVolumeProvider);
    final double uiCue = ref.watch(uiCueVolumeProvider);
    final WhiteNoiseState wnState = ref.watch(effectiveWhiteNoiseProvider);
    final bool wnFollows = ref.watch(whiteNoiseFollowsSceneProvider);
    final bool sMuted = ref.watch(soundscapeMutedProvider);
    final double master = ref.watch(masterVolumeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: AppSize.iconSm,
                  color: context.appColors.iconInactive,
                ),
                const SizedBox(width: AppSpace.sm),
                Text('其他音量', style: context.appText.subtitle),
                const SizedBox(width: AppSpace.sm),
                Text(
                  '${(master * 100).round()}%',
                  style: context.appText.caption.copyWith(
                    color: context.appColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _expanded ? 1.0 : 0.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: AppSpace.xs),
                  _SliderRow(
                    label: AudioCategory.music.label,
                    concept: AudioCategory.music.concept,
                    value: volume,
                    onChanged: (double v) {
                      ref.read(musicVolumeProvider.notifier).state = v;
                      unawaited(ref
                          .read(audioServiceProvider)
                          .setMusicVolume(v));
                      unawaited(ref
                          .read(audioServiceProvider)
                          .playCategoryCue(AudioCategory.music));
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('静音', style: context.appText.body),
                    subtitle:
                        Text('暂停音乐输出', style: context.appText.artist),
                    value: muted,
                    onChanged: (bool v) {
                      ref.read(musicMutedProvider.notifier).state = v;
                      unawaited(
                          ref.read(audioServiceProvider).setMusicMuted(v));
                    },
                  ),
                  const _PlayModeRow(),
                  _SliderRow(
                    label: AudioCategory.soundscape.label,
                    concept: AudioCategory.soundscape.concept,
                    value: sVolume,
                    onChanged: (double v) {
                      ref.read(soundscapeVolumeProvider.notifier).state = v;
                      unawaited(ref
                          .read(audioServiceProvider)
                          .setSoundscapeVolume(v));
                      unawaited(ref
                          .read(audioServiceProvider)
                          .playCategoryCue(AudioCategory.soundscape));
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('背景声静音', style: context.appText.body),
                    subtitle: Text('暂停场景背景声（音景）输出',
                        style: context.appText.artist),
                    value: sMuted,
                    onChanged: (bool v) {
                      ref.read(soundscapeMutedProvider.notifier).state = v;
                      unawaited(ref
                          .read(audioServiceProvider)
                          .setSoundscapeMuted(v));
                    },
                  ),
                  _SliderRow(
                    label: AudioCategory.sfx.label,
                    concept: AudioCategory.sfx.concept,
                    value: sfx,
                    onChanged: (double v) {
                      ref.read(sfxVolumeProvider.notifier).state = v;
                      unawaited(
                          ref.read(audioServiceProvider).setSfxVolume(v));
                      unawaited(ref
                          .read(audioServiceProvider)
                          .playCategoryCue(AudioCategory.sfx));
                    },
                  ),
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
                    title: Text('白噪音跟随场景',
                        style: context.appText.body),
                    subtitle: Text(
                      wnFollows
                          ? '每个场景独立记忆白噪音开关与音量，换场景自动切换'
                          : '全局播放：忽略场景设置，所有场景共用同一份白噪音',
                      style: context.appText.artist,
                    ),
                    value: wnFollows,
                    onChanged: (bool v) {
                      ref
                          .read(whiteNoiseFollowsSceneProvider.notifier)
                          .state = v;
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
                        ref.read(whiteNoiseEnabledProvider.notifier).state =
                            v;
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
