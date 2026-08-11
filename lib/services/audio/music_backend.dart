/// ════════════════════════════════════════════════════════════════════════
/// 音乐播放后端抽象（S2，media_kit 迁移）
/// ════════════════════════════════════════════════════════════════════════
///
/// `AudioService` 只依赖本抽象，不直接触碰 just_audio / media_kit：
/// - [JustAudioBackend]：现状（just_audio 0.9.x），行为零变化；
/// - [MediaKitBackend]：media_kit（libmpv），全格式 / Hi-Res / 无缝播放。
///
/// 切换：`AudioService` 构造时注入；默认 just_audio（稳妥回退）。
library;

import 'dart:async';

/// 播放引擎处理状态（跨后端统一语义）。
enum MusicProcess {
  /// 空闲（无曲目）
  idle,

  /// 加载 / 缓冲中
  loading,

  /// 就绪（可播放）
  ready,

  /// 播放完成
  completed,
}

/// 引擎一次状态快照：处理状态 + 是否在播放。
class MusicEngineState {
  const MusicEngineState({required this.processing, required this.playing});

  final MusicProcess processing;
  final bool playing;

  @override
  String toString() => 'MusicEngineState($processing, playing=$playing)';
}

/// 音乐播放后端统一接口（S2）。
abstract class MusicBackend {
  /// 当前是否在播放（同步查询）。
  bool get playing;

  /// 当前音量（0~1）。
  double get volume;

  /// 引擎状态流（处理状态 + 播放标志）。
  Stream<MusicEngineState> get stateStream;

  /// 播放位置流（进度；未知为 null，与 just_audio 语义一致）。
  Stream<Duration?> get positionStream;

  /// 曲目时长流（未知为 null）。
  Stream<Duration?> get durationStream;

  /// 打开远程 URI 并准备播放（可带请求头，防 CDN 403）。
  Future<void> openUri(Uri uri, {Map<String, String>? headers});

  /// 打开远程 URL 并准备播放。
  Future<void> openUrl(String url, {Map<String, String>? headers});

  /// 打开本地文件路径并准备播放。
  Future<void> openPath(String path);

  /// 播放 / 继续。
  Future<void> play();

  /// 暂停。
  Future<void> pause();

  /// 跳转。
  Future<void> seek(Duration position);

  /// 设置音量（0~1）。
  Future<void> setVolume(double volume);

  /// 释放资源。
  Future<void> dispose();
}
