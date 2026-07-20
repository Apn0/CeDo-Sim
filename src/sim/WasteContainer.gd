extends StaticBody3D
class_name WasteContainer

## A physical waste/buffer container — a steel skip, an under-conveyor bay, or an
## IBC tote — replacing the old bookkeeping `stored_kg` meta with a real entity
## that has CAPACITY (m³), BULK DENSITY (kg/m³), an OVERFLOW STATE, accepts only
## the stream classes it's designed for, and routes spillover to a floor pile when
## it overflows.
##
## A container has FOUR fill states:
##   • NONE     — under safe-fill threshold
##   • WARNING  — over safe-fill (HUD shows amber, crew may be dispatched)
##   • SPILLING — at usable capacity, excess is leaving the container (floor pile)
##   • BLOCKED  — pile bridges/blocks the chute or surrounding equipment
##
## All maths runs in SI (kg + m³). LineFlow calls `add(mass_kg, density_kg_m3,
## stream_class)`; the container decides if it can accept and pushes overflow to
## any `floor_pile` group neighbour. Pure-logic methods (add/empty/state) make
## the model headless-testable.

signal fill_changed(fraction: float)
signal overflow_state_changed(state: int)

enum Stream {
	COARSE_FILM,       # mixed plastic film reject (the PLASTIC-stickered skips)
	FINES,             # fine fibres / shredded residue (under-conveyor bays)
	DIRT,              # contaminant scraper bins (sand, organics)
	METAL,             # overband magnet collect
	SLUDGE,            # wet cyclone underflow
	EFFLUENT,          # process water / chemicals → IBC tote
	POLY_REJECT,       # off-spec polymer kicked out by sorters
}

enum OverflowState { NONE, WARNING, SPILLING, BLOCKED }

# ── Configuration (set per container type — see PlaceableCatalog) ─────────────
## Geometric usable volume (m³). Spillage starts when loose volume exceeds
## SAFE_FILL × this. A separate overflow_budget_m3 buffers a little before the
## container is BLOCKED.
@export var capacity_m3       : float = 1.5
## Bulk density override (kg/m³). Most containers blend whatever they receive;
## leave 0 to compute the running blend from each `add()` call's density.
@export_range(0.0, 2000.0) var override_density_kg_m3 : float = 0.0
## Maximum overflow the SURROUNDING bay/floor can hold before the bin is "blocked"
## by its own pile (no more material can leave the chute above).
@export var overflow_budget_m3 : float = 0.6
## Safe-fill fraction — crew dispatch fires when fill_fraction ≥ this.
@export var safe_fill : float = 0.85
## Which stream classes this bin accepts. Empty = accept everything (default
## catch-all, used when LineFlow can't find a stream-specific bin).
@export var accepted_streams : Array[int] = []
## True for movable bins (steel skip, fines bin on castors) — the forklift can
## pick this up. False for fixed bays/IBC totes.
@export var movable : bool = true
## True for FLUID containers (IBC tote) — the operator drains them on foot via
## a valve interact prompt (E within DRAIN_RANGE) rather than forklift-dumping.
## Drained fluid is just removed from the world (in reality it goes to a sewer
## or another tank — modelled as bookkeeping for now).
@export var fluid_valve : bool = false
## npc-05 — True for the OUTDOOR open-top end-destination skip: the forklift
## dumps full indoor bins here and the crew never empties it on foot (a full
## outdoor skip is a HUD/gauge warning only — the truck swap that would relieve
## it is outside sim scope). Joins the "waste_container_outdoor" group in
## _ready() so generators can scan outdoor destinations cheaply.
@export var outdoor_skip : bool = false

const DRAIN_RANGE : float = 1.6
var _player_near : bool = false

# ── Runtime state ─────────────────────────────────────────────────────────────
var mass_kg          : float = 0.0
var blended_density  : float = 200.0      # kg/m³ running blend
var overflow_mass_kg : float = 0.0        # spilled but still on the ground nearby
var overflow_state   : int   = OverflowState.NONE

# Where spillover goes when the bin's own overflow_budget is exceeded — a nearby
# FloorPile (see src/sim/FloorPile.gd). Resolved lazily on first overflow.
var floor_pile : Node = null

# Visible overflow mound — a procedural cone grown each frame from
# overflow_mass_kg. Angle of repose ~33° gives h = r × tan(33°) ≈ r × 0.65.
@export var mound_color    : Color = Color(0.40, 0.40, 0.42)
@export var mound_angle_deg : float = 33.0
var _mound_mesh : MeshInstance3D = null
# #159 — solid collider for the spilled mound so you can't walk through the heap
# that's banked up beside an overflowing bin. Grown with the mound each update.
var _mound_col    : CollisionShape3D = null
var _mound_cshape : CylinderShape3D = null

# Cached last-frame fraction so we don't spam fill_changed every tick.
var _last_frac : float = -1.0

# ── Visible fullness gauge (#160) ─────────────────────────────────────────────
## A floating bar + % label above the bin so the operator sees at a glance how
## full it is and whether it's warning/spilling/blocked. Height above the bin's
## local origin — tune per container if a tall bin hides it.
@export var show_gauge   : bool  = true
@export var gauge_height : float = 2.2
const _GAUGE_BAR_H : float = 0.8
var _gauge_root  : Node3D = null
var _gauge_fill  : MeshInstance3D = null
var _gauge_fill_mat : StandardMaterial3D = null
var _gauge_label : Label3D = null

# =============================================================================
func _ready() -> void:
	add_to_group("waste_container")
	# npc-05 — outdoor end-destination skips ALSO join a dedicated scan group so
	# generators can split indoor sources from outdoor destinations without
	# probing every container's properties. Read at tree-enter time: spawners
	# must set outdoor_skip BEFORE add_child() (ContainerGuideManager's real-
	# container spawn does exactly that).
	if outdoor_skip:
		add_to_group("waste_container_outdoor")
	_build_overflow_mound()
	if show_gauge:
		_build_fill_gauge()
	if fluid_valve:
		_build_valve_trigger()

# =============================================================================
# CORE API — LineFlow calls add(); UI reads fill_fraction() / state.
# =============================================================================
## Add `kg` of material with `density_kg_m3` and stream `cls`. Returns the mass
## that was ROUTED ELSEWHERE (overflow to floor / refused for wrong stream).
## Refused mass goes back to the caller so the simulation ledger stays balanced.
func add(kg: float, density_kg_m3: float, cls: int = -1) -> float:
	if kg <= 0.0:
		return 0.0
	# 1) Stream filter — refuse if this bin only accepts specific streams and
	#    `cls` isn't in the list. LineFlow's stream router falls back to a
	#    catch-all container (or a floor pile) for the refused mass.
	if cls >= 0 and not accepted_streams.is_empty() and cls not in accepted_streams:
		return kg
	# 2) Blend density (weighted by mass) so a partly-full sludge bin doesn't
	#    look "empty" just because someone tipped a kg of light film in.
	var d := override_density_kg_m3 if override_density_kg_m3 > 0.0 else density_kg_m3
	if d <= 0.0:
		d = 200.0   # safe default for unknown streams
	if mass_kg > 0.0:
		blended_density = (blended_density * mass_kg + d * kg) / (mass_kg + kg)
	else:
		blended_density = d
	# 3) Accept what fits under the OVERFLOW budget (capacity + bay buffer),
	#    spill the rest to overflow_mass_kg (visible spillover on the floor).
	var total_room_m3 := capacity_m3 + overflow_budget_m3
	var total_room_kg := total_room_m3 * blended_density
	var room_left := total_room_kg - (mass_kg + overflow_mass_kg)
	if room_left <= 0.0:
		# Container fully BLOCKED — nothing more accepted, all returns to caller.
		_update_state()
		return kg
	var accepted := minf(kg, room_left)
	# Split between the bin (up to its capacity) and the spillover pile.
	var bin_room_kg := maxf(0.0, capacity_m3 * blended_density - mass_kg)
	var to_bin := minf(accepted, bin_room_kg)
	mass_kg += to_bin
	overflow_mass_kg += accepted - to_bin
	_update_state()
	var refused := kg - accepted
	# If the bin has nowhere left even for its own overflow budget, push the
	# remainder out to a FloorPile nearby (the spec's "spillage means already
	# beyond controlled storage"). The pile may refuse too if it's maxed — that
	# returns to the caller and gets reported up the chain as truly lost.
	if refused > 0.0:
		var pile := _nearest_floor_pile()
		if pile != null:
			refused = pile.call("add", refused, blended_density)
	return refused

func _nearest_floor_pile() -> Node:
	var best : Node = null
	var best_d := 30.0
	for p in get_tree().get_nodes_in_group("floor_pile"):
		var pn := p as Node3D
		if pn == null:
			continue
		var d := pn.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = pn
	return best

## How full the container itself is (0..1+; > 1 means spillover is happening).
func fill_fraction() -> float:
	if capacity_m3 <= 0.0 or blended_density <= 0.0:
		return 0.0
	var cap_kg := capacity_m3 * blended_density
	return (mass_kg + overflow_mass_kg) / cap_kg

## True when fill or spillover should trigger crew attention.
func needs_emptying() -> bool:
	return fill_fraction() >= safe_fill

## Empty the bin (forklift dumps it at a tip zone, or worker resets it). Returns
## the kg removed so callers can ledger the dump if they want.
func empty() -> float:
	var removed := mass_kg + overflow_mass_kg
	mass_kg = 0.0
	overflow_mass_kg = 0.0
	blended_density = 200.0
	_update_state()
	return removed

# ── #198 NPC-autonomy lumps API ──────────────────────────────────────────────
# Thin aliases so EmptyLumpCartTask (and the board's destination logic) can treat
# a WasteContainer as a lumps sink without knowing its SI add()/fill model. Lumps
# from the laser filter are a coarse solid waste stream — route them through the
# same POLY_REJECT bucket the container already understands (dense chunky reject).
const _LUMPS_DENSITY_KG_M3 : float = 350.0   # cooled extruder lump density

## Receive `kg` of cooled lumps dumped by a forklift. Returns the mass that could
## NOT be accepted (overflowed / refused), matching add()'s ledger contract.
func receive_lumps(kg: float) -> float:
	return add(kg, _LUMPS_DENSITY_KG_M3, Stream.POLY_REJECT)

## Approximate "how many carts' worth" this bin holds, for the board's fill-based
## routing (LumpCart.FULL_THRESHOLD_KG ~ 200 kg per cart). Cheap integer estimate.
func lumps_count() -> int:
	return int(floor((mass_kg + overflow_mass_kg) / 200.0))

## True once the bin is at/over its safe-fill point — the board reads this to
## decide it should route the next load to a different (outdoor) container.
func is_full() -> bool:
	return needs_emptying()

# =============================================================================
# INTERNAL
# =============================================================================
func _update_state() -> void:
	var frac := fill_fraction()
	if absf(frac - _last_frac) > 0.001:
		_last_frac = frac
		emit_signal("fill_changed", frac)
	var new_state := overflow_state
	if mass_kg + overflow_mass_kg >= (capacity_m3 + overflow_budget_m3) * blended_density - 0.01:
		new_state = OverflowState.BLOCKED
	elif overflow_mass_kg > 0.0:
		new_state = OverflowState.SPILLING
	elif frac >= safe_fill:
		new_state = OverflowState.WARNING
	else:
		new_state = OverflowState.NONE
	if new_state != overflow_state:
		overflow_state = new_state
		emit_signal("overflow_state_changed", overflow_state)
	_update_mound()
	_update_gauge()

# =============================================================================
# FULLNESS GAUGE — floating bar + % label, colour-coded by overflow state
# =============================================================================
func _build_fill_gauge() -> void:
	_gauge_root = Node3D.new()
	_gauge_root.name = "FillGauge"
	_gauge_root.position = Vector3(0.0, gauge_height, 0.0)
	add_child(_gauge_root)
	# Dark background bar (full height).
	var bg := MeshInstance3D.new()
	var bgm := BoxMesh.new(); bgm.size = Vector3(0.14, _GAUGE_BAR_H, 0.04)
	bg.mesh = bgm
	var bgmat := StandardMaterial3D.new()
	bgmat.albedo_color = Color(0.06, 0.06, 0.07)
	bgmat.roughness = 0.9
	bg.material_override = bgmat
	_gauge_root.add_child(bg)
	# Coloured fill bar (scaled vertically by fill fraction, anchored at bottom).
	_gauge_fill = MeshInstance3D.new()
	var fm := BoxMesh.new(); fm.size = Vector3(0.11, _GAUGE_BAR_H, 0.05)
	_gauge_fill.mesh = fm
	_gauge_fill_mat = StandardMaterial3D.new()
	_gauge_fill_mat.albedo_color = Color(0.25, 0.75, 0.30)
	_gauge_fill_mat.emission_enabled = true
	_gauge_fill_mat.emission = Color(0.25, 0.75, 0.30)
	_gauge_fill_mat.emission_energy_multiplier = 0.35
	_gauge_fill.material_override = _gauge_fill_mat
	_gauge_root.add_child(_gauge_fill)
	# Billboard % + state label above the bar.
	_gauge_label = Label3D.new()
	_gauge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_gauge_label.font_size = 36
	_gauge_label.outline_size = 6
	_gauge_label.position = Vector3(0.0, _GAUGE_BAR_H * 0.5 + 0.18, 0.0)
	_gauge_root.add_child(_gauge_label)
	_update_gauge()

func _update_gauge() -> void:
	if _gauge_fill == null:
		return
	var frac : float = clampf(fill_fraction(), 0.0, 1.0)
	# Scale the fill bar's height by frac and shift it down so its BASE stays
	# anchored at the bottom of the background bar.
	_gauge_fill.scale.y = maxf(frac, 0.0001)
	_gauge_fill.position.y = -(1.0 - frac) * _GAUGE_BAR_H * 0.5
	# Colour by overflow state.
	var c : Color
	match overflow_state:
		OverflowState.BLOCKED:  c = Color(0.85, 0.12, 0.10)
		OverflowState.SPILLING: c = Color(0.92, 0.45, 0.10)
		OverflowState.WARNING:  c = Color(0.93, 0.80, 0.18)
		_:                      c = Color(0.25, 0.75, 0.30)
	if _gauge_fill_mat:
		_gauge_fill_mat.albedo_color = c
		_gauge_fill_mat.emission = c
	if _gauge_label:
		var pct := int(round(fill_fraction() * 100.0))
		var state_names : Array = ["", " WARN", " SPILL", " BLOCKED"]
		var state_txt : String = state_names[overflow_state] if overflow_state < state_names.size() else ""
		_gauge_label.text = "%d%%%s" % [pct, state_txt]
		_gauge_label.modulate = c

## The 0..1 fraction the gauge bar is currently showing (for tests / HUD).
func gauge_display_fraction() -> float:
	return clampf(fill_fraction(), 0.0, 1.0)

# =============================================================================
# OVERFLOW MOUND — procedural cone that grows from overflow_mass_kg
# =============================================================================
## Build the (initially flat / hidden) overflow mound mesh as a child node, so
## later spillover can grow it in-place without spawning new nodes per frame.
func _build_overflow_mound() -> void:
	_mound_mesh = MeshInstance3D.new()
	_mound_mesh.name = "OverflowMound"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0          # cone — top radius 0
	cyl.bottom_radius = 0.5
	cyl.height = 0.001
	cyl.radial_segments = 16
	_mound_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = mound_color
	mat.roughness = 0.95
	_mound_mesh.material_override = mat
	_mound_mesh.position = Vector3(0.0, 0.0, 0.0)
	_mound_mesh.visible = false
	add_child(_mound_mesh)
	# Solid collider for the mound (#159). The container is already a StaticBody3D,
	# so the shape rides directly on it; disabled until material actually spills.
	_mound_col = CollisionShape3D.new()
	_mound_col.name = "MoundCollision"
	_mound_cshape = CylinderShape3D.new()
	_mound_cshape.radius = 0.5
	_mound_cshape.height = 0.02
	_mound_col.shape = _mound_cshape
	_mound_col.disabled = true
	add_child(_mound_col)

## Resize the conical mound to match overflow_mass_kg. Cone volume V = (1/3) π r² h
## with h = r × tan(angle_repose), so r = (3V / (π × tan(α)))^(1/3).
func _update_mound() -> void:
	if _mound_mesh == null:
		return
	if overflow_mass_kg <= 0.001:
		_mound_mesh.visible = false
		if _mound_col != null:
			_mound_col.disabled = true
		return
	var density := blended_density if blended_density > 0.0 else 200.0
	var vol_m3 := overflow_mass_kg / density
	var tan_a := tan(deg_to_rad(mound_angle_deg))
	var r : float = pow(3.0 * vol_m3 / (PI * tan_a), 1.0 / 3.0)
	var h : float = r * tan_a
	var cyl := _mound_mesh.mesh as CylinderMesh
	if cyl == null:
		return
	cyl.bottom_radius = r
	cyl.height = h
	# Cone is centred on its midpoint in Y — push it up by h/2 so the BASE sits
	# at the bin's local origin (the floor).
	_mound_mesh.position = Vector3(0.0, h * 0.5, 0.0)
	_mound_mesh.visible = true
	# Grow the mound's solid collider to match (#159).
	if _mound_cshape != null:
		_mound_cshape.radius = maxf(r, 0.05)
		_mound_cshape.height = maxf(h, 0.02)
		_mound_col.position = Vector3(0.0, h * 0.5, 0.0)
		_mound_col.disabled = false

# =============================================================================
# FLUID VALVE (IBC tote) — drain on foot via the interact key
# =============================================================================
## Proximity prompt + E to drain. Only built when fluid_valve is true (IBC tote).
func _build_valve_trigger() -> void:
	var area := Area3D.new()
	area.name = "ValveTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = DRAIN_RANGE
	cs.shape = sp
	cs.position = Vector3(0.0, 0.5, 0.0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_valve_body_entered)
	area.body_exited.connect(_on_valve_body_exited)

func _on_valve_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, "Open IBC valve (drain)")

func _on_valve_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _unhandled_input(event: InputEvent) -> void:
	if not fluid_valve or not _player_near:
		return
	if event.is_action_pressed("interact"):
		var drained := empty()
		print("[IBC] Valve opened — drained %.0f L (mass)" % drained)
		get_viewport().set_input_as_handled()
