extends SceneTree
## Headless performance probe for the bale-yard rendering cost (Task #43).
##
## Bale yards were the main frame-rate sink: hundreds of bales, each a full
## ~30-60 sheet + 3-wire model = thousands of draw calls. The fix (see
## PlaceableCatalog._m_bale_simple / detail_bale / _lod_cull and the shadow-off
## loop in _m_bale) is a cheap simple-LOD yard bale that upgrades to full detail
## only when grabbed, plus 15 m visibility-range culling and shadow-casting OFF
## on the full model's sub-meshes.
##
## This probe counts NODES / MESHES (no GPU, no window) so it runs under
## `--headless` and gives hard before/after numbers for the LOD saving.
##
## It depends only on PlaceableCatalog + BaleDefs (both RefCounted, no autoload
## or scene-tree deps), so it follows the repo's pure-logic test convention
## (test_conservation.gd / test_mfi_proxy.gd): `extends SceneTree`, run directly
## via --script, non-zero exit on failure. No .tscn wrapper is needed.
##
## Run:  godot --headless --script res://src/tests/test_bale_lod.gd
##
## Asserts:
##   (1) a SIMPLE bale has FAR fewer MeshInstance3D descendants than a FULL bale
##   (2) the simple bale carries meta simple_bale == true
##   (3) detail_bale() upgrades it: adds Sheets + Wires, clears the simple_bale flag
##   (4) full-bale sheet/wire meshes have cast_shadow OFF and a finite
##       visibility_range_end (the wires are always distance-culled)

var _fail := 0

func _init() -> void:
	print("=== Bale LOD render-cost probe (Task #43) ===")
	_run()
	if _fail == 0:
		print("\nALL BALE-LOD CHECKS PASSED")
	else:
		print("\n%d CHECK(S) FAILED" % _fail)
	# Non-zero exit code on failure so CI / a shell `&&` chain can tell.
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  : %s" % msg)
	else:
		print("  FAIL: %s" % msg)
		_fail += 1

## Recursively count MeshInstance3D descendants of a node (the real draw-call /
## render driver — this is what the GPU has to push per bale).
func _count_meshes(n: Node) -> int:
	if n == null:
		return 0
	# Explicit recursive walk rather than find_children("*","MeshInstance3D"):
	# the bale meshes are built procedurally and never `owner`-stamped, and the
	# owned=false form of find_children behaves inconsistently across versions.
	# A manual walk is unambiguous and counts every descendant mesh.
	var c := 0
	for child in n.get_children():
		if child is MeshInstance3D:
			c += 1
		c += _count_meshes(child)
	return c

func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in n.get_children():
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
		out.append_array(_all_meshes(child))
	return out

func _run() -> void:
	# Use the first feedstock origin as the representative bale. (All origins go
	# through the same _m_bale / _m_bale_simple paths; the counts only scale with
	# bale length via _sheet_count_for, which is clamped 30..60.)
	var origins := BaleDefs.origins()
	_ok(not origins.is_empty(), "BaleDefs has at least one origin to test")
	if origins.is_empty():
		return
	var id := String(origins[0]["id"])
	print("\n[probe] representative bale id = '%s'" % id)

	# ── Build a SIMPLE (LOD yard-fill) bale and a FULL bale ───────────────────
	var simple := PlaceableCatalog.build_node(id, false, true) as Node3D
	var full   := PlaceableCatalog.build_node(id, false, false) as Node3D
	_ok(simple != null, "build_node('%s', false, true) returns a node (simple)" % id)
	_ok(full != null,   "build_node('%s', false, false) returns a node (full)" % id)
	if simple == null or full == null:
		return

	# Count the MODEL subtree (the actual bale geometry the LOD work changes).
	# Both bales ALSO get an identical ~21-mesh paper "Label" (card + barcode
	# stripes) stuck on the body by LabelItem.attach_to — that's shared overhead
	# and not what the LOD trims, so the headline number is Model-only. The
	# whole-node total (incl. label) is printed too for the real per-bale figure.
	var simple_model := simple.get_node_or_null("Model")
	var full_model   := full.get_node_or_null("Model")
	_ok(simple_model != null, "simple bale has a 'Model' subtree")
	_ok(full_model != null,   "full bale has a 'Model' subtree")
	if simple_model == null or full_model == null:
		return
	var simple_meshes := _count_meshes(simple_model)
	var full_meshes   := _count_meshes(full_model)
	var simple_total  := _count_meshes(simple)
	var full_total    := _count_meshes(full)

	# ── (1) HARD NUMBERS: simple << full ──────────────────────────────────────
	print("\n[1] Mesh-count saving (the headline render-cost number)")
	print("    SIMPLE bale model : %d MeshInstance3D  (whole node incl. label: %d)" \
		% [simple_meshes, simple_total])
	print("    FULL   bale model : %d MeshInstance3D  (whole node incl. label: %d)" \
		% [full_meshes, full_total])
	if simple_meshes > 0:
		print("    ratio (model)     : full is %.1fx the simple mesh count (%d fewer per simple bale)" \
			% [float(full_meshes) / float(simple_meshes), full_meshes - simple_meshes])
	_ok(simple_meshes > 0, "simple bale model actually built some meshes (%d)" % simple_meshes)
	_ok(full_meshes > 0,   "full bale model actually built some meshes (%d)" % full_meshes)
	# "far fewer": at least a 2x reduction (in practice ~9x: ~10 vs ~90 model meshes).
	_ok(simple_meshes * 2 < full_meshes,
		"SIMPLE bale model has FAR fewer meshes than FULL (%d vs %d, >2x reduction)" \
			% [simple_meshes, full_meshes])

	# ── (2) simple bale is tagged for later upgrade ───────────────────────────
	print("\n[2] Simple bale carries the upgrade flag")
	_ok(simple.has_meta("simple_bale") and bool(simple.get_meta("simple_bale")) == true,
		"simple bale meta simple_bale == true")
	# The full bale must NOT claim to be a simple/LOD bale.
	_ok(not (full.has_meta("simple_bale") and bool(full.get_meta("simple_bale"))),
		"full bale is NOT flagged simple_bale")

	# ── (3) detail_bale() upgrades the simple bale in place ───────────────────
	print("\n[3] detail_bale() upgrades simple -> full")
	# Before upgrade: the simple model has neither a Sheets nor a Wires subtree.
	var sheets_before := simple_model.get_node_or_null("Sheets")
	var wires_before  := simple_model.get_node_or_null("Wires")
	_ok(sheets_before == null and wires_before == null,
		"simple model has NO Sheets/Wires before upgrade")

	PlaceableCatalog.detail_bale(simple)

	# detail_bale frees the old children via queue_free(); the new Sheets/Wires
	# are add_child'd synchronously, so they are present immediately even though
	# the freed simple boxes linger until the frame end. Count via the new
	# subtrees, not the whole Model, to avoid counting the queued-free boxes.
	var model2 := simple.get_node_or_null("Model")
	var sheets_after := (model2.get_node_or_null("Sheets") if model2 else null)
	var wires_after  := (model2.get_node_or_null("Wires")  if model2 else null)
	_ok(sheets_after != null, "detail_bale() added a 'Sheets' subtree")
	_ok(wires_after != null,  "detail_bale() added a 'Wires' subtree")
	_ok(not bool(simple.get_meta("simple_bale", false)),
		"detail_bale() cleared the simple_bale flag")
	if sheets_after != null and wires_after != null:
		var upgraded_meshes := _count_meshes(sheets_after) + _count_meshes(wires_after)
		print("    upgraded model now has %d sheet+wire meshes (was %d simple)" \
			% [upgraded_meshes, simple_meshes])
		_ok(upgraded_meshes > simple_meshes,
			"upgraded bale has MORE meshes than the simple one (%d > %d)" \
				% [upgraded_meshes, simple_meshes])
		# detail_bale rebuilds with the SAME generator as a born-full bale, so the
		# upgraded sheet+wire count should match the full bale's mesh count.
		_ok(upgraded_meshes == full_meshes,
			"upgraded mesh count matches a born-full bale (%d == %d)" \
				% [upgraded_meshes, full_meshes])

	# ── (4) full-bale sheet/wire meshes: shadow OFF + finite visibility range ──
	print("\n[4] Full-bale sub-meshes: shadow-casting OFF + finite cull range")
	if full_model != null:
		var f_sheets := full_model.get_node_or_null("Sheets")
		var f_wires  := full_model.get_node_or_null("Wires")
		_ok(f_sheets != null, "full bale has a 'Sheets' subtree")
		_ok(f_wires != null,  "full bale has a 'Wires' subtree")

		# (4a) EVERY sheet+wire mesh must have shadow casting OFF.
		var all_full := _all_meshes(full_model)
		var shadow_on := 0
		for mi in all_full:
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow_on += 1
		_ok(shadow_on == 0,
			"all %d full-bale sub-meshes have cast_shadow OFF (%d still casting)" \
				% [all_full.size(), shadow_on])

		# (4b) The WIRES are ALWAYS distance-culled -> finite visibility_range_end.
		# (Opaque every-other sheets are intentionally left un-culled so the bale
		#  still reads as a solid block from afar, so we assert finiteness on the
		#  wires, which _m_bale culls unconditionally.)
		if f_wires != null:
			var wire_meshes := _all_meshes(f_wires)
			_ok(wire_meshes.size() > 0, "full bale has wire meshes (%d)" % wire_meshes.size())
			var wires_finite := 0
			for mi in wire_meshes:
				var vend := mi.visibility_range_end
				if vend > 0.0 and is_finite(vend):
					wires_finite += 1
			_ok(wires_finite == wire_meshes.size(),
				"all %d wire meshes have a finite visibility_range_end (e.g. %.1f m)" \
					% [wire_meshes.size(), (wire_meshes[0].visibility_range_end if wire_meshes.size() > 0 else 0.0)])

		# (4c) At least SOME sheets are distance-culled (the translucent ones) —
		# proves the LOD cull is wired into the sheet path too, not only wires.
		if f_sheets != null:
			var sheet_meshes := _all_meshes(f_sheets)
			var sheets_finite := 0
			for mi in sheet_meshes:
				var vend := mi.visibility_range_end
				if vend > 0.0 and is_finite(vend):
					sheets_finite += 1
			print("    sheets distance-culled: %d / %d (translucent sheets only, by design)" \
				% [sheets_finite, sheet_meshes.size()])
			_ok(sheets_finite > 0,
				"at least some sheet meshes are distance-culled (%d of %d)" \
					% [sheets_finite, sheet_meshes.size()])

	# Clean up the procedurally-built nodes (never entered the tree).
	simple.free()
	full.free()
