extends Node
class_name ContainerGuideManager

## Container-placement guide system (task #85).
##
## Several machines eject or reject material at a fixed point where a CATCH
## CONTAINER is supposed to stand (the overband magnet flings ferrous off its
## side into a steel skip; the flotation tank and the bezinkafscheider drop
## their heavies/reject at the downstream end into a waste container; the
## cutter-compactor sheds lumps that a fines bin catches). New operators don't
## know which bin goes where, so this manager paints a translucent CYAN
## HOLOGRAM of the correct container at each eject point.
##
## When a REAL container of (roughly) the right kind is parked within
## PROXIMITY_M of that point the hologram hides — the slot is satisfied; move
## the bin away and the hologram reappears. It is purely a visual guide: the
## holograms have no collision, are not saved, and never touch the material
## flow.
##
## npc-05 O1 — ONE exception to "purely visual": this manager also spawns the
## plant's REAL outdoor end-destination skip(s) once at world load (see
## WORLD_CONTAINER_SPAWNS). Those are functional WasteContainers the forklift
## dumps into — not holograms — and they are configured BEFORE add_child() so
## WasteContainer._ready() sees outdoor_skip when it joins its scan groups.
##
## Design notes
##   • Everything runs off two cheap timers (rescan ~1 s, proximity ~0.4 s), so
##     there are no per-frame raycasts — only a handful of slots ever exist.
##   • Machines are found through the "placed_object" group + the "placeable_id"
##     meta, exactly like LineFlow / BuildMode do it, so build-placed machines,
##     the Line 3C macro and the demo pipeline are all picked up identically.
##   • Guides are de-duped per (machine instance id + slot index); when a
##     machine is deleted its guides are freed on the next rescan.
##   • The manager owns NO state that needs saving — it rebuilds itself from the
##     live scene every rescan, so it survives load/teardown without bookkeeping.

# ── Registry: machine placeable_id -> Array of eject slots ────────────────────
# Each slot is { "offset": Vector3, "container_id": String }.
#   offset       — LOCAL eject point relative to the machine origin, at FLOOR
#                  level (y = 0), i.e. where a container would STAND to catch the
#                  falling material. The machine origin sits at its base, so a
#                  y of 0 keeps the ghost on the floor.
#   container_id — catalog id of the container that belongs there.
#
# Offsets were read off the machine builders in PlaceableCatalog.gd:
#   • overband_magnet (size 1.6 × 1.8 × 3.0): the ferrous discharge chute is on
#     the +X side toward the +Z (discharge) end → skip just past +X there.
#   • flotation_tank / _wide (size 4.5–6.0 × 1.6 × 9.0): the outlet roll that
#     drags the reject out is at the +Z end → waste container off the +Z end.
#   • sink_float (size 2.6 × 2.0 × 4.0): the overflow weirs / skim chutes are at
#     the +Z (downstream) end → waste container off the +Z end.
#   • cutter_compactor / compactor (size 2.6 × 2.8 × 2.6): lumps shed at the
#     drum's +Z outlet side → fines bin just past +Z.
# These are deliberately rough; the operator will fine-tune in-world.
const SLOT_REGISTRY : Dictionary = {
	"overband_magnet": [
		{"offset": Vector3(1.4, 0.0, 1.0), "container_id": "skip_steel"},
	],
	"flotation_tank": [
		{"offset": Vector3(0.0, 0.0, 5.6), "container_id": "waste_container"},
	],
	"flotation_tank_wide": [
		{"offset": Vector3(0.0, 0.0, 5.6), "container_id": "waste_container"},
	],
	"sink_float": [
		{"offset": Vector3(0.0, 0.0, 2.9), "container_id": "waste_container"},
	],
	"cutter_compactor": [
		{"offset": Vector3(0.0, 0.0, 1.9), "container_id": "fines_bin"},
	],
	"compactor": [
		{"offset": Vector3(0.0, 0.0, 1.9), "container_id": "fines_bin"},
	],
}

# Catalog ids that count as a "real container" able to satisfy a slot. A slot
# prefers its own expected container_id, but ANY of these within range hides the
# hologram (the operator may grab whatever bin is to hand).
const CONTAINER_IDS : Array[String] = [
	"skip_steel", "waste_container", "fines_bin", "cyclone_bin", "ibc_tote",
]

# ── npc-05 O1 — REAL container spawns (outdoor end-destination skip) ──────────
# Unlike SLOT_REGISTRY (machine-anchored holograms), each entry here spawns ONE
# real, functional container once at world load, at an anchor-local offset —
# the same unrotated `anchor + offset` frame LegacyPropsSpawner uses for its
# test skip (6, 0, 18) and dump zone (20, 0, 18).
#   offset       — metres from _get_factory_anchor(), floor level (y = 0).
#   container_id — catalog id to build (ghost = false, so it's a real body).
#   outdoor      — optional flag: configure the spawn as the outdoor open-top
#                  END-DESTINATION skip (outdoor_skip = true → joins the
#                  "waste_container_outdoor" scan group in its _ready(), 30 m³,
#                  generous overflow budget, accepts every stream). The
#                  forklift dumps full indoor bins here; the crew never
#                  empties it on foot.
# npc-05 — PLACEMENT, AND WHY IT IS NOT WHERE THE NAME SUGGESTS.
#
# This comment used to claim "~7 m outside the east-wing exterior facade". That
# was false: (12, 0, 28) measures 10.5 m INSIDE the building, under a roof 7.9 m
# overhead (footprint polygon from tools/regression/out/positions.json, confirmed
# in-world by an up-ray). The claim has been removed rather than left to mislead.
#
# The obvious repair — move it genuinely outdoors — was tried and MEASURED, not
# assumed. (12, 0, 45.5) = (-190.66, 139.54) is 6.9 m past the facade, 16.5 m
# inside the perimeter fence, 53.7 m from the nearest of the 42 placed machines.
# Geometrically ideal. It does not work, and the A/B is unambiguous
# (src/tests/test_npc05_realworld.gd, 200 sim-second watch, same build):
#   offset 45.5 (outdoors): forklift crosses out of the hall, then WEDGES 6.95 m
#                           short of the skip; 47 m covered in 141 s = 0.33 m/s.
#                           bin 275.00 -> 275.00 kg, skip 0.00 kg. Nothing moved.
#   offset 28.0 (indoors) : stage 2 bin 275.00 -> 0.00, skip 0.00 -> 275.00 kg.
#                           Stage 3 (operator CrewPanel force_task) another
#                           275.00 kg. The chain completes, twice, mass balanced.
#
# The blocker is NOT this constant — it is that the NPC vehicle autopilot is
# dead reckoning (BaseVehicle._npc_drive) over a navmesh with no obstacles baked
# into it, so it cannot route through a doorway. Both are already logged as
# npc-06 / npc-07 in docs/BACKLOG_ultracode_2026-07-19.md and are a navigation
# rewrite, not a placement tweak. Independent evidence from the same runs: in the
# shipped layout the yard forklift drives straight at the plant and jams against
# the perimeter fence's east end post at (-79.90, 157.14) — 2.92 m from the fence
# — at the identical coordinate in two separate runs.
#
# So the skip stays INDOORS for now: a working chain the operator can watch beats
# a correctly-placed skip nothing can reach. Flip this one number to 45.5 the day
# vehicle pathfinding lands; test_npc05_realworld.gd pins the expectation and will
# go red the moment the two disagree.
const WORLD_CONTAINER_SPAWNS : Array[Dictionary] = [
	# npc-05 O1 — end-destination skip (operator: verplaats gerust, positie is een gelabelde aanname)
	# OPERATOR RULING 2026-07-21: keep it INDOORS for now. He was shown the A/B
	# above and chose the position where the chain actually completes. Move it to
	# the yard only once npc-06/npc-07 navigation lands — until then the forklift
	# cannot reach an outdoor skip (measured: wedges 6.95 m short, 0 kg moved).
	{"offset": Vector3(12.0, 0.0, 28.0), "container_id": "skip_steel", "outdoor": true},
]

# ── Tunables ──────────────────────────────────────────────────────────────────
const RESCAN_INTERVAL    : float = 1.0    # s between machine rescans (add/remove guides)
const PROXIMITY_INTERVAL : float = 0.4    # s between proximity checks (show/hide)
const PROXIMITY_M        : float = 0.5    # a container this close (XZ) satisfies the slot
const USE_XZ_DISTANCE    : bool  = true   # measure on the floor plane (ignore height)

# ── Runtime state ─────────────────────────────────────────────────────────────
# key (String "machineInstanceId#slotIndex") -> ContainerGuide
var _guides : Dictionary = {}

var _rescan_timer    : Timer = null
var _proximity_timer : Timer = null


func _ready() -> void:
	_rescan_timer = Timer.new()
	_rescan_timer.wait_time = RESCAN_INTERVAL
	_rescan_timer.autostart = true
	_rescan_timer.timeout.connect(_rescan)
	add_child(_rescan_timer)

	_proximity_timer = Timer.new()
	_proximity_timer.wait_time = PROXIMITY_INTERVAL
	_proximity_timer.autostart = true
	_proximity_timer.timeout.connect(_update_proximity)
	add_child(_proximity_timer)

	# npc-05 O1 — spawn the real outdoor end-destination container(s) once, up
	# front, so the overflow chain has its dump target from the first board tick.
	_spawn_world_containers()

	# Do one pass immediately so the guides are up the moment the world loads,
	# rather than after the first timer tick.
	_rescan()
	_update_proximity()


# ── npc-05 O1 — real container spawns ─────────────────────────────────────────
## Build every WORLD_CONTAINER_SPAWNS entry as a REAL container (ghost = false).
## Ordering contract: all per-entry config lands on the detached node BEFORE
## add_child() — WasteContainer._ready() fires the moment the body enters the
## tree and joins its scan groups ("waste_container", and, when outdoor_skip is
## already true, "waste_container_outdoor"). This is the mirror image of the
## ghost group-strip in ContainerGuide._build(), which must run AFTER add_child
## for the very same reason.
func _spawn_world_containers() -> void:
	var world := get_parent()
	var anchor : Vector3 = Vector3.ZERO
	if world != null and world.has_method("_get_factory_anchor"):
		anchor = world.call("_get_factory_anchor")
	for entry in WORLD_CONTAINER_SPAWNS:
		var cid := String(entry["container_id"])
		var node := PlaceableCatalog.build_node(cid, false) as Node3D
		if node == null:
			push_warning("[ContainerGuideManager] build_node failed for '%s'" % cid)
			continue
		if bool(entry.get("outdoor", false)) and node is WasteContainer:
			var wc := node as WasteContainer
			wc.outdoor_skip = true
			wc.capacity_m3 = 30.0          # big open-top skip (design npc-05 D1)
			wc.overflow_budget_m3 = 5.0    # generous — outdoors, no chute to block
			# Accepts every stream. MUST assign a typed Array[int]: an untyped []
			# via set() silently no-ops on the typed export (see the test-skip
			# note in LegacyPropsSpawner._spawn_test_skip).
			var all_streams : Array[int] = []
			wc.accepted_streams = all_streams
		add_child(node)
		node.global_position = anchor + (entry["offset"] as Vector3)
		print("[ContainerGuideManager] Real container '%s' spawned @ %s%s"
			% [cid, str(node.global_position),
				" (outdoor end-destination skip)" if bool(entry.get("outdoor", false)) else ""])


# ── Rescan: ensure exactly one guide per (machine, slot); cull orphans ────────
func _rescan() -> void:
	# 1) Mark every existing guide unseen; we'll re-confirm the ones still valid.
	var seen : Dictionary = {}

	for node in get_tree().get_nodes_in_group("placed_object"):
		if not is_instance_valid(node):
			continue
		var machine := node as Node3D
		if machine == null:
			continue
		var pid := String(machine.get_meta("placeable_id", ""))
		if not SLOT_REGISTRY.has(pid):
			continue
		var slots : Array = SLOT_REGISTRY[pid]
		for i in slots.size():
			var slot : Dictionary = slots[i]
			var key := "%d#%d" % [machine.get_instance_id(), i]
			seen[key] = true
			var slot_pos : Vector3 = machine.global_transform * (slot["offset"] as Vector3)
			if _guides.has(key) and is_instance_valid(_guides[key]):
				# Already built — just refresh its world position in case the
				# machine was jogged (K edit mode).
				(_guides[key] as ContainerGuide).global_position = slot_pos
			else:
				var guide := ContainerGuide.new()
				guide.container_id = String(slot["container_id"])
				add_child(guide)
				guide.global_position = slot_pos
				_guides[key] = guide

	# 2) Free guides whose machine+slot no longer exists (deleted machine, or an
	#    id that left the registry).
	for key in _guides.keys():
		if seen.has(key):
			continue
		var stale = _guides[key]
		if is_instance_valid(stale):
			stale.queue_free()
		_guides.erase(key)


# ── Proximity: hide a hologram when a real container sits on its slot ─────────
func _update_proximity() -> void:
	# Snapshot the live containers once per pass (a handful at most).
	var containers : Array = []
	for node in get_tree().get_nodes_in_group("placed_object"):
		if not is_instance_valid(node):
			continue
		var c := node as Node3D
		if c == null:
			continue
		var pid := String(c.get_meta("placeable_id", ""))
		if pid in CONTAINER_IDS:
			containers.append(c)

	for key in _guides.keys():
		var guide = _guides[key]
		if not is_instance_valid(guide):
			continue
		var g := guide as ContainerGuide
		var slot_pos := g.global_position
		var satisfied := false
		for c in containers:
			var cn := c as Node3D
			var d : float
			if USE_XZ_DISTANCE:
				var a := Vector2(slot_pos.x, slot_pos.z)
				var b := Vector2(cn.global_position.x, cn.global_position.z)
				d = a.distance_to(b)
			else:
				d = slot_pos.distance_to(cn.global_position)
			if d <= PROXIMITY_M:
				satisfied = true
				break
		g.set_hologram_visible(not satisfied)


# =============================================================================
# CONTAINER GUIDE — one translucent cyan hologram standing on a slot.
# =============================================================================
class ContainerGuide extends Node3D:
	## A single holographic ghost of the container that belongs on this slot.
	## Built once from PlaceableCatalog.build_node(container_id, true); every
	## MeshInstance3D under it is overridden with a glowing cyan see-through
	## material. Has no collision and is never saved.

	# ── Holographic look ──────────────────────────────────────────────────────
	const HOLO_COLOR     : Color = Color(0.3, 0.8, 1.0)   # cyan/blue
	const HOLO_ALPHA     : float = 0.32                   # base transparency
	const HOLO_EMISSION  : float = 0.6                    # modest emission energy
	# Optional subtle alpha pulse (nice-to-have): the alpha breathes by ±PULSE_AMP
	# around HOLO_ALPHA at PULSE_HZ. Set ENABLE_PULSE=false for a static ghost.
	const ENABLE_PULSE   : bool  = true
	const PULSE_AMP      : float = 0.10
	const PULSE_HZ       : float = 1.2

	var container_id : String = ""

	# Materials we drive for the pulse (one per MeshInstance3D), kept so _process
	# doesn't have to re-walk the tree every frame.
	var _materials : Array[StandardMaterial3D] = []
	var _pulse_t   : float = 0.0
	var _hologram  : Node3D = null


	func _ready() -> void:
		_build()
		set_process(ENABLE_PULSE)


	func _build() -> void:
		if container_id == "":
			push_warning("[ContainerGuide] no container_id set")
			return
		# ghost=true returns the translucent-model variant of the container. For
		# the Logistics container ids this is a WasteContainer (StaticBody3D) with
		# a translucent model and NO collision — see PlaceableCatalog.build_node.
		var ghost := PlaceableCatalog.build_node(container_id, true) as Node3D
		if ghost == null:
			push_warning("[ContainerGuide] build_node failed for '%s'" % container_id)
			return
		# Container bodies are WasteContainers that build a Label3D fill gauge in
		# their _ready(). A "0%" gauge floating in a hologram reads as a bug, and
		# the Label3D wouldn't pick up our mesh-only holo material anyway — so turn
		# the gauge off BEFORE the body enters the tree (its _ready reads this).
		if "show_gauge" in ghost:
			ghost.set("show_gauge", false)
		_hologram = ghost
		add_child(ghost)
		# Strip any LOGIC groups / save meta the ghost body carries so nothing in
		# the sim (LineFlow stream router, save scan, the proximity check itself)
		# ever mistakes this hologram for a real container or placed object. This
		# MUST run AFTER add_child: the container body (a WasteContainer) re-adds
		# itself to the "waste_container" group in its own _ready(), which only
		# fires once it has entered the tree — so stripping earlier would be undone.
		# npc-05 — "waste_container_outdoor" included defensively: a ghost whose
		# body ever carries outdoor_skip = true would join that GENERATOR scan
		# group in the same _ready(), and a hologram must never draw dump tasks.
		for grp in ["placed_object", "waste_container", "waste_container_outdoor", "belt", "bale", "feed_machine"]:
			if ghost.is_in_group(grp):
				ghost.remove_from_group(grp)
		if ghost.has_meta("placeable_id"):
			ghost.remove_meta("placeable_id")
		# A StaticBody3D ghost would still collide via any CollisionShape3D under
		# it; build_node skips colliders on ghosts, but disable the body's layers
		# defensively in case that ever changes.
		if ghost is CollisionObject3D:
			(ghost as CollisionObject3D).collision_layer = 0
			(ghost as CollisionObject3D).collision_mask  = 0
		_apply_holographic_material(ghost)


	## Override every MeshInstance3D under `root` with a fresh holographic
	## material (a new instance per mesh so the optional pulse can drive each
	## without disturbing shared catalog materials).
	func _apply_holographic_material(root: Node) -> void:
		for child in root.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi == null:
				continue
			var m := _make_holo_material()
			mi.material_override = m
			# Holograms don't cast shadows.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_materials.append(m)


	func _make_holo_material() -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(HOLO_COLOR.r, HOLO_COLOR.g, HOLO_COLOR.b, HOLO_ALPHA)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode    = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true
		m.emission = HOLO_COLOR
		m.emission_energy_multiplier = HOLO_EMISSION
		# A hologram reads better drawn on top of itself without depth fighting.
		m.no_depth_test = false
		return m


	## Show / hide the whole ghost. The manager calls this from its proximity
	## check: hidden == a real container already occupies the slot.
	func set_hologram_visible(v: bool) -> void:
		if _hologram != null and is_instance_valid(_hologram):
			_hologram.visible = v
		else:
			visible = v


	func _process(delta: float) -> void:
		# Subtle alpha "breathing" so the holograms read as projected light.
		_pulse_t += delta
		var a : float = HOLO_ALPHA + sin(_pulse_t * TAU * PULSE_HZ) * PULSE_AMP
		a = clampf(a, 0.05, 0.95)
		for m in _materials:
			if m != null:
				var c := m.albedo_color
				c.a = a
				m.albedo_color = c
