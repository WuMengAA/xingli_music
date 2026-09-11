/// M3U / M3U8 播放列表解析与序列化（完善功能：播放列表导入导出）。
///
/// 解析覆盖常见两种写法：
///   - `#EXTINF:123,Artist - Title`（逗号后整体作标题，含 " - " 则拆艺人）
///   - `#EXTINF:-1 t="Title"`（t= 属性优先作标题）
/// URI 行可为本地绝对路径或 http(s) 直链；相对路径按 .m3u 所在目录拼接。
library;

import '../../models/track.dart';

/// 一条 M3U 解析结果（尚未转成可播放 [Track]）。
class M3uEntry {
  const M3uEntry({
    required this.uri,
    this.title,
    this.artist,
    this.duration,
  });

  final String uri;
  final String? title;
  final String? artist;
  final Duration? duration;
}

/// 解析 M3U/M3U8 文本 → 条目列表（跳过空行与未知指令行）。
List<M3uEntry> parseM3u(String content) {
  final List<M3uEntry> out = <M3uEntry>[];
  String? pendingTitle;
  String? pendingArtist;
  Duration? pendingDuration;

  for (final String raw in content.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#')) {
      if (line.startsWith('#EXTINF')) {
        // 时长：#EXTINF:123,...
        final RegExp durRe = RegExp(r'#EXTINF:\s*(-?\d+(?:\.\d+)?)');
        final RegExpMatch? durMatch = durRe.firstMatch(line);
        if (durMatch != null) {
          final double secs = double.tryParse(durMatch.group(1)!) ?? -1;
          if (secs > 0) pendingDuration = Duration(milliseconds: (secs * 1000).round());
        }
        // t="Title" 优先
        final RegExp tRe = RegExp(r't="([^"]*)"');
        final RegExpMatch? tMatch = tRe.firstMatch(line);
        if (tMatch != null && tMatch.group(1)!.isNotEmpty) {
          pendingTitle = tMatch.group(1);
        }
        // 逗号后的 "Artist - Title" / 纯标题
        final int comma = line.indexOf(',');
        if (comma >= 0) {
          final String meta = line.substring(comma + 1).trim();
          if (meta.isNotEmpty) {
            if (pendingTitle == null || pendingTitle.isEmpty) {
              if (meta.contains(' - ')) {
                final List<String> parts = meta.split(' - ');
                pendingArtist = parts.first.trim();
                pendingTitle = parts.sublist(1).join(' - ').trim();
              } else {
                pendingTitle = meta;
              }
            }
          }
        }
      }
      // #EXTM3U / #EXT-X-* / 注释：忽略
      continue;
    }

    out.add(M3uEntry(
      uri: line,
      title: pendingTitle,
      artist: pendingArtist,
      duration: pendingDuration,
    ));
    pendingTitle = null;
    pendingArtist = null;
    pendingDuration = null;
  }
  return out;
}

/// 把 M3U 条目转为可播放 [Track]：本地路径 → [TrackSource.local]，
/// http(s) → [TrackSource.stream]；标题缺省回退为文件名。
List<Track> tracksFromM3u(List<M3uEntry> entries) => entries.map((M3uEntry e) {
      final bool remote = e.uri.startsWith('http');
      final String name = e.title ?? _basename(e.uri);
      return Track(
        title: name.isEmpty ? '未知曲目' : name,
        artist: e.artist ?? '',
        uri: e.uri,
        source: remote ? TrackSource.stream : TrackSource.local,
        sourceId: remote ? 'm3u' : 'local',
        duration: e.duration,
      );
    }).toList();

/// 序列化 [Track] 列表为 .m3u8 文本（#EXTM3U + #EXTINF）。
String serializeM3u(List<Track> tracks) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('#EXTM3U');
  for (final Track t in tracks) {
    final String dur = t.duration != null ? t.duration!.inSeconds.toString() : '-1';
    final String titleLine =
        t.artist.isNotEmpty ? '${t.artist} - ${t.title}' : t.title;
    sb.writeln('#EXTINF:$dur,$titleLine');
    sb.writeln(t.uri);
  }
  return sb.toString();
}

/// 取路径/URL 的文件名（去扩展名）作标题回退。
String _basename(String uri) {
  final int slash = uri.lastIndexOf('/');
  String name = slash >= 0 ? uri.substring(slash + 1) : uri;
  final int dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  return name;
}
