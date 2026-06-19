extends Merlo
class_name MerloP40

## Merlo P40 telehandler — high-detail variant built from the imported FBX in
## res://assets/models/merlo_p40/. The FBX ships with named sub-meshes per
## body part (Cabine, Capot, Carrosserie 1/2/3, Porte, Vitre, Volant, Roue×4,
## Essui glace, Girophare, Tableau de bord, Siege, …) plus a full PBR
## texture set in textures/.
##
## INHERITS FROM Merlo (not BaseVehicle) so all the boom hydraulics —
## R/F raise-lower, T/G extend-retract, Z/C bucket curl, V/B grapple — flow
## through unchanged. _wire_articulation() finds the FBX's Carrosserie 2/3
## sub-meshes and points _boom_pivot / _boom_extend at them.
##
## RUNTIME WIRING:
##  • Roue×4: visual wheels reparented under each VehicleWheel3D AND local
##    transform zeroed, so the FBX origin's elevation doesn't put the wheels
##    "on top of the machine" (the bug the operator hit on the first build).
##  • Vitre×N: glass meshes get an alpha-blended material so the operator
##    actually sees through the windscreen from inside the cabin.
##  • Porte: hinged door — required to be OPEN before the operator can board.
##    Press E on the door (on foot, proximity prompt) to toggle open/closed.
##  • Essui glace: front blade pivots from its bottom; rear blade has a
##    smaller sweep amplitude. `vehicle_wipers` (Y) toggles on/off — default OFF.
##  • Girophare: amber strobe spins around its own Y.
##  • Volant: steering wheel mirrors chassis steer.
##  • Cabine: CabCamera is moved INSIDE the cabin's bounding box on load so
##    the operator's eye-line lands behind the windshield, not on top of the
##    boom.
##
## EDITOR-IMPORT REQUIREMENT: Godot can't load a raw FBX at runtime — the
## editor has to ingest it once to generate the .scn cache + .import file.
## Until that happens, the model fails to load and this script falls back to
## a tiny "[MerloP40] FBX not imported yet" warning + a placeholder bounding
## box, so the rest of the game keeps working.

const FBX_PATH := "res://assets/models/merlo_p40/Merlo.fbx"

# Names we look for when walking the FBX tree (case-insensitive substring).
# French because the source pack labels its parts in French.
# Boom-like meshes use Carrosserie 2/3 by convention in this pack; we also
# accept English/Italian/French aliases just in case the FBX got renamed.
const PART_NAMES := {
	# The REAL boom is the "Rampe" telescoping assembly, NOT a Carrosserie panel
	# (those are the body — confirmed in-game: rotating Carrosserie_2 lifted half
	# the chassis while the actual arm stood still). "interior" comes before the
	# generic "carrosserie" chassis catch-all so Carrosserie_Inte isn't swallowed.
	# _classify() returns on the first matching category, so order is load-bearing.
	"boom":      ["rampe", "bras", "fleche", "flèche", "boom", "telescope"],
	"boom_ext":  ["extension"],
	"interior":  ["carrosserie_inte", "carosserie_inte", "interieur", "intérieur", "tableau", "siege", "siège"],
	"chassis":   ["carrosserie", "carosserie"],
	"cabin":     ["cabine"],
	"hood":      ["capot"],
	"glass":     ["vitre"],
	"wheel":     ["roue"],
	"axle":      ["essieu"],
	"door":      ["porte"],
	"wiper_f":   ["essui glace front", "essui front", "essui glace avant", "essui avant"],
	"wiper_r":   ["essui glace rear", "essui rear", "essui glace arriere", "essui arriere"],
	"wiper":     ["essui"],   # generic fallback — comes AFTER front/rear above
	"beacon":    ["girophare"],
	"steering":  ["volant"],
	"grille":    ["grille"],
	# Fork carriage / pallet-tablier sub-meshes — get HIDDEN once the procedural
	# grapple bucket is mounted (P40 ships with forks; CeDo runs it with a
	# basket+clamp like the other Merlo). Order: must come before generic
	# fallbacks so a "fourche_tablier" gets pinned here, not "chassis".
	"fork":      ["fork", "fourche", "tablier", "carriage", "pallet"],
	"misc":      ["autre", "vis"],
}

# Discovered parts (filled by _load_and_classify) — name → Array[Node3D]
var _parts : Dictionary = {}

# Articulated handles cached for per-frame motion.
var _door_pivot      : Node3D = null
var _boom_sections   : Array  = []     # telescoping boom sections [{node, rest}]; inner slides furthest
var _wiper_pivots_front : Array  = []
var _wiper_pivots_rear  : Array  = []
var _beacon_node     : Node3D = null
var _steering_node   : Node3D = null
var _door_open_deg   : float  = 0.0
var _door_target_deg : float  = 0.0
var _wiper_phase     : float  = 0.0
var wipers_on        : bool   = false
const DOOR_OPEN_DEG : float = 75.0
const WIPER_RATE    : float = 3.5  # rad/s
const DOOR_OPEN_THRESHOLD : float = 25.0   # door must be at least 25° open to board
const BOOM_EXTEND_MAX_M : float = 6.0      # #201 — matches Merlo.gd extend_max_m (P40.17 ~7 m reach)

# Door interaction (on-foot proximity prompt + E to toggle)
var _door_trigger    : Area3D = null
var _player_near_door: bool   = false
var _player_node     : Node   = null

# =============================================================================
func _ready() -> void:
	# Merlo._ready() sets boom_min/max + bucket/grapple defaults + calls
	# BaseVehicle._ready (which builds the lights/audio aux). After it returns
	# we restore vehicle_type (Merlo overwrites to "merlo") and then load the FBX.
	super._ready()
	vehicle_type = "merlo_p40"
	all_wheel_steer = true
	_ensure_p40_actions()
	_load_and_classify()

## Register the wipers-toggle action (Y) at runtime — same fallback trick the
## HUD uses elsewhere, since the saved InputMap might be stale.
func _ensure_p40_actions() -> void:
	if not InputMap.has_action("vehicle_wipers"):
		InputMap.add_action("vehicle_wipers")
		var k := InputEventKey.new()
		k.keycode = KEY_Y
		InputMap.action_add_event("vehicle_wipers", k)

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	# Wipers toggle — only while occupied.
	if occupied and event.is_action_pressed("vehicle_wipers"):
		wipers_on = not wipers_on
		# Snap wipers back to rest position when turning OFF.
		if not wipers_on:
			for p in _wiper_pivots_front:
				(p as Node3D).rotation.z = 0.0
			for p in _wiper_pivots_rear:
				(p as Node3D).rotation.z = 0.0
		get_viewport().set_input_as_handled()

## Try to instantiate the FBX. If it isn't imported yet, leave a placeholder.
func _load_and_classify() -> void:
	if not ResourceLoader.exists(FBX_PATH):
		push_warning("[MerloP40] %s not imported yet — open project in editor once." % FBX_PATH)
		_install_placeholder()
		return
	var scn := load(FBX_PATH) as PackedScene
	if scn == null:
		push_warning("[MerloP40] %s loaded but not a PackedScene — placeholder." % FBX_PATH)
		_install_placeholder()
		return
	var root := scn.instantiate() as Node3D
	if root == null:
		push_warning("[MerloP40] %s instantiate() returned null." % FBX_PATH)
		_install_placeholder()
		return
	# Mount the imported visual tree under us, then walk it to classify parts.
	add_child(root)
	root.name = "MerloMesh"
	for n in _walk(root):
		_classify(n)
	# Measure how far the FBX's lowest visual point (the tyres) sits below the
	# vehicle origin BEFORE articulation reparents the wheels out of MerloMesh.
	# The FBX origin sits ~2 m above the wheel contact, so without this the whole
	# machine spawns buried in the floor.
	var visual_lift : float = -_subtree_aabb_local(root).position.y
	_wire_articulation()
	# Lift the body (+ boom + door, still under MerloMesh) so it sits at its proper
	# ground clearance. The wheels were reparented out + seated on the floor in
	# _articulate_wheels, so they keep their own (correct) height.
	if visual_lift > 0.01:
		root.position.y += visual_lift
	print("[MerloP40] loaded — parts: %s (visual_lift=%.2f)" % [str(_parts.keys()), visual_lift])
	# Dump the full mesh node tree so we can map the EXACT FBX node names for
	# the telescope/boom wiring (#142). Tells us whether the boom + extension
	# meshes are 'Carrosserie 2/3' or something else — needed to fix T/G extend.
	print("[MerloP40] FBX mesh nodes:")
	for n in _walk(root):
		if n is MeshInstance3D:
			print("    %s" % n.name)

func _walk(n: Node) -> Array:
	var out : Array = []
	out.append(n)
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _classify(n: Node) -> void:
	if not (n is Node3D):
		return
	var name_l := n.name.to_lower()
	# Iteration order matters: front/rear wiper categories live BEFORE the
	# generic "wiper" fallback so a matching name gets pinned to the specific
	# pivot list instead of the generic pool.
	for category in PART_NAMES:
		for needle in PART_NAMES[category]:
			if name_l.contains(needle):
				var arr : Array = _parts.get(category, [])
				arr.append(n)
				_parts[category] = arr
				return

## Cache handles + add the small bits of physics/animation each articulated
## part needs. Static visuals (chassis / cabin / glass / etc.) are left alone.
func _wire_articulation() -> void:
	_articulate_door()
	_articulate_wipers()
	_articulate_beacon_and_steering()
	_articulate_wheels()
	_articulate_glass()
	_articulate_boom()
	_reposition_cab_camera()

func _articulate_door() -> void:
	if not _parts.has("door") or (_parts["door"] as Array).is_empty():
		return
	# The cab door is modelled as TWO stacked leaves at the SAME x/z — "Portes_2"
	# (lower) and "Portes_1" (upper). There is ALSO a separate solid panel named
	# exactly "Porte" which is NOT the door (it's a body piece) — earlier we
	# grabbed that by mistake. Take both "portes" leaves (plural, with the 's')
	# and group them under ONE pivot so the whole door swings as a single piece.
	var leaves : Array = []
	for nd in _parts["door"]:
		var n3 := nd as Node3D
		if n3 != null and n3.name.to_lower().contains("portes"):
			leaves.append(n3)
	if leaves.is_empty():
		return
	var anchor : Node3D = leaves[0]
	# Vertical-Y hinge — the lower leaf moved acceptably this way before; we now
	# also bring the upper leaf along on the same pivot.
	_door_pivot = _wrap_pivot(anchor, Vector3.UP, 0.45)
	if _door_pivot == null:
		return
	# Adopt the remaining leaves into the same pivot, preserving world transform
	# so they swing together with the anchor (one solid door, not split halves).
	for i in range(1, leaves.size()):
		var leaf : Node3D = leaves[i]
		var w : Transform3D = leaf.global_transform
		if leaf.get_parent():
			leaf.get_parent().remove_child(leaf)
		_door_pivot.add_child(leaf)
		leaf.global_transform = w
	# Proximity trigger so the player gets an "Open door / Close door" prompt
	# when they walk up to it on foot — E toggles the door.
	_door_trigger = Area3D.new()
	_door_trigger.name = "DoorTrigger"
	_door_trigger.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = 1.6
	cs.shape = sp
	_door_trigger.add_child(cs)
	anchor.add_child(_door_trigger)
	_door_trigger.body_entered.connect(_on_door_body_entered)
	_door_trigger.body_exited.connect(_on_door_body_exited)

func _articulate_wipers() -> void:
	# Front + rear wipers wrapped with a DOWN-axis pivot so the rotation axis
	# is at the BASE of the blade (windscreen mount) — fixes the front wiper
	# pivoting around its centre of mass.
	if _parts.has("wiper_f"):
		for w in _parts["wiper_f"]:
			var p := _wrap_pivot(w as Node3D, Vector3.DOWN, 0.15)
			if p != null:
				_wiper_pivots_front.append(p)
	if _parts.has("wiper_r"):
		for w in _parts["wiper_r"]:
			var p := _wrap_pivot(w as Node3D, Vector3.DOWN, 0.12)
			if p != null:
				_wiper_pivots_rear.append(p)
	# Generic "essui" fallback — only catches wiper meshes whose names DON'T
	# include front/rear keywords (since _classify returns on first match and
	# wiper_f / wiper_r are tested before the generic "wiper", there's no
	# overlap with the lists above — no dedup needed). Sort each into front/rear
	# by world Z. Canonical CeDo direction: forward = -Z, so the BOOM/FRONT
	# side sits at NEGATIVE world Z relative to the body centre, and the REAR
	# (cab counterweight) sits at POSITIVE Z.
	if _parts.has("wiper"):
		for w in _parts["wiper"]:
			var wn := w as Node3D
			var pivot := _wrap_pivot(wn, Vector3.DOWN, 0.15)
			if pivot == null:
				continue
			if wn.global_position.z <= global_position.z:
				_wiper_pivots_front.append(pivot)
			else:
				_wiper_pivots_rear.append(pivot)

func _articulate_beacon_and_steering() -> void:
	if _parts.has("beacon") and not (_parts["beacon"] as Array).is_empty():
		_beacon_node = (_parts["beacon"] as Array)[0] as Node3D
		# Reset any degenerate/singular FBX-imported transform BEFORE handing the
		# node to BaseVehicle's per-frame `rotation.y +=` spin. A zero-scale or
		# NaN basis here propagates into every rotation update and the renderer
		# floods is_finite() errors. Identity is safe because the part's
		# meaningful pose comes from its position under the chassis, not its
		# scale/basis.
		if _beacon_node != null:
			var b := _beacon_node.transform.basis
			if not (b.x.is_finite() and b.y.is_finite() and b.z.is_finite()) \
					or b.determinant() < 1e-6:
				_beacon_node.transform.basis = Basis()
			_beacons.append(_beacon_node)
	if _parts.has("steering") and not (_parts["steering"] as Array).is_empty():
		_steering_node = (_parts["steering"] as Array)[0]

func _articulate_wheels() -> void:
	if not _parts.has("wheel"):
		return
	var wheels : Array = _parts["wheel"]
	var vwheels : Array = []
	for c in get_children():
		if c is VehicleWheel3D:
			vwheels.append(c)
	# Sort wheels by which VW3D they're closest to in WORLD XZ, then re-parent
	# AND ZERO the local transform — that's the fix for "wheels on top of the
	# machine." Before, we preserved the world transform, so a wheel at FBX-
	# origin's high Y stayed at high Y; now it lands at the VW3D anchor.
	for w in wheels:
		var wn := w as Node3D
		var best : VehicleWheel3D = null
		var best_d := 1e9
		for vw in vwheels:
			var d : float = (vw as Node3D).global_position.distance_to(wn.global_position)
			if d < best_d:
				best_d = d
				best = vw
		if best == null:
			continue
		if wn.get_parent():
			wn.get_parent().remove_child(wn)
		best.add_child(wn)
		wn.transform = Transform3D.IDENTITY    # ← snap to the VW3D anchor
		# Hide the procedural cylinder fallback mesh under each VW3D so we
		# don't draw two wheels stacked.
		var proc_mesh := best.get_node_or_null("WheelMesh")
		if proc_mesh:
			(proc_mesh as Node3D).visible = false
	# Second pass: the reparented FBX wheels sit ~2 m below the contact (their tyre
	# meshes carry a big internal offset, so zeroing the Roue node leaves the tyre
	# buried). Drop each so its tyre BOTTOM rests at the wheel contact (body-local
	# y = 0 = floor). Done AFTER the reparent loop so nested Roue nodes are already
	# split across their VW3Ds and each subtree is just its own tyre.
	for vw in vwheels:
		for child in (vw as Node3D).get_children():
			if child is VehicleWheel3D or String(child.name) == "WheelMesh" or not (child is Node3D):
				continue
			var ab : AABB = _subtree_aabb_local(child as Node3D)
			if ab.size.y > 0.0001:
				(child as Node3D).position.y = -(vw as Node3D).position.y - ab.position.y

func _articulate_glass() -> void:
	if not _parts.has("glass"):
		return
	for g in _parts["glass"]:
		var gm := g as MeshInstance3D
		if gm == null or gm.mesh == null:
			continue
		# Clone the existing surface material (so we don't mutate the imported
		# shared resource) and switch it to alpha-blended translucent glass.
		var surf_count := gm.mesh.get_surface_count()
		for i in surf_count:
			var base_mat := gm.mesh.surface_get_material(i)
			var mat : StandardMaterial3D
			if base_mat is StandardMaterial3D:
				mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
				mat.albedo_color = Color(0.78, 0.84, 0.88)
			# Make it glassy
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var c := mat.albedo_color
			c.a = 0.30
			mat.albedo_color = c
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.metallic = 0.10
			mat.roughness = 0.08
			gm.set_surface_override_material(i, mat)

## Wire the boom. The REAL boom on this FBX is the "Rampe" assembly — a parent
## node hinged at the REAR of the machine with nested telescoping sections
## (Rampe_1/2/3) plus the fork carriage. We rotate the Rampe parent about its own
## origin for elevation (Merlo.gd drives _boom_pivot.rotation.x via R/F) and slide
## the inner sections for telescoping (in _process, via extend_m). The Carrosserie
## meshes are the BODY and stay static — rotating Carrosserie_2 lifted half the
## chassis while the real arm stood still (operator-reported).
func _articulate_boom() -> void:
	if not _parts.has("boom") or (_parts["boom"] as Array).is_empty():
		return
	var pivot : Node3D = null
	var sections : Array = []
	for nd in _parts["boom"]:
		var n3 := nd as Node3D
		if n3 == null:
			continue
		if n3.name.to_lower() == "rampe":
			pivot = n3                      # assembly root = the rear hinge
		elif n3 is MeshInstance3D:
			sections.append(n3)             # telescoping sections + fork carriage
	# Fallback: if there's no bare "Rampe" parent, hinge on the sections' parent.
	if pivot == null and not sections.is_empty():
		pivot = (sections[0] as Node3D).get_parent() as Node3D
	if pivot == null:
		return
	# Merlo.gd rotates _boom_pivot.rotation.x for elevation. The Rampe node's
	# origin already sits at the rear hinge, so we rotate it in place (no wrap).
	_boom_pivot = pivot
	# Order sections REAR→FRONT by world position along the boom. The rear base
	# stays put; the tip / fork carriage extends FURTHEST. (Sorting by width was
	# wrong — the wide front carriage looked like a base and barely moved, so the
	# arm "overtook" the forks. Operator: the forks moved ~3× too slow.)
	var infos : Array = []
	for s in sections:
		infos.append({"node": s, "z": _world_aabb_center_z(s as Node3D)})
	infos.sort_custom(func(a, b): return a["z"] < b["z"])
	_boom_sections.clear()
	var m : int = infos.size()
	for i in m:
		var weight : float = float(i) / float(max(m - 1, 1))   # rear base = 0 (fixed), front carriage = 1 (full travel)
		_boom_sections.append({"node": infos[i]["node"], "rest": (infos[i]["node"] as Node3D).position, "w": weight})
	print("[MerloP40] boom = '%s' (%d telescoping sections, rear→front weighted)" % [pivot.name, _boom_sections.size()])
	# No _boom_extend: base Merlo.gd's single-node slide is skipped; _process()
	# does the multi-section telescope. The FBX ships with a fork carriage; CeDo
	# runs the P40 with a basket+clamp like the other Merlo (per operator's spec).
	# Hide the FBX forks and mount a procedural bucket+grapple on the boom tip.
	_hide_fbx_forks()
	_install_basket_clamp()

## Hide every FBX sub-mesh classified as "fork" so the procedural bucket/clamp
## is the only visible attachment on the boom tip.
func _hide_fbx_forks() -> void:
	if not _parts.has("fork"):
		return
	for nd in _parts["fork"]:
		var n3 := nd as Node3D
		if n3 != null:
			n3.visible = false

## Mount a procedural grapple-bucket on the front-most (innermost) boom section
## of the FBX telescope. Dimensions cloned from Merlo.tscn so this P40 ends up
## with the SAME visible attachment as the standard Merlo, and the base Merlo
## script's _apply_boom() drives BOTH the bucket-curl (Z/C) and the grapple
## clamp (V/B) without modification.
##
## Frame: the frontmost boom section is a MeshInstance3D whose local origin
## sits at the boom-tip pivot. We parent the bucket-tilt at that origin with a
## small forward offset so it visually overhangs the section's tip.
func _install_basket_clamp() -> void:
	if _boom_sections.is_empty():
		return
	var tip : Node3D = _boom_sections[-1]["node"] as Node3D
	if tip == null:
		return
	# Compute the tip section's local AABB so we know where its forward face is.
	var tip_aabb : AABB = _subtree_aabb_local(tip)
	# The bucket should hang BELOW the section tip and a touch forward of it.
	# These offsets match the base Merlo's BucketTilt local transform
	# (0.62, -0.15, 5.0 in that scene's BoomExtend frame). For P40 the section
	# IS the tip, so we just push slightly forward of the AABB centre.
	var tip_z : float = tip_aabb.position.z + tip_aabb.size.z
	# Materials — colours match base Merlo's Mat_grapple_red / Mat_steel / Mat_dark.
	var mat_red   := StandardMaterial3D.new()
	mat_red.albedo_color = Color(0.78, 0.10, 0.12); mat_red.roughness = 0.55; mat_red.metallic = 0.20
	var mat_steel := StandardMaterial3D.new()
	mat_steel.albedo_color = Color(0.62, 0.65, 0.68); mat_steel.roughness = 0.45; mat_steel.metallic = 0.70
	var mat_dark  := StandardMaterial3D.new()
	mat_dark.albedo_color = Color(0.20, 0.20, 0.22); mat_dark.roughness = 0.65; mat_dark.metallic = 0.40
	# BucketTilt body — rotated by curl_deg from Merlo._apply_boom(). #201 makes
	# it a real AnimatableBody3D with sync_to_physics so loads sit in the bowl
	# via contact, not by being parented to it.
	var bucket := AnimatableBody3D.new()
	bucket.name = "BucketTilt_P40"
	bucket.position = Vector3(0.0, -0.15, tip_z + 0.30)
	bucket.sync_to_physics = true
	bucket.collision_layer = 1
	bucket.collision_mask  = 1
	tip.add_child(bucket)
	# Headstock + ribs: visual only (mount bracket / inside-bowl ribs — no useful
	# load contact, so no collision sibling).
	_p40_box(bucket, "Headstock",   Vector3(1.5, 0.6, 0.18),  Vector3( 0.0,  0.00, -0.18), mat_dark, false)
	_p40_box(bucket, "BucketBottom",Vector3(1.9, 0.1, 1.05),  Vector3( 0.0, -0.45,  0.38), mat_red,  true)
	_p40_box(bucket, "BucketBack",  Vector3(1.9, 0.6, 0.1),   Vector3( 0.0, -0.18, -0.12), mat_red,  true)
	var rib_size := Vector3(0.06, 0.16, 1.0)
	var rib_y    : float = -0.36
	var rib_z    : float =  0.40
	for i in range(5):
		var rx : float = (-0.6) + 0.3 * i
		_p40_box(bucket, "Rib%d" % (i + 1), rib_size, Vector3(rx, rib_y, rib_z), mat_red, false)
	_p40_box(bucket, "BucketLeft", Vector3(0.09, 0.55, 1.05), Vector3(-0.9, -0.18, 0.38), mat_red,   true)
	_p40_box(bucket, "BucketRight",Vector3(0.09, 0.55, 1.05), Vector3( 0.9, -0.18, 0.38), mat_red,   true)
	_p40_box(bucket, "BucketLip",  Vector3(1.9, 0.06, 0.18),  Vector3( 0.0, -0.47, 0.90), mat_steel, true)
	# GrappleArm body — rotated by grapple_deg from Merlo._apply_boom() (V/B clamp).
	var grapple := AnimatableBody3D.new()
	grapple.name = "GrappleArm_P40"
	grapple.position = Vector3(0.0, 0.12, -0.05)
	grapple.sync_to_physics = true
	grapple.collision_layer = 1
	grapple.collision_mask  = 1
	bucket.add_child(grapple)
	_p40_box(grapple, "ArmBar", Vector3(1.55, 0.12, 0.14), Vector3.ZERO, mat_steel, true)
	var tine_size := Vector3(0.06, 0.5, 0.62)
	for i in range(5):
		var tx : float = (-0.62) + 0.31 * i
		_p40_box(grapple, "Tine%d" % (i + 1), tine_size, Vector3(tx, -0.20, 0.34), mat_steel, true)
	# Hand the new nodes to the base Merlo script. The inherited _apply_boom()
	# rotates them every frame; Merlo._ready (called via super) already set the
	# PhysicsMaterial overrides for friction.
	_bucket_tilt = bucket
	_grapple_arm = grapple

## Helper: spawn a BoxMesh at `pos` with `size`, parented under `parent`.
## If `solid` is true, also add a matching CollisionShape3D sibling so the
## kinematic body around `parent` actually carries that piece's collision.
func _p40_box(parent: Node3D, n: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D, solid: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if solid:
		var col := CollisionShape3D.new()
		col.name = n + "_Col"
		var sh := BoxShape3D.new()
		sh.size = size
		col.shape = sh
		col.position = pos
		parent.add_child(col)
	return mi

## Move CabCamera into the actual cabin interior — its tscn default of
## (0, 2.1, -0.3) puts the eye-line above the machine. We use the Cabine
## bounding box centre as the seat anchor and offset slightly forward + up to
## the operator's natural eye position.
func _reposition_cab_camera() -> void:
	if not _parts.has("cabin") or (_parts["cabin"] as Array).is_empty():
		return
	var cabin : Node3D = (_parts["cabin"] as Array)[0]
	var aabb := _approx_aabb(cabin)
	if aabb.size == Vector3.ZERO:
		return
	var centre := cabin.global_position + aabb.position + aabb.size * 0.5
	# Move CabCamera (which lives under the root) to roughly the seat eye
	# point — centre but biased slightly forward + low so the operator sees
	# out the windshield rather than the dashboard.
	var cam := get_node_or_null("CabCamera") as Camera3D
	if cam == null:
		return
	var local_centre := to_local(centre)
	cam.position = local_centre + Vector3(0.0, 0.25, -0.10)

## Wrap `node`'s mesh under a Node3D pivot positioned at its bounding-box edge
## along `axis` (in node-local space). `cap` clamps the half-size shift so a
## wildly oversized AABB doesn't push the pivot kilometres away. Returns the
## pivot Node3D for the caller to rotate, or null if the wrap failed.
func _wrap_pivot(node: Node3D, axis: Vector3, cap: float = 1.0) -> Node3D:
	var parent := node.get_parent() as Node3D
	if parent == null:
		return null
	var pivot := Node3D.new()
	pivot.name = node.name + "_Pivot"
	pivot.transform = node.transform
	parent.add_child(pivot)
	parent.remove_child(node)
	pivot.add_child(node)
	node.transform = Transform3D.IDENTITY
	var aabb := _approx_aabb(node)
	var half := aabb.size * 0.5
	# Distance to shift the pivot — clamped against `cap` so a misclassified
	# huge AABB doesn't throw the pivot off into space.
	var shift : float = clampf(half.dot(axis), 0.0, cap)
	# When axis points DOWN, half.dot(DOWN) = -half.y (negative if size is
	# positive). Take absf to actually get a SHIFT magnitude.
	shift = clampf(absf(half.dot(axis)), 0.0, cap)
	pivot.position += axis * shift
	node.position -= axis * shift
	return pivot

func _approx_aabb(node: Node) -> AABB:
	var bb := AABB()
	var started := false
	for n in _walk(node):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var m_aabb := (n as MeshInstance3D).get_aabb()
			if not started:
				bb = m_aabb
				started = true
			else:
				bb = bb.merge(m_aabb)
	return bb

## World-space Z of a node's mesh-AABB centre — used to order the boom sections
## along the arm (rear → front).
func _world_aabb_center_z(node: Node3D) -> float:
	return (node.global_transform * _approx_aabb(node).get_center()).z

## Combined AABB of all of `node`'s mesh descendants expressed in `node`'s OWN
## local space (transform-aware — handles nested offsets/scales in the FBX, which
## _approx_aabb does not). Used to seat the wheels + lift the body correctly.
func _subtree_aabb_local(node: Node3D) -> AABB:
	var bb := AABB()
	var started := false
	var inv := node.global_transform.affine_inverse()
	for mi in _all_meshes(node):
		var a : AABB = (mi as MeshInstance3D).get_aabb()
		var xf : Transform3D = inv * (mi as Node3D).global_transform
		for ix in [0.0, 1.0]:
			for iy in [0.0, 1.0]:
				for iz in [0.0, 1.0]:
					var p : Vector3 = xf * (a.position + Vector3(a.size.x * ix, a.size.y * iy, a.size.z * iz))
					if not started:
						bb = AABB(p, Vector3.ZERO); started = true
					else:
						bb = bb.expand(p)
	return bb

func _all_meshes(node: Node) -> Array:
	var out : Array = []
	for c in node.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out

# =============================================================================
# DOOR — proximity prompt + E to toggle + can_enter gate
# =============================================================================
func _on_door_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near_door = true
	_player_node = body
	_refresh_door_prompt()

func _on_door_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near_door = false
	_player_node = null
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _refresh_door_prompt() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus == null or not bus.has_signal("interaction_prompt_show"):
		return
	var msg := "Close door" if _door_target_deg > 5.0 else "Open door"
	bus.emit_signal("interaction_prompt_show", self, msg)

## The OperatorContext checks this on E. If the door isn't open enough, refuse.
func can_enter() -> bool:
	# When the script's door pivot isn't wired (placeholder mode or missing
	# Porte), allow entry — operator shouldn't get locked out by a missing
	# asset.
	if _door_pivot == null:
		return true
	return _door_open_deg >= DOOR_OPEN_THRESHOLD

func enter_refusal_reason() -> String:
	return "Open the door first (E on the door)"

# =============================================================================
# PLACEHOLDER (when FBX isn't loadable yet — open project in editor once)
# =============================================================================
func _install_placeholder() -> void:
	var mark := MeshInstance3D.new()
	mark.name = "PlaceholderMesh"
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 2.0, 5.0)
	mark.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.45, 0.10)
	m.roughness = 0.6
	mark.material_override = m
	mark.position = Vector3(0, 1.2, 0)
	add_child(mark)

# =============================================================================
# PER-FRAME ANIMATION (wipers / beacon / steering wheel / door interpolation)
# =============================================================================
func _process(delta: float) -> void:
	# Wipers — only run while wipers_on is true. Front and rear get DIFFERENT
	# sweep curves: front uses a clean sine (broad sweep), rear uses a slower
	# half-amplitude sweep (real rear wipers have a shorter arc).
	if wipers_on:
		_wiper_phase += delta * WIPER_RATE
		var sweep_front := sin(_wiper_phase) * deg_to_rad(50.0)
		var sweep_rear  := sin(_wiper_phase * 0.7) * deg_to_rad(22.0)
		for p in _wiper_pivots_front:
			(p as Node3D).rotation.z = sweep_front
		for p in _wiper_pivots_rear:
			(p as Node3D).rotation.z = sweep_rear
	# Steering wheel mirrors the chassis steering. Sign matches Godot
	# VehicleWheel3D convention: positive `steering` (A pressed) = wheels left,
	# steering column rotates +Z (CCW from driver) = wheel held left.
	if _steering_node != null and "steering" in self:
		_steering_node.rotation.z = (self.steering as float) * 3.0
	# Door interpolates to its target angle. Once it passes the OPEN
	# threshold, can_enter() returns true.
	if _door_pivot != null:
		_door_open_deg = lerpf(_door_open_deg, _door_target_deg, clampf(delta * 4.5, 0.0, 1.0))
		_door_pivot.rotation.y = deg_to_rad(_door_open_deg)
	# Telescope the boom: slide each inner section forward along its local +Z by a
	# fraction of extend_m (outer sections move least, the innermost most). The
	# sections are children of the Rampe pivot, so they slide along the boom's axis
	# and inherit its elevation. `extend_m` (0..1-ish) comes from base Merlo's T/G.
	if _boom_sections.size() > 0:
		var frac : float = clampf(extend_m / maxf(extend_max_m, 0.0001), 0.0, 1.0)
		for sec in _boom_sections:
			var rest : Vector3 = sec["rest"]
			(sec["node"] as Node3D).position.z = rest.z + frac * BOOM_EXTEND_MAX_M * float(sec["w"])

# =============================================================================
# PUBLIC API — used by OperatorContext / interact hooks to open/close the door
# =============================================================================
func toggle_door() -> void:
	if _door_pivot == null:
		return
	_door_target_deg = 0.0 if _door_target_deg > 5.0 else DOOR_OPEN_DEG
	if _player_near_door:
		_refresh_door_prompt()

## Handle E on the door while the player is on foot near it. OperatorContext
## triggers vehicle entry via E on the EnterArea, but here we intercept the
## door-trigger Area3D's prompt + E first so the player can open the door.
## NOTE: we listen via _unhandled_input but only when _player_near_door is true.
func _input(event: InputEvent) -> void:
	if not _player_near_door:
		return
	if event.is_action_pressed("interact"):
		toggle_door()
		get_viewport().set_input_as_handled()
