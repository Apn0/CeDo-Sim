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

# Cumulative counters (HUD / tests). bales_accepted only counts scanned bales
# that made it onto the belt; bales_rejected counts scan-gate refusals.
var bales_accepted : int = 0
var bales_rejected : int = 0

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
	_incline_angle = deg_to_rad(incline_deg)
	_incline_hyp   = incline_run / maxf(cos(_incline_angle), 0.01)
	_path_total = deck_length + _incline_hyp + maxf(top_flat_m, 0.0)
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
	area.position = Vector3(0.0, 0.0, deck_length + incline_run + 1.5)
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

func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.45, 0.48); steel.roughness = 0.6; steel.metallic = 0.3
	# Static fallback material in case the textured one fails to load; the textured
	# scrolling material is then applied per-surface below.
	var belt_mat := StandardMaterial3D.new()
	belt_mat.albedo_color = Color(0.12, 0.12, 0.13); belt_mat.roughness = 0.9
	var guard := StandardMaterial3D.new()
	guard.albedo_color = Color(0.92, 0.78, 0.18); guard.roughness = 0.7   # safety yellow
	# Horizontal deck belt surface — skipped when there is no flat section (Westa, opzetband 1).
	if deck_length > 0.01:
		var deck := MeshInstance3D.new()
		var dm := BoxMesh.new(); dm.size = Vector3(deck_width, 0.10, deck_length)
		deck.mesh = dm
		_belt_mat_deck = load("res://src/build/PlaceableCatalog.gd").make_belt_material(0.0, Vector2(1.0, deck_length * 0.5))
		deck.material_override = _belt_mat_deck if _belt_mat_deck != null else belt_mat
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
	# Inclined belt section — a long box rotated about X, mounted at the deck end.
	var inc := MeshInstance3D.new()
	var hyp := _incline_hyp
	var im := BoxMesh.new(); im.size = Vector3(deck_width * 0.8, 0.10, hyp)
	inc.mesh = im
	_belt_mat_incline = load("res://src/build/PlaceableCatalog.gd").make_belt_material(0.0, Vector2(1.0, hyp * 0.5))
	inc.material_override = _belt_mat_incline if _belt_mat_incline != null else belt_mat
	# Pivot the incline so its base sits at the deck's far end and it rises incline_deg.
	var inc_pivot := Node3D.new()
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
	# Top end: either a horizontal discharge tray (opzetband 3A/3B's 0.5 m flat top)
	# OR the legacy drop snout. Only one — the flat tray is the realistic version.
	if top_flat_m > 0.01:
		var tray := MeshInstance3D.new()
		var tm := BoxMesh.new(); tm.size = Vector3(deck_width * 0.8, 0.10, top_flat_m)
		tray.mesh = tm
		_belt_mat_top = load("res://src/build/PlaceableCatalog.gd").make_belt_material(0.0, Vector2(1.0, top_flat_m * 0.5))
		tray.material_override = _belt_mat_top if _belt_mat_top != null else belt_mat
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
	# "belt_speed" meta is belt_speed while running / 0.0 while stopped. The player
	# controller reads this off the body it's standing on and drags itself along.
	_belt_body = body
	body.add_to_group("belt")
	body.set_meta("belt_speed", belt_speed if is_running() else 0.0)
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
## Is the belt currently moving? False while the throat is full, AND false when the
## PLC interlock trips because there's no healthy shredder downstream (#27).
func is_running() -> bool:
	return fill < fill_setpoint and _shredder_ok()

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
		if n3d.has_method("is_running"):
			return bool(n3d.call("is_running"))
		return true
	return false   # no shredder present → PLC keeps the belt stopped

## Minimum clear distance at the loading end before another bale may be dropped —
## roughly a bale length + a gap, so bales never land inside one another.
const LOAD_ZONE_M : float = 1.7

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
func accept_bale(bale: Node3D, lane: int = 0) -> bool:
	if bale == null:
		return false
	if not bool(bale.get_meta("scanned", false)):
		bales_rejected += 1
		bale_rejected.emit(bale, "not scanned")
		return false
	if not can_accept():
		bale_rejected.emit(bale, "load zone occupied")
		return false
	# Re-parent onto the belt; freeze it so it rides as a kinematic prop.
	if bale.get_parent():
		bale.get_parent().remove_child(bale)
	add_child(bale)
	if bale is RigidBody3D:
		(bale as RigidBody3D).freeze = true
	# lane 0 = CENTRE of the deck (the feeders feed here so bales ride down the
	# middle, not the old left/right zigzag); lane 1 = offset right if ever needed.
	var lane_x : float = (0.0 if lane == 0 else 0.5 * deck_width * 0.5)
	_riders.append({
		"node": bale, "progress": 0.0, "mass": 1.0,
		"feeding": false, "lane_x": lane_x,
	})
	_place_rider(_riders.back())
	bales_accepted += 1
	bale_accepted.emit(bale)
	return true

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
		if digested > 0.0:
			_emit_output(digested * OUTPUT_KG_PER_FILL, delta)
	var running := is_running()
	# Drive the textured belt scroll speed from the live PLC state so a stopped
	# belt is OBVIOUSLY stopped (the slats freeze) and a running one is OBVIOUSLY
	# moving. Scale by belt_speed so a slow belt scrolls slowly. (#texturedbelts)
	_set_scroll_speed((belt_speed * 4.0) if running else 0.0)
	# Keep the walkable collider's belt-carry meta in step with the PLC run-state so
	# the player is carried only while the belt actually moves (0.0 when stopped).
	if _belt_body != null and is_instance_valid(_belt_body):
		_belt_body.set_meta("belt_speed", belt_speed if running else 0.0)
	var i := _riders.size() - 1
	while i >= 0:
		var r : Dictionary = _riders[i]
		if r["feeding"]:
			# At the top: transfer mass into the throat, but only while there's
			# room (running). This is the portioned drop.
			if running:
				var give : float = min(r["mass"], feed_rate * delta)
				r["mass"] = r["mass"] - give
				fill = minf(1.0, fill + give)
				if r["mass"] <= 0.0:
					var node : Node3D = r["node"]
					_riders.remove_at(i)
					bale_consumed.emit(node)
					if is_instance_valid(node):
						node.queue_free()
		else:
			# Riding the belt toward the top — only while the belt runs.
			if running:
				r["progress"] = minf(1.0, r["progress"] + (belt_speed * delta) / maxf(_path_total, 0.001))
				_place_rider(r)
				if r["progress"] >= 1.0:
					r["feeding"] = true
		i -= 1

## Position a rider bale along the path from its progress (0..1).
func _place_rider(r: Dictionary) -> void:
	var node : Node3D = r["node"]
	if node == null or not is_instance_valid(node):
		return
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
## Ground point just past the top of the incline where shredded flakes drop.
func _discharge_pos() -> Vector3:
	return to_global(Vector3(0.0, 0.0, deck_length + incline_run + 1.5))

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
			_output_pile.call("add", overflow, OUTPUT_DENSITY)
	_flake_t += delta
	if _flake_t >= 0.12 and _flake_live < OUTPUT_FLAKE_MAX:
		_flake_t = 0.0
		_spawn_output_flake(disc)

## A small flake cube that emerges above the discharge and tumbles onto the heap.
func _spawn_output_flake(landing: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.06, 0.10)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.55, 0.52)
	m.roughness = 0.85
	mi.material_override = m
	get_tree().current_scene.add_child(mi)
	mi.global_position = landing + Vector3(randf_range(-0.2, 0.2), 1.7, randf_range(-0.2, 0.2))
	_flake_live += 1
	var land := landing + Vector3(randf_range(-0.5, 0.5), 0.12, randf_range(-0.5, 0.5))
	var t := create_tween()
	t.tween_property(mi, "global_position", land, OUTPUT_FLAKE_LIFE).set_ease(Tween.EASE_IN)
	t.tween_callback(_on_flake_done.bind(mi))

func _on_flake_done(mi: Node) -> void:
	_flake_live = maxi(0, _flake_live - 1)
	if is_instance_valid(mi):
		mi.queue_free()
