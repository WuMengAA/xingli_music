#!/usr/bin/env bash
# 星璃音乐 · 一键构建并放到「默认产物文件夹」
#
# 产物默认位置：D:\Stellara\Music\release\星璃音乐_<版本>_<代号>.apk
# （版本/代号来自 lib/core/app_version.dart 的 AppVersion.display / codename）
#
# 用法：bash tools/build_release.sh
set -e

cd "$(dirname "$0")/.."
FLUTTER="D:/flutter/bin/flutter.bat"
RELEASE_DIR="D:/Stellara/Music/release"

echo "==> 构建 release APK（可能耗时 1-3 分钟）"
"$FLUTTER" build apk --release

SRC="build/app/outputs/flutter-apk/app-release.apk"
# 从 AppVersion 读取展示版本与代号（与设置页一致）
VERSION=$(grep -oP "static const int day = \K\d+" lib/core/app_version.dart)
BUILD=$(grep -oP "static const int buildCount = \K\d+" lib/core/app_version.dart)
STAGE=$(grep -oP "static const AppStage stage = AppStage\.\K\w+" lib/core/app_version.dart)
CODENAME=$(grep -oP "static const String codename = '\K[^']+" lib/core/app_version.dart)
YEAR=$(grep -oP "static const int year = \K\d+" lib/core/app_version.dart)
MONTH=$(grep -oP "static const int month = \K\d+" lib/core/app_version.dart)

NAME="星璃音乐_0.${YEAR}.${MONTH}.${VERSION}_${STAGE}_cl$(printf '%02d' "$BUILD")_${CODENAME}.apk"
mkdir -p "$RELEASE_DIR"
cp "$SRC" "$RELEASE_DIR/$NAME"

echo ""
echo "==> 完成：$RELEASE_DIR/$NAME"
echo "    （$(${FLUTTER} --version 2>/dev/null | head -1 || true)）"
