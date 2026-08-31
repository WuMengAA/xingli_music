import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xingli_music/services/cast/now_playing_server.dart';

void main() {
  group('NowPlayingServer', () {
    late NowPlayingServer server;
    late List<String> controlCalls;

    const NowPlayingSnapshot sampleFull = NowPlayingSnapshot(
      track: NowPlayingTrack(
        title: 'Minecraft - Sweden',
        artist: 'C418',
        album: 'Volume Alpha',
        coverUrl: 'http://example.com/cover.jpg',
        isLiveStream: false,
        sourceId: 'local',
      ),
      isPlaying: true,
      positionMs: 83241,
      durationMs: 211000,
      radio: NowPlayingRadio(
        role: 'host',
        isDj: true,
        djName: '星璃',
        roomName: '午间点歌台',
        roomCode: '1048',
        mode: 'campus',
        memberCount: 6,
      ),
    );

    setUp(() async {
      controlCalls = <String>[];
      server = NowPlayingServer(
        version: '0.26.8.31_beta_cl01_pc',
        reader: () => sampleFull,
        control: (String action) async {
          controlCalls.add(action);
          return true;
        },
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
    });

    Uri urlFor(String path) =>
        Uri.parse('http://127.0.0.1:${server.port}$path');

    test('GET /nowplaying 返回完整快照（曲目 + 电台）', () async {
      final http.Response res = await http.get(urlFor('/nowplaying'));
      expect(res.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['schema'], 1);
      expect(body['app'], 'xingli_music');
      final Map<String, dynamic> track =
          body['track'] as Map<String, dynamic>;
      expect(track['title'], 'Minecraft - Sweden');
      expect(track['artist'], 'C418');
      expect(track['album'], 'Volume Alpha');
      expect(track['coverUrl'], 'http://example.com/cover.jpg');
      expect(track['isLiveStream'], false);
      expect(body['isPlaying'], true);
      expect(body['positionMs'], 83241);
      expect(body['durationMs'], 211000);
      final Map<String, dynamic> radio =
          body['radio'] as Map<String, dynamic>;
      expect(radio['inStation'], true);
      expect(radio['role'], 'host');
      expect(radio['isDj'], true);
      expect(radio['djName'], '星璃');
      expect(radio['roomName'], '午间点歌台');
      expect(radio['roomCode'], '1048');
      expect(radio['mode'], 'campus');
      expect(radio['memberCount'], 6);
    });

    test('GET /nowplaying 无播放时 track/radio 为 null', () async {
      server = NowPlayingServer(
        reader: () => const NowPlayingSnapshot(isPlaying: false),
      );
      await server.stop();
      await server.start();
      final http.Response res =
          await http.get(Uri.parse('http://127.0.0.1:${server.port}/nowplaying'));
      expect(res.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['track'], isNull);
      expect(body['radio'], isNull);
      expect(body['isPlaying'], false);
    });

    test('GET /health 返回探活信息与版本', () async {
      final http.Response res = await http.get(urlFor('/health'));
      expect(res.statusCode, 200);
      final Map<String, dynamic> body =
          jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['app'], 'xingli_music');
      expect(body['version'], '0.26.8.31_beta_cl01_pc');
    });

    test('POST /control 回环来源命中控制器', () async {
      final http.Response res = await http.post(
        urlFor('/control'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{'action': 'next'}),
      );
      expect(res.statusCode, 204);
      expect(controlCalls, <String>['next']);
    });

    test('POST /control 未知 action 返回 400', () async {
      final http.Response res = await http.post(
        urlFor('/control'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{'action': 'nuke'}),
      );
      expect(res.statusCode, 400);
      expect(controlCalls, isEmpty);
    });

    test('POST /control 未注入控制器返回 501', () async {
      final NowPlayingServer noCtrl = NowPlayingServer(
        reader: () => sampleFull,
      );
      await noCtrl.start();
      try {
        final http.Response res = await http.post(
          Uri.parse('http://127.0.0.1:${noCtrl.port}/control'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'action': 'play'}),
        );
        expect(res.statusCode, 501);
      } finally {
        await noCtrl.stop();
      }
    });

    test('未知路径返回 404', () async {
      final http.Response res = await http.get(urlFor('/nope'));
      expect(res.statusCode, 404);
    });

    group('可选 token 鉴权（v1.1）', () {
      late NowPlayingServer authServer;

      tearDown(() async {
        await authServer.stop();
      });

      Future<NowPlayingServer> startAuth(String? tk) async {
        authServer = NowPlayingServer(
          version: '0.26.8.31_beta_cl01_pc',
          reader: () => sampleFull,
          control: (String action) async {
            controlCalls.add(action);
            return true;
          },
          token: tk,
        );
        await authServer.start();
        return authServer;
      }

      Uri authUrl(String path, {String? token}) {
        final String q =
            token != null ? '?token=${Uri.encodeQueryComponent(token)}' : '';
        return Uri.parse(
            'http://127.0.0.1:${authServer.port}$path$q');
      }

      test('token=null 时行为与 v1 冻结一致（GET 放行、/control 回环）', () async {
        await startAuth(null);
        expect((await http.get(authUrl('/nowplaying'))).statusCode, 200);
        expect((await http.get(authUrl('/health'))).statusCode, 200);
        final http.Response ctl = await http.post(
          authUrl('/control'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'action': 'next'}),
        );
        expect(ctl.statusCode, 204);
      });

      test('启用 token 后无 token 访问返回 401', () async {
        await startAuth('s3cret');
        expect((await http.get(authUrl('/nowplaying'))).statusCode, 401);
        expect((await http.get(authUrl('/health'))).statusCode, 401);
        final http.Response ctl = await http.post(
          authUrl('/control'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'action': 'next'}),
        );
        expect(ctl.statusCode, 401);
      });

      test('启用 token 后 ?token= 通过鉴权', () async {
        await startAuth('s3cret');
        expect(
            (await http.get(authUrl('/nowplaying', token: 's3cret')))
                .statusCode,
            200);
        expect(
            (await http.get(authUrl('/health', token: 's3cret'))).statusCode,
            200);
        final http.Response ctl = await http.post(
          authUrl('/control', token: 's3cret'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'action': 'next'}),
        );
        expect(ctl.statusCode, 204);
        expect(controlCalls, <String>['next']);
      });

      test('启用 token 后 Authorization: Bearer 通过鉴权', () async {
        await startAuth('s3cret');
        final Map<String, String> hdr = <String, String>{
          'Authorization': 'Bearer s3cret',
        };
        expect((await http.get(authUrl('/nowplaying'), headers: hdr)).statusCode,
            200);
        expect((await http.get(authUrl('/health'), headers: hdr)).statusCode,
            200);
        final http.Response ctl = await http.post(
          authUrl('/control'),
          headers: <String, String>{
            ...hdr,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, String>{'action': 'prev'}),
        );
        expect(ctl.statusCode, 204);
        expect(controlCalls, <String>['prev']);
      });

      test('启用 token 后错误 token 返回 401', () async {
        await startAuth('s3cret');
        expect(
            (await http.get(authUrl('/nowplaying', token: 'wrong'))).statusCode,
            401);
        expect(
            (await http.get(authUrl('/health', token: 'wrong'))).statusCode,
            401);
        final http.Response ctl = await http.post(
          authUrl('/control', token: 'wrong'),
          headers: <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, String>{'action': 'next'}),
        );
        expect(ctl.statusCode, 401);
        expect(controlCalls, isEmpty);
      });
    });
  });
}