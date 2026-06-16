extends Node3D

class_name SystemsSpawner

# =============================================================================
# #195 — Operator / build / line systems init extracted from MainWorld.gd.
# =============================================================================
# Owns the spawn helpers for OperatorContext (embodiment switcher), BuildMode
# (in-game factory builder + ToolPlacementMode sibling), and LineFlow (machine
# auto-linker + material simulator). MainWorld creates one of these as a child
# node and calls setup(self) exactly once during world setup; the spawner then
# materialises everything by mutating MainWorld's member vars (operator_context,
# build_mode, line_flow) and parenting the spawned systems under MainWorld so
# the resulting scene tree shape is identical to the pre-extract layout.

# Reference back to MainWorld for member-var mutation + spawned-node parenting.
# Set when the spawner is added to the tree (its parent IS MainWorld) and also
# by setup() for the call-time-explicit codepath.
var _world : Node = null

func _ready() -> void:
	if _world == null:
		_world = get_parent()

# ── Public entry point ──────────────────────────────────────────────────────
func setup(world: Node) -> void:
	_world = world
	_spawn_operator_context()
	_spawn_build_mode()
	_spawn_line_flow()

# =============================================================================
# OPERATOR CONTEXT (embodiment switcher: on_foot ↔ forklift ↔ ...)
# =============================================================================
func _spawn_operator_context() -> void:
	var operator_context := OperatorContext.new()
	operator_context.name = "OperatorContext"
	operator_context.on_foot_body = _world.player
	operator_context.foot_camera  = (_world.player as Node).find_child("Camera3D", true, false) as Camera3D
	_world.add_child(operator_context)
	_world.operator_context = operator_context
	print("[SystemsSpawner] OperatorContext ready")

# =============================================================================
# BUILD MODE (in-game factory builder — press Tab)
# =============================================================================
## #90 — per-save placed-build layout path. Derived from the active save name (the
## same stem GameState uses), so every save has its own factory file and a brand-new
## save starts empty. Falls back to the legacy stem when no save name was provided
## (e.g. MainWorld launched directly without going through the menu).
func _factory_layout_path() -> String:
	var stem := "cedo_simulator"
	if EventBus.has_meta("pending_save_name"):
		var n := String(EventBus.get_meta("pending_save_name")).strip_edges()
		if n != "":
			stem = n
	return "user://%s_factory.json" % stem

func _spawn_build_mode() -> void:
	# #90 — PER-SAVE placed-build layout. Each save gets its OWN factory file
	# (user://<save>_factory.json), so a NEW world can NEVER inherit a previous run's
	# machines, and one save's build never clobbers another's. BuildMode reads/writes
	# this injected path; a CONTINUED save with no per-save file yet falls back ONCE to
	# the legacy global user://factory_layout.json (migration), a NEW save never does —
	# its per-save file simply doesn't exist, so it comes up empty. (The old approach
	# wiped a shared global file on a runtime flag, which was fragile; this can't fail.)
	var fpath := _factory_layout_path()
	var gs = _world.game_state
	var is_new : bool = gs != null and gs.is_new_save
	if is_new and FileAccess.file_exists(fpath):
		# Same-named save reused after a delete: force it to truly start fresh.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fpath))
		print("[SystemsSpawner] New save — wiped stale %s" % fpath)
	print("[SystemsSpawner] Save factory layout: %s (new_save=%s)" % [fpath, str(is_new)])
	var build_mode := BuildMode.new()
	build_mode.name = "BuildMode"
	build_mode.player_body = _world.player              # so placement rays ignore the capsule
	build_mode.wall_openings = _world.wall_openings     # set BEFORE add_child → load_layout
	build_mode.layout_path = fpath                       # per-save layout file (#90)
	build_mode.allow_legacy_fallback = not is_new        # continue may migrate; new never inherits
	_world.add_child(build_mode)
	_world.build_mode = build_mode
	print("[SystemsSpawner] BuildMode ready — press Tab to build")
	# Tool-placement mode (the build-mode sibling for hand-held items). Same
	# UX as BuildMode (ghost preview + rotate + confirm) but operates on the
	# active Inventory tool — never spawns from catalog, so accidental tap
	# can't drop a machine into the world.
	var tool_place := preload("res://src/build/ToolPlacementMode.gd").new()
	tool_place.name = "ToolPlacementMode"
	tool_place.main_world = _world
	_world.add_child(tool_place)
	print("[SystemsSpawner] ToolPlacementMode ready — press G to place held tool")

# =============================================================================
# LINE FLOW (auto-links placed machines + simulates material through them)
# =============================================================================
func _spawn_line_flow() -> void:
	var line_flow := LineFlow.new()
	line_flow.name = "LineFlow"
	_world.add_child(line_flow)                # _ready() discovers machines already placed
	_world.line_flow = line_flow
	if _world.build_mode:
		_world.build_mode.line_flow = line_flow  # so placing/deleting re-links the line
	print("[SystemsSpawner] LineFlow ready")
