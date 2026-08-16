/// ════════════════════════════════════════════════════════════════════════
/// OTA 增量补丁合成（cl76_hotfix6：修复 cl76_hotfix5 的 bspatch 致命缺陷）
/// ════════════════════════════════════════════════════════════════════════
///
/// 背景 / cl76_hotfix5 的缺陷：
/// - 当时把 BSDIFF40 的控制/diff/extra 三块当成**未压缩**字节直接读，且 header
///   按**大端**解析 → 永远抛「补丁文件损坏（长度非法）」，合成不出合法 APK。
///   Dart 标准库无 bzip2 解码器，必须引入 [archive] 包的 BZip2Decoder。
/// - 桌面端「MATCH」用的是 Python bsdiff4 参考实现，从未跑过这个 Dart 函数，
///   缺陷一直没暴露 → 真机补丁升级失败（错误 110）。
///
/// 标准 BSDIFF40 格式（本文件为纯 Dart 正确实现）：
///   [0..7]    "BSDIFF40"
///   [8..15]   ctrlLen   int64 LE  —— bzip2(控制块) 的压缩长度
///   [16..23]  diffLen   int64 LE  —— bzip2(diff块) 的压缩长度
///   [24..31]  newSize   int64 LE  —— 合成后 APK 总字节数
///   [32 .. 32+ctrlLen)             bzip2 压缩的控制块
///   [..   +diffLen)                bzip2 压缩的 diff 块（有符号 delta）
///   [..   ]                        bzip2 压缩的 extra 块（原样字面字节）
///
/// 控制块解压后是连续的 (x,y,z) 三元组，每项 int64 LE 有符号：
///   x = diff 段长度，y = extra 段长度，z = old 指针相对前移量。
/// 合成（标准 bspatch）：
///   for 每块:
///     new[newpos..] += old[oldpos..] + diff[diffpos..]  (diff 为有符号字节)
///     new[newpos..]  = extra[extrapos..]                 (字面拷贝)
///     oldpos += z
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show BZip2Decoder;

/// 补丁合成异常（消息可直接展示）。
class OtaPatchException implements Exception {
  const OtaPatchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// BSDIFF40 魔数。
const List<int> _kMagic = <int>[
  0x42, 0x53, 0x44, 0x49, 0x46, 0x46, 0x34, 0x30, // "BSDIFF40"
];

/// 读 BSDIFF40 的 offtin 编码（非标准二进制补码）：
/// 大端幅值（7 字节）+ 第 8 字节最高位为符号位。bsdiff4 用此格式存控制三元组
/// 与 header 长度；小正数与标准补码巧合一致，负数/高位字节会出错，故必须专用。
int _readI64(Uint8List b, int off) {
  int y = b[off + 7] & 0x7F;
  for (int i = 6; i >= 0; i--) {
    y = y * 256 + b[off + i];
  }
  if ((b[off + 7] & 0x80) != 0) y = -y;
  return y;
}

/// 把 [patchPath]（BSDIFF40 差分）把 [oldPath]（旧 APK 基线）合成出 [newPath]。
///
/// 失败抛 [OtaPatchException]，调用方可回退整包下载。
Future<void> bspatch(
  String oldPath,
  String newPath,
  String patchPath,
) async {
  final Uint8List patch = await File(patchPath).readAsBytes();
  if (patch.length < 32) {
    throw const OtaPatchException('补丁文件损坏（过短）');
  }
  for (int i = 0; i < 8; i++) {
    if (patch[i] != _kMagic[i]) {
      throw const OtaPatchException('补丁文件损坏（非 BSDIFF40）');
    }
  }

  final int ctrlLen = _readI64(patch, 8);
  final int diffLen = _readI64(patch, 16);
  final int newSize = _readI64(patch, 24);
  if (ctrlLen < 0 ||
      diffLen < 0 ||
      newSize <= 0 ||
      newSize > 1024 * 1024 * 1024 ||
      32 + ctrlLen + diffLen > patch.length) {
    throw const OtaPatchException('补丁文件损坏（长度非法）');
  }

  // 三段 bzip2 流。
  final Uint8List ctrlComp = patch.sublist(32, 32 + ctrlLen);
  final Uint8List diffComp = patch.sublist(32 + ctrlLen, 32 + ctrlLen + diffLen);
  final Uint8List extraComp =
      patch.sublist(32 + ctrlLen + diffLen, patch.length);

  final BZip2Decoder bz = BZip2Decoder();
  late final Uint8List ctrl;
  late final Uint8List diff;
  late final Uint8List extra;
  try {
    ctrl = Uint8List.fromList(bz.decodeBytes(ctrlComp));
    diff = Uint8List.fromList(bz.decodeBytes(diffComp));
    extra = Uint8List.fromList(bz.decodeBytes(extraComp));
  } on Exception catch (e) {
    throw OtaPatchException('补丁解压失败：$e');
  }

  final Uint8List oldData = await File(oldPath).readAsBytes();
  final int oldLen = oldData.length;
  final Uint8List newData = Uint8List(newSize);

  int ctrlPos = 0;
  int diffPos = 0;
  int extraPos = 0;
  int oldPos = 0;
  int newPos = 0;

  try {
    while (newPos < newSize) {
      final int x = _readI64(ctrl, ctrlPos);
      final int y = _readI64(ctrl, ctrlPos + 8);
      final int z = _readI64(ctrl, ctrlPos + 16);
      ctrlPos += 24;
      if (x < 0 || y < 0) {
        throw const OtaPatchException('补丁文件损坏（控制块非法）');
      }

      // diff 段：new = old + signed(diff)；old 越界时只取 diff。
      for (int i = 0; i < x; i++) {
        final int dByte = diff[diffPos + i];
        final int signed = dByte <= 127 ? dByte : dByte - 256;
        final int o = (oldPos + i) < oldLen ? oldData[oldPos + i] : 0;
        newData[newPos + i] = (o + signed) & 0xFF;
      }
      diffPos += x;
      newPos += x;
      oldPos += x;

      // extra 段：原样拷贝。
      for (int i = 0; i < y; i++) {
        newData[newPos + i] = extra[extraPos + i];
      }
      extraPos += y;
      newPos += y;

      oldPos += z;
    }
  } on RangeError {
    throw const OtaPatchException('补丁合成越界（补丁与基线不匹配）');
  }

  if (newPos != newSize) {
    throw const OtaPatchException('补丁合成失败（长度不符）');
  }

  await File(newPath).writeAsBytes(newData, flush: true);
}
