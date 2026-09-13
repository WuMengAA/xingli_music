import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_version.dart' show UpdateChannel;
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
import '../settings/settings_persistence_providers.dart';

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

/// 当前运行渠道（持久化于 SettingsRepository，切换后重启生效）。
///
/// 实验「测试通道」门控依据：正式渠道（Beta）只显示已毕业（全渠道）实验，
/// 尝鲜渠道（Alpha）额外显示仅挂测试通道的实验。
final Provider<UpdateChannel> currentChannelProvider =
    Provider<UpdateChannel>(
  (Ref ref) => ref.watch(settingsRepositoryProvider).updateChannel,
);

/// 实验清单（数据驱动配置表）。
///
/// 排序原则：
/// 1. **已毕业 · 真实可用**（`stable`）在前——全渠道可见；
/// 2. `experimenting` 在后——真实链路已通但需外部配置/登录；
/// 3. **测试通道**（`visibleChannels: {alpha}`）——仅 Alpha 可见，正式渠道隐藏。
///
/// 「毕业」原则（2026-09-13 定）：实验一旦具备**真实链路**就毕业为正式功能，
/// 不再长期停留在实验阶段；未就绪的留在测试通道（Alpha）继续养。
/// 页面实现文件保留在 `lib/pages/explore/experiments/`，毕业只需改此处配置。
///
/// 不硬编码在 UI；新增实验只需在此追加。
final Provider<List<ExperimentItem>> experimentsProvider =
    Provider<List<ExperimentItem>>((Ref ref) => <ExperimentItem>[
          // ── 已毕业 · 真实可用（全渠道可见）──────────────────
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
          // 毕业（本次）：真 EQ 链路早已就绪（Android AndroidEqualizer 真滤波 /
          // Windows mpv af=equalizer 真 DSP / 其余模拟层），此前被误下线。
          ExperimentItem(
            id: 'equalizer',
            name: '音效均衡器',
            description: '10 段真 EQ · Android 真滤波 / Windows mpv DSP · 10 组预设',
            icon: Icons.graphic_eq_rounded,
            status: ExperimentStatus.stable,
            builder: () => const EqualizerPage(),
          ),
          // 毕业（本次）：MusicBrainz 真实元数据 / 封面查询链路已通。
          ExperimentItem(
            id: 'scraper',
            name: '刮削器',
            description: 'MusicBrainz 元数据查询 · 补全错名文件与封面',
            icon: Icons.manage_search_rounded,
            status: ExperimentStatus.stable,
            builder: () => const ScraperPage(),
          ),
          // 毕业（本次）：真实 WebDAV 远程曲库（浏览 + 在线播放）。
          ExperimentItem(
            id: 'net_library',
            name: '网络音乐库',
            description: 'WebDAV 曲库 · 远程目录浏览在线播放',
            icon: Icons.cloud_rounded,
            status: ExperimentStatus.stable,
            builder: () => const NetLibraryPage(),
          ),
          // ── 实验中 · 官方源 / 需外部配置（全渠道可见）────────
          ExperimentItem(
            id: 'netease_recommend',
            name: '网易云推荐',
            description: '每日精选 · 官方源无限漫游（需登录网易云）',
            icon: Icons.explore_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const NeteaseRecommendPage(),
          ),
          ExperimentItem(
            id: 'netease_playlist',
            name: '网易云歌单',
            description: '我的歌单 · 收藏曲目（需登录网易云）',
            icon: Icons.queue_music_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const NeteasePlaylistPage(),
          ),
          // 毕业（有条件）：离线无 LLM 时曾只有固定回复；现接真大模型
          // （设置→大模型配置 baseUrl/key/model），未配置则本地兜底——真实链路已通，
          // 按「毕业原则」转正式功能（出圈到探索页「功能」区，不再被实验同意门拦截）。
          ExperimentItem(
            id: 'companion',
            name: 'AI 陪伴',
            description: 'AI 音乐伙伴 · 需在设置配置大模型（未配置走本地兜底）',
            icon: Icons.auto_awesome_rounded,
            status: ExperimentStatus.stable,
            builder: () => const CompanionPage(),
          ),
          ExperimentItem(
            id: 'recommend',
            name: '智能推荐',
            description: '大模型按口味推荐 · 需在设置配置大模型（未配置走本地兜底）',
            icon: Icons.recommend_rounded,
            status: ExperimentStatus.stable,
            builder: () => const RecommendPage(),
          ),
          ExperimentItem(
            id: 'mood',
            name: '心情分析',
            description: '按心情选曲 · 需在设置配置大模型（未配置走本地兜底）',
            icon: Icons.mood_rounded,
            status: ExperimentStatus.stable,
            builder: () => const MoodAnalysisPage(),
          ),
          // ── 测试通道（仅 Alpha 可见，正式渠道隐藏）──────────
          // 传感器属开发者调试工具，非面向用户功能：留在 Alpha 测试通道。
          ExperimentItem(
            id: 'sensor',
            name: '传感器',
            description: '设备传感器调试 · 仅测试通道（Alpha）可见',
            icon: Icons.sensors_rounded,
            status: ExperimentStatus.experimenting,
            visibleChannels: const <UpdateChannel>{UpdateChannel.alpha},
            builder: () => const SensorPage(),
          ),
        ]);
