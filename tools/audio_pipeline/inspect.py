"""批量探测 audio_material/ 下的音频素材，输出 JSON 清单。

用法：
    python inspect.py                 # 探测并写入 build/inspect.json
    python inspect.py --dry-run       # 只打印将要执行的 ffprobe 命令
    python inspect.py --dir <路径>    # 指定素材目录
"""

from __future__ import annotations

import os
import sys

# 本脚本名为 inspect.py，会遮蔽标准库的 inspect 模块。
# 把脚本目录从 sys.path 首位挪到末尾，保证 stdlib 优先，同时仍可 import common。
_HERE = os.path.dirname(os.path.abspath(__file__))
if sys.path and os.path.abspath(sys.path[0] or ".") == _HERE:
    sys.path.pop(0)
    sys.path.append(_HERE)

import argparse  # noqa: E402

import common  # noqa: E402

AUDIO_EXTS = {".m4a", ".mp3", ".wav", ".flac", ".ogg", ".opus", ".aac"}


def probe_one(path: str, *, dry_run: bool, logger) -> dict | None:
    if dry_run:
        logger.info(
            "[dry-run] %s -v error -print_format json -show_format -show_streams %s",
            common.quote(common.find_tool("ffprobe")), common.quote(path),
        )
        return None

    info = common.ffprobe_json(path)
    fmt = info.get("format", {})
    audio = next(
        (s for s in info.get("streams", []) if s.get("codec_type") == "audio"), {}
    )

    duration = float(fmt.get("duration") or audio.get("duration") or 0.0)
    size = int(fmt.get("size") or os.path.getsize(path))
    bit_rate = int(fmt.get("bit_rate") or audio.get("bit_rate") or 0)

    return {
        "file": os.path.basename(path),
        "path": path,
        "size_bytes": size,
        "size_human": common.human_size(size),
        "duration_sec": round(duration, 3),
        "duration_human": f"{int(duration // 60)}m{int(duration % 60):02d}s",
        "codec": audio.get("codec_name"),
        "sample_rate": int(audio.get("sample_rate") or 0),
        "channels": int(audio.get("channels") or 0),
        "channel_layout": audio.get("channel_layout"),
        "bit_rate_bps": bit_rate,
        "bit_rate_kbps": round(bit_rate / 1000) if bit_rate else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="批量探测音频素材信息")
    parser.add_argument("--dir", default=common.MATERIAL_DIR, help="素材目录")
    parser.add_argument("--out", default=common.INSPECT_JSON, help="输出 JSON 路径")
    parser.add_argument("--dry-run", action="store_true", help="只打印命令，不执行")
    args = parser.parse_args()

    logger = common.setup_logger("inspect")
    logger.info("素材目录: %s", args.dir)

    if not os.path.isdir(args.dir):
        logger.error("目录不存在: %s", args.dir)
        return 1

    files = sorted(
        os.path.join(args.dir, n)
        for n in os.listdir(args.dir)
        if os.path.splitext(n)[1].lower() in AUDIO_EXTS
    )
    logger.info("发现 %d 个音频文件", len(files))

    results: list[dict] = []
    for path in files:
        try:
            item = probe_one(path, dry_run=args.dry_run, logger=logger)
        except Exception as exc:  # 单个文件失败不影响整体
            logger.error("探测失败 %s: %s", os.path.basename(path), exc)
            continue
        if item is None:
            continue
        results.append(item)
        logger.info(
            "%-28s %8s | %7s | %s %dHz %dch | %skbps",
            item["file"], item["size_human"], item["duration_human"],
            item["codec"], item["sample_rate"], item["channels"],
            item["bit_rate_kbps"],
        )

    if args.dry_run:
        logger.info("[dry-run] 结束，未写入 %s", args.out)
        return 0

    total_bytes = sum(i["size_bytes"] for i in results)
    total_sec = sum(i["duration_sec"] for i in results)
    payload = {
        "source_dir": args.dir,
        "count": len(results),
        "total_size_bytes": total_bytes,
        "total_size_human": common.human_size(total_bytes),
        "total_duration_sec": round(total_sec, 1),
        "items": results,
    }
    common.dump_json(args.out, payload)
    logger.info(
        "已写入 %s（%d 个文件，合计 %s / %.1f 分钟）",
        args.out, len(results), common.human_size(total_bytes), total_sec / 60,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
