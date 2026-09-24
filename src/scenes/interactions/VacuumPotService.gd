extends RefCounted
class_name VacuumPotService
## P3 STAGE B (2026-09-24) — the vacuum-pot cleaning mini-game, as the operator
## described it (docs/plant/operator_rulings_2026-09-23.md §14, design in
## docs/DESIGN_vacuum_pot_minigame_2026-09-23.md). Static state per pot root,
## driven by VacuumPotInteract (the pot's crosshair body) in the game and by
## test_vacuum_pot_minigame headless. It owns NO input and NO rendering beyond
## parking the lid and placing the block; the model stays the truth.
##
## His sequence, and what each call does:
##   1. the alarm: the pot is full, the melt pushed the lid open (ExtruderModel
##      VACUUM_ALARM, vacuum_alarm_pot names the pot).
##   2. PULL THE LID OFF — a hold that gets longer "the longer the vacuum has
##      been not in vacuum": lid_pull_required_s() grows with the model's
##      vacuum_alarm_elapsed_s. Letting go springs it back (cancel).
##   3. CLEAR THE FOUR PLANES with the plamuurmes: top, bottom, left, right,
##      each a 2×2 grid of cells. push() gains a depth that depends on the
##      melt's stiffness (also from the elapsed time): "might only go
##      halfway … then three quarters or all the way". Between pushes the
##      tool must be PULLED OUT (pull_out()): a push while it is in is refused.
##   4. RELEASE — every plane ≥ PLANE_CLEAR_FRAC (0.90, his testing value):
##      the block "drops down and forwards … by like a centimetre".
##   5. TAKE THE BLOCK by hand (take_block): it leaves the pot as a carryable
##      MeltBlock, the model is told the pot is empty (pot_emptied).
##   6. LID BACK ON (relid): the model gets vacuum_restored; within the
##      two-minute window that clears the alarm, past it the cascade already
##      shut the line down (FAULT, "laserfilter_error" on the bus).
## Parameters marked PLACEHOLDER are for him to play and set.

const PLANES : Array[String] = ["top", "bottom", "left", "right"]
const CELLS : int = 4                          # his "quadrants" — PLACEHOLDER
const PLANE_CLEAR_FRAC : float = 0.90          # operator, "for the testing phase"
const LID_PULL_BASE_S : float = 2.0            # PLACEHOLDER: lid pull at the moment of the alarm
const LID_PULL_PER_MIN_S : float = 1.0         # PLACEHOLDER: + per minute the vacuum has been gone
const STIFF_FULL_S : float = 180.0             # PLACEHOLDER: melt fully stiff after 3 min
const PUSH_FULL : float = 1.0                  # a push into soft melt clears a cell
const PUSH_STIFF : float = 0.45                # a push into stiff melt: "only halfway"
const BLOCK_SHIFT_M : float = 0.01             # operator: "by like a centimetre"
const _MELT_BLOCK_SCRIPT : String = "res://src/scenes/world/MeltBlock.gd"

static var _pots : Dictionary = {}

static func state(pot_root: Node) -> Dictionary:
	var key : int = pot_root.get_instance_id()
	if not _pots.has(key):
		var planes := {}
		for pl in PLANES:
			var arr : Array[float] = []
			for i in CELLS:
				arr.append(0.0)
			planes[pl] = arr
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(pot_name(pot_root)) * 31 + (key % 4093)
		_pots[key] = {
			"lid_off": false, "pull": 0.0, "pulling": false,
			"planes": planes, "tool_in": false, "pushes": 0,
			"block": null, "released": false, "taken": false, "kg": 0.0, "rng": rng,
		}
	return _pots[key]

static func reset(pot_root: Node) -> void:
	_pots.erase(pot_root.get_instance_id())

static func pot_name(pot_root: Node) -> String:
	return String(pot_root.get_meta("pot_name", ""))

static func pot_fill_kg(model, pot_root: Node) -> float:
	if model == null:
		return 0.0
	return float(model.secondary_pot_fill_kg) if pot_name(pot_root) == "secondary" else float(model.primary_pot_fill_kg)

static func pot_is_full(model, pot_root: Node) -> bool:
	return model != null and pot_fill_kg(model, pot_root) >= ExtruderModel.VACUUM_POT_CAPACITY_KG - 1e-6

## The lid sticks harder the longer the vacuum has been gone.
static func lid_pull_required_s(model) -> float:
	var elapsed : float = float(model.vacuum_alarm_elapsed_s) if model != null else 0.0
	return LID_PULL_BASE_S + LID_PULL_PER_MIN_S * elapsed / 60.0

## 0 = soft (just pushed open), 1 = stiff (cooled for STIFF_FULL_S or more).
static func stiffness(model) -> float:
	var elapsed : float = float(model.vacuum_alarm_elapsed_s) if model != null else 0.0
	return clampf(0.25 + 0.75 * elapsed / STIFF_FULL_S, 0.0, 1.0)

# ── 2. the lid ───────────────────────────────────────────────────────────────
static func can_pull_lid(model, pot_root: Node) -> bool:
	var st := state(pot_root)
	return not bool(st["lid_off"]) and pot_is_full(model, pot_root)

## Integrates a hold; returns progress 0..1 and completes the pull at 1.
static func tick_lid_pull(model, pot_root: Node, delta: float) -> float:
	if not can_pull_lid(model, pot_root):
		return 0.0
	var st := state(pot_root)
	st["pulling"] = true
	st["pull"] = float(st["pull"]) + delta / maxf(lid_pull_required_s(model), 0.05)
	if float(st["pull"]) >= 1.0:
		complete_lid_pull(model, pot_root)
		return 1.0
	return float(st["pull"])

static func cancel_lid_pull(pot_root: Node) -> void:
	var st := state(pot_root)
	st["pulling"] = false
	st["pull"] = 0.0          # let go and it seals itself back — PLACEHOLDER (no ratchet)

static func complete_lid_pull(model, pot_root: Node) -> Node:
	var st := state(pot_root)
	st["lid_off"] = true
	st["pulling"] = false
	st["pull"] = 1.0
	st["kg"] = pot_fill_kg(model, pot_root)
	pot_root.set_meta("lid_off", true)
	_park_lid(pot_root, true)
	var block : Node3D = load(_MELT_BLOCK_SCRIPT).new()
	block.set("kg", float(st["kg"]))
	block.set("pot_name", pot_name(pot_root))
	var centre : Vector3 = pot_root.get_meta("pot_centre", Vector3.ZERO)
	var dome_r : float = float(pot_root.get_meta("dome_r", 0.12))
	block.set("size_m", dome_r * 1.1)
	block.position = centre + Vector3(0.0, -dome_r * 0.15, 0.0)
	pot_root.add_child(block)
	st["block"] = block
	return block

## The Lid mesh leans against the dome while it is off (the driver leaves it
## alone through the root's lid_off meta) and sits back on its seat after.
static func _park_lid(pot_root: Node, off: bool) -> void:
	var lid := pot_root.get_node_or_null("Lid") as Node3D
	if lid == null:
		return
	if not lid.has_meta("lid_home"):
		lid.set_meta("lid_home", Vector3(lid.position.x, float(lid.get_meta("lid_closed_y", lid.position.y)), lid.position.z))
	var home : Vector3 = lid.get_meta("lid_home")
	if off:
		var dome_r : float = float(pot_root.get_meta("dome_r", 0.12))
		var dome_h : float = float(pot_root.get_meta("dome_h", 0.12))
		lid.position = home + Vector3(dome_r * 1.7, -dome_h * 0.35, 0.0)
		lid.rotation = Vector3(0.0, 0.0, deg_to_rad(78.0))
	else:
		lid.position = home
		lid.rotation = Vector3.ZERO

# ── 3. the plamuurmes ────────────────────────────────────────────────────────
static func plane_progress(pot_root: Node) -> Dictionary:
	var st := state(pot_root)
	var out := {}
	for pl in PLANES:
		var cells : Array = st["planes"][pl]
		var sum := 0.0
		for c in cells:
			sum += float(c)
		out[pl] = sum / float(maxi(cells.size(), 1))
	return out

static func all_planes_clear(pot_root: Node) -> bool:
	var pp := plane_progress(pot_root)
	for pl in PLANES:
		if float(pp[pl]) < PLANE_CLEAR_FRAC - 1e-9:
			return false
	return true

## The next cell in his order — top-left, top-right, bottom-right, bottom-left
## — that is not clear yet, for a caller without an aim (tests, a fallback).
static func next_cell(pot_root: Node) -> Array:
	var st := state(pot_root)
	var order : Array[int] = [0, 1, 3, 2]
	for pl in PLANES:
		for c in order:
			if float(st["planes"][pl][c]) < 1.0 - 1e-9:
				return [pl, c]
	return ["", -1]

## One push of the plamuurmes into `plane` / `cell`. Refused while the tool is
## still in the melt (pull_out first), before the lid is off, or after release.
static func push(model, pot_root: Node, plane: String, cell: int) -> Dictionary:
	var st := state(pot_root)
	var res := {"ok": false, "why": "", "gained": 0.0, "clearance": 0.0, "released": bool(st["released"])}
	if not bool(st["lid_off"]) or st["block"] == null:
		res["why"] = "lid on"
		return res
	if bool(st["released"]):
		res["why"] = "already free"
		return res
	if bool(st["tool_in"]):
		res["why"] = "pull the tool out first"
		return res
	if not PLANES.has(plane) or cell < 0 or cell >= CELLS:
		res["why"] = "no such cell"
		return res
	var rng : RandomNumberGenerator = st["rng"]
	var step : float = lerpf(PUSH_FULL, PUSH_STIFF, stiffness(model)) * rng.randf_range(0.6, 1.0)
	var cells : Array = st["planes"][plane]
	var before : float = float(cells[cell])
	cells[cell] = minf(1.0, before + step)
	st["tool_in"] = true
	st["pushes"] = int(st["pushes"]) + 1
	res["ok"] = true
	res["gained"] = float(cells[cell]) - before
	res["clearance"] = float(cells[cell])
	if all_planes_clear(pot_root):
		_release_block(pot_root)
		res["released"] = true
	return res

static func pull_out(pot_root: Node) -> bool:
	var st := state(pot_root)
	if not bool(st["tool_in"]):
		return false
	st["tool_in"] = false
	return true

# ── 4. release, 5. the block, 6. the lid back ────────────────────────────────
static func _release_block(pot_root: Node) -> void:
	var st := state(pot_root)
	st["released"] = true
	var block = st["block"]
	if block != null and is_instance_valid(block):
		# "drops down and forwards, towards the player by like a centimetre":
		# down, and out toward the sight-glass side (+X) — PLACEHOLDER for
		# "towards the player".
		(block as Node3D).position += Vector3(BLOCK_SHIFT_M, -BLOCK_SHIFT_M, 0.0)
		block.set("free", true)

static func block_free(pot_root: Node) -> bool:
	var st := state(pot_root)
	return bool(st["released"]) and st["block"] != null and is_instance_valid(st["block"])

## Lift the block out by hand. It leaves the pot as a world prop (the caller
## may hand it to the player); the model is told the pot is empty.
static func take_block(pot_root: Node, brain: Node) -> Node:
	if not block_free(pot_root):
		return null
	var st := state(pot_root)
	var block : Node3D = st["block"]
	var gp : Vector3 = block.global_position
	var world : Node = block.get_tree().current_scene if block.is_inside_tree() else null
	block.get_parent().remove_child(block)
	if world != null:
		world.add_child(block)
		block.global_position = gp
	st["block"] = null
	st["taken"] = true
	if brain != null and is_instance_valid(brain):
		var pend = brain.get("_pending")
		if pend is Dictionary:
			pend["pot_emptied"] = pot_name(pot_root)
	return block

static func can_relid(pot_root: Node) -> bool:
	var st := state(pot_root)
	return bool(st["lid_off"]) and bool(st["taken"])

## Seat the lid; the model gets vacuum_restored. Whether that clears the alarm
## is the model's call (the two-minute window).
static func relid(pot_root: Node, brain: Node) -> bool:
	if not can_relid(pot_root):
		return false
	_park_lid(pot_root, false)
	pot_root.set_meta("lid_off", false)
	if brain != null and is_instance_valid(brain):
		var pend = brain.get("_pending")
		if pend is Dictionary:
			pend["vacuum_restored"] = true
	reset(pot_root)
	return true
