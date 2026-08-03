extends Node

## #224 — Character-customization persistence round-trip.
## Scene-based (not --script) so the project autoloads load — GameState.gd
## references the EventBus autoload at compile time, which --script can't resolve.
## Run:  godot --headless --path <proj> res://src/tests/test_appearance_persistence.tscn
## Proves the fix for "I modified characters, now they're all reset to base":
## GameState now DECLARES + SAVES + LOADS player_wardrobes + player_name (they
## used to be dropped silently because gs.set() no-ops on an undeclared prop),
## and an empty-in-memory save no longer clobbers on-disk customizations.
##
##   godot --headless --path <proj> --script src/tests/test_appearance_persistence.gd
##
## Checks:
##   A. player_wardrobes round-trips (was never persisted before).
##   B. player_name round-trips.
##   C. npc_appearances round-trips (regression guard).
##   D. player_appearance round-trips.
##   E. Anti-clobber: a FRESH (empty) GameState saving over the file preserves
##      the customization instead of blanking it — the "reset to base" symptom.
##   F. clear_save() wipes all appearance fields (no stale leak into a new game).

const GameStateScript = preload("res://src/scenes/world/GameState.gd")

const SAVE_PATH := "user://test_appearance_roundtrip_save.json"

var _fails : int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

func _make_gs() -> Node:
	# .new() does NOT run _ready(), so the EventBus autoload lookup in _ready is
	# never hit — save_game()/load_game() touch neither the tree nor autoloads.
	var gs = GameStateScript.new()
	gs.save_file_path = SAVE_PATH
	return gs

func _ready() -> void:
	print("[TEST] appearance persistence round-trip")
	# Clean slate.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	# ── Author a customization exactly as CharacterCustomizer._commit does:
	# colors already flattened to {r,g,b} dicts (JSON-safe).
	var wardrobe := {
		"Arno": {
			"on_duty":  {"hair": "buzz", "beard": "goatee", "ppe": "operator",
						 "shirt_color": {"r": 0.95, "g": 0.92, "b": 0.10}},
			"off_duty": {"hair": "buzz", "beard": "goatee", "ppe": "none",
						 "shirt_color": {"r": 0.40, "g": 0.45, "b": 0.55}},
		}
	}
	var npc_ap := {
		"pascal": {"hair": "bald", "beard": "none", "height_mul": 0.90},
		"kevin":  {"cap": true, "hair": "short", "beard": "thin"},
	}
	var player_flat : Dictionary = (wardrobe["Arno"]["on_duty"] as Dictionary).duplicate(true)

	var gs1 = _make_gs()
	gs1.player_wardrobes = wardrobe.duplicate(true)
	gs1.player_name = "Arno"
	gs1.npc_appearances = npc_ap.duplicate(true)
	gs1.player_appearance = player_flat.duplicate(true)
	gs1.save_game()
	gs1.free()

	# ── Fresh GameState, same path → load (simulates a reload).
	var gs2 = _make_gs()
	gs2.load_game()
	_check(gs2.player_wardrobes.has("Arno")
		and gs2.player_wardrobes["Arno"].get("on_duty", {}).get("hair", "") == "buzz",
		"A player_wardrobes round-trips (Arno/on_duty/hair == buzz)")
	_check(gs2.player_name == "Arno", "B player_name round-trips (== Arno)")
	_check(gs2.npc_appearances.get("pascal", {}).get("hair", "") == "bald"
		and bool(gs2.npc_appearances.get("kevin", {}).get("cap", false)) == true,
		"C npc_appearances round-trips (pascal bald + kevin cap)")
	_check(gs2.player_appearance.get("ppe", "") == "operator",
		"D player_appearance round-trips (ppe == operator)")

	# ── Anti-clobber: a fresh EMPTY GameState saves over the same file. The old
	# behaviour blanked the appearance to {}; the guard must preserve it.
	var gs3 = _make_gs()
	# all appearance dicts empty (fresh), just like an autosave before load ran
	gs3.save_game()
	gs3.free()
	var gs4 = _make_gs()
	gs4.load_game()
	_check(gs4.player_wardrobes.has("Arno")
		and gs4.player_name == "Arno"
		and gs4.npc_appearances.get("pascal", {}).get("hair", "") == "bald",
		"E anti-clobber: empty-in-memory save did NOT wipe on-disk customization")

	# ── clear_save wipes everything (new-game hygiene).
	gs4.clear_save()
	_check(gs4.player_wardrobes.is_empty() and gs4.npc_appearances.is_empty()
		and gs4.player_appearance.is_empty() and gs4.player_name == "",
		"F clear_save() clears all appearance fields")
	gs4.free()
	gs2.free()

	# Cleanup.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	if _fails == 0:
		print("[TEST] appearance persistence PASS")
	else:
		print("[TEST] appearance persistence FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
