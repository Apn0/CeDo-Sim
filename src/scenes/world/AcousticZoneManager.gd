extends Node
class_name AcousticZoneManager

## Manages dynamic spatial acoustics & acoustic zone crossfading.
## Blends between warehouse cavernous reverb, office/canteen dampened acoustics,
## and dry outdoor bale yard soundscapes based on player location.

enum Zone { OUTDOOR, WAREHOUSE, CANTEEN_OFFICE }

var current_zone : int = Zone.OUTDOOR
var _player : Node3D = null

# Warehouse bounding box in world space (approximate CeDo factory envelope)
var warehouse_bounds : AABB = AABB(Vector3(-60.0, -1.0, -90.0), Vector3(120.0, 15.0, 180.0))
# Canteen / Break room bounding box
var canteen_bounds   : AABB = AABB(Vector3(-15.0, -0.5, 35.0), Vector3(25.0, 6.0, 20.0))

var _reverb_wh_idx     : int = -1
var _reverb_office_idx : int = -1
var _machines_bus_idx  : int = -1

var _target_wh_db     : float = -80.0
var _target_office_db : float = -80.0
var _current_wh_db    : float = -80.0
var _current_office_db: float = -80.0

func _ready() -> void:
	add_to_group("acoustic_zone_manager")
	_reverb_wh_idx     = AudioServer.get_bus_index("ReverbWarehouse")
	_reverb_office_idx = AudioServer.get_bus_index("ReverbOffice")
	_machines_bus_idx  = AudioServer.get_bus_index("Machines")

func setup(p_player: Node3D) -> void:
	_player = p_player

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return

	var ppos : Vector3 = _player.global_position
	var new_zone : int = Zone.OUTDOOR

	if canteen_bounds.has_point(ppos):
		new_zone = Zone.CANTEEN_OFFICE
	elif warehouse_bounds.has_point(ppos):
		new_zone = Zone.WAREHOUSE

	if new_zone != current_zone:
		current_zone = new_zone

	match current_zone:
		Zone.WAREHOUSE:
			_target_wh_db     = -2.0
			_target_office_db = -80.0
		Zone.CANTEEN_OFFICE:
			_target_wh_db     = -80.0
			_target_office_db = -4.0
		Zone.OUTDOOR:
			_target_wh_db     = -24.0
			_target_office_db = -80.0

	_current_wh_db     = move_toward(_current_wh_db, _target_wh_db, delta * 30.0)
	_current_office_db = move_toward(_current_office_db, _target_office_db, delta * 30.0)

	if _reverb_wh_idx >= 0:
		AudioServer.set_bus_volume_db(_reverb_wh_idx, _current_wh_db)
	if _reverb_office_idx >= 0:
		AudioServer.set_bus_volume_db(_reverb_office_idx, _current_office_db)
