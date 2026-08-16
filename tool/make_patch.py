#!/usr/bin/env python3
"""星璃音乐 · OTA 增量补丁生成（cl76_hotfix5 补丁式热修复）。

用法：
    python tool/make_patch.py <old_apk> <new_apk> [--tag cl76_hotfix5]

生成 `app-release.apk.patch`（BSDIFF40 差分），并提示上传到目标 Release。

客户端 `OtaService.downloadAndVerify` 检测到该 asset 且本地留存有基线
（`files/ota_base.apk`）时，自动「基线 + 补丁」合成新包 → SHA-256 校验 →
安装；补丁缺失/合成失败自动回退整包下载。
"""
import argparse
import os
import sys


def main() -> None:
    ap = argparse.ArgumentParser(description="生成星璃 OTA 增量补丁")
    ap.add_argument("old_apk", help="旧版本 APK（客户端基线版本，如 cl76 的包）")
    ap.add_argument("new_apk", help="新版本 APK（本次发布，如 cl76_hotfix5 的包）")
    ap.add_argument("--tag", default="cl76_hotfix5", help="目标 Release tag")
    args = ap.parse_args()

    if not (os.path.exists(args.old_apk) and os.path.exists(args.new_apk)):
        sys.exit("old_apk / new_apk 文件不存在")
    try:
        import bsdiff4
    except ImportError:
        sys.exit("需要 bsdiff4：pip install bsdiff4")

    out = "app-release.apk.patch"
    bsdiff4.file_diff(args.old_apk, args.new_apk, out)
    old_sz = os.path.getsize(args.old_apk)
    new_sz = os.path.getsize(args.new_apk)
    patch_sz = os.path.getsize(out)
    print(
        f"old: {old_sz / 1e6:.1f} MB   new: {new_sz / 1e6:.1f} MB   "
        f"patch: {patch_sz / 1e6:.2f} MB（省 {(1 - patch_sz / new_sz) * 100:.0f}%）"
    )
    print(f"→ 上传 {out} 到 Release {args.tag} 的 asset（与 app-release.apk 同 tag）")


if __name__ == "__main__":
    main()
