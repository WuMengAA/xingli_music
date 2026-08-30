/// ════════════════════════════════════════════════════════════════════════
/// OOBE 流派试听服务（cl17 补项：「风格选择能听歌」）
/// ════════════════════════════════════════════════════════════════════════
///
/// 纯编排、不持有播放器：把「流派 → 一首可试听曲目」解析为可注入函数，
/// UI 只调 [previewFor] 拿结果。网络与登录态全部外置：
/// - [canPreview]：试听可用性（正式走「网易云已登录」判定）
/// - [search]：按流派搜候选曲目（正式走 neteaseSourceProvider.search，
///   播放前其 uri 为占位符，由既有 StreamResolver 懒解析）
///
/// 失败一律降级为可展示的提示消息，绝不抛异常；空结果 / 网络异常 /
/// 未登录各有明确文案。可注入桩函数做纯 Dart 单测（零 Flutter 依赖）。
library;

import '../../models/track.dart';

/// 一次试听的结果。
class GenrePreview {
  /// 有可播放曲目时的成功结果（[message] 为空串）。
  const GenrePreview.track(Track t)
      : track = t,
        message = '';

  /// 不可用 / 失败结果（[track] 为 null，[message] 为可展示原因）。
  const GenrePreview.unavailable(this.message)
      : track = null;

  /// 非 null → 可直接交给播放器（PlaybackActions.playTrack）的曲目。
  final Track? track;

  /// [track] 为 null 时的可展示原因（登录引导 / 无结果 / 网络异常）。
  final String message;

  bool get ok => track != null;
}

/// 流派搜索函数：返回候选曲目（取首曲即试听）；抛异常视为失败。
typedef GenreSearch = Future<List<Track>> Function(String genre);

/// 试听可用性判定（如「网易云已登录」）。
typedef GenrePreviewAvailability = bool Function();

/// OOBE 流派试听服务。
class OobePreviewService {
  const OobePreviewService({
    required this.canPreview,
    required this.search,
  });

  final GenrePreviewAvailability canPreview;
  final GenreSearch search;

  /// 取一个流派的试听曲目。
  Future<GenrePreview> previewFor(String genre) async {
    if (!canPreview()) {
      return const GenrePreview.unavailable('登录网易云账号后，选风格时就能直接试听对应流派');
    }
    try {
      final List<Track> tracks = await search(genre.trim());
      if (tracks.isEmpty) {
        return const GenrePreview.unavailable('暂时没有可试听的曲目，换个风格试试');
      }
      return GenrePreview.track(tracks.first);
    } catch (_) {
      return const GenrePreview.unavailable('暂时无法试听，请稍后重试');
    }
  }
}