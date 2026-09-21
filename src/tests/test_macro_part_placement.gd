extends Node
## MACRO PART PLACEMENT — every visible part of a macro-placed machine must
## actually BE on that machine.
##
##   godot --headless --path . res://src/tests/test_macro_part_placement.tscn
##
## WHY THIS FILE EXISTS. Found 2026-09-16 while framing an orthographic plan
## render of line 1 (src/tests/shot_line1_plan.gd): the measured bounding box of
## the line came out 269 m wide instead of 120 m, because 47 parts were sitting
## at the WORLD ORIGIN instead of on their machines. They were visible, so the
## world had a cluster of stray hatches and gate leaves floating in mid-air at
## roughly (0, 3, 0), and shredder_1's inspection hatch was at global
## (1.76, 3.19, 0.00) while the shredder itself stood at (-156.76, 0, 38.98).
##
## The cause was `AnimatableBody3D.sync_to_physics`, which defaults to TRUE. With
## it on, Godot drives the body FROM the physics server every tick
## (`global_transform = state.transform`), and the server is only told about a
## new transform when the body's OWN transform is written — moving an ANCESTOR
## never notifies it. Machines are built at the catalog's local origin and moved
## into place afterwards by the line macro, so each of these bodies stayed pinned
## to the global transform it held at build time, which was its intended LOCAL
## offset. Fixed by clearing the flag at all three construction sites
## (PlaceableCatalog._interactive_hatch, PushGate._build_hinge_pivot,
## Door._build_hinge_pivot).
##
## Nothing caught it: the geometry suites check where MACHINES land, not where a
## machine's own parts land relative to it, and the flow suites only care about
## ports. This asserts the missing invariant, over several macros, so the next
## sub-assembly built from a physics body cannot strand itself silently.
##
## MUTATION-TESTED 2026-09-16, twice, on two DIFFERENT construction paths, so
## this is not a one-site proof — both went red on all three macros:
##   sync_to_physics = true at PlaceableCatalog._interactive_hatch
##     -> 37 / 14 / 18 stray parts (line_1 / 3a / 3c), 143-265 m out
##   sync_to_physics = true at PushGate._build_hinge_pivot
##     -> 10 / 10 / 10 stray silo-gate leaves, 143-266 m out
## Restored, both green again. NOTE the first mutation would now be caught one
## step earlier: InteractiveHatch._ready clears the flag itself, so re-running
## that exact mutation stays green — re-do it at the PushGate site, or delete
## the _ready line too, if this proof ever needs repeating.

## Extra metres allowed beyond a machine's own catalog half-diagonal, for parts
## that legitimately stick out — access ladders, discharge chutes, the extruder
## silo's top-of-ladder gate.
##
## MEASURED 2026-09-16, after the fix, the worst legitimate part on each macro:
##   line_1   opzetband_1     10.5 m  (limit 17.9)
##   line_3a  extruder_silo    7.3 m  (limit 15.5)
##   line_3c  voorraad_silo    6.9 m  (limit 15.9)
## and the bug this guards against put parts 143-201 m out, so the margin is
## wide but nowhere near wide enough to let the defect back through. Each run
## reprints its closest-to-limit part, so the headroom stays a number somebody
## can check rather than a constant nobody revisits.
const OVERHANG_ALLOWANCE_M : float = 12.0

const MACROS : Array[String] = ["line_1", "line_3a", "line_3c"]

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] macro part placement — parts must sit on their own machine")
	for macro_id in MACROS:
		await _check_macro(macro_id)
	if _fails == 0:
		print("[TEST] macro part placement PASS")
		print("Result: PASS (0 fail)")
		get_tree().quit(0)
	else:
		print("[TEST] macro part placement FAIL (%d fail)" % _fails)
		print("Result: FAIL (%d fail)" % _fails)
		get_tree().quit(1)

func _check_macro(macro_id: String) -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	# Build at a start that is FAR from the world origin and on a non-zero Z.
	# Building at Vector3.ZERO would have hidden this entire class of bug: a part
	# pinned to the world origin is indistinguishable from a correctly-placed one
	# when the machine is standing on the origin itself.
	var start := Vector3(-142.7, 0.0, 42.9)
	bm.call("_build_full_line", macro_id, start, 0.0)
	await get_tree().process_frame

	var machines : Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 != null and n3.has_meta("macro_id") and String(n3.get_meta("macro_id")) == macro_id:
			machines.append(n3)
	_check(not machines.is_empty(), "%s placed machines to inspect (%d)" % [macro_id, machines.size()])

	var worst_ratio := 0.0        # (distance - limit) is what fails; ratio is for the report
	var worst_desc := ""
	var worst_over := 0.0
	var offenders : Array = []
	var parts_seen := 0
	for n3 in machines:
		var node := n3 as Node3D
		var mid := String(node.get_meta("placeable_id", node.name))
		var item : Dictionary = PlaceableCatalog.get_item(mid)
		var size : Vector3 = (item["size"] as Vector3) if item.has("size") else Vector3(2.0, 2.0, 2.0)
		var limit : float = Vector3(size.x, size.y, size.z).length() * 0.5 + OVERHANG_ALLOWANCE_M
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
				continue
			# VerletRope3D draws its rope mesh top_level in world coordinates and
			# its points are all zero until the first physics tick, so its AABB is
			# meaningless here. Not the bug under test.
			if mi.top_level:
				continue
			parts_seen += 1
			var w : AABB = mi.global_transform * mi.get_aabb()
			var centre : Vector3 = w.position + w.size * 0.5
			var d : float = centre.distance_to(node.global_position)
			if d > limit:
				offenders.append("%s/%s  %.1f m from its machine (limit %.1f)" % [mid, mi.name, d, limit])
				if d - limit > worst_over:
					worst_over = d - limit
			var ratio : float = d / maxf(limit, 0.001)
			if ratio > worst_ratio:
				worst_ratio = ratio
				worst_desc = "%s/%s  %.1f m (limit %.1f)" % [mid, mi.name, d, limit]

	print("    %s: %d visible parts, closest-to-limit %s" % [macro_id, parts_seen, worst_desc])
	_check(offenders.is_empty(),
		"%s every visible part sits on its own machine (%d stray)" % [macro_id, offenders.size()])
	for o in offenders.slice(0, 10):
		print("        stray: " + o)
	if offenders.size() > 10:
		print("        ... and %d more" % (offenders.size() - 10))

	bm.queue_free()
	await get_tree().process_frame
