# 星璃音乐 · 项目资料索引

> 本文件汇总 `D:\Stellara\Music` 工作区的资料组织。由 AI 整理于 2026-08-26。

## 顶层目录
| 目录 | 用途 |
|------|------|
| `xingli_music/` | **主代码仓库**（Flutter App），独立 git 仓库，已提交并推送 `origin/feat/liquid-glass-lib` |
| `assets/` | 美术资源（约 9784 png + 少量 jar/ogg） |
| `audio_material/` | 音频素材（10 m4a） |
| `device_shots/` | 设备运行截图（6 png） |
| `docs/` | **项目文档资料库**（见下） |
| `generated-images/` | 程序生成图（3 png） |
| `minecraft_music/` | Minecraft 音乐素材（414 ogg + 3 json） |
| `ui_exploration/` | UI 探索原型：`xingli_music_prototype.html`（**可靠·离线·零依赖**高保真液态玻璃原型）、`my_music_space.html`（⚠ 依赖外网 Unsplash 图，离线破图）、`stellara_liquid_glass.html`（自包含碎片探索） |
| `vendor/` | 第三方依赖（1 js） |
| `_archive/` | **历史临时产物归档**（见下），非项目运行所需 |

## docs/ 文档库
| 文件 | 说明 |
|------|------|
| `weekly_report_2026-08-14.md` | 周报 |
| `星璃音乐 · 构建手册.md` | 构建/运行说明手册 |
| `designs/` | 独立设计稿：LOD 改进、首页重构、音乐可视化 2.5D、小空间剔除、体素世界反馈 |

## _archive/ 归档结构（历史调试/构建产物，确认无用后可整体删除）
- `logs/` — 81 个，已细分：
  - `build/`(41) — Flutter 编译/构建日志（`_build_*`/`build_*`/`_ps_build` 等）
  - `diag/`(40) — 运行/诊断日志（`_*.txt`/`app_log.txt`/`run_log.txt`/`_serve_tmp.log` 等）
- `scripts/` — 17 个，按语言分：
  - `ps1/` — Flutter 构建/运行/调试、Minecraft 音频提取、SDK 安装等 9 个
  - `py/` — 缓存/引擎检查、stamp 恢复、wbi 探测等 6 个
  - `dart/` — `_dart_write_test.dart`
  - `bat/` — `run_debug_gui.bat`
- `screenshots/` — 11 个 png：
  - `designs/` — Figma 导出设计稿 6 个（`design_3_*`）
  - `shots/` — 运行/界面截图 5 个
- `prototypes/` — 4 个 html 原型（`fireplace_demo` / `music_space_prototype` / `voxel_scene` / `analyze_fire`）
- `misc/` — 杂项：`figma_file.json`、`vswhere.json`、`_ui.xml`、`minecraft_music.7z`、4 个 `tmp_*.bin` 临时二进制

## 说明
- 外层 `D:\Stellara\Music` 是空 git 仓库（未跟踪任何文件），以上整理均为本地归拢，不进版本控制。
- 代码版本管理请见 `xingli_music/` 子仓库。
- `_archive/` 为一次性调试/构建残留，如确认不再需要回溯，可直接删除整个目录。
