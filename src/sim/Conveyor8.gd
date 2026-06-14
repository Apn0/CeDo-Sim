extends Node
class_name Conveyor8

## #138 — drives the bidirectional behaviour of intake conveyor 8. C8 normally
## carries material FORWARD (toward C9), but when both VSS_3A and VSS_3B
## report FULL the controller commands it to REVERSE, dropping material off
## the upstream end into C8.5 → U-bay. The reversal isn't instant: the belt
## ramps down (2 s), then ramps up the other way (2 s) — the operator's
## "soft" overflow trip.
##
## Public state:
##   direction_x      : -1.0 (fully reversed) ... +1.0 (fully forward), the
##                      CURRENT actual direction LineFlow reads for the share.
##   direction_target : where direction_x is heading (set by LineFlow per tick
##                      from the downstream VSS levels).
##
## Visual side: the belt skin's scroll-speed shader uniform is updated to
## match direction_x so the conveyor visibly STOPS and RESTARTS in the other
## direction during the transition.

const DIR_RAMP_RATE : float = 0.5      # 1.0 / 2.0 s — matches operator's "2 s ramp"
const FWD_SHADER_SPEED : float = 0.6   # POSITIVE = belt visually scrolls toward +Z
                                        # (the canonical downstream direction; see
                                        #  BeltSurface.gd docstring). make_belt_material
                                        #  no longer negates as of #140, so caller
                                        #  passes positive for downstream flow.

var direction_x      : float = 1.0     # start running forward
var direction_target : float = 1.0

var _belt_mat : ShaderMaterial = null   # cached belt-skin material for sign flips

static func attach_to(body: Node3D) -> Conveyor8:
	if body == null:
		return null
	var existing := body.get_node_or_null("_Conveyor8Ctrl") as Conveyor8
	if existing != null:
		return existing
	var ctrl := Conveyor8.new()
	ctrl.name = "_Conveyor8Ctrl"
	body.add_child(ctrl)
	ctrl._resolve_belt_material(body)
	return ctrl

## LineFlow calls this each tick with +1.0 (run forward) or -1.0 (reverse).
## The controller smoothly walks direction_x toward this target.
func set_direction_target(t: float) -> void:
	direction_target = clampf(t, -1.0, 1.0)

## Share heading to the FORWARD output edge this frame, given the current
## direction_x. = direction_x when positive, 0 when reversed. Mirror for the
## reverse edge (`share_reverse`). Together they cap at 1.0; when the belt is
## mid-ramp at direction_x ≈ 0, both are near zero and material backs up in
## C8's buffer — exactly the "belt stopped, nothing leaves" moment.
func share_forward() -> float:
	return maxf(direction_x, 0.0)

func share_reverse() -> float:
	return maxf(-direction_x, 0.0)

func _physics_process(delta: float) -> void:
	var diff : float = direction_target - direction_x
	if absf(diff) > 1e-4:
		var step : float = DIR_RAMP_RATE * delta
		if absf(diff) <= step:
			direction_x = direction_target
		else:
			direction_x += step if diff > 0.0 else -step
		# Sync the belt skin scroll so the surface visibly stops and restarts
		# when reversing. FWD_SHADER_SPEED * direction_x: at +1 → -0.6 (forward
		# visual), at -1 → +0.6 (reverse visual), at 0 → 0 (stopped).
		if _belt_mat == null:
			_resolve_belt_material(get_parent() as Node3D)
		if _belt_mat != null:
			_belt_mat.set_shader_parameter("scroll_speed", FWD_SHADER_SPEED * direction_x)

func _resolve_belt_material(body: Node3D) -> void:
	if body == null:
		return
	# _m_intake_belt parents the deck assembly under "Model/DeckPivot"; the
	# scrolling belt skin is the only MeshInstance3D child with a ShaderMaterial.
	var pivot : Node3D = body.find_child("DeckPivot", true, false) as Node3D
	if pivot == null:
		return
	for ch in pivot.get_children():
		if ch is MeshInstance3D:
			var sm := (ch as MeshInstance3D).material_override as ShaderMaterial
			if sm != null:
				_belt_mat = sm
				return
