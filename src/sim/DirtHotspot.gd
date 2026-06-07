extends Node3D
class_name DirtHotspot

## A floor hot-spot that accumulates dirt over time — fines around mechanical dryers,
## spillage from forklifts driving past containers, sand from dirty-water drips, etc.
## Builds on the existing FloorPile (#159) so it gets the cone visual + solid collider
## + scoop() API for free. Water-hose / HP-washer cones call scoop() to shrink it.

const _PileScript := preload("res://src/sim/FloorPile.gd")

@export var growth_kg_per_s : float = 0.3                    # how fast dirt piles up
@export var density_kg_m3   : float = 700.0                  # sand / fines bulk density
@export var max_kg          : float = 80.0                   # pile saturates here
@export var pile_color      : Color = Color(0.46, 0.36, 0.22)  # brown / wet-sand
@export var max_radius_m    : float = 1.6

var _pile : Node3D = null

func _ready() -> void:
	add_to_group("dirt_hotspot")
	_pile = _PileScript.new()
	_pile.name = "DirtPile"
	_pile.pile_color = pile_color
	_pile.max_radius_m = max_radius_m
	add_child(_pile)
	# Make the pile findable as a regular "floor_pile" so the hose spray scoops it
	# the same way it scoops shredder output piles — single code path.
	_pile.add_to_group("floor_pile")

func _process(delta: float) -> void:
	if _pile == null or not is_instance_valid(_pile):
		return
	if float(_pile.mass_kg) < max_kg:
		_pile.add(growth_kg_per_s * delta, density_kg_m3)
