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

# Persistent setpoints registry across screens & channels.
# Defaults seeded with captured real plant operational values.
var _setpoints : Dictionary = {
	# EREMA Extruder channels (Plant photo capture)
	"schuif": 100.0,
	"ex_belasting": 100.0,
	"extr_rpm": 120.0,
	"sv_temperatuur": 105.0,
	"ez_1": 115.0,
	"zz_1": 160.0,
	"zz_2": 185.0,
	"zz_3": 215.0,
	"sv_vulpeil": 45.0,
	"afzuiging_1": 55.0,
	"afzuiging_2": 0.0,
	"sv_belasting": 60.0,
	"sv_vermogen": 190.0,
	# Line 3C Siemens Motors & Timers (FORM-008 & Plant capture)
	"starttijd": 5.0,
	"stoptijd": 60.0,
	"leegdraaitijd": 30.0,
	"loopbewaking": 9000.0,
	"frequentie": 35.0,
	"schroef_1_frequentie": 50.0,
	"schroef_2_frequentie": 50.0,
	"schroef_3_frequentie": 50.0,
	"maalmolen_frequentie": 50.0,
	"doseersluis_frequentie": 45.0,
	"snelheid": 50.0,
	# Sorteerlijn Bunker Setpoints
	"bunkersnelheid": 220.0,
	"speed_autom": 100.0,
	"filling_setpoint": 258.0,
	"conveyor_speed": 125.0,
	# Shredder & Water Circuit
	"vulpeil": 56.0,
	"toevoer_stop": 8.0,
	"toevoer_start": 7.0,
	"druk": 2750.0,
	"flow": 800.0,
	"niveau": 1380.0,
}

# Live simulated actual values (drift / ramp toward setpoints)
var _actuals : Dictionary = {
	"schuif": 100.0,
	"ex_belasting": 102.0,
	"extr_rpm": 120.0,
	"sv_temperatuur": 108.0,
	"ez_1": 113.0,
	"zz_1": 157.0,
	"zz_2": 184.0,
	"zz_3": 213.0,
	"sv_vulpeil": 45.0,
	"afzuiging_1": 55.0,
	"afzuiging_2": 0.0,
	"sv_belasting": 61.0,
	"sv_vermogen": 193.0,
	"starttijd": 5.0,
	"stoptijd": 60.0,
	"leegdraaitijd": 30.0,
	"loopbewaking": 9000.0,
	"frequentie": 35.0,
	"schroef_1_frequentie": 50.0,
	"schroef_2_frequentie": 50.0,
	"schroef_3_frequentie": 50.0,
	"bunkersnelheid": 219.0,
	"vulpeil": 56.0,
	"druk": 2218.0,
	"flow": 804.2,
	"niveau": 1379.0,
}

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
func open_for(label: String, scope: Dictionary) -> void:
	_scope = scope
	var start := String(scope.get("web_screen", INDEX_FILE))
	print("[HmiWebOverlay] open_for: label='%s' screen='%s'" % [label, start])
	_ensure_webview()
	visible = true
	if _web != null and is_instance_valid(_web):
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
		# Diagnostic probe. Was eval()-injecting an ad-hoc JS string into the
		# page — bypasses whatever CSP the page sets, and was the one caller
		# in this file not using the post_message channel every other Godot->
		# shell message already goes through. The probe logic itself now
		# lives in hmi_shell.html as a declared script (its own "message"
		# listener, type "diag_probe") and replies the same {type:'probe',...}
		# shape over ipc, so _on_ipc below needed no change. If this arrives
		# but "ready" never did, the page's own <script> was blocked; if this
		# never arrives either, the ipc channel itself is broken.
		_web.call("post_message", JSON.stringify({"type": "diag_probe"})))
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
		"set_setpoint":
			var ch := String(d.get("channel", "")).strip_edges().to_lower()
			var val := float(d.get("value", 0.0))
			var scr := String(d.get("screen", ""))
			var u := String(d.get("unit", ""))
			_apply_setpoint(scr, ch, val, u)
			_push_vals()
		"event":
			var btn_name := String(d.get("name", "")).to_lower().strip_edges()
			
			if btn_name == "aan" or btn_name == "start" or btn_name == "⚡":
				var lf := _find_line_flow()
				if lf and lf.has_method("start_line"):
					lf.call("start_line")
					print("[HmiWebOverlay] Line started via HMI button.")
				var tree := get_tree()
				if tree:
					for belt in tree.get_nodes_in_group("shredder_feed_belt"):
						if belt.has_method("request_start"):
							belt.call("request_start")
			elif btn_name == "uit" or btn_name == "stop" or btn_name == "stop runtime":
				var lf := _find_line_flow()
				if lf and lf.has_method("stop_line"):
					lf.call("stop_line")
					print("[HmiWebOverlay] Line stopped via HMI button.")
				var tree := get_tree()
				if tree:
					for belt in tree.get_nodes_in_group("shredder_feed_belt"):
						if belt.has_method("request_stop"):
							belt.call("request_stop")
			elif btn_name == "reset":
				var lf := _find_line_flow()
				if lf and lf.has_method("clear_estop"):
					lf.call("clear_estop")
				var tree := get_tree()
				if tree:
					for belt in tree.get_nodes_in_group("shredder_feed_belt"):
						if belt.has_method("reset_faults"):
							belt.call("reset_faults")
				print("[HmiWebOverlay] Faults reset via HMI button.")
			elif btn_name == "⌂" or btn_name == "home" or btn_name == "index" \
					or btn_name == "start scherm" or btn_name == "f1" or btn_name == "logout":
				_send_screen(INDEX_FILE)
			elif btn_name == "overzicht" or btn_name == "▤" or btn_name == "📋" or btn_name == "f2":
				_send_screen("Waslijn 3C Overzicht.dc.html")
			elif btn_name == "⚠" or btn_name == "alarm" or btn_name == "storing" or btn_name == "f3":
				_send_screen("Waslijn 3C Storingen.dc.html")
			elif btn_name == "◀" or btn_name == "‹" or btn_name == "«" or btn_name == "<" \
					or btn_name == "prev" or btn_name == "vorige" or btn_name == "f4" or btn_name == "f5":
				_send_screen(_nav_target("prev"))
			elif btn_name == "▶" or btn_name == "›" or btn_name == "»" or btn_name == ">" \
					or btn_name == "next" or btn_name == "volgende" or btn_name == "f6":
				_send_screen(_nav_target("next"))
			elif btn_name == "f7" or btn_name == "trend":
				_send_screen("Waslijn 3C Stroom Trend.dc.html")
			elif btn_name == "f8" or btn_name == "water":
				_send_screen("Water Circuit Lijn 3C-6.dc.html")
			elif btn_name == "f9" or btn_name == "extruder":
				_send_screen("EREMA Extruder Scherm 3C.dc.html")
			elif btn_name == "f10" or btn_name == "bluport":
				_send_screen("BluPort Overzicht Lijn 3C.dc.html")
			elif btn_name == "clean screen" or btn_name == "clean\nscreen":
				print("[HmiWebOverlay] Clean screen acknowledged.")
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
	print("[HmiWebOverlay] _send_screen: '%s'" % file)
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
		"extruder": _gather_extruder_vals(),
		"screen_vals": _gather_screen_vals(),
		"alarm": _top_alarm(),
		"clock": _clock_lines(),
	}

func _find_extruder_model() -> ExtruderModel:
	var tree := get_tree()
	if tree != null:
		var machines := tree.get_nodes_in_group("extruder_machine")
		for em in machines:
			if em != null and is_instance_valid(em):
				var m = em.get("model")
				if m == null and em.has_meta("model"):
					m = em.get_meta("model")
				if m != null:
					return m as ExtruderModel
	return null

func _find_cutter_compactor() -> CutterCompactor:
	var lf := _find_line_flow()
	if lf != null and is_instance_valid(lf):
		if lf.has_method("get_first_cutter_compactor"):
			var c = lf.call("get_first_cutter_compactor")
			if c != null:
				return c as CutterCompactor
		var nodes = lf.get("_nodes")
		if nodes is Array:
			for nd in nodes:
				if nd is Dictionary and nd.get("cc") != null:
					return nd.get("cc") as CutterCompactor
	return null

func _apply_setpoint(scr: String, ch: String, val: float, u: String) -> void:
	_setpoints[ch] = val
	print("[HmiWebOverlay] setpoint changed: %s = %s (%s) on screen '%s'" % [ch, str(val), u, scr])
	
	var ex_model := _find_extruder_model()
	var cc := _find_cutter_compactor()
	
	if ch == "extr_rpm" or ch.ends_with("screw_rpm"):
		if ex_model != null and ex_model.has_method("set_screw_rpm_setpoint"):
			ex_model.set_screw_rpm_setpoint(val)
	elif ch == "sv_temperatuur" or ch.ends_with("pcu_temp") or ch.ends_with("pot_temp"):
		if cc != null and cc.has_method("set_target_temperature"):
			cc.set_target_temperature(val)
	elif ch == "sv_vermogen" or ch.ends_with("power_cap"):
		if cc != null and "power_cap_kw_setpoint" in cc:
			cc.power_cap_kw_setpoint = val
	elif ch == "schuif" or ch.ends_with("dosing_gate"):
		if cc != null and cc.has_method("set_dosing_gate"):
			cc.set_dosing_gate(val / 100.0 if val > 1.0 else val)
	elif ch == "afzuiging_1" or ch.ends_with("primary_suction"):
		if ex_model != null and ex_model.has_method("set_primary_suction"):
			ex_model.set_primary_suction(val / 100.0 if val > 1.0 else val)
	elif ch == "afzuiging_2" or ch.ends_with("secondary_suction"):
		if ex_model != null and ex_model.has_method("set_secondary_suction"):
			ex_model.set_secondary_suction(val / 100.0 if val > 1.0 else val)
	elif ch == "ez_1":
		if ex_model != null and ex_model.has_method("set_zone_temp"):
			ex_model.set_zone_temp(0, val)
	elif ch == "zz_1":
		if ex_model != null and ex_model.has_method("set_zone_temp"):
			ex_model.set_zone_temp(1, val)
	elif ch == "zz_2":
		if ex_model != null and ex_model.has_method("set_zone_temp"):
			ex_model.set_zone_temp(2, val)
	elif ch == "zz_3":
		if ex_model != null and ex_model.has_method("set_zone_temp"):
			ex_model.set_zone_temp(3, val)
			
	var lf := _find_line_flow()
	if lf != null and is_instance_valid(lf):
		if lf.has_method("set_machine_setpoint"):
			lf.call("set_machine_setpoint", ch, val)

func _gather_extruder_vals() -> Dictionary:
	var ex_model := _find_extruder_model()
	var cc := _find_cutter_compactor()
	
	if ex_model != null:
		_actuals["extr_rpm"] = ex_model.screw_rpm
		_actuals["ex_belasting"] = clampf(ex_model.motor_torque_pct, 0.0, 150.0)
		_actuals["afzuiging_1"] = ex_model.primary_suction_pct * 100.0
		_actuals["afzuiging_2"] = ex_model.secondary_suction_pct * 100.0
		_actuals["ez_1"] = ex_model.get_actual_zone_temp(0)
		_actuals["zz_1"] = ex_model.get_actual_zone_temp(1)
		_actuals["zz_2"] = ex_model.get_actual_zone_temp(2)
		_actuals["zz_3"] = ex_model.get_actual_zone_temp(3)
		_setpoints["extr_rpm"] = ex_model.screw_rpm_setpoint
		if ex_model.zone_temp_setpoints.size() >= 4:
			_setpoints["ez_1"] = ex_model.zone_temp_setpoints[0]
			_setpoints["zz_1"] = ex_model.zone_temp_setpoints[1]
			_setpoints["zz_2"] = ex_model.zone_temp_setpoints[2]
			_setpoints["zz_3"] = ex_model.zone_temp_setpoints[3]
	
	if cc != null:
		_actuals["sv_temperatuur"] = cc.pot_temperature
		_actuals["schuif"] = cc.dosing_gate * 100.0
		_actuals["sv_belasting"] = cc.get_pot_load_pct()
		_actuals["sv_vermogen"] = cc.power_kw
		_actuals["sv_vulpeil"] = cc.get_fill_level_cm()
		_setpoints["sv_temperatuur"] = cc.pot_temperature_setpoint
		_setpoints["sv_vermogen"] = cc.power_cap_kw_setpoint
		_setpoints["schuif"] = cc.dosing_gate * 100.0
	
	var units_map := {
		"schuif": "%",
		"ex_belasting": "%",
		"extr_rpm": "rpm",
		"sv_temperatuur": "°C",
		"ez_1": "°C",
		"zz_1": "°C",
		"zz_2": "°C",
		"zz_3": "°C",
		"sv_vulpeil": "cm",
		"afzuiging_1": "%",
		"afzuiging_2": "%",
		"sv_belasting": "%",
		"sv_vermogen": "kW",
	}
	
	# Physical cross-coupling when running simulated or standalone
	var lf := _find_line_flow()
	var estop_active := false
	if lf != null and is_instance_valid(lf) and lf.has_method("estop_fault_key"):
		estop_active = (String(lf.call("estop_fault_key")) != "")

	var gate_fraction := clampf(float(_setpoints.get("schuif", 100.0)) / 100.0, 0.0, 1.0)
	var target_load := 12.0 + gate_fraction * 50.0 # 12% idle to 62% full load
	var target_power := 25.0 + gate_fraction * 170.0 # 25 kW idle to 195 kW full power
	var target_rpm := float(_setpoints.get("extr_rpm", 120.0))
	var avg_temp : float = (float(_actuals.get("ez_1", 115.0)) + float(_actuals.get("zz_1", 160.0)) + float(_actuals.get("zz_2", 185.0)) + float(_actuals.get("zz_3", 215.0))) / 4.0
	var temp_shortfall := maxf(0.0, 170.0 - avg_temp)
	var target_ex_load := (target_rpm / 120.0) * 100.0 + temp_shortfall * 0.8
	
	if estop_active:
		target_load = 0.0
		target_power = 0.0
		target_ex_load = 0.0

	if cc == null:
		_actuals["sv_belasting"] = move_toward(float(_actuals.get("sv_belasting", 61.0)), target_load, 1.5)
		_actuals["sv_vermogen"] = move_toward(float(_actuals.get("sv_vermogen", 193.0)), target_power, 3.0)
	if ex_model == null:
		_actuals["ex_belasting"] = move_toward(float(_actuals.get("ex_belasting", 102.0)), target_ex_load, 2.0)

	var res : Dictionary = {}
	var t_msec := Time.get_ticks_msec()
	for k in units_map.keys():
		var target : float = float(_setpoints.get(k, 0.0))
		var cur : float = float(_actuals.get(k, target))
		if (ex_model == null and k in ["extr_rpm", "afzuiging_1", "afzuiging_2", "ez_1", "zz_1", "zz_2", "zz_3"]) or (cc == null and k in ["sv_temperatuur", "schuif", "sv_vulpeil"]):
			if estop_active and k in ["extr_rpm", "afzuiging_1", "afzuiging_2"]:
				cur = move_toward(cur, 0.0, 5.0)
			else:
				cur = move_toward(cur, target, 2.5)
			_actuals[k] = cur
		
		# Subtle realistic sensor jitter (~±0.25%) when machines are operational
		var jitter : float = 0.0
		if not estop_active and cur > 5.0 and k in ["ex_belasting", "sv_belasting", "sv_vermogen", "extr_rpm"]:
			jitter = sin(t_msec * 0.003 + float(k.hash() % 100)) * 0.35
			
		res[k] = {
			"actual": cur + jitter,
			"setpoint": target,
			"unit": units_map[k],
		}
	return res

func _gather_screen_vals() -> Dictionary:
	var res : Dictionary = {}
	var lf := _find_line_flow()
	var estop_active := false
	if lf != null and is_instance_valid(lf) and lf.has_method("estop_fault_key"):
		estop_active = (String(lf.call("estop_fault_key")) != "")

	var t_msec := Time.get_ticks_msec()
	for k in _setpoints.keys():
		var target : float = float(_setpoints[k])
		var cur : float = float(_actuals.get(k, target))
		
		# "unless there's a problem, of course":
		var is_motion_ch : bool = (k.ends_with("rpm") or k.ends_with("frequentie") or k.ends_with("belasting") or k.ends_with("amps") or k.ends_with("speed") or k.ends_with("stroom") or k.ends_with("vermogen"))
		if estop_active and is_motion_ch:
			cur = move_toward(cur, 0.0, 3.0)
		else:
			cur = move_toward(cur, target, 2.0)
			
		_actuals[k] = cur
		
		var jitter : float = 0.0
		if not estop_active and cur > 5.0:
			jitter = sin(t_msec * 0.0025 + float(k.hash() % 100)) * (cur * 0.002)

		res[k] = {
			"actual": cur + jitter,
			"setpoint": target,
		}
	return res

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
