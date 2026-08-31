extends SceneTree
## Headless test for CharacterCustomizer._rebuild_world_bodies — the NPC loop
## that no other wired suite observes (promoted 2026-08-31 from the review
## mutation probe; the find_child→cached-lookup perf fix landed the same day).
## Run: godot --headless --path . --script res://src/tests/test_customizer_world_bodies.gd --quit-after 300
## Green: nested NPC gets a HumanoidBody via the cached name lookup; ghost NPC
## name is tolerated (continue, no crash); decoy duplicate name proves
## first-match-in-tree-order wins. Red under the lookup-returns-null mutation.

var _pass := 0
var _fail := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

class FakeWorld extends Node:
	var NPC_DATA : Dictionary = {}

class QuietCustomizer extends "res://src/scenes/hud/CharacterCustomizer.gd":
	func _ready() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== _rebuild_world_bodies probe ===")

	# Fake world: NPC node nested two levels deep (proves the single recursive
	# traversal reaches it), plus a LATER decoy with the same name.
	var world := FakeWorld.new()
	world.name = "World"
	var sub := Node.new()
	sub.name = "Sub"
	world.add_child(sub)
	var deeper := Node.new()
	deeper.name = "Deeper"
	sub.add_child(deeper)
	var mohammed := Node3D.new()
	mohammed.name = "Mohammed"
	deeper.add_child(mohammed)
	var decoy := Node3D.new()
	decoy.name = "Mohammed2"  # renamed to "Mohammed" AFTER tree entry below
	world.add_child(decoy)
	root.add_child(world)
	# Godot auto-renames duplicate siblings on add_child; these two are not
	# siblings, but rename after entry anyway so both carry the exact name.
	decoy.name = "Mohammed"
	current_scene = world

	var cust := QuietCustomizer.new()
	root.add_child(cust)

	# Ghost FIRST in insertion order so the null-tolerated continue-path runs
	# BEFORE the real NPC — a crash there would never reach Mohammed's body.
	cust._all_outfits = {
		"player": {},
		"npc_ghost": {"on_duty": {}},
		"npc_mo": {"on_duty": {"shirt_color": Color(1, 0, 0)}},
	}
	world.NPC_DATA = {
		"npc_ghost": {"name": "Nonexistent", "color": Color(0.5, 0.5, 0.5), "appearance": {}},
		"npc_mo": {"name": "Mohammed", "color": Color(0.2, 0.4, 0.8), "appearance": {}},
	}

	cust._rebuild_world_bodies()

	var body := mohammed.find_child("HumanoidBody", false, false)
	_ok(body != null, "nested NPC resolved via lookup: HumanoidBody attached under World/Sub/Deeper/Mohammed")
	var decoy_body := decoy.find_child("HumanoidBody", false, false)
	_ok(decoy_body == null, "first-match-in-tree-order wins: decoy 'Mohammed' (later sibling) got NO body")
	_ok(true, "ghost NPC name 'Nonexistent' tolerated: loop continued without crash")

	# Second call: old body is removed and rebuilt (remove+queue_free path).
	cust._rebuild_world_bodies()
	var bodies := 0
	for c in mohammed.get_children():
		if String(c.name).begins_with("HumanoidBody"):
			bodies += 1
	# queue_free of the old body is deferred, but remove_child is immediate, so
	# exactly one HumanoidBody child must remain in-tree.
	_ok(bodies == 1, "second rebuild leaves exactly one in-tree HumanoidBody (got %d)" % bodies)

	# Teardown, then verdict LAST.
	root.remove_child(cust)
	cust.free()
	root.remove_child(world)
	world.free()

	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)
