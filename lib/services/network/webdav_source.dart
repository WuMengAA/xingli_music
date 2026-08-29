import 'dart:convert';

import '../../models/track.dart';
import '../../services/network/webdav_client.dart';
import '../music_sources/music_source.dart';

/// WebDAV 网络音乐库源（T12）。
///
/// uri 约定：`webdav://<base64url(路径)>` —— 解析时还原出真实 http(s)
/// 流地址并附带 Basic 认证头（[playbackHeaders]）。不参与本地聚合
/// （目录由「网络音乐库」页动态浏览），仅承担占位解析。
class WebDavSource implements MusicSource {
  WebDavSource(this._client, {required String sourceId})
      : _sourceId = 'webdav:$sourceId';

  final WebDavClient _client;
  final String _sourceId;

  @override
  String get sourceId => _sourceId;

  @override
  bool get enabled => true;

  @override
  Future<List<Track>> getTracks() async => <Track>[];

  @override
  Future<String> resolveStreamUrl(Track track) async {
    if (!track.uri.startsWith('webdav://')) {
      throw StateError('非 WebDAV 占位 uri: ${track.uri}');
    }
    final String payload = track.uri.substring('webdav://'.length);
    final String path = utf8.decode(base64Url.decode(payload));
    final String base = _client.baseUrl.endsWith('/')
        ? _client.baseUrl.substring(0, _client.baseUrl.length - 1)
        : _client.baseUrl;
    return '$base/${path.replaceFirst(RegExp(r'^/+'), '')}';
  }

  @override
  Map<String, String> get playbackHeaders => _client.authHeaders;

  @override
  bool get requiresMediaKit => false;
}