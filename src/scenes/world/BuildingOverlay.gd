extends Node3D
## Overlay the AliceVision scan (flipped Y-up, scaled, rotated to a candidate
## heading) semi-transparently on top of a North-up Esri satellite tile, rendered
## straight down. Because the scan's own textures are Google-Earth imagery, roads
## / field edges COINCIDE when the heading+scale are right and GHOST when wrong.
##
## Args (after --):  <heading_deg> <scale> <dx_m> <dz_m>
##   Godot ... res://.../BuildingOverlay.tscn -- 145 8.4 0 0
## Satellite tile: scratchpad/sat_overlay.png, 300 m box, North-up, centred on the
## capture centroid (= mesh origin). World -Z = North, +X = East.

const SAT := "C:/Users/arnod/AppData/Local/Temp/claude/V---Claude/370e0175-2243-4ddb-b7bf-1a7a58a5f0d3/scratchpad/sat_overlay.png"
const OUT := "C:/Users/arnod/AppData/Local/Temp/claude/V---Claude/370e0175-2243-4ddb-b7bf-1a7a58a5f0d3/scratchpad/building_overlay.png"

var heading : float = 145.0
var scale_f : float = 8.4
var dx : float = 0.0
var dz : float = 0.0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1: heading = float(a[0])
	if a.size() >= 2: scale_f = float(a[1])
	if a.size() >= 3: dx = float(a[2])
	if a.size() >= 4: dz = float(a[3])

	# Satellite ground.
	var img := Image.new()
	if img.load(SAT) == OK:
		var tex := ImageTexture.create_from_image(img)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		($Ground as MeshInstance3D).material_override = m
	else:
		push_error("could not load satellite " + SAT)

	# Scan: 180deg X flip (Y-down -> Y-up) then heading yaw, uniformly scaled.
	var holo := $Hologram as MeshInstance3D
	var b := Basis(Vector3.UP, deg_to_rad(heading)) * Basis(Vector3.RIGHT, PI)
	b = b.scaled(Vector3.ONE * scale_f)
	holo.transform = Transform3D(b, Vector3(dx, 0.0, dz))
	# Textured, ~55% opaque: the scan keeps its Google-Earth imagery so roads /
	# yard edges / the Indaver side building line up (or ghost) against the tile.
	holo.transparency = 0.45

	print("[overlay] heading=%.1f scale=%.2f dx=%.1f dz=%.1f" % [heading, scale_f, dx, dz])

var _f : int = 0
func _process(_delta: float) -> void:
	_f += 1
	if _f == 28:
		get_viewport().get_texture().get_image().save_png(OUT)
		print("[shot] ", OUT)
	elif _f == 38:
		get_tree().quit()
