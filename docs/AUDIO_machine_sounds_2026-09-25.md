# Machine sounds from the operator's recordings — 2026-09-25

Eleven recordings the operator made on the plant floor on 2026-09-22, cut to the
instructions carried in their file names, baked to loops and one-shots, and
placed on the machines that made them. Companion to
`docs/AUDIO_sound_engine_state_2026-08-03.md` (the positional walkthrough clips);
this is the second, per-machine chain.

## What arrived

Dropped on the Desktop 2026-09-22 15:07–15:32, moved to
`assets/audio/machines/_source/` (gitignored with all of `assets/`, `.gdignore`d
so Godot never imports the mp3s). The Desktop originals were removed on
2026-09-25 only after a SHA256 match against the `_source/` copy, file by file.

| recording | length | format |
|---|---|---|
| `17s+_trilzeef_sorting_3A_3B.mp3` | 65.09 s | 24 kHz stereo 160 kb/s |
| `25s-35s_laserfilter.mp3` | 64.90 s | 24 kHz stereo 160 kb/s |
| `5s+_onwards_mechanical_dryer.mp3` | 58.17 s | 44.1 kHz mono 256 kb/s |
| `blower_in_operation.mp3` | 14.35 s | 24 kHz stereo 160 kb/s |
| `leaf_blower_starter_idle_revving.mp3` | 20.14 s | 24 kHz stereo 160 kb/s |
| `loop_3x_1m11s-1m14s_automatic_compactor_PCU_ringleiding_cleaning.mp3` | 94.13 s | 24 kHz stereo 160 kb/s |
| `plasmaq.mp3` | 163.03 s | 48 kHz stereo 256 kb/s |
| `shredder_2_sorting_3A_3B.mp3` | 60.02 s | 48 kHz stereo 256 kb/s |
| `turn-crank_old_metal_manually_operated_valve_loop_4x.mp3` | 6.74 s | 48 kHz mono 256 kb/s |
| `verdeelwals_in_operation.mp3` | 62.81 s | 24 kHz stereo 160 kb/s |
| `washing_3A_alarm.mp3` | 0.37 s | 44.1 kHz mono 256 kb/s |

## The file names are the cutting instructions (operator, 2026-09-25)

| fragment | meaning, in his words |
|---|---|
| `_in_operation` | "not ramping up, not ramping down, not starting up, not shutting down — just a constant sound of the machine in operation" |
| `_loop_4x` | "four times a similar sound, not the same, but similar — pick one for action one (opening) and another for action two (closing)" |
| `1m11s-1m14s` | "start from that clip at 1 minute 11 seconds, go to 1 minute 14 seconds" |
| `loop_3x_` prefix | "…then it does twice more from 1:11 to 1:14, and then that entire sound of the three, in a sequence, has to loop" |
| `5s+_onwards` | "skip the first 4.999999 seconds and start at 5.00" |

## What was baked — `tools/audio/machine_sounds.json` → `machine_clips.py`

18 WAVs, all 16-bit PCM stereo 44.1 kHz; every loop carries one `smpl` chunk and
a `compress/mode=0` `.import` sidecar (the IMA_ADPCM trap in `tools/audio/README.md`).
Loops are cut at a correlated seam with an equal-power crossfade and
RMS-normalised to −20 dBFS under a −1 dBFS ceiling; one-shots are peak-normalised.
Lengths measured with ffprobe after the bake.

| output | from | kind | length |
|---|---|---|---|
| `trilzeef_run` | trilzeef 17.0–57.0 s (24 s loop, seam ncc +0.778, gain −3.3 dB) | loop | 22.749 s |
| `laser_filter_run` | laserfilter 25–35 s | loop | 8.943 s |
| `mech_dryer_run_30s` | dryer 30.0–42.0 s (seam ncc +0.931, gain −14.8 dB) | loop | 9.944 s |
| `mech_dryer_run_43s` | dryer 43.0–55.5 s (seam ncc +0.325, gain −12.6 dB) | loop | 10.209 s |
| `blower_run` | blower 0.5–14.3 s | loop | 11.460 s |
| `verdeelwals_run` | verdeelwals 1–62 s | loop | 22.060 s |
| `plasmaq_run` | plasmaq 5–160 s | loop | 23.506 s |
| `shredder_2_run` | shredder 1.5–58 s | loop | 25.172 s |
| `compactor_ringleiding_loop` | compactor 71.0–74.0 s × 3, 30 ms joins, wrap = one more join (gain +6.1 dB) | **loop** | 8.910 s |
| `leafblower_start` / `_idle` / `_rev` / `_stop` | 0–1.30 / 6.0–17.2 / 2.3–5.65 / 17.35–20.14 s | shot / loop / loop / shot | 1.300 / 8.429 / 2.405 / 2.786 s |
| `valve_crank_1..4` | 0.10–1.60 / 1.75–3.30 / 3.40–4.95 / 5.10–6.74 s | shot ×4 | 1.50 / 1.55 / 1.55 / 1.64 s |
| `washing_alarm_beep` | alarm 0–0.366 s | shot | 0.366 s |

The 30–42 s dryer window is clipped in the recording itself (−2.4 dBFS flat, 7.8–8.3 %
of samples at full scale per 2 s); normalisation lowers it, the distortion stays.
The 5–30 s rise of that recording (−14 → −2.4 dB with the motor fundamental fixed
at 72–74 Hz) is the microphone walking up to the machine, not a spin-up, and is
in neither loop.

## Runtime — data-driven, one `.tres` per placeable id

`src/audio/machine_sounds/<placeable_id>.tres` (`MachineSoundSpec`) decides which
machines have a sound at all: no `.tres`, no sound (the centrifuge is the negative
control in the suite). `MachineSoundBank.attach()` hangs a `MachineSound` under
the placed body at the tail of `PlaceableCatalog.build_node`, idempotent, never on
a ghost. Drivers:

| who | how |
|---|---|
| `LineFlow._tick_plc_power_downstream` (10 Hz) | `set_drive(spin × rotor fraction)` — heard at the speed the machine is AT; a node that leaves the graph winds down on a 1 s watchdog |
| `LeafBlower._physics_process` | `set_drive(_spool)`; start clip on OFF→SPOOLING_UP, idle↔rev equal-power crossfade, stop clip at OFF |
| `HoseReel`, `WasteContainer` (IBC) | `play_event("valve_open" / "valve_close")` — hose reel: takes 1 and 3; IBC drain: take 2 |
| `Hmi` (the physical panel) | `set_alarm(unacked > 0)`: repeats the 0.37 s beep every `alarm_period_s` until KWITTEREN (overlay signal `faults_acknowledged`), counting both EventBus alarms in the panel's scope and the overlay's scoped faults |

Not operating → the loop players are STOPPED, not quiet. Ramp-up/ramp-down are
GENERATED from the run loop (pitch `pitch_floor`→1.0, level `ramp_db_floor`→0 dB
over the machine's spin or the spec's `ramp_up_s`/`ramp_down_s`); the recordings
themselves hold no ramps, per `_in_operation`. `gain_db` is the per-machine
slider the operator asked for and the ONLY place relative loudness lives.

## Decisions, and what the operator has not decided

- **Compactor: the 3× sequence is a LOOP.** The first bake (the parallel session,
  01:11–01:22) made it a 9 s one-shot fired every 90 s — the period was invented
  (EREMA GUIDE 355_CeDo59 describes the air flush and gives no interval). Rebaked as
  `compactor_ringleiding_loop`, the compactor's run loop, `pitch_floor` 1.0 so air
  pulses do not pitch-bend with motor speed. The compactor has no other recording.
- **Dryer: two windows, assignment pending.** Asked which window, the operator:
  "30-42s and 43-55s clipped separately, I'll let you know what dryer is which."
  Both L3C.14 dryers are the one placeable id `mech_dryer` (`"stream": "L"/"R"`
  in `BuildMode.LINE_3C_SEQ`); `mech_dryer.tres` points at `_43s` as an interim
  default. Assigning per dryer needs a per-stream spec variant that does not exist yet.
- **Trilzeef starts at 17.0 s**, as the name says (the first bake used 18.0).
- **Which valve was recorded is an ASSUMPTION** (`hose_reel_valve.tres`,
  `ibc_valve.tres`): the hose-reel base valve and the IBC drain are the only
  hand-operated valves in the sim.
- **Every level, radius, ramp time and the 1.2 s alarm period are PLACEHOLDERS**,
  labelled so in each `.tres`; the suite asserts the label is present.

## Proof — measured 2026-09-25 01:44–01:50, this worktree

- `--import`: exit 0, 0 `SCRIPT ERROR` lines (the ERROR lines are the known WebView /
  waterbox-icon / one unrecognised UID, none names an asset).
- `res://src/tests/test_machine_sounds.tscn`: **`Result: PASS (80 ok, 0 fail)`**,
  0 `SCRIPT ERROR`, 44 s. S1: 16 referenced WAVs valid, 10 loops `LOOP_FORWARD`,
  6 one-shots not looping, both spares baked. S7: run loop 8.910 s, pitch 1.000 at
  full and at half drive, stopped at drive 0.
- `tools/regression/parse_sweep.gd`: `Result: 453 ok, 0 fail`.
- Wired into `tools/regression/run.sh` as `test_machine_sounds`, first in the main loop.

**Not proven:** how any of it sounds in a MainWorld boot. Nothing headless asserts
audio content, and every level is a placeholder — that is the operator's play-test.

## Rebuild, and where the bakes are

```bash
python tools/audio/machine_clips.py --check     # what is missing
python tools/audio/machine_clips.py             # bake it
python tools/audio/machine_clips.py --force     # rebake everything (deterministic)
```

`assets/` is gitignored, so the 18 WAVs + `.import` exist only where they were
baked. On 2026-09-25 they were COPIED (never linked — `docs/audit/assets_loss_and_restore_2026-09-21.md`)
into the operator's checkout `C:\Users\arnod\Documents\CeDo_Simulator\assets\audio\machines\`
(36 files; SHA256 identical on the three sampled). The two superseded bakes
(`compactor_ringleiding_flush.wav`, `mech_dryer_run.wav`) are kept beside them as `.bak`.
