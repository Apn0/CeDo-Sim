extends Node
class_name NirSorter

## Per-machine sim controller for a placed TITECH / TOMRA NIR sorter.
##
## DESIGN — why a thin wrapper?
##   LineFlow stores every sorter as a generic `nd` dict; it does NOT instantiate
##   a dedicated controller per machine. NirSorter exists to give the new
##   shaft-wrap fault state somewhere clean to live (the wrap accumulator + the
##   alarm signal + the cached node reference for the wire-cutter interaction)
##   without bloating LineFlow's per-tick dictionary. Attached by LineFlow in
##   _attach_advanced_systems() on titech_sort / tomra_sort nodes only.
##
## CONTRACT
##   - tick(delta_s, throughput_kg_s) — call once per sim tick with what the
##     sorter actually MOVED on (kg/s); the wrap accumulates with that material.
##   - throughput_multiplier() — call BEFORE the tick to read the current rate
##     penalty; LineFlow multiplies `eff_rate` by this so the sorter slows down
##     as wrap accumulates past TRIP_WRAP_G.
##   - is_tripping() — true once wrap >= TRIP_WRAP_G; rising edge raises an
##     EventBus alarm AND emits the local shaft_wrap_alarm signal.
##   - cut_wrap(amount) — called by TitechShaftCut when the operator completes
##     the hold-E with a wire-cutter; falling edge clears the alarm.
##
## A reference to the placed Node3D is stamped on the node as
## meta("nir_sorter_ctrl") so TitechShaftCut can resolve the controller from a
## crosshair hit without scanning the whole tree.

const WrapModel = preload("res://src/sim/TitechShaftWrap.gd")

## Local signal — code that wants to react inside the same scene (HMI gauge,
## particle FX) can wire this directly instead of subscribing to the global bus.
signal shaft_wrap_alarm(machine_id: String, wrap_g: float)

const ALARM_ID       : String = "SHAFT-WRAP"
const ALARM_SEVERITY : int    = 2

var shaft_wrap : RefCounted = WrapModel.new()
var machine_id : String = "titech_sort"
var node       : Node3D  = null   # the placed sorter body (for the visual + interaction)

var _alarm_raised : bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────────────

## Bind the controller to a placed sorter body. Stamps the back-reference so the
## interaction helper can resolve us from a crosshair hit.
func bind(p_node: Node3D, p_machine_id: String) -> void:
	node = p_node
	machine_id = p_machine_id
	if node != null and is_instance_valid(node):
		node.set_meta("nir_sorter_ctrl", self)

# ── Per-tick driver ───────────────────────────────────────────────────────────

## Advance the wrap model and update the alarm edge. Returns the current
## throughput multiplier so the caller can apply it without a second call.
func tick(delta_s: float, throughput_kg_s: float) -> float:
	shaft_wrap.tick(delta_s, throughput_kg_s)
	_update_alarm()
	_update_visual()
	return shaft_wrap.throughput_multiplier()

func throughput_multiplier() -> float:
	return shaft_wrap.throughput_multiplier()

func is_tripping() -> bool:
	return shaft_wrap.is_tripping()

func wrap_g() -> float:
	return shaft_wrap.wrap_g

## Wire-cutter / knife interaction entry point. Reduces wrap by `reduce_g` and
## clears the alarm if we dropped back below the trip threshold. Returns the
## actual grams removed.
func cut_wrap(reduce_g: float = 250.0) -> float:
	var removed : float = shaft_wrap.cut_wrap(reduce_g)
	_update_alarm()
	_update_visual()
	return removed

func reset() -> void:
	shaft_wrap.reset()
	_update_alarm()
	_update_visual()

# ── Alarm edge + visual coupling ──────────────────────────────────────────────

func _update_alarm() -> void:
	var tripping : bool = shaft_wrap.is_tripping()
	if tripping and not _alarm_raised:
		_alarm_raised = true
		emit_signal("shaft_wrap_alarm", machine_id, shaft_wrap.wrap_g)
		var bus := _event_bus()
		if bus != null and bus.has_signal("machine_alarm_raised"):
			bus.emit_signal("machine_alarm_raised", machine_id, ALARM_ID, ALARM_SEVERITY)
	elif not tripping and _alarm_raised:
		_alarm_raised = false
		var bus := _event_bus()
		if bus != null and bus.has_signal("machine_alarm_cleared"):
			bus.emit_signal("machine_alarm_cleared", machine_id, ALARM_ID)

## Drive the catalog-built shaft_wrap_visual mesh from the wrap fraction
## (0.0 = hidden, 1.0 = FULL_WRAP_G). Cheap — one set_shaft_wrap_visual() call
## per tick. No-op if the catalog helper isn't loadable (headless test).
func _update_visual() -> void:
	if node == null or not is_instance_valid(node):
		return
	var catalog := load("res://src/build/PlaceableCatalog.gd")
	if catalog == null or not catalog.has_method("set_shaft_wrap_visual"):
		return
	var frac : float = clampf(shaft_wrap.wrap_g / WrapModel.FULL_WRAP_G, 0.0, 1.0)
	catalog.call("set_shaft_wrap_visual", node, frac)

func _event_bus() -> Node:
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/EventBus")
