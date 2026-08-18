extends CanvasLayer
class_name HmiWebOverlay

## HmiWebOverlay — renders the Claude-Design HMI exports (.dc.html) as the
## live in-game HMI (task #2, operator order: NO re-porting to Godot Controls).
##
## Architecture (decided after mapping godot_wry's compositing model):
##   - godot_wry's WebView is a NATIVE WebView2 child window floating above the
##     whole Godot output — it can never be a texture on a 3D machine screen.
##     That matches the existing HMI UX anyway: walk to a panel, press E, get a
##     fullscreen overlay (HmiOverlay). This class is the WebView twin of that.
##   - The WebView loads ONE host page, hmi_shell.html (same directory as the
##     screen exports). The 34 .dc.html design files are NEVER modified: Godot
##     reads a screen file and pushes its bytes to the shell (post_message,
##     base64); the shell iframes it, injects local React (vendor/) so
##     support.js never touches the unpkg CDN, scales the fixed-px canvas, and
##     wires the dead nav buttons back to us over IPC.
##   - GODOT OWNS ALL LOGIC (headless-testable): which screen a panel starts
##     on (HmiScopes "web_screen"), the ◀/▶/home navigation order (parsed from
##     "HMI Index.dc.html"'s own link list), file loading, and the 4 Hz live
##     value push from LineFlow. The JS side only renders and reports clicks.
##
## IPC contract (see hmi_shell.html header for the JS side):
##   shell → Godot: ready / screen_ready / nav{dir} / open{file} / close /
##                  event{name,screen}
##   Godot → shell: screen{file,b64} / vals{screen,pills,units,alarm}

const SCREENS_DIR := "res://docs/plant/hmi_screens_2026-07-26/"
const SHELL_URL   := SCREENS_DIR + "hmi_shell.html"
const INDEX_FILE  := "HMI Index.dc.html"

## Live-push cadence — mirrors HmiOverlay's 4 Hz refresh.
const PUSH_INTERVAL_S := 0.25

# State-pill colours used by the .dc.html designs (see hmi_shell.html).
const _GREEN := "#35c23a"
const _GREY  := "#6a7a8a"
const _RED   := "#e02020"
const _AMBER := "#e8c040"

var _web : Control = null
var _shell_ready := false
var _pending_screen := ""
var _current_screen := ""
var _screen_order : Array[String] = []   # Index card order = ◀/▶ sequence
var _order_built := false                # lazy — built on first use
var _line_flow : Node = null
var _shift_clock : Node = null
var _scope : Dictionary = {}
var _accum := 0.0

func _init() -> void:
	layer = 46            # one above HmiOverlay (45) — never both open anyway
	visible = false

func _ready() -> void:
	_ensure_screen_order()

## True when a WebView can actually exist here. Headless runs (regression
## harness, CI) skip webview creation inside the addon, so the whole web-HMI
## path must fall back to the GDScript touchscreen there.
static func webview_available() -> bool:
	return DisplayServer.get_name() != "headless" and ClassDB.class_exists("WebView")

## Mirrors HmiOverlay.open_for(label, scope) — called by Hmi.gd on interact.
func open_for(_label: String, scope: Dictionary) -> void:
	_scope = scope
	var start := String(scope.get("web_screen", INDEX_FILE))
	_ensure_webview()
	visible = true
	if _web != null:
		_web.visible = true
	if _shell_ready:
		_send_screen(start)
	else:
		_pending_screen = start

func close() -> void:
	visible = false
	if _web != null and is_instance_valid(_web):
		_web.visible = false   # hides the NATIVE WebView2 child window too
		if _web.has_method("release_focus"):
			_web.call("release_focus")
	get_viewport().gui_release_focus()
	DisplayServer.window_move_to_foreground()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	# Esc closes, exactly like the GDScript overlay. Key events reach us even
	# while the webview has pointer focus because forward_input_events relays
	# them back into Godot's input pipeline.
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible or _web == null or not _shell_ready:
		return
	_accum += delta
	if _accum < PUSH_INTERVAL_S:
		return
	_accum = 0.0
	_push_vals()

# ── WebView lifecycle ──────────────────────────────────────────────────────

func _ensure_webview() -> void:
	if _web != null and is_instance_valid(_web):
		return
	if not webview_available():
		return
	_web = ClassDB.instantiate("WebView") as Control
	if _web == null:
		push_warning("[HmiWebOverlay] WebView class exists but failed to instantiate")
		return
	_web.name = "WebView"
	# The Control rect (not the whole OS window) positions the native webview.
	_web.set("full_window_size", false)
	_web.set("transparent", false)
	_web.set("devtools", true)
	# Keep keyboard focus with Godot (Esc handled natively); mouse clicks hit
	# the native webview by z-order regardless of keyboard focus.
	_web.set("focused_when_created", false)
	_web.set("forward_input_events", true)
	_web.set("url", SHELL_URL)   # res:// — served through Godot FileAccess
	_web.set_anchors_preset(Control.PRESET_FULL_RECT)
	_web.connect("ipc_message", _on_ipc)
	_web.connect("page_load_started", func(u): print("[HmiWebOverlay] page_load_started: %s" % str(u)))
	_web.connect("page_load_finished", func(u):
		print("[HmiWebOverlay] page_load_finished: %s" % str(u))
		# Diagnostic probe: eval() bypasses any page CSP, so if this arrives
		# but "ready" never did, the page's own <script> was blocked; if this
		# never arrives either, the ipc channel itself is broken.
		_web.call("eval",
			"window.ipc && window.ipc.postMessage(JSON.stringify({type:'probe'," +
			"shell:String(typeof window.__shellNav), err:String(window.__lastErr||'')," +
			"scripts:document.querySelectorAll('script').length," +
			"bodyLen:document.body?document.body.innerHTML.length:-1," +
			"pageW:window.innerWidth, pageH:window.innerHeight," +
			"title:String(document.title)}))"))
	add_child(_web)
	print("[HmiWebOverlay] WebView created, loading %s" % SHELL_URL)

func _on_ipc(message: String) -> void:
	var data : Variant = JSON.parse_string(message)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var mtype := String(data.get("type", ""))
	if mtype != "":
		# Full payload for diagnostics; vals/screen echoes would just be noise.
		if mtype == "probe" or mtype == "event":
			print("[HmiWebOverlay] ipc: %s" % message)
		else:
			print("[HmiWebOverlay] ipc: %s" % mtype)
	var d : Dictionary = data
	match String(d.get("type", "")):
		"ready":
			# The shell's own JS booted — safe to push screens from now on.
			_shell_ready = true
			if _pending_screen != "":
				var p := _pending_screen
				_pending_screen = ""
				_send_screen(p)
		"screen_ready":
			_push_vals()   # immediate first paint, don't wait for the 4 Hz tick
		"nav":
			_send_screen(_nav_target(String(d.get("dir", ""))))
		"open":
			var f := String(d.get("file", ""))
			if _is_known_screen(f):
				_send_screen(f)
			else:
				push_warning("[HmiWebOverlay] refused open of unknown screen '%s'" % f)
		"close":
			close()
		"event":
			var btn_name := String(d.get("name", "")).to_lower().strip_edges()
			
			if btn_name == "aan" or btn_name == "start":
				var lf := _find_line_flow()
				if lf and lf.has_method("start_line"):
					lf.call("start_line")
					print("[HmiWebOverlay] Line started via HMI button.")
			elif btn_name == "uit" or btn_name == "stop":
				var lf := _find_line_flow()
				if lf and lf.has_method("stop_line"):
					lf.call("stop_line")
					print("[HmiWebOverlay] Line stopped via HMI button.")
			elif btn_name == "⌂" or btn_name == "home":
				_send_screen(INDEX_FILE)
			else:
				# Log unwired buttons so we know what else needs wiring
				push_warning("[HmiWebOverlay] HMI button '%s' on %s (not wired)"
					% [String(d.get("name", "?")), String(d.get("screen", "?"))])

## The ◀/▶ sequence is the Index page's own card order — parsed from its
## href list, so navigation always matches what the Index shows the operator.
## Lazy (idempotent): _ready() calls it, but so does every consumer, because
## a caller may touch the overlay before it entered the tree (tests do).
func _ensure_screen_order() -> void:
	if _order_built:
		return
	_order_built = true
	_screen_order.clear()
	var idx := _read_screen_file(INDEX_FILE)
	if idx == "":
		push_warning("[HmiWebOverlay] %s missing — nav arrows limited to home" % INDEX_FILE)
		return
	var re := RegEx.create_from_string("href=\"([^\"]+\\.dc\\.html)\"")
	for m in re.search_all(idx):
		var f := m.get_string(1)
		if f != INDEX_FILE and not _screen_order.has(f):
			_screen_order.append(f)

## Only files the Index links to (or the Index itself) may ever be loaded —
## the shell's "open" IPC can never read arbitrary paths through us.
func _is_known_screen(file: String) -> bool:
	_ensure_screen_order()
	return file == INDEX_FILE or _screen_order.has(file)

func _nav_target(dir: String) -> String:
	_ensure_screen_order()
	if dir == "home":
		return INDEX_FILE
	if _screen_order.is_empty():
		return INDEX_FILE
	var i := _screen_order.find(_current_screen)
	if dir == "next":
		# From the Index (i == -1) ▶ enters the first screen.
		return _screen_order[(i + 1) % _screen_order.size()]
	if dir == "prev":
		if i < 0:
			return _screen_order[_screen_order.size() - 1]
		return _screen_order[(i - 1 + _screen_order.size()) % _screen_order.size()]
	return _current_screen if _current_screen != "" else INDEX_FILE

func _read_screen_file(file: String) -> String:
	return FileAccess.get_file_as_string(SCREENS_DIR + file)

func _send_screen(file: String) -> void:
	if file == "":
		return
	var html := _read_screen_file(file)
	if html == "":
		push_warning("[HmiWebOverlay] screen file empty/missing: %s" % file)
		return
	_current_screen = file
	_post({"type": "screen", "file": file, "b64": Marshalls.utf8_to_base64(html)})

func _post(d: Dictionary) -> void:
	if _web != null and is_instance_valid(_web):
		_web.call("post_message", JSON.stringify(d))

# ── live values (LineFlow → shell) ─────────────────────────────────────────

func _find_line_flow() -> Node:
	if _line_flow != null and is_instance_valid(_line_flow):
		return _line_flow
	var tree := get_tree()
	if tree == null:
		return null
	_line_flow = tree.get_first_node_in_group("line_flow")
	return _line_flow

func _push_vals() -> void:
	if _current_screen == "":
		return
	var payload := gather_vals()
	if payload.is_empty():
		return
	_post(payload)

## Builds the vals message for the current screen. Public + side-effect-free
## on purpose: the headless test drives it with a stub LineFlow.
func gather_vals() -> Dictionary:
	var lf := _find_line_flow()
	if lf == null:
		return {}
	# Per-unit telemetry, keyed by real plant code (only 3C-macro machines
	# carry codes; others simply don't appear — their design boxes stay as-is).
	var estop_key := ""
	if lf.has_method("estop_fault_key"):
		estop_key = String(lf.call("estop_fault_key"))
	var units := {}
	for row_v in lf.call("machine_list"):
		var row : Dictionary = row_v
		var code := String(row.get("l3c_code", ""))
		if code == "":
			continue
		var info : Dictionary = lf.call("get_machine_info", String(row.get("key", "")))
		units[code] = {
			"amps": float(info.get("amps", 0.0)),
			"on": bool(info.get("powered", false)),
			"fault": estop_key != "" and String(row.get("key", "")) == estop_key,
		}
	# Header pills — same Fault > Starting > Running > Idle derivation TagMap's
	# linestatus row uses.
	var line_pill : Dictionary
	if bool(lf.call("is_estopped")):
		line_pill = {"text": "Storing", "bg": _RED}
	elif bool(lf.call("is_line_starting")):
		line_pill = {"text": "Start", "bg": _AMBER}
	elif float(lf.call("line_powered_fraction")) > 0.05:
		line_pill = {"text": "Auto", "bg": _GREEN}
	else:
		line_pill = {"text": "Uit", "bg": _GREY}
	# "Status was" = any wash-section unit powered (everything except the
	# doseersilo L3C.1 and extruder silo L3C.18); "Status Silo" = L3C.18.
	var wash_on := false
	for code in units:
		if code != "L3C.1" and code != "L3C.18" and bool(units[code]["on"]):
			wash_on = true
			break
	var silo_on : bool = bool(units.get("L3C.18", {}).get("on", false))
	var pills := {
		"Status Lijn 3C": line_pill,
		"Status was": {"text": "Aan" if wash_on else "Uit", "bg": _GREEN if wash_on else _GREY},
		"Status Silo": {"text": "Aan" if silo_on else "Uit", "bg": _GREEN if silo_on else _GREY},
	}
	return {
		"type": "vals",
		"screen": _current_screen,
		"pills": pills,
		"units": units,
		"alarm": _top_alarm(),
		"clock": _clock_lines(),
	}

## The two header clock lines. The designs ship a frozen Gregorian date+time
## (e.g. "zaterdag 10 augustus 2024 / 18:00:30"); a screen standing in the plant
## must show the PLANT's time, not the player's PC clock (which is what the
## page's own fallback Date() gives — measured 03:22 real-time on a 07:00 shift).
## The sim has no Gregorian calendar, it has a rota: ShiftClock.calendar_string()
## is exactly what the HUD shows ("Dag 1 · Vroege dienst · Ploeg A"), so that
## takes the date line and the wall clock takes the time line — seconds included,
## since the design's format has them.
func _clock_lines() -> Dictionary:
	var sc := _find_shift_clock()
	if sc == null:
		return {}
	var hhmm := String(sc.call("get_time_string"))          # "HH:MM"
	var secs := int(absf(float(sc.get("shift_elapsed_seconds")))) % 60
	return {
		"date": String(sc.call("calendar_string")),
		"time": "%s:%02d" % [hhmm, secs],
	}

## Locate the ShiftClock. current_scene FIRST (the normal game path), then the
## whole tree — a harness that add_child()s MainWorld without assigning
## current_scene would otherwise silently find nothing, and the page would fall
## back to the player's PC clock with no error anywhere. That is exactly what
## happened on the first in-game verification of this feature (2026-08-10):
## the screen showed real wall-clock time and looked plausible.
func _find_shift_clock() -> Node:
	if _shift_clock != null and is_instance_valid(_shift_clock):
		return _shift_clock
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene != null:
		_shift_clock = scene.find_child("ShiftClock", true, false)
	if _shift_clock == null and tree.root != null:
		_shift_clock = tree.root.find_child("ShiftClock", true, false)
	return _shift_clock

## Highest-severity active storing from the plant-wide registry, or null.
func _top_alarm() -> Variant:
	var board := get_node_or_null("/root/NpcAutonomyBoard")
	if board == null or not board.has_method("storing_list"):
		return null
	var best : Dictionary = {}
	for e_v in board.call("storing_list"):
		var e : Dictionary = e_v
		if best.is_empty() or int(e.get("severity", 1)) > int(best.get("severity", 1)):
			best = e
	if best.is_empty():
		return null
	return {
		"nr": String(best.get("alarm_id", "")),
		"text": "%s — %s" % [String(best.get("machine_id", "")), String(best.get("alarm_id", ""))],
	}
