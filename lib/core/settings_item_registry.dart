/// ════════════════════════════════════════════════════════════════════════
/// 设置项注册表：id → 渲染控件（布局驱动的渲染桥）
/// ════════════════════════════════════════════════════════════════════════
///
/// 布局数据只存 `id`；实际控件由这里按 id 提供。这样布局可任意拖拽排序、
/// 跨组移动、新建合集，UI 不重写。新增设置项 = 注册一个 id + builder。
/// 未注册的 id（用户自定义合集里放了未知项）→ 占位提示，不崩。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pages/explore/experiments/equalizer_page.dart';
import '../pages/library/favorites_page.dart';
import '../pages/library/top_list_page.dart';
import '../pages/scene/custom_scene_list_page.dart';
import '../pages/scene/voxel_sound_editor_page.dart';
import '../pages/settings/scene_editor_page.dart';
import '../pages/settings/game_graphics_page.dart';
import '../pages/settings/server_settings_page.dart';
import '../pages/voxel/voxel_main_menu_page.dart';
import '../providers/voxel/graphics_quality_provider.dart';
import '../providers/voxel/hud_layout_provider.dart';
import '../providers/voxel/world_audio_provider.dart';
import '../widgets/voxel/voxel_world_view3d.dart' show GraphicsQuality;
import '../providers/audio/audio_providers.dart';
import '../providers/audio/audio_scheme.dart';
import '../providers/audio/auto_play_providers.dart';
import '../providers/audio/music_quality_provider.dart';
import '../models/experiment.dart';
import '../models/track.dart';
import '../providers/explore/experiment_providers.dart';
import '../providers/settings/performance_providers.dart';
import '../providers/sources/netease_provider.dart';
import '../providers/sources/bilibili_provider.dart';
import '../services/audio/sources/bilibili/bilibili_api.dart';
import '../services/audio/sources/bilibili/bilibili_source.dart';
import '../providers/theme/theme_providers.dart';
import '../services/audio/audio_service.dart';
import '../services/permission_service.dart';
import '../pages/templates/ui_editor_page.dart';
import '../pages/templates/ui_template_gallery_page.dart';
import '../widgets/common/state_chip.dart';
import '../widgets/notification/notification_center.dart';
import '../widgets/settings/llm_settings_sheet.dart';
import '../widgets/settings/log_upload_sheet.dart';
import '../widgets/sources/netease_login_sheet.dart';
import '../widgets/sources/bilibili_login_sheet.dart';
import 'app_version.dart';
import 'theme/app_theme_colors.dart';
import 'theme/light_tokens.dart';
import 'theme/theme_skins.dart';
import '../widgets/notification/app_notify.dart';

/// 单项渲染函数。
typedef SettingItemBuilder = Widget Function(
    BuildContext context, WidgetRef ref);

/// 注册表条目。
class SettingItemDef {
  const SettingItemDef({required this.title, required this.builder});

  final String title;
  final SettingItemBuilder builder;
}

/// 入口行（跳转子页）。
Widget _entry(
  BuildContext context,
  WidgetRef ref, {
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: onTap,
    ),
  );
}

/// 单选 chips。
Widget _chips<T>({
  required WidgetRef ref,
  required T value,
  required List<T> values,
  required List<String> labels,
  required ValueChanged<T> onChanged,
}) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (int i = 0; i < values.length; i++)
        ChoiceChip(
          label: Text(labels[i]),
          selected: value == values[i],
          onSelected: (_) => onChanged(values[i]),
        ),
    ],
  );
}

/// cl46：画质预设卡片（名称 + 参数摘要预览，点击选择）。
class _QualityPresetCard extends StatelessWidget {
  const _QualityPresetCard({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  final GraphicsQuality quality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = context.appColors.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : context.appColors.border,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? accent.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.high_quality_rounded,
                  size: 16,
                  color: selected ? accent : context.appColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    quality.label,
                    style: context.appText.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: accent),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _summary(quality),
              style: context.appText.caption,
            ),
          ],
        ),
      ),
    );
  }

  static String _summary(GraphicsQuality g) =>
      '视距 ${g.viewDistanceChunks} 区块 · 渲染 ${(g.renderScale * 100).round()}%\n'
      '面数 ${g.maxFaces ~/ 1000}k · '
      '${g.texture ? '贴图' : '纯色'}${g.water ? ' · 水面' : ''}'
      '${g.fog ? ' · 雾' : ''}';
}

/// cl46：自定义世界机制——偏移率滑块行（0.0~1.0）。
Widget _worldGenSlider(
  BuildContext context,
  String label,
  double value,
  ValueChanged<double> onChanged,
) {
  return Row(
    children: <Widget>[
      SizedBox(
        width: 84,
        child: Text(label, style: context.appText.bodyMuted),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(0.0, 1.0),
          onChanged: onChanged,
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          value.toStringAsFixed(2),
          style: context.appText.caption,
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}

/// 开关行。
Widget _toggle(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return SwitchListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    value: value,
    onChanged: onChanged,
  );
}

/// 声音分类音量滑杆（R26skel-b5）。
class _VolSlider extends StatelessWidget {
  const _VolSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: Text(label, style: context.appText.caption),
        ),
        Expanded(
          flex: 2,
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: 20,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${(value * 100).round()}%',
            style: context.appText.artist,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// 未知 id 占位（不崩）。
Widget _placeholder(BuildContext context, String id) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        '设置项「$id」未注册（可到整理模式移除）',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.outline),
      ),
    );

/// 全部注册表项。
final Map<String, SettingItemDef> kSettingItemRegistry =
    <String, SettingItemDef>{
  // ── 音频 ──────────────────────────────────────────────
  'masterVolume': SettingItemDef(
    title: '主音量',
    builder: (context, ref) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('主音量', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(width: 6),
              Expanded(
                child: Text('所有分类的总输出',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
          Slider(
            value: ref.watch(masterVolumeProvider),
            onChanged: (double v) {
              ref.read(masterVolumeProvider.notifier).state = v;
              ref.read(audioServiceProvider).setMasterVolume(v);
            },
          ),
        ],
      ),
    ),
  ),
  'otherVolumes': SettingItemDef(
    title: '其他音量',
    builder: (context, ref) {
      final ChannelScheme scheme = ref.watch(channelSchemeProvider);
      final AudioDeviceClass cls = ref.watch(audioDeviceClassProvider);
      final bool wnFollow = ref.watch(whiteNoiseFollowsSceneProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 设备自适应方案说明。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: 8),
            decoration: BoxDecoration(
              color: context.appColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              '自动检测：${cls.label} · ${scheme.label}\n'
              '音乐 ${scheme.music.maxTracks}轨/${scheme.music.maxChannels}声道 · '
              '背景 ${scheme.background.maxTracks}轨/${scheme.background.maxChannels}声道 · '
              '音效 ${scheme.sfx.maxTracks}轨/${scheme.sfx.maxChannels}声道 · '
              '白噪音 ${scheme.whiteNoise.maxTracks}轨/${scheme.whiteNoise.maxChannels}声道',
              style: context.appText.caption,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          _VolSlider(
            label: '音乐（流媒体/本地）',
            value: ref.watch(musicVolumeProvider),
            onChanged: (double v) =>
                ref.read(musicVolumeProvider.notifier).state = v,
          ),
          _VolSlider(
            label: '背景（世界内背景音乐/背景声）',
            value: ref.watch(soundscapeVolumeProvider),
            onChanged: (double v) =>
                ref.read(soundscapeVolumeProvider.notifier).state = v,
          ),
          _VolSlider(
            label: '音效（世界内音效/按钮/提示音）',
            value: ref.watch(sfxVolumeProvider),
            onChanged: (double v) =>
                ref.read(sfxVolumeProvider.notifier).state = v,
          ),
          _VolSlider(
            label: wnFollow ? '白噪音（跟随场景 · 局部）' : '白噪音（全局）',
            value: ref.watch(whiteNoiseVolumeProvider),
            onChanged: (double v) =>
                ref.read(whiteNoiseVolumeProvider.notifier).state = v,
          ),
          const SizedBox(height: 4),
          Text(
            '默认：主 50% · 音乐 50% · 背景 25% · 音效 50% · 白噪音 局部25%/全局10%',
            style: context.appText.artist,
          ),
        ],
      );
    },
  ),
  'balanceMode': SettingItemDef(
    title: '音量均衡',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('音量均衡', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<BalanceMode>(
          ref: ref,
          value: ref.watch(balanceModeProvider),
          values: BalanceMode.values,
          labels: const <String>['高保真', '普通'],
          onChanged: (BalanceMode m) {
            ref.read(balanceModeProvider.notifier).state = m;
            ref.read(audioServiceProvider).setBalanceMode(m);
          },
        ),
      ],
    ),
  ),
  'equalizer': SettingItemDef(
    title: '均衡器（10 段）',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.graphic_eq_rounded,
      title: '均衡器（10 段）',
      subtitle: '31Hz ~ 16kHz · 7 组预设 · Android 真 EQ',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const EqualizerPage()),
      ),
    ),
  ),
  'serverSource': SettingItemDef(
    title: '服务器与音源',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.dns_outlined,
      title: '服务器与音源',
      subtitle: '本地目录 / Subsonic / 公开电台 分组管理',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ServerSettingsPage()),
      ),
    ),
  ),
  'netease': SettingItemDef(
    title: '网易云登录',
    builder: (context, ref) {
      final bool loggedIn = ref.watch(neteaseAuthProvider).isLoggedIn;
      return _entry(
        context,
        ref,
        icon: Icons.music_note_rounded,
        title: '网易云登录',
        subtitle: loggedIn ? '已登录，点击管理' : '扫码 / Cookie 登录',
        onTap: () => showNeteaseLoginSheet(context),
      );
    },
  ),
  // R26skel-b3：B站视频源（登录 + 自动匹配当前曲目播放）。
  'bilibili': SettingItemDef(
    title: '哔哩哔哩视频源',
    builder: (context, ref) {
      final bool loggedIn = ref.watch(bilibiliAuthProvider).isLoggedIn;
      final bool busy = ref.watch(bilibiliAuthProvider).busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _entry(
            context,
            ref,
            icon: Icons.video_library_outlined,
            title: '哔哩哔哩视频源',
            subtitle: loggedIn
                ? '已登录 · 点击管理 / 自动匹配'
                : '扫码 / Cookie 登录（未登录不可用）',
            onTap: () => showBilibiliLoginSheet(context),
          ),
          if (loggedIn) ...<Widget>[
            const SizedBox(height: 4),
            // 自动匹配：按当前曲目名 + 时长找 B站视频并播放（默认静音）。
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => _autoPlayBilibiliForCurrent(context, ref),
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('自动匹配当前曲目并播放（默认静音）'),
            ),
          ],
        ],
      );
    },
  ),
  // R26skel-b6：音乐源音质（网易云 音乐源）。
  'musicQuality': SettingItemDef(
    title: '网易云音质',
    builder: (context, ref) {
      final bool vip = ref.watch(neteaseVipProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '网易云音质 · ${vip ? "VIP" : "未开通VIP"}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          _chips<MusicQuality>(
            ref: ref,
            value: ref.watch(musicQualityProvider),
            values: MusicQuality.values,
            labels: <String>[
              for (final MusicQuality q in MusicQuality.values)
                q.label + (q == MusicQuality.lossless && !vip ? ' · 需VIP' : ''),
            ],
            onChanged: (MusicQuality q) {
              if (q == MusicQuality.lossless && !vip) return;
              ref.read(musicQualityProvider.notifier).state = q;
            },
          ),
        ],
      );
    },
  ),
  // R26skel-b6：B站清晰度（视频源，大会员解锁高清晰度）。
  'biliQuality': SettingItemDef(
    title: 'B站清晰度',
    builder: (context, ref) {
      final bool vip = ref.watch(bilibiliVipProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'B站清晰度 · ${vip ? "大会员" : "非大会员"}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          _chips<BiliVideoQuality>(
            ref: ref,
            value: ref.watch(biliVideoQualityProvider),
            values: BiliVideoQuality.values,
            labels: <String>[
              for (final BiliVideoQuality q in BiliVideoQuality.values)
                q.label +
                    ((q == BiliVideoQuality.ultra ||
                            q == BiliVideoQuality.uhd4k) &&
                            !vip
                        ? ' · 需大会员'
                        : ''),
            ],
            onChanged: (BiliVideoQuality q) {
              if ((q == BiliVideoQuality.ultra ||
                      q == BiliVideoQuality.uhd4k) &&
                  !vip) {
                return;
              }
              ref.read(biliVideoQualityProvider.notifier).state = q;
            },
          ),
        ],
      );
    },
  ),
  'musicEngine': SettingItemDef(
    title: '播放引擎',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('播放引擎', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<MusicEngine>(
          ref: ref,
          value: ref.watch(musicEngineProvider),
          values: MusicEngine.values,
          labels: <String>[
            for (final MusicEngine e in MusicEngine.values) e.label,
          ],
          onChanged: (MusicEngine e) =>
              ref.read(musicEngineProvider.notifier).state = e,
        ),
      ],
    ),
  ),

  // ── 游戏设置（开放世界 · 游戏内快捷项）────────────────────────
  // R26skel：设置页新增「游戏」集合——把游戏内快捷开关（白噪音/世界音效/
  // 布局编辑）收进来，与游戏菜单「游戏设置」共享同一批 provider。
  'whiteNoise': SettingItemDef(
    title: '白噪音',
    builder: (context, ref) => _toggle(
      context,
      title: '白噪音',
      subtitle: '均匀掩蔽环境杂音，帮助专注 / 睡眠',
      value: ref.watch(whiteNoiseEnabledProvider),
      onChanged: (bool v) =>
          ref.read(whiteNoiseEnabledProvider.notifier).state = v,
    ),
  ),
  'worldAudio': SettingItemDef(
    title: '世界音效',
    builder: (context, ref) => _toggle(
      context,
      title: '世界音效',
      subtitle: '开放世界中随地形/机位变化的风、水、叶、鸟声',
      value: ref.watch(worldAudioEnabledProvider),
      onChanged: (bool v) =>
          ref.read(worldAudioEnabledProvider.notifier).state = v,
    ),
  ),
  'hudEdit': SettingItemDef(
    title: '布局编辑',
    builder: (context, ref) => _toggle(
      context,
      title: '布局编辑',
      subtitle: '开 = 浮动 HUD（摇杆/动作键）显示边框可拖动；关 = 自动保存位置',
      value: ref.watch(hudEditProvider),
      onChanged: (bool v) => ref.read(hudEditProvider.notifier).state = v,
    ),
  ),

  // ── 画面 ──────────────────────────────────────────────
  'themeMode': SettingItemDef(
    title: '主题模式',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('主题模式', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<String>(
          ref: ref,
          value: ref.watch(themeModeNameProvider),
          values: const <String>['system', 'light', 'dark'],
          labels: const <String>['跟随系统', '浅色', '深色'],
          onChanged: (String v) =>
              ref.read(themeModeNameProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  'themeSkin': SettingItemDef(
    title: '皮肤',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('皮肤', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final ThemeSkin skin in ThemeSkins.all)
              ChoiceChip(
                avatar: CircleAvatar(
                  backgroundColor: skin.primary,
                  radius: 8,
                ),
                label: Text(skin.name),
                selected: ref.watch(themeSkinProvider) == skin.id,
                onSelected: (_) =>
                    ref.read(themeSkinProvider.notifier).state = skin.id,
              ),
          ],
        ),
      ],
    ),
  ),
  'uiDensity': SettingItemDef(
    title: '界面密度',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('界面密度', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<UiDensity>(
          ref: ref,
          value: ref.watch(uiDensityProvider),
          values: UiDensity.values,
          labels: <String>[for (final UiDensity d in UiDensity.values) d.label],
          onChanged: (UiDensity d) =>
              ref.read(uiDensityProvider.notifier).state = d,
        ),
      ],
    ),
  ),
  // R26skel-b3：全局 UI 大小（整体界面缩放，0.8~1.2）。
  'uiScale': SettingItemDef(
    title: '全局 UI 大小',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '全局 UI 大小 · 当前 ${(ref.watch(uiScaleProvider) * 100).round()}%',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Slider(
          value: ref.watch(uiScaleProvider),
          min: kUiScaleMin,
          max: kUiScaleMax,
          divisions: 8,
          label: '${(ref.watch(uiScaleProvider) * 100).round()}%',
          onChanged: (double v) =>
              ref.read(uiScaleProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  // R26skel-b3：游戏 UI 大小（3D 世界 HUD：摇杆 / 动作键整体缩放）。
  'hudScale': SettingItemDef(
    title: '游戏 UI 大小',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '游戏 UI 大小 · 当前 ${(ref.watch(hudScaleProvider) * 100).round()}%',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Slider(
          value: ref.watch(hudScaleProvider),
          min: kHudScaleMin,
          max: kHudScaleMax,
          divisions: 6,
          label: '${(ref.watch(hudScaleProvider) * 100).round()}%',
          onChanged: (double v) =>
              ref.read(hudScaleProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  // ── 场景背景渲染画质（R26skel-b4：独立于游戏画质）────────────────
  'sceneBgQuality': SettingItemDef(
    title: '场景背景画质',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('场景背景画质', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<SceneBgQuality>(
          ref: ref,
          value: ref.watch(sceneBgQualityProvider),
          values: SceneBgQuality.values,
          labels: <String>[
            for (final SceneBgQuality q in SceneBgQuality.values) q.label,
          ],
          onChanged: (SceneBgQuality q) =>
              ref.read(sceneBgQualityProvider.notifier).state = q,
        ),
        const SizedBox(height: 4),
        Text('仅影响场景页/播放器背景渲染，与游戏画质互不影响',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  ),
  'sceneBgFps': SettingItemDef(
    title: '场景背景帧率',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '场景背景帧率 · 当前 ${ref.watch(sceneBgFpsProvider)} FPS',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        _chips<int>(
          ref: ref,
          value: ref.watch(sceneBgFpsProvider),
          values: const <int>[15, 30, 60],
          labels: const <String>['15', '30', '60'],
          onChanged: (int v) =>
              ref.read(sceneBgFpsProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  'sceneBgFog': SettingItemDef(
    title: '场景背景 · 雾',
    builder: (context, ref) => _toggle(
      context,
      title: '场景背景 · 雾',
      subtitle: '远处淡入雾效',
      value: ref.watch(sceneBgFogProvider),
      onChanged: (bool v) =>
          ref.read(sceneBgFogProvider.notifier).state = v,
    ),
  ),
  'sceneBgWater': SettingItemDef(
    title: '场景背景 · 水波动画',
    builder: (context, ref) => _toggle(
      context,
      title: '场景背景 · 水波动画',
      subtitle: '水面起伏重绘',
      value: ref.watch(sceneBgWaterProvider),
      onChanged: (bool v) =>
          ref.read(sceneBgWaterProvider.notifier).state = v,
    ),
  ),
  'sceneBgSky': SettingItemDef(
    title: '场景背景 · 天空渐变',
    builder: (context, ref) => _toggle(
      context,
      title: '场景背景 · 天空渐变',
      subtitle: '天顶到地平线渐变',
      value: ref.watch(sceneBgSkyProvider),
      onChanged: (bool v) =>
          ref.read(sceneBgSkyProvider.notifier).state = v,
    ),
  ),
  'sceneBgAnim': SettingItemDef(
    title: '场景背景 · 动画',
    builder: (context, ref) => _toggle(
      context,
      title: '场景背景 · 动画',
      subtitle: '关 = 静态单帧省电',
      value: ref.watch(sceneBgAnimProvider),
      onChanged: (bool v) {
        // 与场景页「实时渲染」联动：动画开则实时开，二者保持同步。
        ref.read(sceneBgAnimProvider.notifier).state = v;
        ref.read(voxelBgLiveProvider.notifier).state = v;
      },
    ),
  ),
  'sceneEditor': SettingItemDef(
    title: '场景编辑器',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.auto_awesome_outlined,
      title: '场景编辑器',
      subtitle: '编辑自定义场景 · 导出场景包',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SceneEditorPage(sceneId: 'rain'),
        ),
      ),
    ),
  ),
  'customSceneList': SettingItemDef(
    title: '自定义场景管理',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.collections_bookmark_outlined,
      title: '自定义场景管理',
      subtitle: '列出 / 新建 / 编辑自定义场景（含默认 BGM 选曲）',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CustomSceneListPage()),
      ),
    ),
  ),

  // ── 机制（世界 / 性能）─────────────────────────────────
  'worldSfx': SettingItemDef(
    title: '世界音效设置',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.graphic_eq_rounded,
      title: '世界音效设置',
      subtitle: '水 / 风 / 叶 / 鸟 四轨 · 随机位变化的空间音效',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoxelSoundEditorPage()),
      ),
    ),
  ),
  'worldSave': SettingItemDef(
    title: '世界存档',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.save_outlined,
      title: '世界存档',
      subtitle: '经游戏主菜单进入：新建 / 恢复（多备份）/ 导出 / 重命名 / 删除',
      // R26skel：存档唯一入口 = 游戏主菜单「世界存档」——其他地方不直接
      // 打开管理器，避免绕过主菜单新建/跳转/恢复存档（叠加存档）。
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoxelMainMenuPage()),
      ),
    ),
  ),
  // cl46：全局收藏 + 自定义歌单（名称 / 相册背景图 / 排序方式）。
  'favoritesPlaylists': SettingItemDef(
    title: '收藏与歌单',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.favorite_outline_rounded,
      title: '收藏与歌单',
      subtitle: '全局收藏 · 自定义歌单（名称 / 背景图 / 排序）',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const FavoritesAndPlaylistsPage(),
        ),
      ),
    ),
  ),
  // cl46：听歌排行——全局播放次数 / 收听时长 Top 榜。
  'topList': SettingItemDef(
    title: '听歌排行',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.leaderboard_rounded,
      title: '听歌排行',
      subtitle: '全局播放次数 / 收听时长排行榜',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TopListPage()),
      ),
    ),
  ),
  // cl46：自动播放——曲毕自动按播放顺序 / 歌单顺序下一首。
  'autoPlay': SettingItemDef(
    title: '自动播放',
    builder: (context, ref) => _toggle(
      context,
      title: '自动播放',
      subtitle: '曲目播完后自动按播放顺序 / 歌单顺序播下一首',
      value: ref.watch(autoPlayProvider),
      onChanged: (bool v) =>
          ref.read(autoPlayProvider.notifier).state = v,
    ),
  ),
  // cl46：自动过渡——接近曲末 5 秒淡出淡入，无缝衔接。
  'autoTransition': SettingItemDef(
    title: '自动过渡',
    builder: (context, ref) => _toggle(
      context,
      title: '自动过渡',
      subtitle: '接近曲末 5 秒淡出旧曲、淡入新曲，无感连续播放',
      value: ref.watch(autoTransitionProvider),
      onChanged: (bool v) =>
          ref.read(autoTransitionProvider.notifier).state = v,
    ),
  ),
  // cl46：渲染分辨率（渲染精度缩放 0.5×~2×，与渲染·高级的「渲染精度」同一数据源）。
  'renderResolution': SettingItemDef(
    title: '分辨率',
    builder: (context, ref) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('分辨率 · 渲染缩放', style: context.appText.body),
          const SizedBox(height: 6),
          _chips<double>(
            ref: ref,
            value: ref.watch(renderPrecisionScaleProvider),
            values: const <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
            labels: const <String>['0.5×', '0.75×', '1×', '1.25×', '1.5×', '2×'],
            onChanged: (double v) =>
                ref.read(renderPrecisionScaleProvider.notifier).state = v,
          ),
        ],
      ),
    ),
  ),
  // cl46：世界自动备份间隔。
  'backupInterval': SettingItemDef(
    title: '备份间隔',
    builder: (context, ref) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('自动备份间隔', style: context.appText.body),
          const SizedBox(height: 6),
          _chips<int>(
            ref: ref,
            value: ref.watch(backupIntervalMinutesProvider),
            values: const <int>[5, 15, 30, 60],
            labels: const <String>['5 分钟', '15 分钟', '30 分钟', '1 小时'],
            onChanged: (int v) =>
                ref.read(backupIntervalMinutesProvider.notifier).state = v,
          ),
        ],
      ),
    ),
  ),
  // cl46：自定义世界机制——全局偏移率 + 地形 / 群系 / 结构细调。
  'worldGen': SettingItemDef(
    title: '自定义世界机制',
    builder: (context, ref) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _worldGenSlider(
            context,
            '全局偏移率',
            ref.watch(worldGenOffsetProvider),
            (double v) => ref.read(worldGenOffsetProvider.notifier).state = v,
          ),
          _worldGenSlider(
            context,
            '地形起伏',
            ref.watch(worldGenTerrainProvider),
            (double v) => ref.read(worldGenTerrainProvider.notifier).state = v,
          ),
          _worldGenSlider(
            context,
            '群系分布',
            ref.watch(worldGenBiomeProvider),
            (double v) => ref.read(worldGenBiomeProvider.notifier).state = v,
          ),
          _worldGenSlider(
            context,
            '结构生成',
            ref.watch(worldGenStructureProvider),
            (double v) => ref.read(worldGenStructureProvider.notifier).state = v,
          ),
        ],
      ),
    ),
  ),

  // ── 画面 · 游戏画质（cl45：从「游戏」迁入「个性」，含专属高级页）──
  'gameGraphics': SettingItemDef(
    title: '游戏画面 · 高级设置',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.dashboard_customize_outlined,
      title: '游戏画面 · 高级设置',
      subtitle: '画质档 / 视距 / LOD / 描边 / 帧率（与游戏内共享）',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GameGraphicsPage()),
      ),
    ),
  ),
  'outlineToggle': SettingItemDef(
    title: '方块描边',
    builder: (context, ref) => _toggle(
      context,
      title: '方块描边',
      subtitle: '玩家 5 格内实描边 + 5~12 格极淡渐隐；关掉更省面数',
      value: ref.watch(outlineEnabledProvider),
      onChanged: (bool v) =>
          ref.read(outlineEnabledProvider.notifier).state = v,
    ),
  ),
  'boundaryFog': SettingItemDef(
    title: '边界雾',
    builder: (context, ref) => _toggle(
      context,
      title: '边界雾',
      subtitle: '开=视距边缘收口雾（隐藏远景，LOD 关闭）；关=LOD 远景看得更远',
      value: ref.watch(boundaryFogEnabledProvider),
      onChanged: (bool v) =>
          ref.read(boundaryFogEnabledProvider.notifier).state = v,
    ),
  ),

  // ── 机制 · 渲染与机制（cl30+ 可单独开关）────────────
  'faceCull': SettingItemDef(
    title: '侧面剔除',
    builder: (context, ref) => _toggle(
      context,
      title: '侧面剔除',
      subtitle: '远处区块按视角朝向减面（配合 LOD 迟滞防闪烁）',
      value: ref.watch(faceCullEnabledProvider),
      onChanged: (bool v) =>
          ref.read(faceCullEnabledProvider.notifier).state = v,
    ),
  ),
  'occlusionCull': SettingItemDef(
    title: '遮挡剔除',
    builder: (context, ref) => _toggle(
      context,
      title: '遮挡剔除',
      subtitle: '隐藏被相邻不透明方块完全盖住的内部面（最大面数收益）',
      value: ref.watch(occlusionCullEnabledProvider),
      onChanged: (bool v) =>
          ref.read(occlusionCullEnabledProvider.notifier).state = v,
    ),
  ),
  'backFaceCull': SettingItemDef(
    title: '背面剔除',
    builder: (context, ref) => _toggle(
      context,
      title: '背面剔除',
      subtitle: '去掉背向相机的三角面（面数减半）',
      value: ref.watch(backFaceCullEnabledProvider),
      onChanged: (bool v) =>
          ref.read(backFaceCullEnabledProvider.notifier).state = v,
    ),
  ),
  'frustumCull': SettingItemDef(
    title: '视锥剔除',
    builder: (context, ref) => _toggle(
      context,
      title: '视锥剔除',
      subtitle: '跳过视锥外区块（默认关：历史曾误删可见区块）',
      value: ref.watch(frustumCullEnabledProvider),
      onChanged: (bool v) =>
          ref.read(frustumCullEnabledProvider.notifier).state = v,
    ),
  ),
  'flashlight': SettingItemDef(
    title: '手电筒模式',
    builder: (context, ref) => _toggle(
      context,
      title: '手电筒模式',
      subtitle: '手电筒光锥：FOV 不变，锥内照亮、锥外变暗 + 泛光（仅渲染）',
      value: ref.watch(flashlightEnabledProvider),
      onChanged: (bool v) =>
          ref.read(flashlightEnabledProvider.notifier).state = v,
    ),
  ),
  'shadowRender': SettingItemDef(
    title: '阴影渲染',
    builder: (context, ref) => _toggle(
      context,
      title: '阴影渲染',
      subtitle: '太阳投影硬阴影（开=真实立体；关=省面数）',
      value: ref.watch(shadowRenderProvider),
      onChanged: (bool v) =>
          ref.read(shadowRenderProvider.notifier).state = v,
    ),
  ),
  'aoRender': SettingItemDef(
    title: '环境光屏蔽（AO）',
    builder: (context, ref) => _toggle(
      context,
      title: '环境光屏蔽（AO）',
      subtitle: '方块角落/缝隙变暗增强立体感；关 = 均匀亮度更省',
      value: ref.watch(aoEnabledProvider),
      onChanged: (bool v) =>
          ref.read(aoEnabledProvider.notifier).state = v,
    ),
  ),
  'underwaterFilter': SettingItemDef(
    title: '水下滤镜',
    builder: (context, ref) => _toggle(
      context,
      title: '水下滤镜',
      subtitle: '水下蓝色色调 + 阳光衰减',
      value: ref.watch(underwaterFilterEnabledProvider),
      onChanged: (bool v) =>
          ref.read(underwaterFilterEnabledProvider.notifier).state = v,
    ),
  ),
  'waterFlow': SettingItemDef(
    title: '水流动',
    builder: (context, ref) => _toggle(
      context,
      title: '水流动',
      subtitle: '放置水源后向四周 9 格扩散（20 tick/秒 驱动）',
      value: ref.watch(waterFlowEnabledProvider),
      onChanged: (bool v) =>
          ref.read(waterFlowEnabledProvider.notifier).state = v,
    ),
  ),
  'autoBackup': SettingItemDef(
    title: '后台自动备份',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.backup_outlined,
      title: '后台自动备份',
      subtitle: '存档自动滚动备份 20 份（游戏主菜单「世界存档」可任选恢复）',
      // R26skel：存档/恢复唯一入口 = 游戏主菜单「世界存档」。
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const VoxelMainMenuPage()),
      ),
    ),
  ),
  'perfPreset': SettingItemDef(
    title: '画质预设',
    builder: (context, ref) {
      final GraphicsQuality q = ref.watch(graphicsQualityProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('画质预设 · 一键套用整套画面参数', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '当前：${q.label} · 视距 ${ref.watch(viewDistanceChunksProvider)} 区块 · '
            '渲染 ${ref.watch(renderPrecisionScaleProvider).toStringAsFixed(2)}×',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          // cl46：低中高预设 → 卡片预览与选择。
          LayoutBuilder(
            builder: (BuildContext c, BoxConstraints bc) {
              const int cols = 2;
              final double cardW = (bc.maxWidth - 8) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final GraphicsQuality g in GraphicsQuality.values)
                    SizedBox(
                      width: cardW,
                      child: _QualityPresetCard(
                        quality: g,
                        selected: q == g,
                        onTap: () => _applyQualityPreset(ref, g),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  ),
  'fpsLimit': SettingItemDef(
    title: '帧率限制',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('帧率限制', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<FpsLimit>(
          ref: ref,
          value: ref.watch(fpsLimitProvider),
          values: FpsLimit.values,
          labels: <String>[for (final FpsLimit f in FpsLimit.values) f.label],
          onChanged: (FpsLimit f) =>
              ref.read(fpsLimitProvider.notifier).state = f,
        ),
      ],
    ),
  ),
  'viewDistance': SettingItemDef(
    title: '视距',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '视距 · 当前 ${ref.watch(viewDistanceChunksProvider)} 区块',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Slider(
          value: ref.watch(viewDistanceChunksProvider).toDouble(),
          min: 2,
          max: 12,
          divisions: 10,
          label: '${ref.watch(viewDistanceChunksProvider)} 区块',
          onChanged: (double v) => ref
              .read(viewDistanceChunksProvider.notifier)
              .state = v.round(),
        ),
      ],
    ),
  ),
  'lodStart': SettingItemDef(
    title: 'LOD 起始',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'LOD 起始 · 当前 ${ref.watch(lodStartChunksProvider)} 区块',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // R26fix：min=0/max=8 兼容旧持久化值（旧 slider 0-6，新推荐 2/3/4）；
        // 推荐值用 chips 一行提示，避免启动时 value=6 越界崩溃。
        Slider(
          value: ref.watch(lodStartChunksProvider).toDouble().clamp(0, 8),
          min: 0,
          max: 8,
          divisions: 8,
          onChanged: (double v) =>
              ref.read(lodStartChunksProvider.notifier).state = v.round().clamp(0, 8),
        ),
      ],
    ),
  ),
  'lodStep': SettingItemDef(
    title: 'LOD 步长（兼容）',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('LOD 步长（兼容）', style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: ref.watch(lodStepChunksProvider).toDouble(),
          min: 1,
          max: 4,
          divisions: 3,
          onChanged: (double v) =>
              ref.read(lodStepChunksProvider.notifier).state = v.round(),
        ),
      ],
    ),
  ),
  // R26lod：LOD 参数体系（用户确认：开关/起始/步长格/采样2幂/最远区块）。
  'lodEnabled': SettingItemDef(
    title: 'LOD 开关',
    builder: (context, ref) => _toggle(
      context,
      title: 'LOD 开关',
      subtitle: '关 = 全满精度方阵，无远景大方块（最费面数）',
      value: ref.watch(lodEnabledProvider),
      onChanged: (bool v) =>
          ref.read(lodEnabledProvider.notifier).state = v,
    ),
  ),
  'lodStepBlocks': SettingItemDef(
    title: 'LOD 步长（格）',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('LOD 步长（格）', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<int>(
          ref: ref,
          value: ref.watch(lodStepBlocksProvider),
          values: const <int>[3, 9, 16],
          labels: const <String>['3 格（密）', '9 格（中）', '16 格（疏）'],
          onChanged: (int v) =>
              ref.read(lodStepBlocksProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  'lodSample': SettingItemDef(
    title: 'LOD 采样（大方块）',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('LOD 采样（合成大方块边长）', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<int>(
          ref: ref,
          value: ref.watch(lodSampleBaseProvider),
          values: const <int>[2, 4, 8],
          labels: const <String>['2×2（细）', '4×4（中）', '8×8（粗）'],
          onChanged: (int v) =>
              ref.read(lodSampleBaseProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  'lodMaxChunks': SettingItemDef(
    title: 'LOD 最远距离',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'LOD 最远距离 · 当前 ${ref.watch(lodMaxChunksProvider)} 区块（可超视距）',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          value: ref.watch(lodMaxChunksProvider).toDouble(),
          min: 4,
          max: 32,
          divisions: 28,
          onChanged: (double v) =>
              ref.read(lodMaxChunksProvider.notifier).state = v.round(),
        ),
      ],
    ),
  ),
  'renderPrecisionScale': SettingItemDef(
    title: '渲染精度',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '渲染精度 · 当前 ${ref.watch(renderPrecisionScaleProvider).toStringAsFixed(2)}×'
          '（同比例降分辨率，尺寸不变）',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          value: ref.watch(renderPrecisionScaleProvider),
          min: 0.25,
          max: 2.0,
          divisions: 14,
          label: '${ref.watch(renderPrecisionScaleProvider).toStringAsFixed(2)}×',
          onChanged: (double v) =>
              ref.read(renderPrecisionScaleProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  'renderPrecision': SettingItemDef(
    title: '几何精度（面数）',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('几何精度（面数倍率，与渲染分辨率无关）', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<double>(
          ref: ref,
          value: ref.watch(renderPrecisionProvider),
          values: const <double>[0.5, 1.0, 1.5, 2.0],
          labels: const <String>['0.5×', '1×', '1.5×', '2×'],
          onChanged: (double v) =>
              ref.read(renderPrecisionProvider.notifier).state = v,
        ),
      ],
    ),
  ),
  'picturePreset': SettingItemDef(
    title: '全局画面预设',
    builder: (context, ref) {
      final PicturePreset p = ref.watch(picturePresetProvider);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('全局画面预设 · 一键套用（精度 + 模糊 + 噪点 + 动画）',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          _chips<PicturePreset>(
            ref: ref,
            value: p,
            values: PicturePreset.values,
            labels: <String>[for (final PicturePreset x in PicturePreset.values) x.label],
            onChanged: (PicturePreset x) => applyPicturePreset(ref, x),
          ),
        ],
      );
    },
  ),
  'engineBackend': SettingItemDef(
    title: '图形后端',
    builder: (context, ref) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('图形后端', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        _chips<EngineBackend>(
          ref: ref,
          value: ref.watch(engineBackendProvider),
          values: EngineBackend.values,
          labels: <String>[for (final EngineBackend e in EngineBackend.values) e.label],
          onChanged: (EngineBackend e) =>
              ref.read(engineBackendProvider.notifier).state = e,
        ),
      ],
    ),
  ),
  'fxNoise': SettingItemDef(
    title: '噪点纹理',
    builder: (context, ref) => _toggle(
      context,
      title: '噪点纹理',
      subtitle: '胶片颗粒质感；关 = 更省 GPU（低档位默认关）',
      value: ref.watch(noiseEnabledProvider),
      onChanged: (bool v) =>
          ref.read(noiseOverrideProvider.notifier).state = v,
    ),
  ),
  'fxBlur': SettingItemDef(
    title: '玻璃模糊',
    builder: (context, ref) {
      final double blur = ref.watch(glassBlurProvider);
      return _toggle(
        context,
        title: '玻璃模糊',
        subtitle: blur > 0 ? '强度 $blur' : '关',
        value: blur > 0,
        onChanged: (bool v) =>
            ref.read(glassBlurOverrideProvider.notifier).state = v ? 12 : 0,
      );
    },
  ),
  'fxBg': SettingItemDef(
    title: '背景动画',
    builder: (context, ref) => _toggle(
      context,
      title: '背景动画',
      subtitle: '背景动态动画；关 = 省电省性能（低档位默认关）',
      value: ref.watch(bgAnimationEnabledProvider),
      onChanged: (bool v) =>
          ref.read(bgAnimationOverrideProvider.notifier).state = v,
    ),
  ),
  'fxLiquid': SettingItemDef(
    title: '液态玻璃（折射）',
    builder: (context, ref) => _toggle(
      context,
      title: '液态玻璃（折射）',
      subtitle: '液态玻璃折射；关 = 省性能（低档位默认关）',
      value: ref.watch(liquidGlassEnabledProvider),
      onChanged: (bool v) =>
          ref.read(liquidGlassOverrideProvider.notifier).state = v,
    ),
  ),

  // ── 通知 ──────────────────────────────────────────────
  'permissions': SettingItemDef(
    title: '权限与授权',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.shield_outlined,
      title: '权限与授权',
      subtitle: '申请通知 / 存储 / 媒体读取权限（Android 13+ 分级）',
      onTap: () async {
        final bool ok = await PermissionService.requestAll();
        if (!context.mounted) return;
        appNotify(context, ok ? '权限已全部授予' : '部分权限未授予，已打开系统设置');
      },
    ),
  ),
  'notificationCenter': SettingItemDef(
    title: '通知中心',
    builder: (context, ref) => const NotificationCenter(),
  ),

  // ── 实验 ──────────────────────────────────────────────
  'llmSettings': SettingItemDef(
    title: '大模型设置',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.smart_toy_outlined,
      title: '大模型设置',
      subtitle: '接入 OpenAI 兼容大模型（AI 陪伴优先 LLM 回复）',
      onTap: () => showLlmSettingsSheet(context),
    ),
  ),
  'consentStatus': SettingItemDef(
    title: '同意状态',
    builder: (context, ref) {
      final bool agreed = ref.watch(experimentConsentProvider).agreed;
      return Row(
        children: <Widget>[
          Text('同意状态', style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          StateChip(
            tone: agreed ? ChipTone.ok : ChipTone.retired,
            label: agreed ? '已同意' : '未同意',
          ),
        ],
      );
    },
  ),
  'experimentToggles': SettingItemDef(
    title: '逐项启停',
    builder: (context, ref) {
      final items = ref.watch(experimentsProvider);
      final consent = ref.watch(experimentConsentProvider);
      return Column(
        children: <Widget>[
          for (final ExperimentItem item in items)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(item.name, style: Theme.of(context).textTheme.bodyMedium),
              subtitle:
                  Text(item.statusLabel, style: Theme.of(context).textTheme.bodySmall),
              value: consent.isEnabled(item),
              onChanged: (bool v) => ref
                  .read(experimentConsentProvider.notifier)
                  .setEnabled(item.id, v),
            ),
        ],
      );
    },
  ),

  // ── 关于 ──────────────────────────────────────────────
  'aboutInfo': SettingItemDef(
    title: '应用信息',
    builder: (context, ref) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('星璃音乐空间', style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(AppVersion.display, style: Theme.of(context).textTheme.bodySmall),
    ),
  ),
  'logUpload': SettingItemDef(
    title: '日志上报',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.cloud_upload_outlined,
      title: '日志上报',
      subtitle: '把已脱敏日志发到自建日志服务（默认关闭）',
      onTap: () => showLogUploadSheet(context),
    ),
  ),

  // ── 开发者工具（UI 模板库 / UI 编辑器）──────────────
  'uiTemplateGallery': SettingItemDef(
    title: 'UI 模板库',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.widgets_outlined,
      title: 'UI 模板库',
      subtitle: '拆解现有界面为优质模板：控件/界面预览，一键起步',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const UiTemplateGalleryPage()),
      ),
    ),
  ),
  'uiEditor': SettingItemDef(
    title: 'UI 编辑器',
    builder: (context, ref) => _entry(
      context,
      ref,
      icon: Icons.edit_rounded,
      title: 'UI 编辑器',
      subtitle: '资产拖入 + 实时编辑预览 + 自动纠错，导出 JSON',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const UiEditorPage()),
      ),
    ),
  ),
};

/// 按 id 取渲染控件；未知 id → 占位。
Widget buildSettingItem(BuildContext context, WidgetRef ref, String id) {
  final SettingItemDef? def = kSettingItemRegistry[id];
  if (def == null) return _placeholder(context, id);
  return def.builder(context, ref);
}

/// R26skel-b3：B站自动匹配——按当前播放曲目的「标题 + 时长」在 B站搜相似
/// 结果，自动播放时长最接近的那个；**默认静音**（匹配到的视频可能是翻唱/
/// 剪辑，不该突然出声；用户可手动取消静音）。
Future<void> _autoPlayBilibiliForCurrent(
    BuildContext context, WidgetRef ref) async {
  final Track? cur = ref.read(audioServiceProvider).currentTrack;
  if (cur == null) {
    appNotify(context, '当前没有播放中的曲目');
    return;
  }
  appNotify(context, '正在 B站搜索「${cur.title}」…');
  try {
    final BiliMatchCandidate? c = await ref
        .read(bilibiliSourceProvider)
        .autoMatch(cur.title, artist: cur.artist, targetDuration: cur.duration);
    if (c == null) {
      appNotify(context, '未找到时长相近的 B站视频（差 ${cur.duration?.inSeconds ?? 0}s 内）');
      return;
    }
    // 默认静音：先静音再播放，避免匹配到非原曲时突然出声。
    await ref.read(audioServiceProvider).setMusicMuted(true);
    await ref.read(audioServiceProvider).playMusic(c.track);
    appNotify(context,
        '已自动匹配 B站：${c.track.title}（${c.delta}s 差）· 默认静音，可手动取消');
  } on BilibiliApiException catch (e) {
    appNotify(context, bilibiliErrorText(e));
  } on BilibiliResolveException catch (e) {
    appNotify(context, e.message);
  } catch (e) {
    appNotify(context, 'B站自动匹配失败：$e');
  }
}

/// R26fx：画质预设一键应用——把整套画面参数（画质档/视距/LOD/分辨率/特效/
/// 帧率）一次设齐，避免「画质档、性能预设、视距、LOD、渲染参数各自独立
/// 叠加生效、出了问题不知道是哪一层」的混乱。
void _applyQualityPreset(WidgetRef ref, GraphicsQuality q) {
  ref.read(graphicsQualityProvider.notifier).state = q;
  ref.read(performanceModeProvider.notifier).state =
      q == GraphicsQuality.perf || q == GraphicsQuality.smooth
          ? PerformanceMode.performance
          : PerformanceMode.quality;
  ref.read(viewDistanceChunksProvider.notifier).state = q.viewDistanceChunks;
  ref.read(lodStartChunksProvider.notifier).state = q.lodStartChunks;
  ref.read(lodStepChunksProvider.notifier).state = q.lodStepChunks;
  ref.read(lodEnabledProvider.notifier).state = true;
  ref.read(lodStepBlocksProvider.notifier).state = 16;
  ref.read(lodSampleBaseProvider.notifier).state = 4;
  ref.read(lodMaxChunksProvider.notifier).state =
      q == GraphicsQuality.perf
          ? 4
          : (q == GraphicsQuality.smooth ? 6 : 8);
  // R26fx3：渲染分辨率倍率重置为 1.0（档位默认 renderScale 已含 0.25/0.5/0.8/1.0，
  // painter = q.renderScale × 手动倍率；不再双乘）。
  ref.read(renderPrecisionScaleProvider.notifier).state = 1.0;
  ref.read(renderPrecisionProvider.notifier).state = 1.0;
  // 画面预设重置为标准（跟随档位）。
  ref.read(picturePresetProvider.notifier).state = PicturePreset.standard;
  ref.read(fpsLimitProvider.notifier).state =
      q == GraphicsQuality.perf ? FpsLimit.fps24 : FpsLimit.fps60;
  // R26fx3：极低档「所有剔除拉满」——视锥剔除也开（其他档位默认关）。
  ref.read(frustumCullEnabledProvider.notifier).state =
      q == GraphicsQuality.perf;
  ref.read(faceCullEnabledProvider.notifier).state = true;
  ref.read(occlusionCullEnabledProvider.notifier).state = true;
  ref.read(backFaceCullEnabledProvider.notifier).state = true;
  final bool low = q == GraphicsQuality.perf || q == GraphicsQuality.smooth;
  ref.read(noiseOverrideProvider.notifier).state = low ? false : null;
  ref.read(glassBlurOverrideProvider.notifier).state = low ? 0.0 : null;
  ref.read(bgAnimationOverrideProvider.notifier).state = low ? false : null;
  ref.read(liquidGlassOverrideProvider.notifier).state = low ? false : null;
}
