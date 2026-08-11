import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../../models/server_config.dart';
import '../../models/track.dart';
import 'music_source.dart';

/// Subsonic / Navidrome / Jellyfin 兼容数据源。
///
/// 鉴权采用官方推荐的 token 方式：t = md5(password + salt)，salt 随机，
/// 密码不直接出现在 URL 中。token 长期有效，故 [getTracks] 时直接预解析出
/// 可播放的流地址与封面地址填入 [Track]，播放层无需二次解析。
class SubsonicSource implements MusicSource {
  final ServerConfig config;

  late final String _base;
  late final String _salt;
  late final String _token;

  SubsonicSource(this.config) {
    final String raw = config.baseUrl.trim();
    _base = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    _salt = _randomSalt();
    _token = md5.convert(utf8.encode('${config.password}$_salt')).toString();
  }

  String _randomSalt() {
    final Random r = Random.secure();
    final Uint8List bytes = Uint8List(12);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = r.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uri _endpoint(String ep, [Map<String, String> extra = const {}]) {
    final Map<String, String> q = <String, String>{
      'u': config.user,
      's': _salt,
      't': _token,
      'c': 'stelarith',
      'v': '1.16.1',
      'f': 'json',
      ...extra,
    };
    return Uri.parse('$_base/rest/$ep.view').replace(queryParameters: q);
  }

  String _streamUrl(String id) => _endpoint('stream', {'id': id}).toString();
  String _coverUrl(String id) =>
      _endpoint('getCoverArt', {'id': id}).toString();

  @override
  String get sourceId => config.name;

  @override
  bool get enabled => config.enabled;

  /// 测试连接（设置页「测试连接」按钮调用）
  Future<bool> testConnection() async {
    try {
      final Uri uri = _endpoint('ping');
      final http.Response res = await http.get(uri);
      if (res.statusCode != 200) return false;
      final dynamic json = jsonDecode(res.body);
      return json['subsonic-response']?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Track>> getTracks() async {
    final Uri uri = _endpoint('getRandomSongs', {'size': '60'});
    final http.Response res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Subsonic 请求失败 (${res.statusCode})');
    }
    final dynamic json = jsonDecode(res.body);
    final dynamic resp = json['subsonic-response'];
    if (resp == null || resp['status'] != 'ok') {
      throw Exception('Subsonic 鉴权或响应异常');
    }
    final List<dynamic> songs =
        (resp['randomSongs']?['song'] as List?) ?? const [];
    return songs.map((dynamic s) {
      final Map<String, dynamic> song = s as Map<String, dynamic>;
      final String id = song['id'] as String;
      final String? coverArt = song['coverArt'] as String?;
      return Track(
        title: (song['title'] as String?) ?? '未知曲目',
        artist: (song['artist'] as String?) ?? '未知艺术家',
        uri: _streamUrl(id),
        source: TrackSource.stream,
        sourceId: config.name,
        coverUrl: coverArt != null ? _coverUrl(coverArt) : null,
      );
    }).toList();
  }

  @override
  Future<String> resolveStreamUrl(Track track) async => track.uri;
}
