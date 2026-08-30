extends Node3D

## =============================================================================
## LINE-1 MATERIAL-FLOW TEST WORLD
## =============================================================================
## Operator request 2026-08-29, near-verbatim:
##
##   "Build a separate test world in the simulator where you just have a flat
##    floor, it doesn't matter. Then spawn line 1 — just call line 1. And then
##    after fifteen seconds, drop a Rotterdam bale on the feed conveyor. And
##    then just let it run until I close it. I have to be able to walk around
##    and stop normally, and I can see the material here and there going such
##    and such, including the extruder and stuff of course."
##
## Launch:
##   Godot_v4.6.3-stable_win64_console.exe --path . res://src/scenes/world/Line1FlowTestWorld.tscn
##
## What this scene is:
##   * flat ground + collision, sun + procedural sky
##   * a first-person player (same wiring as SandboxWorld._build_player,
##     including the head/body render-layer split so he can look down)
##   * line_1 built through the REAL BuildMode._build_full_line — real legs,
##     real turns, real branches, real LineFlow edges. NOT SandboxWorld's
##     simplified _spawn_macro_at (which stamps no macro meta, handles no
##     turn_deg/at_entry/parallel_branch, and has no LineFlow at all).
##   * a live LineFlow that ticks ITSELF every frame (LineFlow._process ->
##     tick(delta), LineFlow.gd:2086-2087) — this scene must NOT call tick()
##     or the whole sim runs at 2x.
##   * ONE Rotterdam bale placed on the real head feed point at T+15 s via the
##     production path (build_node -> _head_feed_point -> "delivered" meta),
##     the same sequence src/tests/probe_single_bale_line1.gd proved.
##   * an always-on left-hand HUD panel with the live mass ledger, because a
##     large part of the material on this line is a numeric ledger, not a mesh.
##
## RUNS FOREVER. There is deliberately no get_tree().quit() and no timer that
## ends the session — ESC opens the HUD pause menu (which frees the mouse) and
## the window close button ends it. For a headless check, wrap the launch in an
## external timeout; --quit-after counts FRAMES, not seconds.
## =============================================================================

const BM = preload("res://src/build/BuildMode.gd")
const PlaceableCatalogScript = preload("res://src/build/PlaceableCatalog.gd")

const LINE_ID      : String  = "line_1"
## Vector3.ZERO keeps us 149 m clear of the nearest WorldLayout.line_starts
## marker (line 1 -> (-142.70, 0, 42.92)). LineFlow._head_feed_point snaps the
## feed point to any marker within LINE_START_MARKER_RADIUS (25 m); building
## near the real plant coordinates would silently teleport the feed point up to
## 25 m away from where this scene parks the bale, and feeding would stop with
## no message at all.
const LINE_ORIGIN  : Vector3 = Vector3.ZERO
const LINE_ROT_Y   : float   = 0.0
const BALE_DELAY_S : float   = 15.0
const BALE_ID      : String  = "rotterdam"
## line_1's intake. _tick_feed feeds EVERY node with role != "sink" and no
## incoming edge — on the macro-built line that is FOURTEEN nodes, not one — so
## the head is matched by id rather than by "first source in _discover order".
const INTAKE_ID    : String  = "opzetband_1"

const HUD_REFRESH_S : float = 0.25
const LOG_EVERY_S   : float = 5.0

var _player : CharacterBody3D = null
var _bm     : BuildMode   = null
var _lf     : LineFlow    = null
var _hud    : CanvasLayer = null
var _scada  : Node        = null

var _panel_label : RichTextLabel = null
var _hint_label  : Label = null

var _line_ready   : bool  = false
var _elapsed      : float = 0.0
var _bale_dropped : bool  = false
var _bale         : Node3D = null
var _bale_full_kg : float = 0.0
var _bale_gone_at : float = -1.0
var _hud_accum    : float = 0.0
var _log_accum    : float = 0.0
var _machines     : int = 0
var _links        : int = 0
var _rotors       : Array = []      # cached RotatingMechanism list, for the "turning" readout

# =============================================================================
func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_player()
	_build_hud()
	_build_panel()
	# Deferred, not awaited inside _ready(): BuildMode raycasts against the
	# player capsule and LineFlow scans the "placed_object" group, so both need
	# every _ready() in this scene to have finished first.
	call_deferred("_boot_line")

# =============================================================================
# LINE BOOT — the ordering here is load-bearing. Each step's comment records
# the measured failure mode of getting it wrong.
# =============================================================================
func _boot_line() -> void:
	# ── 1. BuildMode ────────────────────────────────────────────────────────
	# MUST be in the tree and have run _ready() before _build_full_line:
	# BuildMode._ready() (BuildMode.gd:844-846) creates `_placed_root`, and
	# _build_full_line writes into it at BuildMode.gd:2293. On a detached
	# BuildMode you get one "Cannot call method 'add_child' on a null value"
	# and a 0-machine world that otherwise boots normally.
	_bm = BM.new()
	_bm.name = "BuildMode"
	_bm.player_body = _player                                # placement rays skip the capsule
	_bm.wall_openings = null                                 # no building shell in this world
	_bm.layout_path = "user://line1_flowtest_factory.json"   # scratch — never a real save
	_bm.allow_legacy_fallback = false                        # never migrate user://factory_layout.json in
	# load_shared_structure defaults TRUE and would spawn WorldLayout's "3A/3B
	# gate" slab ~290 m away and 6 m below this flat ground — and, if anything
	# ever routed through _save_layout, would write WorldLayout.structure_items
	# back from a bench (the footgun BuildMode.gd:3502-3504 warns about).
	_bm.load_shared_structure = false
	add_child(_bm)
	await get_tree().process_frame                           # _ready() -> _placed_root exists

	var t0 := Time.get_ticks_msec()
	_bm.call("_build_full_line", LINE_ID, LINE_ORIGIN, LINE_ROT_Y)
	var build_ms := Time.get_ticks_msec() - t0
	await get_tree().process_frame

	# ── 2. LineFlow ─────────────────────────────────────────────────────────
	# LineFlow._ready() calls rebuild() itself, so adding it AFTER the macro is
	# built IS the "rebuild once the machines exist" step — no second rebuild()
	# call. Deliberately not calling one: rebuild #1 spawns compressor_a and
	# compressor_b as siblings under this world (LineFlow.gd:881-921) at
	# player_spawn + (20,0,20) = (-182.66, 0, 114.04), 214 m from the line, and
	# a second rebuild drags that stray pair into the material graph as an
	# isolated 2-node island (measured 50/51 -> 52/53) which then dilutes
	# line_powered_fraction(). Also: never rebuild() AFTER start_line(), which
	# constructs a fresh idle PLCSequencer and silently abandons the ramp.
	_lf = LineFlow.new()
	_lf.name = "LineFlow"
	add_child(_lf)
	if not _lf.is_in_group("line_flow"):
		_lf.add_to_group("line_flow")
	_machines = (_lf.get("_nodes") as Array).size()
	_links    = (_lf.get("_edges") as Array).size()
	await get_tree().process_frame

	# ── 3. ISA-101 SCADA dashboard (the same two-line wiring MainWorld uses at
	#     MainWorld.gd:195-206). LineFlow._push_scada feeds it line state, amps,
	#     granulaat quality, melt temp, MFI and air pressure at ~6 Hz, and logs
	#     micro-stops. It is always visible; no key toggles it.
	var scada_script := load("res://src/scenes/hud/ScadaDashboard.gd")
	if scada_script != null:
		_scada = scada_script.new()
		_scada.name = "ScadaDashboard"
		_scada.add_to_group("scada_dashboard")   # ExtruderMachine finds it by group
		add_child(_scada)
		if _lf.has_method("set_scada"):
			_lf.set_scada(_scada)

	# ── 4. Start the line ───────────────────────────────────────────────────
	# MANDATORY. LineFlow.auto_start defaults FALSE (LineFlow.gd:186), so
	# without this the PLC never powers a single stage. _tick_feed does NOT
	# check `powered`, so the bale still visibly depletes for ~30 s while the
	# head buffer fills, then the line hits OVERLOAD_KG (250 kg) and E-STOPs
	# with feed_enabled latched false. Measured: "powered=0% ... E-STOP:
	# overload at 'opzetband_1'".
	_lf.start_line()
	if _hud != null:
		_hud.set("line_flow", _lf)   # HUD.gd:137 only sets this from MainWorld
	_cache_rotors()
	_line_ready = true

	# ── Boot banner (stdout, so a headless run is verifiable) ───────────────
	print("")
	print("=============================================================")
	print("  LINE-1 MATERIAL-FLOW TEST WORLD")
	print("=============================================================")
	print("  line macro          : %s built at %s in %d ms" % [LINE_ID, str(LINE_ORIGIN), build_ms])
	print("  LineFlow graph      : %d machines / %d links" % [_machines, _links])
	print("  rotors under LineFlow: %d (set_running cascade)" % _rotors.size())
	print("  PLC                 : started (auto_start is false; start_line() called)")
	print("  bale                : 1x %s drops on '%s' feed point at T+%.0f s"
		% [BALE_ID, INTAKE_ID, BALE_DELAY_S])
	print("  duration            : INDEFINITE — no quit timer. ESC = pause/free mouse.")
	print("=============================================================")
	print("")

# =============================================================================
# PER-FRAME: bale drop + HUD refresh. LineFlow ticks ITSELF (LineFlow._process
# -> tick(delta)); calling tick() from here would double-tick the entire sim.
# =============================================================================
func _process(delta: float) -> void:
	if not _line_ready:
		return
	_elapsed += delta

	if not _bale_dropped and _elapsed >= BALE_DELAY_S:
		_bale_dropped = true
		_drop_bale()
	if _bale_dropped and _bale_gone_at < 0.0 \
			and (_bale == null or not is_instance_valid(_bale) or _bale.is_queued_for_deletion()):
		_bale_gone_at = _elapsed
		print("[L1FLOW] t=%.1fs — bale fully consumed" % _bale_gone_at)

	_hud_accum += delta
	if _hud_accum >= HUD_REFRESH_S:
		_hud_accum = 0.0
		_refresh_panel()

	_log_accum += delta
	if _log_accum >= LOG_EVERY_S:
		_log_accum = 0.0
		_log_state()

# =============================================================================
# BALE DROP — production path, mirroring src/tests/probe_single_bale_line1.gd
# =============================================================================
func _drop_bale() -> void:
	var head := _find_feed_head()
	if head == null:
		push_error("[L1FLOW] no source head on %s — nothing to feed" % LINE_ID)
		return
	var feed_point : Vector3 = _lf.call("_head_feed_point", head)
	var bale : Node3D = PlaceableCatalogScript.build_node(BALE_ID, false)
	if bale == null:
		push_error("[L1FLOW] catalog would not build a '%s' bale" % BALE_ID)
		return
	add_child(bale)
	bale.global_position = feed_point
	# PRODUCTION GATE — LineFlow._bale_at (LineFlow.gd:2900) only draws from
	# bales a vehicle has DELIVERED. Omitting this meta is a totally silent
	# no-op: no error, no warning, the line runs at 100 % power and fed_mass
	# stays 0.0 forever. Measured.
	#
	# The bale is left FROZEN (PlaceableCatalog.gd:1440-1441 spawns bales with
	# freeze = true / FREEZE_MODE_KINEMATIC). Unfreezing it to make it "fall"
	# risks it rolling outside FEED_RADIUS (5 m), after which _bale_at returns
	# null and feeding stops silently.
	bale.set_meta("delivered", true)
	_bale = bale

	_bale_full_kg = float(bale.get_meta("weight_kg", 0))
	if _bale_full_kg <= 0.0 and bale.has_meta("material_origin"):
		var item := PlaceableCatalogScript.get_item(String(bale.get_meta("material_origin")))
		_bale_full_kg = BaleDefs.estimated_weight(item.get("size", Vector3.ONE))

	# head.name is the catalog body's auto-generated node name (@Node3D@421);
	# report the LineFlow id the feed actually keys off instead.
	print("[L1FLOW] t=%.1fs — DROPPED 1x %s bale (%.1f kg) on head '%s' feed point %s"
		% [_elapsed, BALE_ID, _bale_full_kg, INTAKE_ID, str(feed_point)])

## The node LineFlow itself will draw from: role != "sink" and no incoming edge.
##
## MEASURED 2026-08-29: macro-built line_1 has FOURTEEN such heads (opzetband_1,
## shredder_1, sga_feed_chute, mech_dryer, 2x cyclone, blower, cyclone,
## kufferath_sieve, blower, extruder_silo, extruder_1, lump_platform,
## lump_cart_spot). "First node with no incoming edge" only lands on the intake
## because _discover() walks the placed_object group in placement order — match
## by id so a stray earlier placement can never redirect the bale into the
## middle of the line.
func _find_feed_head() -> Node3D:
	var nodes : Array = _lf.get("_nodes")
	var edges : Array = _lf.get("_edges")
	var has_incoming : Dictionary = {}
	for e in edges:
		has_incoming[int((e as Dictionary)["b"])] = true
	var fallback : Node3D = null
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		if String(nd.get("role", "")) == "sink" or has_incoming.has(i):
			continue
		var n3d = nd.get("node")
		if n3d == null or not is_instance_valid(n3d):
			continue
		if String(nd.get("id", "")) == INTAKE_ID:
			return n3d as Node3D
		if fallback == null:
			fallback = n3d as Node3D
	if fallback != null:
		push_warning("[L1FLOW] '%s' is not a LineFlow head — falling back to the first source node"
			% INTAKE_ID)
	return fallback

# =============================================================================
# HUD PANEL — every number below is read from a LineFlow member or method that
# exists; nothing here is derived or invented.
#   vars    : fed_mass, gran_mass, waste_mass, water_added, water_removed,
#             contam_removed, poly_rejected, feed_enabled
#   methods : line_powered_fraction(), in_transit_mass(), pipe_mass(),
#             live_line_amps(), granulaat_quality(), ledger_residual(),
#             is_estopped(), estop_fault_id(), is_line_starting()
# =============================================================================
func _refresh_panel() -> void:
	if _panel_label == null or _lf == null:
		return

	var powered   : float = float(_lf.call("line_powered_fraction"))
	var fed       : float = float(_lf.get("fed_mass"))
	var gran      : float = float(_lf.get("gran_mass"))
	var gran_q    : float = float(_lf.call("granulaat_quality"))
	var waste     : float = float(_lf.get("waste_mass"))
	var dirt      : float = float(_lf.get("contam_removed"))
	var h2o_in    : float = float(_lf.get("water_added"))
	var h2o_out   : float = float(_lf.get("water_removed"))
	var reject    : float = float(_lf.get("poly_rejected"))
	var transit   : float = float(_lf.call("in_transit_mass"))
	var pipes     : float = float(_lf.call("pipe_mass"))
	var amps      : float = float(_lf.call("live_line_amps"))
	var residual  : float = float(_lf.call("ledger_residual"))
	var feed_on   : bool  = bool(_lf.get("feed_enabled"))
	var estopped  : bool  = bool(_lf.call("is_estopped"))
	var estop_id  : String = String(_lf.call("estop_fault_id"))
	var starting  : bool  = bool(_lf.call("is_line_starting"))

	var s := "[b]LINE 1 — MATERIAL FLOW TEST[/b]\n"
	s += "t = %.1f s\n" % _elapsed

	# ── bale line: countdown, then confirmation, then depletion ────────────
	if not _bale_dropped:
		s += "[color=#ffd24a]bale drop in %.1f s[/color]\n" % maxf(0.0, BALE_DELAY_S - _elapsed)
	elif _bale != null and is_instance_valid(_bale) and not _bale.is_queued_for_deletion():
		var left : float = _bale_full_kg
		if _bale.has_meta("remaining_kg"):
			left = float(_bale.get_meta("remaining_kg"))
		s += "[color=#8ce07a]BALE DROPPED[/color] %s %.0f kg — %.1f kg left\n" \
			% [BALE_ID, _bale_full_kg, left]
	else:
		s += "[color=#8ce07a]BALE DROPPED[/color] %s %.0f kg — consumed at t=%.1f s\n" \
			% [BALE_ID, _bale_full_kg, _bale_gone_at]

	# ── line state ─────────────────────────────────────────────────────────
	var state_txt := "RUNNING"
	if estopped:
		state_txt = "[color=#ff6b5e]E-STOP[/color]"
	elif starting:
		state_txt = "[color=#ffd24a]STARTING[/color]"
	s += "\n[b]LINE[/b]  %s   %d%% powered   %.0f A\n" % [state_txt, int(round(powered * 100.0)), amps]
	s += "feed %s   graph %d machines / %d links\n" \
		% ["ON" if feed_on else "OFF", _machines, _links]
	if estop_id != "":
		s += "[color=#ff6b5e]tripped: %s[/color]\n" % estop_id
	var mol_trips := _tripped_motors()
	if not mol_trips.is_empty():
		s += "[color=#ff6b5e]motor overload: %s[/color]\n" % ", ".join(mol_trips)

	# ── mass ledger ────────────────────────────────────────────────────────
	s += "\n[b]MASS LEDGER (kg)[/b]\n"
	s += "fed onto line   %8.1f\n" % fed
	s += "process water   %8.1f\n" % h2o_in
	s += "granulaat       %8.1f  (q %.0f/100)\n" % [gran, gran_q]
	s += "waste           %8.1f\n" % waste
	s += "dirt removed    %8.1f\n" % dirt
	s += "water driven off%8.1f\n" % h2o_out
	s += "poly reject     %8.1f\n" % reject
	s += "[b]in transit    %8.1f[/b]  (pipes %.1f)\n" % [transit, pipes]
	s += "balance err     %8.3f\n" % residual

	# ── what is actually moving right now ──────────────────────────────────
	s += "\n[b]MOVING NOW (kg/s)[/b]\n"
	var moving := _moving_machines(8)
	if moving.is_empty():
		s += "  (nothing — line starved)\n"
	else:
		for m in moving:
			s += "  %-18s %5.2f\n" % [String(m["id"]), float(m["thru"])]

	# ── visible outputs ────────────────────────────────────────────────────
	var piles := _pile_totals()
	s += "\n[b]VISIBLE[/b]\n"
	s += "rotors turning  %d/%d\n" % [_turning_rotors(), _rotors.size()]
	s += "waste piles     %d  (%.0f kg on the floor)\n" % [int(piles["n"]), float(piles["kg"])]
	s += "flotation flakes%4d floating\n" % _visible_flakes()

	# ── extruder (its own clock — SimTick 10 Hz — and player-started with E) ─
	s += "\n[b]EXTRUDER 1[/b] "
	var xm := _extruder_machine()
	if xm == null:
		s += "no SimBrain found\n"
	else:
		var mdl = xm.get("model")
		if mdl == null:
			s += "brain present, model not built\n"
		else:
			s += "%s  melt %.0f C  screw %.0f rpm  %.0f kg/h\n" % [
				String(mdl.call("get_state_name")),
				float(mdl.get("melt_temp")),
				float(mdl.get("screw_rpm")),
				float(mdl.get("throughput_kg_h"))]
			s += "[color=#9fb6c8]walk up to it and press E to warm up / start[/color]\n"

	_panel_label.text = s

## Machines with live throughput, biggest first. `thru` is written every tick by
## LineFlow's route step; this is the only honest "material is moving HERE" readout.
func _moving_machines(limit: int) -> Array:
	var out : Array = []
	for nd in (_lf.get("_nodes") as Array):
		var thru : float = float((nd as Dictionary).get("thru", 0.0))
		if thru > 0.001:
			out.append({"id": String((nd as Dictionary).get("id", "?")), "thru": thru})
	out.sort_custom(func(a, b): return float(a["thru"]) > float(b["thru"]))
	return out.slice(0, limit)

func _tripped_motors() -> Array:
	var out : Array = []
	for nd in (_lf.get("_nodes") as Array):
		var mol = (nd as Dictionary).get("mol")
		if mol != null and is_instance_valid(mol) and mol.has_method("is_tripped") \
				and bool(mol.call("is_tripped")):
			out.append(String((nd as Dictionary).get("id", "?")))
	return out

## Snapshot the rotor list once, from the SAME arrays LineFlow drives
## (nd["mechs"], filled by _find_mechanisms during _discover). Rebuilt lazily if
## a node's list was empty at boot.
func _cache_rotors() -> void:
	_rotors.clear()
	for nd in (_lf.get("_nodes") as Array):
		for m in ((nd as Dictionary).get("mechs", []) as Array):
			if m != null and is_instance_valid(m) and m.has_method("current_rpm"):
				_rotors.append(m)

func _turning_rotors() -> int:
	var n := 0
	for m in _rotors:
		if m != null and is_instance_valid(m) and float(m.call("current_rpm")) > 0.1:
			n += 1
	return n

## The ExtruderMachine brain MachineBrains.attach() parented under the placed
## extruder_1 body (PlaceableCatalog.gd:1645). It joins group "extruder_machine"
## in its own _ready (ExtruderMachine.gd:58).
func _extruder_machine() -> Node:
	var list := get_tree().get_nodes_in_group("extruder_machine")
	return list[0] if not list.is_empty() else null

func _log_state() -> void:
	var powered : float  = float(_lf.call("line_powered_fraction"))
	var fed     : float  = float(_lf.get("fed_mass"))
	var gran    : float  = float(_lf.get("gran_mass"))
	var waste   : float  = float(_lf.get("waste_mass"))
	var transit : float  = float(_lf.call("in_transit_mass"))
	var estop   : String = String(_lf.call("estop_fault_id"))
	var feed_on : bool   = bool(_lf.get("feed_enabled"))
	var moving  : int    = _moving_machines(9999).size()
	var left    : float  = -1.0
	if _bale != null and is_instance_valid(_bale) and _bale.has_meta("remaining_kg"):
		left = float(_bale.get_meta("remaining_kg"))
	var piles := _pile_totals()
	print("[L1FLOW] t=%6.1fs pwr=%3.0f%% feed=%s fed=%8.1f gran=%6.1f waste=%7.1f transit=%8.1f moving=%2d rotors=%2d/%d flakes=%3d piles=%d/%.0fkg bale_left=%7.1f estop='%s'"
		% [_elapsed, powered * 100.0, ("on" if feed_on else "off"), fed, gran, waste,
		   transit, moving, _turning_rotors(), _rotors.size(), _visible_flakes(),
		   int(piles["n"]), float(piles["kg"]), left, estop])

## Live LDPE flakes drawn on the flotation tank's raft (FilmFlakeField, group
## "film_field", MultiMesh). LineFlow drives it via nd["view"].set_live_state()
## at LineFlow.gd:2230-2235 — this readout is the honest check that the drive is
## actually reaching the visual, not just that the node exists.
func _visible_flakes() -> int:
	var n := 0
	for f in get_tree().get_nodes_in_group("film_field"):
		if f != null and is_instance_valid(f) and f.has_method("visible_count"):
			n += int(f.call("visible_count"))
	return n

## Visible floor-waste cones (FloorPile, group "floor_pile"). mass_kg is a VAR,
## not a method — src/tests/probe_single_bale_line1.gd:174 reads it with
## has_method() and therefore always reports 0.0 kg per pile. Read the property.
func _pile_totals() -> Dictionary:
	var n := 0
	var kg := 0.0
	for p in get_tree().get_nodes_in_group("floor_pile"):
		var pn := p as Node3D
		if pn == null:
			continue
		n += 1
		if "mass_kg" in pn:
			kg += float(pn.get("mass_kg"))
	return {"n": n, "kg": kg}

# =============================================================================
# WORLD DRESSING
# =============================================================================
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.62, 0.88)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.92)
	sky_mat.ground_horizon_color = Color(0.55, 0.60, 0.55)
	sky_mat.ground_bottom_color = Color(0.30, 0.35, 0.28)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(800.0, 800.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.34, 0.33)   # plant-floor grey, not grass
	mat.roughness = 0.96
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(800.0, 0.2, 800.0)
	col.shape = sh
	col.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(col)
	add_child(body)

## Same wiring as SandboxWorld._build_player: capsule + Head/Camera3D with
## layer 3 culled, plus a visible Humanoid body split head-from-body by summed
## local Y so the operator can look down and see himself.
func _build_player() -> void:
	var script := load("res://src/scenes/player/PlayerController.gd")
	if script == null:
		push_error("[L1FLOW] PlayerController.gd missing — no player")
		return
	var p : CharacterBody3D = script.new()
	p.name = "Player"
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.7, 0.0)
	p.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.cull_mask &= ~(1 << 2)     # #200 — hide the player's own head from the FP camera
	head.add_child(cam)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	p.add_child(col)
	add_child(p)
	# The macro marches along -Z from LINE_ORIGIN at rot_y 0, and opzetband_1's
	# centre lands at z = -5. Standing at (+6, 1, +10) puts the operator ~10 m
	# in front of the intake, off to one side, with the whole 155 m train ahead.
	p.global_position = LINE_ORIGIN + Vector3(6.0, 1.0, 10.0)
	var humanoid_script = load("res://src/scenes/world/Humanoid.gd")
	if humanoid_script:
		var body : Node3D = humanoid_script.build(Color(0.96, 0.45, 0.12), 0, {})
		body.name = "PlayerBody"
		p.add_child(body)
		_tag_body_layers(body)
	_player = p

## Head-vs-body render-layer split by summed local Y (SandboxWorld's rule, NOT
## MainWorld's ancestor-name rule). Valid AT REST ONLY — called here before any
## AnimationTree poses the skeleton.
func _tag_body_layers(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var y_local : float = mi.position.y
		var par : Node = mi.get_parent()
		while par != null and (not (par is Node3D) or par.name != "PlayerBody"):
			if par is Node3D:
				y_local += (par as Node3D).position.y
			par = par.get_parent()
		mi.layers = (1 << 2) if y_local >= 0.55 else (1 << 1)
	for c in root.get_children():
		_tag_body_layers(c)

## The real game HUD — crosshair, interaction prompts, and critically the ESC
## pause menu that releases the mouse. PlayerController._ready() captures the
## mouse and deliberately does not handle ui_cancel (PlayerController.gd:1069,
## "ESC is owned by HUD.gd"), so without this the operator would be stuck with a
## captured cursor. HUD.gd:133 resolves main_world as `current_scene as
## MainWorld`, gets null here, and prints its "no MainWorld" line rather than
## warning; its Save & Quit falls through to the main menu, never
## get_tree().quit().
func _build_hud() -> void:
	var hud_scene := load("res://src/scenes/hud/HUD.tscn") as PackedScene
	if hud_scene == null:
		push_warning("[L1FLOW] HUD.tscn missing — ESC will not free the mouse")
		return
	_hud = hud_scene.instantiate() as CanvasLayer
	add_child(_hud)

## Left-hand live-state panel. LineFlow builds its own mass-ledger label on
## CanvasLayer 38 at the top-right (LineFlow.gd:259-276) — this one is deliberately
## on the left so the two do not overlap, and carries the test-world state
## (elapsed / bale countdown / what is moving) that LineFlow does not know about.
func _build_panel() -> void:
	var cl := CanvasLayer.new()
	cl.name = "L1FlowPanel"
	cl.layer = 12
	add_child(cl)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 372
	panel.offset_bottom = 660
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.08, 0.82)
	sb.border_color = Color(0.30, 0.34, 0.38, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	cl.add_child(panel)

	_panel_label = RichTextLabel.new()
	_panel_label.bbcode_enabled = true
	_panel_label.fit_content = true
	_panel_label.scroll_active = false
	_panel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_label.add_theme_font_size_override("normal_font_size", 13)
	_panel_label.add_theme_font_size_override("bold_font_size", 13)
	_panel_label.add_theme_font_override("normal_font", ThemeDB.fallback_font)
	_panel_label.text = "[b]LINE 1 — MATERIAL FLOW TEST[/b]\nbuilding line_1 …"
	panel.add_child(_panel_label)

	# Bottom hint strip.
	var hint_panel := PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_panel.offset_left = -430
	hint_panel.offset_right = 430
	hint_panel.offset_top = -52
	hint_panel.offset_bottom = -18
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_theme_stylebox_override("panel", sb.duplicate())
	cl.add_child(hint_panel)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.text = "WASD walk · mouse look · E interact (extruder / HMI) · Tab build · ESC pause & free mouse · runs until you close it"
	hint_panel.add_child(_hint_label)
