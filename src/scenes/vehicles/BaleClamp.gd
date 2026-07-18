extends BaseVehicle
class_name BaleClamp

## LPG bale clamp — vertical plates instead of forks. Picks bales up by friction
## between the two plates, NOT by snap-attaching them like the forklift. The
## strength of the grip depends on how hard the operator clamps (hold-to-build).
##
## Controls (reuses the forklift action set):
##   R / F  lift up / down
##   T / G  mast tilt back / forward
##   V      clamp open (also: release a currently-clamped bale)
##   B      tap   = clamp shut at LAST-SET force (default 50%)
##          hold  = force ramps 0 → 100% over CLAMP_RAMP_S; release sets it
##   Shift+B  cut the iron wires on the bale currently in the clamp,
##            but only if it is bulging (clamp_force ≥ wire_compliance) —
##            this is the "concrete scissors" action.
##
## Physics model (the bit that lets you lift the bottom of a 3-stack):
##   - Bales are RigidBody3D. Placed bales are FROZEN (freeze=true) so stacks
##     sit where the player put them and don't drift under gravity.
##   - On grab: we walk UP the stack from the grabbed bale, collecting every
##     bale sitting in the same vertical column. Those bales (and the one in
##     the plates) are reparented under the carry point — they ride along
##     kinematically with the clamp instead of fighting it with physics.
##     The clamp_force value gates whether we can grab at all: if it's below
##     the bale's clamp_force_needed, the grab fails silently (you didn't
##     squeeze hard enough). For multi-bale stacks the floor for "enough" is
##     scaled by stack height so a 3-tall stack needs ~3× the force of one.
##   - On release: the whole stack drops back as separate frozen rigid bodies
##     at the release position. Wires-cut bales also fan out into the sheet
##     arc described in _open_to_sheet_arc.
##   - The earlier Generic6DOFJoint3D approach was too unreliable for heavy
##     (459+ kg) RigidBody3D bales — the joint would soften under gravity and
##     drop the load, or jitter the vehicle. Reparenting works every time.
##
## Wire / cut model:
##   - Every bale comes wrapped in 3 iron wires (visible). meta `wires_cut`
##     starts false.
##   - When clamp_force ≥ meta.wire_compliance, the top wire segments visibly
##     bulge upward — that's the signal the wires are loose enough to cut.
##   - Shift+B (vehicle_wire_cut) cuts: removes the 3 Wire_i children from the
##     bale's Model.Wires node, sets meta.wires_cut=true, releases the joint
##     and re-clamps at the same force (so cutting doesn't drop the load).
##   - On release of a cut bale: each Sheet_i child detaches into its own
##     RigidBody3D with low friction so the bale falls open into an arc.

# ── Inspector wiring ──────────────────────────────────────────────────────────
@export_group("Clamp rig nodes")
@export var mast_pivot_path    : NodePath
@export var lift_carriage_path : NodePath
@export var left_plate_path    : NodePath
@export var right_plate_path   : NodePath

@export_group("Lift")
# #201 — Geometry: chassis origin sits at ground (wheel attach Y = 0.4, radius = 0.4).
# Plate chain: MastPivot(+0.40) → LiftCarriage(+lift_height_m) → LeftPlate
# (local +0.55) → mesh half-height 0.52 → plate-bottom local Y = 0.43 + lift_height_m.
# lift_min_m = -0.43 → plate flat on floor.
# lift_max_m =  2.57 → plate bottom 3.0 m up (reach for top of a 3-bale stack).
@export var lift_min_m              : float = -0.43
@export var lift_max_m              : float =  2.57
@export var lift_speed_no_load_m_s  : float = 0.60   # spec: 0.50–0.65 m/s unloaded
@export var lift_speed_full_load_m_s: float = 0.40   # spec: 0.30–0.45 m/s at rated 2 t

@export_group("Tilt")
@export var tilt_min_deg     : float = -6.0    # forward — was -8°, real-spec 3–6°
@export var tilt_max_deg     : float = 12.0
@export var tilt_speed_deg_s : float = 8.0     # spec: 6–10°/s

@export_group("Clamp")
# Bales ~1.1 × 1.2 × 1.4 m. Plates must clear 1.4 m wide bales with travel allowance.
@export var clamp_open_m    : float = 1.70
@export var clamp_closed_m  : float = 0.6
@export var clamp_speed_m_s : float = 0.15     # spec: 0.10–0.20 m/s (was 0.6 — way too fast)

@export_group("Load")
@export var max_safe_load_kg: float = 2000.0   # Cascade R-series class rated capacity

# ── Tunables ──────────────────────────────────────────────────────────────────
## Time to ramp clamp_force from 0 → 1 while B is held. Long on purpose — the
## operator should have time to FEEL how hard they're squeezing, so light grabs
## are easy to dial in (otherwise tap-to-grab always maxes out the force).
const CLAMP_RAMP_S       : float = 7.5
## How quickly the plates' visible gap reaches the target.
const PLATE_TRACK_RATE   : float = 6.0
## How far above the bale the top wire segments rise when bulging.
const WIRE_BULGE_M       : float = 0.04
## Hydraulic cylinder pump-flow ramp for the lift carriage. 0.3–0.6 s on a
## real LPG clamp. The plate-gap ramp (PLATE_TRACK_RATE) and clamp-force ramp
## (CLAMP_RAMP_S) are separate and already smooth.
const LIFT_RAMP_TAU_S : float = 0.45
const TILT_RAMP_TAU_S : float = 0.40

const SmoothedRateScript = preload("res://src/sim/SmoothedRate.gd")

# ── Runtime state ─────────────────────────────────────────────────────────────
var lift_height_m : float = -0.43   # plate flat on floor (#201)
var tilt_deg      : float = 0.0
var clamp_gap_m   : float = 1.35

## Locked-in clamp force in [0, 1]. Used by the wire bulge effect, the HUD
## force bar, and the grab gate (force < bale.clamp_force_needed = no grip).
var clamp_force        : float = 0.5
## True while the operator is holding B and the force is ramping up.
var _force_ramping     : bool  = false
# #161 — V key triggers a smooth force decay instead of a snap to 0. The plate
# gap follows clamp_force, so this gives the operator a visible "let go" — was
# instant zero before, which looked like nothing happened.
var _force_unramping   : bool  = false
var _ramp_started_at   : float = 0.0
var _ramp_start_force  : float = 0.0

var _lift_velocity : SmoothedRate = null
var _tilt_velocity : SmoothedRate = null

# (Stack pickup — _carried_stack / _carried_stack_orig_parents — now lives in
#  BaseVehicle so every vehicle lifts the bottom of a yard stack, not just this one.)

# Cached node lookups
var _mast_pivot    : Node3D
var _lift_carriage : Node3D
var _left_plate    : Node3D
var _right_plate   : Node3D

# ── #211e — Bale alignment ghost ──────────────────────────────────────────────
# Mirror of the forklift's ghost (see Forklift.gd) so the operator sees the
# same lengthwise-aligned target slab no matter which vehicle is carrying the
# bale. The bale clamp is the PRIMARY tool for moving bales onto the feed
# belt, so this is where the ghost matters most.
const GHOST_BELT_REACH_M      : float = 5.0
const GHOST_YAW_TOLERANCE_DEG : float = 15.0
const GHOST_BALE_LEN_M        : float = 1.4
const GHOST_BALE_WID_M        : float = 1.2
const GHOST_BALE_HGT_M        : float = 0.10
const GHOST_FLASH_HZ          : float = 2.5
var _bale_alignment_ghost : Node3D = null
var _ghost_mesh           : MeshInstance3D = null
var _ghost_mat            : StandardMaterial3D = null
var _ghost_flash_t        : float = 0.0

# =============================================================================
func _ready() -> void:
	# Drive-ramp tuning per the throttle/brake audit. The clamp + LPG-twin tank
	# rig is heavier than a bare forklift and operators drive it more cautiously
	# when bales are aboard — slowest spool-up of the lift fleet, ~1.1 s to top
	# speed. Brake matches the forklift's 16 m/s² (the load fights you).
	throttle_accel_mps2 = 3.0
	brake_decel_mps2    = 16.0
	coast_decel_mps2    = 4.0
	throttle_ramp_tau_s = 1.2
	brake_ramp_tau_s    = 0.3
	super._ready()
	vehicle_type = "bale_clamp"
	if mast_pivot_path:    _mast_pivot    = get_node_or_null(mast_pivot_path)    as Node3D
	if lift_carriage_path: _lift_carriage = get_node_or_null(lift_carriage_path) as Node3D
	if left_plate_path:    _left_plate    = get_node_or_null(left_plate_path)    as Node3D
	if right_plate_path:   _right_plate   = get_node_or_null(right_plate_path)   as Node3D
	_build_bale_alignment_ghost()
	# #201 — physicalize the plates. .tscn changed them to AnimatableBody3D with a
	# CollisionShape3D sibling matching the plate mesh (0.12 × 1.04 × 1.10).
	# Real bale-clamp plates have a heavy rubber/steel-stud face for grip; a
	# friction of ~1.6 lets clamp_force ≈ rated load hold a 250 kg bale via
	# normal-force × μ alone (no script-attach magic). Bounce is near zero so
	# the bale doesn't kick out when first squeezed.
	var plate_pm := PhysicsMaterial.new()
	plate_pm.friction = 1.6
	plate_pm.bounce   = 0.02
	if _left_plate is PhysicsBody3D:
		(_left_plate as PhysicsBody3D).physics_material_override = plate_pm
	if _right_plate is PhysicsBody3D:
		(_right_plate as PhysicsBody3D).physics_material_override = plate_pm
	_lift_velocity = SmoothedRateScript.new(0.0, LIFT_RAMP_TAU_S)
	_tilt_velocity = SmoothedRateScript.new(0.0, TILT_RAMP_TAU_S)

# =============================================================================
# INPUT — override the BaseVehicle V/B handlers so we get the force-ramp + cut
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not occupied:
		return
	# Tool-joystick: track LMB/RMB and route drag to the tool (lift / tilt) while
	# held, instead of the camera (shared BaseVehicle plumbing).
	if _track_tool_mouse(event):
		return
	# Mouse look — feed the camera rig (same path as BaseVehicle uses).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _camera_rig:
			_camera_rig.handle_mouse_look((event as InputEventMouseMotion).relative)
		return
	# Camera rig (F4 cycle / hold-F4 + arrows / hold-F4 + scroll). Let the rig
	# claim the event first — it's the same handler the BaseVehicle uses.
	if _camera_rig and _camera_rig.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	# Legacy P toggle also cycles modes
	if event.is_action_pressed("camera_toggle"):
		_camera_rig.cycle_mode()
		get_viewport().set_input_as_handled()
		return
	# H → switch the active LPG cylinder (bale-clamp dual-tank valve). The base
	# vehicle does the safe-handover (current level back to its tank, load
	# from the new one). H only does something while occupied + LPG-powered.
	if event.is_action_pressed("lpg_switch_active"):
		switch_active_lpg_tank()
		get_viewport().set_input_as_handled()
		return
	# B → start the force ramp; grab on release. (The Shift+B in-cab wire cut was
	# removed: cutting now happens ON FOOT with the WireCutter tool — realistic
	# flow, you have to exit the cab, grab the concrete scissors, and cut each
	# wire individually before re-entering the clamp to place + open the bale.)
	if event.is_action_pressed("forklift_forks_pinch"):
		_force_ramping    = true
		_force_unramping  = false   # #161 — pressing B mid-decay cancels the V un-ramp
		_ramp_started_at  = Time.get_ticks_msec() / 1000.0
		_ramp_start_force = clamp_force
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("forklift_forks_pinch"):
		if _force_ramping:
			# Lock in the held force, then close on the nearest bale
			var dt := Time.get_ticks_msec() / 1000.0 - _ramp_started_at
			clamp_force = clampf(_ramp_start_force + dt / CLAMP_RAMP_S, 0.0, 1.0)
			_force_ramping = false
			_try_grab()
		get_viewport().set_input_as_handled()
		return
	# V → open: release the bale (whole stack drops, cut bales fall to a sheet arc)
	if event.is_action_pressed("forklift_forks_widen"):
		_release()
		get_viewport().set_input_as_handled()
		return

# =============================================================================
# PHYSICS TICK — clamp / lift / tilt animation + plate tracking + bulge visuals
# =============================================================================
func _physics_process(delta: float) -> void:
	super._physics_process(delta)

	# Achterwielbesturing = A/D draait de neus de "verkeerde" kant op t.o.v. de auto logica.
	# We flippen de stuurhoek van alle sturende wielen om de BaseVehicle logica recht te trekken.
	for c in get_children():
		if c is VehicleWheel3D and c.use_as_steering:
			c.steering = -c.steering

	if occupied:
		_update_lift_tilt(delta)
		# While ramping, update clamp_force live so the HUD bar climbs
		if _force_ramping:
			var dt := Time.get_ticks_msec() / 1000.0 - _ramp_started_at
			clamp_force = clampf(_ramp_start_force + dt / CLAMP_RAMP_S, 0.0, 1.0)
	# #161 — V triggers a smooth force decay rather than snap-to-zero. Runs even
	# when un-occupied so a quit-out mid-clamp still relaxes naturally.
	if _force_unramping:
		clamp_force = maxf(0.0, clamp_force - delta / CLAMP_RAMP_S)
		if clamp_force <= 0.0:
			_force_unramping = false
	_update_plate_gap(delta)
	_apply_mast_lift_tilt()
	_update_wire_bulge()
	_update_bale_alignment_ghost(delta)

func _update_lift_tilt(delta: float) -> void:
	# Mouse-as-joystick: hold LEFT, drag Y = lift up/down, X = mast tilt.
	# (Clamp open/close + wire-cut stay on V / B / Shift+B.)
	var m := _tool_axes()

	var lift_axis := Input.get_action_strength("forklift_lift_up") \
				   - Input.get_action_strength("forklift_lift_down")
	# #201 — load-aware lift speed: a clamped bale slows the hydraulic.
	var load_ratio : float = 0.0
	if _carried_bale != null and is_instance_valid(_carried_bale) and "mass" in _carried_bale:
		load_ratio = clampf(float(_carried_bale.mass) / max_safe_load_kg, 0.0, 1.0)
	var lift_speed : float = lerpf(lift_speed_no_load_m_s, lift_speed_full_load_m_s, load_ratio)
	var target_lift_v : float = lift_axis * lift_speed + float(m["b"]) * lift_speed * MOUSE_TOOL_MULT
	var cur_lift_v    : float = _lift_velocity.approach(target_lift_v, delta)
	lift_height_m = clampf(lift_height_m + cur_lift_v * delta, lift_min_m, lift_max_m)

	var tilt_axis := Input.get_action_strength("forklift_tilt_back") \
				   - Input.get_action_strength("forklift_tilt_fwd")
	var target_tilt_v : float = tilt_axis * tilt_speed_deg_s + float(m["a"]) * tilt_speed_deg_s * MOUSE_TOOL_MULT
	var cur_tilt_v    : float = _tilt_velocity.approach(target_tilt_v, delta)
	tilt_deg = clampf(tilt_deg + cur_tilt_v * delta, tilt_min_deg, tilt_max_deg)

	# Mouse-as-joystick clamp control: RIGHT-drag X scales clamp_force live so the
	# mouse joystick can open/close the plates (was: V/B keys only). Right = close
	# (squeeze harder), left = open. Treated as a rate, like the other tool axes,
	# so a steady drag ramps the force smoothly — matching the B hold-to-build feel.
	# Pairs cleanly with the keyboard force ramp: either input is welcome.
	var cf_delta : float = float(m["c"]) * delta * MOUSE_TOOL_MULT * 0.4
	if absf(cf_delta) > 0.0:
		clamp_force = clampf(clamp_force + cf_delta, 0.0, 1.0)
		# A live mouse-driven close should attempt a grab when crossing the bale's
		# force gate, just like releasing B does — otherwise the mouse path can
		# build force without ever latching onto a bale.
		if _carried_bale == null and cf_delta > 0.0:
			_try_grab()
		# Mouse-driven open below the wire-compliance threshold should release —
		# mirror of pressing V (drop the squeeze + drop the bale).
		if _carried_bale != null and cf_delta < 0.0 and clamp_force < 0.05:
			_release()

## Plate gap tracks a target — open when no bale, snug against the bale width
## minus clamp_force squeeze when a bale is gripped. The plates close along the
## clamp's local X axis, so the gap must follow the bale's X dimension (its
## LENGTH along the carry-point X). Was previously using size.z — a bug that
## let the plates close ~15 cm INSIDE the bale, visibly penetrating it past the
## 10% give. Fix: use size.x and clamp to (bale.x × 0.9) so the closed plates
## sit exactly at the bale's collision boundary, only the squeeze going further.
func _update_plate_gap(delta: float) -> void:
	var target_gap := clamp_open_m
	if _carried_bale != null:
		# #201 Step 5 — plates are now real AnimatableBody3D bodies that push the
		# bale's rigid body via contact. Target gap converges to the bale's
		# collision width (no further squeeze geometry); friction × normal force
		# from PhysicsMaterial does the grip, and a higher clamp_force still
		# feels different at the HUD because the operator chose to hold harder.
		# The old `bale_x_collision - squeeze` math drove plates INTO the bale's
		# collision volume, which with real plate collision would shove the
		# bale rigid body around — visible jitter / ejection.
		var size := _bale_size(_carried_bale)
		var bale_x_collision := size.x * 0.9
		target_gap = clampf(bale_x_collision, clamp_closed_m, clamp_open_m)
	elif clamp_force > 0.01:
		# #161 fix: plates track clamp_force even when no bale is being carried.
		# Was: only closed while the pinch button was physically held, so
		# releasing B with 94% force still showing snapped the plates back open
		# — the operator's "94%" felt fake. Now the gap follows the force value:
		# 0 = wide open, 1 = fully closed, so the visible state matches the HUD.
		target_gap = lerpf(clamp_open_m, clamp_closed_m, clamp_force)
	elif Input.is_action_pressed("forklift_forks_pinch"):
		target_gap = clamp_closed_m
	clamp_gap_m = lerpf(clamp_gap_m, target_gap, clampf(PLATE_TRACK_RATE * delta, 0.0, 1.0))

func _apply_mast_lift_tilt() -> void:
	if _lift_carriage:
		_lift_carriage.position.y = lift_height_m
	if _mast_pivot:
		_mast_pivot.rotation.x = deg_to_rad(tilt_deg)
	if _left_plate:
		_left_plate.position.x = -clamp_gap_m * 0.5
	if _right_plate:
		_right_plate.position.x = clamp_gap_m * 0.5

# =============================================================================
# GRAB / RELEASE — uses BaseVehicle's stack pickup, adds the clamp-force gate,
# the wire-bulge hook-in, and the sheet-arc fan-out on release.
# =============================================================================
## Refuse the grab if clamp_force is below the floor for THIS stack height: a
## single bale needs ~clamp_force_needed; each additional bale on top piles on
## the load so the floor scales by stack size. Stops a weak grip lifting a 3-tall
## stack — the operator must squeeze proportionally harder to take the whole pile.
func _can_grab_stack(primary: Node3D, stack: Array[Node3D]) -> bool:
	var base_needed: float = float(primary.get_meta("clamp_force_needed", 0.30))
	var floor_force := minf(base_needed * float(1 + stack.size()), 0.95)
	return clamp_force >= floor_force

func _on_grab_refused(primary: Node3D, _stack: Array[Node3D]) -> void:
	# Subtle feedback: nudge the bale a hair so the player feels they tried.
	_nudge(primary, Vector3(0.0, 0.02, 0.0))

func _on_grabbed(_primary: Node3D, _stack: Array[Node3D]) -> void:
	# Tell the wire-bulge logic to start checking against the primary bale.
	_update_plate_gap(0.001)

## V pressed: start the gradual force decay (#161). Was: instant 0, which felt
## like nothing happened because the plates had already snapped open. Now the
## bale is released immediately (you let go), but clamp_force ramps DOWN over
## CLAMP_RAMP_S, so the plates visibly relax. _physics_process ticks the decay.
func _on_pre_release() -> void:
	_force_ramping = false
	_force_unramping = true

## Bale fully dropped — keep the decay running so the plates open the rest of
## the way; clamp_force has already started its descent from _on_pre_release.
func _on_released() -> void:
	_force_ramping = false
	_force_unramping = true

## Hook into BaseVehicle._drop_bale: after a normal drop, a cut bale opens into
## the sheet arc. (BaseVehicle calls _drop_bale for every bale in the column.)
func _drop_bale(b: Node3D, dest: Node) -> void:
	super._drop_bale(b, dest)
	if b != null and is_instance_valid(b) and bool(b.get_meta("wires_cut", false)):
		_open_to_sheet_arc(b)

## Small physical nudge so the player feels their grab attempt did SOMETHING
## even when clamp_force was insufficient.
func _nudge(bale: Node3D, impulse: Vector3) -> void:
	if bale is RigidBody3D:
		var rb := bale as RigidBody3D
		var was_frozen := rb.freeze
		rb.freeze = false
		rb.apply_central_impulse(impulse * rb.mass)
		# Refreeze after a moment so the stack doesn't drift
		await get_tree().create_timer(0.2).timeout
		if is_instance_valid(rb):
			rb.freeze = was_frozen
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO

## (Kept as a no-op stub for save-game compatibility — wire cutting now happens
## ON FOOT via the WireCutter tool, not from inside the clamp cab. See
## src/scenes/world/WireCutter.gd for the new flow.)
func _try_cut_wires() -> void:
	pass

# =============================================================================
# VISUAL HELPERS (wire bulge + sheet arc fall)
# =============================================================================
## When carrying with clamp_force above the bale's wire compliance, the top
## wire segments visibly rise — that's the player's cue to use Shift+B to cut.
func _update_wire_bulge() -> void:
	if _carried_bale == null:
		return
	var wires := _carried_bale.find_child("Wires", true, false)
	if wires == null:
		return
	var compliance: float = float(_carried_bale.get_meta("wire_compliance", 0.55))
	var bulge := 0.0
	if clamp_force > compliance:
		bulge = (clamp_force - compliance) / maxf(1.0 - compliance, 0.001) * WIRE_BULGE_M
	for wire in wires.get_children():
		var top := wire.get_node_or_null("Top") as Node3D
		if top:
			var base_y := (wire as Node3D).position.y + (_bale_size(_carried_bale).y * 1.005)
			top.position.y = base_y - (_bale_size(_carried_bale).y * 1.005) + bulge

## When a cut bale is released, detach each Sheet_i child into its own RigidBody3D.
## Sheets are now FLEXIBLE + STICKY (was: rigid fan-out slabs). Concretely:
##   • HIGH inter-sheet friction (0.95) — they cling to each other and the floor,
##     draping into a pile instead of skating apart like dominoes.
##   • Strong damping (linear 3.5, angular 5.0) — they settle quickly, no rolling.
##   • PinJoint3D chain — adjacent sheets are weakly linked so the layered stack
##     stays roughly together when it falls; the pile drapes, doesn't explode.
##   • The "outward kick" impulse is REMOVED — sheets fall under gravity only,
##     so the column drops in place and gradually deforms into a pile of film.
## Net feel: a bound bale becomes a heavy, lumpy mound of layered film, exactly
## like what the operator described.
func _open_to_sheet_arc(bale: Node3D) -> void:
	var sheets := bale.find_child("Sheets", true, false)
	if sheets == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	var spawned : Array[RigidBody3D] = []
	for sheet in sheets.get_children():
		var mi := sheet as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var s_size: Vector3 = (mi.mesh as BoxMesh).size
		var s_world := mi.global_transform
		var sheet_rb := RigidBody3D.new()
		# Each compressed-film slice is light — it's a thin slab, not a brick.
		sheet_rb.mass = maxf(s_size.x * s_size.y * s_size.z * 80.0, 0.1)
		sheet_rb.linear_damp  = 3.5       # was 1.2 — kills sliding so sheets stack
		sheet_rb.angular_damp = 5.0       # was 2.5 — kills tumbling
		var pm := PhysicsMaterial.new()
		pm.friction = 0.95                # was 0.35 — STICKY (the user's word)
		pm.bounce   = 0.0
		sheet_rb.physics_material_override = pm
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s_size
		col.shape = bs
		sheet_rb.add_child(col)
		var disp_mi := MeshInstance3D.new()
		disp_mi.mesh = mi.mesh
		disp_mi.material_override = mi.material_override
		sheet_rb.add_child(disp_mi)
		scene_root.add_child(sheet_rb)
		sheet_rb.global_transform = s_world
		# No outward impulse — sheets drop in place under gravity and cling.
		spawned.append(sheet_rb)
		sheet.queue_free()
	# Pin adjacent sheets together with a soft joint — the column stays roughly
	# layered as it falls + drapes (films cling in the real world too). Soft
	# joints (high `softness`) let the bind stretch rather than yank.
	for i in spawned.size() - 1:
		var a := spawned[i]
		var b := spawned[i + 1]
		var joint := PinJoint3D.new()
		# Anchor halfway between the two sheets' centres so the pin has slack.
		joint.global_position = (a.global_position + b.global_position) * 0.5
		joint.set("nodes/node_a", a.get_path())
		joint.set("nodes/node_b", b.get_path())
		# A loose impulse cap so a sharp jerk breaks the bond (a stiff joint chain
		# would keep the whole pile moving as one rigid stack).
		joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP, 4.0)
		joint.set_param(PinJoint3D.PARAM_DAMPING, 0.6)
		scene_root.add_child(joint)

func _bale_size(b: Node) -> Vector3:
	# Read footprint back from the collision shape (it's the authoritative size
	# in the running scene — independent of the PlaceableCatalog item entry).
	for c in b.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ONE

# =============================================================================
# #211e — BALE ALIGNMENT GHOST (mirror of Forklift.gd)
# =============================================================================
## Spawn the ghost as a translucent slab parented to the scene root so its
## world transform tracks the belt, not the vehicle. Hidden until the carry +
## proximity check passes.
func _build_bale_alignment_ghost() -> void:
	_bale_alignment_ghost = Node3D.new()
	_bale_alignment_ghost.name = "BaleAlignmentGhost"
	_ghost_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(GHOST_BALE_WID_M, GHOST_BALE_HGT_M, GHOST_BALE_LEN_M)
	_ghost_mesh.mesh = bm
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.2, 0.95, 0.3, 0.5)
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mesh.material_override = _ghost_mat
	_bale_alignment_ghost.add_child(_ghost_mesh)
	_bale_alignment_ghost.visible = false
	call_deferred("_deferred_attach_ghost")

func _deferred_attach_ghost() -> void:
	if _bale_alignment_ghost == null:
		return
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(_bale_alignment_ghost)

func _update_bale_alignment_ghost(delta: float) -> void:
	if _bale_alignment_ghost == null or not is_instance_valid(_bale_alignment_ghost):
		return
	if _carried_bale == null:
		_bale_alignment_ghost.visible = false
		return
	var belt := _nearest_shredder_feed_belt(GHOST_BELT_REACH_M)
	if belt == null:
		_bale_alignment_ghost.visible = false
		return
	_bale_alignment_ghost.visible = true
	var deck_y : float = 0.7
	if "deck_height" in belt:
		deck_y = float(belt.get("deck_height"))
	var local_pos := Vector3(0.0, deck_y + 0.15, 1.0)
	var ghost_xf : Transform3D = (belt as Node3D).global_transform * Transform3D(Basis(), local_pos)
	_bale_alignment_ghost.global_transform = ghost_xf
	var yaw_dev_deg : float = 0.0
	if belt.has_method("_bale_yaw_deviation_deg"):
		yaw_dev_deg = float(belt.call("_bale_yaw_deviation_deg", _carried_bale))
	if absf(yaw_dev_deg) <= GHOST_YAW_TOLERANCE_DEG:
		_ghost_flash_t = 0.0
		_ghost_mat.albedo_color = Color(0.2, 0.95, 0.3, 0.5)
	else:
		_ghost_flash_t += delta * GHOST_FLASH_HZ * TAU
		var a : float = 0.5 + (sin(_ghost_flash_t) + 1.0) * 0.15
		_ghost_mat.albedo_color = Color(0.95, 0.2, 0.2, a)

func _nearest_shredder_feed_belt(reach: float) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var here : Vector3 = global_transform.origin
	var best : Node3D = null
	var best_d : float = reach
	for b in tree.get_nodes_in_group("shredder_feed_belt"):
		if not (b is Node3D) or not is_instance_valid(b):
			continue
		var d : float = (b as Node3D).global_transform.origin.distance_to(here)
		if d <= best_d:
			best = b as Node3D
			best_d = d
	return best

func _exit_tree() -> void:
	if _bale_alignment_ghost != null and is_instance_valid(_bale_alignment_ghost):
		_bale_alignment_ghost.queue_free()
		_bale_alignment_ghost = null
