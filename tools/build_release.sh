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

# ── D 盘构建约定（2026-08-12 SDK/缓存迁移后）──────────────
# C 盘空间紧张：Android SDK 已迁到 D:\Android\Sdk、Gradle 缓存迁到 D:\.gradle。
# 本脚本显式指定，避免因 shell 环境（setx 只对新进程生效）未继承变量而
# 回到 C 盘重建缓存（曾导致构建冷启动 10+ 分钟 + 重复下载依赖，用户反馈浪费流量）。
export GRADLE_USER_HOME="D:\.gradle"
export ANDROID_HOME="D:\Android\Sdk"

echo "==> 构建 release APK（可能耗时 1-3 分钟）"
# --no-tree-shake-icons：保留动态图标（ui_editor_model.resolveIcon 运行时解析 IconData，
# 无法被图标瘦身优化处理，release 下会报错）。
# 注：android/app/build.gradle 已配置 splits { abi { universalApk true } }，
# 一次构建即产出 arm64/armeabi 拆分包 + universal 整包（无需 --split-per-abi 标志，
# 否则会塞入 x86_64 与 androidComponents 排除规则冲突）。
"$FLUTTER" build apk --release --no-tree-shake-icons

# 从 AppVersion 读取展示版本与代号（与设置页一致；2026-08-17 渠道化：channel 替代 stage）
VERSION=$(grep -oP "static const int day = \K\d+" lib/core/app_version.dart)
BUILD=$(grep -oP "static const int buildCount = \K\d+" lib/core/app_version.dart)
CHANNEL=$(grep -oP "static const UpdateChannel channel = UpdateChannel\.\K\w+" lib/core/app_version.dart)
CODENAME=$(grep -oP "static const String codename = '\K[^']+" lib/core/app_version.dart)
YEAR=$(grep -oP "static const int year = \K\d+" lib/core/app_version.dart)
MONTH=$(grep -oP "static const int month = \K\d+" lib/core/app_version.dart)

BASE="星璃音乐_0.${YEAR}.${MONTH}.${VERSION}_${CHANNEL}_cl$(printf '%02d' "$BUILD")_${CODENAME}"
mkdir -p "$RELEASE_DIR"

FLD="build/app/outputs/flutter-apk"
# 整包（OTA 基线）：gradle universalApk 产出即 app-release.apk（已是历史 OTA 文件名，
# 应用内 ota_service.dart 的 kOtaAssetName 直接拉它，无需改名）。
if [ -f "$FLD/app-release.apk" ]; then
  cp "$FLD/app-release.apk" "$RELEASE_DIR/$BASE.apk"
  ( cd "$RELEASE_DIR" && sha256sum "$BASE.apk" > "$BASE.apk.sha256" )
  echo "    整包（OTA）：$BASE.apk"
fi

# 拆分包（更小，手动下载优选；现代手机多为 arm64-v8a，单包比整包小约 40%）
for pair in "app-arm64-v8a-release.apk:arm64" "app-armeabi-v7a-release.apk:arm32"; do
  src="${pair%%:*}"; tag="${pair##*:}"
  if [ -f "$FLD/$src" ]; then
    cp "$FLD/$src" "$RELEASE_DIR/$BASE.$tag.apk"
    ( cd "$RELEASE_DIR" && sha256sum "$BASE.$tag.apk" > "$BASE.$tag.apk.sha256" )
    echo "    拆分包：$BASE.$tag.apk"
  fi
done

echo ""
echo "==> 完成：$RELEASE_DIR/$BASE.apk （整包，OTA 用）"
echo "          $RELEASE_DIR/$BASE.arm64.apk / $BASE.arm32.apk （拆分，更小）"
echo "    （$(${FLUTTER} --version 2>/dev/null | head -1 || true)）"
