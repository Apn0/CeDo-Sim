#!/usr/bin/env python3
"""
Slice the source video/audio file(s) referenced in audio_layout.json
into one clip per JSON entry, using ffmpeg.

Default: re-encodes to mono 44.1 kHz WAV — small, lossless, perfect for
loading into Godot's AudioStreamPlayer3D. Override with flags.

Example:
    python extract_segments.py \
        --manifest audio_layout.json \
        --source-dir . \
        --out audio_clips/

Source files are looked up by `source_file` in each entry; pass
--source-dir to point at the folder where those originals live.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys


def sanitize(name: str) -> str:
    """Filesystem-safe clip filename. Collapses anything that isn't
    alphanumeric / dash / underscore / dot into '_'."""
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
    return s.strip("._") or "clip"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--manifest", default="audio_layout.json",
                   help="Path to the audio_layout.json file (default: ./audio_layout.json)")
    p.add_argument("--source-dir", default=".",
                   help="Folder containing the source video/audio files (default: .)")
    p.add_argument("--out", default="audio_clips",
                   help="Output folder for per-segment clips (default: ./audio_clips)")
    p.add_argument("--format", default="wav", choices=["wav", "mp3", "ogg", "flac"],
                   help="Output container/codec (default: wav)")
    p.add_argument("--mono", action="store_true", default=True,
                   help="Mix down to mono (default: on; AudioStreamPlayer3D is positional, stereo wastes space)")
    p.add_argument("--stereo", dest="mono", action="store_false",
                   help="Keep stereo")
    p.add_argument("--sample-rate", type=int, default=44100,
                   help="Output sample rate in Hz (default: 44100)")
    p.add_argument("--dry-run", action="store_true",
                   help="Print the ffmpeg command for each entry but don't execute")
    p.add_argument("--overwrite", action="store_true",
                   help="Overwrite existing output files (default: skip if file already exists)")
    args = p.parse_args()

    if not shutil.which("ffmpeg"):
        print("ERROR: ffmpeg not found in PATH. Install it (e.g. winget install Gyan.FFmpeg) and reopen the shell.", file=sys.stderr)
        return 2

    if not os.path.exists(args.manifest):
        print(f"ERROR: manifest not found: {args.manifest}", file=sys.stderr)
        return 2

    with open(args.manifest, "r", encoding="utf-8") as f:
        entries = json.load(f)
    if not isinstance(entries, list):
        print("ERROR: manifest root is not a JSON array", file=sys.stderr)
        return 2

    os.makedirs(args.out, exist_ok=True)

    print(f"Manifest:    {args.manifest}  ({len(entries)} entries)")
    print(f"Source dir:  {os.path.abspath(args.source_dir)}")
    print(f"Output dir:  {os.path.abspath(args.out)}")
    print(f"Format:      {args.format} {'mono' if args.mono else 'stereo'} @ {args.sample_rate} Hz")
    print()

    sources_seen = set()
    ok = skipped = failed = 0
    for i, e in enumerate(entries):
        # Prefer the placer's pre-composed `filename_stem` (with machine + tag
        # suffixes); fall back to `clip_name` (back-compat with v2 exports).
        stem = e.get("filename_stem") or e.get("clip_name") or f"segment_{i:03d}"
        clip = stem
        src_name = e.get("source_file") or ""
        start = e.get("start_s")
        end = e.get("end_s")
        if not src_name or start is None or end is None:
            print(f"  SKIP   {clip}: missing source_file/start_s/end_s")
            skipped += 1
            continue
        src_path = os.path.join(args.source_dir, src_name)
        if not os.path.exists(src_path):
            print(f"  SKIP   {clip}: source not found at {src_path}")
            skipped += 1
            continue

        duration = float(end) - float(start)
        if duration <= 0.05:
            print(f"  SKIP   {clip}: duration too short ({duration:.3f}s)")
            skipped += 1
            continue

        if src_path not in sources_seen:
            sources_seen.add(src_path)
            print(f"\n  --- source: {src_path} ---")

        out_name = sanitize(clip) + "." + args.format
        out_path = os.path.join(args.out, out_name)
        if os.path.exists(out_path) and not args.overwrite and not args.dry_run:
            print(f"  EXISTS {clip} -> {out_name}  (use --overwrite to replace)")
            skipped += 1
            continue

        # -ss BEFORE -i for fast seek (uses container index, ~frame-accurate for our use).
        # Re-encode audio to ensure clean cut and uniform output codec/sample rate.
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-ss", f"{float(start):.3f}",
            "-t",  f"{duration:.3f}",
            "-i",  os.path.abspath(src_path),
            "-vn",  # discard video; audio only
            "-ac", "1" if args.mono else "2",
            "-ar", str(args.sample_rate),
        ]
        # Codec by container
        if args.format == "wav":
            cmd += ["-c:a", "pcm_s16le"]
        elif args.format == "mp3":
            cmd += ["-c:a", "libmp3lame", "-q:a", "2"]
        elif args.format == "ogg":
            cmd += ["-c:a", "libvorbis", "-q:a", "5"]
        elif args.format == "flac":
            cmd += ["-c:a", "flac"]
        cmd.append(os.path.abspath(out_path))

        if args.dry_run:
            print(f"  WOULD  {clip} -> {out_name}")
            print(f"           {' '.join(cmd)}")
            ok += 1
            continue

        try:
            r = subprocess.run(cmd, capture_output=True, text=True)
        except Exception as ex:
            print(f"  FAIL   {clip}: {ex}")
            failed += 1
            continue
        if r.returncode != 0:
            print(f"  FAIL   {clip}: ffmpeg exit {r.returncode}\n           {r.stderr.strip()[:240]}")
            failed += 1
            continue
        size_kb = os.path.getsize(out_path) // 1024 if os.path.exists(out_path) else 0
        print(f"  OK     {clip:40s} -> {out_name}  ({size_kb} KB, {duration:.1f}s)")
        ok += 1

    print(f"\nDone: {ok} extracted, {skipped} skipped, {failed} failed.")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
