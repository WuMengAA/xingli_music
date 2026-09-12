import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xingli_music/services/voicehub/voicehub_client.dart';
import 'package:xingli_music/services/voicehub/voicehub_models.dart';

/// 真实后端 `server/api/open/songs.get.ts` 的响应形状：
/// `{success, data: {songs: [...], pagination: {page, limit, total, totalPages}}}`。
Map<String, dynamic> _songsEnvelope({
  int page = 1,
  int limit = 20,
  int total = 1,
}) =>
    <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'songs': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 1,
            'title': '夜曲',
            'artist': '周杰伦',
            'cover': 'https://x/c.jpg',
            'musicPlatform': 'netease',
            'musicId': '123',
            'playUrl': 'https://x/n.mp3',
            'durationSeconds': 245,
            'played': false,
            'scheduled': false,
            'semester': '2026-2027-1',
            'requestedAt': '2026-09-10 12:00',
            'voteCount': 7,
            'requester': 'shaoze',
            'submissionNote': '想送给同桌',
            'submissionNotePublic': true,
            'preferredPlayTimeId': 3,
            'preferredPlayTime': <String, dynamic>{
              'id': 3,
              'name': '午间',
              'startTime': '12:00',
              'endTime': '12:30',
              'enabled': true,
            },
          },
        ],
        'pagination': <String, dynamic>{
          'page': page,
          'limit': limit,
          'total': total,
          'totalPages': (total / limit).ceil(),
        },
      },
    };

/// 真实后端 `server/api/open/schedules.get.ts` 的响应形状：
/// 排期 → 歌曲两层结构。
Map<String, dynamic> _schedulesEnvelope() => <String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'schedules': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 9,
            'playDate': '2026-09-10T00:00:00.000Z',
            'playDateFormatted': '2026-09-10',
            'semester': '2026-2027-1',
            'song': <String, dynamic>{
              'id': 5,
              'title': '晴天',
              'artist': '周杰伦',
              'cover': 'https://x/q.jpg',
              'musicPlatform': 'bilibili',
              'musicId': 'BV1xx411c7mD:12345:2',
              'durationSeconds': 269,
              'played': false,
              'requestedAt': '2026-09-08 09:00',
              'collaborators': <Map<String, dynamic>>[
                <String, dynamic>{'id': 2, 'name': '小明'},
              ],
            },
            'requester': <String, dynamic>{'id': 1, 'name': 'shaoze'},
            'playTime': <String, dynamic>{
              'id': 2,
              'name': '午间',
              'startTime': '12:00',
              'endTime': '12:30',
              'enabled': true,
            },
          },
        ],
        'pagination': <String, dynamic>{
          'page': 1,
          'limit': 20,
          'total': 1,
          'totalPages': 1,
        },
      },
    };

void main() {
  group('VoiceHubClient', () {
    test('fetchSongs 解析 Map 形状响应（data.data.songs + pagination）',
        () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        apiKey: 'test-key',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/open/songs');
          expect(req.headers['X-API-Key'], 'test-key');
          expect(req.url.queryParameters['page'], '1');
          expect(req.url.queryParameters['limit'], '20');
          return http.Response(
            jsonEncode(_songsEnvelope()),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final VoiceHubSongPage page = await client.fetchSongs();
      expect(page.songs, hasLength(1));

      final VoiceHubSong song = page.songs.first;
      expect(song.id, 1);
      expect(song.title, '夜曲');
      expect(song.artist, '周杰伦');
      // 后端字段名是 cover（不是 coverUrl）。
      expect(song.cover, 'https://x/c.jpg');
      expect(song.musicPlatform, 'netease');
      expect(song.musicId, '123');
      expect(song.playUrl, 'https://x/n.mp3');
      expect(song.durationSeconds, 245);
      expect(song.voteCount, 7);
      expect(song.requester, 'shaoze');
      expect(song.semester, '2026-2027-1');
      expect(song.requestedAt, '2026-09-10 12:00');
      expect(song.submissionNote, '想送给同桌');
      expect(song.submissionNotePublic, isTrue);
      expect(song.preferredPlayTimeId, 3);
      expect(song.preferredPlayTime?.name, '午间');
      expect(song.played, isFalse);
      expect(song.scheduled, isFalse);
      expect(song.votable, isTrue);

      // 分页信封要真的读出来，而不是停在默认值。
      expect(page.pagination.total, 1);
      expect(page.pagination.limit, 20);
      expect(page.pagination.hasMore(1, 20), isFalse);
    });

    test('fetchSongs 兼容 data.data 退化为数组的旧形状', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async => http.Response(
              jsonEncode(<String, dynamic>{
                'data': <Map<String, dynamic>>[
                  <String, dynamic>{'id': 2, 'title': '稻香', 'artist': '周杰伦'},
                ],
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
      );
      final VoiceHubSongPage page = await client.fetchSongs();
      expect(page.songs, hasLength(1));
      expect(page.songs.first.title, '稻香');
      // 缺 cover/时长时应为 null 而不是 0。
      expect(page.songs.first.cover, isNull);
      expect(page.songs.first.durationSeconds, isNull);
    });

    test('fetchSongs 有下一页时 hasMore 为真', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async => http.Response(
              jsonEncode(_songsEnvelope(page: 1, limit: 20, total: 95)),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            )),
      );
      final VoiceHubSongPage page = await client.fetchSongs(page: 1, limit: 20);
      expect(page.pagination.total, 95);
      expect(page.pagination.totalPages, 5);
      expect(page.pagination.hasMore(1, 20), isTrue);
      expect(page.pagination.hasMore(5, 20), isFalse);
    });

    test('fetchSchedules 解析两层结构（排期 → 歌曲）', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        apiKey: 'k',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/open/schedules');
          return http.Response(
            jsonEncode(_schedulesEnvelope()),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final VoiceHubSchedulePage page = await client.fetchSchedules();
      expect(page.schedules, hasLength(1));

      final VoiceHubSchedule s = page.schedules.first;
      expect(s.id, 9);
      expect(s.songId, 5);
      expect(s.songTitle, '晴天');
      expect(s.songArtist, '周杰伦');
      expect(s.songCover, 'https://x/q.jpg');
      expect(s.songDurationSeconds, 269);
      expect(s.dateLabel, '2026-09-10');
      expect(s.requester, 'shaoze');
      expect(s.playTimeName, '午间');
      expect(s.timeLabel, '午间 12:00-12:30');
      expect(s.collaborators, <String>['小明']);
      // B 站复合 musicId：bvid 取首段。
      final VoiceHubSong asSong = VoiceHubSong.fromJson(<String, dynamic>{
        'musicPlatform': 'bilibili',
        'musicId': s.songMusicId,
      });
      expect(asSong.bvid, 'BV1xx411c7mD');
    });

    test('fetchMySongs 走 /api/songs?scope=mine 且带 Cookie', () async {
      http.Request? captured;
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        cookie: 'auth-token=jwt-abc',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'songs': <Map<String, dynamic>>[
                  <String, dynamic>{'id': 11, 'title': '花海', 'voteCount': 3},
                ],
                'total': 1,
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final List<VoiceHubSong> mine = await client.fetchMySongs();
      expect(captured!.url.path, '/api/songs');
      expect(captured!.url.queryParameters['scope'], 'mine');
      expect(captured!.headers['Cookie'], 'auth-token=jwt-abc');
      expect(mine, hasLength(1));
      expect(mine.first.title, '花海');
      expect(mine.first.voteCount, 3);
    });

    test('submitSong 路径为 /api/open/songs/request 且不带 Cookie', () async {
      http.Request? captured;
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        apiKey: 'vhub_x',
        cookie: 'auth-token=should-not-be-sent',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'id': 42,
              'title': '夜曲',
              'artist': '周杰伦',
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final int id = await client.submitSong(
        title: '夜曲',
        artist: '周杰伦',
        cover: 'https://x/c.jpg',
        musicPlatform: 'netease',
        musicId: '42',
        playUrl: 'https://x/n.mp3',
        submissionNote: '想送给同桌',
        submissionNotePublic: true,
        preferredPlayTimeId: 3,
      );
      // 公开端点只认 X-API-Key，不要求 Cookie。
      expect(captured!.url.path, '/api/open/songs/request');
      expect(captured!.method, 'POST');
      expect(captured!.headers['X-API-Key'], 'vhub_x');
      expect(captured!.headers['Cookie'], isNull);

      final dynamic body = jsonDecode(captured!.body);
      expect(body['title'], '夜曲');
      expect(body['artist'], '周杰伦');
      expect(body['cover'], 'https://x/c.jpg');
      expect(body['musicPlatform'], 'netease');
      expect(body['musicId'], '42');
      expect(body['playUrl'], 'https://x/n.mp3');
      // durationSeconds 不在 open 端点白名单内（`request.post.ts` 的
      // ALLOWED_FIELDS），客户端不下发，避免发了也被服务端剥掉。
      expect(body.containsKey('durationSeconds'), isFalse);
      expect(body['submissionNote'], '想送给同桌');
      expect(body['submissionNotePublic'], isTrue);
      expect(body['preferredPlayTimeId'], 3);
      // 后端白名单外的字段不该被塞进去。
      expect(body.containsKey('requester'), isFalse);
      expect(id, 42);
    });

    test('submitSong 未传可选项时不产生 null 字段', () async {
      http.Request? captured;
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response('{}', 200);
        }),
      );
      await client.submitSong(title: 'a', artist: 'b');
      final dynamic body = jsonDecode(captured!.body);
      expect(body, <String, dynamic>{
        'title': 'a',
        'artist': 'b',
        'submissionNotePublic': false,
      });
    });

    test('vote 走 /api/songs/vote，body 为 {songId, unvote} 且带 Cookie',
        () async {
      http.Request? captured;
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        cookie: 'auth-token=jwt-abc',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'message': '投票成功',
              'song': <String, dynamic>{
                'id': 7,
                'title': '夜曲',
                'artist': '周杰伦',
                'voteCount': 9,
              },
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      final int? count = await client.vote(7);
      expect(captured!.url.path, '/api/songs/vote');
      expect(captured!.method, 'POST');
      expect(captured!.headers['Cookie'], 'auth-token=jwt-abc');
      final dynamic body = jsonDecode(captured!.body);
      expect(body['songId'], 7);
      expect(body['unvote'], isFalse);
      expect(count, 9);
    });

    test('vote(unvote: true) 发 unvote=true', () async {
      http.Request? captured;
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        cookie: 'auth-token=jwt',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(
            jsonEncode(<String, dynamic>{
              'song': <String, dynamic>{'voteCount': 8},
            }),
            200,
          );
        }),
      );
      expect(await client.vote(7, unvote: true), 8);
      expect(jsonDecode(captured!.body)['unvote'], isTrue);
    });

    test('withdraw 走 /api/songs/withdraw', () async {
      http.Request? captured;
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        cookie: 'auth-token=jwt',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(
            jsonEncode(<String, dynamic>{'message': '歌曲已成功撤回'}),
            200,
          );
        }),
      );
      await client.withdraw(7);
      expect(captured!.url.path, '/api/songs/withdraw');
      expect(jsonDecode(captured!.body), <String, dynamic>{'songId': 7});
    });

    test('login 从 Set-Cookie 里取出 auth-token', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/auth/login');
          expect(jsonDecode(req.body)['username'], 'shaoze');
          expect(jsonDecode(req.body)['password'], 'pw');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'user': <String, dynamic>{'id': 1, 'name': 'shaoze'},
            }),
            200,
            headers: <String, String>{
              'set-cookie': 'auth-token=jwt-xyz; Path=/; HttpOnly; '
                  'Max-Age=604800; SameSite=Lax',
            },
          );
        }),
      );
      final String cookie = await client.login('shaoze', 'pw');
      expect(cookie, 'auth-token=jwt-xyz');
    });

    test('login 401 → VoiceHubException', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async => http.Response(
              jsonEncode(<String, dynamic>{'message': '用户名或密码错误'}),
              401,
            )),
      );
      expect(
        () => client.login('shaoze', 'bad'),
        throwsA(isA<VoiceHubException>()),
      );
    });

    test('fetchSubmissionStatus 解析额度字段', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        cookie: 'auth-token=jwt',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/songs/submission-status');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'limitEnabled': true,
              'submissionClosed': false,
              'dailyLimit': 3,
              'dailyUsed': 1,
              'dailyRemaining': 2,
            }),
            200,
          );
        }),
      );
      final VoiceHubSubmissionStatus s = await client.fetchSubmissionStatus();
      expect(s.limitEnabled, isTrue);
      expect(s.dailyRemaining, 2);
      expect(s.remaining, 2);
      expect(s.summary, '本期剩余投稿额度 2 次');
    });

    test('401 按路径分类：/api/open/* → API Key 文案', () async {
      // 点歌列表走 X-API-Key，401 只可能是 Key 有问题。
      final VoiceHubClient list = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/open/songs');
          return http.Response(
            jsonEncode(<String, dynamic>{'message': 'API认证失败'}),
            401,
          );
        }),
      );
      try {
        await list.fetchSongs();
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, VoiceHubClient.kUnauthorizedApiKey);
      }

      // 排期列表同样是 open 前缀。
      final VoiceHubClient sched = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/api/open/schedules');
          return http.Response('', 401);
        }),
      );
      try {
        await sched.fetchSchedules();
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, VoiceHubClient.kUnauthorizedApiKey);
      }

      // 提交点歌也在 open 前缀下（不要求 Cookie），401 同样是 Key 的问题。
      final VoiceHubClient submit = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client:
            MockClient((http.Request req) async => http.Response('', 401)),
      );
      try {
        await submit.submitSong(title: 'a', artist: 'b');
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, VoiceHubClient.kUnauthorizedApiKey);
      }
    });

    test('401 按路径分类：/api/songs/* → 会话失效文案', () async {
      // 私有端点靠 Cookie 里的 auth-token，401 = 会话过期，与 API Key 无关。
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        cookie: 'auth-token=expired-jwt',
        client: MockClient((http.Request req) async => http.Response(
              jsonEncode(<String, dynamic>{'message': '需要登录才能投票'}),
              401,
            )),
      );
      try {
        await client.vote(7);
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, VoiceHubClient.kUnauthorizedSession);
      }

      try {
        await client.fetchMySongs();
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, VoiceHubClient.kUnauthorizedSession);
      }

      // 撤回同理。
      try {
        await client.withdraw(7);
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, VoiceHubClient.kUnauthorizedSession);
      }

      // 投稿额度端点 /api/songs/submission-status 也走 Cookie 认证
      // （_getJson(..., withCookie: true) → _ensureOk），401 同样归「会话失效」，
      // 不能被误分类成 API Key 文案。
      try {
        await client.fetchSubmissionStatus();
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, VoiceHubClient.kUnauthorizedSession);
      }
    });

    test('isOpenApi 只认 /api/open/ 前缀', () {
      expect(VoiceHubClient.isOpenApi(Uri.parse('/api/open/songs')), isTrue);
      expect(
          VoiceHubClient.isOpenApi(Uri.parse('/api/open/songs/request')),
          isTrue);
      expect(VoiceHubClient.isOpenApi(Uri.parse('/api/songs')), isFalse);
      expect(
          VoiceHubClient.isOpenApi(Uri.parse('/api/songs/vote')), isFalse);
      expect(
          VoiceHubClient.isOpenApi(Uri.parse('/api/songs/submission-status')),
          isFalse);
    });

    test('401 → VoiceHubException 认证失败', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async => http.Response('', 401)),
      );
      expect(
        () => client.fetchSongs(),
        throwsA(isA<VoiceHubException>()),
      );
    });

    test('服务端 message 透传到异常文案', () async {
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        cookie: 'auth-token=jwt',
        client: MockClient((http.Request req) async => http.Response(
              jsonEncode(<String, dynamic>{'message': '你已经为这首歌投过票了'}),
              409,
            )),
      );
      try {
        await client.vote(7);
        fail('应抛出 VoiceHubException');
      } on VoiceHubException catch (e) {
        expect(e.message, '你已经为这首歌投过票了');
      }
    });

    test('submitSong 下发 bilibiliCid / bilibiliPage 与数值 collaborators',
        () async {
      http.Request? captured;
      final VoiceHubClient client = VoiceHubClient(
        baseUrl: 'https://vh.example.com',
        client: MockClient((http.Request req) async {
          captured = req;
          return http.Response(jsonEncode(<String, dynamic>{'id': 8}), 200);
        }),
      );
      await client.submitSong(
        title: '晴天',
        artist: '周杰伦',
        musicPlatform: 'bilibili',
        musicId: 'BV1xx411c7mD',
        bilibiliCid: '12345',
        bilibiliPage: '2',
        collaborators: <int>[3, 7],
      );
      final dynamic body = jsonDecode(captured!.body);
      // 服务端按 musicId.split(':')[0] 重建，cid/page 只能走独立字段。
      expect(body['musicId'], 'BV1xx411c7mD');
      expect(body['bilibiliCid'], '12345');
      expect(body['bilibiliPage'], '2');
      // collaborators 必须是数值用户 id（服务端 Number(id) 查 users.id）。
      expect(body['collaborators'], <int>[3, 7]);
    });

    test('VoiceHubBilibiliId 按 : 拆出 bvid / cid / page', () {
      final VoiceHubBilibiliId full =
          VoiceHubBilibiliId.parse('BV1xx411c7mD:12345:2');
      expect(full.bvid, 'BV1xx411c7mD');
      expect(full.cid, '12345');
      expect(full.page, '2');
      expect(full.isEmpty, isFalse);

      final VoiceHubBilibiliId noPage =
          VoiceHubBilibiliId.parse('BV1xx411c7mD:12345');
      expect(noPage.bvid, 'BV1xx411c7mD');
      expect(noPage.cid, '12345');
      expect(noPage.page, '');

      // av 号同样走 B 站分支。
      expect(VoiceHubBilibiliId.parse('av170001').bvid, 'av170001');
      // 非 B 站形态（网易云纯数字 id）不拆。
      expect(VoiceHubBilibiliId.parse('123').isEmpty, isTrue);
      expect(VoiceHubBilibiliId.parse('').isEmpty, isTrue);
      expect(VoiceHubBilibiliId.parse(null).isEmpty, isTrue);
    });
  });
}
