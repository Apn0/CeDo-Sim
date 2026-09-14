extends Node3D

class_name ShiftCarSpawner

# =============================================================================
# #195 follow-up — Shift-start car spawning extracted from MainWorld.gd.
# =============================================================================
# Owns the shift-start car spawn pipeline (#155):
#   • Parks one NPC car per crew member with a real GLB asset in the staff lot.
#   • Spawns the player's red Suzuki Swift on the south end of De Asselen Kuil
#     so the operator can drive northbound into the parking turn.
#   • Seats Yasin (yassine) in the Swift's passenger seat.
#   • Boards the player into the driver seat via OperatorContext so the camera
#     takes the CabCamera straight away.
#   • Applies Pascal's body-only Y-squish (Streetka variant of the Ford Ka) as
#     a deferred call after the asset finishes loading.
#
# Coupled to NPC_DATA (lives on MainWorld until NPCSpawner extracts it) — we
# read it via the world reference so this module survives that future move
# without touching code here. Same pattern as ExteriorManager.gd:
# spawned children are parented under MainWorld (not under this manager) so
# the scene tree shape is identical to the pre-extract layout.

# =============================================================================
# Slot table — public so MainWorld's _position_cars_for_elapsed (still in
# MainWorld, not part of this extract) can read the same authoritative slots.
# =============================================================================
## Slot assignment matching the operator's Google Maps satellite of the lot.
## side: -1 = left row, +1 = right row. idx: 0 = north end, 9 = south end.
## Player Swift sits in right-row slot 2 (operator-identified in the photo).
const CAR_SLOTS : Dictionary = {
	"abdellilah": {"side": -1, "idx": 0},   # left row, slot 1 (Ka sunset orange)
	"emrah":      {"side": -1, "idx": 1},   # left row, slot 2 (Audi A3 sunroof)
	"mohammed":   {"side": -1, "idx": 2},   # left row, slot 3 (VW Golf)
	"vincent":    {"side": -1, "idx": 3},   # left row, slot 4 (Volvo V40 placeholder)
	"pascal":     {"side":  1, "idx": 0},   # right row, slot 1 (black Streetka)
	"romain":     {"side":  1, "idx": 1},   # right row, slot 2 (Hyundai i20 — Roman)
	"peter":      {"side":  1, "idx": 3},   # right row, slot 4 (BMW X1 placeholder)
	# Player Swift: right row, slot 3 (operator's car)
	# Vincent / Pascal / Peter: GLB assets pending — slots reserved when those land.
}
const PLAYER_SWIFT_SLOT : Dictionary = {"side": 1, "idx": 2}

# #155 — Player's car. Swift goes to the player; Yasin (yassine) rides shotgun.
const PLAYER_CAR_SCENE : String = "res://src/scenes/vehicles/cars/SuzukiSwiftGLX.tscn"

# Reference back to MainWorld for canonical helpers + NPC_DATA + spawned-node
# parenting. Set when the manager is added to the tree (its parent IS MainWorld)
# and also by setup() so the caller can pass an explicit world reference if
# this module is ever re-parented.
var _world : Node = null

# Setup-supplied references (mirror the MainWorld locals the original
# functions closed over).
var _staff_parking : Node = null
var _npcs : Dictionary = {}
var _operator_context : Node = null
var _player : Node = null
var _player_spawn_pos : Vector3 = Vector3.ZERO

func _ready() -> void:
	if _world == null:
		_world = get_parent()

## Hand-off from MainWorld: store the references the original functions used
## to read out of MainWorld's own state, then run the spawn pipeline.
## #audit-H5 — guard: a mid-shift resume must NOT re-run the shift-start
## pipeline (parking lot is already filled from the original boot; a second
## call spawns duplicate NPC cars AND a second Swift on the road). Only run
## on a TRUE shift-start (shift_elapsed < 0 still counting down, i.e.
## is_pre_shift() == true on the ShiftClock). Shifted saves skip this block
## and rely on the saved vehicle positions instead.
func setup(world: Node, staff_parking: Node, npcs: Dictionary,
		operator_context: Node, player: Node, player_spawn_pos: Vector3,
		shift_clock: Node = null) -> void:
	_world = world
	_staff_parking = staff_parking
	_npcs = npcs
	_operator_context = operator_context
	_player = player
	_player_spawn_pos = player_spawn_pos
	# #H5 — skip on resume: if a ShiftClock is provided and the shift has
	# already started (elapsed >= 0), the cars were already spawned at the
	# original boot. Re-running would duplicate them.
	if shift_clock != null and shift_clock.has_method("is_pre_shift"):
		if not bool(shift_clock.is_pre_shift()):
			print("[ShiftCarSpawner] #H5 resumed mid-shift — skipping car spawn (already parked)")
			return
	_spawn_shift_cars_and_player_drive_in()


func _spawn_shift_cars_and_player_drive_in() -> void:
	if _staff_parking == null:
		push_warning("[ShiftCarSpawner] #155: staff_parking missing — cars not spawned")
		return
	# (B) NPC cars — one per NPC that has an asset, parked in their satellite slot.
	var spawned_cars : int = 0
	var missing_assets : Array = []
	var npc_data : Dictionary = _world.NPC_DATA
	for npc_id in npc_data.keys():
		var data : Dictionary = npc_data[npc_id]
		var car_path : String = String(data.get("car", ""))
		if car_path == "" or car_path == "passenger:player":
			# All 7 NPC cars have asset paths now (real GLB or placeholder).
			# Missing-asset tracking kept for any future additions.
			continue
		if not CAR_SLOTS.has(npc_id):
			continue
		var slot : Dictionary = CAR_SLOTS[npc_id]
		_spawn_car_in_bay(car_path, int(slot["side"]), int(slot["idx"]),
			"%s's car" % String(data["name"]), String(npc_id))
		spawned_cars += 1
	# (D) Player's Swift on the south end of De Asselen Kuil, facing north
	# (so the operator drives forward into the lot). Parked alongside the
	# road's south waypoint anchor + spawn_pos offset.
	var swift : Node3D = _spawn_player_swift_on_road()
	# (C) Yasin in the Swift's passenger seat.
	if swift != null and _npcs.has("yassine"):
		var yasin : Node3D = _npcs["yassine"] as Node3D
		if yasin != null and swift.has_method("seat_passenger"):
			swift.call("seat_passenger", yasin)
	# Programmatic boarding — put the player in the driver seat so they
	# start the shift sitting in the car (per #155 spec). Uses
	# OperatorContext.enter_interactable_vehicle so the camera takes the
	# CabCamera and the player gets the throttle/steer inputs straight away.
	if swift != null and _player != null:
		if _operator_context and _operator_context.has_method("enter_interactable_vehicle"):
			_operator_context.call("enter_interactable_vehicle", swift)
		elif swift.has_method("get_boarding_position"):
			# Fallback: teleport the player next to the driver door so they
			# can board with E themselves. Not autopilot, just positioning.
			_player.global_position = swift.call("get_boarding_position")
	print("[ShiftCarSpawner] #155 shift-start: %d NPC cars in lot, player in Swift on road, %d assets missing (%s)" \
		% [spawned_cars, missing_assets.size(), str(missing_assets)])

func _spawn_car_in_bay(scene_path: String, side: int, idx: int, label: String, npc_id: String = "") -> Node3D:
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_warning("[ShiftCarSpawner] #155: car scene missing: %s" % scene_path)
		return null
	var car : Node3D = ps.instantiate() as Node3D
	if car == null:
		return null
	_world.add_child(car)
	
	car.set_meta("display_label", label)
	if npc_id != "":
		car.set_meta("npc_id", npc_id)

	# Setup target bay
	var bay_xf = _staff_parking.bay_world_transform(side, idx)
	
	# Spawn down the road instead of instantly in the bay
	# We use the _player_spawn_pos but offset backwards further down De Asselen Kuil
	var by : float = _world.call("_world_yaw")
	var rot := Basis(Vector3.UP, by)
	
	# Stagger them so they don't spawn inside each other
	var spawn_z_offset = -60.0 - (idx * 15.0) - (0.0 if side == -1 else 7.5) 
	car.global_transform.basis = rot
	car.global_position = _player_spawn_pos + rot * Vector3(0, -0.7, spawn_z_offset)
	
	if npc_id == "pascal":
		call_deferred("_apply_pascal_body_squish", car)
		
	# Instead of instantly freezing in bay, instruct it to drive
	if car.has_method("ai_drive_to_bay"):
		car.ai_drive_to_bay(bay_xf)
		
	return car

## Wrap a parked car in a StaticBody3D box sized from its visible AABB, so rays
## (F10 feedback, build-mode placement, interaction) and the player capsule both
## stop at it. Deferred: the GLB is loaded asynchronously, so the AABB is only
## meaningful after the model subtree exists.
func _add_parked_collider(car: Node3D) -> void:
	if car == null or not is_instance_valid(car):
		return
	if car.get_node_or_null("ParkedCollider") != null:
		return
	var aabb := _visual_aabb(car)
	if aabb.size == Vector3.ZERO:
		return
	var body := StaticBody3D.new()
	body.name = "ParkedCollider"
	# DEDICATED LAYER 20, not layer 1. On layer 1 these colliders regressed the
	# world round-trip (14 ok/0 fail -> 13/1, machines drifting 5.8-8.9 m and the
	# amount varying per run): extra static bodies in the car park perturb how the
	# placed machines settle before the save. Layer 20 is masked by nobody, so
	# nothing collides with them — but a query ray with mask 0xFFFFFFFF (the F10
	# feedback ray, PlayerController._feedback_context) still hits them, which is
	# all that is needed to make markers land ON the car.
	body.collision_layer = 1 << 19
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	cs.shape = box
	cs.position = aabb.get_center()
	body.add_child(cs)
	car.add_child(body)

## Union of every GEOMETRY AABB under `root`, in root-local space.
##
## GEOMETRY, not every VisualInstance3D: Light3D also extends VisualInstance3D
## and its AABB spans the light's REACH, not a body. BaseVehicle._build_lights
## gives each vehicle head/work spots at spot_range 22 m plus a 14 m reverse
## beam, so the old union produced a ParkedCollider box measured at
## 28.2 x 32.6 x 44.3 m centred ~17 m BELOW grade — a 50 m phantom around every
## parked car. It sits on the query-only layer so nothing bumps into it, but any
## sweep that probes all layers still hits it, including the F10 feedback ray and
## BuildMode's vehicle-clearance sentinel (BuildMode.gd:1100-1106 probes every
## layer deliberately, to see query-only bodies). A clearance gate that trips on
## a phantom 25 m away is worse than no gate.
func _visual_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var seen := false
	var stack : Array[Node] = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		if (n is MeshInstance3D or n is MultiMeshInstance3D) and n != root:
			var vi := n as VisualInstance3D
			var local := root.global_transform.affine_inverse() * vi.global_transform
			var a := local * vi.get_aabb()
			out = a if not seen else out.merge(a)
			seen = true
		for c in n.get_children():
			stack.append(c)
	return out if seen else AABB()

## Pascal's Ford Ka rides lower than Abdellilah's — squish the imported GLB
## body subtree on Y only. Wheels live under VehicleWheel3D nodes (siblings of
## the body), so they stay perfectly round.
##
## CRITICAL: target the IMPORTED MODEL ROOT (child of FrontAxisCorrection), not
## the wrap itself. Car.load_model() inserts a FrontAxisCorrection Node3D with
## rotation.y = PI (Car.gd:252-257) so the asset's visible front lands on -Z.
## Writing a non-uniform scale to that wrap reads its current Node3D.scale via
## basis decomposition — with a 180° yaw baked in, the decomposition can encode
## the rotation as negative X/Z scale and the requested Y=0.85 ends up smeared
## onto X/Z when re-composed, tipping the car onto its side. Instead, drill
## into the wrap's child (the actual GLB root) and apply the squish there in
## its OWN local frame using Transform3D.basis.scaled() — which acts as a pure
## column-scaling of the basis, with no decomposition step.
func _apply_pascal_body_squish(car: Node3D) -> void:
	if car == null or not is_instance_valid(car):
		return
	# Target only the FrontAxisCorrection wrap by name. If load_model() didn't
	# create one (asset not imported, or subclass opted out via
	# _model_front_axis_correction_deg = 0), warn once and skip.
	var car_wrap := car.get_node_or_null("FrontAxisCorrection") as Node3D
	if car_wrap == null:
		push_warning("[ShiftCarSpawner] Pascal squish: FrontAxisCorrection wrap missing on %s — skipped (model not imported?)" % car.name)
		return
	# Apply Y-shrink to the IMPORTED GLB root (the wrap's only child), in ITS
	# local frame, so the 0.85 factor hits the asset's true vertical axis
	# regardless of the wrap's 180° yaw. Use Transform3D.basis.scaled()
	# directly to bypass the Node3D.scale decomposition pathway, which can
	# encode 180°-Y as negative X/Z scale and smear the non-uniform factor
	# onto the wrong axis.
	for body in car_wrap.get_children():
		if body is Node3D:
			var n : Node3D = body
			var t : Transform3D = n.transform
			t.basis = t.basis.scaled(Vector3(1.0, 0.85, 1.0))
			n.transform = t
			break  # only the top-level imported model root

## Player's red Suzuki Swift parked on De Asselen Kuil at the south end,
## facing NORTH so a forward drive brings the operator straight into the lot.
func _spawn_player_swift_on_road() -> Node3D:
	var ps := load(PLAYER_CAR_SCENE) as PackedScene
	if ps == null:
		push_warning("[ShiftCarSpawner] #155: SuzukiSwiftGLX.tscn missing")
		return null
	var swift : Node3D = ps.instantiate() as Node3D
	if swift == null:
		return null
	_world.add_child(swift)
	# Park at the FAR south end of De Asselen Kuil (the new ~440 m south
	# waypoint). Gives the operator a long clear approach northbound before
	# the east turn into the lot — what was missing was distance.
	# Position offset is expressed in BALE-YARD-CONVENTION local space
	# (canonical +Z = "north" along the road) and then rotated into world
	# coordinates by _world_yaw() so the Swift, the staff lot, and the
	# bale yards all share the same yaw convention. Matches StaffParking's
	# rotation.y = _world_yaw() at MainWorld.gd:2443.
	var anchor : Vector3 = _player_spawn_pos
	var by : float = _world.call("_world_yaw")
	# #221-PC Phase 5 — Swift parking position is now an operator-tunable PC
	# marker (WorldLayout.player_swift / player_swift_pc). When unset, falls
	# back to the Phase 3 default (458, 65) so existing saves keep their
	# current FAR-south-end Swift placement unchanged.
	const SWIFT_PC_DEFAULT := Vector2(458.0, 65.0)
	var swift_pc : Vector2 = SWIFT_PC_DEFAULT
	if WorldLayout.player_swift != Vector3.ZERO and WorldLayout.has_pc_data \
			and WorldLayout.player_swift_pc != Vector2.ZERO:
		swift_pc = WorldLayout.player_swift_pc
		print("[ShiftCarSpawner] Swift parked from operator marker PC(%.1f, %.1f)" % [swift_pc.x, swift_pc.y])
	if _world.has_node("/root/Plant") and Plant.is_initialized():
		swift.global_position = Plant.pc_to_scene_with_y(swift_pc, anchor.y - 0.7)
	else:
		var rot := Basis(Vector3.UP, by)
		var local_offset := Vector3(swift_pc.x - 500.0, -0.7, swift_pc.y - 500.0)
		swift.global_position = anchor + rot * local_offset
	# Face "north" in the bale-yard convention — driver looks UP De Asselen
	# Kuil toward the parking turn. Apply world_yaw so the heading rotates
	# with the rest of the world.
	swift.rotation.y = by
	return swift
