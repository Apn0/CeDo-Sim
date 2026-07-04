extends Object

class_name LegacyPropsSpawner

# =============================================================================
# #195 follow-up — Legacy demo / utility / clutter props extracted from
# MainWorld.gd. All of these are gated by !WorldLayout.is_configured() (the
# user hasn't run WorldSetup yet), and several are further gated by
# !CLEAN_CANVAS (the in-source "show the test props" toggle).
# =============================================================================
# Static-helpers pattern: every function takes `world: Node` (MainWorld) as
# its first argument and routes back to MainWorld helpers via that ref —
# _get_factory_anchor(), _vehicle_anchor(), _floor_top_y(), _player_spawn_node(),
# _local_aabb(...), _fit_box_collider(...). Spawned nodes are still parented
# under MainWorld so the scene-tree shape is identical to pre-extract.

# #11 — rebuilt to drive the REAL clamp controls (no teleport-grab).
const FEEDERS_ENABLED : bool = true

# ── Public entry point ──────────────────────────────────────────────────────
## Call from MainWorld in place of the old inline legacy-prop block. Honours
## CLEAN_CANVAS on the world (the in-source toggle that hides the test props).
static func spawn_all(world: Node, factory_anchor: Vector3, vehicle_anchor: Vector3, floor_top_y: float) -> void:
	_spawn_battery_station(world)
	_spawn_shift_leader_desk(world)
	_spawn_service_stations(world)
	_spawn_wire_cutter(world)
	_spawn_lpg_rack(world)
	var clean_canvas : bool = bool(world.get("CLEAN_CANVAS"))
	if not clean_canvas:
		_spawn_extruder_3b(world)
		# _spawn_bale_yard stays on MainWorld (not in our spec).
		_spawn_test_bunker(world)
		_spawn_test_skip(world)
		_spawn_test_waste_zones(world)
	_spawn_feeder_line(world)

# =============================================================================
# TEST BUNKER — an intake pit beside the player to dump carried bales into
# =============================================================================
## Drops a single intake bunker a short distance from the player's spawn so the
## full loop is testable on the spot: grab a stack from the yard → carry it over →
## release it at the bunker → LineFlow picks up the delivered bale and meters it in.
## Tagged "placed_object" + "feed_machine" like a build-placed one so LineFlow's
## scan treats it as a real feed point.
static func _spawn_test_bunker(world: Node) -> void:
	var base : Vector3 = world.call("_get_factory_anchor")
	# In front of the player, past the bale yard, clear of the vehicle row.
	# -0.9 grounds the base (anchor is the player capsule centre, ~0.9 m up).
	base += Vector3(2.0, -0.9, 14.0)
	var bunker := PlaceableCatalog.build_node("bunker", false) as Node3D
	if bunker == null:
		push_warning("[LegacyPropsSpawner] test bunker build failed")
		return
	world.add_child(bunker)
	bunker.global_position = base
	print("[LegacyPropsSpawner] Test bunker spawned at %s" % str(base))

# =============================================================================
# MACHINES — Extruder 3B (first machine sim, drives the 120s cascade test)
# =============================================================================
static func _spawn_extruder_3b(world: Node) -> void:
	var ext_scene := load("res://src/scenes/machines/Extruder3B.tscn") as PackedScene
	if not ext_scene:
		push_warning("[LegacyPropsSpawner] Extruder3B.tscn missing — skipping")
		return
	var ext := ext_scene.instantiate()
	world.add_child(ext)
	# Park 15 m forward of player spawn so they can walk to it
	var marker : Node3D = world.call("_player_spawn_node")
	if marker:
		var pos := marker.global_position
		pos.z -= 15.0
		pos.y += 0.0
		ext.global_position = pos
	print("[LegacyPropsSpawner] Extruder 3B placed")

# =============================================================================
# BATTERY STATION — walkie-battery charger bench in the shift-leader office
# =============================================================================
## A small bench (charger + drawer + shelf) near the extruders, where the player
## swaps walkie packs. The single charger is the social bottleneck (see
## BatteryStation.gd). Modeled procedurally so no .tscn is needed.
static func _spawn_battery_station(world: Node) -> void:
	var station := BatteryStation.new()
	station.name = "BatteryStation"
	# Near the extruder (which sits ~15 m -Z of spawn), offset to the side so it
	# reads as a corner office bench rather than blocking the machine.
	var anchor : Vector3 = world.call("_get_factory_anchor")
	anchor += Vector3(-6.0, 0.0, -15.0)
	world.add_child(station)
	station.global_position = anchor
	_build_battery_station_model(world, station)
	world.call("_fit_box_collider", station)   # #10 — solid bench, not just a proximity trigger
	print("[LegacyPropsSpawner] Battery station (walkie charger) @ %s" % str(anchor))

## #3 — the shift-leader's desk + computer in the office, beside the walkie-battery
## bench. Walk up + E opens the bale scan-log terminal (ScanLog → ShiftLeaderTerminal).
static func _spawn_shift_leader_desk(world: Node) -> void:
	var desk : Node3D = load("res://src/scenes/world/ShiftLeaderDesk.gd").new()
	desk.name = "ShiftLeaderDesk"
	var anchor : Vector3 = world.call("_get_factory_anchor")
	world.add_child(desk)
	desk.global_position = anchor + Vector3(-9.0, 0.0, -14.0)
	print("[LegacyPropsSpawner] Shift-leader desk (scan log) @ %s" % str(desk.global_position))

## A procedural bench: worktop, a charger block with a status LED, a drawer, and a
## shelf — just enough to read as "the charging corner". Cosmetic; the logic lives
## in BatteryStation.gd.
static func _build_battery_station_model(_world: Node, station: Node3D) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.44, 0.48)
	steel.metallic = 0.5
	steel.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.16, 0.18)
	var led := StandardMaterial3D.new()
	led.albedo_color = Color(0.2, 0.9, 0.3)
	led.emission_enabled = true
	led.emission = Color(0.2, 0.9, 0.3)
	led.emission_energy_multiplier = 2.0

	# Worktop
	var top := MeshInstance3D.new()
	var topm := BoxMesh.new(); topm.size = Vector3(1.8, 0.08, 0.7)
	top.mesh = topm; top.material_override = steel
	top.position = Vector3(0, 0.9, 0)
	station.add_child(top)
	# Legs
	for sx in [-0.8, 0.8]:
		for sz in [-0.28, 0.28]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new(); lm.size = Vector3(0.07, 0.9, 0.07)
			leg.mesh = lm; leg.material_override = dark
			leg.position = Vector3(sx, 0.45, sz)
			station.add_child(leg)
	# Charger block (left) with status LED
	var charger := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.34, 0.22, 0.34)
	charger.mesh = cm; charger.material_override = dark
	charger.position = Vector3(-0.55, 1.05, 0)
	station.add_child(charger)
	var lamp := MeshInstance3D.new()
	var lampm := SphereMesh.new(); lampm.radius = 0.03; lampm.height = 0.06
	lamp.mesh = lampm; lamp.material_override = led
	lamp.position = Vector3(-0.55, 1.19, 0.14)
	station.add_child(lamp)
	# Fresh drawer (centre) + empty shelf (right) as labelled trays
	for data in [{"x": 0.05, "c": Color(0.2, 0.5, 0.25)}, {"x": 0.6, "c": Color(0.5, 0.35, 0.2)}]:
		var tray := MeshInstance3D.new()
		var tm := BoxMesh.new(); tm.size = Vector3(0.4, 0.06, 0.46)
		var trm := StandardMaterial3D.new(); trm.albedo_color = data["c"]
		tray.mesh = tm; tray.material_override = trm
		tray.position = Vector3(data["x"], 0.97, 0)
		station.add_child(tray)

# =============================================================================
# SERVICE STATIONS — wall outlet (electric lift) + diesel pump
# =============================================================================
## A power outlet beside the lift's parking spot, and a diesel bowser by the
## vehicle row. Both anchor to the player's actual spawn so they're reachable.
static func _spawn_service_stations(world: Node) -> void:
	var anchor : Vector3 = world.call("_get_factory_anchor")

	# Wall outlet — near the lift (which parks at +20 on X).
	var outlet := ServiceStation.new()
	outlet.name = "PowerOutlet"
	outlet.mode = "outlet"
	world.add_child(outlet)
	outlet.global_position = anchor + Vector3(22.5, 0.0, 0.0)
	_build_outlet_model(world, outlet)
	world.call("_fit_box_collider", outlet)   # #10 — solid post

	# Diesel pump — near the Merlo (which parks at +15 on X).
	var pump := ServiceStation.new()
	pump.name = "FuelPump"
	pump.mode = "pump"
	world.add_child(pump)
	pump.global_position = anchor + Vector3(13.0, 0.0, -3.0)
	_build_pump_model(world, pump)
	world.call("_fit_box_collider", pump)   # #10 — solid bowser
	print("[LegacyPropsSpawner] Service stations: outlet @ %s · pump @ %s"
		% [str(outlet.global_position), str(pump.global_position)])

static func _build_outlet_model(_world: Node, st: Node3D) -> void:
	var box := StandardMaterial3D.new(); box.albedo_color = Color(0.85, 0.82, 0.2)
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.12, 0.12, 0.13)
	# Yellow industrial outlet box on a short post.
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3(0.12, 1.1, 0.12)
	post.mesh = pm; post.material_override = dark; post.position = Vector3(0, 0.55, 0)
	st.add_child(post)
	var bx := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.34, 0.4, 0.22)
	bx.mesh = bm; bx.material_override = box; bx.position = Vector3(0, 1.15, 0)
	st.add_child(bx)
	# Two socket dots.
	for sx in [-0.07, 0.07]:
		var s := MeshInstance3D.new()
		var sm := CylinderMesh.new(); sm.top_radius = 0.04; sm.bottom_radius = 0.04
		sm.height = 0.04; sm.radial_segments = 10
		s.mesh = sm; s.material_override = dark
		s.transform = Transform3D(Basis(Vector3(1,0,0), PI/2.0), Vector3(sx, 1.15, 0.12))
		st.add_child(s)

static func _build_pump_model(_world: Node, st: Node3D) -> void:
	var red := StandardMaterial3D.new(); red.albedo_color = Color(0.6, 0.13, 0.1)
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.14, 0.14, 0.15)
	var blue := StandardMaterial3D.new(); blue.albedo_color = Color(0.2, 0.4, 0.7)
	# Diesel bowser body.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.8, 1.5, 0.6)
	body.mesh = bm; body.material_override = red; body.position = Vector3(0, 0.75, 0)
	st.add_child(body)
	# A small blue AdBlue can beside it.
	var can := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.35, 0.5, 0.35)
	can.mesh = cm; can.material_override = blue; can.position = Vector3(0.6, 0.25, 0)
	st.add_child(can)
	# Hose reel.
	var reel := MeshInstance3D.new()
	var rm := CylinderMesh.new(); rm.top_radius = 0.18; rm.bottom_radius = 0.18
	rm.height = 0.12; rm.radial_segments = 14
	reel.mesh = rm; reel.material_override = dark
	reel.transform = Transform3D(Basis(Vector3(0,0,1), PI/2.0), Vector3(-0.46, 1.0, 0))
	st.add_child(reel)

# =============================================================================
# WIRE-CUTTER TOOL — the "concrete scissors" the operator carries on foot
# =============================================================================
## Drop a single WireCutter near the bale clamp's parking spot. The operator
## walks up, presses E to pick it up, then can left-click on bales to cut wires
## one at a time. The in-cab Shift+B cut was removed — this is the real flow.
# =============================================================================
# LPG CYLINDER RACK — outside near the vehicle row
# =============================================================================
static func _spawn_lpg_rack(world: Node) -> void:
	var rack_script := preload("res://src/scenes/world/LPGRack.gd")
	var rack := rack_script.new()
	rack.name = "LPGRack"
	world.add_child(rack)
	var anchor : Vector3 = world.call("_vehicle_anchor")
	# A few metres in front of the vehicle row, broadside on so the operator
	# can walk a tank straight from the rack to the forklift cab.
	rack.global_position = anchor + Vector3(-6.0, 0.0, 4.0)
	print("[LegacyPropsSpawner] LPGRack @ %s" % str(rack.global_position))

# =============================================================================
# FEEDER LINE — wide shredder feed belt + a bale lot + autonomous NPC feeders
# =============================================================================
## Two crewed feed stations, one per worker, each with its OWN belt + bale lot +
## personal vehicle + personal scissors & scanner:
##   • Abdullah — Line 1      — drives a Merlo
##   • Mohammed — Line 3A/3B  — drives a bale clamp
## The vehicles are fresh NPC-owned instances (tagged so the player can't board
## them). Tools ride on each worker's holster and aren't player-grabbable.
## Feeders are DISABLED until rebuilt with REAL clamp physics. The current NPCs use
## npc_carry_bale, which teleport-reparents the bale onto the clamp instead of driving
## the mast/clamp controls + force-grabbing it — exactly the "from a distance /
## pre-programmed" the operator forbids — and that childed-bale machinery is the prime
## suspect for the non-finite-transform spam. Disabling them gives a clean, stable scene
## to verify the canvas + rebuilt Line 3C, and stops the "both feeders feeding" bug.
## Rebuild plan: Mohammed feeds Line 3C via the real clamp (lower mast → close plates →
## force-grip → lift → drive → place); Abdullah only stages bales for him. (#6 + rework)
static func _spawn_feeder_line(world: Node) -> void:
	if not FEEDERS_ENABLED:
		print("[LegacyPropsSpawner] Feeders DISABLED (rebuilding with real clamp physics) — clean scene.")
		return
	var base : Vector3 = world.call("_get_factory_anchor")
	# Two autonomous feed stations — one per shred line. Each has its own
	# opzetband (feed belt) + shredder + bale-clamp vehicle + worker with
	# scissors & scanner. Stations are placed on opposite sides of the base
	# anchor so the approach lanes don't overlap.
	# ONE feeder station: Mohammed on Line 3A/3B (operator-confirmed, twice).
	# Abdullah is Line 1 — that line doesn't exist yet, so he has NO station
	# and stays with the regular crew (idle/chill). Do NOT give him a station
	# until Line 1 is actually built.
	# #50 — switched from the legacy "shredder_3a3b" id (generic 3x2.5x3 _m_shredder
	# blob) to the bespoke "shredder_1" model (4x9x5 with rotor + stators + discharge
	# conveyor). The old id was removed from the catalog as part of the dedupe pass.
	_spawn_feeder_station(world, base + Vector3( 12.0, -0.9, 24.0), "Mohammed",
			"Line 3A/3B", "res://src/scenes/vehicles/BaleClamp.tscn",
			"shredder_1")

## Build one station: belt + lot + worker + the worker's personal vehicle +
## personal scissors & scanner. `shredder_id` picks which catalog shredder
## sits at the belt's discharge — different per line so the right LineFlow
## machine receives the shredded film.
static func _spawn_feeder_station(world: Node, station: Vector3, worker_name: String,
		line_name: String, vehicle_scene_path: String,
		shredder_id: String) -> FeederWorker:
	# 1) Wide feed belt.
	var belt = preload("res://src/scenes/world/ShredderFeedBelt.gd").new()
	belt.name = "ShredderFeedBelt_%s" % worker_name
	world.add_child(belt)
	belt.global_position = station

	# 2) The SHREDDER at the belt's discharge. Tagged "shredder" so the belt's
	#    PLC interlock is satisfied and the opzetband runs (#30/#31). Seated on
	#    the floor. `shredder_id` is per-station so Line 3A/3B vs Line 3C/6 each
	#    get their own machine.
	var shredder := PlaceableCatalog.build_node(shredder_id, false) as Node3D
	if shredder != null:
		world.add_child(shredder)
		shredder.add_to_group("shredder")
		var disc := (belt as Node3D).to_global(Vector3(0.0, 0.0, belt.deck_length + belt.incline_run + 2.0))
		disc.y = world.call("_floor_top_y")
		var sbb : AABB = world.call("_local_aabb", shredder)
		shredder.global_position = Vector3(disc.x, disc.y - sbb.position.y, disc.z)

	# (No bale lot / prepped bales — feedstock is built from the build menu now. #32)
	var lot_center := station + Vector3(7.0, 0.0, 0.0)

	# 3) The worker.
	var worker = preload("res://src/scenes/world/FeederWorker.gd").new()
	worker.worker_name = worker_name
	worker.assigned_line = line_name
	worker.lot_center = lot_center
	worker.lot_radius = 16.0
	world.add_child(worker)
	worker.global_position = station + Vector3(3.0, 1.0, 2.0)

	# 4) Their personal vehicle (NPC-owned), parked behind the worker.
	var vscene := load(vehicle_scene_path) as PackedScene
	if vscene:
		var v := vscene.instantiate() as Node3D
		world.add_child(v)
		v.global_position = station + Vector3(2.0, 0.5, -3.0)
		worker.assign_vehicle(v)

	# 5) Personal scissors + scanner on the holster (not player-grabbable).
	var scissors := WireCutter.new()
	world.add_child(scissors)
	scissors.global_position = worker.global_position
	worker.stow_personal_tool(scissors, -1.0)
	var scanner := preload("res://src/scenes/world/BarcodeScanner.gd").new()
	world.add_child(scanner)
	scanner.global_position = worker.global_position
	worker.stow_personal_tool(scanner, 1.0)
	worker.personal_scissors = scissors
	worker.personal_scanner = scanner

	print("[LegacyPropsSpawner] Feeder station: %s on %s (vehicle %s)" % \
			[worker_name, line_name, vehicle_scene_path.get_file()])
	return worker

static func _spawn_wire_cutter(world: Node) -> void:
	var anchor : Vector3 = world.call("_get_factory_anchor")
	# Sit it on the floor between the bale clamp (+10 X) and the bale yard (+6 X,
	# +6 Z), so it's right where the wire-cutting action happens.
	# anchor.Y is now the floor surface (was the capsule centre); no Y fudge needed.
	var cutter_pos := anchor + Vector3(8.0, 0.0, 3.0)
	var cutter := WireCutter.new()
	cutter.name = "WireCutter"
	world.add_child(cutter)
	cutter.global_position = cutter_pos
	print("[LegacyPropsSpawner] WireCutter (concrete scissors) @ %s" % str(cutter_pos))

	# Personal cabin props (#162): a coffee + a sandwich on the floor near the
	# scissors. Pick up with E, hotbar-swap to them, then G to place into a cab
	# slot — the coffee snaps into the cup holder, the sandwich onto a surface.
	var prop_script := preload("res://src/scenes/world/CabinProp.gd")
	var coffee : Node3D = prop_script.new()
	coffee.prop_kind = "coffee"
	world.add_child(coffee)
	coffee.global_position = anchor + Vector3(8.6, 0.0, 3.4)
	var sandwich : Node3D = prop_script.new()
	sandwich.prop_kind = "sandwich"
	world.add_child(sandwich)
	sandwich.global_position = anchor + Vector3(8.9, 0.0, 3.4)
	print("[LegacyPropsSpawner] Cabin props (coffee + sandwich) spawned")

	# Drop a barcode scanner half a metre to the right of the scissors. The
	# operator picks it up the same way (E), swaps to it with hotbar 1-4, and
	# left-clicks to scan a bale / container label. Right-click peels the
	# label off into a held LabelItem.
	var scanner_pos := anchor + Vector3(8.6, 0.0, 3.0)
	var scanner := BarcodeScanner.new()
	scanner.name = "BarcodeScanner"
	world.add_child(scanner)
	scanner.global_position = scanner_pos
	print("[LegacyPropsSpawner] BarcodeScanner @ %s" % str(scanner_pos))

	# Shovel (#154) — for cleaning up chute-spill floor piles into a container.
	var shovel := preload("res://src/scenes/world/ShovelTool.gd").new()
	shovel.name = "ShovelTool"
	world.add_child(shovel)
	shovel.global_position = anchor + Vector3(9.2, 0.0, 3.0)
	print("[LegacyPropsSpawner] ShovelTool @ %s" % str(shovel.global_position))

# =============================================================================
# TEST SKIP + DUMP ZONE — Wave 5 MVP
# =============================================================================
## A single PLASTIC steel skip near the test bunker so the operator can:
##   1. Forklift up to it (skip has forklift pockets at base)
##   2. Press B to grab it onto the forks
##   3. Drive to the orange-striped dump zone
##   4. Press V to release — the skip's contents are emptied at the tip area
## Skip is configured for the COARSE_FILM stream so LineFlow routes plastic
## rejects into it automatically.
static func _spawn_test_skip(world: Node) -> void:
	var anchor : Vector3 = world.call("_get_factory_anchor")

	# Steel skip — drop it 4 m to the +X side of the test bunker so the forklift
	# can swing around to pick it up. anchor.Y is the floor surface now.
	var skip := PlaceableCatalog.build_node("skip_steel", false) as Node3D
	if skip != null:
		world.add_child(skip)
		skip.global_position = anchor + Vector3(6.0, 0.0, 18.0)
		# Configure as a COARSE_FILM-only catcher (Stream.COARSE_FILM = 0).
		# MUST be a typed Array[int]: set() with an untyped Array silently
		# no-ops on the Array[int] export, leaving the bin an accept-everything
		# catch-all.
		var skip_streams : Array[int] = [0]
		skip.set("accepted_streams", skip_streams)
		skip.set("capacity_m3", 2.4)
		skip.set("safe_fill", 0.8)
		# Seed with some material so the operator can see the dump-empty cycle work.
		if skip.has_method("add"):
			skip.call("add", 80.0, 90.0, 0)
		print("[LegacyPropsSpawner] Steel skip (PLASTIC, COARSE_FILM) @ %s, fill=%.0f%%"
			% [str(skip.global_position), float(skip.call("fill_fraction")) * 100.0])

	# Dump zone — a flat orange-striped pad ~10 m further out. Tag with the
	# dump_zone group so BaseVehicle._drop_bale empties any skip released over it.
	var zone := Node3D.new()
	zone.name = "DumpZone_PLASTIC"
	zone.add_to_group("dump_zone")
	world.add_child(zone)
	zone.global_position = anchor + Vector3(20.0, 0.0, 18.0)
	var pad := MeshInstance3D.new()
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.88, 0.55, 0.10)
	pad_mat.roughness = 0.85
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(6.0, 0.04, 6.0)
	pad.mesh = pad_mesh
	pad.material_override = pad_mat
	pad.position = Vector3(0.0, 0.05, 0.0)
	zone.add_child(pad)
	# A label so the operator can see it from afar.
	var lbl := Label3D.new()
	lbl.text = "DUMP — PLASTIC"
	lbl.font_size = 64
	lbl.pixel_size = 0.012
	lbl.modulate = Color(0.10, 0.10, 0.10)
	lbl.position = Vector3(0.0, 0.2, 0.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone.add_child(lbl)
	print("[LegacyPropsSpawner] Dump zone (PLASTIC) @ %s" % str(zone.global_position))

# =============================================================================
# TEST WASTE ZONES — Wave 5: bay + cyclone bin + IBC + floor pile
# =============================================================================
## Spawn one of each remaining waste-buffer type beside the test skip so the
## complete Wave 5 model is visible on first launch:
##   • Fines bay     — 3 black bins on castors under a fake conveyor (FINES stream)
##   • Cyclone bin   — grey steel bin sat under a virtual cyclone chute (SLUDGE)
##   • IBC tote      — caged 1 m³ for process water (EFFLUENT) with valve drain
##   • Floor pile    — bounded zone for spillover when bins overflow + no skip nearby
## Each is pre-seeded so the operator can see fills, mounds, valves immediately.
static func _spawn_test_waste_zones(world: Node) -> void:
	var anchor : Vector3 = world.call("_get_factory_anchor")
	# anchor.y is the floor top now (was the capsule centre, hence the legacy −0.9).
	var floor_y := anchor.y

	# ── Fines bay: 3 fines_bin in a row, +Z further out from the skip ──────────
	for i in 3:
		var bin := PlaceableCatalog.build_node("fines_bin", false) as Node3D
		if bin == null:
			continue
		world.add_child(bin)
		bin.global_position = Vector3(anchor.x + 9.0 + float(i) * 1.1, floor_y, anchor.z + 22.0)
		var bin_streams : Array[int] = [1]   # Stream.FINES (typed — untyped no-ops on Array[int])
		bin.set("accepted_streams", bin_streams)
		bin.set("capacity_m3", 0.7)
		bin.set("safe_fill", 0.8)
		# Seed the LAST bin past its safe-fill so the mound visualisation is live.
		if i == 2 and bin.has_method("add"):
			bin.call("add", 180.0, 180.0, 1)   # 1 m³ of fines @180 kg/m³ → bin is full + spilling
	print("[LegacyPropsSpawner] Fines bay (3× FINES bins) seeded — last one over safe-fill")

	# ── Cyclone bin: grey steel cube under a virtual cyclone discharge (SLUDGE) ─
	var cb := PlaceableCatalog.build_node("cyclone_bin", false) as Node3D
	if cb != null:
		world.add_child(cb)
		cb.global_position = Vector3(anchor.x + 13.0, floor_y, anchor.z + 25.0)
		var cb_streams : Array[int] = [4]    # Stream.SLUDGE (typed — untyped no-ops on Array[int])
		cb.set("accepted_streams", cb_streams)
		cb.set("capacity_m3", 1.3)
		cb.set("safe_fill", 0.85)
		cb.set("mound_color", Color(0.32, 0.30, 0.26))
		# Pre-seed so a small visible mound appears on top of the bin.
		if cb.has_method("add"):
			cb.call("add", 1200.0, 800.0, 4)
		print("[LegacyPropsSpawner] Cyclone bin (SLUDGE) @ %s, fill=%.0f%%"
			% [str(cb.global_position), float(cb.call("fill_fraction")) * 100.0])

	# ── IBC tote: caged 1 m³ for process water (EFFLUENT) with on-foot valve ───
	var ibc := PlaceableCatalog.build_node("ibc_tote", false) as Node3D
	if ibc != null:
		world.add_child(ibc)
		ibc.global_position = Vector3(anchor.x + 17.0, floor_y, anchor.z + 25.0)
		var ibc_streams : Array[int] = [5]   # Stream.EFFLUENT (typed — untyped no-ops on Array[int])
		ibc.set("accepted_streams", ibc_streams)
		ibc.set("capacity_m3", 1.0)
		ibc.set("safe_fill", 0.9)
		ibc.set("movable", false)
		ibc.set("fluid_valve", true)        # operator opens on foot with E
		if ibc.has_method("add"):
			ibc.call("add", 720.0, 1000.0, 5)
		print("[LegacyPropsSpawner] IBC tote (EFFLUENT, valve-drain) @ %s, fill=%.0f%%"
			% [str(ibc.global_position), float(ibc.call("fill_fraction")) * 100.0])

	# ── Floor pile: a bounded zone for bin-overflow spillover. Sits beside the
	#    skip's dump zone so it's where excess material would actually end up. ──
	var pile_script := load("res://src/sim/FloorPile.gd")
	if pile_script != null:
		var pile = pile_script.new()
		pile.name = "FloorPile_PLASTIC"
		world.add_child(pile)
		pile.global_position = Vector3(anchor.x + 12.0, floor_y, anchor.z + 14.0)
		pile.max_radius_m = 3.0
		pile.pile_color = Color(0.48, 0.45, 0.38)
		# Seed a visible mound so the operator can see what it looks like.
		pile.add(220.0, 90.0)
		print("[LegacyPropsSpawner] Floor pile @ %s seeded — visible cone overflow"
			% str(pile.global_position))
