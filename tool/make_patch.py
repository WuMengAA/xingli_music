#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 BSDIFF40 增量补丁（cl76_hotfix6 起，Dart 端 bspatch 正确解码）。

用法:
    python3 tool/make_patch.py <旧APK> <新APK> <输出.patch> [--tag clNN]

说明:
    - 用 bsdiff4 生成 Colin Percival 的 BSDIFF40 差分（bzip2 压缩三块）。
    - APK 构建非字节可复现（Dex/资源顺序随小改动重排），bsdiff 的后缀对齐
      能把 71MB 整包压到约 4~5MB；朴素逐字节 delta 压不动（实测 42MB）。
    - Dart 端用 archive 包的 BZip2Decoder 解三块后标准 bspatch 合成。
"""
import os
import sys

import bsdiff4
import hashlib


def main() -> int:
    args = sys.argv[1:]
    if len(args) < 3:
        print("用法: python3 tool/make_patch.py <旧APK> <新APK> <输出.patch> [--tag clNN]")
        return 2

    old_path, new_path, out_path = args[0], args[1], args[2]
    if not os.path.isfile(old_path):
        print(f"旧 APK 不存在: {old_path}")
        return 1
    if not os.path.isfile(new_path):
        print(f"新 APK 不存在: {new_path}")
        return 1

    bsdiff4.file_diff(old_path, new_path, out_path)

    new_sha = hashlib.sha256(open(new_path, "rb").read()).hexdigest()
    size = os.path.getsize(out_path)
    print(f"patch 大小: {size/1024/1024:.2f} MB")
    print(f"new SHA256: {new_sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
