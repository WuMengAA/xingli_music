import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/models/scene.dart';
import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/services/content/local_semantic_random.dart';

/// 构造一个测试场景（带 mood，供语义词库命中）。
Scene _scene(String name, String mood) => Scene(
      id: 'test',
      name: name,
      mood: mood,
      desc: '测试场景',
      track: '',
      artist: '',
      soundscape: '',
      icon: '',
      visual: const SceneVisual(
        gradientColors: <Color>[Color(0xFF000000), Color(0xFF111111)],
        stops: <double>[0, 1],
        accent: Color(0xFF9B7BFF),
        glyph: '✦',
      ),
      visualWeight: 0.5,
      valence: 0.5,
      energy: 0.5,
      visible: true,
      // 其余 Scene 必填字段按默认兜底。
    );

Track _track(String title, String artist, {String? album}) => Track(
      title: title,
      artist: artist,
      uri: 'local://$title',
      sourceId: 'local',
      album: album,
    );

void main() {
  const LocalSemanticRandom rng = LocalSemanticRandom();

  test('语义命中优先：标题含场景 mood 关键词的曲目排前面', () {
    final List<Track> lib = <Track>[
      _track('普通歌曲', '无名歌手'),
      _track('钢琴独奏', '演奏家'), // 命中「静默」词库的 piano/钢琴
      _track('雨中漫步', '某人'), // 命中「湿润」词库的 rain/雨
    ];
    final List<Track> r = rng.recommend(lib, _scene('雨天', '湿润'), count: 3);
    expect(r.first.title, '雨中漫步');
  });

  test('同一 seed 结果确定、不同 seed 结果可能不同（随机性存在）', () {
    final List<Track> lib = <Track>[
      for (int i = 0; i < 20; i++) _track('歌曲$i', '歌手$i'),
    ];
    final List<Track> a = rng.recommend(lib, _scene('普通', '静默'), seed: Random(1));
    final List<Track> b = rng.recommend(lib, _scene('普通', '静默'), seed: Random(1));
    expect(a.map((Track t) => t.title).toList(),
        b.map((Track t) => t.title).toList());

    // 无 seed（真随机）-> 允许不同（多数情况如此，用两轮不同种子挑一轮验证）
    final List<Track> c = rng.recommend(lib, _scene('普通', '静默'), seed: Random(2));
    final bool differs =
        a.map((Track t) => t.title).toList().join('|') !=
            c.map((Track t) => t.title).toList().join('|');
    expect(differs, isTrue);
  });

  test('词库零命中时退化为纯随机，仍返回不重复的 count 首', () {
    final List<Track> lib = <Track>[
      for (int i = 0; i < 10; i++) _track('编号$i', '艺人$i'),
    ];
    final List<Track> r = rng.recommend(lib, _scene('无', '静默'), count: 5, seed: Random(7));
    expect(r.length, 5);
    expect(r.map((Track t) => t.title).toSet().length, 5); // 无重复
  });

  test('空曲库返回空', () {
    expect(rng.recommend(<Track>[], _scene('x', '静默')), isEmpty);
  });
}