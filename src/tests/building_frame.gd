extends RefCounted
## The building frame ("bf") the world suites place their line fixtures in, and
## the measurement that keeps it honest against the 3D shell.
##
## bf: metres along the halls' long axis (+x, 0..150.7, 0 at the NE gable) and
## across them (+y, 0..71.5). The frame is NOT typed here. It is the one the
## game FITS from the shell's own collision faces at runtime,
## InteriorLightingManager.get_building_frame() (oriented box over the hull,
## orientation picked by measured roof heights), which the TL bars and the map
## overlay already use. Only the outline's SHAPE in bf metres is typed, and
## outline_off_wall_m() measures it against the walls on every run.
##
## Why (MEASURED 2026-09-25, probe against the shell triangles WallOpenings
## caches): the suites mapped typed bf constants (BF_O/BF_XU/BF_ZU, written in
## Plant Coordinates when PC was still scene-aligned) through
## Plant.pc_to_scene, which by now applies the world yaw (130.2 deg on the
## operator's layout) a SECOND time. The shell's walls run at 40.00 deg
## (mod 90); that mapping put bf +x at -0.2 deg. Six of the ten outline
## corners stood 3.6-39.8 m from any wall, and line 3A built from bf(4,22) had
## 8 of its 39 machines outside the building (the vss_silo 21 m out) while
## regression_world_save reported "39/39 inside". Mapped with no yaw at all,
## the same constants put all ten corners 0.0 m from a wall: they were right,
## the mapping was not.
##
## Loaded with preload() (no class_name: a fresh class_name is unknown to a
## standalone headless run, CLAUDE.md).

# True outer wall outline in bf (the 10-corner union, NOT an AABB).
const OUTLINE := [
	Vector2(0.0, 0.0), Vector2(150.7, 0.0), Vector2(150.7, 31.5),
	Vector2(131.5, 31.5), Vector2(131.5, 71.5), Vector2(81.0, 71.5),
	Vector2(81.0, 66.0), Vector2(57.0, 66.0), Vector2(57.0, 61.0),
	Vector2(0.0, 61.0),
]

## The shell-fitted frame {"o": scene-XZ Vector2 of bf(0,0), "x", "z": unit
## scene-XZ Vector2s, "err": mean roof-height error of the fit, m}, or {} when
## the world has no fit (no shell, or the fit was rejected). `any` is MainWorld
## or any node in its tree (a suite's BuildMode will do).
static func fitted(any: Node) -> Dictionary:
	var ilm : Node = any.get_node_or_null("InteriorLightingManager")
	if ilm == null and any.is_inside_tree():
		ilm = any.get_tree().root.find_child("InteriorLightingManager", true, false)
	if ilm == null or not ilm.has_method("get_building_frame"):
		return {}
	var fr : Dictionary = ilm.call("get_building_frame")
	return fr if fr.has("o") and fr.has("x") and fr.has("z") else {}

## The fit runs a few physics frames after MainWorld's boot, so a suite that
## places lines right after its boot wait asks for it through this: waits up to
## `max_frames` process frames and returns the frame, or {} if none came.
static func wait_fitted(world: Node, max_frames: int = 600) -> Dictionary:
	var tree := world.get_tree()
	for _i in range(max_frames):
		var fr := fitted(world)
		if not fr.is_empty():
			return fr
		await tree.process_frame
	return fitted(world)

## Scene position of a bf point, at height y.
static func to_scene(fr: Dictionary, bf: Vector2, y: float) -> Vector3:
	var p : Vector2 = (fr["o"] as Vector2) + (fr["x"] as Vector2) * bf.x + (fr["z"] as Vector2) * bf.y
	return Vector3(p.x, y, p.y)

## bf coordinates of a scene position (Y ignored).
static func from_scene(fr: Dictionary, p: Vector3) -> Vector2:
	var d : Vector2 = Vector2(p.x, p.z) - (fr["o"] as Vector2)
	return Vector2(d.dot(fr["x"] as Vector2), d.dot(fr["z"] as Vector2))

## The rot_y that makes BuildMode._build_full_line's forward run along +bf x
## (its forward is -Z of the yaw basis).
static func forward_rot_y(fr: Dictionary) -> float:
	var fx : Vector2 = fr["x"]
	return atan2(-fx.x, -fx.y)

## The shell's triangles in scene space, split into walls (|n.y| < 0.2) and
## the rest (roofs, floors). From WallOpenings' pre-carve cache, the same
## triangles the door carve tests against.
static func shell_triangles(world: Node) -> Dictionary:
	var walls : Array = []
	var roofs : Array = []
	var shell : MeshInstance3D = null
	if world.has_method("_shell"):
		shell = world.call("_shell") as MeshInstance3D
	var wo : Node = world.find_child("WallOpenings", true, false)
	if shell == null or wo == null:
		return {"walls": walls, "roofs": roofs}
	var xf : Transform3D = shell.global_transform
	for s in wo.get("_orig_surfaces"):
		var v : PackedVector3Array = s["v"]
		var i := 0
		while i + 2 < v.size():
			var a : Vector3 = xf * v[i]
			var b : Vector3 = xf * v[i + 1]
			var c : Vector3 = xf * v[i + 2]
			var n := (b - a).cross(c - a)
			if n.length() > 1e-6:
				if absf(n.normalized().y) < 0.2:
					walls.append([a, b, c])
				else:
					roofs.append([a, b, c])
			i += 3
	return {"walls": walls, "roofs": roofs}

## Horizontal distance from each outline corner to the nearest shell wall,
## sampled 3 m above the floor top `floor_y`.
static func outline_off_wall_m(fr: Dictionary, tris: Dictionary, floor_y: float) -> Array:
	var out : Array = []
	for bf in OUTLINE:
		out.append(nearest_wall_m(tris, to_scene(fr, bf, floor_y + 3.0)))
	return out

static func nearest_wall_m(tris: Dictionary, p: Vector3) -> float:
	var best := INF
	for t in tris["walls"]:
		var c : Vector3 = _closest_on_tri(p, t[0], t[1], t[2])
		best = minf(best, Vector2(c.x - p.x, c.z - p.z).length())
	return best

## True when the shell has a roof (any non-wall triangle) straight above `p`.
static func under_roof(tris: Dictionary, p: Vector3) -> bool:
	var from := p + Vector3(0.0, 0.5, 0.0)
	for t in tris["roofs"]:
		if Geometry3D.ray_intersects_triangle(from, Vector3.UP, t[0], t[1], t[2]) != null:
			return true
	return false

# Ericson, Real-Time Collision Detection 5.1.5.
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)
