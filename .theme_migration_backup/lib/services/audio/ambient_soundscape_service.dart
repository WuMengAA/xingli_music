import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/scene.dart';

/// 解析 Minecraft 环境音素材位置的服务。
///
/// 素材布局（与抽取脚本约定一致）：
///   桌面：`<minecraft_music>/ambient/sounds/ambient/<group>/<name>.ogg`
///   移动：`<公共音乐>/minecraft_music/ambient/sounds/ambient/<group>/<name>.ogg`
/// 因此 `_baseDir()` 返回到 `.../ambient` 这一级，文件名统一拼 `sounds/ambient/<rel>.ogg`。
class AmbientSoundscapeService {
  // 素材相对于 _baseDir() 的固定子路径。
  static const String _soundsRel = 'sounds/ambient';

  /// 依据场景 id 映射到的环境音相对路径（不含 `sounds/ambient` 前缀）。
  static Future<String?> ambientPathFor(Scene scene) async {
    final String? rel = scene.soundscapePath?.isNotEmpty == true
        ? scene.soundscapePath
        : _sceneToAmbient[scene.id];
    if (rel == null) return null;

    final String? base = await _baseDir();
    if (base == null) return null;

    final File f = File('$base/$_soundsRel/$rel.ogg');
    if (await f.exists()) return f.path;
    return null;
  }

  /// 返回素材根目录（到 `.../ambient` 这一级），找不到则返回 null。
  static Future<String?> _baseDir() async {
    if (kIsWeb) return null;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      const String dev = r'd:\Stellara\Music\minecraft_music\ambient';
      final File probe = File('$dev/$_soundsRel/weather/rain1.ogg');
      if (await probe.exists()) return dev;
      return null;
    }

    for (final String prefix in [
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
    ]) {
      final String base = '$prefix/minecraft_music/ambient';
      final File probe = File('$base/$_soundsRel/weather/rain1.ogg');
      if (await probe.exists()) return base;
    }
    return null;
  }

  static const Map<String, String> _sceneToAmbient = {
    'rain': 'weather/rain1',
    'ocean': 'underwater/underwater_ambience',
    'starnight': 'cave/cave1',
    'dawn': 'cave/cave2',
    'dusk': 'cave/cave3',
    'forest': 'underwater/additions/water2',
    'night': 'cave/cave1',
    'aurora': 'underwater/underwater_ambience',
    'warm': 'cave/cave3',
    'cool': 'cave/cave2',
    'cozy': 'cave/cave1',
  };
}
