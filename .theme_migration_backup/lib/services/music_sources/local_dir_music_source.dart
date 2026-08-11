import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/local_dir_config.dart';
import '../../models/track.dart';
import '../log_service.dart';
import 'music_source.dart';

/// 自定义本地目录曲库源：扫描指定文件夹里的音频文件。
///
/// - 同名文件优先 .mp3（Windows 桌面 just_audio 对 OGG 解码不稳时自动用 MP3）
/// - 支持扩展名与 [LocalMusicScanner] 一致
/// - 桌面端直接读绝对路径；移动端先申请音频权限
class LocalDirMusicSource implements MusicSource {
  final LocalDirConfig config;
  const LocalDirMusicSource(this.config);

  static const List<String> _extensions = [
    '.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.wma',
  ];

  @override
  String get sourceId => 'dir:${config.path}';

  @override
  bool get enabled => config.enabled;

  @override
  Future<List<Track>> getTracks() async {
    if (kIsWeb) return const [];
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final PermissionStatus status = await Permission.audio.request();
        if (!status.isGranted) return const [];
      } catch (_) {
        return const [];
      }
    }

    final Directory dir = Directory(config.path);
    if (!await dir.exists()) return const [];

    // 同名文件优先 mp3
    final Map<String, File> byName = <String, File>{};
    await for (final FileSystemEntity e
        in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final String lower = e.path.toLowerCase();
      if (!_extensions.any(lower.endsWith)) continue;
      final String name = _baseName(e.path);
      final File? existing = byName[name];
      final bool isMp3 = lower.endsWith('.mp3');
      if (existing == null ||
          (isMp3 && !existing.path.toLowerCase().endsWith('.mp3'))) {
        byName[name] = e;
      }
    }

    final String artist = _dirName(config.path);
    final List<String> names = byName.keys.toList()..sort();
    final List<Track> tracks = <Track>[];
    for (final String name in names) {
      final File file = byName[name]!;
      tracks.add(Track(
        title: _prettyTitle(name),
        artist: artist,
        uri: file.path,
        source: TrackSource.local,
        sourceId: sourceId,
        isLiveStream: false,
      ));
    }
    LogService.instance.i(
        'source', '目录曲库 ${config.path}: 扫描到 ${tracks.length} 首');
    return tracks;
  }

  @override
  Future<String> resolveStreamUrl(Track track) async => track.uri;

  String _baseName(String path) {
    final String f = path.replaceAll('\\', '/');
    return f.substring(f.lastIndexOf('/') + 1);
  }

  String _dirName(String path) {
    final String p = path.replaceAll('\\', '/');
    final String t = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    final String n = t.substring(t.lastIndexOf('/') + 1);
    return n.isEmpty ? '本地曲库' : n;
  }

  String _prettyTitle(String fileName) {
    final String noExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final RegExp leading = RegExp(r'^([a-z]+?)(\d+)$');
    final Match? m = leading.firstMatch(noExt);
    if (m != null) {
      final String word = m.group(1)!;
      return '${word[0].toUpperCase()}${word.substring(1)} ${m.group(2)}';
    }
    return noExt.replaceAll('_', ' ');
  }
}
