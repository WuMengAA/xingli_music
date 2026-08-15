import '../../models/track.dart';
import '../audio/local_music_scanner.dart';
import '../log_service.dart';
import 'music_source.dart';

/// 本地曲库源：包装现有 LocalMusicScanner。
///
/// 权限由扫描器（on_audio_query）自行申请；桌面端无媒体库，scan() 返回空，
/// 交由聚合层回退到其它音源。
class LocalMusicSource implements MusicSource {
  const LocalMusicSource();

  @override
  String get sourceId => 'local';

  @override
  bool get enabled => true;

  @override
  Future<List<Track>> getTracks() async {
    try {
      final List<Track> t = await LocalMusicScanner.scan();
      LogService.instance.i('source', '系统本地曲库: 扫描到 ${t.length} 首');
      return t;
    } catch (e) {
      LogService.instance.e('source', '本地曲库扫描异常: $e');
      return const [];
    }
  }

  @override
  Future<String> resolveStreamUrl(Track track) async => track.uri;

  @override
  Map<String, String> get playbackHeaders => const <String, String>{};

  /// 本地文件 just_audio 即可解码，无需 media_kit。
  @override
  bool get requiresMediaKit => false;
}
