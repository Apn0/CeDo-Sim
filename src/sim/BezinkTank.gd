extends Node
class_name BezinkTank

## Live state + control loop for the bezinkafscheider (settling separator) tank.
##
## Water flows in from the wash process; an automatic discharge valve drains it to
## hold the level between a LOW and HIGH setpoint (hysteresis). The operator can
## switch the valve to MANUAL (open/close by hand) and move the setpoints from the
## tank's local HMI — walk up and press E.
##
## Attached as a child of the sink_float "Model" node by PlaceableCatalog
## ._m_sinkfloat (real placed instances only, never ghost previews). The water
## surface meshes (tagged meta "bezink_water") rise/fall with the live level.

const _HMI_SCRIPT := "res://src/scenes/hud/BezinkHmi.gd"
static var _hmi : CanvasLayer = null      # one shared panel, reused per tank

# ── Live state ────────────────────────────────────────────────────────────────
var water_level : float = 0.55       # 0..1 of trough depth
var valve_auto  : bool  = true       # AUTOMAAT = level controller drives the valve
var valve_open  : bool  = false      # discharge valve position
var pump_on     : bool  = false      # process pump runs while draining
var sp_low      : float = 0.30       # auto: close valve at/below this
var sp_high     : float = 0.80       # auto: open valve at/above this

const INFLOW_PER_S : float = 0.05
const DRAIN_PER_S  : float = 0.12

var _water_meshes : Array = []        # [{node, lo, hi}]
var _player_near  : bool  = false

# Inflow is WASH-PROCESS water — it may only enter while the line is actually
# running. Previously INFLOW_PER_S was added every frame unconditionally, so the
# tank filled from nothing on a cold/stopped plant (operator: "water from
# nothing", bughunt 2026-07-17). Gate it on any belt moving = line active,
# recomputed on a 0.5 s cache so we don't scan the belt group every physics tick.
var _line_active   : bool  = false
var _line_check_t  : float = 0.0
const _LINE_CHECK_PERIOD : float = 0.5
const _BELT_MOVING_MPS   : float = 0.05

func _ready() -> void:
	add_to_group("bezink_tank")
	_build_trigger()
	# Defer the mesh gather to the next idle so the whole machine subtree is in
	# the tree. (Manual walk, not find_children — procedurally-built meshes have
	# no `owner`, so find_children(owned=true) would skip them.)
	call_deferred("_gather_water_meshes")

func _gather_water_meshes() -> void:
	var root := get_parent()
	if root == null:
		return
	_water_meshes.clear()
	_collect_water(root)

func _collect_water(node: Node) -> void:
	for c in node.get_children():
		if c is MeshInstance3D and c.has_meta("bezink_water"):
			_water_meshes.append({
				"node": c,
				"lo": float(c.get_meta("y_lo")),
				"hi": float(c.get_meta("y_hi")),
			})
		_collect_water(c)

func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "BezinkHmiTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.0, 6.0)
	cs.shape = box
	cs.position = Vector3(0.0, 1.2, 0.0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, "Open Bezinkafscheider HMI")

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near:
		return
	if event.is_action_pressed("interact"):
		_open_hmi()
		get_viewport().set_input_as_handled()

func _open_hmi() -> void:
	if _hmi == null or not is_instance_valid(_hmi):
		var scr := load(_HMI_SCRIPT)
		if scr == null:
			push_error("[BezinkTank] %s missing" % _HMI_SCRIPT)
			return
		_hmi = scr.new() as CanvasLayer
		get_tree().root.add_child(_hmi)
	if _hmi.has_method("open_for"):
		_hmi.open_for(self)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	# Automatic level control: open above the high setpoint, close below the low
	# one (hysteresis keeps the valve from chattering at a single threshold).
	if valve_auto:
		if water_level >= sp_high:
			valve_open = true
		elif water_level <= sp_low:
			valve_open = false
	pump_on = valve_open
	# Refresh the "is the line running" gate on a slow cache.
	_line_check_t -= delta
	if _line_check_t <= 0.0:
		_line_check_t = _LINE_CHECK_PERIOD
		_line_active = _any_belt_running()
	var dl := 0.0
	# Process water only enters while the wash line runs (conservation) — a stopped
	# plant supplies nothing, so the tank holds its level instead of inventing water.
	if _line_active:
		dl += INFLOW_PER_S * delta
	if valve_open:
		dl -= DRAIN_PER_S * delta
	water_level = clampf(water_level + dl, 0.0, 1.0)
	_update_water_visual()

## True if any conveyor belt is physically moving — the plant is running, so the
## wash process is drawing and shedding water. Cheap group scan, called at most
## twice a second (see the cache in _physics_process).
func _any_belt_running() -> bool:
	for b in get_tree().get_nodes_in_group("belt"):
		if b != null and b.has_method("current_belt_speed_mps") \
				and absf(float(b.call("current_belt_speed_mps"))) > _BELT_MOVING_MPS:
			return true
	return false

func _update_water_visual() -> void:
	for w in _water_meshes:
		var node : Node3D = w["node"] as Node3D
		if is_instance_valid(node):
			node.position.y = lerpf(float(w["lo"]), float(w["hi"]), water_level)

# ── HMI API (called by BezinkHmi) ─────────────────────────────────────────────
func toggle_auto() -> void:
	valve_auto = not valve_auto

func set_valve_manual(open: bool) -> void:
	if not valve_auto:
		valve_open = open

func adjust_sp_low(d: float) -> void:
	sp_low = clampf(sp_low + d, 0.05, sp_high - 0.05)

func adjust_sp_high(d: float) -> void:
	sp_high = clampf(sp_high + d, sp_low + 0.05, 0.98)
