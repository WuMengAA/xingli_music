/// ════════════════════════════════════════════════════════════════════════
/// bsdiff/bspatch · 增量补丁合成（cl76_hotfix5：真正的补丁式热修复）
/// ════════════════════════════════════════════════════════════════════════
///
/// Flutter 是 AOT 编译，Dart 代码无法像 RN code-push 那样运行时热更；Android
/// 上最贴近「补丁热修复」的是 **增量差分**：
/// - 发布端用 bsdiff 生成「旧 APK → 新 APK」的差分包（几 MB，而非整包 71MB）；
/// - 客户端用**本地已装 APK 的副本（基线）** + 补丁合成出新 APK → SHA-256 校验
///   → 走系统安装器升级。
///
/// 本文件是纯 Dart 实现 `bspatch`（bsdiff 格式解包合成），零外部依赖——
/// 补丁格式即 Colin Percival 的 `BSDIFF40`：header(32B) + control + diff + extra。
library;

import 'dart:io';
import 'dart:typed_data';

/// 补丁合成异常（消息可直接展示）。
class OtaPatchException implements Exception {
  const OtaPatchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// `BSDIFF40` 魔数。
const List<int> _kMagic = <int>[
  0x42, 0x53, 0x44, 0x49, 0x46, 0x46, 0x34, 0x30,
];

/// 用 [patchPath]（BSDIFF40 差分）把 [oldPath]（旧 APK 基线）合成出 [newPath]。
///
/// 失败抛 [OtaPatchException]（补丁损坏 / 长度不符等），调用方可回退整包下载。
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
  final ByteData pb = patch.buffer.asByteData(patch.offsetInBytes, patch.length);
  final int ctrlLen = pb.getInt64(8, Endian.big);
  final int diffLen = pb.getInt64(16, Endian.big);
  final int newLen = pb.getInt64(24, Endian.big);
  if (ctrlLen < 0 ||
      diffLen < 0 ||
      newLen < 0 ||
      32 + ctrlLen + diffLen > patch.length) {
    throw const OtaPatchException('补丁文件损坏（长度非法）');
  }

  final Uint8List oldData = await File(oldPath).readAsBytes();
  final int oldLen = oldData.length;
  final Uint8List newData = Uint8List(newLen);

  int ctrlPos = 32;
  int diffPos = 32 + ctrlLen;
  int extraPos = 32 + ctrlLen + diffLen;
  int oldPos = 0;
  int newPos = 0;
  try {
    while (newPos < newLen) {
      final int x = pb.getInt64(ctrlPos, Endian.big);
      final int y = pb.getInt64(ctrlPos + 8, Endian.big);
      final int z = pb.getInt64(ctrlPos + 16, Endian.big);
      ctrlPos += 24;
      if (x < 0 || y < 0) throw const OtaPatchException('补丁文件损坏（控制块非法）');
      // diff 段：新字节 = 旧字节 + 差值（旧处为 0 时取原值）。
      for (int i = 0; i < x; i++) {
        final int d = patch[diffPos + i] & 0xFF;
        if (oldPos < oldLen && oldData[oldPos] != 0) {
          newData[newPos] = (oldData[oldPos] + d) & 0xFF;
        } else {
          newData[newPos] = d;
        }
        newPos++;
        oldPos++;
      }
      diffPos += x;
      // extra 段：原样拷贝。
      for (int i = 0; i < y; i++) {
        newData[newPos] = patch[extraPos + i];
        newPos++;
      }
      extraPos += y;
      oldPos += z;
    }
  } on RangeError {
    throw const OtaPatchException('补丁合成越界（补丁与基线不匹配）');
  }
  if (newPos != newLen) {
    throw const OtaPatchException('补丁合成失败（长度不符）');
  }
  await File(newPath).writeAsBytes(newData, flush: true);
}
