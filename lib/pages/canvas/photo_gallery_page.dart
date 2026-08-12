/// ════════════════════════════════════════════════════════════════════════
/// 照片墙（R23k）：拍下的「照片」= 可随时进入的场景
/// ════════════════════════════════════════════════════════════════════════
///
/// 读取**应用支持目录** captures/ 下「同名 .png + .json」对：
/// - 网格展示缩略图（PNG）；
/// - 点击 → 用 .json 里的 [VoxelSceneCapture]（seed + 机位）重建世界与
///   相机，push [PhotoScenePage] 进入该场景；
/// - 删除按钮把 PNG + JSON 一起移入回收站（保守：只删用户明确点的）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../widgets/voxel/voxel_capture_models.dart';
import '../../widgets/voxel/voxel_world_view3d.dart';

/// 一张已保存的照片（PNG + 场景快照）。
class _Photo {
  const _Photo({required this.png, required this.json, required this.capture});

  final File png;
  final File json;
  final VoxelSceneCapture capture;

  String get title {
    final String name = png.uri.pathSegments.last;
    return name.replaceFirst('voxel_', '').replaceFirst('.png', '');
  }
}

/// 照片墙页。
class PhotoGalleryPage extends StatefulWidget {
  const PhotoGalleryPage({super.key});

  @override
  State<PhotoGalleryPage> createState() => _PhotoGalleryPageState();
}

class _PhotoGalleryPageState extends State<PhotoGalleryPage> {
  List<_Photo>? _photos;
  String? _error;

  Future<void> _load() async {
    try {
      final Directory dir =
          Directory('${(await getApplicationSupportDirectory()).path}/captures');
      if (!await dir.exists()) {
        setState(() => _photos = const <_Photo>[]);
        return;
      }
      final List<File> jsons = await dir
          .list()
          .where((FileSystemEntity e) => e.path.endsWith('.json'))
          .cast<File>()
          .toList();
      final List<_Photo> list = <_Photo>[];
      for (final File j in jsons) {
        final File png = File(j.path.replaceFirst('.json', '.png'));
        if (!await png.exists()) continue;
        try {
          final Map<String, dynamic> map =
              jsonDecode(await j.readAsString()) as Map<String, dynamic>;
          list.add(_Photo(
            png: png,
            json: j,
            capture: VoxelSceneCapture.fromJson(map),
          ));
        } catch (_) {
          // 坏 JSON 跳过（不阻断整个列表）。
        }
      }
      list.sort((_Photo a, _Photo b) => b.title.compareTo(a.title));
      if (!mounted) return;
      setState(() => _photos = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _delete(_Photo p) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('删除这张照片？'),
        content: const Text('照片与对应场景快照都会被删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (await p.png.exists()) await p.png.delete();
      if (await p.json.exists()) await p.json.delete();
      if (!mounted) return;
      setState(() => _photos = _photos
          ?.where((_Photo e) => e.png.path != p.png.path)
          .toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e')),
      );
    }
  }

  void _enter(_Photo p) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoScenePage(capture: p.capture),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.bgPage,
      appBar: AppBar(
        backgroundColor: context.appColors.bgPage,
        foregroundColor: context.appColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('照片 · 场景', style: context.appText.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text('读取照片失败: $_error', style: context.appText.bodyMuted),
      );
    }
    final List<_Photo>? photos = _photos;
    if (photos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.photo_camera_outlined,
                size: 48, color: context.appColors.iconInactive),
            const SizedBox(height: AppSpace.md),
            Text('还没有照片\n在体素世界按快门拍下第一张', style: context.appText.bodyMuted),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpace.md),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: AppSpace.sm,
        crossAxisSpacing: AppSpace.sm,
        childAspectRatio: 1.15,
      ),
      itemCount: photos.length,
      itemBuilder: (BuildContext _, int i) {
        final _Photo p = photos[i];
        return _PhotoTile(
          photo: p,
          onTap: () => _enter(p),
          onDelete: () => _delete(p),
        );
      },
    );
  }
}

/// 单张照片卡片：缩略图 + 时间戳 + 进入/删除。
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.onTap,
    required this.onDelete,
  });

  final _Photo photo;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appColors.bgCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Image.file(
                photo.png,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: context.appColors.accentSoft,
                  child: Icon(Icons.image_not_supported_outlined,
                      color: context.appColors.iconInactive),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      photo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.appText.caption,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    visualDensity: VisualDensity.compact,
                    color: context.appColors.iconInactive,
                    tooltip: '删除',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 进入照片对应的场景：按快照 seed + 机位重建世界与相机。
class PhotoScenePage extends StatelessWidget {
  const PhotoScenePage({super.key, required this.capture});

  final VoxelSceneCapture capture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F16),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('进入场景', style: context.appText.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: VoxelWorldView3D(
        world: capture.toWorld(),
        initialCamera: capture.toCamera(),
      ),
    );
  }
}
