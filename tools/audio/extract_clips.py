#!/usr/bin/env python3
"""Regenerate every positional plant clip from the operator's source recordings.

WHY THIS EXISTS
---------------
`assets/` is gitignored (`.gitignore:2`). The 48 baked WAVs and the runtime copy
of the layout are therefore local-only and do NOT survive a fresh clone. The
audio design's answer to that is "generator scripts under tools/ are the
committed source of truth; baked assets are derived artifacts" — but no such
script existed, so the audio work was one disk failure from being unrecoverable.

This script is that committed source of truth. Given the source recordings, it
reproduces every clip byte-for-byte from `audio_layout.json` (the master copy
lives HERE, next to this script, because the runtime copy under `assets/` is
gitignored).

USAGE
-----
    python tools/audio/extract_clips.py --check      # report only, touch nothing
    python tools/audio/extract_clips.py              # regenerate missing clips
    python tools/audio/extract_clips.py --force      # regenerate all

Source recordings are NOT in the repo either (49 MB of operator video). Point at
them with --sources; the default is the operator's Desktop staging folder.

THE IMA_ADPCM TRAP
------------------
Godot 4.6 imports WAVs as `compress/mode=2` (IMA_ADPCM) by DEFAULT. PlantAudio's
loop crossfade does byte-level PCM editing and bails on anything that is not
16-bit PCM (`PlantAudio.gd:162`), so an ADPCM clip silently loses its crossfade
and clicks at the loop point. This script writes a `.import` sidecar with
`compress/mode=0` for every clip it creates. If you ever add a clip by hand,
set that field yourself and reimport — measured 2026-08-03, all five hand-added
clips came in as mode=2 until forced.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MASTER_LAYOUT = Path(__file__).resolve().parent / "audio_layout.json"
RUNTIME_LAYOUT = REPO / "assets" / "audio" / "audio_layout.json"
CLIPS_DIR = REPO / "assets" / "audio" / "clips"
DEFAULT_SOURCES = Path.home() / "Desktop" / "tmp"

# Format the existing 43 clips use; new clips must match or they will not mix.
SAMPLE_RATE = 44100
CHANNELS = 2
CODEC = "pcm_s16le"

IMPORT_SIDECAR = """[remap]

importer="wav"
type="AudioStreamWAV"

[deps]

source_file="res://assets/audio/clips/{name}.wav"

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
"""


def ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    fallback = Path.home() / "AppData/Local/Microsoft/WinGet/Links/ffmpeg.exe"
    if fallback.exists():
        return str(fallback)
    sys.exit("ffmpeg not found on PATH — install it or add it to PATH")


def load_layout() -> list[dict]:
    path = MASTER_LAYOUT if MASTER_LAYOUT.exists() else RUNTIME_LAYOUT
    if not path.exists():
        sys.exit(f"no layout found at {MASTER_LAYOUT} or {RUNTIME_LAYOUT}")
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sources", type=Path, default=DEFAULT_SOURCES,
                    help=f"folder holding the source recordings (default {DEFAULT_SOURCES})")
    ap.add_argument("--check", action="store_true", help="report only, write nothing")
    ap.add_argument("--force", action="store_true", help="regenerate clips that already exist")
    args = ap.parse_args()

    layout = load_layout()
    CLIPS_DIR.mkdir(parents=True, exist_ok=True)

    missing_src: set[str] = set()
    cut_names: list[str] = []
    made = kept = 0

    # Cuts are staged OUTSIDE CLIPS_DIR. loopify_wavs.py takes a folder and
    # rewrites every WAV in it, and it is NOT idempotent — a second pass strips
    # another fade_ms off an already-faded clip. Pointing it at CLIPS_DIR
    # therefore corrupts every clip that was already there (measured 2026-08-03:
    # 42 of 43 operator clips silently lost exactly 17,640 bytes = 100 ms of
    # stereo 16-bit 44.1 kHz audio). Staging makes that structurally impossible:
    # only the files this run actually cut are ever handed to loopify.
    stage = CLIPS_DIR.parent / "_stage"
    if not args.check:
        if stage.exists():
            shutil.rmtree(stage)
        stage.mkdir(parents=True)

    for entry in layout:
        if not re.match(r"^[A-Za-z0-9_.-]+$", entry["clip_name"]):
            sys.exit(f"Invalid clip_name: {entry['clip_name']}")
        if not re.match(r"^[A-Za-z0-9_.-]+$", entry["source_file"]):
            sys.exit(f"Invalid source_file: {entry['source_file']}")

        name = entry["clip_name"]
        src = args.sources / entry["source_file"]
        dst = CLIPS_DIR / f"{name}.wav"

        if not src.exists():
            missing_src.add(entry["source_file"])
            continue
        if dst.exists() and not args.force:
            kept += 1
            continue
        if args.check:
            print(f"  WOULD CUT  {name}")
            made += 1
            continue

        start = float(entry["start_s"])
        dur = float(entry["end_s"]) - start
        subprocess.run(  # nosec B603
            [ffmpeg(), "-v", "error", "-y", "-ss", str(start), "-t", f"{dur:.3f}",
             "-i", str(src), "-vn", "-acodec", CODEC,
             "-ar", str(SAMPLE_RATE), "-ac", str(CHANNELS), str(stage / f"{name}.wav")],
            check=True,
        )
        made += 1
        cut_names.append(name)
        print(f"  cut  {name}")

    # Step 2 — loopify the staged cuts only. A raw ffmpeg cut clicks at the loop
    # point; every one of the operator's 43 original clips carries a 100 ms
    # equal-power head-tail crossfade and a `smpl` chunk from loopify_wavs.py.
    # Skipping this is why a naive re-cut is NOT byte-identical to the originals
    # (measured 2026-08-03: 17,640 bytes / 0.1 s longer, and no smpl chunk).
    # PlantAudio's runtime crossfade is only 10 ms, so it does not substitute.
    # With this step wired in, regenerating an operator clip reproduces it
    # byte-for-byte — verified on VID-20250912-WA0011_110.9s, md5 9b8f46f1.
    if not args.check:
        if cut_names:
            loopify = Path(__file__).resolve().parent / "loopify_wavs.py"
            if loopify.exists():
                subprocess.run([sys.executable, str(loopify),  # nosec B603
                                "--in", str(stage), "--in-place"], check=True)
            else:
                sys.exit(f"{loopify.name} missing — refusing to install un-looped "
                         f"clips that would click at the loop point")
            for name in cut_names:
                shutil.move(str(stage / f"{name}.wav"), str(CLIPS_DIR / f"{name}.wav"))
                # Force PCM so PlantAudio's crossfade applies — see IMA_ADPCM above.
                (CLIPS_DIR / f"{name}.wav.import").write_text(
                    IMPORT_SIDECAR.format(name=name), encoding="utf-8")
        shutil.rmtree(stage, ignore_errors=True)

    if not args.check and MASTER_LAYOUT.exists():
        RUNTIME_LAYOUT.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MASTER_LAYOUT, RUNTIME_LAYOUT)

    print(f"\n  {made} cut, {kept} already present, {len(layout)} in layout")
    if missing_src:
        print("\n  MISSING SOURCE RECORDINGS (clips from these were skipped):")
        for s in sorted(missing_src):
            print(f"    {s}")
        print(f"  Put them in {args.sources} or pass --sources.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
