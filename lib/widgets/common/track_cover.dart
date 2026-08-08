import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/light_tokens.dart';
import '../../models/track.dart';

/// 曲目封面（唯一实现，禁止在别处重复造轮子）
///
/// 取图优先级：本地缓存文件 `coverPath` → 远程 `coverUrl` → 占位块。
/// 任一环节失败都平滑降级到占位块，永不抛出、永不留白框。
///
/// 复用点：`MiniPlayer` 左胶囊缩略图（48）、`AlbumCard` 封面（72）、
/// `NowPlayingPage` 大封面。
class TrackCover extends StatelessWidget {
  const TrackCover({
    super.key,
    required this.track,
    required this.size,
    this.radius = AppRadius.sm,
  });

  /// 目标曲目；`null` 表示当前无播放内容 → 直接渲染占位块
  final Track? track;

  /// 正方形边长
  final double size;

  /// 圆角
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    final Track? t = track;
    if (t != null) {
      final String? path = t.coverPath;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        return Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        );
      }
      final String? url = t.coverUrl;
      if (url != null && url.isNotEmpty) {
        return Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
          loadingBuilder: (BuildContext context, Widget child,
              ImageChunkEvent? progress) {
            if (progress == null) return child;
            return _placeholder();
          },
        );
      }
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return ColoredBox(
      color: AppColors.bgPlaceholder,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: size * 0.42,
          color: AppNeutral.n0,
        ),
      ),
    );
  }
}
