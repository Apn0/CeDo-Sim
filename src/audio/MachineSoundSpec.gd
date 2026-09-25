extends Resource
class_name MachineSoundSpec
## ONE machine's sound design, as data. Instances live in
## `src/audio/machine_sounds/<placeable_id>.tres` and are edited in the Godot
## inspector — every number below is a slider there. `gain_db` is the per-machine
## level the operator asked for ("add audio slider per machine's audio in the
## editor so that it can be easily edited later after my testing", 2026-09-25).
##
## The baked clips are RMS-normalised to one common level by
## `tools/audio/machine_clips.py`, so `gain_db` is the ONLY place a machine's
## loudness relative to the others lives. Clip paths are strings, not
## ext_resources, because `assets/` is gitignored: a missing WAV must degrade to
## a warning and a silent machine, never to a .tres that fails to load.
##
## Runtime reader: `src/audio/MachineSound.gd` (built by MachineSoundBank.attach).

@export_group("Level")
## Per-machine level. 0 dB plays the normalised loop as baked.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var gain_db : float = 0.0
## Radius (m) inside which the machine is heard at full level.
@export_range(0.5, 20.0, 0.5, "suffix:m") var unit_size_m : float = 3.0
## Distance (m) beyond which it is inaudible.
@export_range(5.0, 150.0, 1.0, "suffix:m") var max_distance_m : float = 30.0
## Audio bus (default_bus_layout.tres). Falls back to Master if missing.
@export var bus : String = "Machines"

@export_group("Clips")
## The constant-operation loop. Empty = this machine has no running sound (yet).
@export_file("*.wav") var run_loop : String = ""
## Optional low-speed loop (leaf blower idle). Crossfaded into run_loop as the
## drive rises past idle_to_run_at.
@export_file("*.wav") var idle_loop : String = ""
## One-shot played when the machine goes from stopped to running.
@export_file("*.wav") var start_clip : String = ""
## One-shot played when the machine comes to a stop.
@export_file("*.wav") var stop_clip : String = ""
## Named one-shots for MachineSound.play_event(name): {"valve_open": "res://…"}.
@export var event_clips : Dictionary = {}

@export_group("Ramp (generated from the run loop)")
## Pitch of the run loop at drive 0 (ramp-up start / ramp-down end).
@export_range(0.2, 1.0, 0.01) var pitch_floor : float = 0.55
## Level of the run loop at drive 0, relative to gain_db.
@export_range(-60.0, 0.0, 1.0, "suffix:dB") var ramp_db_floor : float = -24.0
## Seconds for the sound to go 0 → 1. 0 = follow the machine's own spin-up
## (LineFlow.SPIN_UP_S, 2.5 s). A larger value slows the audible ramp-up.
@export_range(0.0, 60.0, 0.1, "suffix:s") var ramp_up_s : float = 0.0
## Seconds for the sound to go 1 → 0 (a heavy rotor coasts down slowly).
@export_range(0.0, 60.0, 0.1, "suffix:s") var ramp_down_s : float = 0.0
## With an idle loop: the drive at which the idle starts handing over to run.
@export_range(0.0, 0.95, 0.01) var idle_to_run_at : float = 0.25
## With an idle loop: the idle loop's pitch at full drive.
@export_range(1.0, 2.0, 0.01) var idle_pitch_top : float = 1.25

@export_group("Periodic event")
## Name (in event_clips) of a one-shot that fires on a period while running.
@export var periodic_event : String = ""
## The period in seconds; 0 disables.
@export_range(0.0, 3600.0, 1.0, "suffix:s") var periodic_event_s : float = 0.0
## ±fraction of random jitter on the period.
@export_range(0.0, 1.0, 0.05) var periodic_jitter : float = 0.0

@export_group("Alarm")
## Beep repeated every alarm_period_s while MachineSound.set_alarm(true).
@export_file("*.wav") var alarm_clip : String = ""
@export_range(0.2, 10.0, 0.1, "suffix:s") var alarm_period_s : float = 1.2

@export_group("Provenance")
## Where the sounds came from and what is still a placeholder.
@export_multiline var notes : String = ""
