import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme_colors.dart';
import '../../core/theme/light_tokens.dart';
import '../../models/track.dart';

/// 封面文件存在性缓存：避免 `File.existsSync()` 在每次 `build`/`_buildImage`
/// 重建时都打磁盘（滚动列表里每帧同步 IO = 明显卡顿）。按路径缓存一次，
/// 仅在首次访问时做一次同步 IO；之后走内存查表。
///
/// 缓存命中为「存在」时若文件后续被删，`Image.file` 的 `errorBuilder` 仍会
/// 平滑降级到占位块；缓存为「不存在」时若文件稍后出现，最多延迟到下次
/// 重建才命中本地图——对本音乐 App 的封面场景可接受（路径在会话内稳定）。
final Map<String, bool> _coverExistsCache = <String, bool>{};

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
        child: _buildImage(context),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final Track? t = track;
    if (t != null) {
      // ── 内存：按「实际显示尺寸 × 设备像素比」限制解码尺寸 ──────────
      // 不加 cacheWidth 时，48dp 的缩略图也会完整解码 1000px 原图
      // （≈4MB/张），几百首歌的封面就能把内存推到 GB 级——这是启动后
      // 内存飙升的主因。限制后 48dp 缩略图仅解码约 144px（≈80KB）。
      final int cachePx =
          (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 768);
      final String? path = t.coverPath;
      // 存在性走缓存：首次才做同步 IO，避免滚动时每帧打磁盘。
      // 判空与存在性检查保持在本层，`path` 进入分支后被收窄为 `String`。
      if (path != null && path.isNotEmpty) {
        final bool exists =
            _coverExistsCache.putIfAbsent(path, () => File(path).existsSync());
        if (exists) {
          return Image.file(
            File(path),
            width: size,
            height: size,
            cacheWidth: cachePx,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(context),
            // cl07：封面加载完成渐显（不硬跳）。
            frameBuilder: (BuildContext c, Widget child, int? frame,
                bool wasSync) {
              if (wasSync) return child;
              return _fadeIn(child);
            },
          );
        }
      }
      final String? url = t.coverUrl;
      if (url != null && url.isNotEmpty) {
        return Image.network(
          url,
          width: size,
          height: size,
          cacheWidth: cachePx,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context),
          loadingBuilder: (BuildContext context, Widget child,
              ImageChunkEvent? progress) {
            // cl07：加载完成 → 平滑渐显，替代「占位块 → 图」硬跳。
            if (progress == null) return _fadeIn(child);
            return _placeholder(context);
          },
        );
      }
    }
    return _placeholder(context);
  }

  /// cl07：封面加载完成平滑渐显（180ms，避免占位块→图硬跳）。
  Widget _fadeIn(Widget child) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: 1),
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
    builder: (BuildContext context, double v, Widget? c) =>
        Opacity(opacity: v, child: c),
    child: child,
  );

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: context.appColors.bgPlaceholder,
      child: Center(
        child: Icon(
          Icons.music_note,
          size: size * 0.42,
          color: context.appColors.bgCard,
        ),
      ),
    );
  }
}
