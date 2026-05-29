---
name: video-edit
description: Reliably edit video files with ffmpeg and ffprobe: trim, join, transcode, resize, crop, speed-change, mix audio, add text/subtitles, make GIFs, and verify the result visually and with metadata.
---

# Video Edit Skill

Use this skill for practical video edits that can be done reliably with `ffmpeg`. The goal is not to memorize filters; the goal is to inspect the input, choose the least destructive operation, create a new output file, and verify that the edit is actually correct.

If `ffmpeg` or `ffprobe` is missing, tell the user what is missing and stop. Do not overwrite the original media unless the user explicitly asks.

## Reliable Workflow

1. Inspect the input with `ffprobe`.
2. Identify whether the edit can use stream copy or requires re-encoding.
3. Decide how audio should be handled: keep, remove, replace, mix, or retime.
4. Run the ffmpeg command into a new output file.
5. Verify metadata: duration, streams, codecs, resolution, frame rate.
6. Verify visually by extracting representative frames and inspecting them.
7. Fix objective defects and repeat up to 3 times.

Metadata proves the file parses. Visual frames prove the edit looks right. Use both.

## Inspect First

Probe before editing:

```bash
ffprobe -v error \
  -show_entries format=duration:stream=index,codec_type,codec_name,width,height,avg_frame_rate,pix_fmt,sample_rate,channels \
  -of json input.mp4
```

Get duration only:

```bash
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 input.mp4
```

Check:

- Duration and expected cut points.
- Video codec, resolution, frame rate, pixel format.
- Whether there is audio.
- Whether inputs for concat/transition have matching dimensions, frame rates, and audio shape.
- Whether the target platform needs MP4/H.264/AAC compatibility.

## Stream Copy Or Re-Encode

Prefer stream copy when it is correct:

- Container change only: usually stream copy.
- Fast rough trim at keyframes: stream copy.
- Concatenate already matching clips: stream copy.

Re-encode when the edit changes pixels, timing, or audio samples:

- Frame-accurate trim.
- Resize, crop, rotate, overlays, subtitles, watermark, picture-in-picture.
- Speed changes and slow motion.
- Compression or codec change.
- Normalizing clips before concat or transitions.
- Mixing, fading, replacing, or retiming audio.

Good distribution defaults for MP4:

```bash
-c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 192k
```

Use CRF 18 for near-lossless, 20-23 for normal delivery, 26-30 for aggressive compression.

In zsh, quote optional maps such as `-map '0:a?'` because `?` is a shell glob character.

## Visual QA

When locating an event, extract frames and inspect them with the available image/vision tool:

```bash
mkdir -p frames
ffmpeg -i input.mp4 -vf fps=1 -q:v 2 frames/frame_%04d.jpg
```

For sub-second timing, increase sampling:

```bash
ffmpeg -i input.mp4 -vf fps=5 -q:v 2 frames/frame_%04d.jpg
```

After editing, sample explicit timestamps across the output. Pick timestamps from the actual output duration: near start, before/after edits, middle, near end.

```bash
mkdir -p qa
ffmpeg -ss 00:00:01 -i output.mp4 -frames:v 1 -q:v 2 qa/start.jpg
ffmpeg -ss 00:00:10 -i output.mp4 -frames:v 1 -q:v 2 qa/check_10s.jpg
ffmpeg -ss 00:00:30 -i output.mp4 -frames:v 1 -q:v 2 qa/check_30s.jpg
```

Also listen to or inspect audio when the task changes audio. At minimum confirm stream presence, duration, and that the chosen audio mapping is intentional.

## Cuts

Fast keyframe trim, no re-encode. This may start/end a little off the requested frame:

```bash
ffmpeg -ss 00:01:30 -i input.mp4 -t 00:00:45 -map 0 -c copy -avoid_negative_ts make_zero output.mp4
```

Frame-accurate trim, re-encoded:

```bash
ffmpeg -i input.mp4 -ss 00:01:30 -t 00:00:45 \
  -map 0:v:0 -map '0:a?' \
  -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k -movflags +faststart output.mp4
```

Remove audio:

```bash
ffmpeg -i input.mp4 -map 0:v:0 -c:v copy -an output.mp4
```

Extract one frame:

```bash
ffmpeg -ss 00:00:30 -i input.mp4 -frames:v 1 -q:v 2 frame.jpg
```

## Join Clips

For clips with identical codec, resolution, frame rate, pixel format, and audio layout, use the concat demuxer:

```text
file '/absolute/path/clip1.mp4'
file '/absolute/path/clip2.mp4'
file '/absolute/path/clip3.mp4'
```

```bash
ffmpeg -f concat -safe 0 -i list.txt -c copy output.mp4
```

If clips differ, normalize each clip first, then concat:

```bash
ffmpeg -i clip1.mp4 \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,format=yuv420p" \
  -c:v libx264 -crf 20 -preset medium -c:a aac -ar 48000 -ac 2 norm1.mp4
```

Repeat for each input, then concatenate the normalized files with `-c copy`.

## Resize, Crop, Rotate

Resize to 720p while preserving aspect ratio and even dimensions:

```bash
ffmpeg -i input.mp4 -map 0:v:0 -map '0:a?' \
  -vf "scale=-2:720" \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k -movflags +faststart output.mp4
```

Crop:

```bash
ffmpeg -i input.mp4 -map 0:v:0 -map '0:a?' \
  -vf "crop=1280:720:0:0" \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k output.mp4
```

Rotate or flip:

```bash
ffmpeg -i input.mp4 -map 0:v:0 -map '0:a?' -vf "transpose=1" -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac output.mp4
ffmpeg -i input.mp4 -map 0:v:0 -map '0:a?' -vf "hflip" -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac output.mp4
```

`transpose=1` is 90 degrees clockwise; `transpose=2` is 90 degrees counterclockwise.

## Compress Or Convert

Compatible MP4:

```bash
ffmpeg -i input.mov -map 0:v:0 -map '0:a?' \
  -c:v libx264 -crf 22 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 160k -movflags +faststart output.mp4
```

Container change only, when codecs are already compatible:

```bash
ffmpeg -i input.mov -map 0 -c copy output.mp4
```

If stream copy fails or the result does not play where needed, re-encode.

## Speed Changes

Whole clip, 2x faster:

```bash
ffmpeg -i input.mp4 -filter_complex \
  "[0:v]setpts=0.5*PTS[v];[0:a]atempo=2.0[a]" \
  -map "[v]" -map "[a]" \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k output.mp4
```

Whole clip, half speed:

```bash
ffmpeg -i input.mp4 -filter_complex \
  "[0:v]setpts=2.0*PTS[v];[0:a]atempo=0.5[a]" \
  -map "[v]" -map "[a]" \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k output.mp4
```

If there is no audio, omit the audio filter and use `-an`. `atempo` only accepts 0.5 to 2.0 per filter; chain it for larger changes, such as `atempo=2.0,atempo=2.0` for 4x faster.

Selective slow motion requires trimming segments, resetting timestamps, retiming the selected segment, then concatenating. Always reset timestamps after every `trim` and `atrim`:

```bash
ffmpeg -i input.mp4 -filter_complex \
  "[0:v]trim=0:4,setpts=PTS-STARTPTS[v0]; \
   [0:v]trim=4:5,setpts=4.0*(PTS-STARTPTS)[v1]; \
   [0:v]trim=5:10,setpts=PTS-STARTPTS[v2]; \
   [v0][v1][v2]concat=n=3:v=1:a=0[v]; \
   [0:a]atrim=0:4,asetpts=PTS-STARTPTS[a0]; \
   [0:a]atrim=4:5,atempo=0.5,atempo=0.5,asetpts=PTS-STARTPTS[a1]; \
   [0:a]atrim=5:10,asetpts=PTS-STARTPTS[a2]; \
   [a0][a1][a2]concat=n=3:v=0:a=1[a]" \
  -map "[v]" -map "[a]" \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k output.mp4
```

For silent input, use only the video part and add `-an`.

Reverse short clips:

```bash
ffmpeg -i input.mp4 -vf reverse -af areverse -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac output.mp4
```

Reverse buffers media in memory. For silent input, remove `-af areverse` and add `-an`. For long clips, split first.

## Audio

Extract audio:

```bash
ffmpeg -i input.mp4 -vn -c:a copy output.m4a
ffmpeg -i input.mp4 -vn -c:a libmp3lame -b:a 192k output.mp3
```

Replace original audio:

```bash
ffmpeg -i video.mp4 -i new_audio.mp3 \
  -map 0:v:0 -map 1:a:0 \
  -c:v copy -c:a aac -b:a 192k -shortest output.mp4
```

Mix original audio with background music:

```bash
ffmpeg -i video.mp4 -i music.mp3 -filter_complex \
  "[0:a]volume=1.0[orig];[1:a]volume=0.25[music];[orig][music]amix=inputs=2:duration=first:dropout_transition=2[a]" \
  -map 0:v:0 -map "[a]" -c:v copy -c:a aac -b:a 192k output.mp4
```

Music under speech is usually 0.15 to 0.35 volume.

Fade music in and out before mixing:

```bash
ffmpeg -i video.mp4 -i music.mp3 -filter_complex \
  "[1:a]afade=t=in:st=0:d=2,afade=t=out:st=58:d=2,volume=0.25[music];[0:a][music]amix=inputs=2:duration=first[a]" \
  -map 0:v:0 -map "[a]" -c:v copy -c:a aac -b:a 192k output.mp4
```

Set the fade-out start to `duration - fade_length`.

Mute a segment:

```bash
ffmpeg -i input.mp4 -map 0:v:0 -map 0:a:0 \
  -c:v copy -af "volume=0:enable='between(t,10,15)'" \
  -c:a aac -b:a 192k output.mp4
```

## Text, Subtitles, Watermarks, Picture-In-Picture

Text overlay:

```bash
ffmpeg -i input.mp4 -filter_complex \
  "[0:v]drawtext=fontfile=/System/Library/Fonts/Supplemental/Arial.ttf:text='Hello world':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=h-100:box=1:boxcolor=black@0.5:boxborderw=10[v]" \
  -map "[v]" -map '0:a?' -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac output.mp4
```

Show only between 3 and 6 seconds by adding:

```text
:enable='between(t,3,6)'
```

Burn subtitles into pixels:

```bash
ffmpeg -i input.mp4 -map 0:v:0 -map '0:a?' \
  -vf "subtitles=subs.srt" \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k output.mp4
```

Add toggleable soft subtitles to MP4:

```bash
ffmpeg -i input.mp4 -i subs.srt -map 0 -map 1 -c copy -c:s mov_text output.mp4
```

Logo watermark:

```bash
ffmpeg -i input.mp4 -i logo.png -filter_complex \
  "[0:v][1:v]overlay=W-w-20:20[v]" \
  -map "[v]" -map '0:a?' \
  -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac output.mp4
```

Picture-in-picture:

```bash
ffmpeg -i screen.mp4 -i webcam.mp4 -filter_complex \
  "[1:v]scale=iw*0.25:-2[pip];[0:v][pip]overlay=W-w-20:H-h-20[v]" \
  -map "[v]" -map '0:a?' \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -c:a aac output.mp4
```

## Transitions

`xfade` requires matching resolution, frame rate, time base, and pixel format. Normalize first when in doubt.

Video and audio crossfade:

```bash
ffmpeg -i clip1.mp4 -i clip2.mp4 -filter_complex \
  "[0:v]fps=30,format=yuv420p[v0];[1:v]fps=30,format=yuv420p[v1]; \
   [v0][v1]xfade=transition=fade:duration=1:offset=4[v]; \
   [0:a][1:a]acrossfade=d=1[a]" \
  -map "[v]" -map "[a]" \
  -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p \
  -c:a aac -b:a 192k output.mp4
```

`offset` is usually `first_clip_duration - transition_duration`.

## GIFs

Use a two-pass palette:

```bash
ffmpeg -i input.mp4 -vf "fps=12,scale=480:-2:flags=lanczos,palettegen" -t 10 palette.png
ffmpeg -i input.mp4 -i palette.png -filter_complex "fps=12,scale=480:-2:flags=lanczos[x];[x][1:v]paletteuse" -t 10 output.gif
```

Keep GIFs short. For most sharing, MP4 is smaller and better.

## Common Failures

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Cut starts early/late | Stream-copy trim hit keyframes | Re-encode for frame accuracy |
| Output will not play on phone/web | Pixel format or codec incompatible | Use H.264/AAC and `-pix_fmt yuv420p` |
| Encoder says odd width/height | H.264 needs even dimensions | Use `scale=-2:720` or pad/crop to even dimensions |
| Audio disappears | Wrong `-map` options | Map audio intentionally, often `-map '0:a?'` |
| Audio out of sync after filters | Missing timestamp reset | Use `setpts=PTS-STARTPTS` and `asetpts=PTS-STARTPTS` after trims |
| Slow motion audio fails | `atempo` outside 0.5-2.0 | Chain multiple `atempo` filters |
| Concat fails or desyncs | Inputs do not match | Normalize codec, resolution, fps, pixel format, sample rate, channels |
| Transition fails | Clips differ in geometry/fps/audio | Normalize first; ensure both clips have the needed streams |
| Music overwhelms speech | Music volume too high | Use 0.15-0.35 for music under original audio |
| GIF looks bad | No palette pass | Use palettegen then paletteuse |
| `drawtext` cannot load font | Bad font path | Use a known system font path or omit `fontfile` if supported |
| Reverse runs out of memory | Reverse buffers frames | Split long clips before reversing |

## Stopping Criterion

Ship when metadata matches the requested edit and sampled frames/audio prove the visible result is correct: right duration, right content, no black/frozen sections, no unexpected crop, overlays/subtitles appear at the right time, audio is present or absent by design, and the output plays in the intended format.

For complex color grading, stabilization, denoising, chroma key, motion graphics, or multi-track editorial timelines, tell the user ffmpeg can attempt it but a real editor such as Final Cut, Premiere, or DaVinci Resolve is usually the better tool.
