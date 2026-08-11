/// ════════════════════════════════════════════════════════════════════════
/// 设置页 UI 状态（Master-Detail）
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据 P0-F2/F3【已裁决 · Master-Detail】：设置卡片左侧 52dp 竖栏含 5 个
/// 分类 tile，右侧详情区展示当前分类。
///
/// ### 分类重映射（Q5 已裁决 · 功能性偏离已授权）
/// 设计稿只给了 5 个空槽位，未标注文字；这里把 5 个槽位映射到本 App
/// **真实存在的能力**，保证既有页面全部可达、零功能倒退：
///
/// | 槽位 | 分类   | 承接能力                                            |
/// |------|--------|-----------------------------------------------------|
/// | ①    | 播放   | 音量 / 静音 / 播放模式 / 粒子开关（原 MorePanel + VolumeSlider） |
/// | ②    | 音源   | `ServerSettingsPage`（P0-F4）                        |
/// | ③    | 场景   | `SceneEditorPage` + `PalettePanel` + 心情（P0-F5 / P1-08） |
/// | ④    | 通知   | 后台播放 / 锁屏控件说明与开关                        |
/// | ⑤    | 关于   | 应用名称与版本号（P0-F6）                            |
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/shell_providers.dart';


/// 设置页 7 个分类槽位。
enum SettingsSection {
  /// ① 播放：音量、静音、播放模式、视觉粒子。
  playback,

  /// ② 音源：服务器 / 本地目录 / 电台（`ServerSettingsPage`）。
  source,

  /// ③ 场景：场景编辑器、调色盘、心情。
  scene,

  /// ④ 通知：通知中心（运行状态 / 媒体控制 / 场景状态）。
  notification,

  /// ⑤ 关于：应用信息。
  about,

  /// ⑥ 实验：同意状态 / 撤销同意 / 逐项启停（v2 M2 · P1-M2-5）。
  experiment,

  /// ⑦ 外观：主题（明暗/跟随系统）与皮肤（R16）。
  appearance,
}

/// 设置页 5 个一级分组（v3 整理）：把 7 个二级分类归到 5 组，左栏按组
/// 显示分组标题 + 组内分类 tile，detail 仍按 [SettingsSection] 渲染。
///
/// 合并规则：
/// - 播放组 = 播放 + 音源（音乐相关都在这里）
/// - 外观组 = 外观 + 场景（视觉相关）
/// - 通知 / 实验 / 关于 各自独立
enum SettingsGroup {
  /// ① 播放：音量/模式/均衡/EQ + 音源管理（合并 playback + source）
  play,

  /// ② 外观：主题/皮肤 + 场景编辑/2.5D（合并 appearance + scene）
  appearance,

  /// ③ 通知：通知中心、权限、后台播放
  notification,

  /// ④ 实验：同意状态、逐项启停
  experiment,

  /// ⑤ 关于：应用信息
  about,
}

/// 分类的展示属性（标签 / 图标 / 搜索关键词 / 分组）。
extension SettingsSectionX on SettingsSection {
  /// 所属一级分组（用于左栏分组渲染）。
  SettingsGroup get group => switch (this) {
        SettingsSection.playback || SettingsSection.source => SettingsGroup.play,
        SettingsSection.appearance ||
        SettingsSection.scene =>
          SettingsGroup.appearance,
        SettingsSection.notification => SettingsGroup.notification,
        SettingsSection.experiment => SettingsGroup.experiment,
        SettingsSection.about => SettingsGroup.about,
      };

  /// 竖栏 tile 文字（52dp 宽栏内仅容 2 个汉字）。
  String get label => switch (this) {
        SettingsSection.playback => '播放',
        SettingsSection.source => '音源',
        SettingsSection.scene => '场景',
        SettingsSection.notification => '通知',
        SettingsSection.about => '关于',
        SettingsSection.experiment => '实验',
        SettingsSection.appearance => '外观',
      };

  /// 详情区标题。
  String get title => switch (this) {
        SettingsSection.playback => '播放设置',
        SettingsSection.source => '音源与服务器',
        SettingsSection.scene => '场景与配色',
        SettingsSection.notification => '通知中心',
        SettingsSection.about => '关于星璃',
        SettingsSection.experiment => '实验管理',
        SettingsSection.appearance => '外观与主题',
      };

  /// tile 图标（26dp）。
  IconData get icon => switch (this) {
        SettingsSection.playback => Icons.play_circle_outline_rounded,
        SettingsSection.source => Icons.dns_outlined,
        SettingsSection.scene => Icons.auto_awesome_outlined,
        SettingsSection.notification => Icons.notifications_none_rounded,
        SettingsSection.about => Icons.info_outline_rounded,
        SettingsSection.experiment => Icons.science_outlined,
        SettingsSection.appearance => Icons.palette_outlined,
      };

  /// 搜索匹配用关键词（P1-02：设置页搜索过滤设置项）。
  List<String> get keywords => switch (this) {
        SettingsSection.playback => const <String>[
            '播放',
            '音量',
            '静音',
            '播放模式',
            '顺序',
            '倒序',
            '随机',
            '单曲',
            '粒子',
            'volume',
            'mute',
            'mode',
          ],
        SettingsSection.source => const <String>[
            '音源',
            '服务器',
            'subsonic',
            '本地',
            '目录',
            '电台',
            'minecraft',
            '扫描',
            'server',
            'source',
          ],
        SettingsSection.scene => const <String>[
            '场景',
            '编辑器',
            '调色盘',
            '配色',
            '主色',
            '心情',
            'scene',
            'palette',
            'mood',
          ],
        SettingsSection.notification => const <String>[
            '通知',
            '后台',
            '锁屏',
            '通知栏',
            '耳机',
            'notification',
            'background',
          ],
        SettingsSection.about => const <String>[
            '关于',
            '版本',
            '日志',
            'about',
            'version',
            'log',
          ],
        SettingsSection.experiment => const <String>[
            '实验',
            '同意',
            '撤销',
            '传感器',
            '均衡器',
            '小游戏',
            '心情',
            'experiment',
            'consent',
            'sensor',
            'equalizer',
          ],
        SettingsSection.appearance => const <String>[
            '外观',
            '主题',
            '皮肤',
            '浅色',
            '深色',
            '跟随系统',
            '明暗',
            'theme',
            'skin',
            'dark',
            'light',
          ],
      };

  /// 关键词命中判断（大小写不敏感；空串视为命中）。
  bool matches(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (label.toLowerCase().contains(q)) return true;
    if (title.toLowerCase().contains(q)) return true;
    return keywords.any((String k) => k.toLowerCase().contains(q));
  }
}

/// 一级分组的展示属性（v3 整理后用）。
extension SettingsGroupX on SettingsGroup {
  /// 分组标题（顶部小标，2 字紧凑）。
  String get label => switch (this) {
        SettingsGroup.play => '播放与音源',
        SettingsGroup.appearance => '外观与场景',
        SettingsGroup.notification => '通知',
        SettingsGroup.experiment => '实验',
        SettingsGroup.about => '关于',
      };

  /// 分组图标（左栏分组标题前的图标）。
  IconData get icon => switch (this) {
        SettingsGroup.play => Icons.play_circle_outline_rounded,
        SettingsGroup.appearance => Icons.palette_outlined,
        SettingsGroup.notification => Icons.notifications_none_rounded,
        SettingsGroup.experiment => Icons.science_outlined,
        SettingsGroup.about => Icons.info_outline_rounded,
      };

  /// 分组内包含的 SettingsSection 列表（按显示顺序）。
  List<SettingsSection> get sections => SettingsSection.values
      .where((SettingsSection s) => s.group == this)
      .toList(growable: false);
}

/// 当前选中的设置分类（默认「播放」）。
final StateProvider<SettingsSection> settingsSectionProvider =
    StateProvider<SettingsSection>((Ref ref) => SettingsSection.playback);

/// 设置页搜索命中的分类集合（P1-02）。
///
/// 关键词为空时返回全部 5 个分类；否则按 [SettingsSectionX.matches] 过滤。
final Provider<List<SettingsSection>> settingsSectionMatchesProvider =
    Provider<List<SettingsSection>>((Ref ref) {
  final String query = ref.watch(searchQueryProvider(ShellPage.settings));
  if (query.trim().isEmpty) return SettingsSection.values;
  final List<SettingsSection> hits = SettingsSection.values
      .where((SettingsSection s) => s.matches(query))
      .toList(growable: false);
  // 无命中时不清空竖栏（否则用户会以为设置页坏了），退回全量。
  return hits.isEmpty ? SettingsSection.values : hits;
});
