extends Node
## PROBE (2026-09-23) — what a recursive find_child costs on a real bale, per
## call, versus a cached reference. Written for the BaleClamp._update_wire_bulge
## fix (it ran find_child("Wires", true) every physics tick while carrying) and
## the LumpCart._now_sim_s one (whole-tree find_child per call). Numbers are
## printed, not asserted: this is a measurement, not a gate. Not wired in run.sh.
##
##   godot --headless --path . res://src/tests/probe_find_child_cost.tscn

const N := 2000

func _ready() -> void:
	call_deferred("_run")

func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

func _run() -> void:
	print("[PROBE] find_child cost")
	var bale : Node3D = PlaceableCatalog.build_node("rotterdam", false)
	if bale == null:
		print("FATAL: catalog could not build a bale")
		get_tree().quit(2); return
	add_child(bale)
	await get_tree().process_frame
	var nodes := _count(bale)
	var t0 := Time.get_ticks_usec()
	var hits := 0
	for _i in N:
		if bale.find_child("Wires", true, false) != null:
			hits += 1
	var t1 := Time.get_ticks_usec()
	var cached : Node = bale.find_child("Wires", true, false)
	var hits2 := 0
	for _i in N:
		if cached != null and is_instance_valid(cached):
			hits2 += 1
	var t2 := Time.get_ticks_usec()
	print("  info  : bale subtree %d nodes; find_child('Wires', true) x%d = %.1f us/call (%d hits); cached ref x%d = %.2f us/call (%d hits)"
		% [nodes, N, float(t1 - t0) / N, hits, N, float(t2 - t1) / N, hits2])
	# Whole-tree search like the old LumpCart._now_sim_s: build a wider tree first.
	var pad := Node.new()
	add_child(pad)
	for _i in 3000:
		pad.add_child(Node.new())
	var total := _count(get_tree().root)
	var t3 := Time.get_ticks_usec()
	for _i in 200:
		get_tree().root.find_child("ShiftClock", true, false)
	var t4 := Time.get_ticks_usec()
	print("  info  : whole tree %d nodes; root.find_child('ShiftClock', true) x200 = %.1f us/call (miss)" % [total, float(t4 - t3) / 200.0])
	print("Result: PASS (1 ok, 0 fail — measurement printed above)")
	get_tree().quit(0)
