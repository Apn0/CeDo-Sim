extends Node

## #224 — CharacterCustomizer reaches the REAL GameState (the write-side fix).
## The actual "customized, then reset to base" bug: GameState is NOT an autoload
## (MainWorld.tscn holds it as a child node), but the customizer looked it up at
## "/root/GameState" — always null — so _commit_to_gamestate() hit `if gs == null:
## return` and saved NOTHING. This proves _resolve_game_state() now finds the node
## a MainWorld-shaped scene exposes, exactly where the old lookup failed.
##   godot --headless --path <proj> res://src/tests/test_customizer_resolves_gamestate.tscn
##
## Checks:
##   A. PRECONDITION (proves the bug was real): the old path get_node_or_null(
##      "/root/GameState") returns null in this scene — GameState is a child node.
##   B. FIX: customizer._resolve_game_state() returns the scene's GameState node.
##   C. NON-VACUOUS: that resolved node is the SAME instance we put in the scene
##      (find_child by name), not some unrelated object.

const GameStateScript = preload("res://src/scenes/world/GameState.gd")
const CustomizerScript = preload("res://src/scenes/hud/CharacterCustomizer.gd")

# Subclass that skips the heavy UI _ready (SubViewport + preview Humanoid +
# AnimationTree) — we only need to exercise the REAL inherited _resolve_game_state.
# Booting the full customizer headless overflows the preview render; that path is
# unrelated to the GameState-resolution fix under test.
class QuietCustomizer extends CustomizerScript:
	func _ready() -> void:
		pass

var _fails : int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

func _ready() -> void:
	print("[TEST] customizer resolves the real GameState node")

	# This test scene IS get_tree().current_scene — give it a GameState CHILD,
	# mirroring MainWorld.tscn (node named "GameState", not an autoload).
	var gs_node = GameStateScript.new()
	gs_node.name = "GameState"
	add_child(gs_node)

	# A — the old lookup path is null here (the bug). Non-vacuous: proves the fix
	# is addressing a real gap, not a no-op.
	_check(get_node_or_null("/root/GameState") == null,
		"A PRECONDITION: /root/GameState is null (GameState is a scene child, not an autoload)")

	# Parent under this scene (current_scene) so cust is in-tree and its
	# get_tree().current_scene resolves to us — the same shape as the customizer
	# living under a MainWorld that has a GameState child. UI-less subclass avoids
	# the preview-render overflow.
	var cust = QuietCustomizer.new()
	add_child(cust)
	_check(cust.is_inside_tree(), "B0 customizer is in the scene tree")

	# B + C — the fix resolves the real node.
	var resolved = cust._resolve_game_state()
	_check(resolved != null, "B _resolve_game_state() returns non-null (fix reaches GameState)")
	_check(resolved == gs_node, "C resolved node IS the scene's GameState instance (not unrelated)")

	cust.queue_free()
	gs_node.queue_free()

	if _fails == 0:
		print("[TEST] customizer resolve PASS")
	else:
		print("[TEST] customizer resolve FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
