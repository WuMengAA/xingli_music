import 'package:flutter/foundation.dart';

import 'track.dart';

/// 曲库「文件夹」视图的目录树节点（v2 M3 · P0-M3-3）。
///
/// 由曲库 tracks 按 `Track.sourceId` + 本地路径前缀派生：
/// - `pathKey` 用于展开状态与唯一标识；
/// - `children` 为子目录；`tracks` 为该目录直接包含的歌曲（不含子目录）。
@immutable
class LibraryFolderNode {
  const LibraryFolderNode({
    required this.name,
    required this.pathKey,
    this.children = const <LibraryFolderNode>[],
    this.tracks = const <Track>[],
  });

  /// 目录显示名（最后一段路径）。
  final String name;

  /// 唯一路径键（`/` 分隔的完整路径）。
  final String pathKey;

  /// 子目录。
  final List<LibraryFolderNode> children;

  /// 直接歌曲（不含子目录内歌曲）。
  final List<Track> tracks;

  /// 本目录（含所有子目录递归）的歌曲总数。
  int get trackCount =>
      tracks.length +
      children.fold<int>(0, (int sum, LibraryFolderNode c) => sum + c.trackCount);
}
