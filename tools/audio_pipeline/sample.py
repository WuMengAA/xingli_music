"""从长素材中裁剪「可无缝循环」的片段，输出中间 WAV 到 build/segments/。

无缝循环原理（acrossfade 自环）：
    设起点 START、目标时长 D、交叉淡化 XF
      Part1 = src[START+XF, START+XF+D]   长度 D
      Part2 = src[START,    START+XF]     长度 XF
      out   = acrossfade(Part1, Part2, d=XF)   长度 D
    输出的结尾正好淡入到 src[START+XF]，而输出的开头也是 src[START+XF]，
    因此首尾波形连续，循环播放时听不到接缝。

用法：
    python sample.py --dry-run     # 只打印 ffmpeg 命令
    python sample.py               # 实际裁剪
    python sample.py --only rain   # 只处理 id 含 rain 的片段
"""

from __future__ import annotations

import argparse
import os

import common

# ---------------------------------------------------------------------------
# 裁剪计划
#   at       : 起点占源文件总时长的比例（0~1），与源时长解耦，避免写死秒数
#   dur      : 目标片段时长（秒）
#   xf       : 交叉淡化时长（秒）；0 表示不做自环（一次性音效）
#   channels : 场景音景保留立体声；空间音效用单声道（3D 声像需要 mono 源）
#   norm     : lufs = 按响度归一（环境音）；peak = 按峰值归一（短音效）
# ---------------------------------------------------------------------------
PLAN: list[dict] = [
    # ── 鸟叫合集：多采样，做成一次性点缀音效（不循环、单声道） ──────────────
    {"id": "birds_chirp_a", "src": "［短多采样］鸟叫合集.m4a", "at": 0.10, "dur": 6,
     "xf": 0, "loop": False, "channels": 1, "bitrate": "64k", "norm": "peak",
     "tags": ["鸟叫"], "usage": "鸟叫点缀",
     "scene": "森林/清晨场景的随机点缀，可随机延时触发；单声道便于做 3D 声像"},
    {"id": "birds_chirp_b", "src": "［短多采样］鸟叫合集.m4a", "at": 0.40, "dur": 6,
     "xf": 0, "loop": False, "channels": 1, "bitrate": "64k", "norm": "peak",
     "tags": ["鸟叫"], "usage": "鸟叫点缀",
     "scene": "同上，用于与 a 交替避免重复感"},
    {"id": "birds_chirp_c", "src": "［短多采样］鸟叫合集.m4a", "at": 0.70, "dur": 6,
     "xf": 0, "loop": False, "channels": 1, "bitrate": "64k", "norm": "peak",
     "tags": ["鸟叫"], "usage": "鸟叫点缀",
     "scene": "同上，三个样本轮换基本听不出循环"},

    # ── 雨声 ────────────────────────────────────────────────────────────────
    {"id": "rain_432hz_a", "src": "［长］432Hz雨声.m4a", "at": 0.30, "dur": 25,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["雨声"], "usage": "场景音景",
     "scene": "「雨天/专注」场景主音景，助眠与白噪音模式首选"},
    {"id": "rain_432hz_b", "src": "［长］432Hz雨声.m4a", "at": 0.62, "dur": 25,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["雨声"], "usage": "场景音景",
     "scene": "雨势稍有差异的备选段，长时间播放时可与 a 交替"},

    # ── 夏天环境音 ──────────────────────────────────────────────────────────
    {"id": "summer_ambience_a", "src": "［长］夏天环境音.m4a", "at": 0.32, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["环境"], "usage": "场景音景",
     "scene": "「夏日/午后」场景底噪，蝉鸣草地感，适合做基础层叠加其它音效"},
    {"id": "summer_ambience_b", "src": "［长］夏天环境音.m4a", "at": 0.68, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["环境"], "usage": "场景音景",
     "scene": "同上备选段"},

    # ── 树叶窸窣 ────────────────────────────────────────────────────────────
    {"id": "leaves_rustle_a", "src": "［长］树叶窸窸窣窣.m4a", "at": 0.28, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["树叶"], "usage": "场景音景",
     "scene": "「森林」场景中层音景，配合鸟叫点缀使用效果最好"},
    {"id": "leaves_rustle_b", "src": "［长］树叶窸窸窣窣.m4a", "at": 0.66, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["树叶"], "usage": "场景音景",
     "scene": "风势略强的备选段"},

    # ── 海滩 ────────────────────────────────────────────────────────────────
    {"id": "beach_waves_a", "src": "［长］海滩.m4a", "at": 0.18, "dur": 20,
     "xf": 2.5, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["海滩"], "usage": "场景音景",
     "scene": "「海边」场景主音景；浪涌周期较长，用 2.5s 交叉淡化更自然"},
    {"id": "beach_waves_b", "src": "［长］海滩.m4a", "at": 0.55, "dur": 20,
     "xf": 2.5, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["海滩"], "usage": "场景音景",
     "scene": "同上备选段"},

    # ── 通用环境音 ──────────────────────────────────────────────────────────
    {"id": "ambience_soft_a", "src": "［长］环境音.m4a", "at": 0.25, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["环境"], "usage": "场景音景",
     "scene": "中性底噪，适合做「专注/阅读」场景或其它音景的垫底层"},
    {"id": "ambience_soft_b", "src": "［长］环境音.m4a", "at": 0.62, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["环境"], "usage": "场景音景",
     "scene": "同上备选段"},

    # ── 田野风铃 ────────────────────────────────────────────────────────────
    {"id": "wind_chimes_a", "src": "［长］田野风铃.m4a", "at": 0.28, "dur": 15,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["风铃"], "usage": "场景音景",
     "scene": "「田野/庭院」场景，铃声有旋律性，建议音量压低当点缀层"},
    {"id": "wind_chimes_b", "src": "［长］田野风铃.m4a", "at": 0.64, "dur": 15,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["风铃"], "usage": "场景音景",
     "scene": "同上备选段"},

    # ── 竹林窸窣、风声 ──────────────────────────────────────────────────────
    {"id": "bamboo_wind_a", "src": "［长］竹林窸窣、风声.m4a", "at": 0.30, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["树叶", "环境"], "usage": "场景音景",
     "scene": "「竹林/禅意」场景主音景，源码率最高（322kbps），细节最好"},
    {"id": "bamboo_wind_b", "src": "［长］竹林窸窣、风声.m4a", "at": 0.66, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["树叶", "环境"], "usage": "场景音景",
     "scene": "风声更明显的备选段"},

    # ── 篝火 ────────────────────────────────────────────────────────────────
    {"id": "campfire_a", "src": "［长］篝火燃烧.m4a", "at": 0.25, "dur": 15,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["篝火"], "usage": "场景音景",
     "scene": "「营地/夜晚」场景主音景；噼啪声密集，采样级精确切点保证无缝"},
    {"id": "campfire_b", "src": "［长］篝火燃烧.m4a", "at": 0.60, "dur": 15,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["篝火"], "usage": "场景音景",
     "scene": "同上备选段，也可当 Minecraft 风格火把/营火的空间音效"},

    # ── 雨林 + 鸟叫 ─────────────────────────────────────────────────────────
    {"id": "rainforest_birds_a", "src": "［长］雨林、鸟叫.m4a", "at": 0.26, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["雨林", "鸟叫"], "usage": "场景音景",
     "scene": "「雨林」场景一体式音景，自带鸟叫，单独用就够丰富"},
    {"id": "rainforest_birds_b", "src": "［长］雨林、鸟叫.m4a", "at": 0.62, "dur": 20,
     "xf": 2.0, "loop": True, "channels": 2, "bitrate": "96k", "norm": "lufs",
     "tags": ["雨林", "鸟叫"], "usage": "场景音景",
     "scene": "同上备选段"},
]

SAMPLE_RATE = 48000


def build_cmd(entry: dict, src_path: str, start: float, out_path: str) -> list[str]:
    ffmpeg = common.find_tool("ffmpeg")
    dur = float(entry["dur"])
    xf = float(entry["xf"])
    channels = int(entry["channels"])

    cmd = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y"]

    if xf > 0:
        # 自环交叉淡化。
        # 只做一次 -ss 粗定位并解码一整段，Part1/Part2 都用 atrim 在**解码后的样本**上切，
        # 保证 out[0] 与 out[-1] 落在源文件的同一个采样点上 —— 这是无缝的关键。
        # （早期版本用两路 -ss 分别定位，AAC 的帧级寻道误差会让两路错开若干样本，
        #   在篝火这类瞬态密集的素材上就会听到接缝爆音。）
        cmd += ["-ss", f"{start:.3f}", "-t", f"{dur + xf + 0.5:.3f}", "-i", src_path]
        cmd += [
            "-filter_complex",
            (
                f"[0:a]asplit=2[m][h];"
                f"[m]atrim=start={xf}:end={xf + dur},asetpts=N/SR/TB[p1];"
                f"[h]atrim=start=0:end={xf},asetpts=N/SR/TB[p2];"
                f"[p1][p2]acrossfade=d={xf}:c1=tri:c2=tri[a]"
            ),
            "-map", "[a]",
        ]
    else:
        # 一次性音效：只做极短进出淡化，消除切点爆音
        fade_out_start = max(0.0, dur - 0.05)
        cmd += ["-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", src_path]
        cmd += [
            "-af",
            f"afade=t=in:st=0:d=0.03,afade=t=out:st={fade_out_start:.3f}:d=0.05",
        ]

    cmd += [
        "-vn",                       # 丢弃可能内嵌的封面图
        "-ar", str(SAMPLE_RATE),
        "-ac", str(channels),
        "-c:a", "pcm_s16le",
        out_path,
    ]
    return cmd


def main() -> int:
    parser = argparse.ArgumentParser(description="裁剪可循环音频片段")
    parser.add_argument("--inspect", default=common.INSPECT_JSON,
                        help="inspect.py 产出的 JSON")
    parser.add_argument("--out-dir", default=common.SEGMENT_DIR, help="片段输出目录")
    parser.add_argument("--only", default=None, help="只处理 id 包含该子串的片段")
    parser.add_argument("--dry-run", action="store_true", help="只打印命令，不执行")
    args = parser.parse_args()

    logger = common.setup_logger("sample")

    if not os.path.isfile(args.inspect):
        logger.error("缺少 %s，请先运行 inspect.py", args.inspect)
        return 1

    inspected = common.load_json(args.inspect)
    by_name = {i["file"]: i for i in inspected["items"]}

    if not args.dry_run:
        os.makedirs(args.out_dir, exist_ok=True)

    entries = [e for e in PLAN if not args.only or args.only in e["id"]]
    logger.info("计划裁剪 %d 个片段 → %s", len(entries), args.out_dir)

    segments: list[dict] = []
    for entry in entries:
        info = by_name.get(entry["src"])
        if info is None:
            logger.error("源文件未探测到，跳过: %s", entry["src"])
            continue

        total = float(info["duration_sec"])
        dur = float(entry["dur"])
        xf = float(entry["xf"])
        need = dur + xf

        if total < need + 1:
            logger.error("源太短（%.1fs < %.1fs），跳过 %s", total, need, entry["id"])
            continue

        # 按比例定位起点，并确保 [start, start+dur+xf] 落在文件内（留 0.5s 余量）
        start = total * float(entry["at"])
        start = max(0.0, min(start, total - need - 0.5))

        out_path = os.path.join(args.out_dir, entry["id"] + ".wav")
        cmd = build_cmd(entry, info["path"], start, out_path)

        logger.info(
            "%-20s ← %-24s @%7.1fs  时长%5.1fs  xf%.1fs  %dch  %s",
            entry["id"], entry["src"], start, dur, xf,
            entry["channels"], "loop" if entry["loop"] else "one-shot",
        )
        common.run_cmd(cmd, dry_run=args.dry_run, logger=logger)

        segments.append({
            **{k: entry[k] for k in
               ("id", "src", "dur", "xf", "loop", "channels",
                "bitrate", "norm", "tags", "usage", "scene")},
            "start_sec": round(start, 3),
            "wav": out_path,
        })

    if args.dry_run:
        logger.info("[dry-run] 结束，未生成文件，未写入 %s", common.SEGMENT_JSON)
        return 0

    common.dump_json(common.SEGMENT_JSON, {"count": len(segments), "items": segments})
    total_wav = sum(os.path.getsize(s["wav"]) for s in segments)
    logger.info(
        "完成：%d 个 WAV 片段，中间文件合计 %s（不进 assets）",
        len(segments), common.human_size(total_wav),
    )
    logger.info("清单已写入 %s", common.SEGMENT_JSON)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
