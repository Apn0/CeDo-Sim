extends Node
## TEMPORARY debug autoload — scans the whole tree for non-finite transforms,
## prints exact node paths, then quits. Added by an automated root-cause
## investigation; safe to delete.

var _ticks := 0
var _done := false

func _physics_process(_delta: float) -> void:
	if _done:
		return
	var cs := get_tree().current_scene
	if cs == null or not String(cs.name).contains("MainWorld"):
		return
	_ticks += 1
	if _ticks < 120:
		return
	_done = true
	var bad: Array = []
	_scan(get_tree().root, bad)
	print("[NanScan] non-finite Node3D count: %d" % bad.size())
	for p in bad:
		print("[NanScan] BAD: %s" % p)
	get_tree().quit()

func _scan(n: Node, bad: Array) -> void:
	if n is Node3D:
		var n3 := n as Node3D
		var lf := n3.transform.is_finite()
		var gf := true
		if n3.is_inside_tree():
			gf = n3.global_transform.is_finite()
		if not lf or not gf:
			bad.append("%s | local_finite=%s global_finite=%s visual=%s | local=%s" % [
				str(n3.get_path()), str(lf), str(gf), str(n3 is VisualInstance3D), str(n3.transform)])
	for c in n.get_children():
		_scan(c, bad)
