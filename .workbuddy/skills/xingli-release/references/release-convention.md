# 星璃音乐 发版规范（release convention）

源：`lib/core/app_version.dart` 头部注释（用户 2026-08-09 定版）+ 历次 cl 发版实践。

## 版本串格式
```
0.26.8.13_alpha_cl29
 └┬─┘└┬┘└┬┘└┬┘ └┬┘ └┬┘
 大版本 年 月 日 阶段 构建次数
```
- 大版本：固定 `0`（早期）。
- 年/月/日：当日日期（`YY.MM.DD`）。展示用 `app_version.dart` 的 `display` getter；但 **release 文件夹 / build.gradle / pubspec 用「不补零」形式** `0.26.8.13`（month=8, day=13 不补零）。`display` getter 内部对 mm/dd 补零成 `0.26.08.13`——这是已知差异，不要改。
- 阶段：`alpha`=早期内测（当前）；另有 `beta`/`rc`/`release`。非 release 时展示串带 `_alpha` 后缀。
- `clNN`：当日构建次数，`01` 起；同日每次构建 +1，次日清零。

## 版本代号演进表
随阶段推进逐级升级（改 `codename` 一处即可）：
```
星尘初聚 → 星轨初现 → 星河流转 → 星光满照 → 星河静默 → 星尘余响
```
当前：`星尘初聚`。

## 三处同步（发版必查）
| 位置 | 字段 | cl28→cl29 示例 |
|---|---|---|
| `lib/core/app_version.dart` | `static const int buildCount` | `28` → `29` |
| `android/app/build.gradle` | `versionName` | `"0.26.8.13_alpha_cl28"` → `"0.26.8.13_alpha_cl29"` |
| `pubspec.yaml` | `version` | `0.26.8+13`（**按日，cl 不参与，不要动**）|

⚠️ `app_version.dart` 与 `build.gradle` 的 cl 必须一致；`pubspec.yaml` 的 cl 不参与。

## Release 文件夹命名
```
release/星璃音乐_<semver>_alpha_cl<NN>_<codename>_Windows_Debug_<PUB>
```
- `<semver>` = `0.26.8.13`（不补零，与 build.gradle versionName 一致）。
- `<codename>` = `星尘初聚`。
- `<PUB>` = 独立计数（无文件源），每次发布 +1：`cl28`→`_54`、`cl29`→`_55`。下个发版应是 `cl30`→`_56`。

## 构建与发布
1. `flutter analyze lib` → 目标 **0 error**（既有 info/warning 可忽略，全老代码风格）。
2. `flutter build windows --debug` → 等 `√ Built build\windows\x64\runner\Debug\xingli_music.exe`。
3. robocopy（见 SKILL.md Step 6）`build\windows\x64\runner\Debug` → release 文件夹。
4. 校验：`release/.../xingli_music.exe` 存在（约 1041408 B）+ `release/.../data/flutter_assets` 存在。

## 已知坑
- **exe mtime 偏旧是正常的**：Windows runner 是 C++ 壳，只有改 C++ 才重链；Dart 改动（含 buildCount）进 `flutter_assets`，exe 不动 → exe 时间戳不更新，但 clNN 内容确实在新构建里。robocopy 后 `data/` 目录时间戳应为发布时间。
- **`withOpacity` 弃用**：项目统一用 `Colors.black.withValues(alpha: 0.42)` 之类。
- **绝不自动 git commit**：发版后留给用户先验证（历史惯例，cl15–cl29 均未提交）。

## 验收清单（发版后用户/1050 自测）
- 设置 → 关于 显示 `..._cl<NN>` 正确递增。
- release 文件夹 exe 可启动、资源完整。
- 本次批次功能可用（如相机入场景、存档背景等）。
