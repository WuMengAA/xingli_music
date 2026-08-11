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

  /// 用户素材（assets/audio 裁剪片段）优先映射：场景 id → asset 路径。
  ///
  /// R23g：audio_material 原始素材经素材管线裁剪成 21 个片段打进包，
  /// 场景音景优先用它们（原始文件 566MB 无法进包，用裁剪产物）。
  /// 自定义音景路径（用户指定文件）优先走原逻辑，返回 null。
  static String? assetFor(Scene scene) {
    if (scene.soundscapePath?.isNotEmpty == true) return null;
    return _sceneToAsset[scene.id];
  }

  /// 场景 id → assets/audio 素材片段映射（从 audio_material 裁剪而来）。
  static const Map<String, String> _sceneToAsset = {
    'rain': 'assets/audio/rain_432hz_a.m4a',
    'forest': 'assets/audio/leaves_rustle_a.m4a',
    'ocean': 'assets/audio/beach_waves_a.m4a',
    'beach': 'assets/audio/beach_waves_a.m4a',
    'cozy': 'assets/audio/campfire_a.m4a',
    'warm': 'assets/audio/rainforest_birds_a.m4a',
    'cool': 'assets/audio/bamboo_wind_a.m4a',
    'starnight': 'assets/audio/ambience_soft_a.m4a',
    'night': 'assets/audio/ambience_soft_b.m4a',
    'dawn': 'assets/audio/summer_ambience_a.m4a',
    'dusk': 'assets/audio/summer_ambience_b.m4a',
    'aurora': 'assets/audio/wind_chimes_a.m4a',
  };

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
