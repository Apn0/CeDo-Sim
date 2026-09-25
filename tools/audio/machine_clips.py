#!/usr/bin/env python3
"""Bake the per-machine sound clips from the operator's recordings.

WHY THIS EXISTS
---------------
`assets/` is gitignored, so the baked WAVs under `assets/audio/machines/` are
local-only. What IS committed is this script plus `machine_sounds.json`, the
manifest that says, for every recording the operator dropped on his Desktop,
which seconds to take and what to make of them. Re-running the script from the
source recordings reproduces every clip deterministically.

The recordings' file names carried the cutting instructions (operator,
2026-09-25):

    5s+_<name>            take the audio from 5 s onwards ("skip the first
                          4.999999 seconds and start at 5.00")
    25s-35s_<name>        take 25 s .. 35 s
    loop_3x_1m11s-1m14s_  take 1:11 .. 1:14, play it three times in a row, and
                          LOOP that whole 3x sequence ("that entire sound of
                          the three, in a sequence, has to loop") — kind
                          "repeat" with "loop": true
    <name>_in_operation   the RUNNING sound only — no ramp-up, no ramp-down,
                          no start, no stop in the clip; ramps are generated at
                          runtime from it (MachineSound.gd)
    <name>_starter_idle_revving   several sounds in one file: split them
    <name>_loop_4x        four similar (not identical) takes of one action:
                          pick one for action 1 (opening), another for action 2
                          (closing)

The manifest is the machine-readable form of those instructions plus the
measured segment boundaries (see `notes` on every clip).

WHAT A LOOP GETS
----------------
1. The region the manifest names is decoded (ffmpeg → 44.1 kHz stereo float).
2. A loop of `loop_len_s` is cut from it, and the loop END is searched (±1 s)
   for the point whose last `xfade_s` best correlates with the loop's first
   `xfade_s` (band-limited to 2 kHz, so a motor hum lands in phase). The tail
   is then equal-power crossfaded INTO the head, exactly like
   `loopify_wavs.py`: the loop wraps between two samples that were adjacent in
   the recording, and the join is a `xfade_s` blend rather than a cut. That is
   what makes a constant-operation loop unnoticeable.
3. Level: loops are normalised to a common RMS (`rms_db`, default −20 dBFS)
   with a −1 dBFS peak ceiling, so the per-machine `gain_db` slider in the
   MachineSoundSpec .tres is the ONLY place relative loudness lives. One-shots
   are peak-normalised (`peak_db`).
4. A `smpl` chunk marks the loop so Godot's importer sets LOOP_FORWARD, and an
   `.import` sidecar with `compress/mode=0` keeps it 16-bit PCM (the IMA_ADPCM
   trap in tools/audio/README.md).

USAGE
-----
    python tools/audio/machine_clips.py --analyze        # envelopes only
    python tools/audio/machine_clips.py --check          # what would be cut
    python tools/audio/machine_clips.py                  # bake missing
    python tools/audio/machine_clips.py --force          # bake everything
    python tools/audio/machine_clips.py --only trilzeef_run
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy import signal

REPO = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).resolve().parent / "machine_sounds.json"

SAMPLE_RATE = 44100
CHANNELS = 2

IMPORT_SIDECAR = """[remap]

importer="wav"
type="AudioStreamWAV"

[deps]

source_file="res://{rel}"

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


# ── decoding ──────────────────────────────────────────────────────────────────
def ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    fallback = Path.home() / "AppData/Local/Microsoft/WinGet/Links/ffmpeg.exe"
    if fallback.exists():
        return str(fallback)
    sys.exit("ffmpeg not found on PATH")


_DECODE_CACHE: dict[Path, np.ndarray] = {}


def decode(path: Path) -> np.ndarray:
    """Whole file as float32 (N, 2) at SAMPLE_RATE. Cached per run."""
    if path in _DECODE_CACHE:
        return _DECODE_CACHE[path]
    raw = subprocess.run(  # nosec B603
        [ffmpeg(), "-v", "error", "-i", str(path), "-vn", "-ar", str(SAMPLE_RATE),
         "-ac", str(CHANNELS), "-f", "f32le", "-"],
        check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, CHANNELS).copy()
    _DECODE_CACHE[path] = x
    return x


def sl(x: np.ndarray, t0: float, t1: float) -> np.ndarray:
    a = max(0, int(round(t0 * SAMPLE_RATE)))
    b = min(x.shape[0], int(round(t1 * SAMPLE_RATE)))
    return x[a:b]


# ── measurement ───────────────────────────────────────────────────────────────
def rms_db(x: np.ndarray) -> float:
    if x.size == 0:
        return -120.0
    return 20.0 * math.log10(max(float(np.sqrt(np.mean(x ** 2))), 1e-9))


def peak_db(x: np.ndarray) -> float:
    if x.size == 0:
        return -120.0
    return 20.0 * math.log10(max(float(np.max(np.abs(x))), 1e-9))


def clip_fraction(x: np.ndarray, thr: float = 0.985) -> float:
    return float(np.mean(np.abs(x) >= thr)) if x.size else 0.0


# ── loop building ─────────────────────────────────────────────────────────────
def _lowpass_mono(x: np.ndarray, cutoff_hz: float = 2000.0) -> np.ndarray:
    m = x.mean(axis=1)
    b, a = signal.butter(4, cutoff_hz / (SAMPLE_RATE * 0.5))
    return signal.filtfilt(b, a, m).astype(np.float32)


def find_loop_end(region: np.ndarray, loop_len: int, xfade: int, search: int) -> tuple[int, float]:
    """Return (end_sample, correlation) for the loop end in
    [loop_len - search, loop_len + search] whose closing `xfade` window best
    matches the opening `xfade` window (normalised cross-correlation on the
    band-limited mono mix). The loop is region[0:end]."""
    lo = max(xfade + 1, loop_len - search)
    hi = min(region.shape[0], loop_len + search)
    if hi <= lo:
        return min(loop_len, region.shape[0]), 0.0
    m = _lowpass_mono(region)
    head = m[:xfade]
    head = (head - head.mean())
    hn = float(np.sqrt(np.sum(head ** 2))) + 1e-9
    # window candidates: tail window for end e is m[e - xfade : e]
    seg = m[lo - xfade:hi]
    corr = signal.correlate(seg, head, mode="valid")          # len = hi - lo + 1
    # local energy of each tail window for normalisation
    sq = np.concatenate([[0.0], np.cumsum(seg.astype(np.float64) ** 2)])
    energy = np.sqrt(np.maximum(sq[xfade:] - sq[:-xfade], 1e-12))[: corr.shape[0]]
    ncc = corr / (hn * energy)
    k = int(np.argmax(ncc))
    return lo + k, float(ncc[k])


def crossfade_loop(region: np.ndarray, end: int, xfade: int) -> np.ndarray:
    """loopify_wavs.py's construction: output = [head⊗tail crossfade][body].
    The output's last sample is region[end - xfade - 1] and its first sample is
    ≈ region[end - xfade]: adjacent in the recording, so the wrap is continuous."""
    x = region[:end]
    n = x.shape[0]
    out = np.empty((n - xfade, CHANNELS), dtype=np.float32)
    out[xfade:] = x[xfade:n - xfade]
    t = (np.arange(xfade) / xfade).astype(np.float32).reshape(-1, 1)
    fade_in = np.sin(t * np.pi / 2)      # weights the original head
    fade_out = np.cos(t * np.pi / 2)     # weights the original tail
    out[:xfade] = x[:xfade] * fade_in + x[n - xfade:] * fade_out
    return out


def edge_fades(x: np.ndarray, in_ms: float, out_ms: float) -> np.ndarray:
    x = x.copy()
    fi = int(SAMPLE_RATE * in_ms / 1000.0)
    fo = int(SAMPLE_RATE * out_ms / 1000.0)
    if fi > 1:
        x[:fi] *= np.linspace(0.0, 1.0, fi, dtype=np.float32).reshape(-1, 1)
    if fo > 1:
        x[-fo:] *= np.linspace(1.0, 0.0, fo, dtype=np.float32).reshape(-1, 1)
    return x


def join_repeat(seg: np.ndarray, times: int, xfade: int) -> np.ndarray:
    """Concatenate `seg` `times` times with a short equal-power blend at each
    join (the loop_3x instruction)."""
    if times <= 1 or xfade <= 0:
        return np.concatenate([seg] * max(times, 1))
    out = seg.copy()
    t = (np.arange(xfade) / xfade).astype(np.float32).reshape(-1, 1)
    fi, fo = np.sin(t * np.pi / 2), np.cos(t * np.pi / 2)
    for _ in range(times - 1):
        a = out[:-xfade]
        blend = out[-xfade:] * fo + seg[:xfade] * fi
        out = np.concatenate([a, blend, seg[xfade:]])
    return out


# ── level ─────────────────────────────────────────────────────────────────────
def normalise(x: np.ndarray, rms_target_db: float | None, peak_target_db: float | None,
              ceiling_db: float = -1.0) -> tuple[np.ndarray, str]:
    if rms_target_db is not None:
        g = 10 ** ((rms_target_db - rms_db(x)) / 20.0)
    elif peak_target_db is not None:
        g = 10 ** ((peak_target_db - peak_db(x)) / 20.0)
    else:
        g = 1.0
    y = x * g
    note = f"gain {20 * math.log10(g):+.1f} dB"
    p = peak_db(y)
    if p > ceiling_db:
        y *= 10 ** ((ceiling_db - p) / 20.0)
        note += f", then {ceiling_db - p:+.1f} dB to hold the {ceiling_db:.0f} dBFS ceiling"
    return y.astype(np.float32), note


# ── writing ───────────────────────────────────────────────────────────────────
def write_wav(path: Path, x: np.ndarray, loop: bool) -> None:
    s16 = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    n_frames = s16.shape[0]
    block_align = CHANNELS * 2
    fmt_chunk = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, CHANNELS, SAMPLE_RATE,
                            SAMPLE_RATE * block_align, block_align, 16)
    data_bytes = s16.tobytes()
    pad = b"\x00" if len(data_bytes) % 2 else b""
    data_chunk = struct.pack("<4sI", b"data", len(data_bytes)) + data_bytes + pad
    payload = b"WAVE" + fmt_chunk + data_chunk
    if loop:
        smpl = struct.pack("<IIIIIIIII", 0, 0, int(round(1e9 / SAMPLE_RATE)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<IIIIII", 0, 0, 0, n_frames - 1, 0, 0)
        payload += struct.pack("<4sI", b"smpl", len(smpl)) + smpl
    path.write_bytes(struct.pack("<4sI", b"RIFF", len(payload)) + payload)


def write_sidecar(wav: Path) -> None:
    rel = wav.relative_to(REPO).as_posix()
    (wav.parent / (wav.name + ".import")).write_text(IMPORT_SIDECAR.format(rel=rel), encoding="utf-8")


# ── the recipe kinds ──────────────────────────────────────────────────────────
def build_clip(entry: dict, src: np.ndarray) -> tuple[np.ndarray, bool, str]:
    kind = entry["kind"]
    if kind == "loop":
        t0, t1 = entry["region"]
        region = sl(src, t0, t1)
        xfade = int(SAMPLE_RATE * float(entry.get("xfade_s", 0.75)))
        search = int(SAMPLE_RATE * float(entry.get("search_s", 1.0)))
        want = int(SAMPLE_RATE * float(entry.get("loop_len_s", (t1 - t0))))
        want = min(want, region.shape[0])
        if want + search > region.shape[0]:
            search = max(0, region.shape[0] - want)
        end, ncc = find_loop_end(region, want, xfade, search)
        y = crossfade_loop(region, end, xfade)
        y, ln = normalise(y, entry.get("rms_db", -20.0), None)
        info = (f"loop {y.shape[0] / SAMPLE_RATE:.2f} s from {t0:.2f}+{end / SAMPLE_RATE:.3f} s, "
                f"xfade {xfade / SAMPLE_RATE:.2f} s, seam ncc {ncc:+.3f}, {ln}")
        return y, True, info
    if kind == "oneshot":
        t0, t1 = entry["range"]
        y = sl(src, t0, t1)
        fi, fo = entry.get("fade_ms", [3, 30])
        y = edge_fades(y, fi, fo)
        y, ln = normalise(y, None, entry.get("peak_db", -3.0))
        return y, False, f"one-shot {y.shape[0] / SAMPLE_RATE:.3f} s from {t0:.2f}..{t1:.2f} s, {ln}"
    if kind == "repeat":
        t0, t1 = entry["range"]
        seg = sl(src, t0, t1)
        times = int(entry.get("repeat", 3))
        jx = int(SAMPLE_RATE * float(entry.get("join_xfade_s", 0.03)))
        y = join_repeat(seg, times, jx)
        if bool(entry.get("loop", False)):
            # The whole N-times sequence LOOPS (the loop_3x instruction). Its
            # tail is blended into its head with the SAME xfade as the joins
            # inside it, so the wrap is one more join: N*(t1-t0) - N*join long,
            # no edge fades, RMS-normalised like every other loop.
            y = crossfade_loop(y, y.shape[0], jx)
            y, ln = normalise(y, entry.get("rms_db", -20.0), None)
            return y, True, (f"{times}x {t0:.2f}..{t1:.2f} s LOOP = {y.shape[0] / SAMPLE_RATE:.2f} s, "
                             f"joins {1000.0 * jx / SAMPLE_RATE:.0f} ms, {ln}")
        fi, fo = entry.get("fade_ms", [5, 60])
        y = edge_fades(y, fi, fo)
        y, ln = normalise(y, None, entry.get("peak_db", -3.0))
        return y, False, f"{times}x {t0:.2f}..{t1:.2f} s = {y.shape[0] / SAMPLE_RATE:.2f} s, {ln}"
    raise ValueError(f"unknown kind {kind!r}")


# ── analyze ───────────────────────────────────────────────────────────────────
def analyze(sources: dict[str, Path]) -> None:
    for name, path in sources.items():
        x = decode(path)
        dur = x.shape[0] / SAMPLE_RATE
        print(f"\n== {name}  {dur:.2f} s  rms {rms_db(x):.1f} dBFS  peak {peak_db(x):.1f} dBFS  "
              f"clipped {clip_fraction(x) * 100:.2f} %")
        hop = SAMPLE_RATE if dur > 30 else SAMPLE_RATE // 4
        step_s = hop / SAMPLE_RATE
        n = x.shape[0] // hop
        vals = [rms_db(x[i * hop:(i + 1) * hop]) for i in range(n)]
        clips = [clip_fraction(x[i * hop:(i + 1) * hop]) for i in range(n)]
        per = int(round(10 / step_s))
        for i in range(0, n, per):
            print(f"  t={i * step_s:6.1f}s  " + " ".join(f"{v:6.1f}" for v in vals[i:i + per]))
            if any(c > 0.001 for c in clips[i:i + per]):
                print(f"  clip%      " + " ".join(f"{c * 100:6.2f}" for c in clips[i:i + per]))


# ── main ──────────────────────────────────────────────────────────────────────
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", type=Path, default=MANIFEST)
    ap.add_argument("--check", action="store_true", help="report only, write nothing")
    ap.add_argument("--force", action="store_true", help="rebuild clips that already exist")
    ap.add_argument("--analyze", action="store_true", help="print envelopes of the sources and exit")
    ap.add_argument("--only", action="append", default=[], help="bake only these output names")
    args = ap.parse_args()

    man = json.loads(args.manifest.read_text(encoding="utf-8"))
    src_dir = REPO / man["source_dir"]
    out_dir = REPO / man["out_dir"]
    if args.analyze:
        seen: dict[str, Path] = {}
        for e in man["clips"]:
            seen.setdefault(e["source"], src_dir / e["source"])
        missing = [n for n, p in seen.items() if not p.exists()]
        if missing:
            print("MISSING SOURCES:", *missing, sep="\n  ")
        analyze({n: p for n, p in seen.items() if p.exists()})
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    made = kept = skipped = 0
    missing_src: set[str] = set()
    for e in man["clips"]:
        name = e["out"]
        if args.only and name not in args.only:
            continue
        src = src_dir / e["source"]
        dst = out_dir / f"{name}.wav"
        if not src.exists():
            missing_src.add(e["source"])
            skipped += 1
            continue
        if dst.exists() and not args.force and not args.only:
            kept += 1
            continue
        if args.check:
            print(f"  WOULD BAKE  {name}  <- {e['source']}  ({e['kind']})")
            made += 1
            continue
        y, loop, info = build_clip(e, decode(src))
        write_wav(dst, y, loop)
        write_sidecar(dst)
        print(f"  baked  {name:34s} {info}")
        made += 1
    print(f"\n  {made} baked, {kept} already present, {skipped} skipped, {len(man['clips'])} in manifest")
    if missing_src:
        print("\n  MISSING SOURCE RECORDINGS:")
        for s in sorted(missing_src):
            print(f"    {src_dir / s}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
