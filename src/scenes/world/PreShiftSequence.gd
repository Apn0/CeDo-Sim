extends Node
class_name PreShiftSequence

## #166 Phase B — drives the pre-shift arrival choreography.
##
## Reads the PRE_SHIFT_SCHEDULE from MainWorld (per-NPC arrives_at_s, dress_time_s,
## pre_changed, optional smokes_at_s). At setup, every scheduled NPC is HIDDEN
## and dressed in personal clothes (ppe=none, footwear=shoes). Each frame the
## sequence checks each NPC's schedule against the shift clock and walks them
## through: arrive at parking → walk to dressing room → wait dress timer →
## rebuild_appearance to PPE+work_boots → walk to canteen → idle until bell.
## Pre_changed workers (Vincent, Pascal) skip the dressing room — they're already
## in PPE. Pascal also routes via SMOKE_SPOT at his smokes_at_s and stays there
## until shortly before the bell.
##
## On the bell (shift_started signal from ShiftClock), this node disables itself
## and CrewManager's normal posting takes over.
##
## Setup is non-destructive: NPCs that DON'T have a schedule entry (Mohammed,
## Peter, etc.) are left untouched at their spawn pose so they still behave
## normally during pre-shift.

const _STATE_PENDING       : int = 0   # not yet arrived
const _STATE_WALK_DRESSING : int = 1
const _STATE_DRESSING      : int = 2   # standing in the dressing room, timer running
const _STATE_WALK_CANTEEN  : int = 3
const _STATE_IDLE_CANTEEN  : int = 4
const _STATE_WALK_SMOKE    : int = 5
const _STATE_SMOKING       : int = 6
const _STATE_DONE          : int = 99  # bell rang; PreShiftSequence is hands-off

const _STATE_NAMES : Array[String] = [
	"PENDING", "WALK_DRESSING", "DRESSING", "WALK_CANTEEN",
	"IDLE_CANTEEN", "WALK_SMOKE", "SMOKING",
]

# How close (m) the NPC must be to its target before the state advances.
const _ARRIVE_DIST_M : float = 1.4

# Pascal stops smoking when 2 game-minutes remain before the bell.
const _SMOKE_END_BEFORE_BELL_S : float = 2.0 * 60.0

var main_world  : Node = null
var shift_clock : Node = null

# per NPC: { schedule, state, timer_due_s, npc_node, personal_appearance, work_appearance, color, variant }
var _entries : Dictionary = {}
var _bell_handled : bool = false

# =============================================================================
func setup(mw: Node, sc: Node, schedule: Dictionary,
		dress_pos: Vector3, canteen_pos: Vector3, smoke_pos: Vector3,
		arrival_anchor: Vector3) -> void:
	main_world  = mw
	shift_clock = sc
	for npc_id in schedule.keys():
		var sched : Dictionary = schedule[npc_id]
		var npc_node : Node3D = null
		if "npcs" in mw and mw.npcs is Dictionary and (mw.npcs as Dictionary).has(npc_id):
			npc_node = (mw.npcs as Dictionary)[npc_id] as Node3D
		if npc_node == null:
			continue
		# Build per-NPC pre-shift entry. `arrival_anchor` is the parking lot's
		# pedestrian exit (we don't drive the car in for Phase B — the NPC just
		# appears here on foot at arrives_at_s; Phase C can swap in a drive-in).
		var data : Dictionary = mw.NPC_DATA.get(npc_id, {})
		var personal_app : Dictionary = (data.get("appearance", {}) as Dictionary).duplicate()
		personal_app["shirt_type"] = "t_shirt"
		personal_app["footwear"]   = "shoes"
		personal_app["ppe"]        = "none"
		var work_app : Dictionary = (data.get("appearance", {}) as Dictionary).duplicate()
		work_app["shirt_type"] = work_app.get("shirt_type", "t_shirt")
		work_app["footwear"]   = "work_boots"
		work_app["ppe"]        = work_app.get("ppe", "hi_vis")
		var color : Color = data.get("color", Color.WHITE)
		# Hide + park out of camera until arrival.
		npc_node.visible = false
		var pre_changed : bool = bool(sched.get("pre_changed", false))
		var start_appearance : Dictionary = work_app if pre_changed else personal_app
		# Use the holder's existing humanoid variant — we don't track it per NPC,
		# fall back to a hash of npc_id so swaps stay deterministic.
		var variant : int = (hash(npc_id) % 8 + 8) % 8
		_swap_humanoid(npc_node, color, variant, start_appearance)
		npc_node.global_position = arrival_anchor
		# Park their target on their feet so the walker doesn't start trying to
		# move them while hidden — _tick() takes over once arrival time hits.
		_stop_walking(npc_node)
		# Park NPCs OFF-DUTY during pre-shift so CrewManager.tick doesn't fight
		# us for target_position. _on_bell flips this back on when the shift
		# actually starts; CrewManager.assign_posts then routes them to posts.
		if npc_node.has_method("set_off_duty"):
			npc_node.call("set_off_duty", true)
		_entries[npc_id] = {
			"schedule":   sched,
			"state":      _STATE_PENDING,
			"timer_due":  0.0,
			"node":       npc_node,
			"personal":   personal_app,
			"work":       work_app,
			"color":      color,
			"variant":    variant,
			"dress_pos":  dress_pos,
			"canteen_pos":canteen_pos,
			"smoke_pos":  smoke_pos,
			"arrival_pos":arrival_anchor,
			"smoked":     false,   # Pascal: have we already done the smoke loop?
		}
	print("[PreShiftSequence] active — %d NPC entries" % _entries.size())
	# Wake up the bell handler so we know when to detach.
	if shift_clock != null and shift_clock.has_signal("shift_started"):
		shift_clock.shift_started.connect(_on_bell)

# =============================================================================
func _physics_process(_delta: float) -> void:
	if _bell_handled or shift_clock == null:
		return
	# The bell signal already handled the cleanup; no further work.
	if not shift_clock.has_method("is_pre_shift"):
		return
	if not bool(shift_clock.is_pre_shift()):
		return
	var elapsed : float = float(shift_clock.shift_elapsed_seconds)
	for npc_id in _entries.keys():
		_tick_entry(npc_id, _entries[npc_id], elapsed)

# =============================================================================
# Per-NPC state advancement.
func _tick_entry(npc_id: String, e: Dictionary, elapsed: float) -> void:
	var npc : Node3D = e["node"]
	if npc == null or not is_instance_valid(npc):
		return
	var sched : Dictionary = e["schedule"]
	var state : int = int(e["state"])
	var arrives_at : float = float(sched.get("arrives_at_s", -1.0 * 60.0))
	# ── PENDING ────────────────────────────────────────────────────────────────
	if state == _STATE_PENDING:
		if elapsed < arrives_at:
			return
		# Arrive: reveal, walk to first destination.
		npc.visible = true
		var pre_changed : bool = bool(sched.get("pre_changed", false))
		var smokes_at : float = float(sched.get("smokes_at_s", -9e9))
		# Pascal: pre_changed + smokes — walk to smoke spot first.
		if pre_changed and smokes_at > -9e8:
			e["state"] = _STATE_WALK_SMOKE
			_walk_to(npc, e["smoke_pos"])
			_log_state(npc_id, _STATE_PENDING, _STATE_WALK_SMOKE)
			return
		# Vincent: pre_changed, no smoke — go straight to canteen.
		if pre_changed:
			e["state"] = _STATE_WALK_CANTEEN
			_walk_to(npc, e["canteen_pos"])
			_log_state(npc_id, _STATE_PENDING, _STATE_WALK_CANTEEN)
			return
		# Default flow — head to the dressing room.
		e["state"] = _STATE_WALK_DRESSING
		_walk_to(npc, e["dress_pos"])
		_log_state(npc_id, _STATE_PENDING, _STATE_WALK_DRESSING)
		return
	# ── WALK_DRESSING → DRESSING ──────────────────────────────────────────────
	if state == _STATE_WALK_DRESSING:
		if _arrived(npc, e["dress_pos"]):
			_stop_walking(npc)
			var dress_time : float = float(sched.get("dress_time_s", -1.0))
			if dress_time < 0.0:
				# Default uniform 2–6 min, avg 4. Same as the operator's spec.
				dress_time = randf_range(2.0, 6.0) * 60.0
			e["timer_due"] = elapsed + dress_time
			e["state"] = _STATE_DRESSING
			_log_state(npc_id, _STATE_WALK_DRESSING, _STATE_DRESSING)
		return
	# ── DRESSING → WALK_CANTEEN ───────────────────────────────────────────────
	if state == _STATE_DRESSING:
		if elapsed >= float(e["timer_due"]):
			_swap_humanoid(npc, e["color"], int(e["variant"]), e["work"])
			e["state"] = _STATE_WALK_CANTEEN
			_walk_to(npc, e["canteen_pos"])
			_log_state(npc_id, _STATE_DRESSING, _STATE_WALK_CANTEEN)
		return
	# ── WALK_CANTEEN → IDLE_CANTEEN ───────────────────────────────────────────
	if state == _STATE_WALK_CANTEEN:
		if _arrived(npc, e["canteen_pos"]):
			_stop_walking(npc)
			e["state"] = _STATE_IDLE_CANTEEN
			_log_state(npc_id, _STATE_WALK_CANTEEN, _STATE_IDLE_CANTEEN)
		return
	# ── WALK_SMOKE → SMOKING ──────────────────────────────────────────────────
	if state == _STATE_WALK_SMOKE:
		if _arrived(npc, e["smoke_pos"]):
			_stop_walking(npc)
			e["state"] = _STATE_SMOKING
			e["smoked"] = true
			_log_state(npc_id, _STATE_WALK_SMOKE, _STATE_SMOKING)
		return
	# ── SMOKING → WALK_CANTEEN ────────────────────────────────────────────────
	if state == _STATE_SMOKING:
		# Hold the smoke spot until 2 game-minutes before the bell (i.e.
		# shift_elapsed > -2 min). Then walk in for the start of the shift.
		if elapsed >= -_SMOKE_END_BEFORE_BELL_S:
			e["state"] = _STATE_WALK_CANTEEN
			_walk_to(npc, e["canteen_pos"])
			_log_state(npc_id, _STATE_SMOKING, _STATE_WALK_CANTEEN)
		return
	# IDLE_CANTEEN, DONE — nothing to do; CrewManager picks up at the bell.

# =============================================================================
# Deterministic state recomputer — call when ShiftClock seeks to a new wall
# time so every NPC snaps to the state they SHOULD be in at the new elapsed
# value. Without this, a time-jump leaves NPCs frozen in whatever forward-only
# state the last _tick produced (Pascal stuck at smoke, Emrah halfway to the
# dressing room) instead of matching the operator's new instant.
#
# Determinism note: NPCs with dress_time_s = -1 use a RANDOM 2-6 min uniform.
# Recomputing against that randomness means Apply→Cancel→Apply could land
# different states. We use the MEAN (4 min) here so a time-jump is stable.
# Pre_changed workers (Vincent, Pascal) have a deterministic dress_time of 0.
func recompute_for(elapsed: float) -> void:
	_bell_handled = false   # un-stick the bell so we can serve another pre-shift
	for npc_id in _entries.keys():
		var e : Dictionary = _entries[npc_id]
		var npc : Node3D = e["node"]
		if npc == null or not is_instance_valid(npc):
			continue
		var sched : Dictionary = e["schedule"]
		var arrives_at : float = float(sched.get("arrives_at_s", -60.0))
		var pre_changed : bool = bool(sched.get("pre_changed", false))
		var smokes_at  : float = float(sched.get("smokes_at_s", -9e9))
		var dress_time : float = float(sched.get("dress_time_s", 240.0))
		if dress_time < 0.0:
			dress_time = 4.0 * 60.0   # mean of 2-6 min uniform
		# (1) Before arrival — hide + reset to personal clothes.
		if elapsed < arrives_at:
			_swap_humanoid(npc, e["color"], int(e["variant"]), e["personal"])
			npc.visible = false
			npc.global_position = e["arrival_pos"]
			_stop_walking(npc)
			if npc.has_method("set_off_duty"):
				npc.call("set_off_duty", true)
			e["state"] = _STATE_PENDING
			e["smoked"] = false
			continue
		# (2) Past arrival — visible + on-duty handling. Smoking branch first
		# because pre_changed + smokes_at is Pascal-specific.
		npc.visible = true
		if npc.has_method("set_off_duty"):
			npc.call("set_off_duty", true)   # PreShiftSequence still owns them until bell
		if pre_changed and smokes_at > -9e8:
			# Pascal: arrived → walk smoke → smoke → walk canteen → idle canteen.
			if elapsed < -_SMOKE_END_BEFORE_BELL_S:
				# Still smoking.
				_swap_humanoid(npc, e["color"], int(e["variant"]), e["work"])
				npc.global_position = e["smoke_pos"]
				_stop_walking(npc)
				e["state"] = _STATE_SMOKING
				e["smoked"] = true
			else:
				# Smoke done → canteen.
				_swap_humanoid(npc, e["color"], int(e["variant"]), e["work"])
				npc.global_position = e["canteen_pos"]
				_stop_walking(npc)
				e["state"] = _STATE_IDLE_CANTEEN
				e["smoked"] = true
		elif pre_changed:
			# Vincent: arrived already in PPE → canteen immediately.
			_swap_humanoid(npc, e["color"], int(e["variant"]), e["work"])
			npc.global_position = e["canteen_pos"]
			_stop_walking(npc)
			e["state"] = _STATE_IDLE_CANTEEN
		else:
			# Default flow: arrived → dress → canteen.
			var dress_done_at : float = arrives_at + dress_time
			if elapsed < dress_done_at:
				# Still in dressing room (or walking there — we collapse to "at
				# the dressing pos" because the wall-clock recompute doesn't have
				# a fine-grained walk timer).
				_swap_humanoid(npc, e["color"], int(e["variant"]), e["personal"])
				npc.global_position = e["dress_pos"]
				_stop_walking(npc)
				e["state"] = _STATE_DRESSING
				e["timer_due"] = dress_done_at
			else:
				_swap_humanoid(npc, e["color"], int(e["variant"]), e["work"])
				npc.global_position = e["canteen_pos"]
				_stop_walking(npc)
				e["state"] = _STATE_IDLE_CANTEEN
	# (3) Past the bell — hand back to CrewManager once after the loop. _on_bell()
	# is idempotent on subsequent calls (early-return on _bell_handled), but we
	# only need it the FIRST time the recompute crosses zero.
	if elapsed >= 0.0:
		_on_bell()

# =============================================================================
# Bell handler — invoked by ShiftClock.shift_started.
func _on_bell() -> void:
	if _bell_handled:
		return
	_bell_handled = true
	# Make sure everyone is visible + in work appearance at the bell, even if
	# they were still mid-sequence (operator opened the game with time_scale
	# cranked so the pre-shift collapsed). CrewManager.assign_posts (called
	# elsewhere on shift_started) does the actual station assignment.
	for npc_id in _entries.keys():
		var e : Dictionary = _entries[npc_id]
		var npc : Node3D = e["node"]
		if npc != null and is_instance_valid(npc):
			npc.visible = true
			# Catch anyone who hadn't dressed yet (rare — only if the operator
			# warped through the schedule). Pre_changed workers were already in
			# work_app, so this is a no-op on them.
			if int(e["state"]) in [_STATE_PENDING, _STATE_WALK_DRESSING, _STATE_DRESSING]:
				_swap_humanoid(npc, e["color"], int(e["variant"]), e["work"])
			# Hand the NPC back to CrewManager.
			if npc.has_method("set_off_duty"):
				npc.call("set_off_duty", false)
		e["state"] = _STATE_DONE
	print("[PreShiftSequence] bell — handed off to CrewManager")

# =============================================================================
# Helpers — NPC locomotion + appearance swap.
func _walk_to(npc: Node3D, target: Vector3) -> void:
	if not ("target_position" in npc):
		return
	npc.target_position = Vector3(target.x, npc.global_position.y, target.z)
	if "is_walking" in npc:
		npc.is_walking = true

func _stop_walking(npc: Node3D) -> void:
	if "is_walking" in npc:
		npc.is_walking = false
	if "target_position" in npc:
		npc.target_position = npc.global_position

func _arrived(npc: Node3D, target: Vector3) -> bool:
	return Vector2(npc.global_position.x - target.x,
		npc.global_position.z - target.z).length() < _ARRIVE_DIST_M

func _swap_humanoid(npc: Node3D, color: Color, variant: int, appearance: Dictionary) -> void:
	# Humanoid.rebuild_appearance handles either child name ("Body" or
	# "HumanoidBody"). NPC.gd's per-frame body-scaling lookup re-resolves the
	# child each tick, so the swap doesn't leave a dangling reference.
	Humanoid.rebuild_appearance(npc, color, variant, appearance)

func _log_state(npc_id: String, from: int, to: int) -> void:
	print("[PreShiftSequence] %s: %s → %s" % [npc_id,
		_STATE_NAMES[from] if from < _STATE_NAMES.size() else "?",
		_STATE_NAMES[to]   if to   < _STATE_NAMES.size() else "?"])
