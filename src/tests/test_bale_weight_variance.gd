extends Node
## BALE WEIGHT VARIANCE + LINE_1_FOLIE (2026-09-23, rulings §11 and §18) —
## no two bales weigh the same any more, and line 1's black agricultural film
## bales exist.
##
##   godot --headless --path . res://src/tests/test_bale_weight_variance.tscn
##
## Operator: "weight of large bales ~1000kg (+/- 15%, 1SD; apply this
## variance/ratio to all bale types that are present in the sim thus far
## (since I noticed while testing that e.g. all Rotterdam bales are the exact
## same weight → which is not realistic)".
##
## Checks the production paths: PlaceableCatalog.build_node gives every bale
## body its own weight (meta `weight_kg`, the RigidBody mass, the label), the
## light→full upgrade keeps it, LineFlow's remaining_kg starts from it, and the
## population has the asked-for spread.

const WATCHDOG_S := 200.0
const N := 40

var _fails := 0
var _oks := 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _run() -> void:
	print("[TEST] bale weight variance + LINE_1_FOLIE")
	# ── the new origin ──
	var o := BaleDefs.get_origin("line_1_folie")
	_check(not o.is_empty() and String(o["name"]) == "LINE_1_FOLIE", "L1 origin line_1_folie exists, named LINE_1_FOLIE")
	if not o.is_empty():
		var sz : Vector3 = o["size"]
		_check(absf(sz.x - 2.0) < 1e-6 and absf(sz.y - 1.70) < 1e-6 and absf(sz.z - 1.5) < 1e-6, "L1 big bale 2.0 x 1.70 x 1.5 m (operator: ~2 wide, ~1.70 high, ~1.5 thick)")
		_check(absf(BaleDefs.nominal_weight(o) - 1000.0) < 1e-6, "L1 nominal 1000 kg")
		_check(String(o.get("line", "")) == "1" and float(o.get("dirt", 0.0)) > 0.12, "L1 tagged line 1, dirtier than the film-only feeds")
	var os := BaleDefs.get_origin("line_1_folie_small")
	_check(not os.is_empty() and absf(BaleDefs.nominal_weight(os) / 1000.0 - 0.343) < 1e-3, "L1 the 30 %%-smaller bale: %.0f kg nominal (0.7 on each side)" % BaleDefs.nominal_weight(os))
	_check(not PlaceableCatalog.get_item("line_1_folie").is_empty() and not PlaceableCatalog.get_item("line_1_folie_stack5").is_empty(),
		"L1 the catalog carries the bale and its 5x5 stack")
	# ── a population of Rotterdam bales ──
	var nominal : float = BaleDefs.nominal_weight(BaleDefs.get_origin("rotterdam"))
	var masses : Array[float] = []
	var bodies : Array = []
	var meta_ok := true
	for i in N:
		var b : Node3D = PlaceableCatalog.build_node("rotterdam", false, true)
		if b == null:
			continue
		add_child(b)
		bodies.append(b)
		var rb := b as RigidBody3D
		var m : float = rb.mass if rb != null else -1.0
		masses.append(m)
		if not b.has_meta("weight_kg") or absf(float(b.get_meta("weight_kg")) - m) > 1e-3:   # mass is stored single-precision
			meta_ok = false
	await get_tree().process_frame
	_check(masses.size() == N, "V1 built %d Rotterdam bales" % masses.size())
	_check(meta_ok, "V1 every bale's RigidBody mass equals its weight_kg meta")
	var sum := 0.0
	var distinct := {}
	var lo := 1e9
	var hi := 0.0
	for m in masses:
		sum += m
		distinct[snappedf(m, 0.01)] = true
		lo = minf(lo, m)
		hi = maxf(hi, m)
	var mean : float = sum / float(maxi(masses.size(), 1))
	var var_acc := 0.0
	for m in masses:
		var_acc += (m - mean) * (m - mean)
	var sd : float = sqrt(var_acc / float(maxi(masses.size() - 1, 1)))
	_check(distinct.size() >= N - 2, "V1 weights differ bale to bale (%d distinct of %d — the old yard had 1)" % [distinct.size(), N])
	_check(absf(mean / nominal - 1.0) < 0.08, "V1 mean %.0f kg within 8 %% of the nominal %.0f" % [mean, nominal])
	_check(sd / mean > 0.09 and sd / mean < 0.21, "V1 spread: SD %.1f %% of the mean (asked: 15 %%, 1 SD)" % (100.0 * sd / mean))
	_check(lo >= nominal * 0.55 - 1e-6 and hi <= nominal * 1.45 + 1e-6, "V1 clipped at 3 SD: %.0f .. %.0f kg" % [lo, hi])
	# ── the light → full upgrade keeps the weight ──
	var first : RigidBody3D = bodies[0]
	var before : float = first.mass
	PlaceableCatalog.detail_bale(first)
	await get_tree().process_frame
	_check(absf(first.mass - before) < 1e-6 and absf(float(first.get_meta("weight_kg")) - before) < 1e-6, "V2 detail_bale() keeps the bale's weight (%.1f kg)" % before)
	# ── LineFlow feeds from the bale's own weight ──
	var lf := LineFlow.new()
	add_child(lf)
	var rem : float = float(lf.call("_bale_remaining", first))
	_check(absf(rem - before) < 1e-6, "V3 LineFlow's remaining_kg starts at the bale's own %.1f kg" % rem)
	# ── a LINE_1_FOLIE bale ──
	var big : Node3D = PlaceableCatalog.build_node("line_1_folie", false)
	_check(big != null, "L2 build_node(line_1_folie)")
	if big != null:
		add_child(big)
		var m : float = (big as RigidBody3D).mass
		_check(m >= 550.0 and m <= 1450.0, "L2 it weighs %.0f kg (1000 ±3 SD)" % m)
		_check(absf(float(big.get_meta("weight_nominal_kg")) - 1000.0) < 1e-6, "L2 nominal recorded as 1000 kg")
	for b in bodies:
		b.queue_free()
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
