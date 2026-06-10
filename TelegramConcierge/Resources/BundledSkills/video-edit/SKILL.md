---
name: video-edit
description: "Reliably edit video files with ffmpeg and ffprobe: trim, join, transcode, resize, crop, speed-change, mix audio, add text/subtitles, make GIFs, and verify the result visually and with metadata."
---

# Video Edit Skill

Use this skill for practical video edits that can be done reliably with `ffmpeg`. The goal is not to memorize filters; the goal is to inspect the input, choose the least destructive operation, create a new output file, and verify that the edit is actually correct.

If `ffmpeg` or `ffprobe` is missing, tell the user what is missing and stop. Do not overwrite the original media unless the user explicitly asks.

`${CLAUDE_SKILL_DIR}/recipes.md` contains the full command cookbook (cuts, joins, resize/crop/rotate, compression, speed changes, audio work, text/subtitles/watermarks, transitions, GIFs) plus a symptom→fix table. Read it when you need a concrete command shape; do not paste it wholesale into your reasoning.

## Reliable Workflow

1. Inspect the input: `python3 ${CLAUDE_SKILL_DIR}/probe_video.py input.mp4` (JSON summary of duration, streams, codecs, dimensions, frame rate, audio).
2. Decide stream copy vs re-encode (below).
3. Decide how audio should be handled: keep, remove, replace, mix, or retime.
4. Run the ffmpeg command into a new output file.
5. Verify metadata by probing the output.
6. Verify visually: `python3 ${CLAUDE_SKILL_DIR}/probe_video.py output.mp4 --frames 6 --out-dir qa` extracts frames spread across the duration — inspect them. Sample extra frames around edit points.
7. Fix objective defects and repeat up to 3 times.

Metadata proves the file parses. Visual frames prove the edit looks right. Use both. When the task changes audio, also confirm stream presence, duration, and that the chosen audio mapping is intentional.

## Stream Copy Or Re-Encode

Prefer stream copy (`-c copy`) when it is correct: container change only, fast rough trim at keyframes, concatenating already-matching clips.

Re-encode when the edit changes pixels, timing, or audio samples: frame-accurate trim, resize/crop/rotate/overlay/subtitles, speed changes, compression or codec change, normalizing clips before concat or transitions, mixing/fading/replacing audio.

Good distribution defaults for MP4:

```bash
-c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 192k
```

CRF 18 near-lossless, 20-23 normal delivery, 26-30 aggressive compression.

## Sharp Edges

These cause most real failures — they apply regardless of which recipe you use:

- In zsh, quote optional maps such as `-map '0:a?'` — `?` is a glob character.
- `atempo` only accepts 0.5–2.0 per filter; chain it for larger changes (`atempo=2.0,atempo=2.0` for 4x).
- After every `trim`/`atrim`, reset timestamps with `setpts=PTS-STARTPTS` / `asetpts=PTS-STARTPTS`, or audio desyncs.
- H.264 needs even dimensions: use `scale=-2:720` or pad/crop to even sizes.
- Phone/web compatibility needs `-pix_fmt yuv420p` with H.264/AAC.
- Concat and `xfade` require inputs matching in codec, resolution, fps, pixel format, and audio shape — normalize first when in doubt.
- Stream-copy trims land on keyframes: starts/ends can be slightly off. Re-encode for frame accuracy.
- GIFs need the two-pass palette (`palettegen` → `paletteuse`) or they look terrible.
- `reverse` buffers the whole clip in memory — split long clips first.
- Music under speech is usually 0.15–0.35 volume.

## Stopping Criterion

Ship when metadata matches the requested edit and sampled frames/audio prove the visible result is correct: right duration, right content, no black/frozen sections, no unexpected crop, overlays/subtitles appear at the right time, audio is present or absent by design, and the output plays in the intended format.

For complex color grading, stabilization, denoising, chroma key, motion graphics, or multi-track editorial timelines, tell the user ffmpeg can attempt it but a real editor such as Final Cut, Premiere, or DaVinci Resolve is usually the better tool.
