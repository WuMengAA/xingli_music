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


/// 设置页二级分类（R22 用户定版三级结构）：
///
/// ```
/// {关于}                    → about
/// {基础                     → basic
///    【音频 > 音量·音源】     → audio
///    【画面 > 外观·场景·游戏】 → visual
///    【通知】                → notification
/// }
/// {高级 > 实验}              → advanced(experiment)
/// ```
enum SettingsSection {
  /// 基础·音频：音量、静音、播放模式、EQ + 音源入口。
  audio,

  /// 基础·画面：外观（主题/皮肤/密度）、场景、游戏、性能。
  visual,

  /// 基础·通知：通知中心、后台播放。
  notification,

  /// 高级·实验：同意状态、逐项启停、大模型。
  experiment,

  /// 关于：应用信息、日志上报。
  about,
}

/// 设置页一级分组（用户定版：关于 / 基础 / 高级）。
enum SettingsGroup {
  /// ① 基础：音频 + 画面 + 通知
  basic,

  /// ② 高级：实验
  advanced,

  /// ③ 关于
  about,
}

/// 分类的展示属性（标签 / 图标 / 搜索关键词 / 分组）。
extension SettingsSectionX on SettingsSection {
  /// 所属一级分组。
  SettingsGroup get group => switch (this) {
        SettingsSection.audio ||
        SettingsSection.visual ||
        SettingsSection.notification =>
          SettingsGroup.basic,
        SettingsSection.experiment => SettingsGroup.advanced,
        SettingsSection.about => SettingsGroup.about,
      };

  /// 竖栏 tile 文字（52dp 宽栏内仅容 2 个汉字）。
  String get label => switch (this) {
        SettingsSection.audio => '音频',
        SettingsSection.visual => '画面',
        SettingsSection.notification => '通知',
        SettingsSection.experiment => '实验',
        SettingsSection.about => '关于',
      };

  /// 详情区标题。
  String get title => switch (this) {
        SettingsSection.audio => '音频 · 音量与音源',
        SettingsSection.visual => '画面 · 外观与场景',
        SettingsSection.notification => '通知中心',
        SettingsSection.experiment => '实验管理',
        SettingsSection.about => '关于星璃',
      };

  /// tile 图标（26dp）。
  IconData get icon => switch (this) {
        SettingsSection.audio => Icons.music_note_rounded,
        SettingsSection.visual => Icons.palette_outlined,
        SettingsSection.notification => Icons.notifications_none_rounded,
        SettingsSection.experiment => Icons.science_outlined,
        SettingsSection.about => Icons.info_outline_rounded,
      };

  /// 搜索匹配用关键词（P1-02：设置页搜索过滤设置项）。
  List<String> get keywords => switch (this) {
        SettingsSection.audio => const <String>[
            '音频',
            '音量',
            '静音',
            '播放模式',
            '顺序',
            '随机',
            '单曲',
            '均衡器',
            'EQ',
            '音效',
            '音源',
            '服务器',
            'subsonic',
            '本地',
            '目录',
            '电台',
            '网易云',
            '登录',
            'volume',
            'mute',
            'mode',
            'equalizer',
            'source',
            'netease',
          ],
        SettingsSection.visual => const <String>[
            '画面',
            '外观',
            '主题',
            '皮肤',
            '浅色',
            '深色',
            '跟随系统',
            '明暗',
            '密度',
            '紧凑',
            '场景',
            '编辑器',
            '调色盘',
            '配色',
            '心情',
            '游戏',
            '体素',
            'AI',
            '陪伴',
            '性能',
            '质量',
            '帧率',
            'fps',
            '图形',
            '后端',
            '渲染',
            'OpenGL',
            'Vulkan',
            'DX11',
            '特效',
            '噪点',
            '模糊',
            '动画',
            '液态玻璃',
            'theme',
            'skin',
            'density',
            'scene',
            'voxel',
            'performance',
            'engine',
            'backend',
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
        SettingsSection.experiment => const <String>[
            '实验',
            '同意',
            '撤销',
            '传感器',
            '大模型',
            'AI',
            '小游戏',
            'experiment',
            'consent',
            'sensor',
            'llm',
          ],
        SettingsSection.about => const <String>[
            '关于',
            '版本',
            '日志',
            '上报',
            'about',
            'version',
            'log',
            'upload',
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

/// 一级分组的展示属性（R22 用户定版：关于 / 基础 / 高级）。
extension SettingsGroupX on SettingsGroup {
  /// 分组标题（顶部小标，4 字内紧凑）。
  String get label => switch (this) {
        SettingsGroup.basic => '基础',
        SettingsGroup.advanced => '高级',
        SettingsGroup.about => '关于',
      };

  /// 分组图标（左栏分组标题前的图标）。
  IconData get icon => switch (this) {
        SettingsGroup.basic => Icons.tune_rounded,
        SettingsGroup.advanced => Icons.science_outlined,
        SettingsGroup.about => Icons.info_outline_rounded,
      };

  /// 分组内包含的 SettingsSection 列表（按显示顺序）。
  List<SettingsSection> get sections => SettingsSection.values
      .where((SettingsSection s) => s.group == this)
      .toList(growable: false);
}

/// 当前选中的设置分类（默认「音频」，保持历史习惯首项）。
final StateProvider<SettingsSection> settingsSectionProvider =
    StateProvider<SettingsSection>((Ref ref) => SettingsSection.audio);

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
