extends Node
## DOSEERSILO AS THE OPERATOR DESCRIBED IT (2026-09-23, rulings §17) — an open,
## flat-bottomed trough tilted 20-25°, three augers along the bottom, no
## half-disc ends, the lowest point ~1.7 m up, 10 % narrower and 10 % longer
## than the model he was shown; low end in, high end out.
##
##   godot --headless --path . res://src/tests/test_doseersilo_trough.tscn
##
## Everything here is read off the built node (unmerged: the catalog's own
## _m_doseersilo on a bare Node3D) or off a real LineFlow node, never off the
## builder's constants.

const WATCHDOG_S := 200.0

var _fails := 0
var _oks := 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _box_size(mi: MeshInstance3D) -> Vector3:
	return (mi.mesh as BoxMesh).size if mi != null and mi.mesh is BoxMesh else Vector3.ZERO

func _run() -> void:
	print("[TEST] doseersilo trough — rulings §17")
	var item : Dictionary = PlaceableCatalog.get_item("doseersilo")
	var size : Vector3 = item["size"]
	var p := Node3D.new()
	add_child(p)
	PlaceableCatalog._m_doseersilo(p, size, item["color"], false)
	await get_tree().process_frame
	# ── shape ──
	var trough := p.find_child("Trough", true, false) as Node3D
	_check(trough != null, "T1 a Trough frame exists")
	if trough == null:
		_finish(); return
	var zdir : Vector3 = trough.global_transform.basis.z.normalized()
	var tilt_deg : float = rad_to_deg(asin(clampf(zdir.y, -1.0, 1.0)))
	_check(tilt_deg >= 20.0 and tilt_deg <= 25.0, "T1 the trough rises toward +Z at %.1f° (operator: about 20 to 25)" % tilt_deg)
	var bottom := p.find_child("TroughBottom", true, false) as MeshInstance3D
	_check(bottom != null and _box_size(bottom).y < 0.1, "T1 a flat bottom plate")
	var walls := p.find_children("TroughWall_*", "", true, false)
	var ends := p.find_children("TroughEnd_*", "", true, false)
	_check(walls.size() == 2 and ends.size() == 2, "T1 two side walls and two flat end plates (%d / %d)" % [walls.size(), ends.size()])
	var half_discs := 0
	var gratings := 0
	for c in p.find_children("*", "", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).top_radius > 1.0:
			half_discs += 1
		var bs := _box_size(mi)
		if bs.y < 0.05 and bs.x > 2.0 and bs.z > 4.0 and mi != bottom:
			gratings += 1
	_check(half_discs == 0, "T1 no semicircular end shapes (%d)" % half_discs)
	_check(gratings == 0, "T1 open top: no grating plate over the trough (%d)" % gratings)
	# lowest point of the body
	var lowest := 1e9
	for c in p.find_children("*", "", true, false):
		var mi := c as MeshInstance3D
		if mi == null or not (mi.mesh is BoxMesh) or mi.is_in_group("machine_leg"):
			continue
		if mi.get_parent() != trough and not (mi.get_parent() is Node3D and (mi.get_parent() as Node3D).get_parent() == trough):
			continue
		var bs := _box_size(mi)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner : Vector3 = mi.to_global(Vector3(sx * bs.x * 0.5, sy * bs.y * 0.5, sz * bs.z * 0.5))
					lowest = minf(lowest, corner.y)
	_check(absf(lowest - 1.7) < 0.05, "T1 the body's lowest point sits %.2f m up (operator: about 1.7)" % lowest)
	# proportions against the model he was shown (3.6 wide, 5.5 long)
	var inner_w : float = float(trough.get_meta("inner_w"))
	var inner_l : float = float(trough.get_meta("inner_l"))
	_check(absf(inner_w / (3.6 * 0.92) - 0.90) < 0.05 and absf(inner_l / (5.5 * 0.92) - 1.10) < 0.05,
		"T1 about 10 %% narrower (%.2f m) and 10 %% longer (%.2f m) than the rendered model" % [inner_w, inner_l])
	# augers along the flat bottom, tilting with it
	var augers := 0
	for c in p.find_children("*", "", true, false):
		if c.has_meta("comp") and String(c.get_meta("comp")).begins_with("auger_"):
			augers += 1
			var a3 := c as Node3D
			if a3 != null:
				var ay : float = trough.to_local(a3.global_position).y
				if ay < 0.0 or ay > 0.5:
					augers -= 100
	_check(augers == 3, "T1 three augers low in the trough, on the tilted frame (%d)" % augers)
	# legs reach the trough bottom
	var legs := 0
	for c in p.find_children("*", "", true, false):
		if c.is_in_group("machine_leg"):
			legs += 1
	_check(legs == 4, "T1 four legs (%d)" % legs)
	# ── flow: low end in, high end out ──
	var body : Node3D = PlaceableCatalog.build_node("doseersilo", false)
	add_child(body)
	body.global_position = Vector3(20.0, 0.0, 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.set("feed_enabled", false)
	lf.call("rebuild")
	await get_tree().process_frame
	var nd : Dictionary = {}
	for n in (lf.get("_nodes") as Array):
		if String(n.get("id", "")) == "doseersilo":
			nd = n
	_check(not nd.is_empty(), "F1 LineFlow discovered the doseersilo")
	if not nd.is_empty():
		var win : Vector3 = body.to_local(nd["win"])
		var wout : Vector3 = body.to_local(nd["wout"])
		_check(win.z < -1.0 and wout.z > 1.0, "F1 inlet at the low (-Z) end, outlet at the high (+Z) end (z %.2f / %.2f)" % [win.z, wout.z])
		_check(wout.y > win.y + 1.5, "F1 the outlet is higher than the inlet (%.2f vs %.2f m)" % [wout.y, win.y])
		_check(win.y > 1.7 and wout.y < size.y, "F1 both ports inside the trough's height band")
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
