extends Node3D
## Cost of in-world HMI screens — docs/DESIGN_inworld_hmi_2026-09-25.md §6 and
## §9 step 1. The operator wants each HMI's page drawn on the panel's own screen
## (docs/plant/operator_rulings_2026-09-25.md §H5); before anything is built,
## this measures what N SubViewport screens cost on this machine.
##
## WINDOWED ONLY. The dummy renderer has no GPU, so a headless run would measure
## nothing that matters here — the probe refuses to run headless.
##
## Stage: twelve quads the size of the catalog's HMI screen face (0.49 x 0.315 m,
## PlaceableCatalog._m_hmi), all in view of one camera. N of them are textured by
## their own SubViewport, and each SubViewport hosts a REAL HmiOverlay.tscn opened
## on the hmi_extruder_all scope with the ExtruderBluPort sub-screen — the first
## panel the operator wants in the world. The 2D is always laid out at the
## 1280x800 design canvas and stretched onto the texture size under test.
##
## Configurations (default pass): a baseline (no viewports), then N in {1, 4, 12}
## x texture {640x400, 1280x800} x redraw {every frame, re-armed on a 4 Hz data
## tick}, then the baseline again to show drift.
## `-- --attrib` runs the ATTRIBUTION pass instead: twelve screens at 640x400,
## changing one thing at a time — the page (BluPort vs HOOFDMENU), whether the
## SubViewport ever draws (UPDATE_DISABLED), and whether the BluPort page's own
## per-frame _process runs — to say WHERE the per-screen cost is.
## With vsync off, per configuration:
##   frame   mean / p95 wall time between _process calls (ms)
##   gpu     RenderingServer measured GPU time: root viewport, and summed over
##           the SubViewports (ms)
##   cpu_rs  RenderingServer measured CPU render time summed over the
##           SubViewports (ms)
## (Performance.TIME_PROCESS was printed by the first version and dropped: it
## read 44-214 ms against 2-35 ms frames, i.e. it is not a per-frame figure
## under max_fps 0, and a number that cannot be read is not a measurement.)
##
## LIMITS, stated so nobody reads more into the numbers than is there:
##  * no LineFlow and no extruder model is bound, so the pages draw defaults and
##    the 4 Hz refresh does less work than it would in a running plant;
##  * the camera sees every screen at once (worst case for the GPU); a real
##    build would also stop redrawing screens that are off-screen or far away;
##  * whatever else runs on the machine shares the CPU (the log says so).
##
##   APPDATA=<empty dir> godot --path . res://src/tests/probe_inworld_hmi_cost.tscn [-- --attrib]
## Always point APPDATA at an empty directory: autoloads boot, and user:// must
## not be the operator's.

const SCREEN_W := 0.49
const SCREEN_H := 0.315
const LOGICAL := Vector2i(1280, 800)
const SIZES := [Vector2i(640, 400), Vector2i(1280, 800)]
const COUNTS := [1, 4, 12]
const N_QUADS := 12
const WARM_S := 2.0
const MEASURE_S := 4.0
const TICK_S := 0.25          # HmiOverlay / HmiWebOverlay refresh at 4 Hz
const WATCHDOG_S := 300.0
const SCOPE_ID := "hmi_extruder_all"
const SUBSCOPE_ID := "extruder_1_blueport"
const _OV_SCENE := "res://src/scenes/hud/HmiOverlay.tscn"
const _SCOPES := preload("res://src/build/HmiScopes.gd")

var _quads : Array = []          # MeshInstance3D
var _plain : StandardMaterial3D
var _vps : Array = []            # SubViewport
var _configs : Array = []
var _ci := -1
var _cfg : Dictionary = {}
var _t_cfg := 0.0
var _t_prev := 0
var _t_start := 0
var _tick_acc := 0.0
var _frame_ms : PackedFloat32Array = PackedFloat32Array()
var _gpu_root : PackedFloat32Array = PackedFloat32Array()
var _gpu_sub : PackedFloat32Array = PackedFloat32Array()
var _cpu_sub : PackedFloat32Array = PackedFloat32Array()
var _results : Array = []
var _done := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("[PROBE] Result: FAIL — windowed only (the dummy renderer has no GPU to measure)")
		get_tree().quit(2)
		return
	_t_start = Time.get_ticks_msec()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("[PROBE] adapter '%s' / '%s', window %s, vsync off" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		DisplayServer.window_get_size()])
	_build_stage()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_configs.append({"name": "baseline", "n": 0, "size": Vector2i.ZERO, "mode": "-"})
	if "--attrib" in OS.get_cmdline_user_args():
		var s12 := Vector2i(640, 400)
		_configs.append({"name": "n12_bluport_tick4hz", "n": 12, "size": s12, "mode": "tick4hz"})
		_configs.append({"name": "n12_bluport_neverdraw", "n": 12, "size": s12, "mode": "disabled"})
		_configs.append({"name": "n12_bluport_noproc_4hz", "n": 12, "size": s12, "mode": "tick4hz", "sub_process": false})
		_configs.append({"name": "n12_hoofdmenu_tick4hz", "n": 12, "size": s12, "mode": "tick4hz", "page": "hoofdmenu"})
		_configs.append({"name": "n12_hoofdmenu_neverdraw", "n": 12, "size": s12, "mode": "disabled", "page": "hoofdmenu"})
	else:
		for n in COUNTS:
			for s in SIZES:
				for mode in ["always", "tick4hz"]:
					_configs.append({"name": "n%d_%dx%d_%s" % [n, s.x, s.y, mode], "n": n, "size": s, "mode": mode})
	_configs.append({"name": "baseline_again", "n": 0, "size": Vector2i.ZERO, "mode": "-"})
	_next_config()

func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.19, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 75.0            # SettingsManager default
	cam.position = Vector3(0.0, 1.4, 0.0)
	add_child(cam)
	cam.current = true
	# The catalog's screen material, so the baseline quads look like today's panels.
	_plain = StandardMaterial3D.new()
	_plain.albedo_color = Color(0.05, 0.09, 0.13)
	_plain.emission_enabled = true
	_plain.emission = Color(0.12, 0.42, 0.55)
	_plain.emission_energy_multiplier = 0.5
	var qm := QuadMesh.new()
	qm.size = Vector2(SCREEN_W, SCREEN_H)
	for i in N_QUADS:
		var q := MeshInstance3D.new()
		q.mesh = qm
		var col := i % 4
		var row := int(floor(i / 4.0))
		q.position = Vector3(-0.93 + 0.62 * col, 0.95 + 0.42 * row, -2.2)
		q.material_override = _plain
		add_child(q)
		_quads.append(q)

func _teardown_viewports() -> void:
	for q in _quads:
		(q as MeshInstance3D).material_override = _plain
	for vp in _vps:
		if is_instance_valid(vp):
			vp.free()
	_vps.clear()

func _next_config() -> void:
	_teardown_viewports()
	_ci += 1
	if _ci >= _configs.size():
		_finish()
		return
	_cfg = _configs[_ci]
	var scope := _SCOPES.get_scope(SCOPE_ID)
	var ov_scene := load(_OV_SCENE) as PackedScene
	for i in int(_cfg["n"]):
		var vp := SubViewport.new()
		vp.name = "HmiScreen%d" % i
		vp.size = _cfg["size"]
		vp.size_2d_override = LOGICAL
		vp.size_2d_override_stretch = true
		vp.disable_3d = true
		vp.transparent_bg = false
		match String(_cfg["mode"]):
			"always":   vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			"disabled": vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_:          vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var ov := ov_scene.instantiate()
		vp.add_child(ov)
		ov.call("open_for", String(scope.get("label", "Extruder")), scope)
		if String(_cfg.get("page", "bluport")) == "bluport":
			var sub_ok : bool = ov.call("open_subscope", SUBSCOPE_ID)
			if i == 0 and not sub_ok:
				print("[PROBE] WARNING: open_subscope('%s') returned false — the page is the HOOFDMENU" % SUBSCOPE_ID)
			if not bool(_cfg.get("sub_process", true)):
				var sub = ov.get("_subscope_node")
				if sub != null:
					(sub as Node).set_process(false)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = vp.get_texture()
		(_quads[i] as MeshInstance3D).material_override = mat
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		_vps.append(vp)
	_t_cfg = 0.0
	_tick_acc = 0.0
	_frame_ms = PackedFloat32Array()
	_gpu_root = PackedFloat32Array()
	_gpu_sub = PackedFloat32Array()
	_cpu_sub = PackedFloat32Array()
	_t_prev = Time.get_ticks_usec()

func _process(delta: float) -> void:
	# Watchdog first: a SCRIPT ERROR further down must not leave the probe idling.
	if not _done and float(Time.get_ticks_msec() - _t_start) / 1000.0 > WATCHDOG_S:
		print("[PROBE] Result: FAIL — watchdog after %.0f s at config %d" % [WATCHDOG_S, _ci])
		_done = true
		get_tree().quit(2)
		return
	if _done or _cfg.is_empty():
		return
	var now := Time.get_ticks_usec()
	var dt_ms := float(now - _t_prev) / 1000.0
	_t_prev = now
	_t_cfg += delta
	if _cfg["mode"] == "tick4hz":
		_tick_acc += delta
		if _tick_acc >= TICK_S:
			_tick_acc -= TICK_S
			for vp in _vps:
				(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	if _t_cfg < WARM_S:
		return
	_frame_ms.append(dt_ms)
	_gpu_root.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	var g := 0.0
	var c := 0.0
	for vp in _vps:
		var rid : RID = (vp as SubViewport).get_viewport_rid()
		g += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		c += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_gpu_sub.append(g)
	_cpu_sub.append(c)
	if _t_cfg >= WARM_S + MEASURE_S:
		_record()
		_next_config()

static func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / float(a.size())

static func _p95(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[int(floor(0.95 * float(b.size() - 1)))]

func _record() -> void:
	var r := {
		"name": _cfg["name"], "n": _cfg["n"], "frames": _frame_ms.size(),
		"frame_mean": _mean(_frame_ms), "frame_p95": _p95(_frame_ms),
		"gpu_root": _mean(_gpu_root),
		"gpu_sub": _mean(_gpu_sub), "cpu_sub": _mean(_cpu_sub),
	}
	_results.append(r)
	print("[PROBE] %-24s frames %5d  frame %6.3f ms (p95 %6.3f)  gpu root %6.3f  gpu subs %6.3f  cpu_rs subs %6.3f" % [
		r["name"], r["frames"], r["frame_mean"], r["frame_p95"], r["gpu_root"], r["gpu_sub"], r["cpu_sub"]])

func _finish() -> void:
	_done = true
	var base : float = float(_results[0]["frame_mean"]) if not _results.is_empty() else 0.0
	print("[PROBE] --- frame-time delta against the first baseline (%.3f ms) ---" % base)
	for r in _results:
		print("[PROBE] %-24s %+7.3f ms/frame" % [r["name"], float(r["frame_mean"]) - base])
	print("[PROBE] Result: DONE (%d configurations, %.0f s)" % [_results.size(), float(Time.get_ticks_msec() - _t_start) / 1000.0])
	get_tree().quit(0)
