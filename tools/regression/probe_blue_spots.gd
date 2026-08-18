## Measurement probe (not a pass/fail test): where does each Linde-style blue
## safety spot actually hit the floor, for every lit vehicle, in BOTH
## operator_forward_sign polarities?
##
## Run:  godot --headless --path <proj> --script res://tools/regression/probe_blue_spots.gd
##
## Reported per spot:
##   pos / rot_deg          — the node's local transform as built
##   aim_dir                — -Z of the spot's basis (Godot SpotLight3D aim)
##   floor_hit_z            — where that ray meets y = 0 (chassis origin sits at
##                            ground; see BaleClamp.gd:55)
##   ahead_of_body_m        — signed distance from the chassis face the spot is
##                            supposed to cover, measured in the OPERATOR's
##                            forward direction. Positive = out in front of the
##                            machine (what a blue spot is for). Negative = the
##                            beam has landed under/behind its own chassis.
extends SceneTree

const VEHICLES := {
	"BaleClamp": "res://src/scenes/vehicles/BaleClamp.tscn",
	"Forklift":  "res://src/scenes/vehicles/Forklift.tscn",
	"Merlo":     "res://src/scenes/vehicles/Merlo.tscn",
	"MerloP40":  "res://src/scenes/vehicles/MerloP40.tscn",
}

func _body_half_len(v: Node) -> float:
	# Longest BoxShape3D child on the root = the chassis hull.
	var best := 0.0
	for c in v.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var s : Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
			if s.z * 0.5 > best:
				best = s.z * 0.5
	return best

func _report(tag: String, v: Node3D) -> void:
	var sign_v : float = v.get("operator_forward_sign")
	var half := _body_half_len(v)
	print("--- %s  operator_forward_sign=%+0.1f  chassis_half_len_z=%.2f m" % [tag, sign_v, half])
	for c in v.get_children():
		if not (c is SpotLight3D) or not String(c.name).begins_with("BlueSpot"):
			continue
		var sl := c as SpotLight3D
		var dir : Vector3 = -sl.transform.basis.z
		var org : Vector3 = sl.position
		var hit_z := NAN
		if absf(dir.y) > 0.001:
			var t : float = -org.y / dir.y
			hit_z = org.z + dir.z * t
		# operator forward in local space = -Z * operator_forward_sign
		# (canonical -Z is forward; sign=-1 vehicles drive gear-first on +Z)
		var op_fwd_z : float = -sign_v
		# The face this spot covers: front spot -> operator-forward face,
		# rear spot -> the other one. Front = the one on the operator-forward side.
		var on_fwd_side : bool = (signf(org.z) == signf(op_fwd_z))
		var face_z : float = (half * op_fwd_z) if on_fwd_side else (-half * op_fwd_z)
		var ahead : float = (hit_z - face_z) * (op_fwd_z if on_fwd_side else -op_fwd_z)
		print("    %-14s pos=(%.2f,%.2f,%.2f) rot_deg=(%.1f,%.1f,%.1f) aim=(%.3f,%.3f,%.3f) floor_hit_z=%+.3f  side=%s  ahead_of_body=%+.2f m" % [
			sl.name, org.x, org.y, org.z,
			sl.rotation_degrees.x, sl.rotation_degrees.y, sl.rotation_degrees.z,
			dir.x, dir.y, dir.z, hit_z,
			("FRONT(operator)" if on_fwd_side else "REAR"), ahead])

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	for tag in VEHICLES:
		for forced_sign in [null, 1.0]:
			var ps : PackedScene = load(VEHICLES[tag])
			var v : Node3D = ps.instantiate()
			root.add_child(v)          # _ready() runs here, sets sign = -1
			var label : String = String(tag)
			if forced_sign != null:
				# Force the +1 polarity BEFORE the deferred aux install fires,
				# so we can measure the normal-vehicle branch too.
				v.set("operator_forward_sign", float(forced_sign))
				label = "%s [forced sign=+1]" % tag
			await process_frame
			await process_frame
			_report(label, v)
			v.queue_free()
			await process_frame
	quit()
