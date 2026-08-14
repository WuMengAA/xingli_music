---
name: xingli-release
description: This skill should be used when publishing a new Windows debug build of the 星璃音乐 (xingli_music) Flutter voxel-game project — bumping the clNN build counter, rebuilding, and robocopying to the release/ folder. Trigger on requests like "发版", "发布", "构建", "build windows", "bump version", or after landing a feature batch that needs shipping. Encodes the project's version convention (lib/core/app_version.dart + android/app/build.gradle sync) and the release-folder naming.
agent_created: true
---

# Xingli Release (星璃音乐 / xingli_music 发版)

## Overview
Standardize the Windows debug release cadence for the xingli_music Flutter voxel-game project. The cadence keeps three version sources in sync, rebuilds, and copies the runner to a dated release folder. Use this skill whenever a feature batch is ready to ship (after `flutter analyze` passes and code is complete).

## When to use
- User says "发版 / 发布 / 构建 / build / bump version" for xingli_music.
- After landing a feature batch that needs a shippable Windows debug build.
- When asked to prepare a release folder under `release/`.

## Workflow

### Step 1 — Read current version
Open `lib/core/app_version.dart`. Read `static const int buildCount = N;` (this is the `clNN`). Note `major=0`, `year`, `month`, `day`, `codename='星尘初聚'`, `stage=AppStage.alpha`. The display string is `0.{yy}.{mm}.{dd}_alpha_clNN` (e.g. `0.26.8.13_alpha_cl29`).

### Step 2 — Bump buildCount (clNN)
In `lib/core/app_version.dart`, change `static const int buildCount = N;` → `N+1`. This is a compile-time constant shown in Settings → About.

### Step 3 — Bump versionName (Android, keep in sync)
In `android/app/build.gradle`, change `versionName = "0.26.8.13_alpha_clN";` → `"0.26.8.13_alpha_cl{N+1}";`. Keep this string identical to the app_version display (it already includes clNN).

### Step 4 — Do NOT touch pubspec.yaml version
`pubspec.yaml` `version:` is `0.26.8+13` (per-day `0.YY.MM+DD`); cl is NOT part of it. Leave it.

### Step 5 — Rebuild Windows debug
Run `flutter build windows --debug` from the project root. Wait for `√ Built build\windows\x64\runner\Debug\xingli_music.exe`. Treat 0-error `flutter analyze lib` as the gate before building.

### Step 6 — Publish via script (robocopy + verify)
Run the bundled helper:
```
python .workbuddy/skills/xingli-release/scripts/publish_windows_debug.py <PUB_INDEX>
```
- Reads `versionName` from `android/app/build.gradle` + `codename` from `lib/core/app_version.dart`, builds the release folder name, robocopies `build\windows\x64\runner\Debug` → `release\星璃音乐_<versionName>_<codename>_Windows_Debug_<PUB_INDEX>`, then verifies `xingli_music.exe` + `data/flutter_assets` exist.
- `<PUB_INDEX>` = the trailing counter on the release folder. Independent counter (no file source); +1 each publish (cl28→`_54`, cl29→`_55`). Pass manually.
- Use `--dry-run` to preview the folder name without copying.
- Or run robocopy manually:
  ```
  robocopy "build\windows\x64\runner\Debug" "release\星璃音乐_0.26.8.13_alpha_cl<N+1>_星尘初聚_Windows_Debug_<PUB_INDEX>" /E /R:2 /W:2 /NFL /NDL
  ```

### Step 7 — Never auto-commit
Do NOT run git commit. Leave the release for the user to verify first (consistent project convention).

## Gotchas
- The Windows runner `xingli_music.exe` is a C++ shell; its mtime stays OLD across Dart-only bumps because only `flutter_assets` (which holds the Dart code incl. buildCount) recompiles. A stale exe mtime is EXPECTED and correct — clNN content is inside `flutter_assets`.
- `withOpacity` is deprecated project-wide → use `.withValues(alpha:)`.
- Release folder naming must match exactly: `星璃音乐_<semver>_alpha_cl<NN>_星尘初聚_Windows_Debug_<PUB>`.
- `app_version.dart` display getter pads month/day to 2 digits (`0.26.08.13`), but the release-folder / build.gradle / pubspec convention uses unpadded (`0.26.8.13`). The script derives the folder from `versionName` (authoritative, unpadded) — do not "fix" the padding mismatch.

## Resources
- `references/release-convention.md` — full version spec, folder naming, and verification checklist.
- `scripts/publish_windows_debug.py` — robocopy + verify helper (`python scripts/publish_windows_debug.py <PUB_INDEX> [--dry-run]`).
