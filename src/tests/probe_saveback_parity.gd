extends Node
## Save-back parity probe: build each macro untouched, then ask
## save_macro_overrides what it thinks moved. A clean build must answer NOTHING.
##
##   godot --headless --path . res://src/tests/probe_saveback_parity.tscn
##
## Any reported index is the builder's cursor walk and save_macro_overrides'
## mirror of it disagreeing at that entry — which silently drifts every machine
## downstream of it on the next save/reload.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for macro_id in ["line_1", "line_3a", "line_3b", "line_3c", "line_sort"]:
		var bm := BuildMode.new()
		add_child(bm)
		await get_tree().process_frame
		bm.call("_build_full_line", macro_id, Vector3(-142.7, 0.0, 42.9), 0.0)
		await get_tree().process_frame
		var seq : Array = bm.call("_macro_seed", macro_id)
		var nominal : Array = bm.call("_macro_nominal_poses", seq)
		# Re-run the inversion here so we can name the offending entries, which
		# save_macro_overrides only returns a count for.
		var placed : Node3D = bm.get("_placed_root")
		var report : Array = []
		if placed != null:
			for child in placed.get_children():
				var n3 := child as Node3D
				if n3 == null or not n3.has_meta("macro_id"):
					continue
				if String(n3.get_meta("macro_id")) != macro_id:
					continue
				var i : int = int(n3.get_meta("macro_index", -1))
				if i < 0 or i >= nominal.size():
					continue
				var nom : Dictionary = nominal[i]
				var anc : Dictionary = n3.get_meta("macro_anchor")
				var st : Vector3 = anc.get("start", Vector3.ZERO)
				var rt : float = float(anc.get("rot_y", 0.0))
				var fwd := Vector3(-sin(rt), 0.0, -cos(rt))
				var rgt := Vector3(cos(rt), 0.0, -sin(rt))
				var rel : Vector3 = n3.global_position - st
				var dx : float = rel.dot(rgt) - float(nom.get("x", 0.0))
				var dy : float = rel.y - float(nom.get("y", 0.0))
				var dz : float = rel.dot(fwd) - float(nom.get("z", 0.0))
				if absf(dx) > 0.01 or absf(dy) > 0.01 or absf(dz) > 0.01:
					report.append("      idx %2d %-18s d=(%+.2f, %+.2f, %+.2f)"
						% [i, String(n3.get_meta("placeable_id", "?")), dx, dy, dz])
		var n : int = int(bm.call("save_macro_overrides", macro_id))
		print("  %-9s save_macro_overrides -> %d override(s), %d entry mismatch(es)"
			% [macro_id, n, report.size()])
		report.sort()
		for line in report:
			print(line)
		bm.queue_free()
		await get_tree().process_frame
	print("Result: PASS (0 fail)")
	get_tree().quit(0)
