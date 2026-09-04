import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingli_music/services/voicehub/voicehub_client.dart';

void main() {
  group('VoiceHubClient', () {
    test('fetchSongs 解析点歌列表（data 数组）', () async {
      final client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        apiKey: 'test-key',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/open/songs.get');
          expect(req.headers['X-API-Key'], 'test-key');
          expect(req.url.queryParameters['limit'], '50');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 1,
                  'title': '夜曲',
                  'artist': '周杰伦',
                  'coverUrl': 'https://x/c.jpg',
                  'musicPlatform': 'netease',
                  'musicId': '123',
                  'playCount': 3,
                  'voteCount': 7,
                  'requester': 'shaoze',
                  'status': 'pending',
                },
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final List<VoiceHubSong> songs = await client.fetchSongs(limit: 50);
      expect(songs, hasLength(1));
      expect(songs.first.title, '夜曲');
      expect(songs.first.artist, '周杰伦');
      expect(songs.first.playCount, 3);
      expect(songs.first.voteCount, 7);
      expect(songs.first.requester, 'shaoze');
      expect(songs.first.musicId, '123');
    });

    test('fetchSchedules 解析排期（song 嵌套 + 封面/投稿人）', () async {
      final client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        apiKey: 'k',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/open/schedules.get');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 9,
                  'playDate': '2026-09-10',
                  'playTimeId': 2,
                  'song': <String, dynamic>{
                    'title': '晴天',
                    'artist': '周杰伦',
                    'coverUrl': 'https://x/q.jpg',
                    'votes': 5,
                  },
                  'status': 'confirmed',
                },
              ],
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final List<VoiceHubSchedule> list = await client.fetchSchedules();
      expect(list, hasLength(1));
      expect(list.first.songTitle, '晴天');
      expect(list.first.songArtist, '周杰伦');
      expect(list.first.playDate, '2026-09-10');
      expect(list.first.coverUrl, 'https://x/q.jpg');
      expect(list.first.voteCount, 5);
    });

    test('fetchSongs 401 → VoiceHubException 认证失败', () async {
      final client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async => http.Response('', 401)),
      );
      expect(
        () => client.fetchSongs(),
        throwsA(isA<VoiceHubException>()),
      );
    });

    test('submitSong 200 → true；401 → 提示登录', () async {
      final ok = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async => http.Response('', 201)),
      );
      expect(
        await ok.submitSong(title: 'x', artist: 'y'),
        isTrue,
      );

      final unauth = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async => http.Response('', 401)),
      );
      expect(
        () => unauth.submitSong(title: 'x', artist: 'y'),
        throwsA(isA<VoiceHubException>()),
      );
    });

    test('submitSong 请求体字段对齐', () async {
      http.Request? captured;
      final client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response('', 200);
        }),
      );
      await client.submitSong(
        title: '夜曲',
        artist: '周杰伦',
        coverUrl: 'https://x/c.jpg',
        musicPlatform: 'netease',
        musicId: '42',
        cookies: <String, String>{'token': 'abc'},
      );
      final dynamic body = jsonDecode(captured!.body);
      expect(body['title'], '夜曲');
      expect(body['artist'], '周杰伦');
      expect(body['cover'], 'https://x/c.jpg');
      expect(body['musicPlatform'], 'netease');
      expect(body['musicId'], '42');
      expect(captured!.headers['Cookie'], 'token=abc');
    });
  });
}