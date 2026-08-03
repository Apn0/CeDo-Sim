extends Node
## #gauntlet-parity — the gauntlet must now spawn an OperatorContext so vehicles
## are boardable there (was missing → bale clamp un-enterable).
func _ready() -> void:
	print("=== Gauntlet OperatorContext presence ===")
	var scn := load("res://src/scenes/world/GauntletWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: GauntletWorld.tscn failed to load"); get_tree().quit(2); return
	var g : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(g)
	for i in range(40):
		await get_tree().process_frame
	var oc := get_tree().get_first_node_in_group("operator_context")
	var ok := oc != null and oc.get("on_foot_body") != null
	print("  %s : operator_context in group + wired to player (%s)" % ["ok    " if ok else "FAIL  ", str(oc)])
	print("Result: %s" % ("PASS" if ok else "FAIL"))
	g.queue_free()
	get_tree().quit(0 if ok else 1)
