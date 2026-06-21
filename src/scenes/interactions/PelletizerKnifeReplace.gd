extends RefCounted
class_name PelletizerKnifeReplace

## #210d — Static utility helper for the hold-E knife replace interaction.
##
## CONTRACT
##   Player carries a SocketWrench7 (tool_id == "socket_wrench_7") in the active
##   inventory slot. They aim at a "knife_<i>" StaticBody3D placed by the
##   heetafslag macro (PlaceableCatalog._m_heetafslag, lines 8920-8961). That
##   knife node carries:
##     - meta "placeable_id" == "pelletizer_knife"
##     - meta "knife_index"  (0..3)
##     - meta "knife_state"  (0=NEW / 1=FOUTIEF / 2=BESCHADIGD), default 0
##   Holding E for HOLD_DURATION_S commits the replace; releasing early cancels.
##
## RESPONSIBILITIES
##   - try_begin() validates: wrench held + knife target valid. Does NOT enforce
##     the rotor-stopped safety gate (caller / model do that — see #note below).
##   - tick_hold() integrates progress while the same knife stays under the
##     crosshair (the CALLER is responsible for re-validating the target each
##     tick and calling cancel() if the ray drifts off).
##   - complete() walks up to the pelletizer parent, resolves the right
##     PelletizerModel via the ExtruderMachine group, and calls replace_knife().
##     On success it also flips the blade visual to KnifeState.NEW via
##     PlaceableCatalog.set_knife_state(knife_node, 0).
##
## DESIGN NOTE — why static, not a node?
##   PlayerController owns the per-frame target+input state already; the helper
##   just needs to KNOW about progress, validate inputs, and execute the
##   resolved replace. Living inside PlayerController as a tiny state struct
##   keeps the controller's hold-E branch lean and the resolution logic unit-
##   testable from a single entry point.
##
## DEPENDENCIES (all loaded lazily — no top-level preloads that could cause
## circular imports with PlaceableCatalog):
##   - PlaceableCatalog.set_knife_state(node, state)
##   - PelletizerModel.replace_knife(idx)
##   - ExtruderMachine.model.pelletizer (group "extruder_machine")

const HOLD_DURATION_S : float = 2.0
const WRENCH_TOOL_ID  : String = "socket_wrench_7"
const KNIFE_PLACEABLE_ID : String = "pelletizer_knife"

# Safety gate: rotor speed below this (rpm) counts as "stopped" — replacing a
# knife on a spinning disc is the canonical do-not-do. The cut_rm RotatingMechanism
# ramps to its commanded rpm, so a freshly-stopped rotor coasts through low
# values; 5 rpm is the threshold below which the disc is effectively safe to
# touch (matches the dryer/extruder threshold used elsewhere in the sim).
const ROTOR_SAFE_RPM_MAX : float = 5.0

# ── State (singleton-style — one hold in flight at a time per player) ──────────
static var _progress    : float = 0.0
static var _active_knife : Node3D = null

## Begin a hold on `knife_node`. Returns true if the begin is allowed (wrench
## active + knife meta valid + rotor stopped). Refuses to start while the cut_rm
## rotor is spinning — operator must hit STOP first (and the prompt text upstream
## flips to "Stop eerst de rotor" via is_rotor_safe()).
static func try_begin(player: Node3D, knife_node: Node3D) -> bool:
	if player == null or knife_node == null:
		return false
	if not is_instance_valid(knife_node):
		return false
	if not _is_valid_knife(knife_node):
		return false
	if not _player_holds_wrench(player):
		return false
	# Safety gate: never let the player begin while the rotor is moving.
	if not is_rotor_safe(knife_node):
		return false
	_progress = 0.0
	_active_knife = knife_node
	return true

## Public safety probe — true when the cut_rm rotor that owns this knife is
## stopped (or close enough). Callers (interaction prompt, HUD, debug) use this
## to swap the prompt text to "Stop eerst de rotor" so the player gets feedback
## instead of a silently-refused hold. Duck-types `current_rpm` (method) and
## `rpm` (export var) on whichever ancestor first carries either — the heetafslag
## cut_rm is a RotatingMechanism so it has both.
static func is_rotor_safe(knife_node: Node) -> bool:
	if knife_node == null or not is_instance_valid(knife_node):
		# Nothing to be unsafe about — treat as safe so we don't block degenerate
		# inputs at this gate. Other validators already reject null knives.
		return true
	var rotor := _find_rotor_ancestor(knife_node)
	if rotor == null:
		# No rotor found — heetafslag wasn't built with cut_rm yet, or the knife
		# is a loose fixture. Don't strand the player in an un-passable gate.
		return true
	var live_rpm : float = _read_rotor_rpm(rotor)
	return live_rpm <= ROTOR_SAFE_RPM_MAX

## Returns the live progress (0..1). Caller passes the per-frame `delta` from
## _physics_process / _process. When progress reaches 1.0 the caller should call
## complete(knife_node).
static func tick_hold(delta: float) -> float:
	if _active_knife == null or not is_instance_valid(_active_knife):
		_progress = 0.0
		return 0.0
	_progress = clampf(_progress + delta / HOLD_DURATION_S, 0.0, 1.0)
	return _progress

## Current hold progress without advancing it.
static func progress() -> float:
	return _progress

## True if a hold is currently in flight on `knife_node`.
static func is_active_on(knife_node: Node) -> bool:
	return _active_knife != null and _active_knife == knife_node

## True if any hold is in flight.
static func is_active() -> bool:
	return _active_knife != null and is_instance_valid(_active_knife)

## Abandon the hold (player released E early, or the ray drifted off).
static func cancel() -> void:
	_progress = 0.0
	_active_knife = null

## Commit the replace. Returns true if the model accepted the swap (and the
## visual was flipped back to NEW). Always clears the in-flight state.
static func complete(knife_node: Node3D) -> bool:
	# Snapshot + clear up front so a recursive/early-return path can't leave
	# stale state behind.
	var node := knife_node
	_progress = 0.0
	_active_knife = null
	if node == null or not is_instance_valid(node):
		return false
	if not _is_valid_knife(node):
		return false
	var idx : int = int(node.get_meta("knife_index", -1))
	if idx < 0 or idx >= 4:
		return false
	# Resolve the PelletizerModel. Path: knife_node → cut_rm (rotor) →
	# pelletizer body (heetafslag root) → walk up to placement → find the
	# ExtruderMachine whose line_id matches → use its model.pelletizer.
	var pelletizer := _resolve_pelletizer_model(node)
	if pelletizer == null:
		push_warning("[KnifeReplace] No PelletizerModel resolved for knife %d" % idx)
		return false
	if not pelletizer.has_method("replace_knife"):
		push_warning("[KnifeReplace] Pelletizer has no replace_knife()")
		return false
	var ok : bool = bool(pelletizer.call("replace_knife", idx))
	if not ok:
		return false
	# Visual swap to NEW. PelletizerModel.KnifeState.NEW == 0 — set_knife_state
	# uses the same int contract.
	var catalog := load("res://src/build/PlaceableCatalog.gd")
	if catalog != null and catalog.has_method("set_knife_state"):
		catalog.call("set_knife_state", node, 0)
	return true

# ── Validation helpers ────────────────────────────────────────────────────────

static func _is_valid_knife(node: Node) -> bool:
	if not node.has_meta("placeable_id"):
		return false
	if String(node.get_meta("placeable_id")) != KNIFE_PLACEABLE_ID:
		return false
	if not node.has_meta("knife_index"):
		return false
	return true

static func _player_holds_wrench(player: Node3D) -> bool:
	var inv : Node = null
	if player.is_inside_tree():
		inv = player.get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	if not inv.has_method("active"):
		return false
	var t = inv.call("active")
	if t == null or not is_instance_valid(t):
		return false
	# SocketWrench7 exposes a `tool_id` const — string-match for resilience
	# against script renames / scene-instance variants.
	if "tool_id" in t and String(t.get("tool_id")) == WRENCH_TOOL_ID:
		return true
	# Fallback: group / class-name check for robustness.
	if t.is_in_group("socket_wrench_7"):
		return true
	return false

# ── PelletizerModel resolution ────────────────────────────────────────────────

## Walk up from a knife node to find the heetafslag placement, then locate the
## ExtruderMachine controller that owns the matching line and return its
## `model.pelletizer`. Returns null if any step fails.
##
## Resolution strategy:
##   1. Find the nearest ancestor carrying meta "placeable_id" == "heetafslag"
##      (the per-pelletizer placeable root). That's the in-world anchor.
##   2. Among "extruder_machine" group members, pick the one whose Node3D
##      global_position is closest to the heetafslag's global_position. The
##      heetafslag macro is placed adjacent to its extruder so nearest-neighbour
##      is reliable and avoids needing a hard line_id meta we don't currently
##      stamp on the catalog body.
##   3. Pull `extruder_machine.model.pelletizer` (an ExtruderModel exposes a
##      `pelletizer : PelletizerModel` field via ExtruderModel.gd:256).
##
## This mirrors the nearest-in-group pattern ExtruderMachine itself uses to
## resolve its downstream filters (_closest_in_group, ExtruderMachine.gd:78).
static func _resolve_pelletizer_model(knife_node: Node3D) -> Object:
	var heetafslag := _find_heetafslag_root(knife_node)
	if heetafslag == null:
		return null
	var anchor : Vector3 = heetafslag.global_position
	var tree := knife_node.get_tree()
	if tree == null:
		return null
	var best : Node = null
	var best_d2 : float = INF
	for em in tree.get_nodes_in_group("extruder_machine"):
		if em == null or not is_instance_valid(em):
			continue
		var n3 := em as Node3D
		if n3 == null:
			continue
		var d2 : float = (n3.global_position - anchor).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = em
	if best == null:
		return null
	var model = best.get("model")
	if model == null:
		return null
	# ExtruderModel exposes a `pelletizer` field (PelletizerModel). Duck-type
	# this so a future ExtruderModel refactor doesn't hard-break us.
	if not ("pelletizer" in model):
		return null
	return model.get("pelletizer")

static func _find_heetafslag_root(start: Node) -> Node3D:
	var n : Node = start
	while n != null:
		if n.has_meta("placeable_id"):
			var pid := String(n.get_meta("placeable_id"))
			if pid == "heetafslag":
				return n as Node3D
		n = n.get_parent()
	return null

# ── Rotor safety helpers ──────────────────────────────────────────────────────

## Walk up from a knife node to find the cut_rm rotor that carries it. The
## heetafslag macro adds the per-knife StaticBody3D as a child of cut_rm
## (PlaceableCatalog._m_heetafslag, lines 8924-8930), so the immediate parent is
## the rotor itself in the standard build. We still walk the chain in case a
## future macro wraps the knives in an extra pivot — first ancestor exposing an
## rpm signal wins.
static func _find_rotor_ancestor(start: Node) -> Node:
	var n : Node = start.get_parent() if start != null else null
	while n != null:
		# Stop at the heetafslag root — anything above it is the placement
		# parent / world and won't carry an rpm field.
		if n.has_meta("placeable_id") and String(n.get_meta("placeable_id")) == "heetafslag":
			# Heetafslag root itself doesn't carry the rotor rpm — cut_rm is
			# a child of it. If we got this far without finding a rotor, there's
			# no spinning mechanism between knife and root: nothing to gate.
			return null
		if n.has_method("current_rpm") or "current_rpm" in n or "rpm" in n:
			return n
		n = n.get_parent()
	return null

## Read live rotor speed via duck typing — current_rpm() method wins (it's the
## post-ramp live value from RotatingMechanism), falling back to the `rpm`
## export which holds the commanded setpoint.
static func _read_rotor_rpm(rotor: Node) -> float:
	if rotor == null or not is_instance_valid(rotor):
		return 0.0
	if rotor.has_method("current_rpm"):
		return float(rotor.call("current_rpm"))
	if "current_rpm" in rotor:
		return float(rotor.get("current_rpm"))
	if "rpm" in rotor:
		return float(rotor.get("rpm"))
	return 0.0
