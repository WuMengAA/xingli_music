import '../../models/track.dart';

/// 曲库数据源抽象。
///
/// 本地扫描、自建 Subsonic 服务器、公开电台、演示流都实现本接口。
/// 现有 AudioService 只认 [Track]（isRemote → setUrl / setFilePath），
/// 因此新增任何源都不必改动播放层，差异全部收敛在 [resolveStreamUrl]。
abstract class MusicSource {
  /// 数据源唯一 id（'local' / 'demo' / ServerConfig.name / 'radio'）
  String get sourceId;

  /// 是否参与曲库聚合
  bool get enabled;

  /// 拉取该源的全部曲目（失败应抛异常，由聚合层 catch 回退）
  Future<List<Track>> getTracks();

  /// 把一首曲解析为可直接播放的 URL。
  /// 多数源在 [getTracks] 时已经预解析并填好 uri，本方法作为按需重解析的备用。
  Future<String> resolveStreamUrl(Track track);

  /// 播放 CDN 必须携带的请求头（如网易云的 User-Agent / Referer）。
  /// 多数源返回空；需要鉴权头/反热链头的源自行实现（`NeteaseSource` 已实现）。
  Map<String, String> get playbackHeaders;

  /// 是否需要 media_kit 后端才能播放（默认 false = just_audio 即可）。
  ///
  /// 网易云 / B站 的 CDN 流格式特殊、带签名，just_audio 默认后端无法解码，
  /// 必须走 media_kit（libmpv）。[AudioService] 据此在切歌时路由到正确后端。
  bool get requiresMediaKit => false;
}
