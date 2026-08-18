#!/usr/bin/env bash
# alpha_cl02 Windows 构建 + 打包（便携 zip + Inno setup + sha256）。
# 注意：release 总文件夹 = xingli_music/release（与 inno_xingli.iss 的 MyOut 一致），
# 不是 /d/Stellara/Music/release（该目录不存在）。
set -u
ROOT=/d/Stellara/Music/xingli_music
REL=/d/Stellara/Music/xingli_music/release
LOG=$ROOT/build_windows_alpha.log
export ANDROID_HOME=/d/Android/Sdk
export PATH="/d/flutter/bin:/c/Program Files (x86)/Microsoft Visual Studio/18/BuildTools/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin:$PATH"
cd "$ROOT"
mkdir -p "$REL"
echo "=== win alpha build start $(date) ===" >> "$LOG"
flutter build windows --release --no-tree-shake-icons >> "$LOG" 2>&1
echo "BUILD_EXIT=$?" >> "$LOG"
EXE=$ROOT/build/windows/x64/runner/Release/xingli_music.exe
if [ ! -f "$EXE" ]; then echo "=== BUILD FAILED ===" >> "$LOG"; exit 1; fi
NAME="星璃音乐_0.26.08.17_alpha_cl02_win_portable"
DST="$REL/$NAME"
rm -rf "$DST"
cp -r "$ROOT/build/windows/x64/runner/Release" "$DST"
"/c/Program Files/7-Zip/7z.exe" a -tzip "$REL/${NAME}.zip" "$DST/*" -mx=9 >> "$LOG" 2>&1
"/c/Users/Administrator/AppData/Local/Programs/Inno Setup 7/ISCC.exe" "$ROOT/tools/inno_xingli.iss" >> "$LOG" 2>&1
for f in "$REL/${NAME}.zip" "$REL/星璃音乐_0.26.08.17_alpha_cl02_win_setup.exe"; do
  if [ -f "$f" ]; then
    sha256sum "$f" | sed 's# .*/#  #' > "$f.sha256"
  fi
done
echo "=== win alpha build DONE $(date) ===" >> "$LOG"
