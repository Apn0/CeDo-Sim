extends Node
## Headless test for the Merlo P40 telehandler (Task #22).
##
## Verifies that the FBX-driven articulation in MerloP40.gd actually wires up
## and MOVES the three things that matter:
##   (1) the boom telescoping sections (Rampe_1..4) exist and extend/retract +
##       raise/lower change their transforms;
##   (2) the door (Portes leaves) exists and open/close changes its rotation;
##   (3) the basket / fork-carriage exists on the boom.
##
## Run via the project boot path so autoloads (EventBus, …) register as globals
## and so class_name types (CameraRig, OperatorContext) are loadable:
##   godot --headless --main-scene res://src/tests/test_merlo_p40.tscn
##
## The test runs in _ready, prints a pass/fail summary, and quits with code 0
## (all ok) or 1 (any failure / could-not-run).
##
## DESIGN: MerloP40 drives the boom from plain member vars — `boom_deg` (R/F via
## forklift_lift_*) and `extend_m` (T/G via forklift_tilt_*). _apply_boom()
## (Merlo.gd, every _physics_process) rotates _boom_pivot from boom_deg, and the
## P40's own _process() slides _boom_sections from extend_m — neither is gated on
## `occupied`. So we set the vars directly and pump frames, which is far more
## robust headless than synthesising key Input. We additionally smoke-test the
## real Input path with occupied=true at the end.

const MERLO_P40_SCENE := "res://src/scenes/vehicles/MerloP40.tscn"

var _fail := 0
var _pass := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _section(title: String) -> void:
	print("\n[%s]" % title)

## Pump N full frames so _process AND _physics_process both run, and the door
## lerp / boom telescope interpolation advance.
func _tick(frames: int) -> void:
	for i in range(frames):
		await get_tree().process_frame
		await get_tree().physics_frame

func _ready() -> void:
	print("=== Merlo P40 telehandler verification ===")

	# ── Load + instance the vehicle ────────────────────────────────────────
	if not ResourceLoader.exists(MERLO_P40_SCENE):
		print("FATAL: %s does not exist" % MERLO_P40_SCENE)
		return _finish()
	var packed := load(MERLO_P40_SCENE) as PackedScene
	if packed == null:
		print("FATAL: %s did not load as PackedScene" % MERLO_P40_SCENE)
		return _finish()
	var merlo := packed.instantiate()
	if merlo == null:
		print("FATAL: MerloP40 instantiate() returned null")
		return _finish()
	# Wait a frame so the root has finished setting up children (else add_child
	# fails with "parent is busy setting up children").
	await get_tree().process_frame
	# Adding to the tree runs _ready → _load_and_classify (FBX load + wiring).
	get_tree().root.add_child(merlo)
	# Give the deferred aux install + a couple of physics ticks time to settle.
	await _tick(3)

	# ── 0. Did the FBX actually load (not the placeholder)? ─────────────────
	_section("FBX load")
	var placeholder := merlo.get_node_or_null("PlaceholderMesh")
	var mesh_root := merlo.get_node_or_null("MerloMesh")
	if placeholder != null:
		_ok(false, "FBX did NOT import — MerloP40 fell back to placeholder box "
			+ "(open the project in the editor once to bake the .scn). "
			+ "Cannot verify real parts.")
		return _finish()
	_ok(mesh_root != null, "FBX imported — 'MerloMesh' visual tree mounted under MerloP40")

	var parts : Dictionary = merlo._parts

	# ── 1. BOOM — Rampe sections exist + extend/retract + raise/lower move ──
	_section("Boom (Rampe_1..4)")
	# 1a. The classifier found 'boom' meshes (the Rampe assembly).
	var boom_parts : Array = parts.get("boom", [])
	_ok(not boom_parts.is_empty(),
		"boom parts classified from FBX (count=%d): %s"
			% [boom_parts.size(), _names(boom_parts)])

	# 1b. The telescoping sections got wired (rear→front weighted slides).
	var sections : Array = merlo._boom_sections
	_ok(sections.size() > 0,
		"_boom_sections wired (telescoping sections, count=%d)" % sections.size())
	# We expect the FBX's Rampe_1..4 → at least 2 sliding sections for a real
	# telescope. Report (not hard-fail) if fewer, so a model change is visible.
	_ok(sections.size() >= 2,
		"boom has >= 2 telescoping sections (got %d)" % sections.size())

	if merlo._boom_pivot == null:
		_ok(false, "boom pivot (_boom_pivot) wired — REQUIRED for raise/lower")
	else:
		_ok(true, "boom pivot wired: '%s'" % merlo._boom_pivot.name)

	# 1c. EXTEND / RETRACT changes section transforms.
	if sections.size() > 0:
		# Snapshot rest positions.
		merlo.extend_m = 0.0
		await _tick(2)
		var z_at_zero : Array = _section_z(sections)
		# Extend fully (extend_max_m comes from Merlo.gd, default 3.0).
		merlo.extend_m = merlo.extend_max_m
		await _tick(6)
		var z_extended : Array = _section_z(sections)
		var moved_count := 0
		var max_delta := 0.0
		for i in range(sections.size()):
			var d : float = absf(z_extended[i] - z_at_zero[i])
			if d > 0.001:
				moved_count += 1
			max_delta = maxf(max_delta, d)
		_ok(moved_count > 0,
			"extend_m 0→%.2f slides %d/%d sections (max Δz=%.3f m)"
				% [merlo.extend_max_m, moved_count, sections.size(), max_delta])
		# Retract and confirm it returns toward the rest pose.
		merlo.extend_m = 0.0
		await _tick(6)
		var z_back : Array = _section_z(sections)
		var max_back_err := 0.0
		for i in range(sections.size()):
			max_back_err = maxf(max_back_err, absf(z_back[i] - z_at_zero[i]))
		_ok(max_back_err < 0.01,
			"retract returns sections to rest (max residual=%.4f m)" % max_back_err)

	# 1d. RAISE / LOWER rotates the boom pivot (_apply_boom in _physics_process).
	if merlo._boom_pivot != null:
		merlo.boom_deg = 0.0
		await _tick(2)
		var rot_at_zero : float = merlo._boom_pivot.rotation.x
		merlo.boom_deg = (merlo.boom_min_deg + merlo.boom_max_deg) * 0.5 + 20.0
		await _tick(3)
		var rot_raised : float = merlo._boom_pivot.rotation.x
		_ok(absf(rot_raised - rot_at_zero) > 0.01,
			"boom_deg=%.1f rotates pivot.x %.4f→%.4f rad (Δ=%.4f)"
				% [merlo.boom_deg, rot_at_zero, rot_raised,
					absf(rot_raised - rot_at_zero)])
		merlo.boom_deg = 0.0
		await _tick(3)
		_ok(absf(merlo._boom_pivot.rotation.x - rot_at_zero) < 0.01,
			"boom lower returns pivot toward rest")

	# ── 2. DOOR — exists + open/close changes rotation ─────────────────────
	_section("Door (Portes)")
	var door_parts : Array = parts.get("door", [])
	_ok(not door_parts.is_empty(),
		"door parts classified from FBX (count=%d): %s"
			% [door_parts.size(), _names(door_parts)])
	if merlo._door_pivot == null:
		_ok(false, "door pivot (_door_pivot) wired — REQUIRED for open/close. "
			+ "If door_parts has only 'Porte' (no 'Portes' leaves) the door "
			+ "won't articulate.")
	else:
		_ok(true, "door pivot wired: '%s'" % merlo._door_pivot.name)
		# Door starts closed.
		var ang_closed : float = merlo._door_pivot.rotation.y
		# Open it — toggle_door sets _door_target_deg, _process lerps the pivot.
		merlo.toggle_door()
		await _tick(40)   # ~0.7 s of lerp at 60 fps (rate ~4.5/frame-clamped)
		var ang_open : float = merlo._door_pivot.rotation.y
		_ok(absf(ang_open - ang_closed) > deg_to_rad(10.0),
			"open door rotates pivot.y %.3f→%.3f rad (%.1f°)"
				% [ang_closed, ang_open, rad_to_deg(ang_open - ang_closed)])
		# can_enter() must now report true (door past the boarding threshold).
		_ok(merlo.can_enter(),
			"door open → can_enter() == true (open_deg=%.1f, threshold=%.1f)"
				% [merlo._door_open_deg, merlo.DOOR_OPEN_THRESHOLD])
		# Close it again.
		merlo.toggle_door()
		await _tick(60)
		var ang_reclosed : float = merlo._door_pivot.rotation.y
		_ok(absf(ang_reclosed - ang_closed) < deg_to_rad(8.0),
			"close door returns pivot.y toward rest (%.1f°)"
				% rad_to_deg(ang_reclosed))

	# ── 3. BASKET / FORK-CARRIAGE exists on the boom ───────────────────────
	# The P40 carries no separate procedural grapple/bucket — its fork carriage
	# is modelled as the FRONT-MOST section of the Rampe assembly (see
	# _articulate_boom: "the model carries its own fork attachment on the boom").
	# So "the basket/grapple node exists" == the boom has a front carriage
	# section. We assert a front-most boom section exists and that the boom set
	# carries more than the bare pivot.
	_section("Basket / fork carriage")
	var carriage_ok := sections.size() >= 1
	_ok(carriage_ok,
		"fork carriage present as the front-most boom section (sections=%d)"
			% sections.size())
	if sections.size() >= 1:
		# The last weighted section (w==1.0) is the tip / fork carriage.
		var tip : Dictionary = sections[sections.size() - 1]
		var tip_node : Node3D = tip["node"]
		var tip_w : float = tip["w"]
		_ok(tip_node != null and tip_w > 0.99,
			"front carriage = '%s' (travel weight=%.2f, slides furthest)"
				% [tip_node.name if tip_node else "<null>", tip_w])
	# Bonus: report any explicitly-named fork/carriage mesh we can spot, for
	# documentation (not asserted — naming varies in the FBX pack).
	var named_carriage := _find_named(merlo, [
		"tablier", "fork", "fourche", "carriage", "chariot", "godet", "benne"])
	if named_carriage != "":
		print("  note : found explicitly-named attachment mesh: %s" % named_carriage)
	else:
		print("  note : no separate fork/bucket mesh by name — carriage is part "
			+ "of the Rampe assembly (expected for this model).")

	# ── 4. Smoke-test the REAL input path (occupied + key press) ───────────
	# Exercises Merlo._update_boom → extend_m via forklift_tilt_back (T). This is
	# best-effort: action-press in headless can be timing-sensitive, so a miss
	# here is reported but does NOT fail the run (the direct-var path above is
	# the authoritative boom check).
	_section("Input path smoke test (occupied)")
	merlo.extend_m = 0.0
	merlo.occupied = true
	await _tick(2)
	var z_before : Array = _section_z(sections) if sections.size() > 0 else []
	Input.action_press("forklift_tilt_back")
	await _tick(10)
	Input.action_release("forklift_tilt_back")
	await _tick(2)
	if sections.size() > 0:
		var z_after : Array = _section_z(sections)
		var moved := false
		for i in range(sections.size()):
			if absf(z_after[i] - z_before[i]) > 0.001:
				moved = true
				break
		if moved:
			print("  ok   : T (forklift_tilt_back) extended the boom via Input (extend_m=%.3f)"
				% merlo.extend_m)
			_pass += 1
		else:
			print("  info : Input-driven extend didn't register headless "
				+ "(extend_m=%.3f) — non-fatal; direct-var extend verified above."
				% merlo.extend_m)
	merlo.occupied = false

	_finish()

# ── helpers ─────────────────────────────────────────────────────────────────
func _section_z(sections: Array) -> Array:
	var out : Array = []
	for s in sections:
		out.append((s["node"] as Node3D).position.z)
	return out

func _names(nodes: Array) -> String:
	var n : Array = []
	for x in nodes:
		if x is Node:
			n.append((x as Node).name)
	return str(n)

## Walk the whole instance tree for a Node3D whose (lowercased) name contains any
## of `needles`; returns its name or "".
func _find_named(root: Node, needles: Array) -> String:
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		var nl := n.name.to_lower()
		for needle in needles:
			if nl.contains(needle):
				return n.name
		for c in n.get_children():
			stack.append(c)
	return ""

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
