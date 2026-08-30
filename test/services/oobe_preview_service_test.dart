import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/services/audio/oobe_preview_service.dart';

void main() {
  Track fakeTrack(String name) => Track(
        title: name,
        artist: '试听艺术家',
        uri: 'netease://song/1',
        source: TrackSource.stream,
        sourceId: 'netease',
      );

  group('OobePreviewService', () {
    test('可用且有结果 → 返回首曲', () async {
      final service = OobePreviewService(
        canPreview: () => true,
        search: (genre) async => <Track>[fakeTrack('$genre 之歌'), fakeTrack('$genre 第二首')],
      );
      final GenrePreview p = await service.previewFor('摇滚');
      expect(p.ok, isTrue);
      expect(p.track!.title, '摇滚 之歌');
      expect(p.message, isEmpty);
    });

    test('不可用（未登录）→ 引导登录，不抛异常', () async {
      final service = OobePreviewService(
        canPreview: () => false,
        search: (_) async => throw StateError('不应被调用'),
      );
      final GenrePreview p = await service.previewFor('古典');
      expect(p.ok, isFalse);
      expect(p.message, contains('登录'));
    });

    test('可用但无结果 → 提示无曲目', () async {
      final service = OobePreviewService(
        canPreview: () => true,
        search: (_) async => const <Track>[],
      );
      final GenrePreview p = await service.previewFor('爵士');
      expect(p.ok, isFalse);
      expect(p.message, contains('没有可试听'));
    });

    test('搜索抛异常 → 降级为可重试提示，不冒泡', () async {
      final service = OobePreviewService(
        canPreview: () => true,
        search: (_) async => throw TimeoutException('网络超时'),
      );
      final GenrePreview p = await service.previewFor('电子');
      expect(p.ok, isFalse);
      expect(p.message, contains('请稍后重试'));
    });

    test('流派名带首尾空白 → 传递给搜索前被 trim', () async {
      String? received;
      final service = OobePreviewService(
        canPreview: () => true,
        search: (genre) async {
          received = genre;
          return <Track>[fakeTrack('回显')];
        },
      );
      await service.previewFor('  民谣  ');
      expect(received, '民谣');
    });
  });
}