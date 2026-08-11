import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/scenes/scene_api.dart';
import 'package:xingli_music/services/log_service.dart';

Scene mk({String id = 'snow', String? ssPath, String? bgm, String? msid}) => Scene(
      id: id,
      name: '雪',
      mood: 'calm',
      desc: 'd',
      track: 't',
      artist: 'a',
      soundscape: 's',
      icon: 'star',
      visual: const SceneVisual(
          gradientColors: <Color>[], stops: <double>[], accent: Color(0xFF000000), glyph: '*'),
      visualWeight: 0.8,
      valence: 0.5,
      energy: 0.5,
      musicSourceId: msid,
      soundscapePath: ssPath,
      bgmUri: bgm,
    );

void main() {
  group('P-1 LogService.redact', () {
    test('URL query 整体剥离', () {
      expect(
        LogService.redact('播放 uri=https://m.163.com/song.mp3?token=abc&cookie=xyz'),
        '播放 uri=https://m.163.com/song.mp3?<redacted>',
      );
    });
    test('Windows 用户名脱敏', () {
      expect(LogService.redact(r'加载 C:\Users\张三\Music\a.mp3'),
          r'加载 C:\Users\<user>\Music\a.mp3');
    });
    test('自由文本 key=value 脱敏', () {
      expect(LogService.redact('err: token=SECRET123, ok'),
          'err: token=<redacted>, ok');
    });
    test('普通文本不受影响', () {
      expect(LogService.redact('音乐声音量: 70%'), '音乐声音量: 70%');
    });
  });

  group('P-2 分享隐私', () {
    test('toShareJson 剥离本机路径，toJson 保留', () {
      final s = mk(
        ssPath: r'C:\Users\张三\Music\rain.wav',
        bgm: r'C:\Users\张三\Music\bgm.mp3',
        msid: r'dir:C:\Users\张三\Music',
      );
      expect(s.toJson()['soundscapePath'], isNotNull, reason: '本机持久化需保留');

      final share = s.toShareJson();
      expect(share['soundscapePath'], isNull);
      expect(share['bgmUri'], isNull);
      expect(share['musicSourceId'], isNull);
      expect(jsonEncode(share), isNot(contains('张三')));
    });

    test('分享包整体不含用户名', () {
      final pack = Scenes.encodePack(mk(ssPath: r'C:\Users\张三\Music\rain.wav'));
      expect(pack, isNot(contains('张三')));
      expect(pack, isNot(contains('Users')));
    });

    test('远端 bgmUri 保留但剥离 token', () {
      final share = mk(bgm: 'https://cdn.x.com/a.mp3?token=SECRET').toShareJson();
      expect(share['bgmUri'], 'https://cdn.x.com/a.mp3');
    });

    test('decodePack 重写 id，无法覆盖内置场景', () {
      // 恶意包：伪装成内置场景 id 'snow'
      final evil = jsonEncode({'schema': 1, 'scene': mk(id: 'snow').toJson()});
      final imported = Scenes.decodePack(evil);

      expect(imported.id, isNot('snow'), reason: '必须重写 id');
      expect(imported.id, startsWith('custom_'));
      expect(imported.isCustom, isTrue, reason: '等价 isBuiltin=false');
      expect(imported.sourceShareId, 'snow', reason: '原 id 留作溯源');
    });

    test('decodePack 丢弃外来本机路径', () {
      final evil = jsonEncode({
        'schema': 1,
        'scene': mk(ssPath: r'C:\Windows\System32\x.wav', bgm: r'C:\a\b.mp3').toJson(),
      });
      final imported = Scenes.decodePack(evil);
      expect(imported.soundscapePath, isNull);
      expect(imported.bgmUri, isNull);
    });

    test('连续导入两次 id 不冲突', () {
      final pack = jsonEncode({'schema': 1, 'scene': mk(id: 'snow').toJson()});
      final ids = List.generate(50, (_) => Scenes.decodePack(pack).id).toSet();
      expect(ids.length, 50, reason: 'id 必须唯一');
    });
  });
}
