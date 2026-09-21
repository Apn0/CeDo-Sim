extends Node
## Dump line 1's HEAD geometry, measured from a real build, as JSON.
##
##   godot --headless --path . res://src/tests/dump_line1_head.tscn
##
## Feeds tools/line1_head_schematic.py, which draws the labelled plan +
## elevation of the feeder → Westa → shredder run. Split out as its own tool
## because the numbers that matter here are not node positions — they are the
## belts' own derived ports (`_discharge_lip_pos`, `deck_height`, `incline_run`)
## and the shredder's throat, none of which appear in the whole-line dump that
## shot_line1_plan.gd writes.
##
## WHY A DRAWING AND NOT A RENDER. The operator read an orthographic render of
## this head as showing the feeder pointing the wrong way. It was not: what
## looked like the Westa band was shredder_1's own 11.4 m built-in discharge
## conveyor, which overhangs the machine's 5.0 m catalog footprint and dominates
## the frame. A photograph of that head is genuinely ambiguous. A labelled
## drawing built from these numbers is not.
##
## Headless-safe: it measures, it does not render.

const OUT_PATH : String = "res://docs/plant/line1_head_geometry_2026_09_17.json"

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	# Built away from the world origin deliberately — a geometry bug that
	# resolves to (0,0,0) is invisible when the line starts there.
	bm.call("_build_full_line", "line_1", Vector3(-142.7, 0.0, 42.9), 0.0)
	await get_tree().process_frame

	var opz : Node3D = null
	var wes : Node3D = null
	var shr : Node3D = null
	var belt : Node3D = null
	var mag : Node3D = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 == null or not n3.has_meta("macro_id"):
			continue
		if String(n3.get_meta("macro_id")) != "line_1":
			continue
		match String(n3.get_meta("placeable_id", "")):
			"opzetband_1": opz = n3
			"westa_band_1": wes = n3
			"shredder_1": shr = n3
			"overband_magnet": mag = n3
			"transport_belt":
				# The uitvoerband is the FIRST transport_belt on the line; the
				# other is the short leg-C belt one turn downstream.
				if belt == null:
					belt = n3
	if opz == null or wes == null or shr == null or belt == null or mag == null:
		print("FATAL: head machines missing (opz=%s wes=%s shr=%s belt=%s mag=%s)"
			% [opz != null, wes != null, shr != null, belt != null, mag != null])
		get_tree().quit(1)
		return

	var ssz : Vector3 = PlaceableCatalog.get_item("shredder_1")["size"]
	var bsz : Vector3 = PlaceableCatalog.get_item("transport_belt")["size"]
	# Deck top from BeltBuilder's own default rather than a copy of it.
	var frac : float = float(BeltBuilder.make_spec().get("deck_y_frac", 0.75))

	var d : Dictionary = {
		"opz": {
			"tail": var_to_str(opz.to_global(Vector3.ZERO)),
			"lip": var_to_str(opz.call("_discharge_lip_pos")),
			"deck_h": float(opz.get("deck_height")),
			"incline_deg": float(opz.get("incline_deg")),
			"incline_run": float(opz.get("incline_run")),
			"deck_width": float(opz.get("deck_width")),
			"funnel_min_width": float(opz.get("funnel_min_width")),
			"funnel_start_m": float(opz.get("funnel_start_m")),
			"funnel_narrow_m": float(opz.get("funnel_narrow_m")),
		},
		"wes": {
			"tail": var_to_str(wes.to_global(Vector3(0.0, float(wes.get("deck_height")), 0.0))),
			"lip": var_to_str(wes.call("_discharge_lip_pos")),
			"deck_h": float(wes.get("deck_height")),
			"incline_deg": float(wes.get("incline_deg")),
			"incline_run": float(wes.get("incline_run")),
		},
		"shr": {
			"pos": var_to_str(shr.global_position),
			"throat": var_to_str(shr.to_global(PlaceableCatalog.shredder_infeed_local(ssz))),
			"out_y": shr.global_position.y
				+ float((MachineFlow.profile("shredder_1")["out"] as Vector3).y) * ssz.y,
			"size": var_to_str(ssz),
		},
		"belt": {
			"pos": var_to_str(belt.global_position),
			"deck": belt.global_position.y + bsz.y * frac,
			"size": var_to_str(bsz),
		},
		"mag": {"pos": var_to_str(mag.global_position)},
	}
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	print("[HEAD] wrote %s" % ProjectSettings.globalize_path(OUT_PATH))
	print("[HEAD] opzetband %.2f m @ %.0f deg, lip y %.2f"
		% [float(opz.get("incline_run")), float(opz.get("incline_deg")),
			(opz.call("_discharge_lip_pos") as Vector3).y])
	print("[HEAD] westa     %.2f m @ %.0f deg, lip y %.2f"
		% [float(wes.get("incline_run")), float(wes.get("incline_deg")),
			(wes.call("_discharge_lip_pos") as Vector3).y])
	print("Result: PASS (0 fail)")
	get_tree().quit(0)
