extends Node3D
## Orthographic STRAIGHT-DOWN render of the AliceVision building scan, for
## landmark georeferencing against a North-up Google Maps satellite tile.
## Renders the roof footprint in the mesh's own X/Z frame with +X (red) and
## +Z (green) axis arms marked, saves a PNG, and quits. No interaction.

const SHOT := "C:/Users/arnod/AppData/Local/Temp/claude/V---Claude/370e0175-2243-4ddb-b7bf-1a7a58a5f0d3/scratchpad/building_topdown.png"

func _ready() -> void:
	# Axis arms in the mesh's local frame (drawn on the ground, y just above 0).
	_arm(Vector3(6.0, 0.05, 0.0), Vector3(12.0, 0.2, 0.4), Color(1, 0.25, 0.2), "+X")
	_arm(Vector3(0.0, 0.05, 6.0), Vector3(0.4, 0.2, 12.0), Color(0.3, 1, 0.35), "+Z")

func _arm(pos: Vector3, size: Vector3, col: Color, tag: String) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = m; mi.position = pos
	add_child(mi)
	var l := Label3D.new()
	l.text = tag
	l.font_size = 120
	l.pixel_size = 0.02
	l.modulate = col
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos + Vector3(0.0, 1.0, 0.0)
	add_child(l)

var _f : int = 0

func _process(_delta: float) -> void:
	_f += 1
	if _f == 24:
		get_viewport().get_texture().get_image().save_png(SHOT)
		print("[shot] ", SHOT)
	elif _f == 34:
		get_tree().quit()
