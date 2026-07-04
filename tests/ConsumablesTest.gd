extends Node3D
## Headless verification of vehicle consumables. Runs as a .tscn-based test (in the
## real main loop, so autoloads like EventBus + global classes resolve — an
## `extends SceneTree --script` harness does NOT load them, which breaks the
## refuel/recharge paths that emit on EventBus).
##
## Covers:
##   • electric drive battery — drains under load, goes flat, blocks power, recharges
##   • diesel fuel + AdBlue/DEF — both drain (DEF slower), empty DEF derates power
##   • ServiceStation — outlet only takes electric, pump only combustion; ticking
##     charges / fuels the connected machine
##
## Run: godot --headless --path . res://tests/ConsumablesTest.tscn --quit-after 90

const FORKLIFT := "res://src/scenes/vehicles/Forklift.tscn"   # lpg
const MERLO    := "res://src/scenes/vehicles/Merlo.tscn"      # diesel
const SCISSOR  := "res://src/scenes/vehicles/MastLift.tscn" # electric (ScissorLift was renamed to MastLift)
const _Station := preload("res://src/scenes/world/ServiceStation.gd")

var _pass := 0
var _fail := 0
var _lines : Array[String] = []

func _ready() -> void:
	print("=== Vehicle consumables test ===")
	_electric_battery()
	_diesel_fuel_adblue()
	_service_station()
	print("\nRESULT: %d passed · %d failed" % [_pass, _fail])
	for l in _lines:
		print("  - " + l)
	get_tree().quit(0 if _fail == 0 else 1)

func _ok(c: bool, m: String) -> void:
	if c: _pass += 1
	else:
		_fail += 1
		_lines.append(m)
	print(("  ok  : " if c else "  FAIL: ") + m)

func _make(path: String) -> Node:
	var v := (load(path) as PackedScene).instantiate()
	add_child(v)
	return v

# -----------------------------------------------------------------------------
func _electric_battery() -> void:
	print("\n[electric drive battery]")
	var v := _make(SCISSOR)
	_ok(String(v.fuel_type) == "electric", "lift is electric")
	_ok(v.drive_charge >= 0.999, "spawns fully charged")
	_ok(v._has_power(), "has power when charged")

	v._throttle = 1.0
	for i in 600:
		v._consume_fuel(1.0)   # 600 s at full load
	_ok(v.drive_charge < 1.0, "battery drops under load (%.3f)" % v.drive_charge)
	var after_10min: float = v.drive_charge

	for i in 30000:
		v._consume_fuel(1.0)
	_ok(v.drive_charge <= 0.0, "battery goes flat under sustained load")
	_ok(not v._has_power(), "flat battery = no power")
	_ok(after_10min > v.drive_charge, "charge monotonically decreased")

	for i in 200:
		v.recharge(1.0 / 90.0)   # ServiceStation.CHARGE_PER_S each "second"
	_ok(v.drive_charge >= 0.999, "recharges to full on the outlet")
	_ok(v._has_power(), "has power again after charging")
	v.queue_free()

# -----------------------------------------------------------------------------
func _diesel_fuel_adblue() -> void:
	print("\n[diesel fuel + AdBlue]")
	var v := _make(MERLO)
	_ok(String(v.fuel_type) == "diesel", "merlo is diesel")
	_ok(v.fuel_l >= v.fuel_capacity_l - 0.001, "spawns with a full diesel tank")
	_ok(v.adblue_l >= v.adblue_capacity_l - 0.001, "spawns with a full DEF tank")
	_ok(v._power_factor() == 1.0, "full power with DEF present")

	var fuel0: float = v.fuel_l
	var def0: float = v.adblue_l
	v._throttle = 1.0
	for i in 600:
		v._consume_fuel(1.0)
	var fuel_used: float = fuel0 - v.fuel_l
	var def_used: float = def0 - v.adblue_l
	_ok(fuel_used > 0.0, "diesel burns under load (%.2f L)" % fuel_used)
	_ok(def_used > 0.0, "DEF is consumed too (%.3f L)" % def_used)
	_ok(def_used < fuel_used * 0.2, "DEF burns far slower than diesel (%.3f << %.2f)" % [def_used, fuel_used])

	for i in 200000:
		if v.adblue_l <= 0.0:
			break
		v._consume_fuel(1.0)
	_ok(v.adblue_l <= 0.0, "DEF tank can run dry")
	_ok(v._power_factor() < 1.0, "empty DEF derates the engine (factor %.2f)" % v._power_factor())

	v.fuel_l = 0.0
	var more: bool = v.refuel(1000.0)
	_ok(v.fuel_l >= v.fuel_capacity_l - 0.001 and not more, "refuel fills the tank and reports full")
	v.refill_adblue(1000.0)
	_ok(v._power_factor() == 1.0, "topping DEF restores full power")
	v.queue_free()

# -----------------------------------------------------------------------------
func _service_station() -> void:
	print("\n[service station]")
	var lift := _make(SCISSOR)     # electric
	var merlo := _make(MERLO)      # diesel
	lift.drive_charge = 0.2
	merlo.fuel_l = 10.0
	merlo.adblue_l = 1.0

	var outlet: Node = _Station.new()
	outlet.mode = "outlet"
	var pump: Node = _Station.new()
	pump.mode = "pump"

	_ok(outlet._compatible(lift) and not outlet._compatible(merlo),
		"outlet accepts the electric lift, refuses the diesel Merlo")
	_ok(pump._compatible(merlo) and not pump._compatible(lift),
		"pump accepts the diesel Merlo, refuses the electric lift")

	var c0: float = lift.drive_charge
	for i in 60:
		outlet._tick_service(lift, 0.5)
	_ok(lift.drive_charge > c0, "outlet charges the lift (%.2f → %.2f)" % [c0, lift.drive_charge])

	var f0: float = merlo.fuel_l
	var d0: float = merlo.adblue_l
	for i in 60:
		pump._tick_service(merlo, 0.5)
	_ok(merlo.fuel_l > f0, "pump refuels the Merlo (%.1f → %.1f)" % [f0, merlo.fuel_l])
	_ok(merlo.adblue_l > d0, "pump tops the Merlo's DEF (%.2f → %.2f)" % [d0, merlo.adblue_l])

	outlet.free(); pump.free(); lift.queue_free(); merlo.queue_free()
