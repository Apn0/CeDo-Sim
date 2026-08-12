class_name MachineBrains
extends RefCounted

# =============================================================================
# Attaches the SIM BRAIN to a placed machine.
# =============================================================================
# The problem this fixes, measured rather than assumed (2026-08-11):
#
#   A booted MainWorld on a real 84-placeable save contains 8872 nodes across
#   67 distinct scripts and ZERO ExtruderMachine.gd. A 90-second recording of
#   every EventBus signal produced 0 events.
#
#   ExtruderModel is constructed in exactly one place (ExtruderMachine.gd:54),
#   ExtruderMachine.gd is attached to exactly one scene (Extruder3B.tscn), and
#   that scene was instantiated by exactly two scripts: ExtruderGauntlet.gd (a
#   visual bench) and LegacyPropsSpawner.gd — the latter gated behind
#   `not WorldLayout.is_configured()` (MainWorld.gd:244). So for every real
#   save the world prints "WorldLayout is authoritative — skipping legacy
#   utility/demo spawns" and no extruder brain is ever created.
#
#   The catalog's `extruder_3a` is geometry from _m_extruder_unit(). It looks
#   like an extruder and simulates nothing.
#
# What was therefore dark in a played shift:
#   * the vacuum cascade + 120 s grace + cascade_stop_all_except_pcu
#   * machine_state_changed / machine_alarm_raised / scada_event entirely
#   * the HMI MACHINES screen, which enumerates get_nodes_in_group(
#     "extruder_machine") (HmiOverlay.gd:518/529/561/1756/2132) — an empty
#     group, so nothing to select and no model behind the 7-zone panel
#   * HmiOverlay._find_laser_filter_for_scope(), which resolves a scope's
#     laser filter by finding that scope's extruder first and taking the
#     nearest filter to it — with no extruders it always fell back to
#     "filters[0]", i.e. every scope pointed at the same filter
#   * LaserFilter.gd, which IS spawned in the world (2 instances) and reads
#     lump_passthrough_rate_g_s off an extruder model that did not exist
#
# (An earlier draft of this comment also blamed the SWI-049 startup flow.
# That was wrong in the same way the bug it documents was wrong: SWI-049 is
# "Opstarten sorteerlijn" and SorteerlijnScope.gd contains no reference to
# extruders at all. Checked, not assumed.)
#
# The rest of the codebase was already written against the group. Only the
# spawn was missing, which is why this is a hook and not a subsystem.
# =============================================================================

const BRAIN_SCENE := "res://src/scenes/machines/Extruder3B.tscn"
const CONFIG_DIR  := "res://src/data/machines/"

## Catalog placeable id -> line id carried on its ExtruderConfig.
## One extruder per line (docs/plant), so this is 1:1 by construction.
const EXTRUDERS := {
	"extruder_3a": "3A",
	"extruder_3b": "3B",
	"extruder_1":  "1",
	"extruder_3c": "3C",
	"extruder_6":  "6",
}

const BRAIN_NAME := "SimBrain"


## True if `id` is a placeable that owns a simulation.
static func has_brain(id: String) -> bool:
	return EXTRUDERS.has(id)


## Attach the brain to a freshly built placeable body. Safe to call on anything:
## returns null unless the id is known. Idempotent — a body that already carries
## a brain is left alone, so BuildMode's rebuild_in_place() cannot stack two.
static func attach(body: Node3D, id: String, size: Vector3) -> Node:
	if body == null or not EXTRUDERS.has(id):
		return null
	if body.get_node_or_null(BRAIN_NAME) != null:
		return null

	var scn := load(BRAIN_SCENE) as PackedScene
	if scn == null:
		push_warning("[MachineBrains] %s missing — %s placed without a brain"
			% [BRAIN_SCENE, id])
		return null

	var brain := scn.instantiate() as Node3D
	if brain == null:
		return null
	brain.name = BRAIN_NAME

	# Config BEFORE add_child: ExtruderMachine._ready() builds the model from
	# config_resource, and _ready fires the moment the node enters the tree.
	# Setting it afterwards would leave every line calling itself "3B".
	brain.set("config_resource", _config_for(id, brain))

	# The brain scene ships a placeholder box mesh and its own collider. The
	# catalog model is the visible machine and already carries collision from
	# build_node, so both are switched off here — keeping them would put a
	# second 2.2 x 2.0 x 5.5 m box inside the real one. The InteractionArea and
	# the sim tick stay live; they are the whole point.
	var mesh := brain.get_node_or_null("Body/BodyMesh") as MeshInstance3D
	if mesh != null:
		mesh.visible = false
	var col := brain.get_node_or_null("Body/BodyCollision") as CollisionShape3D
	if col != null:
		col.disabled = true
	var lbl := brain.get_node_or_null("DebugLabel") as Label3D
	if lbl != null:
		lbl.visible = false

	# Fit the interaction volume to the machine that was actually placed. The
	# scene's box is 4 x 2 x 7 m, but a catalog extruder is 2.6 x 4.2 x 14 m —
	# with the stock box the operator can only interact with the middle third
	# and the ends read as dead metal.
	var ishape := brain.get_node_or_null(
		"InteractionArea/InteractionShape") as CollisionShape3D
	if ishape != null and ishape.shape is BoxShape3D:
		var box := (ishape.shape as BoxShape3D).duplicate() as BoxShape3D
		box.size = Vector3(size.x + 1.6, maxf(size.y, 2.0), size.z + 1.6)
		ishape.shape = box
		ishape.position = Vector3(0.0, box.size.y * 0.5, 0.0)

	body.add_child(brain)
	return brain


## Prefer a per-line config resource if one exists (Extruder3A.tres, ...);
## otherwise duplicate whatever the scene shipped and relabel it, so a missing
## .tres degrades to "right behaviour, right name" instead of a wrong line id.
static func _config_for(id: String, brain: Node) -> Resource:
	var line_id: String = String(EXTRUDERS[id])
	var path := "%sExtruder%s.tres" % [CONFIG_DIR, line_id]
	if ResourceLoader.exists(path):
		var res := load(path)
		if res != null:
			# ALWAYS duplicate, even when the line id already matches. load()
			# returns the cached resource, so handing it back unduplicated would
			# give two placeables of the same line one shared ExtruderConfig —
			# and any runtime write (a zone setpoint edited on the HMI) would
			# silently retune the other machine too.
			var owned := res.duplicate()
			owned.set("line_id", line_id)
			owned.set("display_name", "Extruder %s" % line_id)
			return owned

	var base = brain.get("config_resource")
	var cfg = base.duplicate() if base != null else ExtruderConfig.new()
	cfg.set("line_id", line_id)
	cfg.set("display_name", "Extruder %s" % line_id)
	return cfg
