/// 网易云歌词接入测试（I 域 · 歌词修复）。
///
/// 纯逻辑验证，不联网：
/// - [NeteaseApi.getLyrics] 主歌词 / 纯音乐回退 romalrc / 无词 / 风控 → null /
///   同 id 缓存只打一次接口；
/// - [remoteLyricsFetcherProvider] 接线：netease 曲目走 getLyrics，其它源返回 null。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/providers/sources/netease_provider.dart';
import 'package:xingli_music/services/audio/sources/netease/netease_api.dart';
import 'package:xingli_music/widgets/lyrics/lyrics_view.dart';

const String _kLrc = '[00:12.00]第一行\n[00:18.50]第二行';
const String _kRoman = '[00:12.00]roman line';

http.Response _json(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );

NeteaseApi _apiWith(MockClient mock) =>
    NeteaseApi(client: mock, minInterval: Duration.zero);

void main() {
  group('NeteaseApi.getLyrics', () {
    test('正常：返回主歌词 lrc.lyric', () async {
      final NeteaseApi api = _apiWith(MockClient(
        (_) async => _json(<String, dynamic>{
          'code': 200,
          'lrc': <String, dynamic>{'lyric': _kLrc},
        }),
      ));
      addTearDown(api.close);

      expect((await api.getLyrics(123))?.lrc, _kLrc);
    });

    test('纯音乐：主歌词为空 → 回退 romalrc', () async {
      final NeteaseApi api = _apiWith(MockClient(
        (_) async => _json(<String, dynamic>{
          'code': 200,
          'lrc': <String, dynamic>{'lyric': ''},
          'romalrc': <String, dynamic>{'lyric': _kRoman},
        }),
      ));
      addTearDown(api.close);

      expect((await api.getLyrics(456))?.lrc, _kRoman);
    });

    test('无词：主歌词与回退都为空 → 返回 null', () async {
      final NeteaseApi api = _apiWith(MockClient(
        (_) async => _json(<String, dynamic>{
          'code': 200,
          'lrc': <String, dynamic>{'lyric': ''},
          'romalrc': <String, dynamic>{'lyric': ''},
        }),
      ));
      addTearDown(api.close);

      expect(await api.getLyrics(789), isNull);
    });

    test('译文：tlyric 随主歌词一并返回', () async {
      final NeteaseApi api = _apiWith(MockClient(
        (_) async => _json(<String, dynamic>{
          'code': 200,
          'lrc': <String, dynamic>{'lyric': _kLrc},
          'tlyric': <String, dynamic>{'lyric': 'translated line'},
        }),
      ));
      addTearDown(api.close);

      final LyricResult? r = await api.getLyrics(321);
      expect(r?.lrc, _kLrc);
      expect(r?.translation, 'translated line');
    });

    test('译文缺失：tlyric 为空 → translation 为 null', () async {
      final NeteaseApi api = _apiWith(MockClient(
        (_) async => _json(<String, dynamic>{
          'code': 200,
          'lrc': <String, dynamic>{'lyric': _kLrc},
          'tlyric': <String, dynamic>{'lyric': ''},
        }),
      ));
      addTearDown(api.close);

      final LyricResult? r = await api.getLyrics(322);
      expect(r?.lrc, _kLrc);
      expect(r?.translation, isNull);
    });

    test('业务错误码（如 -460 风控）→ 返回 null 不抛', () async {
      final NeteaseApi api = _apiWith(MockClient(
        (_) async => _json(<String, dynamic>{
          'code': -460,
          'message': 'cheating',
        }),
      ));
      addTearDown(api.close);

      expect(await api.getLyrics(1), isNull);
    });

    test('缓存：相同 songId 只打一次接口', () async {
      int hits = 0;
      final NeteaseApi api = _apiWith(MockClient((http.Request req) async {
        hits++;
        return _json(<String, dynamic>{
          'code': 200,
          'lrc': <String, dynamic>{'lyric': _kLrc},
        });
      }));
      addTearDown(api.close);

      expect((await api.getLyrics(999))?.lrc, _kLrc);
      expect((await api.getLyrics(999))?.lrc, _kLrc); // 命中缓存
      expect(hits, 1);
    });
  });

  group('remoteLyricsFetcherProvider（接线）', () {
    test('netease 曲目 → 走 getLyrics 返回歌词', () async {
      final MockClient mock = MockClient(
        (_) async => _json(<String, dynamic>{
          'code': 200,
          'lrc': <String, dynamic>{'lyric': _kLrc},
        }),
      );
      final NeteaseApi api = _apiWith(mock);
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          neteaseApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });

      final RemoteLyricsFetcher? fetch =
          container.read(remoteLyricsFetcherProvider);
      expect(fetch, isNotNull);

      final LyricResult? r = await fetch!(const Track(
        title: '测试曲',
        artist: '测试歌手',
        uri: 'netease://song/123',
        sourceId: 'netease',
        extras: <String, dynamic>{'songId': 123},
      ));
      expect(r?.lrc, _kLrc);
    });

    test('非 netease 曲目 → 返回 null（交给本地/降级）', () async {
      final NeteaseApi api = _apiWith(MockClient((_) async => _json(<String, dynamic>{
        'code': 200,
        'lrc': <String, dynamic>{'lyric': '不应被使用'},
      })));
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          neteaseApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });

      final RemoteLyricsFetcher? fetch =
          container.read(remoteLyricsFetcherProvider);
      expect(fetch, isNotNull);

      // 本地曲没有 songId、uri 不是 netease:// → 不应去打网易云接口
      final LyricResult? r = await fetch!(const Track(
        title: '本地曲',
        artist: '本地歌手',
        uri: 'C:\\Music\\song.mp3',
        sourceId: 'local',
      ));
      expect(r, isNull);
    });
  });

  group('LyricsCache（磁盘缓存）', () {
    test('put → get 往返一致（含译文）', () async {
      final Directory dir =
          Directory.systemTemp.createTempSync('lyrics_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final LyricsCache cache = LyricsCache(dir);

      const LyricResult r = LyricResult(lrc: _kLrc, translation: 'translation');
      await cache.put(123, r);

      final LyricResult? got = await cache.get(123);
      expect(got?.lrc, _kLrc);
      expect(got?.translation, 'translation');
    });

    test('未缓存 → null；空 lrc 视为无歌词', () async {
      final Directory dir =
          Directory.systemTemp.createTempSync('lyrics_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final LyricsCache cache = LyricsCache(dir);

      expect(await cache.get(999), isNull);
      await cache.put(1, const LyricResult(lrc: ''));
      expect(await cache.get(1), isNull);
    });
  });
}
