import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/track.dart';

/// 封面主色提取（R32 一.4 封面提色渐变）。
///
/// 加载封面图（本地文件优先，网络走 [NetworkImage] + Flutter ImageCache，
/// 复用已下载缓存、不重复请求），按步长缩采样后取平均主色。
///
/// - 结果按曲目 key 缓存，切曲时重提、切回时命中缓存，避免重复解码。
/// - 提取在后台 isolate 之外异步执行（解码/采样均在 Flutter 引擎线程，
///   单次开销 <2ms，可接受）。
/// - 任一环节失败（无封面 / 解码异常）返回 `null`，调用方回退主题 accent。
class PaletteExtractor {
  PaletteExtractor._();

  static final Map<String, Color> _cache = <String, Color>{};

  /// 采样步长：按步长跳跃取像素（跳过 7/8 像素），远快于全图遍历。
  static const int _step = 8;

  /// 提取封面主色；失败或无封面返回 `null`。
  static Future<Color?> dominantOf(Track? track) async {
    if (track == null) return null;
    final String key = _keyOf(track);
    final Color? cached = _cache[key];
    if (cached != null) return cached;

    final ui.Image? image = await _load(track);
    if (image == null) return null;
    try {
      final Color color = await _average(image);
      // 缓存上限：防长期运行无界增长（曲目再多也极少，设 64 够用）。
      if (_cache.length > 64) _cache.clear();
      _cache[key] = color;
      return color;
    } catch (_) {
      return null;
    }
    // 注意：不 dispose —— 网络图归 ImageCache 管理，dispose 会破坏缓存；
    // 本地解码图交给 GC 回收即可。
  }

  static String _keyOf(Track t) =>
      '${t.sourceId}|${t.title}|${t.artist}|${t.coverUrl}|${t.coverPath}';

  static Future<ui.Image?> _load(Track t) async {
    try {
      final String? path = t.coverPath;
      if (path != null && path.isNotEmpty && File(path).existsSync()) {
        final Uint8List bytes = await File(path).readAsBytes();
        return _decode(bytes);
      }
      final String? url = t.coverUrl;
      if (url != null && url.isNotEmpty) {
        // NetworkImage.resolve 走 ImageCache：已下载则零网络、未下载则触发
        // 加载并让缓存接管，与 TrackCover 共用同一份缓存。
        final NetworkImage provider = NetworkImage(url);
        final ImageStream stream =
            provider.resolve(ImageConfiguration.empty);
        final Completer<ui.Image> completer = Completer<ui.Image>();
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (ImageInfo info, bool sync) {
            if (!completer.isCompleted) completer.complete(info.image);
          },
          onError: (Object e, StackTrace? st) {
            if (!completer.isCompleted) completer.completeError(e);
          },
        );
        stream.addListener(listener);
        try {
          return await completer.future.timeout(const Duration(seconds: 8));
        } finally {
          stream.removeListener(listener);
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 按步长采样取平均色（RGBA）。
  static Future<Color> _average(ui.Image image) async {
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final int w = image.width;
    final int h = image.height;
    if (w <= 0 || h <= 0) return const Color(0xFF1A1A1A);
    int r = 0, g = 0, b = 0, n = 0;
    for (int y = 0; y < h; y += _step) {
      for (int x = 0; x < w; x += _step) {
        final int off = (y * w + x) * 4;
        r += data.getUint8(off);
        g += data.getUint8(off + 1);
        b += data.getUint8(off + 2);
        n++;
      }
    }
    if (n == 0) return const Color(0xFF1A1A1A);
    return Color.fromARGB(255, (r / n).round(), (g / n).round(), (b / n).round());
  }
}
