extends Node
## PROBE (measures, gates nothing) — what does load_layout's macro re-derivation
## do with a given layout file?
##
##   APPDATA=<scratch> godot --headless --path . res://src/tests/probe_macro_rederive_survey.tscn -- <file.json> [...]
##
## Each argument is a file name under user:// (copy the layouts you want to
## survey into the SCRATCH app_userdata first — this probe never writes, but
## run it on copies anyway). For each file a bare BuildMode loads it
## (load_shared_structure / allow_legacy_fallback off, never saved) and the
## probe prints BuildMode.last_macro_rederive: one line per macro instance,
## stamped / authored / refused, with the reason.
##
## Written 2026-09-25 to measure what the re-derivation does to every
## macro-bearing layout on the operator's machine (test slots, sandbox,
## gauntlet) — docs/audit/macro_edges_reload_2026-09-25.md.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var files : PackedStringArray = OS.get_cmdline_user_args()
	for f in files:
		var bm := BuildMode.new()
		bm.layout_path = "user://" + f
		bm.load_shared_structure = false
		bm.allow_legacy_fallback = false
		add_child(bm)                       # _ready → load_layout → re-derive
		await get_tree().process_frame
		var rep : Variant = bm.get("last_macro_rederive")
		print("SURVEY %s: %d macro instance(s)" % [f, (rep as Array).size() if rep is Array else -1])
		if rep is Array:
			for r in rep:
				var d : Dictionary = r
				print("SURVEY   %-18s %-8s %3d machines / %3d-entry SEQ, %3d edges%s" % [d["macro_id"], d["status"],
					int(d["members"]), int(d["seq_size"]), int(d["edges"]),
					("  — " + String(d["reason"])) if String(d["reason"]) != "" else ""])
		bm.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("Result: PROBE DONE (%d files)" % files.size())
	get_tree().quit(0)
