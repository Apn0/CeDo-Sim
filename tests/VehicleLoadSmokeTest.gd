extends Node3D

## Smoke test: instance the vehicles that NO other test loads (MerloP40 +
## ScissorLift) inside a full scene-tree run (autoloads present), let them run
## _ready + a few physics frames, and confirm no script error / crash. The FBX
## isn't editor-imported in CI, so MerloP40 takes its placeholder path — that's
## fine; we're proving the GDScript compiles + _ready runs end-to-end.

func _ready() -> void:
	var ok := 0
	var fail := 0
	for path in ["res://src/scenes/vehicles/MerloP40.tscn",
				 "res://src/scenes/vehicles/ScissorLift.tscn",
				 "res://src/scenes/vehicles/Forklift.tscn",
				 "res://src/scenes/vehicles/BaleClamp.tscn"]:
		var scn := load(path) as PackedScene
		if scn == null:
			print("  FAIL  could not load %s" % path); fail += 1; continue
		var inst := scn.instantiate()
		if inst == null:
			print("  FAIL  could not instantiate %s" % path); fail += 1; continue
		add_child(inst)
		inst.global_position = Vector3(0, 0, 0)
		print("  ok    %s" % path); ok += 1
	# Let _ready / call_deferred (LPG tanks, aux lights, FBX load) settle.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("RESULT: %d passed, %d failed" % [ok, fail])
	get_tree().quit()
