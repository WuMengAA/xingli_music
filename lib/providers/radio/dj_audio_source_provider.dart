/// ════════════════════════════════════════════════════════════════════════
/// DJ 音源偏好：VoiceHub「多音源显式切换」的持久化状态。
///
/// DJ 在电台页点源 chip 切换「本地 / 网易云 / 哔哩哔哩」，本 provider 记住
/// 当前偏好，供「DJ 自选」弹层默认选中对应平台；换台/重启后仍保持。
/// ════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DJ 音源偏好。
enum DjAudioSource {
  /// 本地曲库（默认）。
  local,

  /// 网易云在线。
  netease,

  /// 哔哩哔哩在线。
  bilibili,
}

class _DjAudioSourceNotifier extends StateNotifier<DjAudioSource> {
  _DjAudioSourceNotifier() : super(DjAudioSource.local);

  /// 启动时从 SharedPreferences 恢复上次偏好。
  Future<void> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('dj_audio_source');
    if (raw == null) return;
    state = DjAudioSource.values.asNameMap()[raw] ?? DjAudioSource.local;
  }

  /// 切换音源并持久化。
  Future<void> set(DjAudioSource src) async {
    state = src;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('dj_audio_source', src.name);
  }
}

final djAudioSourceProvider =
    StateNotifierProvider<_DjAudioSourceNotifier, DjAudioSource>(
  (ref) => _DjAudioSourceNotifier(),
);
