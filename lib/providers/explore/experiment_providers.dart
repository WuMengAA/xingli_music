import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/experiment.dart';
import '../../pages/explore/experiments/cast_page.dart';
import '../../pages/explore/experiments/companion_page.dart';
import '../../pages/explore/experiments/cue_sheet_page.dart';
import '../../pages/explore/experiments/equalizer_page.dart';
import '../../pages/explore/experiments/local_semantic_random_page.dart';
import '../../pages/explore/experiments/mood_analysis_page.dart';
import '../../pages/explore/experiments/net_library_page.dart';
import '../../pages/explore/experiments/netease_playlist_page.dart';
import '../../pages/explore/experiments/netease_recommend_page.dart';
import '../../pages/explore/experiments/recommend_page.dart';
import '../../pages/explore/experiments/scraper_page.dart';
import '../../pages/explore/experiments/sensor_page.dart';
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

/// 实验清单（数据驱动配置表，P0-M2-2）。
///
/// 不硬编码在 UI；新增实验只需在此追加。已下线示例保留注释。
final Provider<List<ExperimentItem>> experimentsProvider =
    Provider<List<ExperimentItem>>((Ref ref) => <ExperimentItem>[
          ExperimentItem(
            id: 'recommend',
            name: '智能推荐',
            description: '按当前场景情绪推荐曲目',
            icon: Icons.auto_awesome_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const RecommendPage(),
          ),
          ExperimentItem(
            id: 'local_random',
            name: '语义随机',
            description: '本地随机 · 按场景语义词库、离线可换一批',
            icon: Icons.shuffle_rounded,
            status: ExperimentStatus.stable,
            builder: () => const LocalSemanticRandomPage(),
          ),
          ExperimentItem(
            id: 'equalizer',
            name: '音效均衡器',
            description: '低中高频三档 + 4 组预设',
            icon: Icons.equalizer_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const EqualizerPage(),
          ),
          ExperimentItem(
            id: 'mood',
            name: '心情分析',
            description: '问卷 → 音乐心情匹配',
            icon: Icons.mood_rounded,
            status: ExperimentStatus.stable,
            builder: () => const MoodAnalysisPage(),
          ),
          ExperimentItem(
            id: 'sensor',
            name: '传感器',
            description: '光线 / 加速度 → 场景联动',
            icon: Icons.sensors_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const SensorPage(),
          ),
          ExperimentItem(
            id: 'companion',
            name: 'AI 陪伴（实验）',
            description: '一个陌生人，先由你开口；全程离线、模板生成',
            icon: Icons.chat_bubble_outline_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const CompanionPage(),
          ),
          ExperimentItem(
            id: 'netease_recommend',
            name: '网易云推荐',
            description: '每日精选 · 个性化无限漫游',
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
          // 电台房（station_lobby）已从实验区移除，转正为导航/主导航入口
          // （见 app_shell / 主导航），不再作为实验项展示。
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
