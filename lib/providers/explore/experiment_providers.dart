import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/experiment.dart';
import '../../pages/explore/experiments/cast_page.dart';
import '../../pages/explore/experiments/cue_sheet_page.dart';
import '../../pages/explore/experiments/local_semantic_random_page.dart';
import '../../pages/explore/experiments/net_library_page.dart';
import '../../pages/explore/experiments/netease_playlist_page.dart';
import '../../pages/explore/experiments/netease_recommend_page.dart';
import '../../pages/explore/experiments/scraper_page.dart';
import '../../providers/color_memory/color_memory_providers.dart';
import '../../services/log_service.dart';

/// 实验同意状态（持久化 key：`experiment_consent_v1`）。
final StateNotifierProvider<ExperimentConsentNotifier, ExperimentConsent>
    experimentConsentProvider =
    StateNotifierProvider<ExperimentConsentNotifier, ExperimentConsent>(
  (Ref ref) => ExperimentConsentNotifier(ref.watch(prefsProvider)),
);

class ExperimentConsentNotifier extends StateNotifier<ExperimentConsent> {
  ExperimentConsentNotifier(this._prefs) : super(const ExperimentConsent.initial()) {
    _load();
  }

  static const String _key = 'experiment_consent_v1';
  final SharedPreferences _prefs;

  void _load() {
    final String? raw = _prefs.getString(_key);
    if (raw == null) {
      state = const ExperimentConsent.initial();
      return;
    }
    try {
      state = ExperimentConsent.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      LogService.instance.w('experiment', '同意状态解析失败: $e');
      state = const ExperimentConsent.initial();
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(_key, jsonEncode(state.toJson()));
  }

  /// 同意并进入（P0-M2-1）。
  Future<void> agree() async {
    state = state.copyWith(agreed: true);
    await _persist();
  }

  /// 撤销同意（退出全部实验，P1-M2-5）。
  Future<void> revoke() async {
    state = state.copyWith(agreed: false, enabled: const <String, bool>{});
    await _persist();
  }

  /// 逐项启停（P1-M2-5）。
  Future<void> setEnabled(String id, bool on) async {
    final Map<String, bool> next = Map<String, bool>.of(state.enabled)
      ..[id] = on;
    state = state.copyWith(enabled: next);
    await _persist();
  }
}

/// 实验清单（数据驱动配置表，P0-M2-2）· **T 系列质量排序**。
///
/// 排序原则（cl17 · 2026-08-31）：
///
/// 1. **稳定且真实可用**的实验优先（`stable` 在前，`experimenting` 在后）；
/// 2. 同类实验按「数据源可靠性」排：网易云官方 > 本地真实计算 > 第三方远端；
/// 3. 无真实效果的**劣质内容已下线**（见下方「已下线清单」），不再进网格——
///    用户反馈：智能推荐/心情分析/AI 陪伴在离线无 LLM 下只有固定回复，
///    音效均衡器无真实滤镜合成，传感器应归开发者调试工具而非功能。
///
/// 页面实现文件保留在 `lib/pages/explore/experiments/`（含 `EqualizerPage`
/// 仍由设置项注册表引用），便于后续修好效果后重新接入，不必重写。
///
/// 不硬编码在 UI；新增实验只需在此追加。
final Provider<List<ExperimentItem>> experimentsProvider =
    Provider<List<ExperimentItem>>((Ref ref) => <ExperimentItem>[
          // ── 稳定 · 本地真实可用 ──────────────────────────────
          ExperimentItem(
            id: 'local_random',
            name: '语义随机',
            description: '本地随机 · 按场景语义词库、离线可换一批',
            icon: Icons.shuffle_rounded,
            status: ExperimentStatus.stable,
            builder: () => const LocalSemanticRandomPage(),
          ),
          ExperimentItem(
            id: 'cast_stream',
            name: '投屏',
            description: '局域网投屏 · 浏览器/VLC/电视盒直接播放',
            icon: Icons.cast_rounded,
            status: ExperimentStatus.stable,
            builder: () => const CastPage(),
          ),
          ExperimentItem(
            id: 'cue_sheet',
            name: 'CUE 分轨',
            description: '解析整轨 CUE · 逐轨自动 seek 播放',
            icon: Icons.album_rounded,
            status: ExperimentStatus.stable,
            builder: () => const CueSheetPage(),
          ),
          // ── 实验中 · 官方源 / 远端工具 ───────────────────────
          ExperimentItem(
            id: 'netease_recommend',
            name: '网易云推荐',
            description: '每日精选 · 官方源无限漫游',
            icon: Icons.explore_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const NeteaseRecommendPage(),
          ),
          ExperimentItem(
            id: 'netease_playlist',
            name: '网易云歌单',
            description: '我的歌单 · 收藏曲目',
            icon: Icons.queue_music_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const NeteasePlaylistPage(),
          ),
          ExperimentItem(
            id: 'net_library',
            name: '网络音乐库',
            description: 'WebDAV 曲库 · 远程目录浏览在线播放',
            icon: Icons.cloud_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const NetLibraryPage(),
          ),
          ExperimentItem(
            id: 'scraper',
            name: '刮削器',
            description: 'MusicBrainz 元数据查询 · 补全错名文件',
            icon: Icons.manage_search_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const ScraperPage(),
          ),
          // ── 已下线清单（cl17，页面文件保留，不再进实验网格）────
          // recommend「智能推荐」：离线无 LLM 只有固定回复，等于垃圾功能 → 下线。
          // mood「心情分析」：问卷结果映射为固定曲目集合，非「分析」初心 → 下线。
          // equalizer「音效均衡器」：无真实滤镜合成链路，滑杆无实际效果 →
          //   从实验区下线（设置「音频」入口仍保留，等待真实 EQ 实现后回归）。
          // sensor「传感器」：属开发者调试/测试工具，不作为面向用户的功能 → 下线。
          // companion「AI 陪伴」：离线模板回复，体验最差 → 下线。
          // station_lobby 已从实验区移除，转正为导航/主导航入口（见 app_shell）。
          // 示例：已下线（P0-M2-4 置灰禁入）
          // ExperimentItem(
          //   id: 'old_x',
          //   name: '旧实验',
          //   description: '已下线的示例',
          //   icon: Icons.block,
          //   status: ExperimentStatus.retired,
          //   builder: () => const SizedBox.shrink(),
          // ),
        ]);
