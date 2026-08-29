import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingli_music/services/musicbrainz/scraper.dart';

void main() {
  group('MusicBrainzScraper', () {
    test('search 构造 query 并解析 recordings', () async {
      late Uri captured;
      final MusicBrainzScraper scraper = MusicBrainzScraper(
        client: MockClient((http.Request req) async {
          captured = req.url;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'recordings': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'rec-1',
                  'title': 'Fly Me To The Moon',
                  'length': 152000,
                  'artist-credit': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'artist': <String, dynamic>{'name': 'Frank Sinatra'},
                      'joinphrase': ''
                    },
                  ],
                  'releases': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'id': 'rel-1',
                      'title': 'It Might as Well Be Swing',
                    },
                  ],
                },
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );

      final List<ScrapeHit> hits = await scraper.search(
        title: 'Fly Me To The Moon',
        artist: 'Frank Sinatra',
        limit: 5,
      );

      expect(captured.path, '/ws/2/recording');
      expect(captured.queryParameters['fmt'], 'json');
      expect(captured.queryParameters['limit'], '5');
      expect(
        captured.queryParameters['query'],
        contains('recording:"Fly Me To The Moon"'),
      );
      expect(
        captured.queryParameters['query'],
        contains('AND artist:"Frank Sinatra"'),
      );

      expect(hits.length, 1);
      final ScrapeHit h = hits.first;
      expect(h.title, 'Fly Me To The Moon');
      expect(h.artist, 'Frank Sinatra');
      expect(h.album, 'It Might as Well Be Swing');
      expect(h.releaseId, 'rel-1');
      expect(h.durationMs, 152000);
      expect(h.coverUrl, contains('coverartarchive.org/release/rel-1'));
    });

    test('artist 为空时 query 不追加 AND artist', () async {
      late Uri captured;
      final MusicBrainzScraper scraper = MusicBrainzScraper(
        client: MockClient((http.Request req) async {
          captured = req.url;
          return http.Response(
              jsonEncode(<String, dynamic>{'recordings': <dynamic>[]}),
              200,
              headers: <String, String>{});
        }),
      );
      await scraper.search(title: '纯音乐');
      expect(captured.queryParameters['query'], isNot(contains('AND artist')));
    });

    test('429 抛节流异常', () async {
      final MusicBrainzScraper scraper = MusicBrainzScraper(
        client: MockClient(
          (http.Request req) async => http.Response('rate limited', 429),
        ),
      );
      expect(
        () => scraper.search(title: 'x'),
        throwsA(isA<MusicBrainzException>()),
      );
    });
  });
}