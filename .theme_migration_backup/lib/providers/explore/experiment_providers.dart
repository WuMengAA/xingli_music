import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/experiment.dart';
import '../../pages/explore/experiments/equalizer_page.dart';
import '../../pages/explore/experiments/mood_analysis_page.dart';
import '../../pages/explore/experiments/recommend_page.dart';
import '../../pages/explore/experiments/search_page.dart';
import '../../pages/explore/experiments/sensor_page.dart';
import '../../pages/explore/experiments/voxel_minigame_page.dart';
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
            id: 'search',
            name: '跨源搜索',
            description: '跨源 / 模糊搜索增强',
            icon: Icons.search_rounded,
            status: ExperimentStatus.stable,
            builder: () => const SearchExperimentPage(),
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
            id: 'voxel_game',
            name: '2.5D 小游戏',
            description: '类我的世界：移动 / 收集 / 计分',
            icon: Icons.videogame_asset_rounded,
            status: ExperimentStatus.experimenting,
            builder: () => const VoxelMinigamePage(),
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
