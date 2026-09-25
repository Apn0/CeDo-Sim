class_name LumpCart
extends RigidBody3D

# #98 — Operator grabs the lump_cart by its push-handle (crosshair + E). While
# grabbed, the cart's handle position tracks ~0.9m in front of the player at
# handle height, and yaws to face away from the player. Real-life mass is ~40 kg
# (bumped from 12 once handle-grab steering existed — walking-into-it shove had
# to stay possible at 12 kg, but with active grab the operator can drag and steer
# the full real weight).
#
# Release: press E again, OR walk further than RELEASE_DIST from the cart.

const HANDLE_LOCAL := Vector3(0.0, 0.78, 0.62)   # ~ handle grip in cart-local space
const HOLD_DIST    : float = 0.95                 # cart sits this far in front of player
const STIFF        : float = 14.0                 # how hard the cart chases the target
const YAW_STIFF    : float = 6.0
const RELEASE_DIST : float = 2.6
# phys-05 interim (2026-09-23): the hard ceiling on how fast this cart can ever
# travel, enforced in _integrate_forces. The vehicles are frozen-kinematic
# bodies with infinite mass (BACKLOG phys-05), so a cart caught between a
# forklift and a wall used to be squeezed out at whatever velocity the solver
# needed to resolve the overlap — tens of m/s across the hall. A hand-pushed
# cart tops out at ~1.8 m/s (see _max_speed_for_load) and a forklift shoving
# one at ~4 m/s; 6 m/s keeps every legitimate push untouched and turns an
# ejection into a shove. Measured with the clamp disabled: a 50 m/s impulse
# left the cart at 48.09 m/s; with it, 5.76 m/s (test_lump_cart_speed_clamp).
# Angular velocity is capped the same way (a cart does not spin like a top:
# 53.33 → 5.58 rad/s). The real fix — an AnimatableBody chassis — is still
# phys-05.
const MAX_SPEED    : float = 6.0
const MAX_SPIN_RAD : float = 6.0     # ~1 rev/s

var _grabbed_by : Node3D = null

# =============================================================================
# #198 — Fill + cool-down state.
# =============================================================================
# Lumps drop in from the laser-filter discharge hose (operator's spec). Each
# lump is hot (~120-180 °C) when extruded; the cart sits under the discharge
# accumulating lumps until either (a) it's full or (b) the line stops pushing.
# Once a lump is in the cart it cools to ambient over COOL_TIME_S (1-3 hours
# sim time). When ALL contents are cool AND the cart has at least
# EMPTY_THRESHOLD_KG of lumps in it, the NpcAutonomyBoard emits an
# "empty_lump_cart" task — an idle NPC will then grab a forklift, drive over,
# lift the cart, transport it to the indoor lumps_container, and dump.
# Operator-recalculated 2026-07-11: a full Lumpenwagen holds ~90 kg of lumps,
# with a small heap over the rim before the discharge truly can't add more.
const CAPACITY_KG       : float = 100.0   # hard cap — heaped a little over the top
const FULL_THRESHOLD_KG : float = 90.0    # above this → "is_full" → block more lumps
const EMPTY_THRESHOLD_KG: float = 20.0    # above this → worth emptying (don't haul ~empty carts)
const COOL_TIME_S_MIN   : float = 60.0 * 60.0   #  1 sim-hour minimum cool-down
const COOL_TIME_S_MAX   : float = 3.0 * 60.0 * 60.0   # 3 sim-hour worst case

const EMPTY_MASS_KG   : float = 40.0     # bare cart (steel dumpster + wheels)

var lumps_kg          : float = 0.0
var _last_received_at : float = -INF     # sim-time of the most recent lump
var _cool_time_s      : float = COOL_TIME_S_MIN   # randomised per receive

## Physics mass tracks the load: bare cart + whatever lumps are in it. A cart
## with 200 kg of lumps genuinely pushes/steers like 240 kg, not like an empty
## one. Called after every fill/dump so the RigidBody the player shoves and the
## forklift lifts feels the real weight.
func _sync_mass() -> void:
	mass = EMPTY_MASS_KG + lumps_kg
	_update_heap()

func is_full() -> bool:
	return lumps_kg >= FULL_THRESHOLD_KG

func has_lumps_worth_emptying() -> bool:
	return lumps_kg >= EMPTY_THRESHOLD_KG

## Lumps are cool when at least _cool_time_s has passed since the last lump
## landed. Returns false if there's nothing in the cart (no point emptying).
func is_cool() -> bool:
	if lumps_kg <= 0.001:
		return false
	var now_s : float = _now_sim_s()
	return (now_s - _last_received_at) >= _cool_time_s

## Called by the laser-filter discharge when a lump drops into this cart.
## Returns the kg the cart could NOT take (0.0 normally).
##
## P6 (2026-09-23). This used to `return` at is_full() with the comment "when
## full, the discharge backs up / overflows on the floor — but the simulator
## doesn't model that yet ... the upstream filter will see is_full() and stop
## pushing". Neither half was true: nothing in LaserFilter ever read is_full(),
## so every purge into a full cart was credited to lumps_kg_this_shift and then
## vanished. Now the refused kg is RETURNED and LaserFilter._disc_advance()
## puts it on the floor as a FloorPile beside the cart (the operator's spec),
## so cart + floor == what the scraper shed. Per the operator's 2026-07-11
## figures a full cart is FULL_THRESHOLD_KG (90, "is_full" — worth emptying)
## and CAPACITY_KG (100) is where the discharge "truly can't add more": the
## last 10 kg heap over the rim and are still accepted; past that, refused.
func receive_lump(mass_kg: float) -> float:
	if mass_kg <= 0.0:
		return 0.0
	var room : float = maxf(0.0, CAPACITY_KG - lumps_kg)
	var accepted : float = minf(mass_kg, room)
	if accepted <= 0.0:
		return mass_kg
	lumps_kg += accepted
	_sync_mass()
	_last_received_at = _now_sim_s()
	# Each receive resets the cool-down with a fresh random sample in [min,max].
	_cool_time_s = randf_range(COOL_TIME_S_MIN, COOL_TIME_S_MAX)
	return mass_kg - accepted

## Called by the EmptyLumpCartTask after the forklift dumps the cart into the
## lumps_container. Returns how many kg were dumped (so the receiving container
## can grow its own fill level by that amount).
func empty() -> float:
	var dumped : float = lumps_kg
	lumps_kg = 0.0
	_sync_mass()
	_last_received_at = -INF
	return dumped

# ── phys-04 — fill state survives save/load ──────────────────────────────────
# BuildMode._save_layout persists lumps_kg + cool_remaining_s() per cart; the
# load path calls restore_fill(). Without this a full 90 kg cart reloaded
# empty: mass conservation violated, the "is_full → discharge blocked" state
# reset, and the pending empty_lump_cart task chain evaporated.

## Remaining cool-down seconds for the current load (0 = already cool or empty).
func cool_remaining_s() -> float:
	if lumps_kg <= 0.001 or _last_received_at == -INF:
		return 0.0
	return maxf(0.0, _cool_time_s - (_now_sim_s() - _last_received_at))

## Put a persisted fill back after a reload. Re-anchors the cool timer at "now"
## so exactly `cool_left_s` seconds remain (a hot cart reloads hot; a cool one
## is immediately eligible for the empty_lump_cart task again).
func restore_fill(kg: float, cool_left_s: float) -> void:
	lumps_kg = clampf(kg, 0.0, CAPACITY_KG)
	_sync_mass()
	if lumps_kg <= 0.001:
		_last_received_at = -INF
		return
	_cool_time_s = maxf(cool_left_s, 0.0)
	_last_received_at = _now_sim_s()

## Resume on load (operator 2026-09-25, rulings file §R1-§R3;
## src/sim/PlantResume.gd). The factory entry still carries lumps_kg /
## cool_left_s and BuildMode still restores them at once, for mass. This runs
## again after the shift clock has loaded, and re-anchors the cool timer there:
## at BuildMode's load the clock still reads its pre-load time, so a cart
## anchored then read as cool as soon as the loaded shift time moved past it.
func save_run_state() -> Dictionary:
	if lumps_kg <= 0.001:
		return {}
	return {"lumps_kg": lumps_kg, "cool_left_s": cool_remaining_s()}

func restore_run_state(d: Dictionary) -> void:
	restore_fill(float(d.get("lumps_kg", 0.0)), float(d.get("cool_left_s", 0.0)))

## Sim time in seconds since the ShiftClock's day-zero epoch. Falls back to the
## wall-clock if the shift clock isn't reachable (test scenes).
## The ShiftClock is looked up ONCE and cached: this used to run
## find_child(recursive) over the whole tree (~9k nodes in a booted world) on
## every call, and is_cool()/cool_remaining_s() are polled by the autonomy
## board for every cart, plus once a second by the heap colour below.
var _shift_clock : Node = null
var _shift_clock_looked_up : bool = false
func _now_sim_s() -> float:
	if not _shift_clock_looked_up or (_shift_clock != null and not is_instance_valid(_shift_clock)):
		_shift_clock_looked_up = true
		_shift_clock = null
		var root : Node = get_tree().get_root() if is_inside_tree() else null
		if root != null:
			var sc := root.find_child("ShiftClock", true, false)
			if sc != null and "shift_elapsed_seconds" in sc:
				_shift_clock = sc
	if _shift_clock != null:
		return float(_shift_clock.shift_elapsed_seconds)
	return Time.get_ticks_msec() / 1000.0

# =============================================================================
# P6 (2026-09-23) — the fill is VISIBLE: a heap grows inside the bucket with
# lumps_kg. Its footprint is MEASURED from the cart's own collision boxes (the
# floor plate and the walls PlaceableCatalog._lump_cart_compound_collision
# builds), never copied from the catalog's constants — a copied number is how
# stale-constant disease starts (CLAUDE.md). The heap reaches the rim at
# FULL_THRESHOLD_KG and heaps a little over it toward CAPACITY_KG (operator
# 2026-07-11: "a small heap over the rim before the discharge truly can't add
# more"). Colour runs from the rope's hot orange to its cooled grey on the
# cart's own cool-down clock, so a fresh load reads hot from across the hall.
# =============================================================================
const HEAP_HOT_COLOR       : Color = Color(1.00, 0.32, 0.06)   # = LaserFilter.SAUSAGE_HOT_COLOR
const HEAP_COOL_COLOR      : Color = Color(0.18, 0.16, 0.14)   # = LaserFilter.SAUSAGE_COOL_COLOR
const HEAP_COLOR_REFRESH_S : float = 1.0
var _heap        : MeshInstance3D = null
var _heap_mat    : StandardMaterial3D = null
var _bucket      : Dictionary = {}    # w, d, floor_top_y, h_max — see _measure_bucket()
var _heap_color_t : float = 0.0

func _ready() -> void:
	_build_heap()
	_update_heap()

## Interior of the bucket, read off the CollisionShape3D boxes on this body:
## the floor plate is the thin (<= 3 cm) box wider than half a metre, the walls
## are the tallest boxes and the thinner of their two horizontal extents is the
## wall thickness. Empty when the body carries no such shapes (a bare script
## instance in a probe) — then there is nothing to size a heap against.
func _measure_bucket() -> Dictionary:
	var plate_size := Vector3.ZERO
	var plate_pos  := Vector3.ZERO
	var wall_h := 0.0
	var wall_t := 0.0
	var wall_top := 0.0
	for c in get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var sz : Vector3 = (cs.shape as BoxShape3D).size
		if sz.y <= 0.03 and sz.x > 0.5 and sz.x > plate_size.x:
			plate_size = sz
			plate_pos  = cs.position
		if sz.y > wall_h:
			wall_h = sz.y
			wall_t = minf(sz.x, sz.z)
			wall_top = cs.position.y + sz.y * 0.5
	if plate_size.x <= 0.0 or wall_h <= 0.0:
		return {}
	var floor_top : float = plate_pos.y + plate_size.y * 0.5
	# The rim is the walls' TOP FACE minus the plate's top face — not the wall
	# box height: the catalog's wall boxes start at the plate's centre, so they
	# overlap it by half a plate (measured 1.25 cm, test_lump_cart_overflow S2).
	return {
		"w": maxf(plate_size.x - 2.0 * wall_t - 0.01, 0.05),
		"d": maxf(plate_size.z - 2.0 * wall_t - 0.01, 0.05),
		"floor_top_y": floor_top,
		"h_max": maxf(wall_top - floor_top, 0.01),
	}

func _build_heap() -> void:
	if _heap != null:
		return
	_bucket = _measure_bucket()
	if _bucket.is_empty():
		return
	_heap = MeshInstance3D.new()
	_heap.name = "LumpHeap"
	var box := BoxMesh.new()
	box.size = Vector3(float(_bucket["w"]), 0.01, float(_bucket["d"]))
	_heap.mesh = box
	_heap_mat = StandardMaterial3D.new()
	_heap_mat.albedo_color = HEAP_COOL_COLOR
	_heap_mat.roughness = 0.85
	_heap.material_override = _heap_mat
	_heap.visible = false
	add_child(_heap)

## Height of the visible load: the rim at FULL_THRESHOLD_KG, heaped a little
## over it up to CAPACITY_KG. 0 when the bucket could not be measured.
func heap_height_m() -> float:
	if _bucket.is_empty():
		return 0.0
	var frac : float = clampf(lumps_kg / FULL_THRESHOLD_KG, 0.0, CAPACITY_KG / FULL_THRESHOLD_KG)
	return frac * float(_bucket["h_max"])

func _update_heap() -> void:
	if _heap == null:
		return
	var h := heap_height_m()
	if h <= 0.001:
		_heap.visible = false
		return
	var box := _heap.mesh as BoxMesh
	box.size = Vector3(float(_bucket["w"]), h, float(_bucket["d"]))
	_heap.position = Vector3(0.0, float(_bucket["floor_top_y"]) + h * 0.5, 0.0)
	_heap.visible = true
	_refresh_heap_color()

## 1.0 = the newest lump just landed (hot), 0.0 = cooled through the cart's own
## cool-down clock. The whole heap takes the colour of the latest arrival — a
## stated simplification (the real top layer is hot, the bottom has cooled).
func heap_hot_fraction() -> float:
	if lumps_kg <= 0.001 or _cool_time_s <= 0.0:
		return 0.0
	return clampf(cool_remaining_s() / _cool_time_s, 0.0, 1.0)

func _refresh_heap_color() -> void:
	if _heap_mat == null:
		return
	var hot := heap_hot_fraction()
	_heap_mat.albedo_color = HEAP_COOL_COLOR.lerp(HEAP_HOT_COLOR, hot)
	_heap_mat.emission_enabled = hot > 0.01
	_heap_mat.emission = HEAP_HOT_COLOR
	_heap_mat.emission_energy_multiplier = lerpf(0.0, 1.2, hot)

func crosshair_prompt(_p: Node3D) -> String:
	if _grabbed_by != null:
		return "Lumpenwagen loslaten [E]"
	return "Lumpenwagen pakken aan handvat [E]"

# ── #223 audit (critical): force-based grab — no more velocity teleport ──────
# The old chase ASSIGNED linear_velocity every tick, which (a) ignored mass —
# a 140 kg full cart snapped to 3.5 m/s exactly like an empty one, and (b)
# overwrote the contact solver's blocking response 60×/s, which is precisely
# why a cart with wheels embedded in the concrete could still be dragged.
# Now the grab applies a CAPPED FORCE (what two hands on a cart handle can
# sustain) and a capped yaw torque; the solver keeps the final word, so an
# embedded or jammed cart stalls against the geometry like it should.
#
# While grabbed, the cart "rolls" — friction drops from the parked 0.9 to a
# rolling-resistance value (castor wheels turning) and the parked damping is
# eased, so the ~350 N hand force actually moves it. Restored on release, so
# a parked cart doesn't creep on belt/vehicle nudges.
const GRAB_PUSH_FORCE_N  : float = 350.0   # sustained two-hand push/pull on a cart handle
const GRAB_YAW_TORQUE_NM : float = 120.0
const ROLLING_FRICTION   : float = 0.04    # castor wheels rolling
const GRAB_LINEAR_DAMP   : float = 0.3
var _parked_friction : float = -1.0        # cached pre-roll values (restored on exit)
var _parked_damp     : float = -1.0

# ── phys-01 — body-shove enters the same rolling state as the grab ───────────
# KinematicPush pokes notify_body_push() on slide contact. The parked friction
# 0.9 caps a per-tick friction impulse of mu*g*dt = 0.147 m/s — more than the
# push delivers at walk (0.046) or sprint (0.101) — so without this the
# "shove it by walking into it" promised at the catalog spawn comment was a
# bolted-down wall. The cart rolls while being pushed and re-parks
# PUSH_ROLL_TIMEOUT_S after the last shove, keeping the belt/vehicle-nudge
# creep protection the high parked friction exists for.
const PUSH_ROLL_TIMEOUT_S : float = 0.5
var _push_roll_left : float = 0.0

func crosshair_interact(player: Node3D) -> void:
	if _grabbed_by == null:
		_grabbed_by = player
		sleeping = false
		_enter_rolling()
	else:
		_release()

## phys-01 — called by KinematicPush when a walking body (player / NPC /
## feeder) shoves the cart. Grab keeps priority: its controller owns the state.
func notify_body_push() -> void:
	if _grabbed_by != null:
		return
	sleeping = false
	_enter_rolling()
	_push_roll_left = PUSH_ROLL_TIMEOUT_S

func _enter_rolling() -> void:
	if _parked_friction >= 0.0:
		return   # already rolling — don't cache the rolling values as "parked"
	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
	_parked_friction = physics_material_override.friction
	_parked_damp = linear_damp
	physics_material_override.friction = ROLLING_FRICTION
	linear_damp = GRAB_LINEAR_DAMP

func _release() -> void:
	_grabbed_by = null
	_exit_rolling()

## Restore the parked friction/damp cached by _enter_rolling (shared by grab
## release and the phys-01 push-decay timer) and clear the caches so the next
## _enter_rolling re-samples them.
func _exit_rolling() -> void:
	if _parked_friction >= 0.0 and physics_material_override != null:
		physics_material_override.friction = _parked_friction
	if _parked_damp >= 0.0:
		linear_damp = _parked_damp
	_parked_friction = -1.0
	_parked_damp = -1.0
	_push_roll_left = 0.0

## Loaded carts can't be walked as fast as empty ones: max towing speed
## derates from a brisk push (empty) to a heavy trudge (full).
func _max_speed_for_load() -> float:
	return lerpf(1.8, 1.1, clampf(lumps_kg / CAPACITY_KG, 0.0, 1.0))

## phys-05 interim — see MAX_SPEED. Runs after the solver has integrated the
## step, so a squeeze-eject impulse is clamped before it moves the cart.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var v := state.linear_velocity
	var sp := v.length()
	if sp > MAX_SPEED:
		state.linear_velocity = v * (MAX_SPEED / sp)
	var w := state.angular_velocity
	var ws := w.length()
	if ws > MAX_SPIN_RAD:
		state.angular_velocity = w * (MAX_SPIN_RAD / ws)

func _physics_process(delta: float) -> void:
	# P6 — the heap cools visibly: refresh its tint once a second while loaded.
	if _heap != null and _heap.visible:
		_heap_color_t += delta
		if _heap_color_t >= HEAP_COLOR_REFRESH_S:
			_heap_color_t = 0.0
			_refresh_heap_color()
	# phys-01 — decay the body-shove rolling window: once nothing has pushed
	# for PUSH_ROLL_TIMEOUT_S the parked friction/damp come back.
	if _grabbed_by == null and _push_roll_left > 0.0:
		_push_roll_left -= delta
		if _push_roll_left <= 0.0:
			_exit_rolling()
	if _grabbed_by == null or not is_instance_valid(_grabbed_by):
		return
	var fwd : Vector3 = -_grabbed_by.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()
	var target : Vector3 = _grabbed_by.global_position + fwd * HOLD_DIST
	var handle_world : Vector3 = global_transform * HANDLE_LOCAL
	var to_target : Vector3 = target - handle_world
	to_target.y = 0.0
	# Desired velocity toward the handle target, capped by what a human can
	# actually walk while towing this load.
	var desired_v : Vector3 = to_target * STIFF
	var vmax : float = _max_speed_for_load()
	if desired_v.length() > vmax:
		desired_v = desired_v.normalized() * vmax
	# F = m·Δv/Δt, clamped to hand force. The solver integrates it — if the
	# cart is jammed against geometry, the force just stalls (realistic).
	var dv : Vector3 = desired_v - Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var force : Vector3 = dv * (mass / maxf(delta, 0.001))
	if force.length() > GRAB_PUSH_FORCE_N:
		force = force.normalized() * GRAB_PUSH_FORCE_N
	apply_central_force(force)
	# Yaw toward handle-away-from-player via capped torque (τ = I·α; the
	# cart's yaw inertia ≈ m·r² with r≈0.5 m footprint radius).
	var desired_yaw : float = atan2(fwd.x, fwd.z) + PI
	var yaw_err     : float = wrapf(desired_yaw - rotation.y, -PI, PI)
	var torque_y : float = clampf(yaw_err * YAW_STIFF * mass * 0.25,
		-GRAB_YAW_TORQUE_NM, GRAB_YAW_TORQUE_NM)
	apply_torque(Vector3(0.0, torque_y, 0.0))
	if global_position.distance_to(_grabbed_by.global_position) > RELEASE_DIST:
		_release()
