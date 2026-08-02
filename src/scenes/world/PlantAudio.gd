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
# Same mesh WorldLayout._rd_to_scene_shift() measures its shift from — keeping
# audio and markers pinned to one source. See _scene_anchor().
const BUILDING_TILE_OBJ : String = "res://assets/models/CeDo_building.obj"

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
			_crossfade_for_loop(stream as AudioStreamWAV)
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(stream as AudioStreamWAV).loop_end = 0   # 0 = end of (now-truncated) stream
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
## The anchor MUST come from the same source WorldLayout pins every other marker
## to — the building tile mesh AABB centre — not from the saved satellite centre.
## The two agree today (mesh 184112.50/-329382.27 vs saved satellite
## 184112.5/329382.25, 0.02 m apart), but the satellite centre lives in a
## user-writable save file: re-save the layout from a differently-centred
## screenshot and every clip silently drifts while vehicles/line-starts stay put.
## Measure it, don't inherit it. Satellite centre remains the fallback.
func _scene_anchor() -> Vector3:
	var mesh = ResourceLoader.load(BUILDING_TILE_OBJ)
	if mesh is Mesh:
		# Mesh vertices carry z = −RD north, so negate to get the RD north anchor
		# that _clip_local_position expects.
		var c : Vector3 = (mesh as Mesh).get_aabb().get_center()
		return Vector3(c.x, 0.0, -c.z)
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		return Vector3.ZERO
	var sat = wl.get("satellite_center_rd")
	if sat is Vector2:
		push_warning("[PlantAudio] %s unavailable — falling back to the saved satellite centre" % BUILDING_TILE_OBJ)
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
	# RD NORTH (rd_y) increases toward world −Z — the SAME convention WorldLayout
	# uses (WorldLayout.gd:306 "RD y → world −z"). The old `rd_y - anchor.z` had the
	# sign flipped, mirroring all 43 clips ~85 m to the far side of the plant so
	# none fell inside max_distance (30 m) and NOTHING was audible. local_z must be
	# anchor.z − rd_y so clips co-locate with the line-starts/yards. (Proven: nearest
	# audible clip 85.5 m → 3.7 m; 0/43 → 30/43 within 30 m of where the operator stands.)
	return Vector3(rd_x - anchor.x, floor_y, anchor.z - rd_y)

## Overlap-add crossfade: blend the tail of the WAV into its own head so the
## loop boundary is continuous. The tail is consumed (truncated) — ~10 ms lost,
## inaudible on multi-second plant-noise clips.
##
## Before:  [...TAIL_last] → [HEAD_first...]   ← sample jump = click
## After:   [...BODY_last] → [XFADE_first...]  ← BODY_last and XFADE_first are
##          consecutive in the ORIGINAL pcm, so the transition is smooth.
func _crossfade_for_loop(wav: AudioStreamWAV) -> void:
	if wav.format != AudioStreamWAV.FORMAT_16_BITS:
		push_warning("[PlantAudio] clip is not 16-bit PCM (format=%d) — skipping crossfade. "
			+ "If IMA_ADPCM, set compress/mode=0 in the .import file and reimport." % wav.format)
		return
	const FADE_SEC := 0.010   # 10 ms — plenty for broadband machine noise
	var channels := 2 if wav.stereo else 1
	var bpf := 2 * channels   # 16-bit = 2 bytes per sample per channel
	@warning_ignore("integer_division")
	var total_frames := wav.data.size() / bpf
	var fade_frames := mini(int(wav.mix_rate * FADE_SEC), total_frames / 3)
	if fade_frames < 2:
		return
	var src := wav.data                            # COW — stays immutable
	var new_count := total_frames - fade_frames    # truncate the tail
	var out := src.slice(0, new_count * bpf)       # copy head + body
	var tail_off := (total_frames - fade_frames) * bpf
	for i in fade_frames:
		var alpha := float(i) / float(fade_frames)
		var f_off := i * bpf
		for ch in channels:
			var byte_off := f_off + ch * 2
			var h := src.decode_s16(byte_off)
			var t := src.decode_s16(tail_off + byte_off)
			var mixed := int(float(h) * alpha + float(t) * (1.0 - alpha))
			out.encode_s16(byte_off, clampi(mixed, -32768, 32767))
	wav.data = out

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
