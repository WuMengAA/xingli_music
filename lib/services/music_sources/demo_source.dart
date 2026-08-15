import '../../models/track.dart';
import 'music_source.dart';

/// 演示流媒体源：无版权公开曲目，曲库为空时的回退。
class DemoSource implements MusicSource {
  const DemoSource();

  static const List<Track> _demoTracks = [
    Track(
      title: 'Lunar Drift',
      artist: 'Stelarith · Demo Stream',
      uri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      sourceId: 'demo',
    ),
    Track(
      title: 'Rain Patterns',
      artist: 'Ambient Lab · Demo Stream',
      uri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      sourceId: 'demo',
    ),
    Track(
      title: 'Moss & Light',
      artist: 'Forest Echo · Demo Stream',
      uri: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      sourceId: 'demo',
    ),
  ];

  @override
  String get sourceId => 'demo';

  @override
  bool get enabled => true;

  @override
  Future<List<Track>> getTracks() async => _demoTracks;

  @override
  Future<String> resolveStreamUrl(Track track) async => track.uri;

  @override
  Map<String, String> get playbackHeaders => const <String, String>{};

  /// 演示流 just_audio 即可解码，无需 media_kit。
  @override
  bool get requiresMediaKit => false;
}
