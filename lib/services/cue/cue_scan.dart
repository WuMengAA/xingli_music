import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/track.dart';
import 'cue_parser.dart';

/// 扫描时自动把「整轨 + 同目录 .cue」拆成逐轨子曲（T12 分轨自动化）。
///
/// 对每首本地曲：探测同基名 `.cue` 或目录内任一 `.cue`，其 `FILE` 命中本音频即
/// 按 INDEX 01 起点 / 下一轨起点（end）生成子曲（带 [Track.cueStartMs] /
/// [Track.cueEndMs]）。未被 CUE 覆盖的整轨保留原样。
List<Track> expandCueTracks(List<Track> base) {
  if (base.isEmpty) return base;
  final List<Track> out = <Track>[];
  for (final Track t in base) {
    if (t.isRemote) {
      out.add(t);
      continue;
    }
    final String uri = t.uri.startsWith('file://')
        ? Uri.parse(t.uri).toFilePath()
        : t.uri;
    final File audioFile = File(uri);
    final String dir = audioFile.parent.path;
    final String baseName = p.basenameWithoutExtension(uri);

    final List<File> cues = <File>[];
    final File primary = File(p.join(dir, '$baseName.cue'));
    if (primary.existsSync()) cues.add(primary);
    try {
      for (final FileSystemEntity e
          in Directory(dir).listSync(followLinks: false)) {
        if (e is File &&
            e.path.toLowerCase().endsWith('.cue') &&
            !cues.any((File c) => c.path == e.path)) {
          cues.add(e);
        }
      }
    } catch (_) {
      // 目录不可列：仅用 primary
    }

    bool split = false;
    for (final File cue in cues) {
      final CueSheet? sheet = parseCue(cue.readAsStringSync());
      if (sheet == null) continue;
      for (final CueTrack ct in sheet.tracks) {
        final String? audio = _resolveCueFile(ct.file, dir);
        if (audio == null || !_samePath(audio, uri)) continue;
        out.add(t.copyWith(
          title: ct.title.isEmpty ? t.title : ct.title,
          artist: ct.performer.isEmpty ? t.artist : ct.performer,
          source: TrackSource.local,
          sourceId: t.sourceId == 'local' ? 'cue' : '${t.sourceId}:cue',
          duration: ct.end == null
              ? t.duration
              : ct.end! - (ct.start ?? Duration.zero),
          cueStartMs: ct.startMs > 0 ? ct.startMs : null,
          cueEndMs: ct.endMs,
        ));
        split = true;
      }
      if (split) break;
    }
    if (!split) out.add(t);
  }
  return out;
}

/// CUE `FILE` 行 → 绝对路径（相对路径基于 cue 目录解析；绝对路径原样返回）。
String? _resolveCueFile(String? rel, String dir) {
  if (rel == null || rel.isEmpty) return null;
  if (rel.contains(':') || rel.startsWith('/')) return rel; // 绝对路径
  return p.join(dir, rel);
}

/// 路径相等（忽略大小写与分隔符）。
bool _samePath(String a, String b) {
  final String na = a.replaceAll('\\', '/').toLowerCase();
  final String nb = b.replaceAll('\\', '/').toLowerCase();
  return na == nb;
}
