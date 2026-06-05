extends SceneTree
## Headless verification of the walkie-talkie + battery + charger system.
##
## Pure logic — no audio server, no scene tree visuals. Exercises:
##   1. Battery drain: a full pack lasts ~4.5 eight-hour shifts; charge ~4 h.
##   2. Walkie routing: headset is quieter than speaker; volume scales; a DEAD
##      battery means a call is NOT heard (effective loudness 0).
##   3. BatteryStation swap loop: one charger, packs are conserved, the
##      considerate "shelve your empty / file the full one" moves work.
##
## Run: godot --headless --path <proj> --script res://tests/WalkieBatteryTest.gd

const _Battery := preload("res://src/sim/Battery.gd")
const _Station := preload("res://src/scenes/world/BatteryStation.gd")
const _Walkie  := preload("res://src/autoload/Walkie.gd")

var _fail := 0

func _init() -> void:
	print("=== Walkie / battery / charger test ===")
	_battery_drain_charge()
	_walkie_routing()
	_station_swap_loop()
	if _fail == 0:
		print("\nALL OK")
	else:
		print("\n%d FAILED" % _fail)
	quit(0 if _fail == 0 else 1)

func _ok(c: bool, msg: String) -> void:
	print(("  ok  : " if c else "  FAIL: ") + msg)
	if not c:
		_fail += 1

# -----------------------------------------------------------------------------
func _battery_drain_charge() -> void:
	print("\n[battery drain + charge]")
	var b = _Battery.new(1.0, "t")
	# One 8h shift = 28800 s. A full pack should survive a full shift with plenty
	# left (it's a ~4.5-shift pack), so after one shift it should read ~78%.
	b.drain(28_800.0)
	_ok(b.charge > 0.70 and b.charge < 0.85,
		"full pack after one 8h shift ≈ 78%% (got %d%%)" % b.percent())

	# Drain it flat over its rated life; drain() returns true exactly on the death step.
	var b2 = _Battery.new(0.02, "t2")
	var died := b2.drain(28_800.0)   # way more than 0.02 of life
	_ok(b2.is_flat(), "pack drains to flat")
	_ok(died, "drain() reports the death transition exactly once")
	_ok(not b2.drain(100.0), "an already-flat pack reports no further death event")

	# Charge: empty → full in ~4 h (14400 s).
	var c = _Battery.new(0.0, "t3")
	var full := c.top_up(14_400.0)
	_ok(c.is_full(), "empty pack reaches full after ~4 h on the charger")
	_ok(full, "top_up() reports the full transition once")
	# Half a charge cycle → ~50%.
	var c2 = _Battery.new(0.0, "t4")
	c2.top_up(7_200.0)
	_ok(c2.charge > 0.45 and c2.charge < 0.55, "half a charge cycle ≈ 50%% (got %d%%)" % c2.percent())

# -----------------------------------------------------------------------------
func _walkie_routing() -> void:
	print("\n[walkie routing]")
	# Build a bare Walkie via its script (autoload not active in --script mode).
	var W: Node = _Walkie.new()
	get_root().add_child(W)
	W.battery = _Battery.new(1.0, "w")

	W.set_volume(1.0)
	W.headset_on = false
	var spk: float = W.effective_loudness()
	W.headset_on = true
	var hs: float = W.effective_loudness()
	_ok(spk > hs, "speaker route is louder than the headset (%.2f > %.2f)" % [spk, hs])
	_ok(hs > 0.0, "headset still audible with a live battery")

	# Volume scales loudness.
	W.headset_on = false
	W.set_volume(0.5)
	_ok(abs(W.effective_loudness() - spk * 0.5) < 0.01, "volume knob scales loudness linearly")

	# Dead battery → nothing heard, and receive_call reports heard=false.
	W.battery = _Battery.new(0.0, "dead")
	_ok(W.effective_loudness() == 0.0, "a dead battery has zero loudness")
	_ok(not W.battery_alive(), "battery_alive() false when flat")
	var heard_flag := [true]
	W.call_received.connect(func(_n, _t, heard): heard_flag[0] = heard)
	W.receive_call("Romain", "test")
	_ok(heard_flag[0] == false, "call on a dead battery is reported as MISSED")

	W.free()

# -----------------------------------------------------------------------------
func _station_swap_loop() -> void:
	print("\n[charger swap loop]")
	var W: Node = _Walkie.new()
	W.name = "Walkie"
	get_root().add_child(W)        # so BatteryStation finds it at /root/Walkie
	W.battery = _Battery.new(0.1, "low")   # player's pack is nearly empty

	var st: Node = _Station.new()
	st.walkie_ref = W      # inject directly (autoloads aren't active in --script)
	# Don't add to tree (avoids _ready's trigger build needing the full scene);
	# seed packs manually like _ready would.
	st._seed_packs()

	# Conservation: count every pack in the system before and after the loop.
	var total_before: int = _count_packs(st, W)
	_ok(total_before >= 4, "system seeded with packs (walkie + drawer + shelf + charger = %d)" % total_before)

	# 1) Player's pack is low → take a fresh one from the drawer into the walkie.
	var drawer0: int = st.drawer_count()
	var got: bool = st.take_fresh_into_walkie()
	_ok(got, "took a fresh pack from the drawer")
	_ok(W.battery.is_full(), "walkie now holds a full pack")
	_ok(st.held() != null and st.held().charge < 0.2, "the old low pack is now in hand")
	_ok(st.drawer_count() == drawer0 - 1, "drawer lost exactly one pack")

	# 2) Considerate move: shelve the empty you pulled out.
	var shelf0: int = st.shelf_count()
	_ok(st.shelve_held(), "shelved the empty pack")
	_ok(st.shelf_count() == shelf0 + 1, "shelf gained the empty")
	_ok(st.held() == null, "hands empty after shelving")

	# 3) Charger finished a pack earlier → file the full one in the drawer, then
	#    load the next shelf empty into the freed charger.
	st.charger.charge = 1.0       # pretend it finished
	_ok(st.take_from_charger(), "lifted the full pack out of the charger")
	_ok(st.charger == null, "charger now empty")
	_ok(st.drawer_held(), "filed the full pack into the drawer")
	_ok(st.charge_next_shelf_empty(), "loaded a shelf empty into the charger")
	_ok(st.charger != null and st.charger.charge < 0.2, "the charging pack is an empty")

	# Conservation holds across the whole loop — no pack created or destroyed.
	var total_after: int = _count_packs(st, W)
	_ok(total_after == total_before, "packs conserved across the loop (%d == %d)" % [total_after, total_before])

	W.free()
	st.free()

func _count_packs(st: Node, W: Node) -> int:
	var n: int = st.drawer_count() + st.shelf_count()
	if st.charger != null: n += 1
	if st.held() != null:  n += 1
	if W.battery != null:  n += 1
	return n
