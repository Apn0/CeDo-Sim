#!/usr/bin/env python3
"""
Post-process the extracted segment WAVs for use as ambient loops in Godot.

For each WAV:
  1. Apply a head-tail equal-power crossfade so the file loops with NO click,
     thump, or break in the noise. The output is shorter than the input by
     the fade duration: the first `fade` samples of the output blend the
     ORIGINAL head into the ORIGINAL tail, so when playback wraps from the
     last sample back to sample 0 the audio trajectory is continuous (the
     loop point ends up between two originally-adjacent samples).
  2. Normalise to 16-bit PCM stereo at a consistent sample rate (44.1 kHz
     default) — the cleanest format for Godot's AudioStreamPlayer3D.
  3. Embed a `smpl` chunk marking the whole file as a forward loop. Godot
     4's WAV importer reads this and auto-sets loop_mode = LOOP_FORWARD,
     so the imported AudioStreamWAV resource loops out-of-the-box.

Usage:
    python loopify_wavs.py --in audio_clips --out audio_clips_loop
    python loopify_wavs.py --in audio_clips --in-place   # overwrite originals
"""
import argparse
import glob
import os
import struct
import sys
from math import gcd

import numpy as np
from scipy.io import wavfile
from scipy import signal


def loopify(samples_f32: np.ndarray, sr: int, fade_ms: int = 100) -> np.ndarray:
    """Tail-to-head crossfade, producing an output of length N - fade.

    output[0]              ≈ original[N - fade]
    output[fade - 1]       ≈ original[fade - 1]
    output[fade : N-fade]  = original[fade : N-fade]   (body untouched)
    output[N-fade-1]       = original[N - fade - 1]
    → loop wraps from original[N-fade-1] back to original[N-fade]: ADJACENT samples.
    """
    if samples_f32.ndim == 1:
        samples_f32 = samples_f32[:, np.newaxis]
    N, C = samples_f32.shape
    fade = min(int(sr * fade_ms / 1000), N // 4)
    if fade < 16:
        # too short to do a meaningful crossfade — return unchanged
        return samples_f32

    out = np.empty((N - fade, C), dtype=np.float32)
    # Body
    out[fade:] = samples_f32[fade : N - fade]
    # Equal-power crossfade region at the start of the output
    t = (np.arange(fade) / fade).astype(np.float32)
    fade_in  = np.sin(t * np.pi / 2).reshape(-1, 1)   # 0 → 1, weights original HEAD
    fade_out = np.cos(t * np.pi / 2).reshape(-1, 1)   # 1 → 0, weights original TAIL
    head = samples_f32[:fade]
    tail = samples_f32[N - fade :]
    out[:fade] = head * fade_in + tail * fade_out
    return out


def resample_to(samples_f32: np.ndarray, sr_in: int, sr_out: int) -> np.ndarray:
    if sr_in == sr_out:
        return samples_f32
    g = gcd(sr_in, sr_out)
    return signal.resample_poly(samples_f32, sr_out // g, sr_in // g, axis=0).astype(np.float32)


def ensure_stereo(samples_f32: np.ndarray) -> np.ndarray:
    if samples_f32.ndim == 1:
        return np.stack([samples_f32, samples_f32], axis=1)
    c = samples_f32.shape[1]
    if c == 1: return np.repeat(samples_f32, 2, axis=1)
    if c == 2: return samples_f32
    return samples_f32[:, :2]


def to_float32(samples, dtype) -> np.ndarray:
    if dtype == np.int16:   return samples.astype(np.float32) / 32768.0
    if dtype == np.int32:   return samples.astype(np.float32) / 2147483648.0
    if dtype == np.uint8:   return (samples.astype(np.float32) - 128.0) / 128.0
    if dtype in (np.float32, np.float64): return samples.astype(np.float32)
    raise ValueError(f"Unsupported WAV dtype: {dtype}")


def write_wav_with_smpl_loop(path: str, samples_int16: np.ndarray, sr: int, channels: int) -> None:
    """Write a 16-bit PCM WAV with a 'smpl' chunk marking the whole file
    as a forward loop. Godot 4's importer reads smpl and sets loop_mode
    accordingly without manual intervention in the Inspector."""
    n_frames = samples_int16.shape[0]
    block_align = channels * 2
    byte_rate = sr * block_align
    data_bytes = samples_int16.tobytes()
    data_size = len(data_bytes)

    fmt_chunk = struct.pack('<4sIHHIIHH',
        b'fmt ', 16,        # chunk id + size
        1,                  # PCM
        channels,
        sr,
        byte_rate,
        block_align,
        16,                 # bits per sample
    )

    pad = b'\x00' if data_size % 2 == 1 else b''
    data_chunk = struct.pack('<4sI', b'data', data_size) + data_bytes + pad

    # smpl chunk: 36-byte header + 24-byte loop record = 60-byte payload.
    smpl_payload = struct.pack('<IIIIIIIII',
        0,                          # manufacturer
        0,                          # product
        int(round(1e9 / sr)),       # sample_period (ns)
        60,                         # MIDI unity note (C4)
        0,                          # MIDI pitch fraction
        0,                          # SMPTE format
        0,                          # SMPTE offset
        1,                          # num sample loops
        0,                          # sampler-specific data size
    )
    loop_record = struct.pack('<IIIIII',
        0,                          # cue point ID
        0,                          # loop type (0 = forward)
        0,                          # start sample
        n_frames - 1,               # end sample (inclusive)
        0,                          # fraction
        0,                          # play count (0 = infinite)
    )
    smpl_data = smpl_payload + loop_record
    smpl_chunk = struct.pack('<4sI', b'smpl', len(smpl_data)) + smpl_data

    payload = b'WAVE' + fmt_chunk + data_chunk + smpl_chunk
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sI', b'RIFF', len(payload)))
        f.write(payload)


def process_file(in_path: str, out_path: str, target_sr: int, fade_ms: int) -> dict:
    sr, samples = wavfile.read(in_path)
    dtype = samples.dtype
    f = to_float32(samples, dtype)
    if f.ndim == 1:
        f = f[:, np.newaxis]
    in_dur = f.shape[0] / sr

    if sr != target_sr:
        f = resample_to(f, sr, target_sr)
        sr = target_sr
    f = loopify(f, sr, fade_ms=fade_ms)
    f = ensure_stereo(f)
    f = np.clip(f, -1.0, 1.0)
    s16 = (f * 32767.0).astype(np.int16)
    write_wav_with_smpl_loop(out_path, s16, sr, 2)

    out_dur = f.shape[0] / sr
    return {"in_dur": in_dur, "out_dur": out_dur, "sr": sr}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--in',  dest='in_dir',  default='audio_clips',
                   help='Input folder of WAVs (default: ./audio_clips)')
    p.add_argument('--out', dest='out_dir', default='audio_clips_loop',
                   help='Output folder (default: ./audio_clips_loop)')
    p.add_argument('--in-place', action='store_true',
                   help='Overwrite input files in --in instead of writing --out')
    p.add_argument('--fade-ms', type=int, default=100,
                   help='Crossfade duration in milliseconds (default: 100)')
    p.add_argument('--sample-rate', type=int, default=44100,
                   help='Output sample rate in Hz (default: 44100)')
    args = p.parse_args()

    if not os.path.isdir(args.in_dir):
        print(f'ERROR: not a directory: {args.in_dir}', file=sys.stderr); return 2
    wavs = sorted(glob.glob(os.path.join(args.in_dir, '*.wav')))
    if not wavs:
        print(f'ERROR: no .wav files in {args.in_dir}', file=sys.stderr); return 2

    out_dir = args.in_dir if args.in_place else args.out_dir
    if not args.in_place:
        os.makedirs(out_dir, exist_ok=True)

    print(f'Loopify {len(wavs)} files: {args.in_dir} -> {out_dir}')
    print(f'  Crossfade: {args.fade_ms} ms (equal-power, output shortened by this much)')
    print(f'  Format:    16-bit PCM stereo @ {args.sample_rate} Hz, smpl loop marker')
    print()
    ok = failed = 0
    for w in wavs:
        name = os.path.basename(w)
        out = os.path.join(out_dir, name)
        try:
            r = process_file(w, out, target_sr=args.sample_rate, fade_ms=args.fade_ms)
            sz = os.path.getsize(out) // 1024
            print(f'  OK   {name:42s}  {r["in_dur"]:5.1f}s -> {r["out_dur"]:5.1f}s  ({sz} KB)')
            ok += 1
        except Exception as e:
            print(f'  FAIL {name}: {e}')
            failed += 1
    print(f'\nDone: {ok} ok, {failed} failed.')
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
