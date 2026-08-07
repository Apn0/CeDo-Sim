# Audio / sound engine — state of play (2026-08-03)

Written because a follow-up session could not find any record of this work.
Everything below is measured, not assumed; where a number appears, it was
produced by a command in that session.

## The two audio systems

| System | File | What it is |
|---|---|---|
| Procedural synth | `src/autoload/AudioManager.gd` | Autoload. **No audio files.** Five `AudioStreamGenerator` voices filled sample-by-sample with `push_frame()`: ambient (50 Hz Dutch mains drone), engine (throttle-driven), machine (extruder hum, state-driven), alarm (two-tone klaxon / fault pulse), radio (walkie squelch + band-limited carrier hiss). This is the house style for any new procedural audio. |
| Positional recordings | `src/scenes/world/PlantAudio.gd` | 43 `AudioStreamPlayer3D` of the real plant, placed from `assets/audio/audio_layout.json`, looped, 30 m `max_distance`. |

Buses (`default_bus_layout.tres`): Master, Machines, Voices, Ambient (−6 dB),
UI (−3 dB).

## Coordinate frame for the 43 clips — VERIFIED, do not "fix" it

```
anchor  = CeDo_building.obj AABB centre = (184112.50, −329382.27)
local_x = rd_x − 184112.50
local_z = 329382.27 − rd_y          # RD north increases toward world −Z
```

- Anchor cross-checked three ways: the mesh AABB, the saved
  `satellite_center_rd` (184112.5 / 329382.25 — agrees to 0.02 m), and
  back-converting `factory_center`, which lands within 4 m of the surveyed
  `src/data/plant/site_georeference.json` anchor.
- All 43 `rd_x`/`rd_y` agree with their own `lat`/`lon` to **0.43 m** (a constant
  residual = the conversion formula's own approximation, not data error).
- Sanity: nearest clip to line 1 / 3c / 6 = 7.1 / 9.2 / 3.7 m.

**No rotation is applied, and that is correct.** `BuildingShell`'s transform in
`MainWorld.tscn` is a pure translation with an **identity basis** — the world is
axis-aligned to RD. `floor_plan.rot_deg = −130.2` rotates only the *overlay
image*, not the world. Applying it to audio would be the bug.

`_scene_anchor()` measures the anchor from the mesh rather than reading
`satellite_center_rd` out of the user-writable save file, so a layout re-saved
from a differently-centred screenshot cannot silently drift the clips while
vehicles and line-starts stay put. Satellite centre remains a warned fallback.

## Loop seams — the crossfade, and the trap under it

The clips were cut from the walkthrough video at *event* timestamps, not
zero-crossings. With plain `LOOP_FORWARD` the loop jumped from the last sample
straight back to the first: **5 clips clicked hard** (worst, `110.9s`, was 25.5 %
of peak) and **20 more popped** (2–10 %).

`_crossfade_for_loop()` does an overlap-add: blends the tail into the head over
10 ms and truncates the tail. The point is not that it minimises a sample delta —
for broadband machine noise that number is meaningless. The point is that the
loop boundary now joins frames that are **consecutive in the original
recording** (verified `consecutive = True` for all 43). Continuity by
construction.

### TRAP: IMA_ADPCM vs byte-level editing

The clips imported with `compress/mode=2` (IMA_ADPCM). Editing that compressed
data as if it were raw PCM corrupts it, and Godot then refuses to play:

```
Condition "ffp != 8" is true. Returning: Ref<AudioStreamPlaybackWAV>()
Failed to instantiate playback.        → 43 silent players
```

Fix: all 43 `.wav.import` files set to `compress/mode=0` (uncompressed 16-bit
PCM, ~41 MB vs ~10 MB). `_crossfade_for_loop()` now guards on
`format != FORMAT_16_BITS` and skips-with-warning instead of corrupting.

> **`assets/` IS GITIGNORED.** The `compress/mode=0` change and every WAV are
> **local-only and will not survive a fresh clone.** On a new machine the guard
> fires, the crossfade is skipped, and the clicks come back. Re-run the
> mode-2 → mode-0 edit across `assets/audio/clips/*.wav.import` after cloning.

## Three open findings (scouted, not yet acted on)

1. **`src/data/surfaces/PhysicalSurface.gd` is dead scaffolding.** A complete
   Resource for footstep / impact / tyre-roll / tyre-skid audio with friction
   and particle fields — and **every clip array is empty, there are zero `.tres`
   instances, and grep finds zero references anywhere in `src/`.** Someone built
   the frame and never filled it. Highest-value audio work available.
2. **The UI bus is completely unused.** It exists at −3 dB and nothing has ever
   played on it. The entire HMI is silent to the touch.
3. **The source recording is 93 % mined — but only for ambience.**
   `C:/Users/arnod/Desktop/tmp/VID-20250912-WA0011.mp4`, 269.421 s, 44.1 kHz
   stereo (also a decoded `.flac` on the Desktop). Already sliced into the 43
   long ambience loops; only 241.7–260.1 s is unsliced. **Nobody has ever
   extracted short discrete one-shots** — impacts, beeps, hisses, splashes,
   the camera operator's own footsteps. That is the untapped reservoir, and it
   is how "no build without docs" applies to audio: take sounds from the real
   plant rather than inventing them.

## Paused work

An ultracode workflow to design and build 15+ new sounds was launched and
**stopped during its read-only phase — nothing was written.** Script saved at:

```
C:\Users\arnod\.claude\projects\C--Users-arnod-Documents-CeDo-Simulator\
  649d2ab2-1aaf-40e4-96fe-ba862dbb423e\workflows\scripts\
  cedo-sound-engine-expansion-wf_a01dce5d-124.js
```

Its plan: understand → two competing catalogues (operator-authenticity vs
gameplay-feedback) → hard judge → four parallel build modules (footsteps /
vehicle / process / UI) → single integration pass → two adversarial verifiers.
Because `assets/` is gitignored, the design makes the **generator scripts under
`tools/audio/` the committed deliverable**; baked WAVs are derived artifacts
anyone can re-emit.

## Relevant commits

- `3480b3d` — PlantAudio: seamless clip loops + pin the RD anchor to the mesh
- `1b29087` — HMI: the remaining 11 L3C unit screens (unrelated, was sitting
  uncommitted from a prior session)
