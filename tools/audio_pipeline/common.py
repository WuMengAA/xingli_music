"""星璃音乐 · 音频素材管线 —— 共享工具模块。

职责：
  1. 定位 ffmpeg / ffprobe（PATH → winget 安装目录 → 环境变量 FFMPEG_DIR）
  2. 统一日志（控制台 + logs/*.log）
  3. 统一的 --dry-run 命令执行封装
"""

from __future__ import annotations

import glob
import json
import logging
import os
import shutil
import subprocess
import sys

# Windows 控制台默认可能是 cp936，素材文件名含全角括号，统一切到 utf-8 避免乱码/报错
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except Exception:
        pass

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))          # xingli_music/
MATERIAL_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "..", "audio_material"))
BUILD_DIR = os.path.join(HERE, "build")
SEGMENT_DIR = os.path.join(BUILD_DIR, "segments")                       # 中间 WAV
LOG_DIR = os.path.join(HERE, "logs")
ASSET_DIR = os.path.join(PROJECT_ROOT, "assets", "audio")               # 最终产物
INSPECT_JSON = os.path.join(BUILD_DIR, "inspect.json")
SEGMENT_JSON = os.path.join(BUILD_DIR, "segments.json")

# winget (Gyan.FFmpeg) 的典型落地路径
_WINGET_GLOB = os.path.join(
    os.environ.get("LOCALAPPDATA", ""),
    "Microsoft", "WinGet", "Packages", "Gyan.FFmpeg*", "**", "bin",
)

_TOOL_CACHE: dict[str, str] = {}


def find_tool(name: str) -> str:
    """返回 ffmpeg / ffprobe 的可执行文件绝对路径。"""
    if name in _TOOL_CACHE:
        return _TOOL_CACHE[name]

    exe = name + (".exe" if os.name == "nt" else "")
    candidates: list[str] = []

    override = os.environ.get("FFMPEG_DIR")
    if override:
        candidates.append(os.path.join(override, exe))

    found = shutil.which(name)
    if found:
        candidates.append(found)

    if os.environ.get("LOCALAPPDATA"):
        candidates.extend(
            os.path.join(d, exe) for d in glob.glob(_WINGET_GLOB, recursive=True)
        )

    for path in candidates:
        if path and os.path.isfile(path):
            _TOOL_CACHE[name] = path
            return path

    raise RuntimeError(
        f"找不到 {name}。请安装 ffmpeg（winget install Gyan.FFmpeg），"
        f"或设置环境变量 FFMPEG_DIR 指向其 bin 目录。"
    )


def setup_logger(script_name: str) -> logging.Logger:
    os.makedirs(LOG_DIR, exist_ok=True)
    logger = logging.getLogger(script_name)
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", "%H:%M:%S")

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(fmt)
    logger.addHandler(console)

    file_handler = logging.FileHandler(
        os.path.join(LOG_DIR, f"{script_name}.log"), mode="w", encoding="utf-8"
    )
    file_handler.setFormatter(fmt)
    logger.addHandler(file_handler)
    return logger


def quote(arg: str) -> str:
    return f'"{arg}"' if (" " in arg or "［" in arg) else arg


def run_cmd(cmd: list[str], *, dry_run: bool, logger: logging.Logger,
            capture: bool = False) -> str | None:
    """执行命令；dry_run 时只打印。capture=True 返回 stdout。"""
    printable = " ".join(quote(c) for c in cmd)
    if dry_run:
        logger.info("[dry-run] %s", printable)
        return None

    logger.debug("exec: %s", printable)
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        logger.error("命令失败 (exit=%s): %s", proc.returncode, printable)
        logger.error("stderr 尾部:\n%s", (proc.stderr or "")[-1500:])
        raise RuntimeError(f"命令执行失败: {printable}")
    return proc.stdout if capture else None


def ffprobe_json(path: str) -> dict:
    """用 ffprobe 读取媒体信息（format + streams）。"""
    cmd = [
        find_tool("ffprobe"), "-v", "error",
        "-print_format", "json",
        "-show_format", "-show_streams",
        path,
    ]
    proc = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    if proc.returncode != 0:
        raise RuntimeError(f"ffprobe 失败: {path}\n{proc.stderr[-800:]}")
    return json.loads(proc.stdout)


def load_json(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def dump_json(path: str, data) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)


def human_size(num_bytes: int) -> str:
    value = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return f"{value:.1f}{unit}"
        value /= 1024
    return f"{value:.1f}GB"
