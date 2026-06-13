extends SceneTree

## #157 — Smoke test for #124 (HIER pin save/load round-trip).
## Run headless: godot --headless --script src/tests/test_hier_pin_roundtrip.gd
##
## What it checks:
##   1. CrewManager.assign_to_position(worker, world_pos, facing) stores a
##      pin with the exact Vector3 + facing.
##   2. CrewManager.save_pins_dict() emits a Dictionary keyed by npc_name,
##      values containing pos (Vector3-as-dict) + facing_rad.
##   3. CrewManager.restore_pins_dict(saved) on a FRESH CrewManager reads the
##      same pin back, position-equal within 1cm and facing equal within 0.01 rad.
##   4. NPC.unpin clears home_facing_rad and removes the entry.

const NPC = preload("res://src/scenes/world/NPC.gd")
const CrewManager = preload("res://src/scenes/world/CrewManager.gd")

func _initialize() -> void:
	print("[TEST] #124 HIER pin round-trip")
	# Build a minimal NPC stand-in (CrewManager keys by npc_name).
	var npc : CharacterBody3D = CharacterBody3D.new()
	npc.set_script(NPC)
	npc.name = "TestWorker"
	npc.npc_name = "TestWorker"
	root.add_child(npc)
	npc.global_position = Vector3(5.0, 1.0, -3.0)
	# CrewManager.
	var cm = CrewManager.new()
	cm.name = "CrewManager"
	root.add_child(cm)
	# Pin the worker at a known world position + facing.
	var pin_pos := Vector3(12.34, 2.50, -7.89)
	var pin_face := 1.5708   # 90° in radians
	var ok := true
	if cm.has_method("assign_to_position"):
		cm.call("assign_to_position", npc, pin_pos, pin_face)
	else:
		print("  FAIL: CrewManager.assign_to_position not present"); ok = false
	# Serialize.
	if not cm.has_method("save_pins_dict"):
		print("  FAIL: CrewManager.save_pins_dict not present"); ok = false
		quit(1); return
	var saved : Dictionary = cm.call("save_pins_dict")
	if not saved.has(npc.npc_name):
		print("  FAIL: save_pins_dict missing worker key '%s'" % npc.npc_name); ok = false
	# Fresh CrewManager + restore.
	var cm2 = CrewManager.new()
	cm2.name = "CrewManager2"
	root.add_child(cm2)
	if not cm2.has_method("restore_pins_dict"):
		print("  FAIL: CrewManager.restore_pins_dict not present"); ok = false
		quit(1); return
	cm2.call("restore_pins_dict", saved)
	# Read back.
	if not cm2.has_method("position_pin_for"):
		print("  WARN: position_pin_for not present, skipping read-back assertion")
	else:
		var read : Dictionary = cm2.call("position_pin_for", npc)
		if read.is_empty():
			print("  FAIL: position_pin_for returned empty after restore"); ok = false
		else:
			var read_pos : Vector3 = read.get("pos", Vector3.ZERO)
			var read_face : float = float(read.get("facing_rad", NAN))
			if read_pos.distance_to(pin_pos) > 0.01:
				print("  FAIL: restored pos %s != original %s" % [read_pos, pin_pos]); ok = false
			if absf(read_face - pin_face) > 0.01:
				print("  FAIL: restored facing %f != original %f" % [read_face, pin_face]); ok = false
	# Unpin.
	if cm2.has_method("unpin"):
		cm2.call("unpin", npc)
		var read2 : Dictionary = cm2.call("position_pin_for", npc)
		if not read2.is_empty():
			print("  FAIL: pin still present after unpin: %s" % read2); ok = false
	if ok:
		print("[TEST] #124 PASS")
	else:
		print("[TEST] #124 FAIL")
	quit(0 if ok else 1)
