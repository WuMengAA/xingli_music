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
    this.folderPath,
    this.assetBase,
    this.previewPath,
  });

  /// 创意工坊目录名（同时也是 workshopid）；打包壁纸用稳定的自定义 id。
  final String id;

  /// 壁纸标题（来自 project.json 的 `title`，中文如「音域回响」）。
  final String title;

  /// 壁纸目录绝对路径（含 index.html）。[bundled] 为 true 时为空。
  final String? folderPath;

  /// 打包资源前缀（[bundled] 为 true 时非空，例如
  /// `assets/wallpapers/sonic_topography`）；运行时经 [LocalWallpaperServer]
  /// 从 [rootBundle] 提供，无需落盘——这是手机端可用的来源。
  final String? assetBase;

  /// 预览图路径（preview.gif / preview.jpg，可选）。
  final String? previewPath;

  /// 是否来自打包资源（而非本机 Steam 目录）。
  bool get bundled => assetBase != null;

  /// 目录是否仍存在（仅文件系统来源需要检查）。
  bool get exists => bundled || Directory(folderPath!).existsSync();
}

/// 当前播放器主题 key。
final StateProvider<String> playerThemeProvider =
    StateProvider<String>((Ref<String> ref) => 'builtin');

/// 壁纸效果默认值（可被同目录的 `effects.json` 覆盖）。键名对应 Wallpaper
/// Engine 的 `project.json` 属性；加载后经 `wallpaperPropertyListener
/// .applyUserProperties` 注入。App 内「效果」滑杆也读写这张表（与壁纸背景
/// 共用，保证初始值一致）。
const Map<String, dynamic> kDefaultWallpaperEffects = <String, dynamic>{
  'audioIntensity': 1.2,
  'theme': 'nocturnal',
  'gridSize': 160,
  'meteorEnabled': true,
  'meteorSensitivity': 0.35,
  'rippleEnabled': true,
  'rippleSensitivity': 0.2,
  'idleWaveEnabled': true,
  'autoRotateEnabled': false,
  'showPlayerController': false,
};

/// 当前壁纸主题的「效果配置」实时表。App 内「效果」滑杆读写它；壁纸加载时
/// 会用 `effects.json`/默认值覆盖（同步滑杆初始值），之后滑杆改动即时经
/// `applyUserProperties` 注入壁纸，无需重载页面。
final StateProvider<Map<String, dynamic>> wallpaperEffectsProvider =
    StateProvider<Map<String, dynamic>>(
  (Ref<Map<String, dynamic>> ref) =>
      Map<String, dynamic>.from(kDefaultWallpaperEffects),
);

/// 随包内置的 Steam 壁纸（手机等无 Steam 路径的平台也能用）。
/// 资源目录已声明在 pubspec 的 `flutter.assets` 下。
const List<ImportedWallpaper> bundleWallpapers = <ImportedWallpaper>[
  ImportedWallpaper(
    id: 'sonic_topography',
    title: '音域回响',
    assetBase: 'assets/wallpapers/sonic_topography',
    previewPath: 'assets/wallpapers/sonic_topography/preview.gif',
  ),
];

/// 发现的 Steam 壁纸列表（打包内置 + 扫描本机 Steam 创意工坊目录）。
final StateProvider<List<ImportedWallpaper>> importedWallpapersProvider =
    StateProvider<List<ImportedWallpaper>>(
  (Ref<List<ImportedWallpaper>> ref) => allWallpapers(),
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

/// 合并「打包内置」与「本机 Steam 目录发现」的壁纸，按标题去重
/// （同款壁纸若本机也有，优先用本机路径版，信息更全）。
List<ImportedWallpaper> allWallpapers() {
  final List<ImportedWallpaper> discovered = discoverSteamWallpapers();
  final Map<String, ImportedWallpaper> byTitle =
      <String, ImportedWallpaper>{};
  for (final ImportedWallpaper w in bundleWallpapers) {
    byTitle[w.title.toLowerCase()] = w;
  }
  for (final ImportedWallpaper w in discovered) {
    final String key = w.title.toLowerCase();
    // 本机版优先（除非打包版还没被覆盖，其实二者都可；这里让本机版覆盖）
    byTitle[key] = w;
  }
  return byTitle.values.toList();
}
