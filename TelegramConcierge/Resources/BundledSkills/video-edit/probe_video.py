#!/usr/bin/env python3
"""Probe a video file and optionally extract QA frames.

Prints a compact JSON summary (duration, container, streams with codec,
dimensions, frame rate, pixel format, audio shape). With --frames N it also
extracts N frames spread evenly across the duration for visual inspection.

Usage:
  python3 probe_video.py input.mp4
  python3 probe_video.py output.mp4 --frames 6 --out-dir qa
  python3 probe_video.py output.mp4 --frames 3 --at 4.5 --at 12 --out-dir qa
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Optional


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe a video and extract QA frames.")
    parser.add_argument("video", type=Path, help="Input video path")
    parser.add_argument("--frames", type=int, default=0, help="Extract N frames spread across the duration")
    parser.add_argument("--at", type=float, action="append", default=[], help="Extract a frame at this timestamp (seconds); repeatable")
    parser.add_argument("--out-dir", type=Path, default=Path("video_qa"), help="Output directory for frames")
    return parser.parse_args()


def probe(path: Path) -> dict:
    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries",
        "format=duration,size,format_name:"
        "stream=index,codec_type,codec_name,width,height,avg_frame_rate,pix_fmt,sample_rate,channels",
        "-of", "json", str(path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"error: ffprobe failed: {result.stderr.strip()}", file=sys.stderr)
        raise SystemExit(1)
    return json.loads(result.stdout)


def summarize(raw: dict) -> dict:
    fmt = raw.get("format", {})
    summary: dict = {
        "container": fmt.get("format_name"),
        "duration_s": round(float(fmt["duration"]), 3) if fmt.get("duration") else None,
        "size_bytes": int(fmt["size"]) if fmt.get("size") else None,
        "streams": [],
    }
    for stream in raw.get("streams", []):
        entry: dict = {
            "index": stream.get("index"),
            "type": stream.get("codec_type"),
            "codec": stream.get("codec_name"),
        }
        if stream.get("codec_type") == "video":
            entry.update(
                width=stream.get("width"),
                height=stream.get("height"),
                fps=stream.get("avg_frame_rate"),
                pix_fmt=stream.get("pix_fmt"),
            )
        elif stream.get("codec_type") == "audio":
            entry.update(
                sample_rate=stream.get("sample_rate"),
                channels=stream.get("channels"),
            )
        summary["streams"].append(entry)
    summary["has_audio"] = any(s["type"] == "audio" for s in summary["streams"])
    return summary


def spread_timestamps(duration: float, count: int) -> List[float]:
    if count <= 0:
        return []
    if count == 1:
        return [duration / 2]
    # Stay slightly inside the file bounds to avoid empty first/last frames.
    start, end = 0.1, max(duration - 0.2, 0.1)
    step = (end - start) / (count - 1)
    return [round(start + i * step, 2) for i in range(count)]


def extract_frame(path: Path, ts: float, out_dir: Path) -> Optional[Path]:
    out = out_dir / f"frame_{ts:08.2f}s.jpg"
    cmd = [
        "ffmpeg", "-y", "-v", "error",
        "-ss", f"{ts:.2f}", "-i", str(path),
        "-frames:v", "1", "-q:v", "2", str(out),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not out.exists():
        print(f"warning: failed to extract frame at {ts}s: {result.stderr.strip()}", file=sys.stderr)
        return None
    return out


def main() -> int:
    args = parse_args()
    video = args.video.expanduser().resolve()
    if not video.exists():
        print(f"error: file not found: {video}", file=sys.stderr)
        return 2
    for tool in ("ffprobe", "ffmpeg"):
        if shutil.which(tool) is None:
            print(f"error: {tool} not found on PATH", file=sys.stderr)
            return 1

    summary = summarize(probe(video))

    timestamps = list(args.at)
    duration = summary.get("duration_s")
    if args.frames > 0:
        if duration is None:
            print("error: cannot spread frames, duration unknown; use --at", file=sys.stderr)
            return 1
        timestamps.extend(spread_timestamps(duration, args.frames))

    if timestamps:
        out_dir = args.out_dir.expanduser().resolve()
        out_dir.mkdir(parents=True, exist_ok=True)
        frames = []
        for ts in sorted(set(timestamps)):
            frame = extract_frame(video, ts, out_dir)
            if frame is not None:
                frames.append(str(frame))
        summary["qa_frames"] = frames

    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
