extends BaseVehicle
class_name Car

## Base class for passenger-car vehicles (#134 / #135). Sits between BaseVehicle
## (forklift / bale-clamp / merlo) and the per-model FBX subclasses (SuzukiSwift,
## FordStreetka, VolvoS60, FordKa, ToyotaAygo, VWPolo, BMWX1, HyundaiI20).
##
## What Car adds on top of BaseVehicle:
##  • Per-model FBX_PATH + part name dictionary, loaded by the subclass.
##  • Generic articulation: 4 wheels (FL/FR/RL/RR), 2-4 doors (FL/FR/RL/RR),
##    glass alpha-blend, steering-wheel mirror, dashboard.
##  • Ignition state: engine OFF on spawn, [I] key turns it on/off.
##  • Engine audio: AudioStreamGenerator-synthesised low rumble whose pitch
##    follows abs(linear velocity) — idle ≈ 25 Hz, full ≈ 95 Hz. Mirrors the
##    beeper synth in BaseVehicle so we don't ship a binary audio asset just
##    for this. Per-model subclasses can override _engine_idle_hz / _engine_max_hz.
##  • Passenger seat marker (right side, +X local). NPCs (e.g. Yasin) parent
##    themselves to this when riding shotgun.
##
## NOTE — FBX import: Godot can't load a raw .fbx at runtime. The editor has to
## ingest it once to generate the .scn + .import cache. Until that happens the
## subclass logs a warning + the VehicleBody3D still functions as a driveable
## box (proxy collision in the .tscn) so the rest of the game keeps booting.

# ── Engine audio synth params (subclass-overridable) ─────────────────────────
@export_group("Engine audio")
@export var engine_idle_hz : float = 28.0      # low rumble at idle
@export var engine_max_hz  : float = 92.0      # near red-line
@export var engine_gain    : float = 0.18

# ── Ignition ──────────────────────────────────────────────────────────────────
var engine_on : bool = false

# ── Audio runtime ─────────────────────────────────────────────────────────────
var _engine_player : AudioStreamPlayer3D = null
var _engine_pb     : AudioStreamGeneratorPlayback = null
var _engine_phase  : float = 0.0
var _engine_hz     : float = 0.0

# ── Passenger seat ────────────────────────────────────────────────────────────
var _passenger_seat : Marker3D = null
var _passenger_npc  : Node3D = null

# Door articulation (filled by subclass when FBX is parsed).
# Each entry: { "pivot": Node3D, "open_deg": float, "side": "L"/"R" }
var _car_doors : Array = []

# =============================================================================
func _ready() -> void:
	# Drive-ramp tuning per the throttle/brake audit. Passenger cars accelerate
	# much more briskly than industrial machines — ~3.7 s 0→80 km/h on the
	# default 6 m/s². Per-model subclasses (BMW / Audi) can bump this higher
	# in their own _ready() override; small hatchbacks (Ka / Swift) can lower
	# it. 12 m/s² brake (~1.2 g) is closer to ABS-locked emergency stop than
	# the legacy 24 m/s²/2.4 g teleport-feel the audit flagged.
	throttle_accel_mps2 = 2.5   # #223: was 6 — realistic mid-car 0-100 in ~11 s
	brake_decel_mps2    = 8.0   # was 12 (1.2g, > best road car) — 0.8g panic stop
	coast_decel_mps2    = 0.8   # was 3 — real engine-braking drift-to-stop
	throttle_ramp_tau_s = 0.6
	brake_ramp_tau_s    = 0.3
	super._ready()
	_ensure_car_actions()
	_install_engine_audio()
	_install_passenger_seat()

func _ensure_car_actions() -> void:
	# Ignition: I toggles engine. Re-registered at runtime so saved InputMaps
	# from before this feature exists still get the binding.
	if not InputMap.has_action("vehicle_ignition"):
		InputMap.add_action("vehicle_ignition")
		var k := InputEventKey.new()
		k.keycode = KEY_I
		InputMap.action_add_event("vehicle_ignition", k)

# ── Engine audio ──────────────────────────────────────────────────────────────
func _install_engine_audio() -> void:
	_engine_player = AudioStreamPlayer3D.new()
	_engine_player.name = "EngineAudio"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.1
	_engine_player.stream = gen
	_engine_player.unit_size = 8.0
	_engine_player.max_db = 0.0
	_engine_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(_engine_player)

func _start_engine() -> void:
	if engine_on:
		return
	engine_on = true
	_engine_player.play()
	_engine_pb = _engine_player.get_stream_playback() as AudioStreamGeneratorPlayback

func _stop_engine() -> void:
	engine_on = false
	_engine_pb = null
	_engine_player.stop()

func _fill_engine_buffer() -> void:
	if _engine_pb == null:
		return
	# Engine note scales with speed: idle when stopped, climbs to max with kmh.
	# Use get_speed_mps() (BaseVehicle's tracked drive speed) not linear_velocity
	# — the body can be freeze-kinematic so linear_velocity reads zero and the
	# engine stays stuck at idle. Audit-caught.
	var kmh : float = get_speed_mps() * 3.6
	var t : float = clampf(kmh / speed_limit_kmh, 0.0, 1.0)
	var target_hz : float = lerpf(engine_idle_hz, engine_max_hz, t)
	# One-pole smooth so pitch doesn't jitter on every physics tick.
	_engine_hz = lerpf(_engine_hz, target_hz, 0.18)
	var frames_avail : int = _engine_pb.get_frames_available()
	if frames_avail <= 0:
		return
	var rate : float = 22050.0
	for _i in frames_avail:
		# Two-stack sine + noise gives a passable engine rumble without a sample.
		var s : float = sin(_engine_phase) * 0.55
		s     += sin(_engine_phase * 2.03) * 0.20
		s     += (randf() - 0.5) * 0.25 * (0.7 + t * 0.3)
		_engine_pb.push_frame(Vector2(s, s) * engine_gain)
		_engine_phase += TAU * _engine_hz / rate
		if _engine_phase > TAU * 64.0:
			_engine_phase -= TAU * 64.0

func _physics_process(delta: float) -> void:
	# CRITICAL: BaseVehicle._physics_process runs the whole drive/steer/move/fuel
	# loop including the canonical steer ramp (_update_steer_ramp → MAX_STEER_RAD
	# 55° / STEER_RATE_RAD_PER_SEC 18.33°/s). Earlier this override skipped super(),
	# silently making every passenger car undriveable. Call it FIRST, then layer
	# the engine-audio fill on top.
	super._physics_process(delta)
	if engine_on:
		_fill_engine_buffer()

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if occupied and event.is_action_pressed("vehicle_ignition"):
		if engine_on:
			_stop_engine()
		else:
			_start_engine()

# ── Passenger seat ────────────────────────────────────────────────────────────
## Subclass calls this once the FBX is loaded to anchor the passenger marker
## relative to the discovered driver seat (or hand-tunes the position).
func _install_passenger_seat() -> void:
	_passenger_seat = Marker3D.new()
	_passenger_seat.name = "PassengerSeat"
	# Default: right side, just inside the cabin, butt-height.
	_passenger_seat.position = Vector3(0.40, 0.65, 0.10)
	add_child(_passenger_seat)

## Park an NPC in the passenger seat. The NPC keeps its node, just gets
## reparented under the seat marker and frozen.
func seat_passenger(npc: Node3D) -> void:
	if npc == null or _passenger_seat == null:
		return
	_passenger_npc = npc
	if npc.get_parent():
		npc.get_parent().remove_child(npc)
	_passenger_seat.add_child(npc)
	npc.position = Vector3.ZERO
	npc.rotation = Vector3.ZERO
	if npc.has_method("set_seated"):
		npc.call("set_seated", true)

# ── Generic 4-door articulation (called by subclass after FBX classify) ──────
## doors_dict[name] = pivot_node3d. side is auto-derived from world X.
## DOOR opens by rotating around its local Y axis at the hinge edge.
func articulate_doors(door_nodes: Array, open_deg: float = 65.0) -> void:
	_car_doors.clear()
	for d in door_nodes:
		var n := d as Node3D
		if n == null:
			continue
		# Side from world X — right doors get NEGATIVE open angle so they
		# swing the right way (Y-up hinge convention).
		var is_right : bool = n.global_position.x > global_position.x
		var sign_d  : float = -1.0 if is_right else 1.0
		_car_doors.append({
			"pivot":     n,
			"open_deg":  open_deg * sign_d,
			"is_open":   false,
			"current":   0.0,
		})

func toggle_door(idx: int) -> void:
	if idx < 0 or idx >= _car_doors.size():
		return
	_car_doors[idx]["is_open"] = not _car_doors[idx]["is_open"]

func _process(delta: float) -> void:
	# Smoothly interpolate doors toward target angle. (Procedural, no AnimPlayer.)
	for door_dict in _car_doors:
		var pivot : Node3D = door_dict["pivot"]
		if pivot == null:
			continue
		var target : float = door_dict["open_deg"] if door_dict["is_open"] else 0.0
		door_dict["current"] = lerpf(door_dict["current"], target, clampf(delta * 6.0, 0.0, 1.0))
		pivot.rotation.y = deg_to_rad(door_dict["current"])
	# Steering wheel mirror (set by _articulate_steering if the model has one).
	# Reads BaseVehicle._current_steer_rad (the canonical ramped angle, ±55° max,
	# 18.33°/s rate). Multiplied by ~6 so a full ±55° wheel-lock spins the
	# in-cabin steering wheel ~±330° (typical car wheel travel ~1.5 turns each way).
	# Positive _current_steer_rad = wheels LEFT = steering column CCW seen from
	# above = +Z rotation visually held left.
	if _steering_node != null and is_inside_tree():
		_steering_node.rotation.z = _current_steer_rad * 6.0

# =============================================================================
# SHARED FBX/GLB LOADER + CLASSIFIER + ARTICULATION
# Subclasses set _model_path, _part_names, _paint_color in _ready() BEFORE
# calling load_model(). One implementation here = no duplicated walkers in
# every per-car script.
# =============================================================================
var _model_path : String = ""
var _model_scale: Vector3 = Vector3.ONE                # subclass override (e.g. Streetka squish)
## V2 — Real-world bumper-to-bumper length in metres. The FBX-import auto-ruler
## (see load_model) measures the loaded model's AABB and rescales it so its
## longest horizontal extent matches this. Default 3.85 m ≈ Suzuki Swift; each
## car subclass overrides to its actual length. Set to 0.0 to disable rescaling.
var _real_world_length_m : float = 3.85
var _part_names : Dictionary = {}
var _paint_color: Color = Color(1.0, 1.0, 1.0, 0.0)    # alpha=0 means "don't paint"
# #157 — Swift's FBX has no carpaint-named material, so the name-based matcher
# can't tint it. When this is true and the matcher didn't apply anywhere, we
# fall back to tinting the largest visible mesh in the imported body (heuristic
# but works for single-mesh-body imports like the FBX).
var _paint_fallback_largest_mesh : bool = false
# Extra material names (lowercased substrings) that the body-paint matcher should
# accept in addition to "paint" / "body" / "lack". Lets each car add its own
# odd-named body material — e.g. the traffic pack labels the VW Golf's body
# material simply "golf" with no "paint" in the name.
var _paint_extra_match : Array = []
var _parts      : Dictionary = {}
var _steering_node: Node3D = null

## VISUAL FRONT RULE compliance. Canonical CeDo direction = forward is local -Z.
## Most car FBX/GLB assets in this project are authored facing +Z, so the
## default loader applies a +180° yaw to the imported model root so the visible
## front face lands on -Z (matching the driving math at BaseVehicle._kinematic_move,
## which uses `fwd := -global_transform.basis.z`). Any car whose source asset is
## already authored facing -Z can opt out by setting this to 0.0 in _ready().
var _model_front_axis_correction_deg : float = 180.0
## Pitch correction for source assets authored in a Z-up DCC (Blender, 3DS)
## that ended up imported tipped onto their nose or tail. Default 0 = no
## pitch correction (assets that import flat). Applied to the same
## FrontAxisCorrection wrap that handles the front-axis yaw, so wheel
## VehicleWheel3D nodes (children of self, NOT of the wrap) keep their
## upright collision and don't tilt with the body.
var _model_pitch_correction_deg : float = 0.0

func load_model() -> void:
	if _model_path == "" or not ResourceLoader.exists(_model_path):
		push_warning("[Car] model not imported yet at %s — using proxy box." % _model_path)
		return
	var packed := load(_model_path)
	if packed == null or not (packed is PackedScene):
		return
	var root : Node = (packed as PackedScene).instantiate()
	# VISUAL FRONT RULE — wrap the imported model in a Node3D carrying the
	# correction yaw so the visible front face lands on local -Z (canonical
	# CeDo forward). Default 180° handles assets authored facing +Z (most of
	# them). A subclass can set _model_front_axis_correction_deg = 0.0 to opt
	# out. The wrap keeps the imported tree's INTERNAL coords intact, so the
	# part walker, paint matcher, door pivots, and wheel articulation see the
	# same geometry they always did — only the entire assembly is yawed under
	# self.
	if root is Node3D and (not is_zero_approx(_model_front_axis_correction_deg) \
			or not is_zero_approx(_model_pitch_correction_deg)):
		var wrap := Node3D.new()
		wrap.name = "FrontAxisCorrection"
		# Assign rotation as a Vector3 in one shot — assigning .x then .y in
		# sequence would clobber the first (rotation IS a Vector3 property).
		wrap.rotation = Vector3(
			deg_to_rad(_model_pitch_correction_deg),
			deg_to_rad(_model_front_axis_correction_deg),
			0.0)
		wrap.add_child(root)
		root = wrap
	# V2 — auto-ruler. Measure the imported model's AABB and rescale uniformly so
	# its longest horizontal extent equals _real_world_length_m. This fixes the
	# "huge cars" complaint without needing per-car magic-number scales; subclasses
	# just declare their real-world length and the rescale falls out from geometry.
	# Combined with subclass _model_scale (a per-axis multiplier for stylistic
	# squishes like Streetka's 0.85 Y), so order matters: AUTO-RULER FIRST, then
	# the artistic squish on top.
	if root is Node3D and _real_world_length_m > 0.01:
		var auto : float = _measure_model_scale(root as Node3D, _real_world_length_m)
		# Floor is 1e-4, NOT 0.01. The old `auto > 0.01` guard silently rejected
		# the Hyundai i20: its GLB is authored in centimetres (394.73 m raw), so
		# the correct factor is 3.94/394.73 = 0.00998 — a hair BELOW 0.01 — and
		# the car spawned 100x life size with no warning. The ford_ka only worked
		# by luck (3.62/362 = 0.01000, a hair ABOVE). The floor only needs to
		# reject degenerate zero-ish factors; _measure_model_scale already
		# returns 1.0 for sub-centimetre AABBs.
		if auto > 0.0001 and not is_equal_approx(auto, 1.0):
			(root as Node3D).scale = (root as Node3D).scale * auto
			# The VehicleWheel3D nodes are CHILDREN OF self (the Car), not of the
			# imported model root. Scaling the imported model alone leaves the
			# wheels (and their procedural WheelMesh placeholders) at full
			# FBX-tuned size, which renders as huge dark cylinders at the corners
			# of an undersized car body. Apply the same scale to the wheel
			# transforms (position pulls in toward the scaled body's corners),
			# their wheel_radius (so physics matches visuals), and any
			# WheelMesh child (so the procedural placeholder shrinks too).
			_scale_vehicle_wheels(auto)
			print("[Car] %s auto-scaled by %.4f to %.2f m" % [_model_path.get_file(), auto, _real_world_length_m])
		elif auto <= 0.0001:
			# Never skip silently again — a silent skip is how a 395 m car
			# reached the operator's car park.
			push_warning("[Car] %s auto-scale REJECTED (factor %.6f) — model left at raw size!"
				% [_model_path.get_file(), auto])
	# #155 — subclass can override _model_scale (default 1,1,1) to squish the
	# imported GLB vertically — e.g. Pascal's Streetka uses the Ka GLB at
	# y=0.85 to read as the lower droptop convertible variant. Multiplied ON TOP of
	# the auto-rescale so the AABB still ends at _real_world_length_m horizontally.
	if root is Node3D and (_model_scale != Vector3.ONE):
		(root as Node3D).scale = (root as Node3D).scale * _model_scale
	add_child(root)
	# #157 — pre-classify hook. Pack-car placeholders (Golf / Volvo-as-Astra /
	# BMW-as-AClass) override this to prune the 9 unwanted cars FIRST, so the
	# wheel/door classifier in _walk_model only sees the target car's parts
	# and proximity-based articulation can't steal wheels from neighbours.
	if has_method("_filter_imported_tree"):
		call("_filter_imported_tree", root)
	_walk_model(root)
	if _paint_color.a > 0.001:
		_paint_hit_any = false
		_paint_body(self)
		# Fallback for FBXs that lack named materials (e.g. the Swift).
		_paint_fallback_apply(root)
	_articulate_wheels()
	_articulate_doors_generic()
	_articulate_glass()
	_articulate_steering()
	_place_passenger_seat()
	# Per-subclass post-load hook. Lets a subclass that needs extra wiring
	# (e.g. Swift's driver-door / passenger-door proximity triggers) plug in
	# AFTER the canonical wrap + auto-ruler + classify path has finished —
	# so each car script no longer has to duplicate the whole loader/walker.
	_post_load_hook()

## Subclass override point — called by load_model() after wheels/doors/glass/
## steering/seat have all been wired. Default no-op.
func _post_load_hook() -> void:
	pass

## Look up the wrapped door pivots that were created by _articulate_doors_generic.
## Subclasses use this to install door-proximity triggers without re-walking
## the imported tree themselves.
func get_door_pivots() -> Array:
	var out : Array = []
	for d in _car_doors:
		var p = d.get("pivot")
		if p is Node3D:
			out.append(p)
	return out

## V2 — Walk every MeshInstance3D under root, compute the union AABB in the
## root's local frame, return the uniform-scale factor needed so the longest
## horizontal extent (max of X, Z) equals target_length_m. Returns 1.0 if the
## tree has no meshes or zero size. Y is excluded so very-tall cars (campers)
## don't pull the wrong axis.
func _measure_model_scale(root: Node3D, target_length_m: float) -> float:
	# The recursive helper can't mutate `has_any` via return-by-reference in GDScript;
	# do the walk again with a wrapper Dictionary to get the result back.
	var acc : Dictionary = {"aabb": AABB(), "any": false}
	_aabb_walk(root, Transform3D.IDENTITY, acc)
	if not bool(acc["any"]):
		return 1.0
	var box : AABB = acc["aabb"]
	var extent_x : float = box.size.x
	var extent_z : float = box.size.z
	var longest : float = maxf(extent_x, extent_z)
	if longest < 0.01:
		return 1.0
	return target_length_m / longest

## Recursive AABB accumulator. `xf` is the cumulative transform from root to
## node. acc["aabb"] is built up, acc["any"] flips true on first hit.
func _aabb_walk(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	var child_xf : Transform3D = xf
	if node is Node3D:
		child_xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var local : AABB = (node as MeshInstance3D).mesh.get_aabb()
		var world_box : AABB = child_xf * local
		if not bool(acc["any"]):
			acc["aabb"] = world_box
			acc["any"] = true
		else:
			acc["aabb"] = (acc["aabb"] as AABB).merge(world_box)
	for c in node.get_children():
		_aabb_walk(c, child_xf, acc)

## Apply the FBX auto-rescale factor to every VehicleWheel3D under this Car so
## the wheels match the new body length. Each wheel's local position scales
## (so they sit at the new corner positions), its wheel_radius / suspension
## travel scales (so physics matches the visuals), and any procedural WheelMesh
## child scales uniformly. Imported tyre meshes attached later by
## _articulate_wheels inherit the parent VehicleWheel3D's scale via add_child +
## Transform3D.IDENTITY, so they end up right-sized for free.
func _scale_vehicle_wheels(factor: float) -> void:
	if factor <= 0.01 or is_equal_approx(factor, 1.0):
		return
	for c in get_children():
		if c is VehicleWheel3D:
			var vw : VehicleWheel3D = c
			vw.position *= factor
			vw.wheel_radius = vw.wheel_radius * factor
			vw.suspension_travel = vw.suspension_travel * factor
			vw.wheel_rest_length = vw.wheel_rest_length * factor
			# Scale the procedural placeholder mesh (visible only when
			# _articulate_wheels can't find an FBX wheel to attach).
			var wheel_mesh := vw.get_node_or_null("WheelMesh") as Node3D
			if wheel_mesh != null:
				wheel_mesh.scale = wheel_mesh.scale * factor

func _walk_model(n: Node) -> void:
	if n is Node3D:
		_classify(n as Node3D)
	for c in n.get_children():
		_walk_model(c)

func _classify(n: Node3D) -> void:
	var nm := n.name.to_lower()
	for category in _part_names:
		for needle in _part_names[category]:
			if nm.contains(needle):
				var arr : Array = _parts.get(category, [])
				arr.append(n)
				_parts[category] = arr
				return

## Returns true if at least one mesh surface was painted by name match.
var _paint_hit_any : bool = false

func _paint_body(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var mnm := String(mat.resource_name).to_lower()
				var hit : bool = mnm.contains("paint") or mnm.contains("body") or mnm.contains("lack")
				if not hit:
					for needle in _paint_extra_match:
						if mnm.contains(String(needle).to_lower()):
							hit = true
							break
				if hit:
					var tinted := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					tinted.albedo_color = _paint_color
					mi.set_surface_override_material(i, tinted)
					_paint_hit_any = true
	for c in n.get_children():
		_paint_body(c)

## #157 — Swift fallback. When name-based matching found nothing AND the
## subclass opted in via _paint_fallback_largest_mesh, tint the largest mesh
## (by AABB volume) under the imported body. Crude but works for single-mesh
## FBX imports where the body is one big mesh covering most of the silhouette.
var _scan_best_mesh : MeshInstance3D = null
var _scan_best_vol  : float = -1.0

func _paint_fallback_apply(root: Node) -> void:
	if not _paint_fallback_largest_mesh or _paint_hit_any:
		return
	_scan_best_mesh = null
	_scan_best_vol = -1.0
	_find_largest_mesh(root)
	if _scan_best_mesh == null:
		return
	var mi := _scan_best_mesh
	for i in mi.mesh.get_surface_count():
		# Skip surfaces that already have a transparent override applied by
		# _articulate_glass — otherwise the fallback paints glass red. Same
		# safety for any other prior override that set transparency.
		var existing_override : Material = mi.get_surface_override_material(i)
		if existing_override is StandardMaterial3D \
				and (existing_override as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var base_mat := mi.mesh.surface_get_material(i)
		var mat : StandardMaterial3D
		if base_mat is StandardMaterial3D:
			mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			mat = StandardMaterial3D.new()
		mat.albedo_color = _paint_color
		mat.metallic = 0.30
		mat.roughness = 0.35
		mi.set_surface_override_material(i, mat)
	_paint_hit_any = true

func _find_largest_mesh(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var ab : AABB = (n as MeshInstance3D).mesh.get_aabb()
		var vol : float = ab.size.x * ab.size.y * ab.size.z
		if vol > _scan_best_vol:
			_scan_best_vol = vol
			_scan_best_mesh = n as MeshInstance3D
	for c in n.get_children():
		_find_largest_mesh(c)

func _articulate_wheels() -> void:
	var vwheels : Array = []
	for c in get_children():
		if c is VehicleWheel3D:
			vwheels.append(c)
	if vwheels.is_empty():
		return
	var found : Array = []
	for key in ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr", "wheel"]:
		if _parts.has(key):
			for w in _parts[key]:
				if not found.has(w):
					found.append(w)
	for w in found:
		var wn := w as Node3D
		if wn == null:
			continue
		var best : VehicleWheel3D = null
		var best_d := 1e9
		for vw in vwheels:
			var d : float = (vw as Node3D).global_position.distance_to(wn.global_position)
			if d < best_d:
				best_d = d
				best = vw
		if best == null:
			continue
		if wn.get_parent():
			wn.get_parent().remove_child(wn)
		best.add_child(wn)
		wn.transform = Transform3D.IDENTITY
		var proc_mesh := best.get_node_or_null("WheelMesh")
		if proc_mesh:
			(proc_mesh as Node3D).visible = false

func _articulate_doors_generic() -> void:
	var doors : Array = []
	for key in ["door_fl", "door_fr", "door_rl", "door_rr"]:
		if _parts.has(key):
			for d in _parts[key]:
				doors.append(d)
	if doors.is_empty() and _parts.has("door"):
		for d in _parts["door"]:
			doors.append(d)
	var wrapped : Array = []
	for d in doors:
		var p := _wrap_door_pivot(d as Node3D)
		if p != null:
			wrapped.append(p)
	articulate_doors(wrapped, 65.0)

func _wrap_door_pivot(panel: Node3D) -> Node3D:
	if panel == null or panel.get_parent() == null:
		return null
	var parent := panel.get_parent()
	var pivot := Node3D.new()
	pivot.name = "%s_Pivot" % panel.name
	var panel_w : Transform3D = panel.global_transform
	parent.add_child(pivot)
	pivot.global_transform = panel_w
	parent.remove_child(panel)
	pivot.add_child(panel)
	panel.transform = Transform3D.IDENTITY
	panel.position.z = -0.40
	return pivot

func _articulate_glass() -> void:
	if not _parts.has("glass"):
		return
	for g in _parts["glass"]:
		var gm := g as MeshInstance3D
		if gm == null or gm.mesh == null:
			continue
		for i in gm.mesh.get_surface_count():
			var base_mat := gm.mesh.surface_get_material(i)
			var mat : StandardMaterial3D
			if base_mat is StandardMaterial3D:
				mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
				mat.albedo_color = Color(0.80, 0.86, 0.90)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var c := mat.albedo_color
			c.a = 0.28
			mat.albedo_color = c
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.metallic = 0.10
			mat.roughness = 0.06
			gm.set_surface_override_material(i, mat)

func _articulate_steering() -> void:
	if _parts.has("steering") and not (_parts["steering"] as Array).is_empty():
		_steering_node = (_parts["steering"] as Array)[0]
		if _steering_node != null:
			var b := _steering_node.transform.basis
			if not (b.x.is_finite() and b.y.is_finite() and b.z.is_finite()) \
					or b.determinant() < 1e-6:
				_steering_node.transform.basis = Basis()

func _place_passenger_seat() -> void:
	if _passenger_seat == null or not _parts.has("seat"):
		return
	var right_seat : Node3D = null
	for s in _parts["seat"]:
		var sn := s as Node3D
		if sn == null:
			continue
		if right_seat == null or sn.global_position.x > right_seat.global_position.x:
			right_seat = sn
	if right_seat != null:
		_passenger_seat.global_position = right_seat.global_position + Vector3(0.0, 0.45, 0.0)

# Default part-name dictionary — subclass can override _part_names entirely if
# its FBX/GLB uses different naming conventions.
const DEFAULT_PART_NAMES := {
	"door_fl":   ["door_fl", "door_lf", "door_front_l", "frontleftdoor", "leftfrontdoor"],
	"door_fr":   ["door_fr", "door_rf", "door_front_r", "frontrightdoor", "rightfrontdoor"],
	"door_rl":   ["door_rl", "door_lr", "door_rear_l", "rearleftdoor", "leftreardoor"],
	"door_rr":   ["door_rr", "door_rear_r", "rearrightdoor", "rightreardoor"],
	"door":      ["door", "porte", "tuer"],
	"wheel_fl":  ["wheel_fl", "wheel_lf", "wheel_front_l", "front_left_wheel"],
	"wheel_fr":  ["wheel_fr", "wheel_rf", "wheel_front_r", "front_right_wheel"],
	"wheel_rl":  ["wheel_rl", "wheel_lr", "wheel_rear_l", "rear_left_wheel"],
	"wheel_rr":  ["wheel_rr", "wheel_rear_r", "rear_right_wheel"],
	"wheel":     ["wheel", "tire", "tyre", "roue", "rad"],
	"glass":     ["glass", "window", "windshield", "windscreen", "vitre"],
	"steering":  ["steering", "volant", "lenkrad"],
	"seat":      ["seat", "siege"],
	"body":      ["body", "chassis", "carrosserie", "shell"],
}
