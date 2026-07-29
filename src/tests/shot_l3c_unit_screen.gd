extends Control
## Render the ported L3C unit screens to PNG so they can be LOOKED AT.
##
##   godot --path <proj> res://src/tests/shot_l3c_unit_screen.tscn -- L3C.14L
##
## Writes docs/plant/renders/hmi_<id>.png (in the repo, not user://, so the
## render sits beside the mockup it was ported from).
##
## NOT headless: --headless has no renderer, so the viewport texture comes back
## empty. Run it windowed; it quits itself once the PNG is on disk.
##
## The screen is bound to a LIVE LineFlow when one is reachable, and rendered
## unbound otherwise — an unbound render is all "--", which is the honest look of
## a screen with no world behind it and is worth being able to see too.

const UnitScreenScript = preload("res://src/scenes/hud/scopes/L3CUnitScreen.gd")
const SpecScript = preload("res://src/data/plant/l3c_unit_screens.gd")

const OUT_DIR := "res://docs/plant/renders/"
const CANVAS := Vector2i(1280, 800)


func _ready() -> void:
	var ids : Array = []
	for a in OS.get_cmdline_user_args():
		if SpecScript.SCREENS.has(String(a)):
			ids.append(String(a))
	if ids.is_empty():
		ids = SpecScript.SCREENS.keys()

	DisplayServer.window_set_size(CANVAS)
	get_viewport().size = CANVAS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	for id in ids:
		await _shoot(String(id))
	get_tree().quit(0)


func _shoot(id: String) -> void:
	# The host must be a CONTROL sized to the canvas, not a Node2D: the screen
	# anchors itself PRESET_FULL_RECT in _ready(), and anchoring against a
	# non-Control parent left it at its 960x560 minimum. The first render of this
	# tool showed the three motor cards WRAPPED into a vertical stack purely
	# because of that — a layout artefact of the harness that looked exactly like
	# a layout bug in the screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = Vector2(CANVAS)

	var bg := ColorRect.new()
	bg.color = Color("#2a2e36")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var s : Control = UnitScreenScript.new()
	s.call("set_screen", id)
	add_child(s)
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.size = Vector2(CANVAS)

	# Let the layout settle before grabbing the texture; a single frame renders
	# containers at their pre-sort sizes and the PNG comes out misleading.
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var outp := ProjectSettings.globalize_path(OUT_DIR + "hmi_%s.png" % id.replace(".", "_"))
	var err := img.save_png(outp)
	print("%s -> %s (%s)" % [id, outp, "ok" if err == OK else "ERR %d" % err])

	s.queue_free()
	bg.queue_free()
	await get_tree().process_frame
