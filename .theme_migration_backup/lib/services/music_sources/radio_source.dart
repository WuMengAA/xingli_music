import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/track.dart';
import 'music_source.dart';

/// 公开网络电台源（Radio Browser 开源目录，无需鉴权）。
///
/// 电台是「直播流」：无时长、无进度、无「下一首单首」语义，UI 据此隐藏进度条。
/// 按标签（ambient / jazz / lo-fi ...）拉取高票电台，契合「意境优先」场景联动。
class RadioSource implements MusicSource {
  /// Radio Browser 公共镜像，按顺序尝试，命中可用即停
  static const List<String> _mirrors = [
    'https://de1.api.radio-browser.info',
    'https://de2.api.radio-browser.info',
    'https://nl1.api.radio-browser.info',
    'https://at1.api.radio-browser.info',
  ];

  final List<String> tags;
  final String _sourceId;

  RadioSource({this.tags = const ['ambient'], String sourceId = 'radio'})
      : _sourceId = sourceId;

  @override
  String get sourceId => _sourceId;

  @override
  bool get enabled => true;

  /// 测试目录可达性（设置页「测试连接」按钮调用）
  Future<bool> testConnection() async {
    for (final String host in _mirrors) {
      try {
        final http.Response res =
            await http.get(Uri.parse('$host/json/stations/topvote/1'));
        if (res.statusCode == 200) return true;
      } catch (_) {
        // 换下一个镜像
      }
    }
    return false;
  }

  @override
  Future<List<Track>> getTracks() async {
    final String tagQuery = tags.isNotEmpty ? tags.join(',') : 'ambient';
    for (final String host in _mirrors) {
      try {
        final Uri uri = Uri.parse(
          '$host/json/stations/search',
        ).replace(queryParameters: <String, String>{
          'tag': tagQuery,
          'limit': '50',
          'hidebroken': 'true',
          'order': 'votes',
          'reverse': 'true',
        });
        final http.Response res = await http.get(uri);
        if (res.statusCode != 200) continue;
        final List<dynamic> stations =
            (jsonDecode(res.body) as List?) ?? const [];
        final List<Track> tracks = stations
            .where((dynamic s) =>
                (s['lastcheckok'] == 1 || s['lastcheckok'] == true) &&
                (s['url_resolved'] as String?)?.isNotEmpty == true)
            .map((dynamic s) {
          final Map<String, dynamic> st = s as Map<String, dynamic>;
          final String name = (st['name'] as String?)?.trim() ?? '未知电台';
          final String country = (st['country'] as String?) ?? '';
          final String tagStr = (st['tags'] as String?) ?? '';
          return Track(
            title: name,
            artist: [country, tagStr].where((e) => e.isNotEmpty).join(' · '),
            uri: st['url_resolved'] as String,
            source: TrackSource.stream,
            sourceId: _sourceId,
            isLiveStream: true,
            coverUrl: (st['favicon'] as String?)?.isNotEmpty == true
                ? st['favicon'] as String
                : null,
          );
        }).toList();
        if (tracks.isNotEmpty) return tracks;
      } catch (_) {
        // 换下一个镜像
      }
    }
    throw Exception('Radio Browser 所有镜像均不可达');
  }

  @override
  Future<String> resolveStreamUrl(Track track) async => track.uri;
}
