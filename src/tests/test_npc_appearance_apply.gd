extends Node

## #224 — NPC customization SURVIVES reload AND is APPLIED to the spawned body.
## Companion to test_appearance_persistence (which proved GameState round-trips).
## This proves the APPLY half end-to-end, driving the REAL resolution code:
## NPCSpawner.resolve_npc_appearance() — the exact static the live spawn loop
## calls (extracted from the loop for testability) — then Humanoid.build().
##
## Scene-based (autoloads load): GameState.gd compiles against the EventBus
## autoload, and NPCSpawner.gd against Plant — neither resolves under --script.
##   godot --headless --path <proj> res://src/tests/test_npc_appearance_apply.tscn
##
## Observable (per code trace): the built body has NO named "Hair"/"Cap" node —
## hair is unnamed _box() meshes, and hair=="bald" simply SKIPS them. So the
## count of MeshInstance3D descendants is the observable. find_children MUST use
## owned=false: runtime meshes have no owner, so the default owned=true yields 0.
##
## NON-VACUOUS by construction:
##   Control A proves the observable has meaning (short hair == bald + 2 meshes),
##   so the later "custom bald body has 2 fewer meshes than the preset" assertion
##   is attributable to hair, not noise. Control D proves the resolver still
##   returns the PRESET for an un-customized NPC (it doesn't blanket-override).
##
## Checks:
##   A. CONTROL: Humanoid.build hair "short" has exactly +2 meshes vs "bald"
##      (and cap:true adds +2) — the observable is real, not vacuous.
##   B. Save custom npc_appearances -> fresh GameState -> load restores it.
##   C. resolve_npc_appearance picks the CUSTOM look over the NPC_DATA preset.
##   D. resolve_npc_appearance falls back to the PRESET for an un-customized NPC.
##   E. APPLY: body built from the resolved custom look has exactly 2 FEWER
##      meshes than the preset body (only hair differs) — the bald reached geometry.

const GameStateScript = preload("res://src/scenes/world/GameState.gd")
const Spawner = preload("res://src/scenes/world/NPCSpawner.gd")
const Humanoid = preload("res://src/scenes/world/Humanoid.gd")

const SAVE_PATH := "user://test_npc_appearance_apply_save.json"

var _fails : int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

# Count MeshInstance3D descendants. owned=false is REQUIRED (runtime meshes,
# reparented under BoneAttachment3D, have no owner → owned=true returns 0).
func _mesh_count(body: Node) -> int:
	return body.find_children("*", "MeshInstance3D", true, false).size()

func _ready() -> void:
	print("[TEST] npc appearance apply (save->load->resolve->build)")
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	var col : Color = Color(0.8, 0.3, 0.3)

	# ── CONTROL A — the mesh-count observable is real (not vacuous). ────────
	var b_bald   : Node3D = Humanoid.build(col, 0, {"hair": "bald",  "beard": "none", "cap": false})
	var b_short  : Node3D = Humanoid.build(col, 0, {"hair": "short", "beard": "none", "cap": false})
	var b_cap    : Node3D = Humanoid.build(col, 0, {"hair": "bald",  "beard": "none", "cap": true})
	var n_bald  : int = _mesh_count(b_bald)
	var n_short : int = _mesh_count(b_short)
	var n_cap   : int = _mesh_count(b_cap)
	_check(n_short == n_bald + 2, "A CONTROL short hair == bald + 2 meshes (%d vs %d)" % [n_short, n_bald])
	_check(n_cap == n_bald + 2, "A CONTROL cap on bald == bald + 2 meshes (%d vs %d)" % [n_cap, n_bald])
	_check(n_bald > 0, "A CONTROL bald body still has meshes (%d) — observable non-zero" % n_bald)
	b_bald.free(); b_short.free(); b_cap.free()

	# ── Author a custom look for Mohammed: preset is hair "mid" (+2) + full
	# beard; we flip ONLY hair -> bald, keeping beard "full" so the preset-vs-
	# custom mesh delta is attributable to hair alone. Primitives only (JSON-safe).
	var custom_mohammed := {"hair": "bald", "beard": "full", "cap": false,
							 "height_mul": 1.0, "width_mul": 1.0}

	var gs1 = GameStateScript.new()          # .new() does not run _ready() (no autoload touch)
	gs1.save_file_path = SAVE_PATH
	gs1.npc_appearances = {"mohammed": custom_mohammed.duplicate(true)}
	gs1.save_game()
	gs1.free()

	# ── B — reload restores npc_appearances. ────────────────────────────────
	var gs2 = GameStateScript.new()
	gs2.save_file_path = SAVE_PATH
	gs2.load_game()
	_check(gs2.npc_appearances.get("mohammed", {}).get("hair", "") == "bald",
		"B reload restores custom npc_appearances (mohammed hair == bald)")

	# ── C — the REAL resolver picks CUSTOM over the NPC_DATA preset. ─────────
	var preset_moh : Dictionary = Spawner.NPC_DATA["mohammed"]["appearance"]
	_check(String(preset_moh.get("hair", "")) == "mid",
		"C precondition: preset Mohammed hair is 'mid' (so bald is a real change)")
	var resolved_moh : Dictionary = Spawner.resolve_npc_appearance("mohammed", Spawner.NPC_DATA["mohammed"], gs2)
	_check(String(resolved_moh.get("hair", "")) == "bald",
		"C resolver returns the CUSTOM look (hair bald), not the preset (mid)")

	# ── D — resolver falls back to PRESET for an un-customized NPC. ──────────
	var resolved_peter : Dictionary = Spawner.resolve_npc_appearance("peter", Spawner.NPC_DATA["peter"], gs2)
	var preset_peter : Dictionary = Spawner.NPC_DATA["peter"]["appearance"]
	_check(resolved_peter.get("height_mul", -1.0) == preset_peter.get("height_mul", -2.0)
		and not gs2.npc_appearances.has("peter"),
		"D resolver returns the PRESET for an un-customized NPC (no blanket override)")

	# ── E — APPLY: the resolved custom look reaches the built geometry. ──────
	var mcol : Color = Spawner.NPC_DATA["mohammed"]["color"]
	var body_custom : Node3D = Humanoid.build(mcol, 0, resolved_moh)          # bald
	var body_preset : Node3D = Humanoid.build(mcol, 0, preset_moh)            # mid hair
	var c_custom : int = _mesh_count(body_custom)
	var c_preset : int = _mesh_count(body_preset)
	_check(c_preset == c_custom + 2,
		"E applied custom body has 2 FEWER meshes than preset (bald removed hair): preset %d, custom %d" % [c_preset, c_custom])
	body_custom.free(); body_preset.free()
	gs2.free()

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	if _fails == 0:
		print("[TEST] npc appearance apply PASS")
	else:
		print("[TEST] npc appearance apply FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
