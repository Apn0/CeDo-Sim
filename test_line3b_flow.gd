extends SceneTree
## Line 3B "functional start to finish" proof (operator 2026-07-16).
##
## Feeds 1000 kg through the REAL LINE_3B_SEQ machine order (node-by-node, using
## MachineFlow.profile + LineFlow's exact sink rule) and checks that material now
## reaches the pelletising back-end and the terminal voorraad_silo — which it did
## NOT before extruder_3b was demoted from sink → process.
##
## Scope note: this exercises the flow SEMANTICS (roles / transforms / sink); the
## real in-game graph edges + PLC + delay-lines are a separate observation.
## Run:  Godot_v4.6.3_console --headless --path <proj> --script res://test_line3b_flow.gd

var _fail := 0

# Flow-relevant machines of LINE_3B_SEQ in order (role=none fixtures like
# kleine_la / lump_* dropped; both mech_dryer branches represented as two drys).
const TRAIN_3B : Array[String] = [
	"vss_silo", "vuilsnippersilo", "transport_screw", "rafter", "dewater_screw",
	"friction_sep", "flotation_tank", "dewater_screw", "friction_sep",
	"mech_dryer", "mech_dryer", "blower", "cyclone", "plasmaq", "cyclone",
	"blower", "cyclone", "extruder_silo", "extruder_3b", "laser_filter",
	"heetafslag", "ontwaterzeef", "centrifuge", "weegschaal", "voorraad_silo",
]
const BACKEND : Array[String] = ["heetafslag", "ontwaterzeef", "centrifuge", "weegschaal", "voorraad_silo"]

func _init() -> void:
	print("=== Line 3B end-to-end flow proof ===")
	var r_old := _run_train(true)    # simulate PRE-FIX: extruder_3b forced sink
	var r_new := _run_train(false)   # POST-FIX: real profile (extruder_3b = process)

	print("\n  PRE-FIX (extruder sink): voorraad_silo in %.1f kg | gran %.1f at %s" \
		% [r_old["silo_in"], r_old["gran"], r_old["gran_at"]])
	print("  POST-FIX (extruder proc): voorraad_silo in %.1f kg | gran %.1f at %s | residual %.4f" \
		% [r_new["silo_in"], r_new["gran"], r_new["gran_at"], r_new["residual"]])
	print("  POST-FIX back-end throughput: %s" % str(r_new["backend"]))

	_ok(r_old["silo_in"] < 0.01,
		"PRE-FIX confirmed broken: back-end starved, voorraad_silo receives ~0 kg")
	_ok(r_new["silo_in"] > 0.0,
		"POST-FIX: material reaches voorraad_silo (%.1f kg)" % r_new["silo_in"])
	_ok(r_new["gran"] > 0.0 and String(r_new["gran_at"]) == "voorraad_silo",
		"POST-FIX: granulaat banked at the TRUE line end (voorraad_silo), not mid-line")
	_ok(absf(float(r_new["residual"])) < 0.1,
		"POST-FIX: mass ledger balances (residual %.4f kg)" % r_new["residual"])
	_ok(float(r_new["backend_min"]) > 0.0,
		"POST-FIX: EVERY back-end machine is fed (weakest %.1f kg)" % r_new["backend_min"])

	print("\n=== LINE 3B FLOW TEST: %s ===" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  : %s" % msg)
	else:
		print("  FAIL: %s" % msg)
		_fail += 1

func _run_train(force_extruder_sink: bool) -> Dictionary:
	var fed := 0.0
	var water_added := 0.0
	var water_removed := 0.0
	var contam_removed := 0.0
	var poly_rejected := 0.0
	var waste := 0.0
	var gran := 0.0
	var gran_at := "(none)"
	var silo_in := 0.0
	var backend : Dictionary = {}

	var flow := BaleDefs.feed_sample("rotterdam", 1000.0)
	fed += flow.mass_kg

	for id in TRAIN_3B:
		# Throughput seen ENTERING this machine (before it may bank/empty).
		if id in BACKEND:
			backend[id] = flow.mass_kg
		if id == "voorraad_silo":
			silo_in = flow.mass_kg

		var pr := MachineFlow.profile(id)
		var role := String(pr["role"])
		if force_extruder_sink and id == "extruder_3b":
			role = "sink"   # reproduce the old behaviour for the A/B comparison

		var cr := float(pr["contam_remove"])
		if cr > 0.0:
			contam_removed += flow.remove_contaminant(cr)
		var ro := float(pr["reject_other"])
		if ro > 0.0:
			poly_rejected += flow.reject_polymer("other", ro)
		var rh := float(pr["reject_hdpe"])
		if rh > 0.0:
			poly_rejected += flow.reject_polymer("HDPE", rh)
		var wr := float(pr["water_remove"])
		if wr > 0.0:
			water_removed += flow.remove_water(wr)
		var wa := float(pr["water_add"])
		if wa > 0.0:
			var added := flow.polymer_kg() * wa
			flow.add_water(added)
			water_added += added
		var wf := float(pr["waste"])
		if wf > 0.0:
			var w := flow.split_fraction(wf)
			waste += w.mass_kg

		if role == "sink":
			gran += flow.mass_kg
			gran_at = id
			flow = MaterialBatch.new()

	var in_line := flow.mass_kg
	var residual := fed + water_added - gran - waste - contam_removed - water_removed - poly_rejected - in_line
	var backend_min := 1.0e9
	for k in BACKEND:
		backend_min = minf(backend_min, float(backend.get(k, 0.0)))

	return {
		"gran": gran, "gran_at": gran_at, "silo_in": silo_in, "residual": residual,
		"backend": backend, "backend_min": backend_min,
	}
