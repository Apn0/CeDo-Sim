extends Node
## WINDOWED visual proof for the web HMI (task #2) — NOT part of the headless
## harness (needs a real display: the WebView is a native WebView2 window).
##
## Boots MainWorld from a COPY of the operator's save1 (slot "hmiproof" — the
## real save is never opened for writing), waits for the placed
## hmi_washing_all panel, opens its overlay through the REAL Hmi._open_overlay
## routing (scope -> web_screen -> HmiWebOverlay -> WebView -> hmi_shell.html),
## then issues a PLC line start so the pushed amps/status are visibly live.
##
## Prints [PROOF] marker lines; an external driver watches them and takes
## OS-level screenshots (Godot's own viewport capture can NOT see the native
## WebView2 child window).
##
## Run:  godot --path . res://src/tests/proof_hmi_web.tscn   (windowed!)

const SRC_SLOT := "save1"
const PROOF_SLOT := "hmiproof"

func _ready() -> void:
	print("[PROOF] boot")
	for suffix in ["_factory.json", "_save.json"]:
		var s := "user://%s%s" % [SRC_SLOT, suffix]
		var d := "user://%s%s" % [PROOF_SLOT, suffix]
		if FileAccess.file_exists(s):
			var err := DirAccess.copy_absolute(s, d)
			if err != OK:
				print("[PROOF] FAIL copying %s (err %d)" % [s, err])
				get_tree().quit(2)
				return
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", PROOF_SLOT)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("[PROOF] FAIL MainWorld.tscn load")
		get_tree().quit(2)
		return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)

	# Wait (up to ~90 s of frames) for the save-placed washing HMI panel.
	var hmi : Node = null
	for i in range(60 * 90):
		await get_tree().process_frame
		for h in get_tree().get_nodes_in_group("hmi"):
			if h.has_meta("hmi_id") and String(h.get_meta("hmi_id")) == "hmi_washing_all":
				hmi = h
				break
		if hmi != null:
			break
	if hmi == null:
		print("[PROOF] FAIL no hmi_washing_all in the world")
		get_tree().quit(3)
		return
	print("[PROOF] hmi found — opening web overlay via Hmi._open_overlay")
	hmi.call("_open_overlay")

	# Let the shell boot (React + first vals push), then show idle state.
	for i in range(60 * 6):
		await get_tree().process_frame
	print("[PROOF] overlay open (idle values)")

	# PLC cold start → machines power up → live amps in the value boxes.
	var lf := get_tree().get_first_node_in_group("line_flow")
	if lf != null and lf.has_method("start_line"):
		lf.call("start_line")
		print("[PROOF] start_line issued")
	else:
		print("[PROOF] WARN no LineFlow to start")

	for i in range(60 * 20):
		await get_tree().process_frame
	print("[PROOF] done — exiting")
	get_tree().quit(0)
