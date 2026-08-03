# Audio toolchain

The positional plant audio is produced by a two-repo chain. `assets/` is
gitignored, so **everything needed to rebuild the clips lives here**, committed.

```
plant walkthrough video
   └─ placer/index.html        operator splits it at silence gaps and clicks each
      (browser app)            segment onto a PDOK aerial map → audio_layout.json
                               (WGS84 lat/lon + RD New EPSG:28992 rd_x/rd_y)
   └─ extract_clips.py         cuts one WAV per layout entry, loopifies, installs
      + loopify_wavs.py        into assets/audio/clips/ with PCM .import sidecars
   └─ src/autoload/PlantAudio  reads audio_layout.json, spawns one
                               AudioStreamPlayer3D per entry at its RD position
```

`audio_layout.json` here is the **master copy**. `assets/audio/audio_layout.json`
is a runtime duplicate that `extract_clips.py` refreshes; it is gitignored and
must never be hand-edited.

## Rebuild

```bash
python tools/audio/extract_clips.py --check                      # report only
python tools/audio/extract_clips.py --sources <folder with the source mp4s>
```

Source recordings are operator video and are not in the repo. As of 2026-08-03
they live in `C:\Users\arnod\Desktop\tmp\` (`VID-20250912-WA0010.mp4`,
`VID-20250912-WA0011.mp4`).

## Traps

**`loopify_wavs.py` is not idempotent.** It applies a 100 ms equal-power
head-to-tail crossfade, so each pass makes the file 100 ms *shorter*. Running it
over a folder of already-loopified clips silently destroys them — measured
2026-08-03, 42 of the 43 operator clips each lost exactly 17,640 bytes
(= 0.1 s of stereo 16-bit 44.1 kHz) that way. `extract_clips.py` now cuts into a
staging dir and hands loopify only the files it cut in that run. Never point it
at `assets/audio/clips/`.

**Godot 4.6 imports WAVs as IMA_ADPCM by default** (`compress/mode=2`).
`PlantAudio.gd:162` does byte-level PCM editing for its loop crossfade and bails
on anything that is not 16-bit PCM, so an ADPCM clip loses its crossfade and
clicks. `extract_clips.py` writes a `compress/mode=0` sidecar for every clip it
creates. Hand-added clips will come in as mode=2 — all five added on 2026-08-03
did — so set it and reimport.

**Every clip is 16-bit PCM stereo @ 44.1 kHz with exactly one `smpl` chunk.**
Anything else will not mix correctly with the rest.

## Two extractors — which one to use

Use **`extract_clips.py`** in this repo. `placer/extract_segments.py` is the
upstream original and is vendored for reference only. They differ:

| | `extract_segments.py` (upstream) | `extract_clips.py` (this repo) |
|---|---|---|
| output | mono by default | stereo, matching the shipped clips |
| loopify | separate manual step | wired in, staged, non-destructive |
| `.import` sidecar | none | written with `compress/mode=0` |
| layout copy | none | syncs master → runtime |
| naming | `filename_stem` w/ machine+tag suffixes | `clip_name` |

Reproducibility is verified, not assumed: deleting an operator clip and
regenerating it through `extract_clips.py` reproduces it **byte-for-byte**
(checked 2026-08-03 on `VID-20250912-WA0011_110.9s`, md5 `9b8f46f1…`, and
`VID-20250912-WA0011_122.5s`, md5 `6cabc748…`, with zero collateral change to
the other 47 clips).

## `placer/` — the mapper

Vendored copy of `C:\Users\arnod\Documents\cedo-audio-placer`. **That repo has no
git remote**, so this is its only backup. Open `placer/index.html` in a browser;
no install. `machines.json` mirrors `PlaceableCatalog` and drives the per-clip
machine checklist.

The operator has **not** used that checklist: all 46 layout entries have empty
`notes` and no `machines`/`tags`/`filename_stem` keys at all (that export predates
them). So no clip is tied to a machine — the audio is placed geographically only.
Labelling is the obvious next improvement and needs an operator pass, not a guess.

## Layout provenance

43 entries were placed by the operator on the map. Three
(`VID-20250912-WA0011_241.7s / _247.83s / _253.96s`) were added 2026-08-03 to
fill the one remaining unmined gap in WA0011 (241.70–260.10 s); their positions
are **interpolated** along the walkthrough path between the operator's own 234.6 s
and 260.1 s placements, which each entry's `notes` field says explicitly. Confirm
them in the placer before treating them as ground truth.

Two further clips exist on disk but are deliberately **not** in the layout:
`VID-20250912-WA0010_0.0s` and `_5.6s`. WA0010 is a different recording with no
placed anchor, so there is no defensible way to derive coordinates for it —
inventing them would break the project's "no build without docs" rule. They need
an operator pass in the placer. Because they are not in the layout,
`extract_clips.py` does not manage them; rebuild them by hand with the same
`ffmpeg -acodec pcm_s16le -ar 44100 -ac 2` cut followed by a single loopify pass.
