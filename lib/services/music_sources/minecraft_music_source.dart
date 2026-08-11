import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/track.dart';
import '../log_service.dart';
import 'music_source.dart';

/// 落雪场景专属音源：Minecraft: Java Edition 背景音乐。
///
/// 音乐由仓库根的 extract_minecraft_music.ps1 从 Minecraft 资源目录提取，
/// 默认放在本地目录：
///   - 桌面端调试：kMinecraftMusicDirDesktop
///   - Android：kMinecraftMusicDirMobile（需先把该目录推到设备并授权）
///
/// 文件为 OGG(Vorbis)：Android(ExoPlayer) 原生可播；Windows 桌面 just_audio
/// 后端对 OGG 支持不一定，可在该目录放同名 .mp3 优先使用（见 getTracks）。
class MinecraftMusicSource implements MusicSource {
  const MinecraftMusicSource();

  /// 桌面调试目录（Windows）。换成你的提取路径即可。
  static const String kMinecraftMusicDirDesktop =
      r'd:\Stellara\Music\minecraft_music';

  /// Android 设备上的目录（adb push 或手动拷贝到此处）。
  static const String kMinecraftMusicDirMobile =
      '/storage/emulated/0/Music/minecraft_music';

  @override
  String get sourceId => 'minecraft';

  @override
  bool get enabled => true;

  String get _dir {
    if (kIsWeb) return '';
    if (Platform.isAndroid || Platform.isIOS) return kMinecraftMusicDirMobile;
    return kMinecraftMusicDirDesktop;
  }

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

    // 只扫描背景乐目录，避免把 ambient/sfx 的短音效/环境音混入曲库。
    final String musicDir = '$_dir/sounds/music';
    final Directory dir;
    if (await Directory(musicDir).exists()) {
      dir = Directory(musicDir);
    } else if (await Directory(_dir).exists()) {
      LogService.instance
          .i('source', 'Minecraft 曲库: 未找到 music 子目录，回退扫描 $_dir');
      dir = Directory(_dir);
    } else {
      return const [];
    }

    // 同名文件优先 mp3（Windows 桌面 just_audio 对 OGG 解码不稳）
    final Map<String, File> byName = <String, File>{};
    await for (final FileSystemEntity e
        in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final String lower = e.path.toLowerCase();
      if (!lower.endsWith('.ogg') && !lower.endsWith('.mp3')) continue;
      final String name = _baseName(e.path);
      final File? existing = byName[name];
      final bool isMp3 = lower.endsWith('.mp3');
      if (existing == null ||
          (isMp3 && !existing.path.toLowerCase().endsWith('.mp3'))) {
        byName[name] = e;
      }
    }

    final List<String> names = byName.keys.toList()..sort();
    final List<Track> tracks = <Track>[];
    for (final String name in names) {
      final File file = byName[name]!;
      tracks.add(Track(
        title: _prettyTitle(name),
        artist: 'Minecraft OST',
        uri: file.path,
        source: TrackSource.local,
        sourceId: sourceId,
        isLiveStream: false,
      ));
    }
    LogService.instance.i(
        'source', 'Minecraft 曲库: 扫描到 ${tracks.length} 首');
    return tracks;
  }

  @override
  Future<String> resolveStreamUrl(Track track) async => track.uri;

  @override
  Map<String, String> get playbackHeaders => const <String, String>{};

  String _baseName(String path) {
    final String f = path.replaceAll('\\', '/');
    return f.substring(f.lastIndexOf('/') + 1);
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
