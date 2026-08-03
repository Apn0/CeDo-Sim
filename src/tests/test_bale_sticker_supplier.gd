extends Node
## Proof for the yard-bale sticker fix (#labelyard).
##
## Before: build_yard_sticker_multimesh(id, n) dropped `id` and baked ONE global
## texture hardcoded to "ROTTERDAM / ID B-00482 / 250 KG NETTO", so every yard
## (Alba Marl, Zwolle, Forst+, Rotterdam) showed the identical Rotterdam sticker —
## and 250 kg was wrong even for Rotterdam.
##
## After: the sticker text is drawn per-supplier from BaleDefs, cached per id, and
## the yard multimesh threads its supplier id through. This measures that:
##   • each supplier bakes a VISUALLY DISTINCT sticker (not one shared bake)
##   • the net weight is data-driven (not the 250 literal)
##   • build_yard_sticker_multimesh actually uses the per-supplier texture
##
##   godot --headless --path <proj> --main-scene res://src/tests/test_bale_sticker_supplier.tscn

const Catalog = preload("res://src/build/PlaceableCatalog.gd")
const Defs    = preload("res://src/sim/BaleDefs.gd")

var _fails : int = 0

func _check(cond: bool, msg: String) -> void:
	print(("  ok    : " if cond else "  FAIL  : ") + msg)
	if not cond:
		_fails += 1

func _ready() -> void:
	print("=== Yard bale sticker per-supplier proof ===")
	var ids := ["rotterdam", "alba_marl", "zwolle", "forstplus"]
	var datas : Dictionary = {}
	for id in ids:
		var tex = Catalog._bale_sticker_texture(id)
		_check(tex != null, "sticker baked for '%s'" % id)
		if tex != null:
			var img : Image = tex.get_image()
			datas[id] = img.get_data() if img != null else PackedByteArray()

	# Every supplier's sticker must differ pixel-for-pixel from every other's.
	var all_distinct := true
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			var a = datas.get(ids[i], null)
			var b = datas.get(ids[j], null)
			if a != null and b != null and a == b:
				all_distinct = false
				print("     dup: %s == %s" % [ids[i], ids[j]])
	_check(all_distinct, "all 4 supplier stickers are visually distinct (was 1 shared Rotterdam bake)")

	# Per-id cache returns the SAME texture instance on repeat calls.
	_check(Catalog._bale_sticker_texture("zwolle") == Catalog._bale_sticker_texture("zwolle"),
		"per-id cache returns the same texture instance")

	# Net weight is computed from BaleDefs, not the old hardcoded 250.
	var rw := int(round(Defs.estimated_weight(Defs.get_origin("rotterdam")["size"])))
	var zw := int(round(Defs.estimated_weight(Defs.get_origin("zwolle")["size"])))
	_check(rw != 250 and rw > 0, "rotterdam net weight is data-driven (%d kg, not the 250 literal)" % rw)
	_check(zw != rw, "zwolle weight (%d) differs from rotterdam (%d) — distinct data" % [zw, rw])

	# The yard multimesh actually uses the per-supplier texture (id threaded through).
	var mm_r = Catalog.build_yard_sticker_multimesh("rotterdam", 3)
	var mm_z = Catalog.build_yard_sticker_multimesh("zwolle", 3)
	_check(mm_r != null and mm_z != null, "yard multimesh built for both suppliers")
	if mm_r != null and mm_z != null:
		var tex_r = mm_r.multimesh.mesh.material.albedo_texture
		var tex_z = mm_z.multimesh.mesh.material.albedo_texture
		_check(tex_r == Catalog._bale_sticker_texture("rotterdam"),
			"rotterdam yard uses the rotterdam sticker texture")
		_check(tex_r != tex_z, "rotterdam and zwolle yards use DIFFERENT sticker textures")
		mm_r.free()
		mm_z.free()

	print("Result: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
