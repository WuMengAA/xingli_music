// 星璃 · m4a 码率/时长快速校验（零依赖 Dart 脚本，无需 ffmpeg）
//
// 用法: dart check_m4a.dart [目录]    （默认 assets/audio）
// 原理: 解析 MP4 容器 —— mvhd.duration/timescale 得时长，mdat 字节数×8/时长 ≈ 码率。
//       纯容器层估算（含少量容器开销），用于判断是否达到 ~128k 规范，足够。
// 运行: D:/flutter/bin/cache/dart-sdk/bin/dart tools/audio_pipeline/check_m4a.dart
import 'dart:io';
import 'dart:typed_data';

const int kOkBitrate = 120000; // 允许容器开销后 ≥ 120k 视为达标（目标 128k）

Uint8List _read(String path) => File(path).readAsBytesSync();

/// 返回 (type, size, payloadStart) 的迭代器。
Iterable<(String, int, int)> _atoms(Uint8List b, int start, int end) sync* {
  int p = start;
  while (p + 8 <= end) {
    final int size =
        (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
    final String type = String.fromCharCodes(b, p + 4, p + 8);
    if (size < 8) break; // 损坏
    final int real = size == 1 ? 16 : size; // 简化：不处理 64 位大 size（素材不会）
    yield (type, real, p + 8);
    p += real;
    if (p > end) break;
  }
}

/// 在 b[start..end] 里找指定 type 的 atom，返回 payloadStart（含 size 头）或 -1。
int _find(Uint8List b, int start, int end, String type) {
  for (final (String t, int size, int payload) in _atoms(b, start, end)) {
    if (t == type) return payload;
  }
  return -1;
}

/// 解析 mvhd 拿时长秒。
double? _durationOf(Uint8List b, int moovStart, int moovEnd) {
  final int mvhd = _find(b, moovStart, moovEnd, 'mvhd');
  if (mvhd < 0) return null;
  // mvhd payload: version(1)+flags(3)；
  // version0: creation(4)+modification(4) 后 timescale(4)+duration(4)
  // version1: creation(8)+modification(8) 后 timescale(4)+duration(8)
  final int version = b[mvhd];
  int off = mvhd + 4;
  off += version == 1 ? 16 : 8;
  final int timescale =
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];
  off += 4;
  double dur;
  if (version == 1) {
    dur = 0;
    for (int i = 0; i < 8; i++) {
      dur = dur * 256 + b[off + i];
    }
  } else {
    dur = ((b[off] << 24) |
            (b[off + 1] << 16) |
            (b[off + 2] << 8) |
            b[off + 3])
        .toDouble();
  }
  if (timescale <= 0) return null;
  return dur / timescale;
}

/// 找所有 mdat 的总大小（码率分子）。
int _mdatBytes(Uint8List b) {
  int total = 0;
  for (final (String t, int size, int _) in _atoms(b, 0, b.length)) {
    if (t == 'mdat') total += size;
  }
  return total;
}

void main(List<String> args) {
  final String dir = args.isNotEmpty ? args.first : 'assets/audio';
  if (!Directory(dir).existsSync()) {
    stdout.writeln('目录不存在: $dir');
    exit(1);
  }
  final List<File> files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.toLowerCase().endsWith('.m4a'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stdout.writeln('$dir 下没有 .m4a 文件');
    exit(0);
  }

  int pass = 0;
  for (final File f in files) {
    final Uint8List b = _read(f.path);
    final int moov = _find(b, 0, b.length, 'moov');
    if (moov < 0) {
      stdout.writeln('---- ${f.uri.pathSegments.last}  无 moov（损坏？）');
      continue;
    }
    final double? dur = _durationOf(b, moov, b.length);
    final int mdat = _mdatBytes(b);
    if (dur == null || dur <= 0 || mdat <= 0) {
      stdout.writeln('---- ${f.uri.pathSegments.last}  解析失败');
      continue;
    }
    final double bitrate = mdat * 8 / dur;
    final bool ok = bitrate >= kOkBitrate;
    if (ok) pass++;
    stdout.writeln(
        '${ok ? "PASS" : "----"} ${f.uri.pathSegments.last}  '
        '${dur.toStringAsFixed(1)}s  ~${(bitrate / 1000).round()}kbps');
  }
  stdout.writeln('\n达标 $pass/${files.length}（目标 128k，容器开销容忍 ≥120k）');
}
