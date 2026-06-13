extends Node3D
class_name PlantAudio

## #60 — Positional plant audio from the audio-placer data.
##
## Loads `assets/audio/audio_layout.json` (exported from the cedo-audio-placer
## web app), spawns one AudioStreamPlayer3D per clip at the clip's recorded
## RD coordinate (converted to scene-local via WorldLayout's anchor), and
## plays each on a continuous loop. The 3D players inherit Godot's distance
## attenuation, so the operator hears each clip only when near the marker —
## walk past the trilzeef and you hear the trilzeef recording, walk further
## and it fades into ambience.
##
## "Until clips are machine-assigned" (per the task description): the placer's
## current JSON has no `machines` field — every clip is anchored to its
## recording GPS position. When the placer is updated to export per-clip
## machine ids, we'll reparent matching players under the machine's Node3D
## so the audio moves with the machine if the operator jogs it.

## PlantAudio was originally disabled while hunting the renderer NaN errors —
## those turned out to be from BaseVehicle's beacon spin + degenerate
## RotatingMechanism bases, NOT this system. Re-enabled now.
const ENABLED : bool = true

const LAYOUT_PATH : String = "res://assets/audio/audio_layout.json"
const CLIPS_DIR   : String = "res://assets/audio/clips/"

# Audio-bus routing. 0..1 of the cedo "Machines" bus volume curve so future
# settings-menu sliders can attenuate everything in one place.
const BUS_NAME : String = "Machines"

# Per-clip 3D attenuation. unit_size is the radius inside which the clip plays
# at full volume; max_distance is where it falls to inaudible. Both in metres.
const UNIT_SIZE_M     : float = 4.0
const MAX_DISTANCE_M  : float = 30.0
const VOLUME_DB       : float = -8.0      # baseline; loud clips can be lowered per-clip later

var _players : Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	if not ENABLED:
		print("[PlantAudio] disabled — set ENABLED=true in PlantAudio.gd to re-enable")
		return
	_load_and_spawn()

func _load_and_spawn() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		push_warning("[PlantAudio] %s not found — no positional audio" % LAYOUT_PATH)
		return
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		push_warning("[PlantAudio] could not open %s" % LAYOUT_PATH)
		return
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Array):
		push_warning("[PlantAudio] audio_layout.json is not a JSON array")
		return
	var clips : Array = parsed
	var anchor : Vector3 = _scene_anchor()
	var placed : int = 0
	for c in clips:
		if not (c is Dictionary):
			continue
		var clip_name : String = String(c.get("clip_name", ""))
		if clip_name == "":
			continue
		var stream_path : String = CLIPS_DIR + clip_name + ".wav"
		if not ResourceLoader.exists(stream_path):
			# Common when a clip was renamed in the placer but never re-exported
			# — skip silently, log once at debug build only.
			if OS.is_debug_build():
				push_warning("[PlantAudio] missing audio file %s" % stream_path)
			continue
		var stream : AudioStream = load(stream_path)
		if stream == null:
			continue
		# Tell Godot to loop the WAV. WAVs default to no loop; we want continuous
		# ambient drone for plant audio, so force it on at the stream level.
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			# Without explicit end points the loop covers the whole sample, which
			# is exactly what the placer's segment exports were trimmed for.
			(stream as AudioStreamWAV).loop_end = 0   # 0 = end of stream
		var pos : Vector3 = _clip_local_position(c, anchor)
		var player := AudioStreamPlayer3D.new()
		player.name = "PA_" + clip_name
		player.stream = stream
		player.bus = BUS_NAME if AudioServer.get_bus_index(BUS_NAME) >= 0 else "Master"
		player.unit_size = UNIT_SIZE_M
		player.max_distance = MAX_DISTANCE_M
		player.volume_db = VOLUME_DB
		# Attenuation model — INVERSE_DISTANCE feels closest to "you hear the
		# fan only when you're next to it" without a sharp cliff at max_distance.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.position = pos
		add_child(player)
		# Start at a random offset within the clip so 43 players don't all
		# crescendo on the same beat — gives the production floor a believable
		# overlapping soundscape instead of a single synchronised pulse.
		player.play(randf() * _stream_length(stream))
		_players.append(player)
		placed += 1
	print("[PlantAudio] spawned %d positional clip players (anchor RD-shift %.0f, %.0f, %.0f)" \
		% [placed, anchor.x, anchor.y, anchor.z])

## Build the RD-anchor shift the same way WorldLayout does — so audio markers
## land in the SAME local frame as vehicles / line-starts / yards. Returns the
## RD-to-local SHIFT (subtracted from each clip's RD coord to produce local).
func _scene_anchor() -> Vector3:
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		return Vector3.ZERO
	var sat = wl.get("satellite_center_rd")
	if sat is Vector2:
		return Vector3(float(sat.x), 0.0, float(sat.y))
	return Vector3.ZERO

## Convert a single clip's RD coord pair to scene-local. The placer's `rd_y` is
## the NORTH coordinate; in our scene the north direction is +Z, matching the
## WorldLayout convention (see the WorldSetup → MainWorld conversion).
func _clip_local_position(clip: Dictionary, anchor: Vector3) -> Vector3:
	var rd_x : float = float(clip.get("rd_x", 0.0))
	var rd_y : float = float(clip.get("rd_y", 0.0))
	var floor_y : float = 0.0
	var mw := get_parent()
	if mw != null and mw.has_method("_floor_top_y"):
		floor_y = float(mw.call("_floor_top_y")) + 1.5   # head-height for the player
	return Vector3(rd_x - anchor.x, floor_y, rd_y - anchor.z)

## Best-effort stream-length lookup so the random-offset jitter doesn't
## over-shoot. Falls back to 2 s for unknown streams.
func _stream_length(stream: AudioStream) -> float:
	if stream is AudioStreamWAV:
		var wav : AudioStreamWAV = stream
		# 16-bit mono → 2 bytes per sample; stereo → halve again. Intentional ints.
		@warning_ignore("integer_division")
		var sample_count : int = wav.data.size() / 2
		if wav.stereo:
			@warning_ignore("integer_division")
			sample_count = sample_count / 2
		if wav.mix_rate > 0:
			return float(sample_count) / float(wav.mix_rate)
	return 2.0
