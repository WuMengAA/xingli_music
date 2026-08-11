import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/track.dart';
import '../log_service.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 本地音乐扫描器：通过系统媒体库读取真实元数据（on_audio_query）。
/// ════════════════════════════════════════════════════════════════════════
///
/// 主路径：`on_audio_query` 查询系统 MediaStore（带元数据 / 封面）。
///
/// **Fallback 路径**（新增）：当系统媒体库不可用时（裁剪 ROM / Wear OS
/// GSI 缺少 `READ_MEDIA_AUDIO` 权限定义、`on_audio_query` 抛 `PlatformException`
/// Unknown permission、或权限请求被拒），回退到 **目录遍历** 直接读
/// `/sdcard/Music/`、`/sdcard/Download/` 下的 `.mp3/.flac/.m4a/.wav/.ogg`，
/// 保证老设备/精简系统也能拿到本地曲目（牺牲元数据精度换取可用性）。
///
/// 桌面 / 无媒体库平台直接返回空，由聚合层回退到其它音源。
class LocalMusicScanner {
  static final OnAudioQuery _query = OnAudioQuery();
  static const String _coverSubdir = 'covers';

  /// 允许的后缀（目录遍历用）
  static const Set<String> _audioExts = <String>{
    '.mp3', '.flac', '.m4a', '.wav', '.ogg', '.aac', '.opus',
  };

  /// 扫描系统媒体库，返回真实元数据的本地曲目列表
  static Future<List<Track>> scan() async {
    // 桌面平台无媒体库概念，交给聚合层回退
    if (!Platform.isAndroid && !Platform.isIOS) return const [];

    // 主路径：on_audio_query 走 MediaStore
    final List<Track> mediaTracks = await _scanViaMediaStore();
    if (mediaTracks.isNotEmpty) return mediaTracks;

    // Fallback：直接目录遍历（兼容裁剪系统 / Wear OS GSI）
    LogService.instance.w(
        'scan', 'MediaStore 未返回曲目，回退到目录遍历');
    return _scanViaDirectory();
  }

  /// on_audio_query 主路径
  static Future<List<Track>> _scanViaMediaStore() async {
    final bool granted = await _requestPermission();
    if (!granted) {
      LogService.instance.w('scan', '未授予音乐库权限，跳过 MediaStore 扫描');
      return const <Track>[];
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
          .i('scan', 'MediaStore 扫描完成: ${tracks.length} 首');
      return tracks;
    } catch (e, st) {
      LogService.instance.e('scan', 'MediaStore 扫描失败: $e\n$st');
      return const <Track>[];
    }
  }

  /// Fallback 目录遍历：直接读常见音乐目录的音频文件
  ///
  /// 仅在 [_scanViaMediaStore] 返回空时调用。无元数据，曲名取文件名。
  static Future<List<Track>> _scanViaDirectory() async {
    final List<Directory> roots = await _candidateRoots();
    final List<Track> tracks = <Track>[];

    for (final Directory dir in roots) {
      try {
        if (!await dir.exists()) continue;
        await for (final FileSystemEntity ent
            in dir.list(recursive: false, followLinks: false)) {
          if (ent is! File) continue;
          final String path = ent.path;
          final String ext = p.extension(path).toLowerCase();
          if (!_audioExts.contains(ext)) continue;
          final String name =
              p.basenameWithoutExtension(path).trim();
          if (name.isEmpty) continue;
          tracks.add(Track(
            title: name,
            artist: '本地音频',
            uri: path,
            source: TrackSource.local,
            sourceId: 'local',
            album: null,
            duration: null,
            coverPath: null,
            extras: <String, dynamic>{
              'fromFallback': true,
              'ext': ext,
            },
          ));
        }
      } catch (e) {
        // P-1：只记最后一级目录名，不落完整绝对路径（可能含用户名/私人目录名）
        LogService.instance
            .w('scan', '目录遍历失败 …/${p.basename(dir.path)}: $e');
      }
    }

    LogService.instance
        .i('scan', '目录遍历完成: ${tracks.length} 首');
    return tracks;
  }

  /// 候选音乐根目录（按优先级）
  static Future<List<Directory>> _candidateRoots() async {
    final List<Directory> roots = <Directory>[];
    final List<String> paths = <String>[
      '/sdcard/Music',
      '/sdcard/Download',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ];
    for (final String s in paths) {
      try {
        final Directory d = Directory(s);
        if (await d.exists()) roots.add(d);
      } catch (_) {}
    }
    if (kDebugMode) {
      //debugPrint('[scan] candidate roots: ${roots.map((d) => d.path).toList()}');
    }
    return roots;
  }

  /// 请求系统媒体库权限（on_audio_query 自带权限接口）
  static Future<bool> _requestPermission() async {
    try {
      if (await _query.permissionsStatus()) return true;
      return await _query.permissionsRequest();
    } catch (e) {
      // 关键兜底：Wear OS / 裁剪系统调用权限 API 时会抛
      // `PlatformException(Unknown permission ...)`，这里捕获后返回 false，
      // 让 scan() 进入 fallback 目录遍历。
      LogService.instance.w('scan', '权限请求失败（系统不识别？）: $e');
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
