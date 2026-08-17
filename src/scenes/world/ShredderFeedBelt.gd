extends Node3D
class_name ShredderFeedBelt

## Dedicated WIDE feed belt that takes opened bales and meters them into a
## shredder. Replaces the narrow inclined_belt for the intake flow.
##
## SHAPE (operator spec):
##   • ~5 m HORIZONTAL deck, wide enough to set two bales side by side. Bales
##     are loaded from the SIDE onto this deck.
##   • a 45° INCLINED belt (~5 m run) rising from the end of the deck.
##   • the top of the incline drops material into the shredder throat.
##
## FEEDING (fill-controlled, portioned):
##   • `fill` (0..1) models how full the shredder throat is. The shredder
##     digests it down at `digest_rate`.
##   • The belt RUNS only while `fill < fill_setpoint`. When the throat is full
##     it STOPS; once the shredder has eaten enough it resumes. So a full belt
##     of opened bales feeds in PORTIONS over time, not all at once.
##   • A bale that reaches the top doesn't dump instantly — it transfers its
##     `mass_remaining` into `fill` at `feed_rate` (and pauses whenever the
##     throat is full), which is the portion-by-portion drop the operator
##     described for nicely-opened bales.
##
## SCAN GATE (#152): accept_bale() REFUSES a bale that hasn't been scanned —
## only scanned bales are allowed on the belt.

signal bale_accepted(bale: Node3D)
signal bale_rejected(bale: Node3D, reason: String)
signal bale_consumed(bale: Node3D)
## #211a — operator-spec feeding rules raise these so LineFlow's pack-up
## cascade + HMI can react. belt_id is the node's name so the operator can
## tell which belt jammed when several lines feed shredders. All three are
## faults that latch on the belt (is_faulted() == true) until cleared.
signal belt_jam(belt_id: String)             # #211a — a bale rode cross-wise too long
signal intake_overfill(belt_id: String)      # #211b — bales packed too tight
signal thermal_shutdown(belt_id: String)     # #211c — sustained over-occupancy

@export var deck_length   : float = 5.0     # horizontal run (m)
@export var deck_width    : float = 2.5     # wide enough for 2 bales side by side
@export var incline_run   : float = 5.0     # incline horizontal run (m)
@export var incline_deg   : float = 35.0    # incline angle — lowered from 45° per operator (top ≈ 4 m)
@export var deck_height   : float = 0.7     # deck top off the ground
@export var belt_speed    : float = 0.12    # m/s creep — +50% per operator (was 0.08)
@export var fill_setpoint : float = 0.85    # belt halts at/above this throat fill
@export var digest_rate   : float = 0.04    # shredder eats throat fill / s
@export var feed_rate     : float = 0.25    # bale mass → throat fill / s at the top
## #26/#27 — a feed belt feeds a SHREDDER. With no shredder present (or one in
## error) there is nothing to pulverize the material into, so the belt must NOT
## digest material into thin air, and the PLC stops the belt. A shredder is any
## node in group "shredder" within reach of the discharge; if it exposes is_running()
## / is_faulted() we honour those. require_shredder=false restores the old standalone
## behaviour for test scenes that have no machine downstream.
@export var require_shredder : bool = true
@export var shredder_reach   : float = 6.0   # m from the discharge to find the shredder
## #218 — Sandbox/mid-shift default: the belt comes up RUNNING because the
## real-plant shift-lead has already executed the morning SWI-049 routine by
## the time a sandbox world spawns. Cold-commission (fresh world boot) will
## flip this to false via the EventBus shift_started gate in a follow-up;
## existing saves keep working because the runtime value persists once set.
## request_start() / request_stop() still drive it from the HMI at runtime.
@export var start_requested  : bool  = true

# ── Optional shape extensions (opzetband variants) ─────────────────────────────
## A short HORIZONTAL discharge piece at the very top, after the incline (e.g. the
## 0.5 m horizontal section at the top of opzetband 3A/3B). 0 = none (default).
@export var top_flat_m : float = 0.0
## Funnel side walls (opzetband 1): straight-and-wide for funnel_start_m along the
## incline, then narrow linearly over funnel_narrow_m to funnel_min_width, then
## straight-and-narrow to the top. funnel_min_width<=0 disables the funnel and falls
## back to the regular straight side guards.
@export var funnel_start_m   : float = 0.0
@export var funnel_narrow_m  : float = 0.0
@export var funnel_min_width : float = 0.0

var fill : float = 0.0
## Kilograms currently in the throat. `fill` is the 0..1 geometric fill level;
## this is what that volume actually weighs. Kept in step with `fill` so the
## belt can hand REAL mass downstream instead of inventing it from a constant.
var _throat_kg : float = 0.0

## Total kg the belt is holding right now (riders still to feed + throat).
## Exists so a conservation test can sum the belt without reaching into privates.
func held_kg() -> float:
	var total : float = _throat_kg
	for r in _riders:
		total += float(r.get("mass", 0.0)) * float(r.get("kg_total", 0.0))
	return total

## The bale's real weight, in the order of preference the codebase already uses.
func _bale_kg(bale: Node) -> float:
	if bale == null:
		return 0.0
	if bale.has_meta("remaining_kg"):
		var rk : float = float(bale.get_meta("remaining_kg"))
		if rk > 0.0:
			return rk
	if bale.has_meta("weight_kg"):
		return float(bale.get_meta("weight_kg"))
	if bale is RigidBody3D:
		return float((bale as RigidBody3D).mass)
	return 0.0

# Cumulative counters (HUD / tests). bales_accepted only counts scanned bales
# that made it onto the belt; bales_rejected counts scan-gate refusals.
var bales_accepted : int = 0
var bales_rejected : int = 0
var untraced_count : int = 0   # accepted but not scanned (traceability miss, not a physical reject)

# Bales currently riding the belt. Each entry: {node, progress(0..1 along the
# whole path), mass(0..1 remaining), feeding(bool)}.
var _riders : Array = []

# Cached path metrics
var _path_total : float = 0.0      # total path length (deck + incline)
var _incline_angle : float = 0.0   # radians
var _incline_hyp   : float = 0.0   # belt length along the slope

# #8 — shredded OUTPUT
const OUTPUT_KG_PER_FILL : float = 350.0   # flake mass produced per unit of throat digested
const OUTPUT_DENSITY     : float = 180.0   # coarse film-flake bulk density (kg/m³)
const OUTPUT_FLAKE_LIFE  : float = 0.7      # falling-flake visual lifetime (s)
const OUTPUT_FLAKE_MAX   : int   = 14       # cap on live falling flakes (no spam)
var _output_pile : Node = null
var _flake_t     : float = 0.0
var _flake_live  : int   = 0

# =============================================================================
func _ready() -> void:
	add_to_group("shredder_feed_belt")
	_incline_angle = _incline_angle_rad()
	_incline_hyp   = _incline_hyp_m()
	_path_total = deck_length + _incline_hyp + maxf(top_flat_m, 0.0)
	# #214 belt-speed ramp — start at the live PLC state. is_running() reads
	# fault latches + fill + _shredder_ok(); at construction these all default
	# to a stopped belt (no shredder cached yet) so initial value is 0 and the
	# belt will smoothly ramp up the first frame the interlock clears.
	_belt_speed_smooth = SmoothedRate.new(0.0, belt_ramp_tau_s)
	_build_visual()
	_build_collision()
	_build_container_area()

func _build_container_area() -> void:
	var area := Area3D.new()
	area.name = "ContainerArea"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 3.0
	cs.shape = sp
	area.add_child(cs)
	# LOCKSTEP with _discharge_pos(): the trigger that notices a container parked
	# at the discharge must sit exactly where _container_at() looks for it. This
	# used to be a hand-copied `deck_length + incline_run + 1.5`, which silently
	# disagreed with the landing point on every belt that has a top tray.
	area.position = Vector3(0.0, 0.0, _landing_z())
	area.body_entered.connect(_on_container_entered)
	area.body_exited.connect(_on_container_exited)
	add_child(area)

func _on_container_entered(body: Node3D) -> void:
	if body.is_in_group("waste_container") and body.has_method("add"):
		if not _cached_containers.has(body):
			_cached_containers.append(body)

func _on_container_exited(body: Node3D) -> void:
	if _cached_containers.has(body):
		_cached_containers.erase(body)

## Cached shader-material references so _process can toggle scroll_speed when the
## belt starts/stops — gives the operator an at-a-glance visual cue that matches
## the PLC state. One material per surface so each can scroll at its own rate
## (the incline surface visually moves the same direction as the flat deck).
var _belt_mat_deck    : ShaderMaterial = null
var _belt_mat_incline : ShaderMaterial = null
var _belt_mat_top     : ShaderMaterial = null

## The walkable StaticBody3D built in _build_collision(). Kept so the run-state
## code can keep its "belt_speed" meta live (belt_speed while running, 0.0 while
## stopped) — that's what the player's belt-carry contract reads off the collider.
var _belt_body : StaticBody3D = null

# ── #214 belt-speed ramp ──────────────────────────────────────────────────────
## Heavy intake belt — slat conveyor with a loaded incline + drive motor inertia
## coasts down over a couple of seconds when the PLC commands stop. Without this
## ramp the carry meta, BeltSurface drag, shader scroll, and rider progress all
## snapped from belt_speed → 0 in a single frame on fault / throat-full / shredder-
## loss — which felt teleport-y on bales mid-ride and made the player jolt off the
## deck. The setpoint (is_running ? belt_speed : 0) is sent through a SmoothedRate
## with tau ≈ 2.5 s so the physical decay matches real induction-motor coast-down.
@export var belt_ramp_tau_s : float = 2.5
var _belt_speed_smooth : SmoothedRate = null

func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.45, 0.48); steel.roughness = 0.6; steel.metallic = 0.3
	# Static fallback material in case the textured one fails to load; the textured
	# scrolling material is then applied per-surface below.
	var belt_mat := StandardMaterial3D.new()
	belt_mat.albedo_color = Color(0.12, 0.12, 0.13); belt_mat.roughness = 0.9
	var guard := StandardMaterial3D.new()
	guard.albedo_color = Color(0.92, 0.78, 0.18); guard.roughness = 0.7   # safety yellow
	_build_deck_visual(steel, belt_mat, guard)
	var inc_pivot := _build_incline_visual(steel, belt_mat, guard)
	_build_top_end_visual(inc_pivot, steel, belt_mat, guard)

func _build_top_end_visual(inc_pivot: Node3D, steel: StandardMaterial3D, belt_mat: StandardMaterial3D, guard: StandardMaterial3D) -> void:
	var hyp := _incline_hyp
	# Top end: either a horizontal discharge tray (opzetband 3A/3B's 0.5 m flat top)
	# OR the legacy drop snout. Only one — the flat tray is the realistic version.
	if top_flat_m > 0.01:
		var tray := MeshInstance3D.new()
		var tm := BoxMesh.new(); tm.size = Vector3(deck_width * 0.8, 0.10, top_flat_m)
		tray.mesh = tm
		_belt_mat_top = load("res://src/build/PlaceableCatalog.gd").make_belt_material(0.0, Vector2(1.0, top_flat_m * 0.5))
		tray.material_override = (_belt_mat_top as Material) if _belt_mat_top != null else (belt_mat as Material)
		var top_y : float = deck_height + hyp * sin(_incline_angle)
		var top_z : float = deck_length + hyp * cos(_incline_angle)
		tray.position = Vector3(0.0, top_y, top_z + top_flat_m * 0.5)
		add_child(tray)
		for sx in [-1.0, 1.0]:
			var gt := MeshInstance3D.new()
			var gtm := BoxMesh.new(); gtm.size = Vector3(0.08, 0.30, top_flat_m)
			gt.mesh = gtm; gt.material_override = guard
			gt.position = Vector3(sx * deck_width * 0.4, top_y + 0.18, top_z + top_flat_m * 0.5)
			add_child(gt)
	else:
		# Drop snout at the top of the incline (where it dumps into the shredder).
		var snout := MeshInstance3D.new()
		var sm := BoxMesh.new(); sm.size = Vector3(deck_width * 0.7, 0.4, 0.8)
		snout.mesh = sm; snout.material_override = steel
		snout.position = Vector3(0.0, 0.0, hyp + 0.2)
		inc_pivot.add_child(snout)


func _build_incline_visual(steel: StandardMaterial3D, belt_mat: StandardMaterial3D, guard: StandardMaterial3D) -> Node3D:
	# Inclined belt section — a long box rotated about X, mounted at the deck end.
	var inc := MeshInstance3D.new()
	var hyp := _incline_hyp
	var im := BoxMesh.new(); im.size = Vector3(deck_width * 0.8, 0.10, hyp)
	inc.mesh = im
	_belt_mat_incline = load("res://src/build/PlaceableCatalog.gd").make_belt_material(0.0, Vector2(1.0, hyp * 0.5))
	inc.material_override = (_belt_mat_incline as Material) if _belt_mat_incline != null else (belt_mat as Material)
	# Pivot the incline so its base sits at the deck's far end and it rises incline_deg.
	var inc_pivot := Node3D.new()
	inc_pivot.name = "InclinePivot"   # #196 — let post-build grafts (metaaldetector head) find it
	inc_pivot.position = Vector3(0.0, deck_height, deck_length)
	inc_pivot.rotation.x = -_incline_angle   # tilt up toward +Z/+Y
	add_child(inc_pivot)
	inc.position = Vector3(0.0, 0.0, hyp * 0.5)
	inc_pivot.add_child(inc)
	# Support legs under the incline (every ~2 m along the slope) so the belt looks
	# self-supported regardless of how high it ends up.
	var leg_count : int = max(2, int(round(hyp / 2.0)))
	for li in leg_count:
		var s : float = float(li) / float(leg_count - 1) if leg_count > 1 else 0.0
		var top_h : float = deck_height + s * hyp * sin(_incline_angle)
		for sx in [-1.0, 1.0]:
			var leg2 := MeshInstance3D.new()
			var lm2 := BoxMesh.new(); lm2.size = Vector3(0.10, top_h, 0.10)
			leg2.mesh = lm2; leg2.material_override = steel
			leg2.position = Vector3(sx * deck_width * 0.45, top_h * 0.5,
				deck_length + s * hyp * cos(_incline_angle))
			add_child(leg2)
			# Simple vertical floor legs (each runs straight down to the floor; only
			# their height varies along the incline) → extend to the floor when raised (#70).
			leg2.add_to_group("machine_leg")
			leg2.set_meta("leg_h", top_h)
	# Side guards along the incline. If funnel walls are configured we draw a tapering
	# wall (parallel → narrowing → parallel-narrow) instead of straight guards.
	if funnel_min_width > 0.0 and funnel_narrow_m > 0.0:
		_build_funnel_walls(inc_pivot, guard, hyp)
	else:
		for sx in [-1.0, 1.0]:
			var g2 := MeshInstance3D.new()
			var gm2 := BoxMesh.new(); gm2.size = Vector3(0.08, 0.30, hyp)
			g2.mesh = gm2; g2.material_override = guard
			g2.position = Vector3(sx * deck_width * 0.4, 0.2, hyp * 0.5)
			inc_pivot.add_child(g2)
	return inc_pivot

func _build_deck_visual(steel: StandardMaterial3D, belt_mat: StandardMaterial3D, guard: StandardMaterial3D) -> void:
	# Horizontal deck belt surface — skipped when there is no flat section (Westa, opzetband 1).
	if deck_length <= 0.01:
		return
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new(); dm.size = Vector3(deck_width, 0.10, deck_length)
	deck.mesh = dm
	_belt_mat_deck = load("res://src/build/PlaceableCatalog.gd").make_belt_material(0.0, Vector2(1.0, deck_length * 0.5))
	# Cast both arms to the common Material supertype so the ternary types unify.
	deck.material_override = (_belt_mat_deck as Material) if _belt_mat_deck != null else (belt_mat as Material)
	deck.position = Vector3(0.0, deck_height, deck_length * 0.5)
	add_child(deck)
	# Side guards along the deck
	for sx in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		var gm := BoxMesh.new(); gm.size = Vector3(0.08, 0.30, deck_length)
		g.mesh = gm; g.material_override = guard
		g.position = Vector3(sx * deck_width * 0.5, deck_height + 0.18, deck_length * 0.5)
		add_child(g)
	# Support legs under the deck
	for sz in [0.2, 0.8]:
		for sx in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new(); lm.size = Vector3(0.10, deck_height, 0.10)
			leg.mesh = lm; leg.material_override = steel
			leg.position = Vector3(sx * deck_width * 0.45, deck_height * 0.5, deck_length * sz)
			add_child(leg)
			# Simple vertical floor legs → lengthen to the floor when raised (#70).
			leg.add_to_group("machine_leg")
			leg.set_meta("leg_h", deck_height)

## Funnel side walls along the incline (opzetband 1): parallel-and-wide for
## funnel_start_m, then narrowing linearly over funnel_narrow_m to funnel_min_width,
## then parallel-and-narrow to the top. Each section is a single box wall on each
## side; the narrowing piece is tilted in-plane so it joins the two parallel runs.
func _build_funnel_walls(inc_pivot: Node3D, guard_mat: StandardMaterial3D, hyp: float) -> void:
	var w_full   : float = deck_width * 0.8           # wall x-offset at the wide end
	var w_narrow : float = funnel_min_width * 0.5     # wall x-offset at the narrow end
	var start_m  : float = clampf(funnel_start_m, 0.0, hyp)
	var taper_m  : float = clampf(funnel_narrow_m, 0.0, hyp - start_m)
	var tail_m   : float = maxf(hyp - start_m - taper_m, 0.0)
	for sx in [-1.0, 1.0]:
		# Parallel-wide segment.
		if start_m > 0.01:
			var w1 := MeshInstance3D.new()
			var wm1 := BoxMesh.new(); wm1.size = Vector3(0.08, 0.30, start_m)
			w1.mesh = wm1; w1.material_override = guard_mat
			w1.position = Vector3(sx * w_full * 0.5, 0.2, start_m * 0.5)
			inc_pivot.add_child(w1)
		# Narrowing segment — a wall tilted in-plane so its inner edge tracks the funnel.
		if taper_m > 0.01:
			var taper_z_mid : float = start_m + taper_m * 0.5
			var x_mid : float = sx * (w_full * 0.5 + w_narrow) * 0.5
			# Length of the slanted wall = sqrt(taper_m^2 + (w_full/2 - w_narrow)^2)
			var dx : float = (w_full * 0.5 - w_narrow)
			var seg_len : float = sqrt(taper_m * taper_m + dx * dx)
			var yaw : float = atan2(sx * dx, taper_m)
			var w2 := MeshInstance3D.new()
			var wm2 := BoxMesh.new(); wm2.size = Vector3(0.08, 0.30, seg_len)
			w2.mesh = wm2; w2.material_override = guard_mat
			w2.position = Vector3(x_mid, 0.2, taper_z_mid)
			w2.rotation.y = yaw
			inc_pivot.add_child(w2)
		# Parallel-narrow segment.
		if tail_m > 0.01:
			var w3 := MeshInstance3D.new()
			var wm3 := BoxMesh.new(); wm3.size = Vector3(0.08, 0.30, tail_m)
			w3.mesh = wm3; w3.material_override = guard_mat
			w3.position = Vector3(sx * w_narrow, 0.2, start_m + taper_m + tail_m * 0.5)
			inc_pivot.add_child(w3)

## Push a common scroll_speed into every textured belt surface this belt owns.
## Called each tick from the live is_running() state so the visual matches the PLC.
func _set_scroll_speed(s: float) -> void:
	if _belt_mat_deck != null:
		_belt_mat_deck.set_shader_parameter("scroll_speed", s)
	if _belt_mat_incline != null:
		_belt_mat_incline.set_shader_parameter("scroll_speed", s)
	if _belt_mat_top != null:
		_belt_mat_top.set_shader_parameter("scroll_speed", s)

## Solid collision so the player + vehicles stand/walk ON the belt instead of
## falling THROUGH it — both the flat deck and the inclined section. (The belt was
## pure MeshInstance visuals before, with no collider at all.)
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "BeltBody"
	add_child(body)
	# Belt-carry contract: the walkable collider is in group "belt", and its
	# "belt_speed" meta is the LIVE (ramped) belt speed each tick — 0 at construction
	# (slats not turning yet), then walked toward `belt_speed` or back to 0 via the
	# SmoothedRate in _process. The player controller reads this off the body it's
	# standing on and drags itself along.
	_belt_body = body
	body.add_to_group("belt")
	body.set_meta("belt_speed", 0.0)
	# Flat deck slab (skip if no flat section).
	if deck_length > 0.01:
		var dc := CollisionShape3D.new()
		var dbs := BoxShape3D.new(); dbs.size = Vector3(deck_width, 0.22, deck_length)
		dc.shape = dbs
		dc.position = Vector3(0.0, deck_height, deck_length * 0.5)
		body.add_child(dc)
	# Inclined slab — rotated + offset to lie along the visual incline.
	var ic := CollisionShape3D.new()
	var ibs := BoxShape3D.new(); ibs.size = Vector3(deck_width * 0.8, 0.22, _incline_hyp)
	ic.shape = ibs
	var t := Transform3D(Basis(Vector3.RIGHT, -_incline_angle), Vector3(0.0, deck_height, deck_length))
	ic.transform = t.translated_local(Vector3(0.0, 0.0, _incline_hyp * 0.5))
	body.add_child(ic)
	# Top flat discharge tray (opzetband 3A/3B), if configured.
	if top_flat_m > 0.01:
		var tc := CollisionShape3D.new()
		var tbs := BoxShape3D.new(); tbs.size = Vector3(deck_width * 0.8, 0.22, top_flat_m)
		tc.shape = tbs
		var top_y : float = deck_height + _incline_hyp * sin(_incline_angle)
		var top_z : float = deck_length + _incline_hyp * cos(_incline_angle)
		tc.position = Vector3(0.0, top_y, top_z + top_flat_m * 0.5)
		body.add_child(tc)

# =============================================================================
# PUBLIC API
# =============================================================================
## Is the belt currently moving? False while the throat is full, false when the
## PLC interlock trips because there's no healthy shredder downstream (#27), AND
## false while any #211 fault latch is set (belt_jam / intake_overfill /
## thermal_shutdown). The fault latch wins over fill state — a jammed belt
## stays dead even if the throat would otherwise call for material.
func is_running() -> bool:
	if is_faulted():
		return false
	if not start_requested:
		return false
	return fill < fill_setpoint and _shredder_ok()

## #218 — HMI hook: SWI-049 green-button press routes here to release the belt.
func request_start() -> void:
	start_requested = true

## #218 — HMI hook: STOP / fault clear / shift-end routes here to park the belt.
func request_stop() -> void:
	start_requested = false

var _cached_shredder: Node3D = null

## #26/#27 — is there a present, non-faulted shredder at the discharge to feed? Drives
## both the PLC stop (is_running) and the no-pulverize gate (the digest in _process).
func _shredder_ok() -> bool:
	if not require_shredder:
		return true
	if not is_inside_tree():
		return false
	var disc := _discharge_pos()

	if _cached_shredder != null and is_instance_valid(_cached_shredder) and _cached_shredder.is_inside_tree() and _cached_shredder.global_position.distance_to(disc) <= shredder_reach:
		if _cached_shredder.has_method("is_faulted") and bool(_cached_shredder.call("is_faulted")):
			return false
		if _shredder_b_gordijn_blocked(_cached_shredder):
			return false
		if _cached_shredder.has_method("is_running"):
			return bool(_cached_shredder.call("is_running"))
		return true

	_cached_shredder = null
	for s in get_tree().get_nodes_in_group("shredder"):
		if not (s is Node3D):
			continue
		var n3d := s as Node3D
		if n3d.global_position.distance_to(disc) > shredder_reach:
			continue

		_cached_shredder = n3d
		# Found one in reach — respect its run/fault state if it exposes them.
		if n3d.has_method("is_faulted") and bool(n3d.call("is_faulted")):
			return false
		# #211c — the b_gordijn (rubber curtain hanging in front of the
		# shredder mouth) acts as a downstream interlock: when it's down or
		# jammed, material can't enter the throat, so the feed belt must
		# refuse to push. We accept either a `b_gordijn_jam` bool / property
		# or a `b_gordijn_state` string ("down"/"jammed"). Missing on legacy
		# shredders → treated as clear, so this stays a no-op until a
		# shredder model adds the curtain state.
		if _shredder_b_gordijn_blocked(n3d):
			return false
		if n3d.has_method("is_running"):
			return bool(n3d.call("is_running"))
		return true
	return false   # no shredder present → PLC keeps the belt stopped

## #211c — true when the downstream shredder reports a closed/jammed b_gordijn
## (intake curtain). Defensive: any of (is property + value, has_method, getter)
## is accepted, and the curtain check is silently SKIPPED when the shredder
## doesn't expose it (legacy models keep working unchanged).
func _shredder_b_gordijn_blocked(shred: Node) -> bool:
	if shred == null:
		return false
	# Prefer a bool flag if present (jammed = true → blocked).
	if "b_gordijn_jam" in shred and bool(shred.get("b_gordijn_jam")):
		return true
	if shred.has_method("is_b_gordijn_jammed") and bool(shred.call("is_b_gordijn_jammed")):
		return true
	# Or a string state — "down" / "jammed" both close the path.
	if "b_gordijn_state" in shred:
		var st := String(shred.get("b_gordijn_state"))
		if st == "down" or st == "jammed":
			return true
	return false

## Minimum clear distance at the loading end before another bale may be dropped —
## roughly a bale length + a gap, so bales never land inside one another.
const LOAD_ZONE_M : float = 1.7

# ── #211 Operator-spec feeding rules ──────────────────────────────────────────
## #211a — A bale's long axis must be within this many degrees of the belt
## travel direction. Anything beyond is "cross-wise" and will jam the
## throat if it isn't corrected.
const CROSS_WISE_ANGLE_DEG : float = 35.0
## #211a — Seconds a cross-wise bale may ride before the belt jams. Real
## operator window — they have a couple of beats to slap it straight
## before the shredder mouth chews on a sideways bale.
const JAM_TIMER_S          : float = 5.0
## #211b — Minimum centre-to-centre spacing between successive bales (m). A
## tighter gap means feed is being dropped before the previous bale has
## advanced — overfilling the intake.
const MIN_SPACING_M        : float = 0.5
## #211b — Frames the spacing violation must hold (~0.5s at 60fps) before
## intake_overfill latches. Brief crowding from a single drop is fine;
## sustained crowding is a real overfill.
const SPACING_VIOLATION_FRAMES : int = 30
## #211c — Maximum fraction of the path that bales may occupy before the
## belt is considered packed. Beyond this the rotor/drive overheats.
const MAX_BELT_OCCUPANCY   : float = 0.80
## #211c — Seconds occupancy may exceed MAX_BELT_OCCUPANCY before the
## thermal cutout drops the drive.
const THERMAL_GRACE_S      : float = 2.0
## A bale's nominal long-axis length on the belt (m). Used by the occupancy
## estimate — real CeDo bales are ~1.4 m long.
const BALE_LENGTH_M        : float = 1.4

# ── #211 fault latches ────────────────────────────────────────────────────────
# A latched fault halts is_running() AND the bale_accepted gate (accept_bale
# refuses new bales while faulted). Crew clears via reset_faults() (or a
# future HMI button); the bus mirrors each raise/clear onto EventBus alarms
# so the HUD siren reacts identically to a LineFlow E-stop.
var _fault_belt_jam          : bool  = false   # #211a
var _fault_intake_overfill   : bool  = false   # #211b
var _fault_thermal_shutdown  : bool  = false   # #211c
# #4 — physical fall-apart: a released bale bursts into these tumbling film pieces.
var _film_pieces : Array = []                  # [{node: RigidBody3D, life: float}]
const FILM_PIECE_LIFE_S : float = 2.5
## Frames of sustained spacing violation accrued so far. Resets the instant a
## tick passes with no pair tighter than MIN_SPACING_M.
var _spacing_violation_frames : int  = 0
## Seconds of sustained over-occupancy accrued so far. Resets to 0 on any
## tick where occupancy is back under MAX_BELT_OCCUPANCY.
var _thermal_grace_t          : float = 0.0

## True when ANY of the three #211 fault latches is set. LineFlow polls this
## via getter methods so its pack-up cascade can stop everything upstream of
## a jammed feeder. Mirrors the LineFlow E-stop pattern: a latched belt fault
## kills is_running() so the belt sits dead until the crew resets it.
func is_faulted() -> bool:
	return _fault_belt_jam or _fault_intake_overfill or _fault_thermal_shutdown
## Per-fault getters so the LineFlow walker (#211d) doesn't poke private state.
func belt_jam_active() -> bool:          return _fault_belt_jam
func intake_overfill_active() -> bool:   return _fault_intake_overfill
func thermal_shutdown_active() -> bool:  return _fault_thermal_shutdown

const _ALARM_BELT_JAM         : String = "BELT-JAM"
const _ALARM_INTAKE_OVERFILL  : String = "INTAKE-OVERFILL"
const _ALARM_THERMAL_SHUTDOWN : String = "THERMAL-SHUTDOWN"

func _belt_id_for_bus() -> String:
	# String() cast: `name` is a StringName and the literal is a String, which
	# trips INCOMPATIBLE_TERNARY.
	return String(name) if name != StringName("") else "shredder_feed_belt"

func _raise_fault(kind: String, alarm_id: String) -> void:
	var bid := _belt_id_for_bus()
	match kind:
		"belt_jam":
			if _fault_belt_jam: return
			_fault_belt_jam = true
			belt_jam.emit(bid)
		"intake_overfill":
			if _fault_intake_overfill: return
			_fault_intake_overfill = true
			intake_overfill.emit(bid)
		"thermal_shutdown":
			if _fault_thermal_shutdown: return
			_fault_thermal_shutdown = true
			thermal_shutdown.emit(bid)
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("machine_alarm_raised"):
		bus.emit_signal("machine_alarm_raised", bid, alarm_id, 3)
	print("[ShredderFeedBelt] FAULT %s on '%s'" % [alarm_id, bid])

## Crew/HMI hook — clear every latched #211 fault and reset the supporting
## counters/timers so the belt resumes the next tick. Pairs with the EventBus
## alarm_cleared mirror so the HUD siren goes quiet.
func reset_faults() -> void:
	var bid := _belt_id_for_bus()
	var bus := get_node_or_null("/root/EventBus")
	if _fault_belt_jam:
		_fault_belt_jam = false
		if bus and bus.has_signal("machine_alarm_cleared"):
			bus.emit_signal("machine_alarm_cleared", bid, _ALARM_BELT_JAM)
	if _fault_intake_overfill:
		_fault_intake_overfill = false
		if bus and bus.has_signal("machine_alarm_cleared"):
			bus.emit_signal("machine_alarm_cleared", bid, _ALARM_INTAKE_OVERFILL)
	if _fault_thermal_shutdown:
		_fault_thermal_shutdown = false
		if bus and bus.has_signal("machine_alarm_cleared"):
			bus.emit_signal("machine_alarm_cleared", bid, _ALARM_THERMAL_SHUTDOWN)
	_spacing_violation_frames = 0
	_thermal_grace_t = 0.0
	# Clear any lingering cross-wise timers on remaining riders — once the
	# crew reset the belt the orientation slate goes blank too.
	for r in _riders:
		r["cross_wise"] = false
		r["cross_wise_t"] = 0.0

## True when the loading end is clear enough to drop another bale. The feeder checks
## this and HOLDS its bale until the belt advances the last one clear.
func can_accept() -> bool:
	for r in _riders:
		if float(r["progress"]) * _path_total < LOAD_ZONE_M:
			return false
	return true

## Place a bale on the loading end of the deck. Returns false (and emits
## bale_rejected) if the bale hasn't been scanned — the scan gate (#152) — or if the
## loading end is still occupied (the spacing guard that stops bales stacking inside
## one another). `lane` 0 or 1 picks which side-by-side lane on the wide deck.
## #211a — also computes the bale's yaw relative to the belt travel axis. The
## bale is still ACCEPTED at any orientation (an operator slapping it sideways
## is the failure mode we want to model), but the rider is tagged cross_wise
## when |yaw| > CROSS_WISE_ANGLE_DEG so the per-tick timer can run it down to
## belt_jam if nobody corrects it. The pre-reparent bale.global_transform is
## sampled so the angle math sees the operator's last-set orientation, not the
## post-reparent local pose.
func accept_bale(bale: Node3D, lane: int = 0) -> bool:
	if bale == null:
		return false
	if not bool(bale.get_meta("scanned", false)):
		# Realism (operator 2026-07-16): a conveyor does NOT physically bounce a
		# 700 kg bale over a missing paper scan. The scan is a TRACEABILITY step
		# (MES logging), not a physical gate. Accept it onto the belt anyway and
		# just flag the compliance miss so the shift-leader scanlog can show it.
		bale.set_meta("untraced", true)
		untraced_count += 1
	if is_faulted():
		# #211 — a latched fault on the belt has to clear before another bale
		# may be dropped. Otherwise the operator could keep stacking onto a
		# jammed/overfilled belt and the fault would never recover.
		bale_rejected.emit(bale, "belt fault")
		return false
	if not can_accept():
		bale_rejected.emit(bale, "load zone occupied")
		return false
	# #211a — yaw of the bale's long axis vs the belt's travel direction. The
	# belt's local +Z is the travel axis (deck runs +Z; the incline pivot is at
	# z=deck_length). The bale's long axis is its local +Z too (1.4 m length
	# along its local Z). We sample the bale's world basis BEFORE reparent, then
	# project onto the belt's XZ plane and compare with the belt's +Z.
	var bale_yaw_deg : float = _bale_yaw_deviation_deg(bale)
	# Re-parent onto the belt. Operator 2026-07-16: a FROZEN kinematic bale ignores
	# the deck's BeltSurface constant_linear_velocity, so it sat dead-still on a
	# "moving" conveyor. Leave it DYNAMIC (freeze=false) so the belt physically
	# drags it down the deck like real material.
	if bale.get_parent():
		bale.get_parent().remove_child(bale)
	add_child(bale)
	if bale is RigidBody3D:
		(bale as RigidBody3D).freeze = false
	# lane 0 = CENTRE of the deck (the feeders feed here so bales ride down the
	# middle, not the old left/right zigzag); lane 1 = offset right if ever needed.
	var lane_x : float = (0.0 if lane == 0 else 0.5 * deck_width * 0.5)
	var cross_wise : bool = absf(bale_yaw_deg) > CROSS_WISE_ANGLE_DEG
	# REAL KILOGRAMS (operator 2026-07-20: "whatever obeys true physics is
	# correct"). `mass` stays the 0..1 FRACTION of the bale still on the belt —
	# the transport logic below is written in fractions — but `kg_total` carries
	# what that fraction is actually worth, read from the bale itself. Before
	# this, accept_bale hard-coded "mass": 1.0 and never looked at the weight, so
	# every bale entered identically and 350 kg was invented downstream.
	# The kg is DEBITED from the bale here: the material is now on the belt, so
	# leaving remaining_kg on the node would double-count it (measured: a 420 kg
	# bale produced 770 kg of ledger — see src/tests/test_mass_ledger.gd).
	var bale_kg : float = _bale_kg(bale)
	bale.set_meta("remaining_kg", 0.0)
	bale.set_meta("on_belt", true)      # LineFlow must not also draw off it
	_riders.append({
		"node": bale, "progress": 0.0, "mass": 1.0, "kg_total": bale_kg,
		"feeding": false, "lane_x": lane_x,
		# #211a — orientation rider state. cross_wise = true means the rider is
		# accumulating jam time; the 5s window matches the operator slap-it-
		# straight window before the shredder mouth chokes.
		"cross_wise": cross_wise,
		"cross_wise_t": JAM_TIMER_S if cross_wise else 0.0,
		"yaw_deg": bale_yaw_deg,
	})
	_place_rider(_riders.back())
	bales_accepted += 1
	bale_accepted.emit(bale)
	return true

## #4 — the operator's fall-apart. A released bale (wires cut, clamp let go) BURSTS
## into N physical RigidBody3D film pieces that tumble on the moving deck, WHILE the
## bale's mass still rides to the shredder via an (invisible) kinematic rider — so
## the line keeps feeding exactly as before (no #2 regression). The visible whole
## block is hidden; what the operator sees is the loose pieces falling open because
## nothing clamps them anymore. Returns false if the belt refuses (scan gate / load
## zone / fault) — same contract as accept_bale.
func burst_bale(bale: Node3D) -> bool:
	if bale == null:
		return false
	var n : int = int(bale.get_meta("sheet_count", 8))
	n = clampi(n, 4, 12)
	var tint : Color = bale.get_meta("bale_tint", Color(0.75, 0.72, 0.66))
	var lp : Vector3 = _belt_load_point_world()
	# Hide the block — it becomes the invisible MASS rider; the pieces are the visual.
	bale.visible = false
	var ok : bool = accept_bale(bale, 0)
	if not ok:
		bale.visible = true            # refused → undo the hide (no invisible orphan)
		return false
	_spawn_film_pieces(lp, n, tint)
	return true

## Deck load point in WORLD space (centred, near the loading end, just above the deck).
func _belt_load_point_world() -> Vector3:
	return to_global(Vector3(0.0, deck_height + 0.12, deck_length * 0.32))

## Spawn `n` loose film pieces at `pos` with a soft "fall open" impulse + tumble.
func _spawn_film_pieces(pos: Vector3, n: int, tint: Color) -> void:
	var scene : Node = get_tree().current_scene
	if scene == null:
		scene = self
	for k in n:
		var rb := RigidBody3D.new()
		rb.add_to_group("film_piece")
		rb.mass = 0.3
		rb.linear_damp = 2.2      # keep them from flying — they must SETTLE on the deck
		rb.angular_damp = 1.6
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.35, 0.02, 0.45)
		col.shape = bs
		rb.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = bs.size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = tint
		m.roughness = 0.92
		mi.material_override = m
		rb.add_child(mi)
		scene.add_child(rb)
		var ang : float = TAU * float(k) / float(maxi(n, 1))
		# Rest right ON the deck and fall open with only a GENTLE outward spread + slow
		# tumble — NO upward launch (operator: the pieces were flying into the air). #4v2
		rb.global_position = pos + Vector3(cos(ang) * 0.20, 0.015 * float(k), sin(ang) * 0.16)
		rb.linear_velocity = Vector3(cos(ang) * 0.30, -0.1, sin(ang) * 0.22)
		rb.angular_velocity = Vector3(randf_range(-1.1, 1.1), randf_range(-1.1, 1.1), randf_range(-1.1, 1.1))
		_film_pieces.append({"node": rb, "life": FILM_PIECE_LIFE_S})

## Per-tick: nudge the loose pieces along belt travel while the belt runs, and retire
## them after their lifetime (they've ridden up / gone into the shredder). Mass has
## already flowed via the invisible rider, so retiring the visuals is ledger-neutral.
func _tick_film_pieces(delta: float, _live_speed: float, _running: bool) -> void:
	if _film_pieces.is_empty():
		return
	var i : int = _film_pieces.size() - 1
	while i >= 0:
		var e : Dictionary = _film_pieces[i]
		var rb = e["node"]
		e["life"] = float(e["life"]) - delta
		if rb == null or not is_instance_valid(rb) or float(e["life"]) <= 0.0:
			if is_instance_valid(rb):
				(rb as Node).queue_free()
			_film_pieces.remove_at(i)
			i -= 1
			continue
		# No conveyor nudge — pushing them up the 35° incline is what flung them into
		# the air. They just fall open + tumble on the deck, then despawn (the bale's
		# MASS still rides to the shredder via the invisible rider). #4v2
		i -= 1

## #211a/#211e — bale yaw deviation (degrees, [-180, +180]) of the bale's long
## axis vs the belt's local +Z travel direction, evaluated in the XZ plane of
## the belt. Used by accept_bale to tag cross-wise riders AND by the forklift
## alignment ghost (#211e) to colour the ghost green/red. 0° = perfectly
## lengthwise, ±90° = cross-wise. Returns 0.0 for null or invalid bales.
func _bale_yaw_deviation_deg(bale: Node3D) -> float:
	if bale == null or not is_instance_valid(bale):
		return 0.0
	# The bale's LONG axis is its local +X — the catalog size is (1.45, 1.25, 1.25)
	# so X is the 1.45 m length, and the feeder aligns X onto belt travel. #233 — this
	# previously sampled local +Z, which mis-read EVERY correctly-fed bale as ~90°
	# cross-wise → a spurious BELT-JAM that latched and permanently deadlocked the
	# feed loop (the feeders stuck in FEED, LINE FLOW fed 0 kg). Measure +X instead.
	var bale_long_world : Vector3 = bale.global_transform.basis.x
	var to_local : Basis = global_transform.basis.inverse()
	var bale_long_local : Vector3 = to_local * bale_long_world
	# Drop Y so we only compare yaw on the XZ plane.
	bale_long_local.y = 0.0
	if bale_long_local.length_squared() < 1e-6:
		return 0.0
	bale_long_local = bale_long_local.normalized()
	# Belt's travel axis in belt-local = +Z. Angle to it (XZ).
	var ang : float = atan2(bale_long_local.x, bale_long_local.z)
	# Fold to ±90° — a bale rotated 180° is still "lengthwise", just facing
	# the other way; both ends look the same to the shredder mouth.
	var deg : float = rad_to_deg(ang)
	if deg > 90.0:
		deg -= 180.0
	elif deg < -90.0:
		deg += 180.0
	return deg

## #211e — convenience for the forklift alignment ghost: the belt's travel
## axis as a world-space direction (deck +Z). Used by the ghost projector to
## lay the lengthwise pose onto the deck without copying belt internals.
func belt_travel_dir_world() -> Vector3:
	var d : Vector3 = global_transform.basis.z
	d.y = 0.0
	if d.length_squared() < 1e-6:
		return Vector3.FORWARD
	return d.normalized()

## How many bales are currently on the belt.
func rider_count() -> int:
	return _riders.size()

# =============================================================================
# SIM
# =============================================================================
func _process(delta: float) -> void:
	# Shredder digests the throat down over time — the eaten mass becomes shredded
	# OUTPUT (flakes) at the discharge: fills a container if one sits there, else
	# grows a floor pile (a real collidable mountain). #8
	# Only an ACTUAL shredder pulverizes — with none present, material is not turned
	# into flakes out of thin air; it just isn't digested (#26).
	if _shredder_ok():
		var before_fill := fill
		fill = maxf(0.0, fill - digest_rate * delta)
		var digested : float = before_fill - fill
		if digested > 0.0 and before_fill > 0.0:
			# Draw the kilograms PROPORTIONALLY out of what is actually in the
			# throat.
			var kg_out : float = _throat_kg * (digested / before_fill)
			kg_out = minf(kg_out, _throat_kg)
			_throat_kg -= kg_out
			if kg_out > 0.0:
				_emit_output(kg_out, delta)
				if _cached_shredder != null and is_instance_valid(_cached_shredder) and _cached_shredder.has_method("set_feed_throughput"):
					var rate_kg_h : float = (kg_out / maxf(delta, 0.001)) * 3600.0
					_cached_shredder.call("set_feed_throughput", rate_kg_h)
		elif _cached_shredder != null and is_instance_valid(_cached_shredder) and _cached_shredder.has_method("set_feed_throughput"):
			_cached_shredder.call("set_feed_throughput", 0.0)
	var running := is_running()
	# #214 belt-speed ramp — the PLC setpoint is binary (running ? belt_speed : 0)
	# but the physical belt coasts smoothly between those two states. Push the
	# setpoint through the SmoothedRate so a stop intent decays over ~2.5 s of
	# motor coast-down instead of snapping in one frame. The cascade-stop
	# behaviour upstream is preserved — is_running() flipping false IS the
	# stop intent, the ramp just stretches its physical effect.
	var setpoint : float = belt_speed if running else 0.0
	var live_speed : float = _belt_speed_smooth.approach(setpoint, delta) if _belt_speed_smooth != null else setpoint
	# Drive the textured belt scroll speed from the live RAMPED state so a stopping
	# belt is OBVIOUSLY winding down (the slats slow visibly) and a starting one
	# is OBVIOUSLY winding up. Scale by live_speed so a slow belt scrolls slowly.
	# Multiplier 0.25 matches the intake-belt convention.
	_set_scroll_speed(live_speed * 0.25)
	# Keep the walkable collider's belt-carry meta in step with the LIVE (ramped)
	# belt speed (NOT the binary run-state) so the player is carried at the actual
	# slat speed during coast-down. Bales mid-ride keep moving until the belt
	# physically stops, matching what an operator sees on a real coast-down.
	if _belt_body != null and is_instance_valid(_belt_body):
		_belt_body.set_meta("belt_speed", live_speed)
		# #172-opzetband — when the deck has the BeltSurface script attached
		# (opzetband path in PlaceableCatalog.build_node), keep BeltSurface's
		# belt_speed_mps in step. BeltSurface itself ALSO low-passes its own
		# setpoint, but since we feed it the already-ramped live_speed the
		# inner ramp is a near-no-op (target tracks within its tau) — shader
		# scroll, rider-bale progress, legacy meta, and the physical carry all
		# converge on the same coast-down curve.
		if "belt_speed_mps" in _belt_body:
			_belt_body.set("belt_speed_mps", live_speed)
	# #214 — rider advance uses the LIVE (ramped) belt speed so a bale already
	# on the belt coasts forward during stop, instead of teleport-freezing the
	# instant the cascade trips. Feeding (at-top mass transfer) still gates on
	# the binary `running` flag — once the throat is full it should NOT drip more
	# in just because the belt slats are still creeping.
	var i := _riders.size() - 1
	while i >= 0:
		var r : Dictionary = _riders[i]
		# A rider's bale can be freed EXTERNALLY mid-ride (clamp grab, wire cut,
		# despawn). Fetch UNTYPED first: `var n : Node3D = r["node"]` on a freed
		# instance throws "Trying to assign invalid previously freed instance"
		# BEFORE any is_instance_valid guard can run — measured 2026-08-07 in
		# the operator's save1 world, where the error repeated every frame
		# (frozen game, 54-error spam). A dead rider is dropped, not replayed.
		var rider_raw = r.get("node")
		if rider_raw == null or not is_instance_valid(rider_raw):
			_riders.remove_at(i)
			i -= 1
			continue
		if r["feeding"]:
			# At the top: transfer mass into the throat, but only while there's
			# room (running). This is the portioned drop.
			if running:
				# Clamp the FRACTION by the room actually left in the throat, so
				# the old `fill = minf(1.0, fill + give)` can no longer swallow
				# the difference silently — that clamp destroyed mass.
				var room : float = maxf(0.0, 1.0 - fill)
				var give : float = min(min(r["mass"], feed_rate * delta), room)
				if give > 0.0:
					r["mass"] = r["mass"] - give
					fill += give
					# Carry the matching kilograms across with it.
					_throat_kg += give * float(r.get("kg_total", 0.0))
				if r["mass"] <= 0.0:
					var node : Node3D = r["node"]
					_riders.remove_at(i)
					bale_consumed.emit(node)
					if is_instance_valid(node):
						node.queue_free()
		else:
			# Riding the belt toward the top — at the live (ramped) speed so the
			# rider keeps gliding during coast-down even though `running` may
			# already be false.
			if live_speed > 0.0001:
				r["progress"] = minf(1.0, r["progress"] + (live_speed * delta) / maxf(_path_total, 0.001))
				_place_rider(r)
				if r["progress"] >= 1.0:
					r["feeding"] = true
		i -= 1
	# ── #211 per-tick rule enforcement ────────────────────────────────────────
	# These run AFTER the rider advance so the orientation timer, pairwise
	# spacing, and occupancy heuristics see this tick's positions. Skip when
	# already faulted — the latch holds until reset_faults() and we don't
	# want to keep re-raising the same alarm every frame.
	_tick_feeding_rules(delta)
	_tick_film_pieces(delta, live_speed, running)   # #4 — advance the physical fall-apart pieces

## #211a/#211b/#211c — per-tick enforcement of the three operator-spec feeding
## rules. Returns early when already faulted (the latch holds until reset). Each
## rule is independent: cross-wise bales each count down their own timer; the
## spacing violation is a single belt-wide counter; the thermal grace is a
## single belt-wide accumulator. They produce three distinct fault signals so
## the HMI can tell the operator WHAT went wrong, not just THAT something did.
func _tick_feeding_rules(delta: float) -> void:
	if is_faulted():
		return
	# ── #211a — cross-wise rider timer ─────────────────────────────────────
	for r in _riders:
		if not bool(r.get("cross_wise", false)):
			continue
		r["cross_wise_t"] = float(r.get("cross_wise_t", JAM_TIMER_S)) - delta
		if float(r["cross_wise_t"]) <= 0.0:
			_raise_fault("belt_jam", _ALARM_BELT_JAM)
			return   # one fault per tick — let the latch settle
	# ── #211b — pairwise spacing along the path ────────────────────────────
	# Sort a working copy by progress (riders advance asynchronously when
	# feeding=true) and walk consecutive pairs. Anything tighter than
	# MIN_SPACING_M counts as a violation for this tick; the per-belt counter
	# trips after SPACING_VIOLATION_FRAMES of sustained crowding (~0.5s @ 60fps).
	var sorted_riders : Array = _riders.duplicate()
	sorted_riders.sort_custom(func(a, b): return float(a["progress"]) < float(b["progress"]))
	var any_tight : bool = false
	for k in range(1, sorted_riders.size()):
		var prev_p : float = float(sorted_riders[k - 1]["progress"])
		var next_p : float = float(sorted_riders[k]["progress"])
		var gap_m : float = (next_p - prev_p) * _path_total
		if gap_m < MIN_SPACING_M:
			any_tight = true
			break
	if any_tight:
		_spacing_violation_frames += 1
		if _spacing_violation_frames > SPACING_VIOLATION_FRAMES:
			_raise_fault("intake_overfill", _ALARM_INTAKE_OVERFILL)
			return
	else:
		_spacing_violation_frames = 0
	# ── #211c — sustained belt occupancy → thermal shutdown ────────────────
	# rider_length defaults to BALE_LENGTH_M (1.4 m) so a single bale on a 6 m
	# path counts as ~23% occupancy. Beyond MAX_BELT_OCCUPANCY for THERMAL_GRACE_S
	# the drive overheats and trips. Path-length check guards against /0 on a
	# zero-length belt (test scene with deck_length = incline_run = 0).
	if _path_total > 0.01:
		var total_len : float = 0.0
		for r2 in _riders:
			total_len += float(r2.get("rider_length", BALE_LENGTH_M))
		var occupancy : float = total_len / _path_total
		if occupancy > MAX_BELT_OCCUPANCY:
			_thermal_grace_t += delta
			if _thermal_grace_t >= THERMAL_GRACE_S:
				_raise_fault("thermal_shutdown", _ALARM_THERMAL_SHUTDOWN)
				return
		else:
			_thermal_grace_t = 0.0

## Position a rider bale along the path from its progress (0..1).
func _place_rider(r: Dictionary) -> void:
	# Untyped fetch first — a typed declaration on a freed instance throws
	# before the guard below could ever run (see the rider-loop note above).
	var node_raw = r.get("node")
	if node_raw == null or not is_instance_valid(node_raw):
		return
	var node : Node3D = node_raw
	var dist : float = r["progress"] * _path_total
	var pos : Vector3
	if dist <= deck_length:
		# Horizontal deck run.
		pos = Vector3(r["lane_x"], deck_height + 0.15, dist)
	elif dist <= deck_length + _incline_hyp:
		# Up the incline at incline_deg.
		var slope_d : float = dist - deck_length
		pos = Vector3(r["lane_x"],
			deck_height + 0.15 + slope_d * sin(_incline_angle),
			deck_length + slope_d * cos(_incline_angle))
	else:
		# Horizontal discharge tray at the top (opzetband 3A/3B's 0.5 m flat).
		var flat_d : float = dist - deck_length - _incline_hyp
		pos = Vector3(r["lane_x"],
			deck_height + 0.15 + _incline_hyp * sin(_incline_angle),
			deck_length + _incline_hyp * cos(_incline_angle) + flat_d)
	node.position = pos

# =============================================================================
# SHREDDED OUTPUT (#8) — eaten throat mass → flakes at the discharge
# =============================================================================
# ── DISCHARGE GEOMETRY — TWO points, deliberately (audit 2026-08-16) ──────────
# The belt has a discharge LIP (high, at the end of the belt surface, where
# material physically leaves the belt) and a discharge LANDING point (on the
# floor, past the end of the structure, where the shredded output comes to rest).
# They are NOT the same point and the code needs both:
#
#   LANDING (_discharge_pos)  — floor level. Used by _container_at (measures 3 m
#     to FLOOR-SEATED container origins), _ensure_output_pile (a FloorPile sits on
#     the floor) and _shredder_ok (measures 6 m to a FLOOR-SEATED machine origin).
#     Raising this to the real lip height would move it 4-7 m away from every one
#     of those origins and stop containers filling / lose the shredder interlock.
#   LIP (_discharge_lip_pos) — belt-surface level at the very end of the path.
#     Used for the falling-flake visual, which used to pop out of thin air 1.7 m
#     over the floor beside the machine instead of off the end of the belt.
#
# operator_issues_2026-07-20.md:130-133 names the old single-point version as an
# open root cause ("y = 0.0 at a z beyond the top of the incline ... ignoring
# top_flat_m"). top_flat_m is now honoured by both points.

## Horizontal distance from the END of the belt structure to the floor landing
## point. UNSOURCED — no docs/plant/ entry gives this overhang; it is carried
## forward unchanged from the original expression rather than re-invented, and is
## an OPEN OPERATOR QUESTION. LegacyPropsSpawner.gd:311 holds a third copy of the
## same idea with a different value (+2.0) and is deliberately left alone: it
## positions a machine, and moving shipped machines needs an operator ruling.
const DISCHARGE_OVERHANG_M : float = 1.5

## The incline angle / slope length for the CURRENT exports. _ready() caches these
## into _incline_angle / _incline_hyp; these helpers are the single formula both
## the cache and the discharge geometry read, so a belt whose exports were set
## after construction can still be asked where its discharge is.
func _incline_angle_rad() -> float:
	return deg_to_rad(incline_deg)

func _incline_hyp_m() -> float:
	return incline_run / maxf(cos(_incline_angle_rad()), 0.01)

## Local Z of the very END of the belt structure: top of the incline plus the
## horizontal discharge tray when there is one. `incline_run` is already the
## HORIZONTAL run (hyp = run / cos θ, so hyp·cos θ == run), which is why this is
## not the hypotenuse — but `top_flat_m` was genuinely missing.
func _end_z() -> float:
	return deck_length + incline_run + maxf(top_flat_m, 0.0)

## Local Z of the floor landing point.
func _landing_z() -> float:
	return _end_z() + DISCHARGE_OVERHANG_M

## LANDING point — on the FLOOR (belt origin plane), just past the end of the
## belt. y is 0 in local space ON PURPOSE: every caller of this measures to a
## floor-seated origin. See the block comment above before "fixing" the height.
func _discharge_pos() -> Vector3:
	return to_global(Vector3(0.0, 0.0, _landing_z()))

## LIP — the belt SURFACE at the very end of the path: the point material is
## actually released from. Same arithmetic _place_rider uses for a rider at
## progress 1.0, minus the 0.15 m rider stand-off, so the two can never drift.
func _discharge_lip_pos() -> Vector3:
	var a : float = _incline_angle_rad()
	return to_global(Vector3(0.0, deck_height + _incline_hyp_m() * sin(a), _end_z()))

var _cached_containers: Array[Node] = []

## A waste container parked at the discharge (fills inside), or null → floor pile.
func _container_at(pos: Vector3) -> Node:
	for c in _cached_containers:
		if is_instance_valid(c):
			if (c as Node3D).global_position.distance_to(pos) < 3.0:
				return c
	return null

## Lazily spawn the floor pile (a real collidable growing mound) at the discharge.
func _ensure_output_pile(pos: Vector3) -> void:
	if _output_pile != null and is_instance_valid(_output_pile):
		return
	var fp := load("res://src/sim/FloorPile.gd")
	if fp == null:
		return
	_output_pile = fp.new()
	(_output_pile as Node).name = "ShredderOutputPile"
	get_tree().current_scene.add_child(_output_pile)
	(_output_pile as Node3D).global_position = pos

## Route shredded flakes: into a container at the discharge if present (overflow
## spills to the pile), else grow the pile. Plus a trickle of falling-flake visuals.
func _emit_output(kg: float, delta: float) -> void:
	var disc := _discharge_pos()
	var overflow := kg
	var bin := _container_at(disc)
	if bin != null:
		overflow = float(bin.call("add", kg, OUTPUT_DENSITY, -1))
	if overflow > 0.0:
		_ensure_output_pile(disc)
		if _output_pile != null and is_instance_valid(_output_pile):
			# FloorPile.add returns the kg it REFUSED once max_radius_m is hit.
			# That return used to be discarded, so mass vanished silently at a
			# full pile. Push it back into the throat instead — a full discharge
			# backs the belt up, which is what a real one does.
			var refused : float = float(_output_pile.call("add", overflow, OUTPUT_DENSITY))
			if refused > 0.0:
				_throat_kg += refused
		else:
			_throat_kg += overflow   # nowhere to put it: keep it, never drop it
	_flake_t += delta
	if _flake_t >= 0.12 and _flake_live < OUTPUT_FLAKE_MAX:
		_flake_t = 0.0
		_spawn_output_flake(_discharge_lip_pos(), disc)

## A small flake cube that leaves the belt AT THE LIP and tumbles onto the heap
## on the floor. It used to be spawned at `landing + 1.7 m`, i.e. hovering at
## chest height next to the machine with the actual discharge 4-7 m above it.
func _spawn_output_flake(lip: Vector3, landing: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.06, 0.10)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.55, 0.52)
	m.roughness = 0.85
	mi.material_override = m
	get_tree().current_scene.add_child(mi)
	mi.global_position = lip + Vector3(randf_range(-0.2, 0.2), 0.10, randf_range(-0.2, 0.2))
	_flake_live += 1
	var land := landing + Vector3(randf_range(-0.5, 0.5), 0.12, randf_range(-0.5, 0.5))
	var t := create_tween()
	t.tween_property(mi, "global_position", land, OUTPUT_FLAKE_LIFE).set_ease(Tween.EASE_IN)
	t.tween_callback(_on_flake_done.bind(mi))

func _on_flake_done(mi: Node) -> void:
	_flake_live = maxi(0, _flake_live - 1)
	if is_instance_valid(mi):
		mi.queue_free()
