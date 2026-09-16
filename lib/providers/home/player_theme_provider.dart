/// ════════════════════════════════════════════════════════════════════════
/// 播放器主题（主页背景层）选择 + Steam 壁纸发现
/// ════════════════════════════════════════════════════════════════════════
///
/// 用户需求：播放器主题支持「导入 Steam 壁纸」（Wallpaper Engine 的 `web`
/// 类型创意工坊作品），随正在播放的音乐做音频反应。
///
/// 主题 key 取值：
/// - `'builtin'` ：默认（音频反应花 + 音效反应堆 + 渐变背景）
/// - `'video'`   ：哔站视频背景
/// - `'<壁纸id>'`：某个已发现的 Steam 壁纸（目录名即 id）

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一个已发现 / 已导入的 Steam 壁纸（Wallpaper Engine `web` 类型）。
class ImportedWallpaper {
  const ImportedWallpaper({
    required this.id,
    required this.title,
    required this.folderPath,
    this.previewPath,
  });

  /// 创意工坊目录名（同时也是 workshopid）。
  final String id;

  /// 壁纸标题（来自 project.json 的 `title`，中文如「音域回响」）。
  final String title;

  /// 壁纸目录绝对路径（含 index.html）。
  final String folderPath;

  /// 预览图路径（preview.gif / preview.jpg，可选）。
  final String? previewPath;

  /// 目录是否仍存在（用户可能删了 Steam 工坊缓存）。
  bool get exists => Directory(folderPath).existsSync();
}

/// 当前播放器主题 key。
final StateProvider<String> playerThemeProvider =
    StateProvider<String>((Ref<String> ref) => 'builtin');

/// 发现的 Steam 壁纸列表（扫描本机 Wallpaper Engine 创意工坊目录）。
final StateProvider<List<ImportedWallpaper>> importedWallpapersProvider =
    StateProvider<List<ImportedWallpaper>>(
  (Ref<List<ImportedWallpaper>> ref) => discoverSteamWallpapers(),
);

/// 扫描 Steam 创意工坊 `431960`（Wallpaper Engine）目录下所有 `web` 类型壁纸。
///
/// 仅识别 `project.json` 中 `type == "web"` 的作品（WebGL/React 类，可经
/// `wallpaperAudioListener` 注入音频做反应）；`video`/`scene`/`application`
/// 类型暂不纳入。
List<ImportedWallpaper> discoverSteamWallpapers() {
  const int appId = 431960;
  const List<String> roots = <String>[
    'D:/Steam/steamapps/workshop/content/$appId',
    'C:/Program Files (x86)/Steam/steamapps/workshop/content/$appId',
    'C:/Program Files/Steam/steamapps/workshop/content/$appId',
    'E:/Steam/steamapps/workshop/content/$appId',
    'F:/Steam/steamapps/workshop/content/$appId',
  ];
  final List<ImportedWallpaper> out = <ImportedWallpaper>[];
  for (final String root in roots) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final FileSystemEntity e in dir.listSync(followLinks: false)) {
      if (e is! Directory) continue;
      final File pj = File('${e.path}/project.json');
      if (!pj.existsSync()) continue;
      try {
        final Map<String, dynamic> json =
            jsonDecode(pj.readAsStringSync()) as Map<String, dynamic>;
        if (json['type'] != 'web') continue;
        final String id = e.path.split(RegExp(r'[/\\]')).last;
        final String title = (json['title'] as String?) ?? id;
        final String? preview = File('${e.path}/preview.gif').existsSync()
            ? '${e.path}/preview.gif'
            : (File('${e.path}/preview.jpg').existsSync()
                ? '${e.path}/preview.jpg'
                : null);
        out.add(
          ImportedWallpaper(
            id: id,
            title: title,
            folderPath: e.path,
            previewPath: preview,
          ),
        );
      } catch (_) {
        // 单个壁纸解析失败不影响其他
      }
    }
  }
  return out;
}
