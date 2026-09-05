#!/usr/bin/env bash
# 星璃音乐 · 一键双平台 release 出包（Android APK + Windows 安装包）
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
mkdir -p build/app/outputs/flutter-apk
# ⚠️ 新鲜度基准：记录构建开始的时刻，构建后只认比它更新的 APK。
#    这是为了堵死「构建真失败 → 脚本把上一次的旧包当成新版本拷出去」的错标
#    产物（2026-08-29 实测踩中：cl10 包与 cl09 sha256 完全相同）。
#    刻意用时间戳比对而**不删旧包**：build/ 下的预置 media_kit jar 绝不能动
#    （绝不 flutter clean），批量删除又易误伤，比对 mtime 是无副作用的做法。
_STAMP="build/app/outputs/flutter-apk/.pre_build_stamp"
touch "$_STAMP"
set +e
"$FLUTTER" build apk --release --no-tree-shake-icons -P disable-abi-filtering=true
BUILD_EXIT=$?
set -e
echo "    （flutter 可能误报 failed to produce，拆分包实际已产出，见 flutter-apk/）"

FLD="build/app/outputs/flutter-apk"
APK_COUNT=0
for pair in "app-arm64-v8a-release.apk:arm64" "app-armeabi-v7a-release.apk:arm32"; do
  src="${pair%%:*}"; tag="${pair##*:}"
  # 只看本次构建的产物：-nt 比对 mtime，旧包（无论存在多久）都不会被采纳。
  if [ -f "$FLD/$src" ] && [ "$FLD/$src" -nt "$_STAMP" ]; then
    cp "$FLD/$src" "$RELEASE_DIR/$BASE.$tag.apk"
    ( cd "$RELEASE_DIR" && sha256sum "$BASE.$tag.apk" > "$BASE.$tag.apk.sha256" )
    echo "    拆分包：$BASE.$tag.apk"
    APK_COUNT=$((APK_COUNT + 1))
  else
    echo "    ！$src 不是本次产物，已跳过（不复用旧包）" >&2
  fi
done
# 一个都没产出的情况下必须显式失败——不能静默跳过，否则 release/ 里会留下
# 上一次的残留，让人误以为出包成功。
# ⚠️ splits.abi 已知现象：构建成功但 flutter 收尾误报 "failed to produce an
# .apk file"。所以这里不按退出码、而按「有没有新鲜产物」判定。
if [ "$APK_COUNT" -eq 0 ]; then
  echo "!! APK 构建失败（exit=$BUILD_EXIT）：本次未产出任何新的拆分包" >&2
  echo "   release/ 未更新 —— 旧包不会冠以新版本号被拷出" >&2
  exit 1
fi

# ── 2. Windows release + 安装包（仅 --win 时）──────────────
if [ "$BUILD_WIN" = "1" ]; then
  echo "==> 构建 Windows release（1-2 分钟）"
  "$FLUTTER" build windows --release --no-tree-shake-icons
  WINREL="build/windows/x64/runner/Release"
  # 校验关键件：exe + sqlite3.dll 必须存在（缺失则 Windows 运行时崩）。
  test -f "$WINREL/xingli_music.exe" && echo "    exe OK"
  test -f "$WINREL/sqlite3.dll" && echo "    sqlite3.dll OK" || { echo "    ⚠️ sqlite3.dll 缺失"; exit 1; }

  # 安装包程序（Inno Setup 7）：用户要求 Windows 只发安装包、不再发便携 zip。
  # ISCC 不在 PATH，用 AppData Local Programs 绝对路径；OutputBaseFilename 已在
  # inno_xingli.iss 固定为 ASCII 的 xingli_music_windows_x64（与 OTA
  # otaWindowsAssetName() 一致——GitHub 会剥离非 ASCII，必须 ASCII）。版本经
  # /dMyAppVersion 注入（与 pubspec 三段式同源）。
  ISCC="C:/Users/Administrator/AppData/Local/Programs/Inno Setup 7/ISCC.exe"
  if [ ! -f "$ISCC" ]; then echo "    ⚠️ ISCC.exe 缺失（$ISCC）"; exit 1; fi
  WIN_VER="${YEAR}.${MONTH}.${VERSION}"
  "$ISCC" "tools/inno_xingli.iss" "/dMyAppVersion=$WIN_VER"
  WIN_EXE="$RELEASE_DIR/xingli_music_windows_x64.exe"
  test -f "$WIN_EXE" && echo "    安装包：$WIN_EXE" || { echo "    ⚠️ 安装包未生成"; exit 1; }
  # sha256（安装包体积较大，固定 contentLength 的 Dart 上传桥会用到一致值）。
  ( cd "$RELEASE_DIR" && sha256sum "xingli_music_windows_x64.exe" > "xingli_music_windows_x64.exe.sha256" )
  echo "    安装包 sha256 已生成"
fi

echo ""
echo "==> 完成：$RELEASE_DIR/"
ls -la "$RELEASE_DIR" | grep "$BASE" || true
echo "    （$(${FLUTTER} --version 2>/dev/null | head -1 || true)）"
