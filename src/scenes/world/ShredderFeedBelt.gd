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
	_path_total = deck_length + _incline_hyp
	_build_visual()
	_build_collision()

func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.45, 0.48); steel.roughness = 0.6; steel.metallic = 0.3
	var belt_mat := StandardMaterial3D.new()
	belt_mat.albedo_color = Color(0.12, 0.12, 0.13); belt_mat.roughness = 0.9
	var guard := StandardMaterial3D.new()
	guard.albedo_color = Color(0.92, 0.78, 0.18); guard.roughness = 0.7   # safety yellow
	# Horizontal deck belt surface
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new(); dm.size = Vector3(deck_width, 0.10, deck_length)
	deck.mesh = dm; deck.material_override = belt_mat
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
	# Inclined belt (45°): a long box rotated about X, mounted at the deck end.
	var inc := MeshInstance3D.new()
	var hyp := _incline_hyp
	var im := BoxMesh.new(); im.size = Vector3(deck_width * 0.8, 0.10, hyp)
	inc.mesh = im; inc.material_override = belt_mat
	# Pivot the incline so its base sits at the deck's far end and it rises incline_deg.
	var inc_pivot := Node3D.new()
	inc_pivot.position = Vector3(0.0, deck_height, deck_length)
	inc_pivot.rotation.x = -_incline_angle   # tilt up toward +Z/+Y
	add_child(inc_pivot)
	inc.position = Vector3(0.0, 0.0, hyp * 0.5)
	inc_pivot.add_child(inc)
	# Incline side guards
	for sx in [-1.0, 1.0]:
		var g2 := MeshInstance3D.new()
		var gm2 := BoxMesh.new(); gm2.size = Vector3(0.08, 0.30, hyp)
		g2.mesh = gm2; g2.material_override = guard
		g2.position = Vector3(sx * deck_width * 0.4, 0.2, hyp * 0.5)
		inc_pivot.add_child(g2)
	# Drop snout at the top of the incline (where it dumps into the shredder).
	var snout := MeshInstance3D.new()
	var sm := BoxMesh.new(); sm.size = Vector3(deck_width * 0.7, 0.4, 0.8)
	snout.mesh = sm; snout.material_override = steel
	snout.position = Vector3(0.0, 0.0, hyp + 0.2)
	inc_pivot.add_child(snout)

## Solid collision so the player + vehicles stand/walk ON the belt instead of
## falling THROUGH it — both the flat deck and the inclined section. (The belt was
## pure MeshInstance visuals before, with no collider at all.)
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "BeltBody"
	add_child(body)
	# Flat deck slab.
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
	else:
		# Up the incline at incline_deg.
		var slope_d : float = dist - deck_length
		pos = Vector3(r["lane_x"],
			deck_height + 0.15 + slope_d * sin(_incline_angle),
			deck_length + slope_d * cos(_incline_angle))
	node.position = pos

# =============================================================================
# SHREDDED OUTPUT (#8) — eaten throat mass → flakes at the discharge
# =============================================================================
## Ground point just past the top of the incline where shredded flakes drop.
func _discharge_pos() -> Vector3:
	return to_global(Vector3(0.0, 0.0, deck_length + incline_run + 1.5))

## A waste container parked at the discharge (fills inside), or null → floor pile.
func _container_at(pos: Vector3) -> Node:
	for c in get_tree().get_nodes_in_group("waste_container"):
		if c is Node3D and (c as Node).has_method("add"):
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
