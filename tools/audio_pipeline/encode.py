"""把 build/segments/ 下的 WAV 片段转码为低码率 AAC(.m4a)，并生成 manifest.json。

关于响度归一：
    刻意不使用 loudnorm/dynaudnorm 的「动态」滤镜——它们会随时间改变增益，
    可能破坏片段首尾的电平连续性，导致循环时出现「一跳」。
    这里先测量（loudnorm 分析 / volumedetect），再套用一个**静态**增益，
    既统一了响度，又完全不影响无缝循环。

用法：
    python encode.py --dry-run
    python encode.py
    python encode.py --bitrate 64k --no-normalize
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess

import common

SAMPLE_RATE = 48000
TARGET_LUFS = -20.0      # 环境音景目标整体响度（背景层，偏轻）
TARGET_PEAK_DB = -3.0    # 一次性音效目标峰值
TRUE_PEAK_CEIL = -1.0    # 真峰上限，防止转码后削顶
GAIN_LIMIT = 24.0        # 静态增益上下限；原始环境音普遍在 -34~-39 LUFS，
                         # 需要约 +19dB 才能拉到目标，上限放宽但仍有真峰保护兜底


def _ffmpeg_stderr(cmd: list[str]) -> str:
    proc = subprocess.run(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    return proc.stderr or ""


def measure_lufs(path: str) -> tuple[float, float] | None:
    """返回 (整体响度 LUFS, 真峰 dBTP)。"""
    cmd = [
        common.find_tool("ffmpeg"), "-hide_banner", "-nostats", "-i", path,
        "-af", f"loudnorm=I={TARGET_LUFS}:TP={TRUE_PEAK_CEIL}:print_format=json",
        "-f", "null", "-",
    ]
    stderr = _ffmpeg_stderr(cmd)
    match = re.search(r"\{[^{}]*input_i[^{}]*\}", stderr, re.S)
    if not match:
        return None
    try:
        data = json.loads(match.group(0))
        return float(data["input_i"]), float(data["input_tp"])
    except (ValueError, KeyError):
        return None


def measure_peak(path: str) -> float | None:
    """返回最大峰值 dBFS。"""
    cmd = [
        common.find_tool("ffmpeg"), "-hide_banner", "-nostats", "-i", path,
        "-af", "volumedetect", "-f", "null", "-",
    ]
    match = re.search(r"max_volume:\s*(-?\d+(?:\.\d+)?) dB", _ffmpeg_stderr(cmd))
    return float(match.group(1)) if match else None


def compute_gain(seg: dict, logger) -> float:
    """计算 loop-safe 的静态增益（dB）。"""
    wav = seg["wav"]
    if seg.get("norm") == "peak":
        peak = measure_peak(wav)
        if peak is None:
            logger.warning("%s 峰值测量失败，增益按 0dB", seg["id"])
            return 0.0
        gain = TARGET_PEAK_DB - peak
    else:
        measured = measure_lufs(wav)
        if measured is None:
            logger.warning("%s 响度测量失败，增益按 0dB", seg["id"])
            return 0.0
        loudness, true_peak = measured
        gain = TARGET_LUFS - loudness
        # 真峰保护：增益后不得超过 TRUE_PEAK_CEIL
        if true_peak + gain > TRUE_PEAK_CEIL:
            gain = TRUE_PEAK_CEIL - true_peak

    return round(max(-GAIN_LIMIT, min(GAIN_LIMIT, gain)), 2)


def build_cmd(seg: dict, gain_db: float, bitrate: str, out_path: str) -> list[str]:
    cmd = [
        common.find_tool("ffmpeg"), "-hide_banner", "-loglevel", "error", "-y",
        "-i", seg["wav"],
    ]
    if abs(gain_db) > 0.05:
        cmd += ["-af", f"volume={gain_db}dB"]
    cmd += [
        "-c:a", "aac", "-profile:a", "aac_low",
        "-b:a", bitrate,
        "-ar", str(SAMPLE_RATE),
        "-ac", str(seg["channels"]),
        "-movflags", "+faststart",
        "-vn",
        out_path,
    ]
    return cmd


def main() -> int:
    parser = argparse.ArgumentParser(description="转码音频片段并生成 manifest")
    parser.add_argument("--segments", default=common.SEGMENT_JSON,
                        help="sample.py 产出的片段清单")
    parser.add_argument("--out-dir", default=common.ASSET_DIR, help="素材输出目录")
    parser.add_argument("--bitrate", default=None,
                        help="统一覆盖码率，如 64k；默认用计划里的每段设置")
    parser.add_argument("--no-normalize", action="store_true", help="跳过响度归一")
    parser.add_argument("--only", default=None, help="只处理 id 包含该子串的片段")
    parser.add_argument("--dry-run", action="store_true", help="只打印命令，不执行")
    args = parser.parse_args()

    logger = common.setup_logger("encode")

    if not os.path.isfile(args.segments):
        logger.error("缺少 %s，请先运行 sample.py", args.segments)
        return 1

    segments = common.load_json(args.segments)["items"]
    segments = [s for s in segments if not args.only or args.only in s["id"]]

    if not args.dry_run:
        os.makedirs(args.out_dir, exist_ok=True)

    logger.info("准备转码 %d 个片段 → %s", len(segments), args.out_dir)

    manifest_items: list[dict] = []
    for seg in segments:
        bitrate = args.bitrate or seg["bitrate"]
        out_name = seg["id"] + ".m4a"
        out_path = os.path.join(args.out_dir, out_name)

        if args.dry_run:
            gain = 0.0
        elif args.no_normalize:
            gain = 0.0
        else:
            if not os.path.isfile(seg["wav"]):
                logger.error("中间 WAV 缺失，跳过 %s", seg["id"])
                continue
            gain = compute_gain(seg, logger)

        cmd = build_cmd(seg, gain, bitrate, out_path)
        common.run_cmd(cmd, dry_run=args.dry_run, logger=logger)

        if args.dry_run:
            continue

        size = os.path.getsize(out_path)

        # 实测成品响度：真峰保护会让部分瞬态多的素材达不到目标响度，
        # 把实测值写进 manifest，App 可据此做每素材音量微调（见 README）。
        measured = None if args.no_normalize else measure_lufs(out_path)
        out_lufs = round(measured[0], 2) if measured else None
        out_tp = round(measured[1], 2) if measured else None

        logger.info(
            "%-20s %-6s %dch  增益%+6.2fdB  实测%s LUFS  → %8s",
            seg["id"], bitrate, seg["channels"], gain,
            f"{out_lufs:7.2f}" if out_lufs is not None else "    n/a",
            common.human_size(size),
        )

        manifest_items.append({
            "id": seg["id"],
            "file": out_name,
            "source": seg["src"],
            "source_offset_sec": seg["start_sec"],
            "duration_sec": round(float(seg["dur"]), 2),
            "tags": seg["tags"],
            "usage": seg["usage"],
            "loop": bool(seg["loop"]),
            "channels": seg["channels"],
            "sample_rate": SAMPLE_RATE,
            "codec": "aac_low",
            "bitrate": bitrate,
            "crossfade_sec": seg["xf"],
            "gain_applied_db": gain,
            "output_lufs": out_lufs,
            "output_true_peak_db": out_tp,
            "size_bytes": size,
            "size_human": common.human_size(size),
            "scene": seg["scene"],
        })

    if args.dry_run:
        logger.info("[dry-run] 结束，未生成文件，未写入 manifest")
        return 0

    total = sum(i["size_bytes"] for i in manifest_items)
    manifest_path = os.path.join(args.out_dir, "manifest.json")
    common.dump_json(manifest_path, {
        "generated_by": "tools/audio_pipeline (inspect.py → sample.py → encode.py)",
        "loudness_target_lufs": TARGET_LUFS,
        "true_peak_ceiling_db": TRUE_PEAK_CEIL,
        "count": len(manifest_items),
        "total_size_bytes": total,
        "total_size_human": common.human_size(total),
        "total_duration_sec": round(sum(i["duration_sec"] for i in manifest_items), 1),
        "items": manifest_items,
    })

    logger.info("-" * 64)
    logger.info("产出 %d 个素材，合计 %s", len(manifest_items), common.human_size(total))
    logger.info("清单已写入 %s", manifest_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
