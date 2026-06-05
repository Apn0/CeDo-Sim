extends StaticBody3D
class_name LPGRack

## Outdoor LPG cylinder storage rack. Steel frame with two rows of slots:
##
##   UPPER ROW  — empty cylinders (returns from vehicles whose mounts ran dry)
##   LOWER ROW  — full cylinders fresh from the gas supplier
##
## Slots are Node3D anchors named `Slot_Upper_N` / `Slot_Lower_N`. On spawn,
## the rack auto-populates each slot with an LPGTank (level=0.0 upper,
## level=1.0 lower). Slots track their occupancy via the `mounted_tank` meta
## so the LPGTank's mount-search logic can be reused (rack slots and vehicle
## mounts have identical contract). Pulling/depositing a tank is just the
## operator's normal tank E-pickup → walk → E-drop near a slot.
##
## SHIFT-RULE FICTION: the rack should have ~8 full + ~8 empty slots so a
## careful crew never runs out, but a lazy half-swap habit will leave the
## lower rack full of half-tanks (the empty-row trips full at the worst time).
## We don't enforce that here — it falls out of the mount/unmount math
## naturally.

@export var slots_per_row : int = 4
@export var slot_spacing  : float = 0.45   # m between cylinders side-by-side
const PICKUP_RANGE_M : float = 1.4         # how close a held tank needs to be to "drop in"
const ROW_HEIGHT_LOW  : float = 0.04
const ROW_HEIGHT_HIGH : float = 0.95
const FRAME_W   : float = 1.9
const FRAME_H   : float = 1.85
const FRAME_D   : float = 0.45

# =============================================================================
func _ready() -> void:
	add_to_group("lpg_rack")
	_build_frame()
	_build_slots()
	call_deferred("_populate_initial_tanks")

func _build_frame() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.45, 0.46); steel.roughness = 0.75
	var ylw := StandardMaterial3D.new()
	ylw.albedo_color = Color(0.92, 0.78, 0.18); ylw.roughness = 0.7
	# Floor pad
	var pad := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(FRAME_W, 0.04, FRAME_D)
	pad.mesh = bm
	pad.material_override = steel
	pad.position = Vector3(0, 0.02, 0)
	add_child(pad)
	# Two vertical posts
	for s in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new(); pm.size = Vector3(0.06, FRAME_H, 0.06)
		post.mesh = pm
		post.material_override = steel
		post.position = Vector3(s * (FRAME_W * 0.5 - 0.03), FRAME_H * 0.5, 0)
		add_child(post)
	# Two horizontal shelves (lower + upper rails)
	for y in [ROW_HEIGHT_LOW + 0.02, ROW_HEIGHT_HIGH - 0.02]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new(); rm.size = Vector3(FRAME_W, 0.04, FRAME_D * 0.85)
		rail.mesh = rm
		rail.material_override = steel
		rail.position = Vector3(0, y, 0)
		add_child(rail)
	# Top sign rail (yellow safety stripe)
	var sign_rail := MeshInstance3D.new()
	var sm := BoxMesh.new(); sm.size = Vector3(FRAME_W, 0.10, 0.04)
	sign_rail.mesh = sm
	sign_rail.material_override = ylw
	sign_rail.position = Vector3(0, FRAME_H - 0.06, -FRAME_D * 0.5 + 0.02)
	add_child(sign_rail)
	# Static body collision for the frame so vehicles can't drive through it
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(FRAME_W, FRAME_H, FRAME_D)
	col.shape = cs
	col.position = Vector3(0, FRAME_H * 0.5, 0)
	add_child(col)

func _build_slots() -> void:
	# slot X positions evenly spaced across the rack width
	var total_w := slot_spacing * float(slots_per_row - 1)
	var x0 := -total_w * 0.5
	for i in slots_per_row:
		var px := x0 + i * slot_spacing
		# Lower (FULL)
		var lo := Node3D.new()
		lo.name = "Slot_Lower_%d" % i
		lo.position = Vector3(px, ROW_HEIGHT_LOW, 0)
		lo.add_to_group("lpg_rack_slot_lower")
		add_child(lo)
		# Upper (EMPTY)
		var hi := Node3D.new()
		hi.name = "Slot_Upper_%d" % i
		hi.position = Vector3(px, ROW_HEIGHT_HIGH, 0)
		hi.add_to_group("lpg_rack_slot_upper")
		add_child(hi)

## Populate every lower slot with a full tank and every upper slot with an
## empty one. Called via call_deferred so the rack is in the tree first.
func _populate_initial_tanks() -> void:
	var tank_script := preload("res://src/scenes/world/LPGTank.gd")
	for i in slots_per_row:
		var lo := get_node_or_null("Slot_Lower_%d" % i) as Node3D
		if lo and not lo.has_meta("mounted_tank"):
			var t_full = tank_script.new()
			t_full.level = 1.0
			get_tree().current_scene.add_child(t_full)
			t_full.global_transform = lo.global_transform
			lo.set_meta("mounted_tank", t_full)
		var hi := get_node_or_null("Slot_Upper_%d" % i) as Node3D
		if hi and not hi.has_meta("mounted_tank"):
			var t_empty = tank_script.new()
			t_empty.level = 0.0
			get_tree().current_scene.add_child(t_empty)
			t_empty.global_transform = hi.global_transform
			hi.set_meta("mounted_tank", t_empty)
