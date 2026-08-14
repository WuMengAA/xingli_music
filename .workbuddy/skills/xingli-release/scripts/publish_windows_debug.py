#!/usr/bin/env python3
"""Publish xingli_music Windows debug build to release/ via robocopy + verify.

Reads the canonical version string from android/app/build.gradle (versionName)
and codename from lib/core/app_version.dart, builds the release folder name,
copies build\\windows\\x64\\runner\\Debug, and verifies exe + data/flutter_assets.

Usage:
  python publish_windows_debug.py <PUB_INDEX> [--dry-run]

  <PUB_INDEX> : trailing counter on the release folder (independent counter, +1
                each publish; e.g. cl29 -> _55). No file source — pass manually.
"""
import os
import re
import subprocess
import sys


def find_root():
    d = os.path.dirname(os.path.abspath(__file__))
    while True:
        if os.path.isfile(os.path.join(d, "pubspec.yaml")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.getcwd()


ROOT = find_root()


def read_version_name():
    p = os.path.join(ROOT, "android", "app", "build.gradle")
    with open(p, encoding="utf-8") as f:
        m = re.search(r'versionName\s*=\s*"([^"]+)"', f.read())
    if not m:
        raise SystemExit("ERROR: versionName not found in android/app/build.gradle")
    return m.group(1)


def read_codename():
    p = os.path.join(ROOT, "lib", "core", "app_version.dart")
    with open(p, encoding="utf-8") as f:
        m = re.search(r"codename\s*=\s*'([^']+)'", f.read())
    return m.group(1) if m else "星尘初聚"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if not args:
        print("Usage: python publish_windows_debug.py <PUB_INDEX> [--dry-run]")
        sys.exit(2)

    pub = args[0]
    version_name = read_version_name()
    codename = read_codename()

    src = os.path.join(ROOT, "build", "windows", "x64", "runner", "Debug")
    folder = f"星璃音乐_{version_name}_{codename}_Windows_Debug_{pub}"
    dst = os.path.join(ROOT, "release", folder)

    print(f"versionName : {version_name}")
    print(f"codename    : {codename}")
    print(f"src         : {src}")
    print(f"dst folder  : release/{folder}")

    if not os.path.isdir(src):
        print("ERROR: build output missing — run `flutter build windows --debug` first.")
        sys.exit(1)

    if dry:
        print("[dry-run] would robocopy now.")
        sys.exit(0)

    os.makedirs(dst, exist_ok=True)
    rc = subprocess.call(["robocopy", src, dst, "/E", "/R:2", "/W:2", "/NFL", "/NDL"])
    if rc >= 2:
        print(f"ERROR: robocopy failed (exit {rc})")
        sys.exit(rc)

    exe = os.path.join(dst, "xingli_music.exe")
    data = os.path.join(dst, "data", "flutter_assets")
    ok = os.path.isfile(exe) and os.path.isdir(data)
    print(f"  exe   : {'OK' if os.path.isfile(exe) else 'MISSING'} "
          f"({os.path.getsize(exe) if os.path.isfile(exe) else 0} B)")
    print(f"  data/ : {'OK' if os.path.isdir(data) else 'MISSING'}")
    print("Published." if ok else "VERIFY FAILED.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
