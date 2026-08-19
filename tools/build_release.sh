#!/usr/bin/env bash
# 星璃音乐 · 一键双平台 release 出包（Android APK + Windows 便携 zip）
#
# 产物目录（铁律）：D:\Stellara\Music\xingli_music\release\
#   星璃音乐_<0.YY.MM.DD>_<channel>_cl<NN>.<arm64|arm32>.apk + .sha256
#   星璃音乐_<0.YY.MM.DD>_<channel>_cl<NN>_pc_<代号>_win_portable.zip + .sha256
#
# 用法：
#   bash tools/build_release.sh            # 仅 Android（快）
#   bash tools/build_release.sh --win      # Android + Windows 便携 zip
#   bash tools/build_release.sh --help     # 本说明
#
# 前置（铁律，见 .workbuddy/memory/MEMORY.md）：
#   1. 版本号三处已同步：lib/core/app_version.dart + android/app/build.gradle
#      (versionCode/versionName) + pubspec.yaml version。
#   2. build/media_kit_libs_android_video/v1.1.7/ 下 4 个 jar 存在（缺失则去
#      D:/Stellara/Music/assets 复制，原件不许动）。
#   3. 绝不 flutter clean（会清掉预置 jar，下次构建卡死下载墙）。
set -e

cd "$(dirname "$0")/.."
FLUTTER="D:/flutter/bin/flutter.bat"
# ⚠️ 真实产物目录 = 工程内 release/（不是 D:/Stellara/Music/release —— 旧脚本
# 指错导致产物静默丢失，MEMORY 2026-08-17 铁律）。
RELEASE_DIR="D:/Stellara/Music/xingli_music/release"

# ── D 盘构建约定（2026-08-12 SDK/缓存迁移后）──────────────
# ⚠️ 必须用正斜杠！Git-Bash 双引号会吞 `\.` 反斜杠 → "D:\.gradle" 变 "D:.gradle"
# （非法）→ Gradle 静默回 C 盘重建缓存（冷启动 10+ 分钟 + 重复下载依赖）。
export GRADLE_USER_HOME=D:/.gradle
export ANDROID_HOME=D:/Android/Sdk

BUILD_WIN=0
for arg in "$@"; do
  case "$arg" in
    --win) BUILD_WIN=1 ;;
    --help|-h)
      sed -n '1,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

# ── 从 AppVersion 读取展示版本与代号（与设置页一致；2026-08-17 渠道化）──
VERSION=$(grep -oP "static const int day = \K\d+" lib/core/app_version.dart)
BUILD=$(grep -oP "static const int buildCount = \K\d+" lib/core/app_version.dart)
CHANNEL=$(grep -oP "static const UpdateChannel channel = UpdateChannel\.\K\w+" lib/core/app_version.dart)
CODENAME=$(grep -oP "static const String codename = '\K[^']+" lib/core/app_version.dart)
YEAR=$(grep -oP "static const int year = \K\d+" lib/core/app_version.dart)
MONTH=$(grep -oP "static const int month = \K\d+" lib/core/app_version.dart)

BASE="星璃音乐_0.${YEAR}.${MONTH}.${VERSION}_${CHANNEL}_cl$(printf '%02d' "$BUILD")"
echo "==> 版本基线：$BASE（代号 $CODENAME）"
mkdir -p "$RELEASE_DIR"

# ── 1. Android release APK ───────────────────────────────────
# --no-tree-shake-icons：保留动态图标（ui_editor_model.resolveIcon 运行时解析
#   IconData，无法被图标瘦身优化处理，release 下会报错）。
# -P disable-abi-filtering=true：Flutter 3.44.8 会向 ndk.abiFilters 注入默认
#   三架构，与 build.gradle 的 splits{abi} 冲突（AGP 报错），官方 flag 规避，
#   不动 build.gradle（MEMORY 2026-08-17）。
echo "==> 构建 Android release APK（1-3 分钟）"
set +e
"$FLUTTER" build apk --release --no-tree-shake-icons -P disable-abi-filtering=true
BUILD_EXIT=$?
set -e
# ⚠️ splits.abi 已知现象：构建成功但 flutter 收尾误报 "failed to produce an
# .apk file"（因产的是拆分 APK）。不能按退出码判失败，按产物存在性判。
if [ "$BUILD_EXIT" -ne 0 ] && ! ls build/app/outputs/flutter-apk/*-release.apk >/dev/null 2>&1; then
  echo "!! APK 构建失败（exit=$BUILD_EXIT，且无 release.apk 产物）" >&2
  exit 1
fi
echo "    （flutter 可能误报 failed to produce，拆分包实际已产出，见 flutter-apk/）"

FLD="build/app/outputs/flutter-apk"
for pair in "app-arm64-v8a-release.apk:arm64" "app-armeabi-v7a-release.apk:arm32"; do
  src="${pair%%:*}"; tag="${pair##*:}"
  if [ -f "$FLD/$src" ]; then
    cp "$FLD/$src" "$RELEASE_DIR/$BASE.$tag.apk"
    ( cd "$RELEASE_DIR" && sha256sum "$BASE.$tag.apk" > "$BASE.$tag.apk.sha256" )
    echo "    拆分包：$BASE.$tag.apk"
  fi
done

# ── 2. Windows release + 便携 zip（仅 --win 时）──────────────
if [ "$BUILD_WIN" = "1" ]; then
  echo "==> 构建 Windows release（1-2 分钟）"
  "$FLUTTER" build windows --release --no-tree-shake-icons
  WINREL="build/windows/x64/runner/Release"
  # 校验关键件：exe + sqlite3.dll 必须存在（缺失则 Windows 运行时崩）。
  test -f "$WINREL/xingli_music.exe" && echo "    exe OK"
  test -f "$WINREL/sqlite3.dll" && echo "    sqlite3.dll OK" || { echo "    ⚠️ sqlite3.dll 缺失"; exit 1; }

  # 7z 中文路径/非交互 glob 坑：先复制到 ASCII 临时目录，再压缩成 ASCII 名，
  # 最后 mv 成中文名（MEMORY 2026-08-17）。
  TMP="D:/temp/xingli_win_build"
  # 清理旧残留（上次中断可能留脏目录；失败不中断——沙箱可能拦批量删除）。
  rm -rf "$TMP" 2>/dev/null || true
  mkdir -p "$TMP"
  cp -r "$WINREL/." "$TMP/xingli_music/"
  ( cd "$TMP" && "C:/Program Files/7-Zip/7z.exe" a -tzip -mx=9 "$TMP/x.zip" xingli_music >/dev/null )
  WIN_ZIP="$RELEASE_DIR/${BASE}_pc_${CODENAME}_win_portable.zip"
  mv "$TMP/x.zip" "$WIN_ZIP"
  # ⚠️ sha256 必须在清理临时目录【之前】生成——沙箱对批量 rm -rf 会弹
  # SAFE_DELETE 确认并中断 set -e，导致哈希步丢失（cl02 实测踩中）。
  ( cd "$RELEASE_DIR" && sha256sum "${BASE}_pc_${CODENAME}_win_portable.zip" > "${BASE}_pc_${CODENAME}_win_portable.zip.sha256" )
  # 清理临时目录：失败不中断（被沙箱拦时仅残留 D:/temp 垃圾，产物已完整）。
  rm -rf "$TMP" 2>/dev/null || true
  echo "    便携包：$WIN_ZIP"
fi

echo ""
echo "==> 完成：$RELEASE_DIR/"
ls -la "$RELEASE_DIR" | grep "$BASE" || true
echo "    （$(${FLUTTER} --version 2>/dev/null | head -1 || true)）"
