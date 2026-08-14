import '../../core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/light_tokens.dart';
import '../../core/terms/naming_dict.dart';
import '../../models/library_folder.dart';
import '../../models/track.dart';
import '../../providers/audio/playback_notifier.dart';
import '../../widgets/common/info_row.dart';
import 'card_view.dart' show LibraryEmptyView;
import '../../widgets/notification/app_notify.dart';

/// 文件夹视图（v2 M3 · P0-M3-3）：按本地目录层级浏览。
///
/// - 竖屏：可展开目录树（目录名 + 曲目数）。
/// - 横屏（≥600dp）：左目录树（master）+ 右歌曲列表（detail，复用 [InfoRow]）。
///
/// 树由 tracks 按 `sourceId` + 本地路径前缀派生（架构 §4.2）。
class FolderView extends ConsumerStatefulWidget {
  const FolderView({super.key, required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends ConsumerState<FolderView> {
  final Set<String> _expanded = <String>{'/root'};
  String? _selectedPath = '/root';

  @override
  Widget build(BuildContext context) {
    final LibraryFolderNode root = buildFolderTree(widget.tracks);
    final double width = MediaQuery.sizeOf(context).width;
    final bool landscape = width >= AppSize.landscapeBreakpoint;

    if (landscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Master：目录树
          SizedBox(
            width: 260,
            child: Card(
              color: context.appColors.bgCard,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: context.appColors.border),
              ),
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.sm),
                children: <Widget>[
                  _buildNode(context, root, depth: 0, landscape: true),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          // Detail：选中目录的歌曲
          Expanded(
            child: _DetailList(
              tracks: _tracksOf(root, _selectedPath),
              empty: const LibraryEmptyView(),
            ),
          ),
        ],
      );
    }

    // 竖屏：可展开目录树
    if (widget.tracks.isEmpty) {
      return const LibraryEmptyView();
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        _buildNode(context, root, depth: 0, landscape: false),
      ],
    );
  }

  List<Track> _tracksOf(LibraryFolderNode root, String? pathKey) {
    if (pathKey == null || pathKey == '/root') return _flatten(root);
    LibraryFolderNode? node = _findNode(root, pathKey);
    if (node == null) return _flatten(root);
    return node.tracks;
  }

  List<Track> _flatten(LibraryFolderNode node) {
    final List<Track> all = <Track>[...node.tracks];
    for (final LibraryFolderNode c in node.children) {
      all.addAll(_flatten(c));
    }
    return all;
  }

  LibraryFolderNode? _findNode(LibraryFolderNode node, String pathKey) {
    if (node.pathKey == pathKey) return node;
    for (final LibraryFolderNode c in node.children) {
      final LibraryFolderNode? found = _findNode(c, pathKey);
      if (found != null) return found;
    }
    return null;
  }

  Widget _buildNode(
    BuildContext context,
    LibraryFolderNode node, {
    required int depth,
    required bool landscape,
  }) {
    final bool isLeaf = node.children.isEmpty;
    final bool isSelected = _selectedPath == node.pathKey;
    final bool isExpanded = _expanded.contains(node.pathKey);

    Widget row = InkWell(
      onTap: () {
        setState(() {
          _selectedPath = node.pathKey;
          if (!isLeaf) {
            if (_expanded.contains(node.pathKey)) {
              _expanded.remove(node.pathKey);
            } else {
              _expanded.add(node.pathKey);
            }
          }
        });
      },
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: EdgeInsets.only(
          left: 8.0 + depth * 16.0,
          right: 8,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              isLeaf
                  ? Icons.music_note_rounded
                  : (isExpanded
                      ? Icons.folder_open_rounded
                      : Icons.folder_rounded),
              size: AppSize.iconSm,
              color: isSelected ? context.appColors.accent : context.appColors.iconInactive,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name,
                style: context.appText.body.copyWith(
                  color: isSelected ? context.appColors.accent : context.appColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${node.trackCount}',
              style: context.appText.caption,
            ),
          ],
        ),
      ),
    );

    if (!landscape && !isLeaf) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          row,
          if (isExpanded)
            ...node.children
                .map((LibraryFolderNode c) =>
                    _buildNode(context, c, depth: depth + 1, landscape: false)),
        ],
      );
    }

    if (landscape) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          row,
          if (isExpanded && !isLeaf)
            ...node.children
                .map((LibraryFolderNode c) =>
                    _buildNode(context, c, depth: depth + 1, landscape: true)),
        ],
      );
    }

    return row;
  }
}

/// 右侧歌曲列表（detail）。
class _DetailList extends ConsumerWidget {
  const _DetailList({required this.tracks, required this.empty});

  final List<Track> tracks;
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) return empty;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: tracks.length,
      itemBuilder: (BuildContext context, int i) {
        final Track t = tracks[i];
        return InfoRow(
          track: t,
          onTap: () async {
            final String msg =
                await ref.read(playbackActionsProvider).playTrack(t);
            if (msg.isNotEmpty && context.mounted) {
              appNotify(context, msg);
            }
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 目录树构建（由 tracks 派生，架构 §4.2）
// ─────────────────────────────────────────────────────────────────────────

/// 从 tracks 构建目录树。
///
/// - 本地路径曲目（`uri` 含路径）：按 `/` 与 `\` 分隔建目录；
/// - 在线曲目（`http`）：归入「在线音源」虚拟目录（按 sourceId 分组）。
///
/// ⚠️ 本函数会向节点列表 `add`，因此**必须**显式传可变列表
/// （`children: <...>[]` / `tracks: <Track>[]`），否则 `LibraryFolderNode`
/// 的 `const []` 默认值会抛 `Unsupported operation: Cannot add to an
/// unmodifiable list`（P1-1 根因修复，勿改回缺省构造）。
LibraryFolderNode buildFolderTree(List<Track> tracks) {
  final LibraryFolderNode root = LibraryFolderNode(
    name: '全部',
    pathKey: '/root',
    children: <LibraryFolderNode>[],
    tracks: <Track>[],
  );
  final Map<String, LibraryFolderNode> nodes = <String, LibraryFolderNode>{
    '/root': root,
  };

  for (final Track t in tracks) {
    final List<String> segs = _segmentsFor(t);
    LibraryFolderNode current = root;
    String path = '/root';
    if (segs.isEmpty) {
      current.tracks.add(t);
      continue;
    }
    for (int i = 0; i < segs.length; i++) {
      path = '$path/${segs[i]}';
      LibraryFolderNode? child = nodes[path];
      if (child == null) {
        child = LibraryFolderNode(
          name: segs[i],
          pathKey: path,
          children: <LibraryFolderNode>[],
          tracks: <Track>[],
        );
        nodes[path] = child;
        current.children.add(child);
      }
      current = child;
    }
    current.tracks.add(t);
  }
  return root;
}

List<String> _segmentsFor(Track t) {
  if (t.isRemote) {
    // 在线音源 → 虚拟目录：在线音源 / sourceId
    return <String>[
      Terms.source,
      t.sourceId.isEmpty ? '在线' : t.sourceId,
    ];
  }
  final String uri = t.uri.replaceAll('\\', '/');
  final List<String> parts = uri
      .split('/')
      .where((String s) => s.isNotEmpty)
      .toList();
  // 去掉盘符（如 d:）
  if (parts.isNotEmpty && parts.first.endsWith(':')) {
    parts.removeAt(0);
  }
  // 去掉文件名
  if (parts.isNotEmpty) parts.removeLast();
  return parts;
}
