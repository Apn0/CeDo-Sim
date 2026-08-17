extends Node3D
## BALE YARD MASS CONSERVATION — audit 2026-08-16 defects C1 + C2.
##
##   godot --headless --path <proj> res://src/tests/test_bale_yard_mass_conservation.tscn
##
## THE DEFECT THIS GUARDS (BaleYardManager.tick()):
##   C1  The far-branch erased the slot key on BOTH paths, including the one that
##       deliberately keeps a grabbed bale alive. Grab a yard bale, haul it past
##       32 m, walk back inside 24 m — the slot had no key, so a SECOND bale was
##       minted in it while the first was still in the forks. Repeat forever.
##       Nothing in the plant model conserves that mass.
##   C2  A re-minted body is INVISIBLE BUT SOLID. build_yard_bale_mm() attaches
##       no MeshInstance: a yard bale's visual is one instance in the yard
##       MultiMesh, and detail_bale() zero-scales that instance the moment the
##       bale is grabbed. Nothing on the respawn path restores it, so the
##       operator sees a gap in the stack and drives into an invisible wall.
##
## WHAT IS ASSERTED — behaviour, not internals (project rule 4):
##   A. FIXTURE   the yard really fills, the MultiMesh really has one instance
##                per slot, and every instance starts full-scale.
##   B. SPAWN     parking a vehicle in the yard materialises exactly one collider
##                per slot — the sweep works at all.
##   C. CONSERVE  three grab → haul 60 m → return cycles. The live yard-bale body
##                count must NEVER exceed the slot count, and no two live bodies
##                may claim the same slot_key.
##   D. VISIBLE   every live body that is still MultiMesh-backed (simple_bale ==
##                true, i.e. it has no visual of its own) must have a non-zero
##                MultiMesh instance behind it. An invisible solid is a FAIL.
##
## NON-VACUITY, stated up front (project rule 3 — a test that cannot fail is
## worthless):
##   • the fixture supplier must be a REAL BaleDefs origin;
##   • the yard must produce >= 8 slots and >= 8 colliders, else "count did not
##     grow" is trivially true;
##   • the grabbed bale's MultiMesh instance must be MEASURED at zero scale
##     after detail_bale(), else check D can never see an invisible body;
##   • the haul must actually cross the 32 m far radius and the return must
##     actually re-enter the 24 m near radius — both distances are printed.
##
## user:// SAFETY: this test writes NOTHING to user://. It mutates the in-memory
## WorldLayout autoload arrays only, and restores them in _finish().
## world_layout.json is never read, written or referenced.

const SUPPLIER := "zwolle"          # a real BaleDefs origin (1.50 m cube, stack 2)
const HALF     := 3.0               # 6 x 6 m yard polygon
const HAUL_M   := 60.0              # > FAR_SQ (32 m) by a wide margin
const CYCLES   := 3                 # three independent grab/haul/return cycles

var _pass := 0
var _fail := 0

var _world : Node3D = null
var _mgr   : Node   = null
var _veh   : Node3D = null

var _saved_yards    : Array = []
var _saved_yards_pc : Array = []
var _saved_pc_flag  : bool  = false

var _yard_centre := Vector3.ZERO
var _carried : Array[Node3D] = []   # bales currently "in the forks"

## MEASURED at startup, not assumed: the --headless (dummy) renderer accepts
## MultiMesh.set_instance_transform() and then hands back IDENTITY for every
## instance, so the yard's visual state cannot be read off the server here.
## _probe_mm_readback() detects that; when it is false the visibility check falls
## back to the slot-key ledger below, which is CPU-side and just as strict.
var _mm_readback := false

## Slot keys whose MultiMesh instance detail_bale() has blanked. Mirrors
## PlaceableCatalog.gd:5972-5981 — that function zero-scales the slot's instance
## and NOTHING on the yard respawn path restores it (only reset_yard_bales,
## BaleYardManager.gd:486-495, ever does). A MultiMesh-only body standing in one
## of these slots is precisely the invisible-but-solid bale of defect C2.
var _blanked : Dictionary = {}      # slot_key -> true


# =============================================================================
# Stand-in MainWorld. BaleYardManager reaches back into its parent for exactly
# these four helpers plus a `player` property; nothing else of MainWorld is
# involved in the yard fill, so this is the whole contract.
# =============================================================================
class StubWorld extends Node3D:
	var player : Node3D = null      # tick() reads this via `"player" in _world`

	func _layout_rel_sane(_marker: Vector3) -> bool:
		return true

	func _layout_to_scene(rel: Vector3) -> Vector3:
		return rel                  # test fixture is already in scene space

	func _floor_top_y() -> float:
		return 0.0

	## Same centroid-angle sort MainWorld.gd:629 uses.
	func _sort_corners_ccw(corners: Array) -> Array:
		if corners.size() < 3:
			return corners
		var cx := 0.0
		var cz := 0.0
		for c in corners:
			cx += c.x; cz += c.z
		cx /= float(corners.size()); cz /= float(corners.size())
		var sorted := corners.duplicate()
		sorted.sort_custom(func(a, b):
			return atan2(a.z - cz, a.x - cx) < atan2(b.z - cz, b.x - cx))
		return sorted


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _info(msg: String) -> void:
	print("  info  : %s" % msg)


# =============================================================================
func _ready() -> void:
	print("=== BALE YARD MASS CONSERVATION — audit C1 (mass creation) + C2 (invisible solid) ===")
	_stash_layout()
	await _build_fixture()
	if _fail == 0:
		await _check_spawn()
		await _check_conservation()
	_finish()


# =============================================================================
# A. FIXTURE — a real yard, filled by the real code path
# =============================================================================
func _build_fixture() -> void:
	print("\n-- A. fixture --")
	_ok(not BaleDefs.get_origin(SUPPLIER).is_empty(),
		"supplier '%s' is a real BaleDefs origin (fixture is not invented)" % SUPPLIER)

	WorldLayout.bale_yards = [{
		"supplier_id": SUPPLIER,
		"corners": [
			Vector3(-HALF, 0.0, -HALF), Vector3(HALF, 0.0, -HALF),
			Vector3(HALF, 0.0,  HALF), Vector3(-HALF, 0.0,  HALF),
		],
	}]
	WorldLayout.bale_yards_pc = []
	WorldLayout.has_pc_data = false     # force the legacy (identity) corner path

	_world = StubWorld.new()
	_world.name = "StubWorld"
	add_child(_world)

	_mgr = BaleYardManager.new()
	_mgr.name = "BaleYardManager"
	_world.add_child(_mgr)
	_mgr.call("setup", _world, null)    # runs the real _spawn_bale_yards_from_layout
	await get_tree().process_frame

	var slots : Array = _mgr.get("_yard_slots")
	var n_slots : int = slots.size()
	_ok(n_slots >= 8, "yard filled %d slots (need >= 8, else 'count did not grow' is vacuous)" % n_slots)
	if n_slots == 0:
		return

	_yard_centre = Vector3.ZERO
	for s in slots:
		_yard_centre += (s as Dictionary)["spawn_pos"] as Vector3
	_yard_centre /= float(n_slots)
	_info("yard centroid %s, %d slots" % [str(_yard_centre), n_slots])

	# One MultiMesh instance per slot, every one full-scale at spawn.
	var mmi : MultiMeshInstance3D = (slots[0] as Dictionary)["mmi"]
	_ok(mmi != null and mmi.multimesh != null, "yard MultiMesh exists")
	if mmi == null or mmi.multimesh == null:
		return
	# stack levels share one MM, so instance_count == slot count for a 1-yard fill
	_ok(mmi.multimesh.instance_count == n_slots,
		"MultiMesh carries %d instances for %d slots" % [mmi.multimesh.instance_count, n_slots])
	_mm_readback = _probe_mm_readback()
	if _mm_readback:
		var zero_at_spawn := 0
		for i in mmi.multimesh.instance_count:
			if mmi.multimesh.get_instance_transform(i).basis.get_scale().length() < 0.001:
				zero_at_spawn += 1
		_ok(zero_at_spawn == 0, "0 of %d MultiMesh instances are zero-scaled at spawn (found %d)"
			% [mmi.multimesh.instance_count, zero_at_spawn])
	else:
		# Measured, not guessed: instance 0 was written at the slot's spawn_pos
		# during the fill and reads back at the origin.
		_info("renderer does NOT store MultiMesh transforms (inst0 reads %s, spawned at %s)"
			% [str(mmi.multimesh.get_instance_transform(0).origin),
			   str((slots[0] as Dictionary)["spawn_pos"])])
		_info("visibility check uses the slot-key ledger instead (CPU-side, same strictness)")

	# The stand-in vehicle. tick() sweeps every node in group "vehicle".
	_veh = Node3D.new()
	_veh.name = "StubForklift"
	_veh.add_to_group("vehicle")
	add_child(_veh)
	_veh.global_position = _yard_centre


# =============================================================================
# B. SPAWN — the sweep materialises one collider per slot
# =============================================================================
func _check_spawn() -> void:
	print("\n-- B. proximity spawn --")
	await _tick()
	var n_slots : int = (_mgr.get("_yard_slots") as Array).size()
	var live := _live_bodies()
	_ok(live.size() == n_slots,
		"vehicle parked in the yard -> %d colliders for %d slots" % [live.size(), n_slots])
	_ok(live.size() > 0, "at least one body exists to haul (non-vacuity for the cycles below)")
	_ok(_dup_slot_keys(live).is_empty(), "no two bodies claim the same slot")


# =============================================================================
# C+D. CONSERVATION — grab, haul past 32 m, return inside 24 m, three times
# =============================================================================
func _check_conservation() -> void:
	print("\n-- C. grab -> haul %.0f m -> return, %d cycles --" % [HAUL_M, CYCLES])
	var n_slots : int = (_mgr.get("_yard_slots") as Array).size()
	var far_pos := _yard_centre + Vector3(HAUL_M, 0.0, 0.0)

	for cycle in CYCLES:
		# --- grab: promote one still-simple body to a detailed (carried) bale ---
		var victim : Node3D = null
		for b in _live_bodies():
			if bool(b.get_meta("simple_bale", true)) and not _carried.has(b):
				victim = b
				break
		if victim == null:
			_ok(false, "cycle %d: found a bale to grab" % (cycle + 1))
			return
		var vkey := String(victim.get_meta("slot_key", ""))
		var bound : bool = victim.has_meta("yard_mm_inst") and victim.has_meta("yard_mm_idx")
		var scale_before : float = _mm_scale(victim)
		PlaceableCatalog.detail_bale(victim)     # what a real grab does
		_carried.append(victim)
		_blanked[vkey] = true
		# Non-vacuity for check D: the grab must really have taken the visual off
		# the MultiMesh, otherwise "no invisible solids" could never fail.
		var scale_after : float = _mm_scale(victim)
		if _mm_readback:
			_ok(scale_before > 0.001 and scale_after < 0.001,
				"cycle %d: grabbing '%s' zero-scaled its MultiMesh instance %.4f -> %.4f (the C2 pre-condition)"
					% [cycle + 1, vkey, scale_before, scale_after])
		else:
			# Both halves of detail_bale's blanking branch, measured CPU-side:
			# the guards were passed (simple_bale flipped true -> false) AND the
			# body carries the MM binding that branch keys on, so
			# set_instance_transform(zero) ran on slot '%s'.
			_ok(bound and not bool(victim.get_meta("simple_bale", true)),
				"cycle %d: grabbing '%s' ran detail_bale's blanking branch (mm-bound %s, simple_bale now %s)"
					% [cycle + 1, vkey, bound, bool(victim.get_meta("simple_bale", true))])

		# --- haul: the vehicle and everything in its forks leave the yard ---
		_move_rig(far_pos)
		var d_far : float = _nearest_slot_distance(far_pos)
		_ok(d_far > 32.0, "cycle %d: hauled to %.1f m — past the 32 m despawn radius"
			% [cycle + 1, d_far])
		await _tick()

		# --- return: back inside the 24 m spawn radius ---
		_move_rig(_yard_centre + Vector3(0.0, 0.0, HALF + 1.0))
		var d_near : float = _nearest_slot_distance(_veh.global_position)
		_ok(d_near < 24.0, "cycle %d: returned to %.1f m — inside the 24 m spawn radius"
			% [cycle + 1, d_near])
		await _tick()

		# --- the two things that must hold ---
		var live := _live_bodies()
		_ok(live.size() <= n_slots,
			"cycle %d: %d live yard bales for %d slots — no bale was minted"
				% [cycle + 1, live.size(), n_slots])
		var dups := _dup_slot_keys(live)
		_ok(dups.is_empty(),
			"cycle %d: no slot holds two bodies at once (duplicates: %s)"
				% [cycle + 1, str(dups)])
		var invisible := _invisible_solids(live)
		_ok(invisible.is_empty(),
			"cycle %d: every MultiMesh-backed body is visible (invisible solids: %s)"
				% [cycle + 1, str(invisible)])
		_info("cycle %d: %d live, %d in the forks, slot budget %d"
			% [cycle + 1, live.size(), _carried.size(), n_slots])

	# Final ledger: the yard is a closed stock. What is standing in slots plus
	# what is in the forks may not exceed what was delivered.
	var final_live := _live_bodies()
	_ok(final_live.size() == n_slots,
		"after %d grabs the world holds exactly %d yard bales (slot count %d)"
			% [CYCLES, final_live.size(), n_slots])
	var still_carried := 0
	for c in _carried:
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			still_carried += 1
	_ok(still_carried == CYCLES,
		"all %d grabbed bales are still alive (mass was not DESTROYED either, found %d)"
			% [CYCLES, still_carried])
	# Informational only, and deliberately tolerant: a build without the
	# consumed-slot ledger must still reach section D and fail on BEHAVIOUR
	# above, not crash on a missing member here.
	var consumed = _mgr.get("_consumed_slots")
	_info("consumed slots recorded by the manager: %s"
		% (str((consumed as Dictionary).size()) if consumed is Dictionary else "no such ledger on this build"))

	# The reset button must re-adopt the bales it snaps home, not double them.
	print("\n-- D. shift-leader 'Reset bales' after the hauls --")
	var n_reset : int = _mgr.call("reset_yard_bales")
	# Mirror the restore half: reset_yard_bales (BaleYardManager.gd:486-495)
	# writes each reset bale's MultiMesh instance back to a full-scale transform,
	# so those slots are no longer blanked.
	for c2 in _carried:
		if is_instance_valid(c2) and not c2.is_queued_for_deletion():
			_blanked.erase(String(c2.get_meta("slot_key", "")))
	await get_tree().process_frame
	await _tick()
	var after_reset := _live_bodies()
	_info("reset_yard_bales() reported %d" % n_reset)
	_ok(after_reset.size() <= n_slots,
		"after reset: %d live yard bales for %d slots — reset did not mint bales"
			% [after_reset.size(), n_slots])
	_ok(_dup_slot_keys(after_reset).is_empty(), "after reset: no slot holds two bodies")
	_ok(_invisible_solids(after_reset).is_empty(),
		"after reset: no invisible solids (%s)" % str(_invisible_solids(after_reset)))

	# -------------------------------------------------------------------------
	# E. The OTHER consumption route: the line eats the bale. LineFlow.gd:2085
	#    frees a bale outright once remaining_kg reaches 0 (BaleBurst.gd:115 does
	#    the same to the husk). That slot is spent for good — a yard that grows
	#    the bale back is creating feedstock the plant never bought.
	# -------------------------------------------------------------------------
	print("\n-- E. a bale fed into the line must not grow back --")
	var eaten : Node3D = null
	for b in after_reset:
		if bool(b.get_meta("simple_bale", true)) and not _carried.has(b):
			eaten = b
			break
	if eaten == null:
		_ok(false, "found an in-slot bale for the line to consume")
		return
	var eaten_key := String(eaten.get_meta("slot_key", ""))
	var before_eat : int = after_reset.size()
	eaten.queue_free()                       # exactly what LineFlow.gd:2085 does
	await get_tree().process_frame
	await get_tree().process_frame
	var after_eat := _live_bodies()
	_ok(after_eat.size() == before_eat - 1,
		"line consumed '%s': %d -> %d bales" % [eaten_key, before_eat, after_eat.size()])

	var budget : int = n_slots - 1           # the yard is one bale poorer, forever
	await _tick()                            # sweep with the vehicle still close
	_ok(_live_bodies().size() <= budget,
		"same-spot sweep did not refill the consumed slot (%d, budget %d)"
			% [_live_bodies().size(), budget])
	# Drive away and come back — the exact motion that re-minted bales before.
	_move_rig(far_pos)
	await _tick()
	_move_rig(_yard_centre + Vector3(0.0, 0.0, HALF + 1.0))
	await _tick()
	var final_bodies := _live_bodies()
	_ok(final_bodies.size() <= budget,
		"after driving away and back: %d bales, budget %d — the eaten bale stayed eaten"
			% [final_bodies.size(), budget])
	var reborn := 0
	for b in final_bodies:
		if String(b.get_meta("slot_key", "")) == eaten_key:
			reborn += 1
	_ok(reborn == 0, "slot '%s' holds %d bodies after the round trip (expect 0)"
		% [eaten_key, reborn])


# =============================================================================
# helpers
# =============================================================================
## One 0.5 s sweep tick, then let queue_free() actually take effect.
func _tick() -> void:
	_mgr.call("tick", 0.6)
	await get_tree().process_frame
	await get_tree().process_frame


## Every yard-bale body that really exists right now.
func _live_bodies() -> Array[Node3D]:
	var out : Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("yard_bale_rb"):
		if not is_instance_valid(n):
			continue
		var n3 := n as Node3D
		if n3 == null or n3.is_queued_for_deletion():
			continue
		out.append(n3)
	return out


## Scale length of a body's MultiMesh instance; -1 if it has no MM binding.
func _mm_scale(body: Node3D) -> float:
	if not (body.has_meta("yard_mm_inst") and body.has_meta("yard_mm_idx")):
		return -1.0
	var mmi := body.get_meta("yard_mm_inst") as MultiMeshInstance3D
	var idx := int(body.get_meta("yard_mm_idx"))
	if mmi == null or mmi.multimesh == null or idx < 0 or idx >= mmi.multimesh.instance_count:
		return -1.0
	return mmi.multimesh.get_instance_transform(idx).basis.get_scale().length()


## Bodies with NO visual of their own (simple_bale) whose MultiMesh slot is
## blanked — i.e. the operator cannot see them but the forklift hits them.
func _invisible_solids(bodies: Array[Node3D]) -> Array[String]:
	var out : Array[String] = []
	for b in bodies:
		if not bool(b.get_meta("simple_bale", true)):
			continue        # has its own Model mesh — visible by construction
		var key := String(b.get_meta("slot_key", b.name))
		var blanked : bool = (_mm_scale(b) < 0.001) if _mm_readback else _blanked.has(key)
		if blanked:
			out.append(key)
	return out


## Does this renderer store MultiMesh instance transforms at all? Written on a
## throwaway MultiMesh so the yard's own buffer is never touched.
func _probe_mm_readback() -> bool:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	var want := Transform3D(Basis.IDENTITY.scaled(Vector3(2.0, 2.0, 2.0)), Vector3(7.0, 8.0, 9.0))
	mm.set_instance_transform(0, want)
	return mm.get_instance_transform(0).origin.distance_to(want.origin) < 0.001


func _dup_slot_keys(bodies: Array[Node3D]) -> Array[String]:
	var seen : Dictionary = {}
	var dups : Array[String] = []
	for b in bodies:
		var k := String(b.get_meta("slot_key", ""))
		if k == "":
			continue
		if seen.has(k) and not dups.has(k):
			dups.append(k)
		seen[k] = true
	return dups


## Move the vehicle and every bale in its forks together.
func _move_rig(to: Vector3) -> void:
	_veh.global_position = to
	for i in _carried.size():
		var b : Node3D = _carried[i]
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			b.global_position = to + Vector3(0.0, 0.6, 1.2 + 0.2 * float(i))


func _nearest_slot_distance(from: Vector3) -> float:
	var best := INF
	for s in (_mgr.get("_yard_slots") as Array):
		var d : float = (from - ((s as Dictionary)["spawn_pos"] as Vector3)).length()
		if d < best:
			best = d
	return best


func _stash_layout() -> void:
	_saved_yards    = WorldLayout.bale_yards.duplicate(true)
	_saved_yards_pc = WorldLayout.bale_yards_pc.duplicate(true)
	_saved_pc_flag  = WorldLayout.has_pc_data


func _finish() -> void:
	WorldLayout.bale_yards    = _saved_yards
	WorldLayout.bale_yards_pc = _saved_yards_pc
	WorldLayout.has_pc_data   = _saved_pc_flag
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
