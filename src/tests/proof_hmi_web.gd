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

## Native canvas of the screen under proof. Sizing the game window to exactly
## this makes the WebView render the design 1:1 — no letterbox scale — so the
## capture can be diffed against the .dc.html rendered in a plain browser.
## (2026-08-10: an earlier capture looked "cropped"; measured cause was the game
## window hanging off the desktop edge at 1920x1080, NOT a render defect —
## window/viewport/Control/page all agreed exactly. Pinning the size removes
## the whole class of screenshot artefact.)
const PROOF_W : int = 1280
const PROOF_H : int = 800

## Seconds the overlay is held open after the CAPTURE NOW marker.
const CAPTURE_HOLD_S : float = 45.0

func _ready() -> void:
	print("[PROOF] boot")
	DisplayServer.window_set_size(Vector2i(PROOF_W, PROOF_H))
	DisplayServer.window_set_position(Vector2i(80, 80))
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

	# Wait (up to 90 REAL seconds) for the save-placed washing HMI panel.
	var hmi : Node = null
	var waited := 0.0
	while waited < 90.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
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
	await _hold_seconds(6.0)
	print("[PROOF] overlay open (idle values)")

	# PLC cold start → machines power up → live amps in the value boxes.
	var lf := get_tree().get_first_node_in_group("line_flow")
	if lf != null and lf.has_method("start_line"):
		lf.call("start_line")
		print("[PROOF] start_line issued")
	else:
		print("[PROOF] WARN no LineFlow to start")

	await _hold_seconds(12.0)

	# Re-assert the overlay before the capture window. Measured 2026-08-10: a
	# spurious {"type":"close"} arrived from the page during the run (the native
	# WebView2 child window can receive an activation click on the ✕ when the
	# game window is moved/resized under the cursor), which left the capture
	# showing the 3D world instead of the HMI. Re-opening makes the proof
	# independent of that, and CAPTURE_HOLD_S gives the screenshotter a wide,
	# clearly-marked window.
	hmi.call("_open_overlay")
	await _hold_seconds(3.0)
	print("[PROOF] CAPTURE NOW — overlay re-asserted, holding %.0f s" % CAPTURE_HOLD_S)
	await _hold_seconds(CAPTURE_HOLD_S)
	print("[PROOF] done — exiting")
	get_tree().quit(0)

## Wall-clock wait. NEVER count frames for a human-facing hold: this scene runs
## WINDOWED with the full plant rendering, measured at 4 fps, so the original
## `for i in range(60 * 30)` meant 1800 frames = 7.5 MINUTES, not 30 s — it left
## the run occupying the machine long after the screenshot was taken and blocked
## the regression harness queued behind it (2026-08-10).
func _hold_seconds(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
