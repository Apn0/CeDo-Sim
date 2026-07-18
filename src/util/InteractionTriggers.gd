extends Object
class_name InteractionTriggers

## Shared builders for the Area3D + SphereShape3D + signal-connect boilerplate
## that appears in 10+ pickup-/proximity-trigger scripts.
##
## Before this helper, every hand tool, ground panel, and surface prop
## hand-rolled the same ~10 lines:
##
##     var area := Area3D.new()
##     area.name = "PickupArea"
##     area.collision_mask = 1
##     var cs := CollisionShape3D.new()
##     var sp := SphereShape3D.new(); sp.radius = PICKUP_RANGE
##     cs.shape = sp
##     area.add_child(cs)
##     add_child(area)
##     area.body_entered.connect(_on_body_entered)
##     area.body_exited.connect(_on_body_exited)
##
## When that pattern drifts (collision_mask, area name, missing signal
## connection) it produces subtle "the tool stopped responding" bugs.
## Consolidating here makes the contract explicit and keeps a single
## site to fix if the player collision layer / detection scheme changes.

## Build a proximity sphere Area3D, parent it to `owner`, and wire the body
## enter/exit callbacks. Returns the Area3D so callers can hold a reference
## or read its name for debugging.
##
## - `owner`           — the Node3D the trigger is parented to (usually `self`).
## - `radius`          — sphere radius in metres (the pickup range).
## - `on_enter` / `on_exit` — Callable; receives (body: Node3D).
## - `area_name`       — node name; defaults to "PickupArea" to match the
##                       legacy pattern, useful for the in-editor remote tree
##                       and for callers that look up the area by name.
## - `collision_mask`  — physics layers to detect; default 1 (player layer).
static func make_pickup_trigger(
		owner: Node3D,
		radius: float,
		on_enter: Callable,
		on_exit: Callable,
		area_name: String = "PickupArea",
		collision_mask: int = 1,
		shape_offset: Vector3 = Vector3.ZERO) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.collision_mask = collision_mask
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	cs.shape = sp
	if shape_offset != Vector3.ZERO:
		cs.position = shape_offset
	area.add_child(cs)
	owner.add_child(area)
	if on_enter.is_valid():
		area.body_entered.connect(on_enter)
	if on_exit.is_valid():
		area.body_exited.connect(on_exit)
	return area
