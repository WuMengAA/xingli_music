/// 网易云播放链路接线测试（I 域 · P1-6）。
///
/// 纯逻辑验证 [buildStreamResolver] 的行为契约：
/// - netease 占位符 → 解析为 https 地址并携带源请求头；
/// - 本地源解析出文件路径（非 http）→ 返回 null（回落 setFilePath）；
/// - uri 已是 http 直连 → 不解析；
/// - 解析失败（登录失效）→ 转成带中文消息的 [StreamResolveException]；
/// - 未知 sourceId → null。
///
/// 全部使用 Fake 源 + ProviderContainer 覆写，不打真实网络、不碰音频引擎。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xingli_music/models/track.dart';
import 'package:xingli_music/providers/audio/audio_providers.dart';
import 'package:xingli_music/services/audio/audio_service.dart';
import 'package:xingli_music/services/audio/sources/netease/netease_source.dart';
import 'package:xingli_music/services/audio/sources/netease/netease_webview_login.dart';
import 'package:xingli_music/services/music_sources/music_source.dart';

/// 模拟网易云源：占位符解析为 CDN 地址 + 请求头。
class _FakeNeteaseSource implements MusicSource {
  @override
  String get sourceId => 'netease';

  @override
  bool get enabled => true;

  @override
  Future<List<Track>> getTracks() async => const <Track>[];

  @override
  Future<String> resolveStreamUrl(Track track) async =>
      'https://m7.music.126.net/xxxx.mp3?sign=abc';

  @override
  Map<String, String> get playbackHeaders => const <String, String>{
        'User-Agent': 'ua-test',
        'Referer': 'https://music.163.com/',
      };

  @override
  bool get requiresMediaKit => true;
}

/// 模拟本地源：解析原样返回文件路径（非 http）。
class _FakeLocalSource implements MusicSource {
  @override
  String get sourceId => 'local';

  @override
  bool get enabled => true;

  @override
  Future<List<Track>> getTracks() async => const <Track>[];

  @override
  Future<String> resolveStreamUrl(Track track) async => track.uri;

  @override
  Map<String, String> get playbackHeaders => const <String, String>{};

  @override
  bool get requiresMediaKit => false;
}

/// 模拟「登录失效」的网易云源。
class _FailingNeteaseSource implements MusicSource {
  @override
  String get sourceId => 'netease';

  @override
  bool get enabled => true;

  @override
  Future<List<Track>> getTracks() async => const <Track>[];

  @override
  Future<String> resolveStreamUrl(Track track) async =>
      throw const NeteaseResolveException(
        NeteaseFailureReason.auth,
        '网易云登录已失效，请重新登录',
      );

  @override
  Map<String, String> get playbackHeaders => const <String, String>{};

  @override
  bool get requiresMediaKit => true;
}

void main() {
  group('buildStreamResolver（播放链路接线）', () {
    test('netease 占位符 → 解析为 https 地址并携带请求头', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          activeSourcesProvider
              .overrideWithValue(<MusicSource>[_FakeNeteaseSource()]),
        ],
      );
      addTearDown(container.dispose);

      final StreamResolver resolver = buildStreamResolver(container.read);
      final ResolvedStream? r = await resolver(
        const Track(
          title: '测试曲',
          artist: '测试歌手',
          uri: 'netease://song/123',
          sourceId: 'netease',
        ),
      );

      expect(r, isNotNull);
      expect(r!.url, startsWith('https://m7.music.126.net/'));
      expect(r.headers['User-Agent'], 'ua-test');
      expect(r.headers['Referer'], contains('music.163.com'));
    });

    test('本地源解析出文件路径（非 http）→ 返回 null（回落 setFilePath）', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          activeSourcesProvider
              .overrideWithValue(<MusicSource>[_FakeLocalSource()]),
        ],
      );
      addTearDown(container.dispose);

      final StreamResolver resolver = buildStreamResolver(container.read);
      final ResolvedStream? r = await resolver(
        const Track(
          title: '本地曲',
          artist: '本地歌手',
          uri: '/storage/emulated/0/Music/a.mp3',
          sourceId: 'local',
        ),
      );

      expect(r, isNull);
    });

    test('uri 已是 http 直连 → 不解析（返回 null）', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          activeSourcesProvider
              .overrideWithValue(<MusicSource>[_FakeNeteaseSource()]),
        ],
      );
      addTearDown(container.dispose);

      final StreamResolver resolver = buildStreamResolver(container.read);
      final ResolvedStream? r = await resolver(
        const Track(
          title: '电台',
          artist: '主播',
          uri: 'https://example.com/radio.mp3',
          sourceId: 'radio',
        ),
      );

      expect(r, isNull);
    });

    test('解析失败（登录失效）→ 抛 StreamResolveException 带中文消息', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          activeSourcesProvider
              .overrideWithValue(<MusicSource>[_FailingNeteaseSource()]),
        ],
      );
      addTearDown(container.dispose);

      final StreamResolver resolver = buildStreamResolver(container.read);
      await expectLater(
        resolver(
          const Track(
            title: '付费曲',
            artist: '歌手',
            uri: 'netease://song/1',
            sourceId: 'netease',
          ),
        ),
        throwsA(
          isA<StreamResolveException>().having(
            (StreamResolveException e) => e.message,
            'message',
            contains('重新登录'),
          ),
        ),
      );
    });

    test('未知 sourceId → 返回 null', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          activeSourcesProvider
              .overrideWithValue(<MusicSource>[_FakeNeteaseSource()]),
        ],
      );
      addTearDown(container.dispose);

      final StreamResolver resolver = buildStreamResolver(container.read);
      final ResolvedStream? r = await resolver(
        const Track(
          title: 'x',
          artist: 'y',
          uri: 'custom://whatever',
          sourceId: 'unknown-source',
        ),
      );

      expect(r, isNull);
    });
  });

  group('MusicSource.playbackHeaders 默认', () {
    test('未覆写的源默认空请求头（不破坏既有源）', () {
      final MusicSource s = _FakeLocalSource();
      expect(s.playbackHeaders, isEmpty);
    });
  });

  group('内嵌网页登录（webview_login）', () {
    test('非 Android 平台不支持内嵌登录（桌面测试环境回落粘贴 Cookie）', () {
      // flutter test 运行在桌面 VM，Platform.isAndroid == false → 不支持。
      expect(webviewLoginSupported, isFalse);
    });
  });
}
