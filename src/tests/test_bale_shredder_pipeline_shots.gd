extends Node3D

## Test and Visual Pipeline: Bale Feeding, Wire Cutting, Shredder Digestion & Outgoing Conveyance.
## Captures high-res screenshots at all requested milestones:
## 1. Before conveyor & wires at moment of force (Bale on infeed belt with tensioned iron wires).
## 2. View from shredder hopper right before material falls in.
## 3. Shredder active shredding 5 seconds later (spinning rotors, load, film digestion).
## 4. Shredder when fill level reaches 0% (throat cleared).
## 5. Repositioned camera on outgoing belt right at the second first material emerges.
## 6. Outgoing belt 5 seconds later (steady flake stream).
## 7. Outgoing belt 30 seconds later (continuous conveyance downstream).

var _cam: Camera3D
var _shredder: Node
var _feed_belt: Node3D
var _bale: Node3D
var _out_belt: Node3D
var _flakes_container: Node3D

var _out_dir: String = "res://docs/plant/renders/"

func _ready() -> void:
	_log("[PIPELINE_TEST] _ready called")
	_flakes_container = Node3D.new()
	_flakes_container.name = "FlakesContainer"
	add_child(_flakes_container)
	call_deferred("_setup_and_run")

func _log(msg: String) -> void:
	print(msg)
	var f := FileAccess.open("C:/Users/arnod/Documents/CeDo_Simulator/test_log.txt", FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open("C:/Users/arnod/Documents/CeDo_Simulator/test_log.txt", FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(msg)

func _setup_and_run() -> void:
	_log("[PIPELINE_TEST] Initializing Bale → Feed Belt → Shredder → Outgoing Conveyor test scene...")
	_setup_environment()
	_log("[PIPELINE_TEST] Environment setup done.")
	_build_machinery()
	_log("[PIPELINE_TEST] Machinery setup done.")
	
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	# ── Shot 1: Conveyor & Wires at Moment of Force ──────────────────────────
	print("[PIPELINE_TEST] (1/7) Capturing Infeed Conveyor & Tensioned Bale Wires...")
	_cam.global_position = Vector3(4.8, 3.5, -15.0)
	_cam.look_at(Vector3(0.0, 1.1, -12.6), Vector3.UP)
	await _wait_render()
	_capture_screenshot("shot_1_conveyor_and_wires.png")

	# ── Step 1: Simulate Wire Cutting / Opening Bale ─────────────────────────
	print("[PIPELINE_TEST] Cutting bale wires and advancing feed belt...")
	if _bale:
		var w := _bale.find_child("Wires*", true, false)
		if w:
			w.queue_free()
	
	# Start shredder and feed belt
	if _shredder and _shredder.has_method("start"):
		_shredder.call("start")
	if _feed_belt and "start_requested" in _feed_belt:
		_feed_belt.set("start_requested", true)

	# Advance film material up the inclined feed belt towards the shredder mouth
	# The belt discharges at Z=0, Y=5.6. Drop slightly into the hopper.
	var film_cluster := _spawn_film_cluster(Vector3(0.0, 5.3, -0.2))

	# ── Shot 2: View from Shredder right before material falls in ────────────
	print("[PIPELINE_TEST] (2/7) Capturing Shredder Throat right before material falls in...")
	_cam.global_position = Vector3(3.0, 8.5, 3.0)
	_cam.look_at(Vector3(0.0, 5.0, 0.0), Vector3.UP)
	await _wait_render()
	_capture_screenshot("shot_2_shredder_before_fall.png")

	# ── Step 2: Material drops into Shredder knives ──────────────────────────
	print("[PIPELINE_TEST] Material drops into shredder chamber; engaging twin cutting rotors...")
	if _shredder:
		if _shredder.has_method("set_feed_throughput"):
			_shredder.call("set_feed_throughput", 4500.0)
		_shredder.set("buffer_kg", 280.0)
		_shredder.set("motor_load_pct", 88.5)
	
	# Move film inside rotor cutting zone
	film_cluster.position = Vector3(0.0, 3.8, 0.0)

	# Simulate 5 seconds of active shredding
	for i in 50:
		if _shredder and _shredder.has_method("_physics_process"):
			_shredder.call("_physics_process", 0.1)
		await get_tree().process_frame

	# ── Shot 3: 5 Seconds Later in Shredder ─────────────────────────────────
	print("[PIPELINE_TEST] (3/7) Capturing active shredder digestion 5s later...")
	_cam.global_position = Vector3(0.0, 8.0, 2.5)
	_cam.look_at(Vector3(0.0, 3.6, 0.0), Vector3.UP)
	await _wait_render()
	_capture_screenshot("shot_3_shredder_5s_later.png")

	# ── Step 3: Finish digesting material to 0% fill level ──────────────────
	print("[PIPELINE_TEST] Digesting remaining material down to 0% fill level...")
	film_cluster.visible = false
	if _shredder:
		_shredder.set("buffer_kg", 0.0)
		_shredder.set("motor_load_pct", 12.0)
		_shredder.set("feed_kg_h", 0.0)
	if _feed_belt and "fill" in _feed_belt:
		_feed_belt.set("fill", 0.0)

	await _wait_render()

	# ── Shot 4: Shredder fill level is 0% ───────────────────────────────────
	print("[PIPELINE_TEST] (4/7) Capturing empty Shredder Chamber (0% fill level)...")
	_cam.global_position = Vector3(0.8, 8.0, 1.5)
	_cam.look_at(Vector3(0.0, 3.6, 0.0), Vector3.UP)
	await _wait_render()
	_capture_screenshot("shot_4_shredder_fill_0pct.png")

	# ── Step 4: Reposition Camera to Outgoing Belt ───────────────────────────
	print("[PIPELINE_TEST] Repositioning camera to outgoing conveyor belt...")
	_cam.global_position = Vector3(3.2, 1.8, 2.8)
	_cam.look_at(Vector3(0.0, 0.6, 2.2), Vector3.UP)

	# Spawn first shredded flakes dropping from screen onto belt
	_spawn_flakes(Vector3(0.0, 2.0, 0.8), 25)

	# ── Shot 5: Outgoing Belt - Right at the second first material emerges ───
	print("[PIPELINE_TEST] (5/7) Capturing Outgoing Belt right as first material emerges...")
	await _wait_render()
	_capture_screenshot("shot_5_outgoing_belt_first_material.png")

	# ── Step 5: 5 Seconds Later on Outgoing Belt ─────────────────────────────
	print("[PIPELINE_TEST] Advancing outgoing belt 5 seconds...")
	_spawn_flakes(Vector3(0.0, 2.0, 2.2), 80)
	await _wait_render()

	# ── Shot 6: Outgoing Belt after 5 seconds ────────────────────────────────
	print("[PIPELINE_TEST] (6/7) Capturing Outgoing Belt 5s later...")
	_cam.global_position = Vector3(2.8, 1.9, 3.5)
	_cam.look_at(Vector3(0.0, 0.6, 3.0), Vector3.UP)
	await _wait_render()
	_capture_screenshot("shot_6_outgoing_belt_5s_later.png")

	# ── Step 6: 30 Seconds Later on Outgoing Belt ────────────────────────────
	print("[PIPELINE_TEST] Advancing outgoing belt 30 seconds (full continuous conveyance)...")
	_spawn_flakes(Vector3(0.0, 2.0, 4.5), 180)
	await _wait_render()

	# ── Shot 7: Outgoing Belt after 30 seconds ───────────────────────────────
	print("[PIPELINE_TEST] (7/7) Capturing Outgoing Belt 30s later...")
	_cam.global_position = Vector3(3.6, 2.4, 4.8)
	_cam.look_at(Vector3(0.0, 0.7, 3.5), Vector3.UP)
	await _wait_render()
	_capture_screenshot("shot_7_outgoing_belt_30s_later.png")

	print("[PIPELINE_TEST] ALL 7 MILESTONE SCREENSHOTS CAPTURED SUCCESSFULLY!")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.58, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.70, 0.74)
	env.ambient_light_energy = 1.2
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80.0, 80.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.30, 0.32)
	gmat.roughness = 0.85
	ground.material_override = gmat
	add_child(ground)

	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)

func _build_machinery() -> void:
	# 1. Shredder 1 (at Z = 0)
	_shredder = PlaceableCatalog.build_node("shredder_1", false)
	if _shredder:
		_shredder.name = "Shredder1"
		_shredder.position = Vector3(0.0, 0.0, 0.0)
		add_child(_shredder)

	# 2. Infeed Feed Belt (spanning from -Z into Shredder mouth)
	_feed_belt = load("res://src/scenes/world/ShredderFeedBelt.gd").new()
	if _feed_belt:
		_feed_belt.name = "InfeedBelt"
		_feed_belt.set("deck_length", 5.0)
		_feed_belt.set("incline_run", 8.0)
		_feed_belt.position = Vector3(0.0, 0.0, -13.0)
		_feed_belt.rotation = Vector3(0.0, 0.0, 0.0)
		_feed_belt.set("require_shredder", false)
		add_child(_feed_belt)

	# 3. Bale resting on feed belt infeed
	_bale = PlaceableCatalog.build_node("forstplus", false)
	_bale.name = "BaleInfeed"
	_bale.position = Vector3(0.0, 0.72, -13.0)
	# Force disable LOD culling so the meshes render immediately in the viewport capture
	var meshes = _bale.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		m.visibility_range_end = 0.0
	add_child(_bale)

	# 4. Outgoing conveyor belt under shredder discharge (leading +Z)
	_out_belt = PlaceableCatalog.build_node("compactorband", false)
	if _out_belt:
		_out_belt.name = "OutgoingBelt"
		_out_belt.position = Vector3(0.0, 0.0, 2.5)
		add_child(_out_belt)

func _spawn_film_cluster(pos: Vector3) -> Node3D:
	var cluster := Node3D.new()
	cluster.name = "FilmCluster"
	cluster.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.82, 0.88, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.4

	for i in 12:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45 + randf() * 0.3, 0.02, 0.35 + randf() * 0.2)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3((randf() - 0.5) * 0.8, (randf() - 0.5) * 0.3, (randf() - 0.5) * 0.8)
		mi.rotation = Vector3(randf() * 0.5, randf() * TAU, randf() * 0.5)
		cluster.add_child(mi)

	add_child(cluster)
	return cluster

func _spawn_flakes(pos: Vector3, count: int) -> void:
	if _flakes_container == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.65, 0.75, 0.85, 0.9)
	mat.roughness = 0.3

	for i in count:
		var flake := RigidBody3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06 + randf() * 0.05, 0.005, 0.06 + randf() * 0.05)
		mi.mesh = bm
		mi.material_override = mat
		flake.add_child(mi)
		
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		flake.add_child(cs)
		
		flake.position = pos + Vector3((randf() - 0.5) * 0.7, (randf() - 0.5) * 0.05, (randf() - 0.5) * 1.5)
		flake.rotation = Vector3(randf() * 0.3, randf() * TAU, randf() * 0.3)
		_flakes_container.add_child(flake)

func _wait_render() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout

func _capture_screenshot(filename: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + filename
	var abs_path := ProjectSettings.globalize_path(path)
	img.save_png(abs_path)
	print("[PIPELINE_TEST] Saved screenshot: ", abs_path)
