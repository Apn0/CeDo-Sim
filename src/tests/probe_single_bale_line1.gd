extends Node
## Operator question 2026-08-29: "what happens if you put a single Rotterdam
## bale on the conveyor that feeds line 1 — where does everything end up, and
## how many kilograms?"
##
## Builds line_1 in isolation (same pattern as test_line1_flow_conformance),
## spawns exactly ONE real Rotterdam bale at the line's feed point via the
## PRODUCTION feed path (LineFlow._bale_at / _head_feed_point / feed_sample —
## nothing here is a mock of that path), ticks until the bale is fully drawn
## and the pipeline drains, then reads LineFlow's own mass ledger.
##
##   godot --headless --path . res://src/tests/probe_single_bale_line1.tscn

const TICK_DT := 0.1
const MAX_TICKS := 6000   # 600 s sim time — line 1's FEED_RATE (8 kg/s) alone
                           # drains a ~330 kg bale in ~41 s; the rest is transit.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[BALE-PROBE] building line_1 …")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.call("start_line")   # PLC powers stages downstream-first; a stopped line
	                        # can't move fed material, so it just overloads and
	                        # E-STOPs the head — this is what that looked like:
	print("[BALE-PROBE] line started, letting the PLC spin every stage up …")
	for _i in 60:            # SPIN_UP_S headroom before feeding
		lf.call("tick", TICK_DT)
	await get_tree().process_frame

	# ── Spawn the ONE bale at line 1's real feed point ───────────────────────
	# _head_feed_point needs a head Node3D; grab the SOURCE node (no incoming
	# edge) LineFlow itself will draw from, so the bale lands exactly where
	# production code looks for it.
	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var has_incoming : Dictionary = {}
	for e in edges:
		has_incoming[int((e as Dictionary)["b"])] = true
	var head_node : Node3D = null
	var head_name : String = ""
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		if String(nd.get("role", "")) == "sink" or has_incoming.has(i):
			continue
		var n3d = nd.get("node")
		if n3d != null and is_instance_valid(n3d):
			head_node = n3d as Node3D
			head_name = String(nd.get("id", "?"))
			break
	if head_node == null:
		print("[BALE-PROBE] ERROR: no source head found on line_1")
		get_tree().quit(1); return
	var feed_point : Vector3 = lf.call("_head_feed_point", head_node)
	print("[BALE-PROBE] feed head = %s at %s" % [head_name, feed_point])

	var bale : Node3D = PlaceableCatalog.build_node("rotterdam", false)
	if bale == null:
		print("[BALE-PROBE] ERROR: catalog would not build a rotterdam bale")
		get_tree().quit(1); return
	add_child(bale)
	bale.global_position = feed_point
	bale.set_meta("delivered", true)   # production gate: only delivered bales feed
	var full_kg : float = float(bale.get_meta("weight_kg", 0))
	if full_kg <= 0.0 and bale.has_meta("material_origin"):
		var item := PlaceableCatalog.get_item(String(bale.get_meta("material_origin")))
		full_kg = BaleDefs.estimated_weight(item.get("size", Vector3.ONE))
	print("[BALE-PROBE] spawned 1x Rotterdam bale, %.1f kg, at the feed point" % full_kg)
	await get_tree().process_frame

	# ── Run until the bale is gone AND the pipeline has drained ──────────────
	var t : int = 0
	var bale_gone_at : float = -1.0
	var mill_i : int = -1
	for i2 in nodes.size():
		if String((nodes[i2] as Dictionary).get("id", "")) == "mill":
			mill_i = i2
			break
	var mill_reported_trip : bool = false
	while t < MAX_TICKS:
		if mill_i >= 0 and t % 50 == 0 and t < 500:
			var mnd : Dictionary = nodes[mill_i]
			var mmol = mnd.get("mol")
			print("[BALE-PROBE] t=%.1fs: mill buffer=%.2f powered=%s mol_acc=%s mol_amps=%s"
				% [float(t) * TICK_DT, float(mnd.get("buffer", 0.0)), str(mnd.get("powered")),
				   (str(mmol.get("accumulated_kg")) if mmol != null else "no-mol"),
				   (str(mmol.get("current_amps")) if mmol != null else "no-mol")])
		lf.call("tick", TICK_DT)
		if mill_i >= 0 and not mill_reported_trip:
			var mol2 = (nodes[mill_i] as Dictionary).get("mol")
			if mol2 != null and bool(mol2.call("is_tripped")):
				mill_reported_trip = true
				print("[BALE-PROBE] mill TRIPPED at tick %d (t=%.1fs), buffer=%.1f"
					% [t, float(t) * TICK_DT, float((nodes[mill_i] as Dictionary).get("buffer", 0.0))])
		t += 1
		if bale_gone_at < 0.0 and (not is_instance_valid(bale) or bale.is_queued_for_deletion()):
			bale_gone_at = float(t) * TICK_DT
		if bale_gone_at >= 0.0:
			var in_transit : float = float(lf.call("in_transit_mass"))
			if in_transit < 0.05:
				break
	var sim_s : float = float(t) * TICK_DT

	# ── Diagnostics for any motor that tripped during the run ────────────────
	for i in nodes.size():
		var ndx : Dictionary = nodes[i]
		var mol = ndx.get("mol")
		if mol != null and bool(mol.call("is_tripped")):
			print("[BALE-PROBE] '%s' ended TRIPPED — powered=%s buffer=%.1f kg"
				% [String(ndx.get("id", "?")), str(ndx.get("powered")), float(ndx.get("buffer", 0.0))])

	# ── Read LineFlow's own mass ledger — the same numbers the in-game HUD
	#    label shows, not a re-derivation ──────────────────────────────────
	var fed_mass       : float = float(lf.get("fed_mass"))
	var water_added    : float = float(lf.get("water_added"))
	var gran_mass       : float = float(lf.get("gran_mass"))
	var waste_mass      : float = float(lf.get("waste_mass"))
	var contam_removed  : float = float(lf.get("contam_removed"))
	var water_removed   : float = float(lf.get("water_removed"))
	var poly_rejected   : float = float(lf.get("poly_rejected"))
	var in_transit      : float = float(lf.call("in_transit_mass"))
	var residual        : float = float(lf.call("ledger_residual"))
	var gran_q          : float = float(lf.call("granulaat_quality"))

	print("")
	print("=== SINGLE-BALE TRACE — 1x Rotterdam bale on line 1 ===")
	print("  sim time to fully drain     : %.1f s (%d ticks, bale consumed at %.1f s)"
		% [sim_s, t, bale_gone_at])
	print("  fed onto the line           : %8.1f kg" % fed_mass)
	print("  process water taken on      : %8.1f kg" % water_added)
	print("  ---------------------------------------------------")
	print("  -> granulaat out (sink)     : %8.1f kg   (quality %.0f/100)" % [gran_mass, gran_q])
	print("  -> mechanical waste         : %8.1f kg" % waste_mass)
	print("  -> dirt/contaminant removed : %8.1f kg" % contam_removed)
	print("  -> water driven off         : %8.1f kg" % water_removed)
	print("  -> off-spec polymer reject  : %8.1f kg" % poly_rejected)
	print("  still in the pipeline       : %8.1f kg" % in_transit)
	print("  ---------------------------------------------------")
	print("  ledger balance error        : %8.3f kg  (0 = nothing lost/invented)" % residual)
	print("")

	# ── Where the waste physically landed (containers vs floor) ─────────────
	var containers := get_tree().get_nodes_in_group("waste_container")
	print("[BALE-PROBE] waste containers in scene: %d" % containers.size())
	for c in containers:
		var cn := c as Node3D
		if cn == null:
			continue
		var lvl_kg : float = 0.0
		if cn.has_method("current_kg"):
			lvl_kg = float(cn.call("current_kg"))
		elif cn.has_meta("current_kg"):
			lvl_kg = float(cn.get_meta("current_kg"))
		if lvl_kg > 0.01:
			print("    %-28s %8.1f kg  at %s" % [cn.name, lvl_kg, cn.global_position])
	var piles := get_tree().get_nodes_in_group("floor_pile")
	print("[BALE-PROBE] floor piles: %d" % piles.size())
	for p in piles:
		var pn := p as Node3D
		if pn == null:
			continue
		var pkg : float = 0.0
		if pn.has_method("mass_kg"):
			pkg = float(pn.call("mass_kg"))
		elif pn.has_meta("mass_kg"):
			pkg = float(pn.get_meta("mass_kg"))
		print("    pile at %-28s %8.1f kg" % [str(pn.global_position), pkg])

	get_tree().quit(0)
