extends SceneTree
## Debug: instantiate the main menu headless and print every Control whose
## rect overlaps the dynamic button column, with its mouse_filter. Finds the
## "invisible overlay eats clicks on Macro sandbox / Feature tester" blocker.

func _initialize() -> void:
	root.size = Vector2i(1920, 1040)   # ~1080p windowed (minus decorations)
	var ps := load("res://src/scenes/menus/main_menu/MainMenu.tscn") as PackedScene
	var menu := ps.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	await process_frame
	# Find the two victim buttons.
	var victims : Array = []
	_collect(menu, victims)
	var targets : Array = []
	for c in victims:
		if c is Button and (c.text == "Macro sandbox" or c.text == "Feature tester"):
			targets.append(c)
	print("window size: %s" % str(root.size))
	print("MainMenu root rect=%s anchors RTLB=%.2f/%.2f/%.2f/%.2f offsets=%s" % [
		(menu as Control).get_global_rect(),
		(menu as Control).anchor_right, (menu as Control).anchor_top,
		(menu as Control).anchor_left, (menu as Control).anchor_bottom,
		str([(menu as Control).offset_left, (menu as Control).offset_top,
			(menu as Control).offset_right, (menu as Control).offset_bottom])])
	for ch in menu.get_children():
		if ch is Control:
			print("child %-24s rect=%s vis=%s" % [ch.name, ch.get_global_rect(), ch.visible])
	for key in ["ScrollContainer", "ScrollContainer/Centerer",
			"ScrollContainer/Centerer/LeftSpacer", "ScrollContainer/Centerer/Wrapper",
			"ScrollContainer/Centerer/Wrapper/SaveList"]:
		var node := menu.get_node_or_null(NodePath(key)) as Control
		if node != null:
			print("%-45s rect=%s min=%s" % [key, node.get_global_rect(), node.get_combined_minimum_size()])
	var sc := menu.get_node_or_null(^"ScrollContainer") as ScrollContainer
	if sc != null:
		print("scroll h=%d v=%d" % [sc.scroll_horizontal, sc.scroll_vertical])
	for b in targets:
		var r : Rect2 = b.get_global_rect()
		var center : Vector2 = r.get_center()
		print("\n=== '%s' rect=%s visible=%s ===" % [b.text, r, b.is_visible_in_tree()])
		for c in victims:
			var ctl := c as Control
			if ctl == null or not ctl.is_visible_in_tree():
				continue
			if ctl.get_global_rect().has_point(center) and ctl != b and not ctl.is_ancestor_of(b):
				print("  overlaps: %-50s filter=%d rect=%s" % [ctl.get_path(), ctl.mouse_filter, ctl.get_global_rect()])
	quit()

func _collect(n: Node, out: Array) -> void:
	if n is Control:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
