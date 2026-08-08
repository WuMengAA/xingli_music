import 'dart:io';
import 'dart:typed_data';

import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/track.dart';
import '../log_service.dart';

/// 本地音乐扫描器：通过系统媒体库读取真实元数据（on_audio_query）。
///
/// 相比早期「遍历目录 + 文件名当曲名」，这里拿到的是系统媒体库里的
/// title / artist / album / duration / 专辑封面，锁屏与曲库展示才准确。
///
/// 桌面 / 无媒体库平台直接返回空，由聚合层回退到其它音源。
class LocalMusicScanner {
  static final OnAudioQuery _query = OnAudioQuery();
  static const String _coverSubdir = 'covers';

  /// 扫描系统媒体库，返回真实元数据的本地曲目列表
  static Future<List<Track>> scan() async {
    // 桌面平台无媒体库概念，交给聚合层回退
    if (!Platform.isAndroid && !Platform.isIOS) return const [];

    final bool granted = await _requestPermission();
    if (!granted) {
      LogService.instance.w('scan', '未授予音乐库权限，跳过本地扫描');
      return const [];
    }

    try {
      final List<SongModel> songs = await _query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
      );

      final Directory coverDir = await _coverDir();
      final List<Track> tracks = <Track>[];

      for (final SongModel s in songs) {
        final int? durMs = int.tryParse((s.duration as String?) ?? '');
        final Duration? duration =
            durMs != null ? Duration(milliseconds: durMs) : null;

        // 封面：按需写入应用文档目录缓存（缺失不致命）
        String? coverPath;
        try {
          final Uint8List? art = await _query.queryArtwork(
            s.id,
            ArtworkType.AUDIO,
            size: 300,
            quality: 75,
          );
          if (art != null) {
            final File f = File(p.join(coverDir.path, '${s.id}.jpg'));
            await f.writeAsBytes(art);
            coverPath = f.path;
          }
        } catch (_) {
          // 封面缺失不阻断扫描
        }

        tracks.add(Track(
          title: s.title,
          artist: (s.artist ?? '未知艺人'),
          uri: s.data,
          source: TrackSource.local,
          sourceId: 'local',
          album: s.album,
          duration: duration,
          coverPath: coverPath,
          extras: <String, dynamic>{
            'androidId': s.id,
            'albumId': s.albumId,
          },
        ));
      }

      LogService.instance
          .i('scan', '本地曲库扫描完成: ${tracks.length} 首');
      return tracks;
    } catch (e) {
      LogService.instance.e('scan', '本地扫描失败: $e');
      return const [];
    }
  }

  /// 请求系统媒体库权限（on_audio_query 自带权限接口）
  static Future<bool> _requestPermission() async {
    try {
      if (await _query.permissionsStatus()) return true;
      return await _query.permissionsRequest();
    } catch (_) {
      return false;
    }
  }

  static Future<Directory> _coverDir() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory d = Directory(p.join(appDir.path, _coverSubdir));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 取某曲封面（按需懒加载，供 UI / 锁屏使用）
  static Future<String?> coverPathFor(Track track) async {
    final int? id = track.extras?['androidId'] as int?;
    if (id == null) return track.coverPath;
    final Directory coverDir = await _coverDir();
    final File f = File(p.join(coverDir.path, '$id.jpg'));
    if (await f.exists()) return f.path;
    try {
      final Uint8List? art = await _query.queryArtwork(
        id,
        ArtworkType.AUDIO,
        size: 300,
        quality: 75,
      );
      if (art != null) {
        await f.writeAsBytes(art);
        return f.path;
      }
    } catch (_) {
      // 忽略
    }
    return null;
  }
}
