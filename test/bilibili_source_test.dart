/// R26skel-b3：B站视频源纯逻辑回归（不碰网络 / 播放引擎）。
///
/// 覆盖：占位 uri 映射、bvid 反解、自动匹配的时长过滤与择优。
library;

import 'package:flutter_test/flutter_test.dart';

import '../lib/models/track.dart';
import '../lib/services/audio/sources/bilibili/bilibili_api.dart';
import '../lib/services/audio/sources/bilibili/bilibili_source.dart';

/// 假 API：只覆写搜索，返回预设视频列表。
class _FakeApi extends BilibiliApi {
  _FakeApi(this.videos);

  final List<BiliVideoLite> videos;

  @override
  Future<List<BiliVideoLite>> searchVideos(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) async =>
      videos;
}

BiliVideoLite _vid(String bvid, String title, int secs) => BiliVideoLite(
      bvid: bvid,
      title: title,
      author: 'up主',
      durationSeconds: secs,
    );

void main() {
  test('toTrack：占位 uri + 时长映射', () {
    final track = BilibiliSource.toTrack(_vid('BV1xx411c7mD', '测试曲', 245));
    expect(track.sourceId, 'bilibili');
    expect(track.uri, 'bilibili://video/BV1xx411c7mD');
    expect(track.uri.startsWith('http'), isFalse,
        reason: '占位符不得以 http 开头，避免 Track.isRemote 误判');
    expect(track.duration, const Duration(seconds: 245));
    expect(track.title, '测试曲');
  });

  test('bvidOf：extras 优先，其次占位 uri', () {
    final Track a = BilibiliSource.toTrack(_vid('BV1A', 'x', 10));
    expect(BilibiliSource.bvidOf(a), 'BV1A');
    final Track b = Track(
      title: 'y',
      artist: '',
      uri: 'bilibili://video/BV1B',
      sourceId: 'bilibili',
    );
    expect(BilibiliSource.bvidOf(b), 'BV1B');
  });

  test('autoMatch：时长接近者胜出，超阈值跳过', () async {
    final api = _FakeApi(<BiliVideoLite>[
      _vid('BV1far', '同名翻唱', 120), // 差 60s → 超阈值跳过
      _vid('BV1near1', '同名现场', 178), // 差 2s → 最优
      _vid('BV1near2', '同名MV', 190), // 差 12s
    ]);
    final src = BilibiliSource(api);
    final c = await src.autoMatch(
      '某曲',
      targetDuration: const Duration(seconds: 180),
    );
    expect(c, isNotNull);
    expect(c!.track.title, '同名现场');
    expect(c.delta, 2);
  });

  test('autoMatch：全部超阈值返回 null', () async {
    final api = _FakeApi(<BiliVideoLite>[
      _vid('BV1x', '同名但完全不同的视频', 60), // 差 120s
      _vid('BV1y', '同名另一内容', 400), // 差 220s
    ]);
    final src = BilibiliSource(api);
    final c = await src.autoMatch(
      '某曲',
      targetDuration: const Duration(seconds: 180),
    );
    expect(c, isNull);
  });

  test('autoMatch：无目标时长时取首条', () async {
    final api = _FakeApi(<BiliVideoLite>[
      _vid('BV1z', '任意', 300),
    ]);
    final src = BilibiliSource(api);
    final c = await src.autoMatch('某曲');
    expect(c, isNotNull);
    expect(c!.track.title, '任意');
  });

  test('resolveStreamUrl：无 bvid 抛中文异常', () async {
    final src = BilibiliSource(_FakeApi(const <BiliVideoLite>[]));
    final track = Track(
      title: 'x',
      artist: '',
      uri: 'bilibili://unknown',
      sourceId: 'bilibili',
    );
    expect(
      () => src.resolveStreamUrl(track),
      throwsA(isA<BilibiliResolveException>()),
    );
  });
}
