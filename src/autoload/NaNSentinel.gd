extends Node
## Permanent NaN-transform sentinel. The renderer's anonymous
## "instance_set_transform !v.is_finite()" flood gives no node names; this
## autoload walks the scene tree every SCAN_PERIOD seconds and names every
## Node3D with a non-finite LOCAL transform (once per node path), so any
## future NaN source identifies itself in the log instead of printing half a
## million unattributed errors.
##
## Local-transform check is sufficient: a NaN local makes every descendant's
## global NaN, and the topmost offender is the one reported — which is exactly
## the node whose math is broken.
##
## Debug builds only; the editor F5 run always has it. Cost: one tree walk per
## SCAN_PERIOD (~86k nodes ≈ tens of ms) — acceptable at this cadence for the
## diagnostic value.

const SCAN_PERIOD : float = 10.0
const MAX_REPORTS : int = 40

var _elapsed : float = 0.0
var _reported : Dictionary = {}

func _ready() -> void:
	if not OS.is_debug_build():
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < SCAN_PERIOD:
		return
	_elapsed = 0.0
	var root := get_tree().current_scene
	if root == null:
		return
	_scan(root)
	if _reported.size() >= MAX_REPORTS:
		push_warning("[NaNSentinel] report cap reached (%d) — scanning stopped" % MAX_REPORTS)
		set_physics_process(false)

func _scan(n: Node) -> void:
	if n is Node3D and not (n as Node3D).transform.is_finite():
		var path := String(n.get_path())
		if not _reported.has(path):
			_reported[path] = true
			push_warning("[NaNSentinel] NON-FINITE transform: %s (class=%s) local=%s" \
				% [path, n.get_class(), str((n as Node3D).transform)])
		# Children of a NaN node are NaN by inheritance — don't spam them.
		return
	for c in n.get_children():
		_scan(c)
