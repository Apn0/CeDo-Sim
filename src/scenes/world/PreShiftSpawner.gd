extends Node3D

class_name PreShiftSpawner

# =============================================================================
# #195 follow-up — Pre-shift arrival orchestration extracted from MainWorld.gd.
# =============================================================================
# Wraps the PreShiftSequence install + anchor-offset constants that drive the
# T-30min arrival → dress → canteen → smoke loop for every scheduled NPC.
# MainWorld instantiates one of these as a child node and calls setup(...) once
# during world bring-up (and again, with force=true, from the time-jump path);
# the spawner then creates a PreShiftSequence as a child of the MainWorld node
# so the scene tree shape stays identical to the pre-extract layout.

# ── #166 Pre-shift arrival schedule ──────────────────────────────────────────
# Per-NPC schedule, expressed in seconds RELATIVE to the bell (negative = before).
# `pre_changed` = arrives already in PPE/boots (skips dressing-room loop).
# `dress_time_s` = how long they spend in the locker room (-1 → use random
#                  uniform 2..6 min default).
# `smokes_at_s`  = if set, NPC stands at SMOKE_SPOT smoking from that time until
#                  3 min later. Only Pascal has this.
# Order corresponds to NPC_DATA keys in MainWorld. Unlisted NPCs default to T-15 +
# random-dressing (so Mohammed / Peter / Vincent fallback work cleanly).
const PRE_SHIFT_SCHEDULE : Dictionary = {
	"emrah":      {"arrives_at_s": -35.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0},
	"pascal":     {"arrives_at_s": -40.0 * 60.0, "pre_changed": true,  "dress_time_s": 0.0, "smokes_at_s": -33.0 * 60.0},
	"vincent":    {"arrives_at_s": -40.0 * 60.0, "pre_changed": true,  "dress_time_s": 0.0},
	"romain":     {"arrives_at_s": -25.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0},
	# PART C1 — Mohammed (permanent feeder, line 3A/3B) is a punctual but not
	# early arriver: T-25 min with the standard 4-min uniform changeover. Without
	# a schedule entry, PreShiftSequence skipped him and he'd stand at the feeder
	# post even at 06:35 — the operator-reported "Mohammed/Peter still at post"
	# half of the bug.
	"mohammed":   {"arrives_at_s": -25.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0},
	"yassine":    {"arrives_at_s": -20.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0, "rides_with": "player"},
	"abdellilah": {"arrives_at_s": -17.0 * 60.0, "pre_changed": false, "dress_time_s":  8.0 * 60.0},
	# PART C1 — Peter (production manager) shows up later but BEFORE the bell so
	# he's in his office at start of shift. T-12 min, pre-changed (managers
	# arrive in office clothes, no locker-room loop).
	"peter":      {"arrives_at_s": -12.0 * 60.0, "pre_changed": true,  "dress_time_s": 0.0},
	"kevin":      {"arrives_at_s": -10.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0},
}

# Placeholder dressing room + smoke spot — operator can refine via WorldSetup
# markers later. For now we anchor relative to the player spawn so the loop
# works against the same building shell as everything else (#34 lesson).
const DRESSING_ROOM_OFFSET : Vector3 = Vector3(-8.0, 0.0,  6.0)   # inside, near canteen
const CANTEEN_OFFSET       : Vector3 = Vector3( 0.0, 0.0, 25.0)   # matches MainWorld:771 fallback
const SMOKE_SPOT_OFFSET    : Vector3 = Vector3( 4.0, 0.0,-12.0)   # outside, near parking

# Reference back to MainWorld for scene-tree parenting + helper calls.
# Set when the manager is added to the tree (its parent IS MainWorld).
var _world : Node = null

func _ready() -> void:
	_world = get_parent()

## #166 Phase B — install the pre-shift arrival sequence if (and only if) we
## are currently in the pre-shift window. Resumed mid-shift saves skip this
## (CrewManager + standard NPC behaviour take over from the moment of load).
## Idempotent: a re-call (e.g. after a time-jump back into pre-shift) reuses
## the existing PreShiftSequence node by calling its recompute_for() and
## returning, instead of spawning a second copy.
func setup(world: Node, npcs: Dictionary, shift_clock: Node, staff_parking: Node, player_spawn_pos: Vector3, force: bool = false) -> void:
	if _world == null:
		_world = world
	if shift_clock == null:
		return
	# `force` skips the is_pre_shift gate — the time-jump path already knows
	# new_elapsed < 0 (the gate is a tautology there) and the implicit coupling
	# has bitten us on resumed-past-bell saves. The _ready() boot-time caller
	# still uses the gate (force=false) because the clock hasn't been started
	# at that point.
	if not force:
		if not shift_clock.has_method("is_pre_shift") or not bool(shift_clock.is_pre_shift()):
			return
	if npcs.is_empty():
		return
	var existing := _world.get_node_or_null("PreShiftSequence")
	if existing != null:
		if existing.has_method("recompute_for"):
			existing.call("recompute_for", float(shift_clock.shift_elapsed_seconds))
		return
	var seq_script := load("res://src/scenes/world/PreShiftSequence.gd")
	if seq_script == null:
		push_warning("[PreShiftSpawner] PreShiftSequence.gd missing — pre-shift skipped")
		return
	var seq : Node = seq_script.new()
	seq.name = "PreShiftSequence"
	_world.add_child(seq)
	# Anchor offsets are defined as constants at the top of the file. Convert
	# to world positions by adding the resolved player spawn. Y is irrelevant
	# (NPCs land on the navmesh-baked floor).
	var anchor : Vector3 = player_spawn_pos
	var dress_pos   : Vector3 = anchor + DRESSING_ROOM_OFFSET
	var canteen_pos : Vector3 = anchor + CANTEEN_OFFSET
	var smoke_pos   : Vector3 = anchor + SMOKE_SPOT_OFFSET
	# Arrival anchor — for Phase B the NPC just APPEARS at the parking-lot
	# pedestrian exit when their arrives_at_s passes. Phase C can swap this
	# for a drive-in animation tied to the per-NPC car.
	var arrival : Vector3 = anchor
	if staff_parking and "global_position" in staff_parking:
		arrival = staff_parking.global_position
	seq.call("setup", _world, shift_clock, PRE_SHIFT_SCHEDULE,
			dress_pos, canteen_pos, smoke_pos, arrival)
	print("[PreShiftSpawner] Pre-shift sequence active (T-%.0f min)" \
			% (-shift_clock.shift_elapsed_seconds / 60.0))
