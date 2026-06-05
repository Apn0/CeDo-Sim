extends RefCounted
class_name PlaceableCatalog
## Data-driven catalog of everything the player can place in build mode.
##
## Each item is, for now, a parametric placeholder: a correctly-sized box with
## a billboard nameplate. When real EREMA / shredder / dryer models exist, swap
## the body of build_node() for a PackedScene lookup keyed by id — BuildMode and
## the save format keep working unchanged.
##
## Sizes are in metres (rough real-world footprints). Colour is per-category so
## the blockout is readable while you arrange the floor.

# Cached so the array (with Vector3 / Color literals) is built once, not on
# every query. Typed Array[Dictionary] so loop variables are typed Dictionaries
# (safe key access under this project's warnings-as-errors setting).
static var _items: Array[Dictionary] = []

static func items() -> Array[Dictionary]:
	if _items.is_empty():
		_items = [
			# ── Structure ────────────────────────────────────────────────────
			{"id": "door",           "name": "Door",               "category": "Structure",  "size": Vector3(1.2, 2.4, 0.18), "color": Color(0.55, 0.40, 0.25)},
			{"id": "pcu_cabinet",    "name": "Extruder PCU",       "category": "Structure",  "size": Vector3(0.9, 2.0, 0.6),  "color": Color(0.30, 0.32, 0.36)},
			{"id": "silo",           "name": "Silo",               "category": "Structure",  "size": Vector3(3.0, 6.0, 3.0),  "color": Color(0.62, 0.63, 0.66)},
		{"id": "doseersilo",     "name": "Doseer Silo",        "category": "Structure",  "size": Vector3(3.6, 2.6, 5.5),  "color": Color(0.66, 0.67, 0.70)},
			# ── Extruders ────────────────────────────────────────────────────
			{"id": "extruder_3a",    "name": "Extruder 3A",        "category": "Extruders",  "size": Vector3(2.2, 2.0, 5.5),  "color": Color(0.26, 0.42, 0.70)},
			{"id": "extruder_3b",    "name": "Extruder 3B",        "category": "Extruders",  "size": Vector3(2.2, 2.0, 5.5),  "color": Color(0.26, 0.50, 0.70)},
			{"id": "extruder_1",     "name": "Extruder 1",         "category": "Extruders",  "size": Vector3(2.2, 2.0, 5.5),  "color": Color(0.26, 0.58, 0.70)},
			{"id": "extruder_3c",    "name": "Extruder 3C",        "category": "Extruders",  "size": Vector3(2.2, 2.0, 5.5),  "color": Color(0.26, 0.64, 0.68)},
			{"id": "extruder_6",     "name": "Extruder 6",         "category": "Extruders",  "size": Vector3(2.2, 2.0, 5.5),  "color": Color(0.26, 0.70, 0.64)},
			# Extruder train (Line 3C tail): Plasmaq dewater press, laser melt
			# filter, melt pump → pellets.
			{"id": "plasmaq",        "name": "Plasmaq (dewater press)","category": "Extruders","size": Vector3(1.6, 2.0, 3.2), "color": Color(0.40, 0.46, 0.52)},
			{"id": "laser_filter",   "name": "Laserfilter",        "category": "Extruders",  "size": Vector3(1.4, 1.6, 2.0),  "color": Color(0.34, 0.38, 0.46)},
			{"id": "melt_pump",      "name": "Meltpump",           "category": "Extruders",  "size": Vector3(1.0, 1.2, 1.2),  "color": Color(0.42, 0.40, 0.44)},
			# ── Shredders ────────────────────────────────────────────────────
			{"id": "shredder_3a3b",  "name": "Shredder 3A/3B",     "category": "Shredders",  "size": Vector3(3.0, 2.5, 3.0),  "color": Color(0.66, 0.34, 0.30)},
			{"id": "shredder_1_3c6", "name": "Shredder 1 · 3C/6",  "category": "Shredders",  "size": Vector3(3.0, 2.5, 3.0),  "color": Color(0.72, 0.40, 0.30)},
			# Per-position shredders the line actually has — Shredder 1 is the
			# big coarse pre-shredder (≤10×10 cm output), Shredder 2 is a smaller
			# compact unit that takes it down to ~1-2 cm flakes.
			{"id": "shredder_1",     "name": "Shredder 1 (coarse)","category": "Shredders",  "size": Vector3(3.6, 3.2, 4.2),  "color": Color(0.42, 0.18, 0.15)},
			{"id": "shredder_2",     "name": "Shredder 2 (fine)",  "category": "Shredders",  "size": Vector3(2.4, 2.4, 2.8),  "color": Color(0.62, 0.30, 0.22)},
			# ── Washing / drying ─────────────────────────────────────────────
			{"id": "mech_dryer",     "name": "Mechanical dryer",   "category": "Washing",    "size": Vector3(2.5, 3.0, 2.5),  "color": Color(0.40, 0.55, 0.55)},
			{"id": "wash_line",      "name": "Washing line",       "category": "Washing",    "size": Vector3(2.0, 2.2, 8.0),  "color": Color(0.35, 0.55, 0.62)},
			{"id": "centrifuge",     "name": "Centrifuge",         "category": "Washing",    "size": Vector3(2.0, 2.4, 2.0),  "color": Color(0.45, 0.50, 0.58)},
			# ── Conveyance ───────────────────────────────────────────────────
			{"id": "transport_belt", "name": "Transport belt",     "category": "Conveyance", "size": Vector3(1.0, 0.9, 4.0),  "color": Color(0.34, 0.34, 0.38)},
			# Inclined belt — climbs 8 m vertically over 8 m horizontal (45°).
			# Goes from Shredder 2's output up to the feed hopper at the top.
			{"id": "inclined_belt_8m","name":"Inclined belt (45°, 8 m rise)","category":"Conveyance","size": Vector3(1.0, 8.5, 8.5),  "color": Color(0.34, 0.34, 0.38)},
			# Small feed hopper with 20 cm flanges — sits at the top of the
			# inclined belt and dribbles material onto the next horizontal belt.
			{"id": "feed_hopper",    "name": "Feed hopper (small)","category": "Conveyance", "size": Vector3(1.0, 1.2, 1.0),  "color": Color(0.50, 0.50, 0.55)},
			{"id": "cyclone",        "name": "Cyclone",            "category": "Conveyance", "size": Vector3(1.6, 3.0, 1.6),  "color": Color(0.58, 0.58, 0.62)},
			{"id": "blower",         "name": "Ventilator / blower","category": "Conveyance", "size": Vector3(1.0, 1.2, 1.2),  "color": Color(0.50, 0.46, 0.40)},
			# ── Sorting (bunkers / scanners / pre-wash drum etc) ─────────────
			# Bunker = the open-top steel pit material is dumped into, with
			# bunker rollers at the bottom that meter the load onto Shredder 1.
			{"id": "bunker",         "name": "Bunker (intake)",    "category": "Sorting",    "size": Vector3(4.2, 4.0, 3.4),  "color": Color(0.55, 0.55, 0.58)},
			# ── Size reduction ───────────────────────────────────────────────
			{"id": "mill",           "name": "Mill (granulator)",  "category": "Size reduction","size": Vector3(3.6, 4.8, 4.6), "color": Color(0.60, 0.36, 0.32)},
			# ── Separation ───────────────────────────────────────────────────
			{"id": "flotation_tank", "name": "Flotation tank",     "category": "Separation", "size": Vector3(3.0, 1.6, 9.0),  "color": Color(0.32, 0.46, 0.56)},
			{"id": "sink_float",     "name": "Bezinkafscheider",   "category": "Separation","size": Vector3(2.6, 2.0, 4.0),"color": Color(0.34, 0.46, 0.50)},
			{"id": "friction_sep",   "name": "Friction separator", "category": "Separation", "size": Vector3(1.8, 2.0, 4.5),  "color": Color(0.52, 0.54, 0.58)},
			{"id": "dewater_screw",  "name": "Dewatering screw",   "category": "Separation", "size": Vector3(1.2, 2.6, 4.5),  "color": Color(0.56, 0.58, 0.62)},
			{"id": "overband_magnet","name": "Overband magnet",    "category": "Separation", "size": Vector3(1.6, 1.8, 3.0),  "color": Color(0.30, 0.32, 0.38)},
			{"id": "scraper_conveyor","name":"Coarse scraper conveyor","category": "Separation","size": Vector3(1.4, 2.6, 6.0), "color": Color(0.46, 0.50, 0.54)},
			# ── Pumps ────────────────────────────────────────────────────────
			{"id": "water_pump",     "name": "Water pump",         "category": "Pumps",      "size": Vector3(0.8, 0.9, 1.3),  "color": Color(0.30, 0.45, 0.62)},
			{"id": "pump_large",     "name": "Process pump (large)","category": "Pumps",     "size": Vector3(1.2, 1.4, 2.0),  "color": Color(0.28, 0.40, 0.58)},
			# ── Line 3B wash train ───────────────────────────────────────────
			{"id": "vuilsnippersilo","name": "Wet film silo (vuilsnipper)","category": "Size reduction","size": Vector3(3.0, 4.0, 3.0),"color": Color(0.50, 0.50, 0.55)},
			{"id": "friction_washer","name": "Friction washer",    "category": "Washing",    "size": Vector3(1.8, 2.0, 4.0),  "color": Color(0.50, 0.55, 0.60)},
			{"id": "intensive_washer","name": "Intensive washer",  "category": "Washing",    "size": Vector3(1.6, 2.4, 2.0),  "color": Color(0.42, 0.55, 0.60)},
			{"id": "rotation_tank",  "name": "Rotation tank",      "category": "Separation", "size": Vector3(2.6, 2.2, 3.6),  "color": Color(0.34, 0.48, 0.56)},
			{"id": "rafter",         "name": "Rafter (sieve deck)","category": "Separation", "size": Vector3(1.8, 1.8, 3.6),  "color": Color(0.55, 0.57, 0.60)},
			{"id": "transport_screw","name": "Transport screw",    "category": "Conveyance", "size": Vector3(1.0, 2.4, 4.5),  "color": Color(0.55, 0.57, 0.61)},
			# ── Extrusion prep ───────────────────────────────────────────────
			{"id": "mas_bak",        "name": "MAS trough",         "category": "Extrusion prep","size": Vector3(2.2, 1.8, 3.0),"color": Color(0.50, 0.52, 0.50)},
			{"id": "compactor",      "name": "Compactor / PCU (preconditioning unit)",    "category": "Extrusion prep","size": Vector3(2.6, 2.6, 2.6),"color": Color(0.46, 0.46, 0.50)},
			# ── Sorting line (the dry front-end: bale opener → screens → NIR sort) ──
			# This is the section the SWIs call SORTEERLIJN. Bales are opened and
			# screened, ferrous tramp metal is magneted off, a ballistic deck splits
			# 2D film from 3D rigids, a windshifter blows out paper/dust, and the
			# TITECH/TOMRA NIR sorter positively sorts LDPE from off-spec polymer.
			{"id": "sga_drum",       "name": "SGA opener drum",    "category": "Sorting",    "size": Vector3(2.6, 2.8, 5.0),  "color": Color(0.50, 0.52, 0.56)},
			{"id": "metal_belt",     "name": "Overband metal sep.","category": "Sorting",    "size": Vector3(1.4, 1.8, 4.5),  "color": Color(0.40, 0.42, 0.48)},
			{"id": "ballistic_sep",  "name": "Ballistic separator","category": "Sorting",    "size": Vector3(2.4, 2.6, 5.5),  "color": Color(0.52, 0.50, 0.44)},
			{"id": "wind_sifter",    "name": "Windshifter (zigzag)","category": "Sorting",   "size": Vector3(1.8, 3.4, 2.0),  "color": Color(0.46, 0.52, 0.58)},
			{"id": "titech_sort",    "name": "TITECH NIR sorter",  "category": "Sorting",    "size": Vector3(2.2, 2.6, 4.5),  "color": Color(0.28, 0.40, 0.55)},
			# ── Wash line (wet section additions) ────────────────────────────
			{"id": "prewash_drum",   "name": "Pre-wash drum",      "category": "Washing",    "size": Vector3(2.4, 2.6, 4.5),  "color": Color(0.40, 0.54, 0.58)},
			{"id": "kufferath_sieve","name": "Kufferath sieve",    "category": "Separation", "size": Vector3(1.8, 2.0, 3.4),  "color": Color(0.56, 0.58, 0.60)},
			# ── Extrusion prep ───────────────────────────────────────────────
			{"id": "mengsilo",       "name": "Mixing silo (mengsilo)","category": "Extrusion prep","size": Vector3(3.0, 6.5, 3.0),"color": Color(0.60, 0.62, 0.66)},
			# ── Water / utilities (closes the wash-water loop) ────────────────
			{"id": "zss_water",      "name": "ZSS water plant",    "category": "Water",      "size": Vector3(4.0, 3.2, 6.0),  "color": Color(0.40, 0.50, 0.60)},
			# ── Logistics ────────────────────────────────────────────────────
			{"id": "waste_container","name": "Waste container (schraperbak)","category": "Logistics","size": Vector3(1.2, 1.2, 1.6),"color": Color(0.72, 0.56, 0.20)},
			{"id": "skip_steel",     "name": "Steel skip (PLASTIC, chute)",  "category": "Logistics","size": Vector3(1.6, 1.2, 1.4),  "color": Color(0.42, 0.46, 0.40)},
			{"id": "fines_bin",      "name": "Fines bin (under-conveyor)",   "category": "Logistics","size": Vector3(0.9, 1.1, 0.9),  "color": Color(0.18, 0.18, 0.20)},
			{"id": "cyclone_bin",    "name": "Cyclone underflow bin",        "category": "Logistics","size": Vector3(1.1, 1.1, 1.1),  "color": Color(0.50, 0.52, 0.54)},
			{"id": "ibc_tote",       "name": "IBC tote (1 m³, fluids)",      "category": "Logistics","size": Vector3(1.0, 1.2, 1.2),  "color": Color(0.86, 0.86, 0.84)},
			# ── Line 3C extruder back-end (#175) ─────────────────────────────
			# Extruder Silo → Compactorband → Compactor (PCU) → Laserfilter →
			# Meltpump → Kopfilter → Heetafslag (pellets form) → Ontwaterzeef →
			# Centrifuge → Weegschaal → Voorraad Silo. Compactor + centrifuge ids
			# already exist; these six are the new machines the back-end needs.
			{"id": "compactorband",  "name": "Compactorband (feed belt)",    "category": "Conveyance",   "size": Vector3(1.2, 1.4, 4.0),  "color": Color(0.34, 0.34, 0.38)},
			{"id": "extruder_screw", "name": "Extruder (3C screw)",          "category": "Extruders",    "size": Vector3(1.6, 2.0, 4.5),  "color": Color(0.30, 0.46, 0.62)},
			{"id": "vacuum_degas",   "name": "Vacuum degassing zone",        "category": "Extruders",    "size": Vector3(1.3, 2.4, 1.6),  "color": Color(0.34, 0.42, 0.50)},
			{"id": "kopfilter",      "name": "Diekop (die head)",            "category": "Extruders",    "size": Vector3(1.2, 1.5, 1.6),  "color": Color(0.36, 0.34, 0.40)},
			{"id": "heetafslag",     "name": "Heetafslag (hot-face cutter)", "category": "Extruders",    "size": Vector3(1.8, 2.0, 2.4),  "color": Color(0.44, 0.40, 0.40)},
			{"id": "ontwaterzeef",   "name": "Ontwaterzeef (dewater screen)","category": "Separation",   "size": Vector3(1.8, 1.8, 3.2),  "color": Color(0.50, 0.56, 0.60)},
			{"id": "weegschaal",     "name": "Weegschaal (25 kg batch weigh)","category": "Logistics",   "size": Vector3(1.2, 2.2, 1.2),  "color": Color(0.55, 0.57, 0.60)},
			{"id": "voorraad_silo",  "name": "Voorraad silo (granulate)",    "category": "Structure",    "size": Vector3(3.0, 6.5, 3.0),  "color": Color(0.66, 0.68, 0.72)},
			# ── Control (HMIs) ───────────────────────────────────────────────
			{"id": "hmi_panel",      "name": "HMI panel (stand)",  "category": "Control",    "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.30, 0.32, 0.36)},
			{"id": "hmi_wall",       "name": "HMI panel (wall)",   "category": "Control",    "size": Vector3(0.6, 0.5, 0.16), "color": Color(0.30, 0.32, 0.36)},
			# ── Hand tools (spawn from the menu instead of being pre-placed) ──
			{"id": "tool_shovel",    "name": "Shovel",             "category": "Tools",      "size": Vector3(0.30, 1.4, 0.30), "color": Color(0.55, 0.40, 0.25)},
			{"id": "tool_scissors",  "name": "Wire scissors",      "category": "Tools",      "size": Vector3(0.30, 0.9, 0.30), "color": Color(0.80, 0.30, 0.25)},
			{"id": "tool_scanner",   "name": "Barcode scanner",    "category": "Tools",      "size": Vector3(0.22, 0.3, 0.22), "color": Color(0.95, 0.78, 0.10)},
			{"id": "tool_lpg_rack",  "name": "LPG cylinder rack",  "category": "Tools",      "size": Vector3(1.2, 1.4, 0.6),   "color": Color(0.85, 0.55, 0.20)},
		]
		# ── Feedstock bales (data-driven from BaleDefs — single source of truth) ──
		for b in BaleDefs.origins():
			_items.append({
				"id":       String(b["id"]),
				"name":     "%s bale" % String(b["name"]),
				"category": "Bales",
				"size":     b["size"],
				"color":    b["tint"],
			})
			# A 5x5 footprint stacked to this origin's max-stack allowance (#33).
			_items.append({
				"id":       String(b["id"]) + "_stack5",
				"name":     "%s stack (5x5x%d)" % [String(b["name"]), int(b.get("stack", 2))],
				"category": "Bales",
				"size":     b["size"],
				"color":    b["tint"],
			})
	return _items

static func get_item(id: String) -> Dictionary:
	for it in items():
		if it["id"] == id:
			return it
	return {}

## Distinct categories in catalog order (for grouping the UI).
static func categories() -> Array[String]:
	var cats: Array[String] = []
	for it in items():
		var c := String(it["category"])
		if not cats.has(c):
			cats.append(c)
	return cats

## Build a placeable node.
##   ghost = false → solid StaticBody3D with collision + nameplate, in group
##                   "placed_object", tagged with meta "placeable_id" (saveable).
##   ghost = true  → translucent, no collision, not saved (the placement preview).
## The node origin sits at the object's BASE so it rests on the ground hit point.
##
## _bale_label_seq cycles the yellow-label face (front/back/left/right) across
## successively-built bales so the operator (and the NPC scanner behaviour, #150)
## has to actually look around the bale to find the barcode — matching the real
## yard where labels land on whichever face the baler spat them onto.
static var _bale_label_seq : int = 0
static func build_node(id: String, ghost: bool = false) -> Node3D:
	var item := get_item(id)
	if item.is_empty():
		push_warning("[PlaceableCatalog] Unknown id: %s" % id)
		return null

	# Hand tools — spawn the real tool node (or a translucent box for the ghost). #28
	if id.begins_with("tool_"):
		return _build_tool(id, Vector3(item["size"]), ghost)
	# Bale stack — a 5x5 footprint stacked to the origin's allowance. #33
	if id.ends_with("_stack5"):
		return _build_bale_stack(id.trim_suffix("_stack5"), ghost)

	var size: Vector3 = item["size"]
	var color: Color  = item["color"]
	var category := String(item["category"])

	# Bales are dynamic (stack physics: lift the bottom of a 3-stack with strong
	# clamp force and you take all three; misalignment shifts COM and they tip).
	# Control-category placeables (HMI panels) get an Hmi.gd script attached so
	# the player can interact with them — proximity prompt + UI overlay.
	# Everything else is a plain StaticBody3D (machines / surfaces don't move).
	var body : PhysicsBody3D
	if category == "Control":
		body = load("res://src/build/Hmi.gd").new()
	elif id == "waste_container" or id == "skip_steel" or id == "fines_bin" or id == "cyclone_bin" or id == "ibc_tote":
		# Real physical buffer entity — has capacity / density / overflow state,
		# accepts only its configured stream class(es), routes spillover to the
		# nearest floor pile. See src/sim/WasteContainer.gd for the model.
		body = load("res://src/sim/WasteContainer.gd").new()
	elif category == "Bales":
		var rb := RigidBody3D.new()
		# freeze=true at spawn so stacked bales sit still until something grabs
		# one — without this every placed bale would start falling at level boot.
		# Vehicle grab flips freeze=false (see BaseVehicle._set_bale_grabbed).
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.gravity_scale = 1.0
		rb.can_sleep = true
		rb.sleeping = true
		rb.contact_monitor = false
		rb.mass = maxf(BaleDefs.estimated_weight(size), 1.0)
		# Slow rotation a bit so a stacked bale settles before drifting
		rb.linear_damp  = 0.4
		rb.angular_damp = 1.2
		body = rb
	else:
		body = StaticBody3D.new()
	body.name = String(item["name"])
	body.set_meta("placeable_id", id)

	# Composite procedural model (base sits at the local origin), not a plain box.
	var model := Node3D.new()
	model.name = "Model"
	body.add_child(model)
	_build_model(model, id, category, size, color, ghost)

	if not ghost:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		# Bales have ~10% HORIZONTAL "give": the collision shape is shrunk on X/Z
		# by 10% (5% each side) so a forklift, bale-clamp or Merlo can press into
		# the compressed-film block slightly before colliding — gives the soft
		# feel of stacked LDPE film rather than a steel brick. Y stays full so
		# stacks settle on each other and the player can walk on top without
		# sinking into the bale.
		if category == "Bales":
			shape.size = Vector3(size.x * 0.9, size.y, size.z * 0.9)
		else:
			shape.size = size
		col.shape = shape
		col.position = Vector3(0.0, size.y * 0.5, 0.0)
		body.add_child(col)
		body.add_to_group("placed_object")
		# Bales also carry a physics material with high friction so stacked bales
		# grip each other (so the clamp picks up multiple at once when held firmly)
		# and a touch of bounce so they settle softly when dropped.
		if category == "Bales":
			var pm := PhysicsMaterial.new()
			pm.friction = 0.85   # high — bale-on-bale friction is what holds stacks
			pm.bounce   = 0.05   # tiny — compressed film barely bounces
			body.physics_material_override = pm
			# Wire + sheet state used by the clamp-force / wire-cutter feature.
			# (see _m_bale for the visuals; BaleClamp.gd flips wires_cut.)
			body.set_meta("wires_cut",          false)
			body.set_meta("wire_compliance",    0.55)   # clamp_force above this bulges the wire
			# Scan gate (#152): bales start UNSCANNED. The barcode scanner flips
			# this true; only scanned bales are allowed onto the feed belt.
			body.set_meta("scanned",            false)
			body.set_meta("sheet_count",        _sheet_count_for(size))
			body.set_meta("clamp_force_needed", 0.30)   # min clamp_force to hold ONE bale on its own

		var label := Label3D.new()
		label.text = String(item["name"])
		if category == "Bales":
			# Tag the bale with its feedstock origin + show the (estimated) weight.
			body.set_meta("material_origin", id)
			body.add_to_group("bale")
			label.text = "%s\n~%d kg" % [String(item["name"]), int(round(BaleDefs.estimated_weight(size)))]
		label.position = Vector3(0.0, size.y + 0.45, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = false
		label.font_size = 48
		label.outline_size = 8
		label.modulate = Color.WHITE
		body.add_child(label)

		# ── YELLOW SHIPPING LABEL (bales) ─────────────────────────────────────
		# Real bales carry a YELLOW sticker with the barcode. (Earlier builds
		# added a redundant WHITE card in the centre of the front face — removed
		# per operator feedback; the yellow label IS the scan target now.) The
		# label lands on one of the four side faces, cycling per bale so it isn't
		# always in the same place — you have to walk around to find it. The
		# scanner reads the `label_info` meta off this "Label" child.
		if category == "Bales" and not ghost:
			var info := {
				"item":       String(item["name"]),
				"origin":     id,
				"weight_kg":  int(round(BaleDefs.estimated_weight(size))),
				"batch":      "B-%04d" % (hash(id + str(size)) & 0xFFFF),
				"dimensions": "%.2f x %.2f x %.2f m" % [size.x, size.y, size.z],
			}
			var eps := 0.012
			var ly := size.y * 0.55
			var face := _bale_label_seq % 4
			_bale_label_seq += 1
			var label_pos : Vector3
			var label_basis : Basis
			match face:
				0:   # front (+Z)
					label_pos   = Vector3(0.0, ly, size.z * 0.5 + eps)
					label_basis = Basis()
				1:   # back (-Z)
					label_pos   = Vector3(0.0, ly, -size.z * 0.5 - eps)
					label_basis = Basis(Vector3.UP, PI)
				2:   # right (+X)
					label_pos   = Vector3(size.x * 0.5 + eps, ly, 0.0)
					label_basis = Basis(Vector3.UP, -PI * 0.5)
				_:   # left (-X)
					label_pos   = Vector3(-size.x * 0.5 - eps, ly, 0.0)
					label_basis = Basis(Vector3.UP, PI * 0.5)
			# preload() rather than class_name — Godot's global class registry
			# isn't populated under --headless --script runs, but preload binds
			# at compile time regardless. card_color defaults to yellow.
			var label_item_script := preload("res://src/scenes/world/LabelItem.gd")
			label_item_script.attach_to(body, info, label_pos, label_basis)

	return body

# =============================================================================
# DETAILED MACHINE MODELS  (composite primitives, base at the local origin)
# =============================================================================
const _STEEL : Color = Color(0.60, 0.63, 0.67)
const _DARK  : Color = Color(0.24, 0.25, 0.28)
const _SAFETY: Color = Color(0.86, 0.70, 0.16)

static func _build_model(p: Node3D, id: String, category: String, size: Vector3, color: Color, ghost: bool) -> void:
	match id:
		"silo":           _m_silo(p, size, color, ghost)
		"doseersilo":     _m_doseersilo(p, size, color, ghost)
		"transport_belt": _m_belt(p, size, color, ghost)
		"cyclone":        _m_cyclone(p, size, color, ghost)
		"blower":         _m_blower(p, size, color, ghost)
		"centrifuge":     _m_centrifuge(p, size, color, ghost)
		"wash_line":      _m_washline(p, size, color, ghost)
		"mech_dryer":     _m_dryer(p, size, color, ghost)
		"pcu_cabinet":    _m_cabinet(p, size, color, ghost)
		"door":           _m_door(p, size, color, ghost)
		"mill":           _m_mill(p, size, color, ghost)
		"flotation_tank": _m_flotation(p, size, color, ghost)
		"sink_float":     _m_sinkfloat(p, size, color, ghost)
		"friction_sep":   _m_friction(p, size, color, ghost)
		"dewater_screw":  _m_dewater(p, size, color, ghost)
		"water_pump":     _m_pump(p, size, color, ghost)
		"pump_large":     _m_pump(p, size, color, ghost)
		"hmi_panel":      _m_hmi(p, size, color, ghost)
		"hmi_wall":       _m_hmi_wall(p, size, color, ghost)
		"vuilsnippersilo":_m_vuilsnippersilo(p, size, color, ghost)
		"friction_washer":_m_friction_washer(p, size, color, ghost)
		"intensive_washer":_m_intensive_washer(p, size, color, ghost)
		"rotation_tank":  _m_rotation_tank(p, size, color, ghost)
		"rafter":         _m_rafter(p, size, color, ghost)
		"transport_screw":_m_transport_screw(p, size, color, ghost)
		"mas_bak":        _m_mas_bak(p, size, color, ghost)
		"compactor":      _m_compactor(p, size, color, ghost)
		"waste_container":_m_waste_container(p, size, color, ghost)
		"skip_steel":     _m_steel_skip(p, size, color, ghost)
		"fines_bin":      _m_fines_bin(p, size, color, ghost)
		"cyclone_bin":    _m_cyclone_bin(p, size, color, ghost)
		"ibc_tote":       _m_ibc_tote(p, size, color, ghost)
		"bunker":         _m_bunker(p, size, color, ghost)
		"shredder_1":     _m_shredder_1(p, size, color, ghost)
		"shredder_2":     _m_shredder_2(p, size, color, ghost)
		"inclined_belt_8m":_m_inclined_belt(p, size, color, ghost)
		"feed_hopper":    _m_feed_hopper(p, size, color, ghost)
		"sga_drum":       _m_sga_drum(p, size, color, ghost)
		"metal_belt":     _m_metal_belt(p, size, color, ghost)
		"ballistic_sep":  _m_ballistic(p, size, color, ghost)
		"wind_sifter":    _m_windsifter(p, size, color, ghost)
		"titech_sort":    _m_optical_sorter(p, size, color, ghost)
		"prewash_drum":   _m_prewash_drum(p, size, color, ghost)
		"kufferath_sieve":_m_kufferath(p, size, color, ghost)
		"mengsilo":       _m_mengsilo(p, size, color, ghost)
		"zss_water":      _m_zss(p, size, color, ghost)
		"plasmaq":        _m_plasmaq(p, size, color, ghost)
		"laser_filter":   _m_laser_filter(p, size, color, ghost)
		"melt_pump":      _m_melt_pump(p, size, color, ghost)
		"overband_magnet":_m_overband_magnet(p, size, color, ghost)
		"scraper_conveyor":_m_scraper_conveyor(p, size, color, ghost)
		# ── Line 3C extruder back-end (#175) ──────────────────────────────────
		"compactorband":  _m_compactorband(p, size, color, ghost)
		"extruder_screw": _m_extruder_screw(p, size, color, ghost)
		"vacuum_degas":   _m_vacuum_degas(p, size, color, ghost)
		"kopfilter":      _m_kopfilter(p, size, color, ghost)
		"heetafslag":     _m_heetafslag(p, size, color, ghost)
		"ontwaterzeef":   _m_ontwaterzeef(p, size, color, ghost)
		"weegschaal":     _m_weegschaal(p, size, color, ghost)
		"voorraad_silo":  _m_silo(p, size, color, ghost)
		_:
			match category:
				"Extruders": _m_extruder(p, size, color, ghost)
				"Shredders": _m_shredder(p, size, color, ghost)
				"Bales":     _m_bale(p, id, size, ghost)
				_:           _box(p, size, Vector3(0.0, size.y * 0.5, 0.0), _mat(color, ghost))

# ── primitive helpers ───────────────────────────────────────────────────────
static func _mat(c: Color, ghost: bool, metallic: float = 0.15, rough: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.metallic = metallic
	m.roughness = rough
	if ghost:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(c.r, c.g, c.b, 0.40)
	else:
		m.albedo_color = c
		if c.a < 0.999:   # already-translucent colours (e.g. tank water) stay see-through
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

## axis: "y" (default upright), "z" (lengthwise), or "x" (crosswise).
static func _cyl(parent: Node3D, r_top: float, r_bot: float, height: float, \
		pos: Vector3, mat: StandardMaterial3D, axis: String = "y") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = height
	cm.radial_segments = 24
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	if axis == "z":
		mi.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	elif axis == "x":
		mi.rotation = Vector3(0.0, 0.0, PI / 2.0)
	parent.add_child(mi)
	return mi

static func _legs(parent: Node3D, size: Vector3, top_y: float, mat: StandardMaterial3D) -> void:
	var hx := size.x * 0.42
	var hz := size.z * 0.42
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			_box(parent, Vector3(0.08, top_y, 0.08), Vector3(sx * hx, top_y * 0.5, sz * hz), mat)

## A TEFC electric motor: finned body cylinder + terminal box on top. axis as _cyl.
static func _motor_unit(parent: Node3D, r: float, length: float, pos: Vector3, axis: String, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.55, 0.5)
	var blk := _mat(Color(0.12, 0.12, 0.13), ghost, 0.3, 0.6)
	_cyl(parent, r, r, length, pos, dark, axis)
	# terminal/junction box sits on top regardless of motor axis
	_box(parent, Vector3(r * 0.8, r * 0.5, length * 0.45), pos + Vector3(0.0, r * 0.95, 0.0), blk)

## Safety-yellow V-belt / coupling guard (a flattened box).
static func _guard(parent: Node3D, size: Vector3, pos: Vector3, ghost: bool) -> void:
	_box(parent, size, pos, _mat(_SAFETY, ghost, 0.2, 0.6))

## A cylinder with an arbitrary tilt about X (for inclined screws/housings).
static func _tube(parent: Node3D, r: float, length: float, pos: Vector3, mat: StandardMaterial3D, x_rot: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = Vector3(x_rot, 0.0, 0.0)
	parent.add_child(mi)
	return mi

## A flat torus ring (lies in XZ, hole along Y) — used for ladder safety-cage hoops.
static func _torus(parent: Node3D, inner_r: float, outer_r: float, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = outer_r
	tm.rings = 6
	tm.ring_segments = 18
	mi.mesh = tm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

## Yellow guard railing around a rectangular deck centred on (0, base_y, 0):
## top rail + mid rail + toe board + posts. `skip` leaves sides open (for the
## ladder / stair landing) — values among "+x","-x","+z","-z".
static func _railing(parent: Node3D, halfx: float, halfz: float, base_y: float, mat: StandardMaterial3D, skip: Array = []) -> void:
	var H := 1.05
	var T := 0.04
	var top_y := base_y + H
	var mid_y := base_y + H * 0.5
	var toe_y := base_y + 0.08
	for key in ["+z", "-z", "+x", "-x"]:
		if key in skip:
			continue
		if key == "+z" or key == "-z":
			var fz : float = (halfz if key == "+z" else -halfz)
			_box(parent, Vector3(halfx * 2.0, T, T), Vector3(0, top_y, fz), mat)
			_box(parent, Vector3(halfx * 2.0, T, T), Vector3(0, mid_y, fz), mat)
			_box(parent, Vector3(halfx * 2.0, 0.10, 0.02), Vector3(0, toe_y, fz), mat)
			for px in [-halfx, 0.0, halfx]:
				_box(parent, Vector3(T, H, T), Vector3(px, base_y + H * 0.5, fz), mat)
		else:
			var fx : float = (halfx if key == "+x" else -halfx)
			_box(parent, Vector3(T, T, halfz * 2.0), Vector3(fx, top_y, 0), mat)
			_box(parent, Vector3(T, T, halfz * 2.0), Vector3(fx, mid_y, 0), mat)
			_box(parent, Vector3(0.02, 0.10, halfz * 2.0), Vector3(fx, toe_y, 0), mat)
			for pz in [-halfz, 0.0, halfz]:
				_box(parent, Vector3(T, H, T), Vector3(fx, base_y + H * 0.5, pz), mat)

## A vertical caged access ladder rising `height` from its foot `base`. Two rails
## + rungs + a safety cage (horizontal hoops + vertical bars) on the climb-out (+Z) side.
static func _caged_ladder(parent: Node3D, base: Vector3, height: float, mat: StandardMaterial3D) -> void:
	var W := 0.46
	_box(parent, Vector3(0.05, height, 0.05), base + Vector3(-W * 0.5, height * 0.5, 0.0), mat)
	_box(parent, Vector3(0.05, height, 0.05), base + Vector3( W * 0.5, height * 0.5, 0.0), mat)
	var rungs := int(height / 0.3)
	for i in range(1, rungs):
		_box(parent, Vector3(W, 0.03, 0.03), base + Vector3(0.0, float(i) * 0.3, 0.0), mat)
	var hoop_y := 2.2
	while hoop_y < height - 0.1:
		_torus(parent, 0.36, 0.44, base + Vector3(0.0, hoop_y, 0.30), mat)
		hoop_y += 0.5
	var cage_h : float = maxf(height - 2.2, 0.2)
	for bz in [Vector3(0.0, 0.0, 0.72), Vector3(-0.42, 0.0, 0.30), Vector3(0.42, 0.0, 0.30)]:
		_box(parent, Vector3(0.03, cage_h, 0.03), base + bz + Vector3(0.0, 2.2 + cage_h * 0.5, 0.0), mat)

## A straight ground stair climbing `rise` in +Z from its foot `base`, `width`
## wide. Grating treads + side posts + sloped handrails.
static func _stair(parent: Node3D, base: Vector3, rise: float, width: float, tread_mat: StandardMaterial3D, rail_mat: StandardMaterial3D) -> void:
	var steps := maxi(int(rise / 0.22), 4)
	var step_h := rise / float(steps)
	var tread := 0.27
	for i in range(steps):
		_box(parent, Vector3(width, 0.04, tread), base + Vector3(0.0, float(i + 1) * step_h, float(i) * tread + tread * 0.5), tread_mat)
	var run := float(steps) * tread
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.05, 1.0, 0.05), base + Vector3(sx * width * 0.5, 0.5, 0.2), rail_mat)
		_box(parent, Vector3(0.05, 1.0, 0.05), base + Vector3(sx * width * 0.5, rise + 1.0, run - 0.2), rail_mat)
		var rail := _box(parent, Vector3(0.04, 0.04, sqrt(run * run + rise * rise)), base + Vector3(sx * width * 0.5, rise * 0.5 + 1.0, run * 0.5), rail_mat)
		rail.rotation.x = -atan2(rise, run)

## A faceted half-cylinder TROUGH (bottom half of a horizontal cylinder, open top)
## with its axis at `axis_pos` running along Z, length `length`. Built from flat
## tangent panels around the lower semicircle.
static func _half_pipe(parent: Node3D, radius: float, length: float, axis_pos: Vector3, mat: StandardMaterial3D, segs: int = 9) -> void:
	var seg_arc := PI / float(segs)
	var panel_w : float = 2.0 * radius * sin(seg_arc * 0.5) * 1.06
	for i in range(segs):
		var amid := PI + seg_arc * (float(i) + 0.5)     # lower semicircle: π → 2π
		var px := cos(amid) * radius
		var py := sin(amid) * radius
		var panel := _box(parent, Vector3(panel_w, 0.05, length), axis_pos + Vector3(px, py, 0.0), mat)
		panel.rotation.z = amid + PI * 0.5              # tangent to the circle

## A screw conveyor / auger running along Z: a shaft + tilted flight discs that
## read as helical flighting. Centred on `pos`.
static func _auger(parent: Node3D, length: float, pos: Vector3, shaft_r: float, flight_r: float, shaft_mat: StandardMaterial3D, flight_mat: StandardMaterial3D) -> void:
	_cyl(parent, shaft_r, shaft_r, length, pos, shaft_mat, "z")
	var n := maxi(int(length / 0.35), 3)
	for i in range(n):
		var zz := -length * 0.5 + (float(i) + 0.5) * (length / float(n))
		var d := _cyl(parent, flight_r, flight_r, 0.025, pos + Vector3(0.0, 0.0, zz), flight_mat, "z")
		# tilt + advancing roll fakes the helix pitch
		d.rotation = Vector3(deg_to_rad(16.0), 0.0, deg_to_rad(float(i) * 55.0))

# ── Overband magnet (#155): a belt running ABOVE the conveyor on a frame, with
#    two drums (spinning) and a side chute it flings the pulled ferrous into ────
static func _m_overband_magnet(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var magnet_mat := _mat(Color(0.15, 0.15, 0.18), ghost, 0.3, 0.6)
	var hz := size.z * 0.5
	# Four uprights holding the belt above where the conveyor below would run.
	for sx in [-0.45, 0.45]:
		for sz in [-0.4, 0.4]:
			_box(p, Vector3(0.08, size.y * 0.82, 0.08),
				Vector3(sx * size.x, size.y * 0.41, sz * size.z), dark)
	# Overband belt housing (the magnet box) up high, spanning Z.
	_box(p, Vector3(size.x * 0.6, size.y * 0.18, size.z * 0.85),
		Vector3(0.0, size.y * 0.82, 0.0), magnet_mat)
	# Two belt drums at each end — spinning (axis X).
	if not ghost:
		var rm_script := preload("res://src/sim/RotatingMechanism.gd")
		for zz in [-hz * 0.8, hz * 0.8]:
			var rm = rm_script.new()
			rm.axis = Vector3.RIGHT; rm.rpm = 40.0; rm.nominal_rpm = 40.0; rm.capacity_kg_s = 1.0
			rm.position = Vector3(0.0, size.y * 0.82, zz)
			p.add_child(rm)
			_cyl(rm, size.y * 0.09, size.y * 0.09, size.x * 0.6, Vector3.ZERO, steel, "x")
		# A few captured ferrous specks stuck to the belt underside.
		for i in range(5):
			_box(p, Vector3(0.06, 0.06, 0.06),
				Vector3(float(i - 2) * 0.12, size.y * 0.72, (float(i % 2) * 0.4 - 0.2)), steel)
	# Side discharge chute where the ferrous is flung off (+X).
	_box(p, Vector3(0.5, size.y * 0.2, size.z * 0.4),
		Vector3(size.x * 0.55, size.y * 0.55, hz * 0.7), dark)

# ── Coarse scraper conveyor (#156): submerged horizontal drag along a tank
#    bottom, climbing a ~50° incline, discharging off the top into a chute ──────
static func _m_scraper_conveyor(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var water := _mat(Color(0.20, 0.40, 0.34, 0.6), ghost, 0.0, 0.2)
	var hz := size.z * 0.5
	_legs(p, size, size.y * 0.2, dark)
	# Submerged horizontal trough (the underwater drag run, -Z half).
	_box(p, Vector3(size.x * 0.9, size.y * 0.3, size.z * 0.6), Vector3(0.0, size.y * 0.2, -hz * 0.4), steel)
	_box(p, Vector3(size.x * 0.72, 0.04, size.z * 0.55), Vector3(0.0, size.y * 0.34, -hz * 0.4), water)
	# Inclined section climbing ~50° toward +Z.
	var inc := Node3D.new()
	inc.position = Vector3(0.0, size.y * 0.2, -hz * 0.1)
	inc.rotation.x = -deg_to_rad(50.0)
	p.add_child(inc)
	_box(inc, Vector3(size.x * 0.7, size.y * 0.25, size.z * 0.7), Vector3(0.0, 0.0, size.z * 0.35), steel)
	# Discharge chute at the top.
	_box(p, Vector3(size.x * 0.5, size.y * 0.2, 0.5), Vector3(0.0, size.y * 0.92, hz * 0.9), dark)
	# Two scraper sprockets (spinning, axis X) with flight bars so the drag is visible.
	if not ghost:
		var rm_script := preload("res://src/sim/RotatingMechanism.gd")
		for zz in [-hz * 0.7, hz * 0.05]:
			var rm = rm_script.new()
			rm.axis = Vector3.RIGHT; rm.rpm = 12.0; rm.nominal_rpm = 12.0; rm.capacity_kg_s = 3.0
			rm.position = Vector3(0.0, size.y * 0.25, zz)
			p.add_child(rm)
			_cyl(rm, size.x * 0.12, size.x * 0.12, size.x * 0.75, Vector3.ZERO, dark, "x")
			for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				_box(rm, Vector3(size.x * 0.78, 0.05, 0.08),
					Vector3(0.0, sin(a) * size.x * 0.12, cos(a) * size.x * 0.12), steel)

# ── Plasmaq: dewater PRESS — housing + a big horizontal squeeze screw that
#    forces water out of the wet flake (the operator's "big screw" press) ──────
static func _m_plasmaq(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.3, 0.5)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	_legs(p, size, size.y * 0.5, dark)
	_box(p, Vector3(size.x * 0.9, size.y * 0.6, size.z * 0.9), Vector3(0, size.y * 0.6, 0), body)
	# Big tapered squeeze screw along Z.
	_cyl(p, size.x * 0.22, size.x * 0.30, size.z * 0.95, Vector3(0, size.y * 0.6, 0), steel, "z")
	_motor_unit(p, size.x * 0.18, size.z * 0.22, Vector3(0, size.y * 0.6, size.z * 0.5), "z", ghost)
	# Water sump catching the pressed-out effluent.
	_box(p, Vector3(size.x * 0.72, 0.18, size.z * 0.55), Vector3(0, size.y * 0.16, 0), dark)

# ── Laserfilter: melt-filter housing + two breaker/filter discs + melt pipe ───
static func _m_laser_filter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# The Laserfilter is the big ROTARY DISC melt filter — the prominent concentric
	# circle on the 3C HMI (259 bar in, ~81% loaded). A large disc faces sideways
	# (axis = X) so the concentric rings read in side elevation; melt flows through
	# along Z, the disc rotates to self-clean. (This is the big circle — NOT the PCU.)
	var body := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	_legs(p, size, size.y * 0.45, dark)
	var cy : float = size.y * 0.6
	var disc_r : float = size.y * 0.46
	# Concentric disc faces toward ±X (the big circle), built from nested rings.
	_cyl(p, disc_r,        disc_r,        size.x * 0.50, Vector3(0.0, cy, 0.0), body,  "x")   # outer housing
	_cyl(p, disc_r * 0.72, disc_r * 0.72, size.x * 0.58, Vector3(0.0, cy, 0.0), steel, "x")   # filter ring (proud)
	_cyl(p, disc_r * 0.40, disc_r * 0.40, size.x * 0.62, Vector3(0.0, cy, 0.0), body,  "x")   # inner disc
	_cyl(p, disc_r * 0.10, disc_r * 0.10, size.x * 0.66, Vector3(0.0, cy, 0.0), dark,  "x")   # centre hub
	# Melt pipe in from the extruder (-Z) and out to the meltpump (+Z).
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.5, Vector3(0.0, cy, -size.z * 0.45), dark, "z")
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.5, Vector3(0.0, cy,  size.z * 0.45), dark, "z")
	# Disc self-clean drive motor off the +X face.
	_motor_unit(p, size.x * 0.13, size.y * 0.28, Vector3(size.x * 0.52, cy, 0.0), "x", ghost)

# ── Meltpump: gear-pump block + twin gear shafts + inlet/outlet melt pipes ────
static func _m_melt_pump(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.4, 0.5)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	_legs(p, size, size.y * 0.5, _mat(_DARK, ghost, 0.5, 0.6))
	_box(p, Vector3(size.x * 0.85, size.y * 0.6, size.z * 0.85), Vector3(0, size.y * 0.6, 0), body)
	for sx in [-0.18, 0.18]:
		_cyl(p, size.x * 0.16, size.x * 0.16, size.z * 0.5, Vector3(sx * size.x, size.y * 0.85, 0), steel, "z")
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.3, Vector3(0, size.y * 0.6, size.z * 0.5), steel, "z")
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.3, Vector3(0, size.y * 0.35, -size.z * 0.5), steel, "z")

# ── extruder: base + gearbox + horizontal barrel + heater bands + hopper + die ─
static func _m_extruder(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var body_mat := _mat(color, ghost, 0.25, 0.55)
	var hz := size.z * 0.5
	_box(p, Vector3(size.x * 0.85, 0.35, size.z * 0.96), Vector3(0.0, 0.18, 0.0), dark)
	# gearbox / drive housing toward the feed (+Z) end
	_box(p, Vector3(size.x * 0.78, size.y * 0.7, size.z * 0.3), Vector3(0.0, size.y * 0.45, hz * 0.62), body_mat)
	# motor stub off the feed end
	_cyl(p, size.x * 0.2, size.x * 0.2, size.z * 0.16, Vector3(0.0, size.y * 0.5, hz * 0.92), steel, "z")
	# barrel running toward the die (-Z)
	var barrel_len := size.z * 0.62
	_cyl(p, size.x * 0.16, size.x * 0.16, barrel_len, Vector3(0.0, size.y * 0.6, -hz * 0.08), steel, "z")
	# heater bands along the barrel
	for i in 5:
		var zz := hz * 0.18 - float(i) * (barrel_len * 0.16)
		_cyl(p, size.x * 0.2, size.x * 0.2, 0.1, Vector3(0.0, size.y * 0.6, zz), dark, "z")
	# feed hopper (funnel, wide at top) above the gearbox
	_cyl(p, size.x * 0.3, 0.06, size.y * 0.45, Vector3(0.0, size.y * 0.9, hz * 0.5), steel)
	# die head at the -Z tip
	_box(p, Vector3(size.x * 0.42, size.x * 0.42, size.z * 0.1), Vector3(0.0, size.y * 0.6, -hz * 0.94), dark)

# ── shredder: frame + cutting chamber + big feed hopper + side motor ──────────
static func _m_shredder(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var body_mat := _mat(color, ghost, 0.25, 0.55)
	_box(p, Vector3(size.x * 0.92, 0.3, size.z * 0.92), Vector3(0.0, 0.15, 0.0), dark)
	_box(p, Vector3(size.x * 0.75, size.y * 0.45, size.z * 0.75), Vector3(0.0, size.y * 0.4, 0.0), body_mat)
	# feed hopper funnel on top (wide mouth)
	_cyl(p, size.x * 0.5, size.x * 0.2, size.y * 0.45, Vector3(0.0, size.y * 0.78, 0.0), steel)
	# drive: motor + V-belt guard on the -X side
	_motor_unit(p, size.y * 0.18, size.z * 0.42, Vector3(-size.x * 0.46, size.y * 0.4, 0.0), "x", ghost)
	_guard(p, Vector3(size.x * 0.18, size.y * 0.42, size.z * 0.26), Vector3(-size.x * 0.3, size.y * 0.42, size.z * 0.18), ghost)

# ── silo: legs + conical hopper bottom + tall cylinder + domed top ────────────
static func _m_silo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var r := size.x * 0.46
	var leg_h := size.y * 0.16
	# support legs
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			_box(p, Vector3(0.12, leg_h, 0.12), Vector3(sx * r * 0.7, leg_h * 0.5, sz * r * 0.7), dark)
	# conical hopper bottom (narrow at the bottom)
	_cyl(p, r, 0.15, size.y * 0.22, Vector3(0.0, leg_h + size.y * 0.11, 0.0), shell)
	# main body
	_cyl(p, r, r, size.y * 0.5, Vector3(0.0, leg_h + size.y * 0.22 + size.y * 0.25, 0.0), shell)
	# domed/short top
	_cyl(p, r * 0.25, r, size.y * 0.1, Vector3(0.0, leg_h + size.y * 0.72 + size.y * 0.05, 0.0), shell)

# ── mechanical dryer: tank cylinder + top duct + base ─────────────────────────
static func _m_dryer(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.3, 0.5)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	_box(p, Vector3(size.x * 0.8, 0.25, size.z * 0.8), Vector3(0.0, 0.12, 0.0), dark)
	_cyl(p, size.x * 0.42, size.x * 0.42, size.y * 0.78, Vector3(0.0, size.y * 0.5, 0.0), body_mat)
	# top air duct out the +Z side
	_cyl(p, size.x * 0.16, size.x * 0.16, size.z * 0.5, Vector3(0.0, size.y * 0.85, size.z * 0.3), steel, "z")

# ── washing line: long trough + access housings + legs + drive motor ──────────
static func _m_washline(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.25, 0.5)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var hz := size.z * 0.5
	_legs(p, size, size.y * 0.45, dark)
	# main trough
	_box(p, Vector3(size.x * 0.7, size.y * 0.4, size.z * 0.96), Vector3(0.0, size.y * 0.62, 0.0), body_mat)
	# access / paddle housings along the length
	for i in 4:
		var zz := -hz * 0.7 + float(i) * (size.z * 0.45)
		_box(p, Vector3(size.x * 0.55, size.y * 0.22, size.z * 0.12), Vector3(0.0, size.y * 0.92, zz), steel)
	# drive: motor + guard at the +Z end
	_motor_unit(p, size.y * 0.16, size.x * 0.3, Vector3(size.x * 0.18, size.y * 0.55, hz * 0.96), "x", ghost)
	_guard(p, Vector3(size.x * 0.26, size.y * 0.3, size.z * 0.1), Vector3(-size.x * 0.12, size.y * 0.6, hz * 0.9), ghost)

# ── centrifuge: frame + big horizontal drum + motor + outlet ──────────────────
static func _m_centrifuge(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	_box(p, Vector3(size.x * 0.9, 0.3, size.z * 0.9), Vector3(0.0, 0.15, 0.0), dark)
	# screen drum (lengthwise along X)
	_cyl(p, size.y * 0.38, size.y * 0.38, size.x * 0.78, Vector3(0.0, size.y * 0.6, 0.0), body_mat, "x")
	# end caps
	_cyl(p, size.y * 0.42, size.y * 0.42, size.x * 0.08, Vector3(size.x * 0.4, size.y * 0.6, 0.0), dark, "x")
	# drive: motor + V-belt guard at -Z
	_motor_unit(p, size.y * 0.2, size.z * 0.3, Vector3(0.0, size.y * 0.45, -size.z * 0.45), "z", ghost)
	_guard(p, Vector3(size.x * 0.3, size.y * 0.35, size.z * 0.16), Vector3(0.0, size.y * 0.52, -size.z * 0.26), ghost)

# ── transport belt: end rollers + belt surface + side rails + legs ────────────
static func _m_belt(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var hz := size.z * 0.45
	var deck_y := size.y * 0.75
	_legs(p, size, deck_y, steel)
	# end rollers (crosswise along X)
	_cyl(p, size.y * 0.22, size.y * 0.22, size.x * 0.9, Vector3(0.0, deck_y, hz), dark, "x")
	_cyl(p, size.y * 0.22, size.y * 0.22, size.x * 0.9, Vector3(0.0, deck_y, -hz), dark, "x")
	# belt deck
	_box(p, Vector3(size.x * 0.82, 0.05, size.z * 0.9), Vector3(0.0, deck_y + size.y * 0.22, 0.0), dark)
	# side rails
	_box(p, Vector3(0.06, size.y * 0.18, size.z * 0.95), Vector3(size.x * 0.44, deck_y + size.y * 0.28, 0.0), steel)
	_box(p, Vector3(0.06, size.y * 0.18, size.z * 0.95), Vector3(-size.x * 0.44, deck_y + size.y * 0.28, 0.0), steel)

# ── cyclone: cylinder body + downward cone + top outlet + tangential inlet ─────
static func _m_cyclone(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var r := size.x * 0.42
	# cone (narrow at the bottom)
	_cyl(p, r, 0.08, size.y * 0.45, Vector3(0.0, size.y * 0.3, 0.0), shell)
	# upper cylinder body
	_cyl(p, r, r, size.y * 0.4, Vector3(0.0, size.y * 0.72, 0.0), shell)
	# central top outlet pipe (clean air up the middle)
	_cyl(p, r * 0.35, r * 0.35, size.y * 0.28, Vector3(0.0, size.y * 0.98, 0.0), steel)
	# tangential inlet near the top
	_box(p, Vector3(size.x * 0.5, size.y * 0.16, size.z * 0.28), Vector3(size.x * 0.36, size.y * 0.82, 0.0), steel)

# ── ventilator / blower: scroll volute + outlet + motor ───────────────────────
static func _m_blower(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.35, 0.5)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	_box(p, Vector3(size.x * 0.7, 0.18, size.z * 0.7), Vector3(0.0, 0.09, 0.0), dark)
	# scroll housing (axis along X)
	_cyl(p, size.y * 0.4, size.y * 0.4, size.x * 0.45, Vector3(0.0, size.y * 0.5, 0.0), body_mat, "x")
	# outlet duct out the top
	_box(p, Vector3(size.x * 0.3, size.y * 0.35, size.z * 0.3), Vector3(0.0, size.y * 0.85, 0.0), body_mat)
	# motor on the -X side
	_cyl(p, size.y * 0.26, size.y * 0.26, size.x * 0.35, Vector3(-size.x * 0.5, size.y * 0.5, 0.0), dark, "x")

# ── control cabinet (PCU): housing + HMI screen + vents + handle ──────────────
static func _m_cabinet(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.2, 0.4)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	_box(p, Vector3(size.x * 0.96, size.y * 0.96, size.z * 0.96), Vector3(0.0, size.y * 0.5, 0.0), body_mat)
	# HMI screen on the front (+Z)
	_box(p, Vector3(size.x * 0.55, size.y * 0.22, 0.04), Vector3(0.0, size.y * 0.7, size.z * 0.5), dark)
	# door handle
	_box(p, Vector3(0.04, size.y * 0.18, 0.05), Vector3(size.x * 0.3, size.y * 0.45, size.z * 0.5), steel)
	# louver vents low on the front
	for i in 3:
		_box(p, Vector3(size.x * 0.5, 0.02, 0.02), Vector3(0.0, size.y * 0.2 + float(i) * 0.06, size.z * 0.5), steel)

# ── door (catalog quick-place): frame + roller slats ──────────────────────────
static func _m_door(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.2, 0.6)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	# two side frames
	_box(p, Vector3(0.1, size.y, size.z), Vector3(size.x * 0.5, size.y * 0.5, 0.0), steel)
	_box(p, Vector3(0.1, size.y, size.z), Vector3(-size.x * 0.5, size.y * 0.5, 0.0), steel)
	# top roll housing
	_cyl(p, size.z * 1.4, size.z * 1.4, size.x * 0.95, Vector3(0.0, size.y * 0.97, 0.0), steel, "x")
	# horizontal roller slats
	for i in 7:
		_box(p, Vector3(size.x * 0.9, size.y * 0.12, size.z * 0.6), \
			Vector3(0.0, size.y * 0.08 + float(i) * (size.y * 0.13), 0.0), body_mat)

# ── mill / granulator: heavy chamber + feed hopper + big motor, guard, flywheel ─
## NEUE HERBOLD granulator on an elevated, railed, grated work platform — with a
## big angled white infeed hopper, a rust rotor/flywheel on one end, a drive motor
## + belt guard on the other, blue drive motors on the ground, a caged access
## ladder, and a ground stair to the right-rear (modelled from the operator photo).
static func _m_mill(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var white   := _mat(Color(0.85, 0.85, 0.81), ghost, 0.2, 0.6)   # NEUE HERBOLD cream
	var steel   := _mat(_STEEL, ghost, 0.55, 0.4)
	var dark    := _mat(_DARK, ghost, 0.5, 0.55)
	var grating := _mat(Color(0.36, 0.40, 0.38), ghost, 0.3, 0.85)
	var yellow  := _mat(_SAFETY, ghost, 0.2, 0.6)
	var rust    := _mat(Color(0.46, 0.30, 0.24), ghost, 0.35, 0.7)
	var blue    := _mat(Color(0.14, 0.34, 0.62), ghost, 0.35, 0.5)

	var deck_y : float = size.y * 0.40
	var hw : float = size.x * 0.40    # deck half-width (X)
	var hd : float = size.z * 0.34    # deck half-depth (Z); rear is left clear for the stair

	# ── Elevated platform: 4 legs + perimeter beams + grated deck ─────────────
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(0.14, deck_y, 0.14), Vector3(sx * hw, deck_y * 0.5, sz * hd), steel)
	_box(p, Vector3(hw * 2.0, 0.10, 0.10), Vector3(0, deck_y - 0.12,  hd), steel)
	_box(p, Vector3(hw * 2.0, 0.10, 0.10), Vector3(0, deck_y - 0.12, -hd), steel)
	_box(p, Vector3(0.10, 0.10, hd * 2.0), Vector3( hw, deck_y - 0.12, 0), steel)
	_box(p, Vector3(0.10, 0.10, hd * 2.0), Vector3(-hw, deck_y - 0.12, 0), steel)
	_box(p, Vector3(hw * 2.0, 0.06, hd * 2.0), Vector3(0, deck_y, 0), grating)
	# railing — open on +X (ladder) and -Z (stair landing)
	_railing(p, hw, hd, deck_y + 0.03, yellow, ["+x", "-z"])

	# ── Granulator body ON the deck ───────────────────────────────────────────
	var base_y : float = deck_y + 0.06
	var ch_h : float = size.y * 0.26
	_box(p, Vector3(hw * 1.1, ch_h, hd * 1.0), Vector3(0, base_y + ch_h * 0.5, 0), white)   # cutting chamber
	# angled infeed hopper (leans back over the chamber, wide opening faces up/front)
	var hop := _box(p, Vector3(hw * 1.0, size.y * 0.30, hd * 0.8), Vector3(0, base_y + ch_h + size.y * 0.11, -hd * 0.15), white)
	hop.rotation.x = deg_to_rad(20.0)
	# rotor / flywheel end (rust) on -X
	_cyl(p, ch_h * 0.55, ch_h * 0.55, 0.20, Vector3(-hw * 1.18, base_y + ch_h * 0.5, 0), rust, "x")
	# drive motor + V-belt guard on +X
	_motor_unit(p, ch_h * 0.34, hw * 0.7, Vector3(hw * 1.22, base_y + ch_h * 0.4, 0), "x", ghost)
	_guard(p, Vector3(hw * 0.5, ch_h * 0.7, 0.10), Vector3(hw * 0.9, base_y + ch_h * 0.5, hd * 0.32), ghost)
	# discharge hopper under the chamber (between the legs)
	_box(p, Vector3(hw * 0.8, deck_y * 0.55, hd * 0.8), Vector3(0, deck_y * 0.5, 0), dark)

	# ── Blue drive/pump motors on the ground beside the platform ──────────────
	_box(p, Vector3(0.5, 0.6, 0.5), Vector3( hw * 0.55, 0.30,  hd + 0.45), blue)
	_box(p, Vector3(0.5, 0.6, 0.5), Vector3(-hw * 0.30, 0.30,  hd + 0.45), blue)

	# ── Caged access ladder on the +X face ────────────────────────────────────
	_caged_ladder(p, Vector3(hw + 0.10, 0.0, hd * 0.35), deck_y + 0.9, steel)

	# ── Ground stair to the right-rear (+X, -Z), ascending toward the deck ────
	_stair(p, Vector3(hw * 0.55, 0.0, -hd - 1.0), deck_y, 0.9, grating, yellow)

## DOSEER (dosing) SILO — NOT a vertical round silo. It's a round silo laid on its
## side, cut horizontally in half: a long HALF-CYLINDER TROUGH (open top) with 3
## screw augers along the bottom that meter material out the bottom discharge. The
## outer two augers ride higher up the curved walls than the centre one (operator:
## "the 3 screws are angled upwards from the side walls"). Output is at the bottom.
static func _m_doseersilo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell  := _mat(color, ghost, 0.45, 0.45)
	var steel  := _mat(_STEEL, ghost, 0.55, 0.4)
	var dark   := _mat(_DARK, ghost, 0.5, 0.55)
	var flight := _mat(Color(0.78, 0.55, 0.16), ghost, 0.3, 0.5)   # auger flighting (brassy)

	var radius : float = size.x * 0.46
	var length : float = size.z * 0.92
	var leg_h : float = size.y * 0.34
	var axis_y : float = leg_h + radius            # trough axis height; bottom sits at leg_h
	var axis := Vector3(0.0, axis_y, 0.0)

	# ── Support legs + cross frame ────────────────────────────────────────────
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(0.16, leg_h, 0.16), Vector3(sx * radius * 0.8, leg_h * 0.5, sz * length * 0.42), steel)
	_box(p, Vector3(radius * 1.8, 0.12, 0.12), Vector3(0, leg_h - 0.1,  length * 0.42), steel)
	_box(p, Vector3(radius * 1.8, 0.12, 0.12), Vector3(0, leg_h - 0.1, -length * 0.42), steel)

	# ── Half-cylinder trough (open top) + round-ish end walls + top rim ───────
	_half_pipe(p, radius, length, axis, shell, 9)
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(radius * 2.0, radius, 0.06), Vector3(0, axis_y - radius * 0.5, sz * length * 0.5), shell)
	# top rim flanges along the open edges
	_box(p, Vector3(0.12, 0.10, length), Vector3( radius, axis_y, 0), steel)
	_box(p, Vector3(0.12, 0.10, length), Vector3(-radius, axis_y, 0), steel)

	# ── 3 augers along the bottom: centre lowest, outer two ride up the walls ──
	var shaft_r : float = radius * 0.06
	var flight_r : float = radius * 0.17
	var clr : float = flight_r * 1.15
	var side_x : float = radius * 0.5
	var side_y : float = axis_y - sqrt(maxf(radius * radius - side_x * side_x, 0.0)) + clr
	_auger(p, length, Vector3(0.0, axis_y - radius + clr, 0.0), shaft_r, flight_r, steel, flight)
	_auger(p, length, Vector3(-side_x, side_y, 0.0), shaft_r, flight_r, steel, flight)
	_auger(p, length, Vector3( side_x, side_y, 0.0), shaft_r, flight_r, steel, flight)

	# ── Bottom discharge chute (the output) between the legs ──────────────────
	_box(p, Vector3(radius * 0.9, leg_h * 0.7, length * 0.3), Vector3(0, leg_h * 0.5, 0), dark)
	# ── Auger drive motor at the +Z end ───────────────────────────────────────
	_motor_unit(p, radius * 0.16, radius * 0.4, Vector3(0, axis_y - radius + clr, length * 0.5 + radius * 0.3), "z", ghost)

# ── flotation tank: long water bath, inlet roll, transport rolls, big outlet roll
static func _m_flotation(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var tank := _mat(color, ghost, 0.4, 0.4)
	var water := _mat(Color(0.20, 0.45, 0.60, 0.55), ghost, 0.0, 0.1)
	var roller := _mat(_DARK, ghost, 0.4, 0.6)
	var legmat := _mat(_DARK, ghost, 0.5, 0.6)
	var hz := size.z * 0.5
	var ty := size.y * 0.5                 # tank floor height
	var wall_y := ty + size.y * 0.22
	_legs(p, size, ty, legmat)
	# tank: floor + 4 walls (open top)
	_box(p, Vector3(size.x * 0.92, 0.08, size.z * 0.96), Vector3(0.0, ty, 0.0), tank)
	_box(p, Vector3(0.08, size.y * 0.5, size.z * 0.96), Vector3(size.x * 0.46, wall_y, 0.0), tank)
	_box(p, Vector3(0.08, size.y * 0.5, size.z * 0.96), Vector3(-size.x * 0.46, wall_y, 0.0), tank)
	_box(p, Vector3(size.x * 0.92, size.y * 0.5, 0.08), Vector3(0.0, wall_y, hz * 0.96), tank)
	_box(p, Vector3(size.x * 0.92, size.y * 0.5, 0.08), Vector3(0.0, wall_y, -hz * 0.96), tank)
	# water surface
	_box(p, Vector3(size.x * 0.85, 0.04, size.z * 0.9), Vector3(0.0, ty + size.y * 0.34, 0.0), water)
	var roll_y := ty + size.y * 0.44
	# inlet roll (small) at -Z
	_cyl(p, size.y * 0.12, size.y * 0.12, size.x * 0.82, Vector3(0.0, roll_y, -hz * 0.85), roller, "x")
	# transport rolls (small, in the middle) — count differs per line; ~4 typical
	for i in 4:
		var zz := -hz * 0.5 + float(i) * (size.z * 0.25)
		_cyl(p, size.y * 0.1, size.y * 0.1, size.x * 0.82, Vector3(0.0, roll_y, zz), roller, "x")
	# outlet roll (LARGER) at +Z — drags the floating film out
	_cyl(p, size.y * 0.2, size.y * 0.2, size.x * 0.86, Vector3(0.0, roll_y + size.y * 0.04, hz * 0.85), roller, "x")
	_motor_unit(p, size.y * 0.14, size.x * 0.24, Vector3(size.x * 0.5, roll_y + size.y * 0.04, hz * 0.85), "x", ghost)
	# ── PHYSICALIZED FILM (#161) ──────────────────────────────────────────────
	# Shredded film drifts across the water toward the +Z outlet, getting pushed
	# UNDER at each transport roll — the flotation behaviour the operator wanted
	# to actually SEE. Skipped on ghost previews (no live animation needed there).
	if not ghost:
		var field : Node3D = preload("res://src/sim/FilmFlakeField.gd").new()
		field.name = "FilmField"
		field.flake_count = 110
		field.area = Vector2(size.x * 0.78, size.z * 0.85)
		field.surface_y = ty + size.y * 0.34 + 0.04
		field.flow_speed = 0.4
		field.flake_size = 0.07
		p.add_child(field)
		# A dunk zone under each transport roll (film shoved beneath the surface).
		for i in 4:
			var zz : float = -hz * 0.5 + float(i) * (size.z * 0.25)
			field.add_dunk_zone(0.0, zz, size.x * 0.22)

# ── sink/float separator (bezinkbakscheider) ────────────────────────────────
## CeDo line 3C / line 6 — twin parallel water troughs with a central drive
## housing, a paddle/screw skimmer in each channel, and overflow weirs at the
## downstream end. Built to match the user's two top-down reference photos
## (the bezinkafscheider seen from the catwalk grating).
##
## Layout (local frame, +Z = flow direction, +Y up):
##   • Two long rectangular troughs running along Z, one on -X and one on +X.
##   • Central stainless-steel drive cabinet between them, full length.
##   • Two paddle shafts (axis = Z, one per trough) skimming the float fraction.
##   • A pair of stainless-steel overflow weir plates at the +Z end (the angled
##     skim chutes visible in the photo) — they catch what floats.
##   • Inlet chutes drop in from above at the -Z end.
##   • Steel grating decks along the outside of each trough (walkways).
##   • Yellow safety rails on the outer edges of the decks.
##   • Water surface with a darker grey-green tint plus a scatter of tiny
##     coloured cubes to suggest mixed flake material floating.
static func _m_sinkfloat(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# ── Materials ─────────────────────────────────────────────────────────────
	var concrete := _mat(Color(0.42, 0.42, 0.43), ghost, 0.0, 0.85)
	var stainless := _mat(Color(0.74, 0.76, 0.78), ghost, 0.55, 0.30)
	var drive_grime := _mat(color, ghost, 0.20, 0.55)
	var water := _mat(Color(0.32, 0.40, 0.34, 0.78), ghost, 0.0, 0.20)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var safety := _mat(Color(0.92, 0.78, 0.18), ghost, 0.0, 0.85)
	var grating := _mat(Color(0.38, 0.42, 0.40), ghost, 0.0, 0.85)
	var _motor_mat := _mat(Color(0.20, 0.36, 0.55), ghost, 0.35, 0.45)

	# ── Dimensions / anchors ──────────────────────────────────────────────────
	var hx     := size.x * 0.5
	var _hz     := size.z * 0.5
	var trough_inner_w  := size.x * 0.30   # each trough is 30% of total width
	var center_w        := size.x * 0.22   # central drive cabinet
	var deck_w          := size.x * 0.09   # outer walkways
	var floor_y         := 0.06            # base slab top
	var trough_top_y    := size.y * 0.55   # top edge of trough walls
	var water_y         := size.y * 0.50   # water surface
	var trough_floor_y  := size.y * 0.10   # inside floor of trough
	var deck_y          := trough_top_y    # grating sits flush with wall tops

	# Trough centre-line X for left / right (mirrored)
	var trough_cx := center_w * 0.5 + trough_inner_w * 0.5

	# ── Base concrete slab ────────────────────────────────────────────────────
	_box(p, Vector3(size.x, 0.12, size.z), Vector3(0.0, floor_y, 0.0), concrete)

	# ── Central stainless drive cabinet (between the two troughs) ─────────────
	_box(p, Vector3(center_w, size.y * 0.85, size.z * 0.94),
			Vector3(0.0, size.y * 0.5, 0.0), stainless)
	# Lid panel + rivets (subtle horizontal seam near the top)
	_box(p, Vector3(center_w * 1.02, 0.04, size.z * 0.95),
			Vector3(0.0, size.y * 0.86, 0.0), dark)
	# Two motor humps poking out the top, one above each trough's drive
	_motor_unit(p, size.y * 0.10, size.x * 0.22,
			Vector3(0.0, size.y * 0.95, -size.z * 0.22), "x", ghost)
	_motor_unit(p, size.y * 0.10, size.x * 0.22,
			Vector3(0.0, size.y * 0.95,  size.z * 0.22), "x", ghost)
	# Belt-guard shrouds over each motor's pulley
	_guard(p, Vector3(size.x * 0.20, size.y * 0.18, size.z * 0.16),
			Vector3(0.0, size.y * 0.92, -size.z * 0.22), ghost)
	_guard(p, Vector3(size.x * 0.20, size.y * 0.18, size.z * 0.16),
			Vector3(0.0, size.y * 0.92,  size.z * 0.22), ghost)
	# Drive housing flank cladding (slight tone difference, runs full length)
	_box(p, Vector3(center_w * 1.04, size.y * 0.30, size.z * 0.85),
			Vector3(0.0, size.y * 0.45, 0.0), drive_grime)

	# ── Two parallel troughs (mirrored on X) ──────────────────────────────────
	for s in [-1.0, 1.0]:
		var cx : float = s * trough_cx
		# Trough outer wall (toward the walkway side)
		_box(p, Vector3(0.06, trough_top_y - floor_y, size.z * 0.96),
				Vector3(cx + s * trough_inner_w * 0.5,
						(floor_y + trough_top_y) * 0.5, 0.0), stainless)
		# Trough inner wall (toward the central housing) — slightly taller
		_box(p, Vector3(0.06, trough_top_y - floor_y + 0.10, size.z * 0.96),
				Vector3(cx - s * trough_inner_w * 0.5,
						(floor_y + trough_top_y + 0.10) * 0.5, 0.0), stainless)
		# Trough floor
		_box(p, Vector3(trough_inner_w + 0.06, 0.04, size.z * 0.96),
				Vector3(cx, trough_floor_y, 0.0), stainless)
		# End caps
		_box(p, Vector3(trough_inner_w + 0.06, trough_top_y - floor_y, 0.06),
				Vector3(cx, (floor_y + trough_top_y) * 0.5,  size.z * 0.48), stainless)
		_box(p, Vector3(trough_inner_w + 0.06, trough_top_y - floor_y, 0.06),
				Vector3(cx, (floor_y + trough_top_y) * 0.5, -size.z * 0.48), stainless)
		# Water surface (translucent) — tagged so BezinkTank raises/lowers it with
		# the live level (between the trough floor and the wall top).
		var wsurf := _box(p, Vector3(trough_inner_w, 0.02, size.z * 0.92),
				Vector3(cx, water_y, 0.0), water)
		wsurf.set_meta("bezink_water", true)
		wsurf.set_meta("y_lo", trough_floor_y + 0.06)
		wsurf.set_meta("y_hi", trough_top_y - 0.04)
		# Paddle/screw shaft running along Z (suspended just above the water)
		_cyl(p, trough_inner_w * 0.08, trough_inner_w * 0.08, size.z * 0.86,
				Vector3(cx, water_y + 0.05, 0.0), dark, "z")
		# Six paddle blades along the shaft (alternating tilt for a screw look)
		for i in range(6):
			var t : float = lerp(-size.z * 0.40, size.z * 0.40, float(i) / 5.0)
			var blade_tilt := deg_to_rad(20.0 if i % 2 == 0 else -20.0)
			var blade := _box(p,
					Vector3(trough_inner_w * 0.55, 0.02, trough_inner_w * 0.18),
					Vector3(cx, water_y + 0.05, t), stainless)
			blade.rotation.z = blade_tilt
		# Drive coupling from the central cabinet into this paddle shaft
		_cyl(p, trough_inner_w * 0.10, trough_inner_w * 0.10, center_w * 0.6,
				Vector3(cx - s * trough_inner_w * 0.4, water_y + 0.05, -size.z * 0.30),
				dark, "x")
		# Motor block where the drive enters the trough (matches the photo's
		# stubby cylindrical motor right at the trough edge).
		_motor_unit(p, trough_inner_w * 0.16, trough_inner_w * 0.40,
				Vector3(cx - s * trough_inner_w * 0.4, water_y + 0.05, -size.z * 0.30),
				"x", ghost)
		# Floating "flake" speckles on the water (small coloured cubes). Mixed
		# greys with the occasional bright colour — the recognisable wet-flake
		# look from the photo. Skipped on ghost previews to keep them light.
		if not ghost:
			var flake_colors := [
				Color(0.74, 0.76, 0.78),    # clear / silver
				Color(0.30, 0.42, 0.68),    # blue
				Color(0.78, 0.22, 0.18),    # red
				Color(0.20, 0.55, 0.32),    # green
				Color(0.85, 0.78, 0.20),    # yellow
				Color(0.55, 0.55, 0.56),    # grey
			]
			for i in range(28):
				var fx : float = trough_cx * s + ((i * 17) % 9 - 4) * (trough_inner_w * 0.10)
				var fz : float = ((i * 23) % 100 - 50) * (size.z * 0.0085)
				var c : Color = flake_colors[i % flake_colors.size()]
				var fm := _mat(c, ghost, 0.0, 0.7)
				_box(p, Vector3(0.05, 0.012, 0.05),
						Vector3(fx, water_y + 0.025, fz), fm)

	# ── Overflow weir plates at the +Z end (the angled skim chutes) ───────────
	# Two stainless-steel plates angled into the trough so the floating
	# fraction tips over the edge into a collector chute. Photo shows them
	# clearly between the troughs and the camera.
	for s in [-1.0, 1.0]:
		var cx : float = s * trough_cx
		var weir := _box(p,
				Vector3(trough_inner_w * 0.95, 0.04, size.z * 0.18),
				Vector3(cx, water_y - 0.02, size.z * 0.42), stainless)
		weir.rotation.x = deg_to_rad(18.0)
		# A small collector lip below the weir's down-stream edge.
		_box(p, Vector3(trough_inner_w * 0.95, 0.06, 0.04),
				Vector3(cx, water_y - 0.18, size.z * 0.49), stainless)

	# ── Inlet chute hoppers at the -Z end (flakes drop in from above) ─────────
	for s in [-1.0, 1.0]:
		var cx : float = s * trough_cx
		_box(p, Vector3(trough_inner_w * 0.6, size.y * 0.20, size.z * 0.10),
				Vector3(cx, trough_top_y + size.y * 0.12, -size.z * 0.40), drive_grime)
		# inlet pipe stub coming in horizontally
		_cyl(p, trough_inner_w * 0.10, trough_inner_w * 0.10, size.z * 0.18,
				Vector3(cx, trough_top_y + size.y * 0.12, -size.z * 0.30), dark, "z")

	# ── Outer walkway grating + yellow railings ───────────────────────────────
	for s in [-1.0, 1.0]:
		var deck_cx : float = s * (hx - deck_w * 0.5)
		_box(p, Vector3(deck_w, 0.04, size.z * 0.96),
				Vector3(deck_cx, deck_y, 0.0), grating)
		# Outer railing — short verticals + top rail
		var rail_y : float = deck_y + 0.55
		_box(p, Vector3(0.03, 1.1, size.z * 0.94),
				Vector3(deck_cx + s * (deck_w * 0.45), rail_y, 0.0), safety)
		# Three vertical posts along the length
		for i in range(3):
			var pz : float = lerp(-size.z * 0.42, size.z * 0.42, float(i) / 2.0)
			_box(p, Vector3(0.05, 1.1, 0.05),
					Vector3(deck_cx + s * (deck_w * 0.45), rail_y - 0.25, pz), safety)

	# ── Overhead inlet pipe spanning across the troughs (-Z end) ──────────────
	var pipe_mat := _mat(Color(0.78, 0.32, 0.10), ghost, 0.0, 0.7)  # orange/copper
	_cyl(p, 0.05, 0.05, size.x * 1.00,
			Vector3(0.0, trough_top_y + size.y * 0.45, -size.z * 0.40), pipe_mat, "x")
	# Drop tees down into each trough
	for s in [-1.0, 1.0]:
		var pipe_x : float = s * trough_cx
		_cyl(p, 0.04, 0.04, size.y * 0.40,
				Vector3(pipe_x, trough_top_y + size.y * 0.25, -size.z * 0.40),
				pipe_mat, "y")

	# ── Front + back containment walls (full tank width) so water is held ─────
	var wall_h : float = trough_top_y - floor_y
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(size.x * 0.98, wall_h, 0.08),
				Vector3(0.0, floor_y + wall_h * 0.5, sz * size.z * 0.49), stainless)

	# ── Process pump + discharge valve (drains the tank under level control) ──
	var pump_blue := _mat(Color(0.14, 0.34, 0.62), ghost, 0.35, 0.45)   # blue motor
	var valve_red := _mat(Color(0.74, 0.20, 0.16), ghost, 0.3, 0.5)     # red valve body
	var pmp_x : float = hx + 0.55
	var pmp_z : float = size.z * 0.28
	_box(p, Vector3(0.7, 0.2, 0.8), Vector3(pmp_x, 0.12, pmp_z), dark)              # pump skid
	_cyl(p, 0.22, 0.22, 0.5, Vector3(pmp_x, 0.45, pmp_z), stainless, "z")           # volute
	_box(p, Vector3(0.5, 0.42, 0.5), Vector3(pmp_x, 0.45, pmp_z + 0.45), pump_blue) # motor (blue)
	_cyl(p, 0.06, 0.06, 0.7, Vector3(hx + 0.2, 0.45, pmp_z), pipe_mat, "x")         # suction
	_cyl(p, 0.06, 0.06, 0.9, Vector3(pmp_x, 0.95, pmp_z), pipe_mat, "y")            # discharge riser
	_box(p, Vector3(0.2, 0.2, 0.2), Vector3(pmp_x, 1.38, pmp_z), valve_red)         # valve body
	_cyl(p, 0.16, 0.16, 0.03, Vector3(pmp_x, 1.55, pmp_z), stainless, "y")          # handwheel

	# ── Live tank controller (level + auto-valve + setpoints + HMI) ───────────
	# Real placed instances only — ghost build previews stay inert + lightweight.
	if not ghost:
		var ctrl : Node = load("res://src/sim/BezinkTank.gd").new()
		ctrl.name = "BezinkTank"
		p.add_child(ctrl)

# ── friction separator: inclined high-speed plate housing + hopper + big drive ─
static func _m_friction(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var tilt := deg_to_rad(15.0)
	_legs(p, size, size.y * 0.5, dark)
	# inclined housing (fatter, runs much faster than the dewatering screw)
	_tube(p, size.x * 0.42, size.z * 0.82, Vector3(0.0, size.y * 0.62, 0.0), body_mat, PI / 2.0 + tilt)
	# inlet hopper at the low (-Z) end
	_cyl(p, size.x * 0.34, size.x * 0.12, size.y * 0.4, Vector3(0.0, size.y * 0.82, -size.z * 0.3), dark)
	# large drive motor + V-belt guard at the low side
	_motor_unit(p, size.x * 0.26, size.z * 0.3, Vector3(size.x * 0.34, size.y * 0.4, -size.z * 0.28), "z", ghost)
	_guard(p, Vector3(size.x * 0.2, size.y * 0.4, size.z * 0.3), Vector3(size.x * 0.32, size.y * 0.55, -size.z * 0.08), ghost)

# ── dewatering screw: inclined perforated tube + water trough + top drive ──────
static func _m_dewater(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var tilt := deg_to_rad(20.0)
	# A-frame supports: short at the low (-Z) end, tall at the high (+Z) end
	_box(p, Vector3(0.1, size.y * 0.4, 0.1), Vector3(size.x * 0.3, size.y * 0.2, -size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.4, 0.1), Vector3(-size.x * 0.3, size.y * 0.2, -size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.9, 0.1), Vector3(size.x * 0.3, size.y * 0.45, size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.9, 0.1), Vector3(-size.x * 0.3, size.y * 0.45, size.z * 0.35), dark)
	# inclined dewatering tube (low at -Z, high at +Z)
	_tube(p, size.x * 0.3, size.z * 0.95, Vector3(0.0, size.y * 0.55, 0.0), steel, PI / 2.0 + tilt)
	# water collection trough at the bottom end
	_box(p, Vector3(size.x * 0.55, 0.15, size.z * 0.35), Vector3(0.0, size.y * 0.18, -size.z * 0.3), dark)
	# drive motor at the top (+Z) end
	_motor_unit(p, size.x * 0.18, size.z * 0.18, Vector3(0.0, size.y * 0.9, size.z * 0.42), "z", ghost)

# ── centrifugal pump: baseplate + volute + motor + coupling guard + piping ─────
static func _m_pump(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	# baseplate
	_box(p, Vector3(size.x * 0.95, 0.12, size.z * 0.95), Vector3(0.0, 0.06, 0.0), dark)
	# volute casing (snail) at the +Z end, axis along X
	_cyl(p, size.y * 0.4, size.y * 0.4, size.x * 0.42, Vector3(0.0, size.y * 0.42, size.z * 0.3), body_mat, "x")
	# discharge pipe up from the volute
	_cyl(p, size.x * 0.14, size.x * 0.14, size.y * 0.5, Vector3(0.0, size.y * 0.75, size.z * 0.3), dark)
	# suction pipe out the front (+Z), axis Z
	_cyl(p, size.x * 0.16, size.x * 0.16, size.z * 0.3, Vector3(0.0, size.y * 0.42, size.z * 0.5), dark, "z")
	# coupling guard then motor at the -Z end
	_guard(p, Vector3(size.x * 0.32, size.y * 0.32, size.z * 0.16), Vector3(0.0, size.y * 0.42, size.z * 0.04), ghost)
	_motor_unit(p, size.y * 0.3, size.z * 0.4, Vector3(0.0, size.y * 0.42, -size.z * 0.25), "z", ghost)

# ── HMI screen material (dark glass that glows faintly when "on") ─────────────
static func _screen_mat(ghost: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.metallic = 0.2
	m.roughness = 0.2
	if ghost:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.10, 0.20, 0.30, 0.4)
	else:
		m.albedo_color = Color(0.05, 0.09, 0.13)
		m.emission_enabled = true
		m.emission = Color(0.12, 0.42, 0.55)
		m.emission_energy_multiplier = 0.5
	return m

# ── HMI panel (stand): base + post + control head + screen + button cluster ───
static func _m_hmi(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var housing := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.4, 0.5)
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var screen := _screen_mat(ghost)
	var green := _mat(Color(0.12, 0.7, 0.2), ghost, 0.1, 0.5)
	var red := _mat(Color(0.85, 0.12, 0.1), ghost, 0.1, 0.5)
	var yellow := _mat(Color(0.85, 0.7, 0.15), ghost, 0.1, 0.5)
	# base + post
	_box(p, Vector3(size.x * 0.8, 0.06, size.z * 0.8), Vector3(0.0, 0.03, 0.0), dark)
	_cyl(p, 0.05, 0.05, size.y * 0.6, Vector3(0.0, size.y * 0.33, 0.0), steel)
	# control head
	var hy := size.y * 0.78
	_box(p, Vector3(size.x * 0.95, size.y * 0.4, size.z * 0.6), Vector3(0.0, hy, 0.0), housing)
	var fz := size.z * 0.3 + 0.012
	# touchscreen
	_box(p, Vector3(size.x * 0.7, size.y * 0.21, 0.015), Vector3(0.0, hy + size.y * 0.06, fz), screen)
	# button cluster below the screen (on the front face)
	var by := hy - size.y * 0.11
	_cyl(p, 0.022, 0.022, 0.025, Vector3(-size.x * 0.26, by, fz), green, "z")   # start
	_cyl(p, 0.022, 0.022, 0.025, Vector3(-size.x * 0.12, by, fz), red, "z")     # stop
	_cyl(p, 0.020, 0.020, 0.025, Vector3(size.x * 0.06, by, fz), yellow, "z")   # selector
	_cyl(p, 0.045, 0.045, 0.035, Vector3(size.x * 0.27, by, fz), red, "z")      # E-stop mushroom

# ── HMI panel (wall): compact head + screen + buttons (raise with [R] to mount)
static func _m_hmi_wall(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var housing := _mat(color, ghost, 0.3, 0.5)
	var screen := _screen_mat(ghost)
	var green := _mat(Color(0.12, 0.7, 0.2), ghost, 0.1, 0.5)
	var red := _mat(Color(0.85, 0.12, 0.1), ghost, 0.1, 0.5)
	var cy := size.y * 0.5
	_box(p, Vector3(size.x * 0.95, size.y * 0.9, size.z * 0.7), Vector3(0.0, cy, 0.0), housing)
	var fz := size.z * 0.35 + 0.012
	_box(p, Vector3(size.x * 0.78, size.y * 0.5, 0.014), Vector3(0.0, cy + size.y * 0.14, fz), screen)
	var by := cy - size.y * 0.26
	_cyl(p, 0.02, 0.02, 0.02, Vector3(-size.x * 0.2, by, fz), green, "z")
	_cyl(p, 0.02, 0.02, 0.02, Vector3(0.0, by, fz), red, "z")
	_cyl(p, 0.035, 0.035, 0.03, Vector3(size.x * 0.25, by, fz), red, "z")

## How many vertical sheets a bale of this footprint holds. Real recycling bales
## are baled film from THOUSANDS of bags/labels — the visible "compressed-sheet"
## count is much higher than a dozen. Roughly one slice per ~2.5 cm of length
## (3× the earlier ~8 cm), capped 30..60 so it's heterogeneous but never absurd.
static func _sheet_count_for(size: Vector3) -> int:
	var base := int(round(size.x / 0.025))
	return clampi(base, 30, 60)

## #28 — spawn a hand tool from the build menu (or a translucent box for the ghost).
static func _build_tool(id: String, size: Vector3, ghost: bool) -> Node3D:
	if ghost:
		return _simple_ghost(size)
	match id:
		"tool_shovel":   return load("res://src/scenes/world/ShovelTool.gd").new()
		"tool_scissors": return load("res://src/scenes/world/WireCutter.gd").new()
		"tool_scanner":  return load("res://src/scenes/world/BarcodeScanner.gd").new()
		"tool_lpg_rack": return load("res://src/scenes/world/LPGRack.gd").new()
	return null

## A translucent box used as a placement preview for items with no ghost model.
static func _simple_ghost(size: Vector3) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.40, 0.80, 1.0, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	n.add_child(mi)
	return n

## #33 — a 5x5 footprint of bales stacked to this origin's max allowance. Bales are
## LIGHT (tinted box + the full-girth wires) so a 50-75-bale pile stays performant;
## each still grabs + opens into the layered pieces (BaleBurst) when fed.
static func _build_bale_stack(origin: String, ghost: bool) -> Node3D:
	var o := BaleDefs.get_origin(origin)
	if o.is_empty():
		return null
	var bsize : Vector3 = o["size"]
	var high : int = int(o.get("stack", 2))
	var root := Node3D.new()
	root.name = "%s stack" % String(o.get("name", origin))
	if not ghost:
		root.set_meta("placeable_id", origin + "_stack5")
		root.add_to_group("placed_object")
	var gap := 0.06
	for ix in 5:
		for iz in 5:
			for iy in high:
				var bale := _build_light_bale(origin, ghost)
				if bale == null:
					continue
				root.add_child(bale)
				bale.position = Vector3(
					(float(ix) - 2.0) * (bsize.x + gap),
					float(iy) * (bsize.y + 0.02),
					(float(iz) - 2.0) * (bsize.z + gap))
	return root

## A single LIGHT bale (used by the stack): tinted box + full-girth wires + bale meta
## + a scannable label. Grabbable by the clamp and opens into pieces (BaleBurst) when fed.
static func _build_light_bale(origin: String, ghost: bool) -> Node3D:
	var o := BaleDefs.get_origin(origin)
	var size : Vector3 = o.get("size", Vector3(1.2, 1.05, 1.05))
	var tint : Color = o.get("tint", Color(0.60, 0.60, 0.55))
	var rb := RigidBody3D.new()
	rb.freeze = true
	rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rb.can_sleep = true
	rb.sleeping = true
	rb.mass = maxf(BaleDefs.estimated_weight(size), 1.0)
	rb.linear_damp = 0.4
	rb.angular_damp = 1.2
	if not ghost:
		rb.set_meta("material_origin", origin)
		rb.set_meta("scanned", false)
		rb.set_meta("wires_cut", false)
		rb.set_meta("clamp_force_needed", 0.30)
		rb.add_to_group("bale")
		var pm := PhysicsMaterial.new()
		pm.friction = 0.85
		pm.bounce = 0.05
		rb.physics_material_override = pm
		var label := Node3D.new()
		label.name = "Label"
		label.set_meta("label_info", {
			"item":       "%s bale" % String(o.get("name", origin)),
			"origin":     origin,
			"weight_kg":  int(round(BaleDefs.estimated_weight(size))),
			"batch":      "B-%04d" % (hash(origin + str(size)) & 0xFFFF),
			"dimensions": "%.2f x %.2f x %.2f m" % [size.x, size.y, size.z],
		})
		rb.add_child(label)
	# Visible sheet stack (a moderate count for a stacked pile) + a yellow shipping
	# label, so stacked bales read as REAL bales, not plain boxes. (#1 labels / #2 sheets)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(origin)
	var n_sheets := 12
	var t := size.x * 0.96 / float(n_sheets)
	for j in n_sheets:
		var mi := MeshInstance3D.new()
		var sbm := BoxMesh.new()
		sbm.size = Vector3(t * 0.92, size.y * 0.97, size.z * 0.97)
		mi.mesh = sbm
		mi.material_override = _mat(tint.lerp(_sample_sheet_color(rng), 0.5), ghost, 0.0, 0.88)
		mi.position = Vector3(-size.x * 0.48 + t * (float(j) + 0.5), size.y * 0.5, 0.0)
		rb.add_child(mi)
	if not ghost:
		# Yellow shipping label on the +Z face (matches the full bale's look).
		_box(rb, Vector3(0.11, 0.08, 0.004),
			Vector3(size.x * 0.18, size.y * 0.62, size.z * 0.5 + 0.004),
			_mat(Color(0.95, 0.85, 0.10), ghost, 0.0, 0.7))
	var wires := Node3D.new()
	wires.name = "Wires"
	rb.add_child(wires)
	_build_wires(wires, size, ghost)
	if not ghost:
		var col := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(size.x * 0.9, size.y, size.z * 0.9)
		col.shape = bx
		col.position = Vector3(0.0, size.y * 0.5, 0.0)
		rb.add_child(col)
	return rb

## Full-spectrum palette of transparent + opaque film colours sampled per sheet.
## Lowest-count entries are the DARK ones (black, dark grey) — they drag quality
## down in the LineFlow simulation. The net visual reads as greenish-grey blend
## (the operator's expectation) with occasional vivid splashes.
const SHEET_PALETTE : Array = [
	# Weight, RGBA — alpha < 1 means transparent film
	[15.0, Color(0.92, 0.92, 0.88, 0.55)],   # transparent white / clear film
	[14.0, Color(0.30, 0.55, 0.40, 0.70)],   # transparent green   (most common = dominant tint)
	[12.0, Color(0.25, 0.45, 0.75, 0.65)],   # transparent blue
	[10.0, Color(0.75, 0.20, 0.18, 0.65)],   # transparent red
	[ 9.0, Color(0.90, 0.55, 0.15, 0.65)],   # transparent orange
	[ 8.0, Color(0.78, 0.72, 0.18, 0.65)],   # transparent yellow
	[ 7.0, Color(0.62, 0.27, 0.72, 0.65)],   # transparent purple
	[ 6.0, Color(0.30, 0.78, 0.85, 0.60)],   # transparent cyan
	[ 6.0, Color(0.88, 0.55, 0.70, 0.70)],   # pink
	[ 8.0, Color(0.78, 0.72, 0.60, 0.85)],   # beige / tan (kraft / labels)
	[ 3.0, Color(0.18, 0.18, 0.18, 0.95)],   # dark grey      (rare, drags quality)
	[ 2.0, Color(0.06, 0.06, 0.06, 0.95)],   # black          (rarest, drags quality)
]

## Sample one sheet colour from SHEET_PALETTE by weight, deterministic per RNG.
static func _sample_sheet_color(rng: RandomNumberGenerator) -> Color:
	var total := 0.0
	for entry in SHEET_PALETTE:
		total += float(entry[0])
	var pick := rng.randf() * total
	var acc := 0.0
	for entry in SHEET_PALETTE:
		acc += float(entry[0])
		if pick <= acc:
			return entry[1]
	return SHEET_PALETTE[0][1]

# ── feedstock bale: vertical sheet stack + 3 iron wires + film patches + label ─
##
## The bale is logically a stack of N vertical sheets running from -X to +X
## (the bale's length). Each sheet is a thin YZ slab with varied thickness so
## the bunch looks pressed-and-bound. Three iron wires wrap each bale in the
## YZ plane (top → right → bottom → left → meet on top), evenly spaced along
## the length. The wires are kept as named children so the wire-cut tool can
## flip them invisible and the clamp-force feature can bulge them.
##
## Visual hierarchy:
##   bale (body)
##     Model (Node3D)
##       Sheets (Node3D)
##         Sheet_00 ... Sheet_N-1   (each a MeshInstance3D)
##       Wires (Node3D)
##         Wire_0  Wire_1  Wire_2   (each contains 4 cylinder segments)
##       Strapping / patches / yellow sticker (unchanged from before)
static func _m_bale(p: Node3D, id: String, size: Vector3, ghost: bool) -> void:
	var o := BaleDefs.get_origin(id)
	var tint: Color = o.get("tint", Color(0.72, 0.71, 0.66))
	var blue: float = float(o.get("blue", 0.0))

	# ── Sheets: stacked along X, full H × D ──────────────────────────────────
	var sheets_root := Node3D.new()
	sheets_root.name = "Sheets"
	p.add_child(sheets_root)
	var n_sheets := _sheet_count_for(size)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	# Generate varying thicknesses that sum to the bale length (inset 2% for strapping clearance)
	var inner_len := size.x * 0.98
	var thicks : Array[float] = []
	var tsum := 0.0
	for _i in n_sheets:
		var t := 0.7 + rng.randf() * 0.6   # 0.7..1.3 relative
		thicks.append(t)
		tsum += t
	for i in thicks.size():
		thicks[i] = thicks[i] / tsum * inner_len
	# Lay sheets out from -X to +X
	var _film_base := _mat(tint, ghost, 0.0, 0.9)
	var patch_blue := _mat(Color(0.30, 0.45, 0.85), ghost, 0.0, 0.85)
	var patch_warm := _mat(Color(tint.r * 0.8, tint.g * 0.8, tint.b * 0.72), ghost, 0.0, 0.9)
	var x := -inner_len * 0.5
	for i in thicks.size():
		var t: float = thicks[i]
		# Sample a sheet colour from the full-spectrum palette (green dominates,
		# dark+black are rare and pull quality down). Net stack reads greenish-grey.
		var col := _sample_sheet_color(rng)
		# Transparent films use the alpha-blend material path so the colours
		# layer realistically when stacked.
		var sheet_mat := _mat(col, ghost, 0.0, 0.85)
		if col.a < 0.99 and not ghost:
			sheet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var sheet := _box(sheets_root, Vector3(t * 0.95, size.y * 0.98, size.z * 0.98), \
			Vector3(x + t * 0.5, size.y * 0.5, 0.0), sheet_mat)
		sheet.name = "Sheet_%02d" % i
		# Roughly every 3rd sheet picks up a face patch (recycled = never uniform)
		if not ghost and (i % 3) == 1:
			var use_blue := rng.randf() < blue
			var pm := patch_blue if use_blue else patch_warm
			_box(sheets_root, Vector3(t * 0.7, size.y * 0.12, 0.008), \
				Vector3(x + t * 0.5, size.y * (0.25 + rng.randf() * 0.55), size.z * 0.495), pm)
		x += t

	# ── Three iron wires wrapping in the YZ plane, evenly spaced along X ─────
	var wires_root := Node3D.new()
	wires_root.name = "Wires"
	p.add_child(wires_root)
	_build_wires(wires_root, size, ghost)

	# (Removed: dark "strapping bands" that ran across the bale's full height.
	#  They were leaving two inseparable vertical black sheets behind whenever a
	#  cut bale opened — bug #95. The 3 iron wires already serve as visible
	#  strapping, so removing these bands is a clean fix.)

	# Yellow stapled label backing (~11×8 cm) on the front (+Z). The origin name
	# + unique barcode are printed on top by add_bale_label() after placement
	# (when the bale's unique code is known).
	if not ghost:
		var ylw := _mat(Color(0.95, 0.85, 0.10), false, 0.0, 0.7)
		_box(p, Vector3(0.11, 0.08, 0.004), Vector3(size.x * 0.18, size.y * 0.62, size.z * 0.5 + 0.003), ylw)

## Builds 3 iron wires (Wire_0/1/2), each a full loop around the bale's length+height
## (Top/Bottom run the full length over every sheet edge; Left/Right cap the ±X ends),
## spaced across the width (Z) so all three bind the whole sheet stack.
## Each wire is 4 darkened steel cylinders (top, right, bottom, left) plus 4
## small corner knots that overlap the segment ends so the wire reads as one
## continuous loop instead of disconnected sticks. Parented under a Node3D
## named "Wire_i" so the cutter can `queue_free` an entire wire, and the
## clamp-force bulge can lift the top segment alone.
static func _build_wires(root: Node3D, size: Vector3, ghost: bool) -> void:
	var wire := _mat(Color(0.18, 0.17, 0.16), ghost, 0.85, 0.30)
	# Thicker than the original 1.2 cm so the loops are clearly visible — real
	# bale-binding wire is ~3-4 mm but visually it needs to read at 5+ metres.
	var r := 0.018
	# 3 wires spaced across the WIDTH (Z). Each is a full loop around the bale's
	# length+height: Top and Bottom run the FULL LENGTH (X), crossing EVERY sheet's
	# edge; Left and Right cap the two end faces (±X). So each wire binds the whole
	# stack — cutting it releases all the sheets, not just one edge. (Was: a loop
	# around a single YZ slice, which only wrapped one sheet's worth.)
	var positions: Array[float] = [-size.z * 0.30, 0.0, size.z * 0.30]
	var top_y  : float = size.y + r * 0.5              # sits on top, half-sunk
	var bot_y  : float = -r * 0.5                       # sits under, half-sunk
	var end_x  : float = size.x * 0.5 + r * 0.5         # sits on the ±X end faces
	var horiz_len : float = size.x + r * 2.0            # Top/Bottom across the FULL length (all sheets)
	var vert_len  : float = size.y + r * 2.0            # Left/Right up the end faces, +overlap
	for i in positions.size():
		var wz: float = positions[i]
		var w := Node3D.new()
		w.name = "Wire_%d" % i
		w.position = Vector3(0.0, 0.0, wz)
		root.add_child(w)
		# Top — along X, running the full length over every sheet edge
		var top := _cyl(w, r, r, horiz_len, Vector3(0.0, top_y, 0.0), wire, "x")
		top.name = "Top"
		# Bottom — along X, under every sheet edge
		var bot := _cyl(w, r, r, horiz_len, Vector3(0.0, bot_y, 0.0), wire, "x")
		bot.name = "Bottom"
		# Right end cap — along Y, on the +X face
		var right_seg := _cyl(w, r, r, vert_len, Vector3( end_x, size.y * 0.5, 0.0), wire, "y")
		right_seg.name = "Right"
		# Left end cap — along Y, on the -X face
		var left_seg  := _cyl(w, r, r, vert_len, Vector3(-end_x, size.y * 0.5, 0.0), wire, "y")
		left_seg.name = "Left"
		# Tied-knot bump on top near one end — sells the "tied loop" read.
		var knot_mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = r * 1.6
		sphere.height = r * 3.2
		sphere.radial_segments = 10
		sphere.rings = 6
		knot_mi.mesh = sphere
		knot_mi.material_override = wire
		knot_mi.position = Vector3(end_x * 0.55, top_y + r * 0.4, 0.0)
		knot_mi.name = "Knot"
		w.add_child(knot_mi)

# ── rotation tank: water tank + horizontal rotating drum + scraper + drive ────
static func _m_rotation_tank(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var tank := _mat(color, ghost, 0.4, 0.4)
	var water := _mat(Color(0.20, 0.45, 0.60, 0.55), ghost, 0.0, 0.1)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var drum := _mat(_STEEL, ghost, 0.5, 0.45)
	var hz := size.z * 0.5
	var ty := size.y * 0.45
	var wy := ty + size.y * 0.25
	_legs(p, size, ty, dark)
	_box(p, Vector3(size.x * 0.92, 0.08, size.z * 0.94), Vector3(0.0, ty, 0.0), tank)
	_box(p, Vector3(0.08, size.y * 0.55, size.z * 0.94), Vector3(size.x * 0.46, wy, 0.0), tank)
	_box(p, Vector3(0.08, size.y * 0.55, size.z * 0.94), Vector3(-size.x * 0.46, wy, 0.0), tank)
	_box(p, Vector3(size.x * 0.92, size.y * 0.55, 0.08), Vector3(0.0, wy, hz * 0.94), tank)
	_box(p, Vector3(size.x * 0.92, size.y * 0.55, 0.08), Vector3(0.0, wy, -hz * 0.94), tank)
	_box(p, Vector3(size.x * 0.85, 0.04, size.z * 0.88), Vector3(0.0, ty + size.y * 0.32, 0.0), water)
	# rotating drum (axis Z)
	_cyl(p, size.y * 0.32, size.y * 0.32, size.z * 0.8, Vector3(0.0, ty + size.y * 0.4, 0.0), drum, "z")
	# bottom scraper trough (schraperbak) draining to a side
	_box(p, Vector3(size.x * 0.4, size.y * 0.18, size.z * 0.4), Vector3(0.0, ty + 0.12, hz * 0.3), dark)
	_motor_unit(p, size.y * 0.16, size.z * 0.26, Vector3(0.0, ty + size.y * 0.4, hz * 0.9), "z", ghost)
	_guard(p, Vector3(size.x * 0.25, size.y * 0.3, size.z * 0.16), Vector3(0.0, ty + size.y * 0.45, hz * 0.7), ghost)

# ── rafter: inclined vibrating sieve deck (zeefdek) + scraper trough + drive ───
static func _m_rafter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var tilt := deg_to_rad(-12.0)
	_legs(p, size, size.y * 0.5, dark)
	var deck := _box(p, Vector3(size.x * 0.8, 0.06, size.z * 0.92), Vector3(0.0, size.y * 0.6, 0.0), steel)
	deck.rotation = Vector3(tilt, 0.0, 0.0)
	var r1 := _box(p, Vector3(0.06, size.y * 0.2, size.z * 0.92), Vector3(size.x * 0.4, size.y * 0.62, 0.0), steel)
	r1.rotation = Vector3(tilt, 0.0, 0.0)
	var r2 := _box(p, Vector3(0.06, size.y * 0.2, size.z * 0.92), Vector3(-size.x * 0.4, size.y * 0.62, 0.0), steel)
	r2.rotation = Vector3(tilt, 0.0, 0.0)
	# scraper trough (schraperbak) under the low end
	_box(p, Vector3(size.x * 0.7, size.y * 0.2, size.z * 0.3), Vector3(0.0, size.y * 0.3, -size.z * 0.32), dark)
	# vibrator / drive motor on the side
	_motor_unit(p, size.x * 0.16, size.z * 0.18, Vector3(size.x * 0.42, size.y * 0.55, size.z * 0.2), "z", ghost)

# ── transport screw: closed auger tube (conveying only — NO dewatering) ───────
static func _m_transport_screw(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var tilt := deg_to_rad(18.0)
	_box(p, Vector3(0.1, size.y * 0.45, 0.1), Vector3(size.x * 0.3, size.y * 0.22, -size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.45, 0.1), Vector3(-size.x * 0.3, size.y * 0.22, -size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.9, 0.1), Vector3(size.x * 0.3, size.y * 0.45, size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.9, 0.1), Vector3(-size.x * 0.3, size.y * 0.45, size.z * 0.35), dark)
	# Closed conveying tube (solid wall — no perforations, no water trough). The
	# tube must ASCEND from the low inlet (-Z, short legs) to the high drive (+Z,
	# tall legs): that's PI/2 - tilt. (It was PI/2 + tilt, which tipped the +Z end
	# DOWN — the tube ran opposite its own support frame, so the screw read as
	# "rotated 180°" / running the wrong way. Operator: it goes from low → up.)
	_tube(p, size.x * 0.28, size.z * 0.95, Vector3(0.0, size.y * 0.55, 0.0), steel, PI / 2.0 - tilt)
	# feed inlet box at the LOW end (-Z) — sits under the friction-separator outlet
	_box(p, Vector3(size.x * 0.5, size.y * 0.25, size.z * 0.18), Vector3(0.0, size.y * 0.35, -size.z * 0.42), dark)
	# drive at the HIGH end (+Z)
	_motor_unit(p, size.x * 0.18, size.z * 0.18, Vector3(0.0, size.y * 0.9, size.z * 0.42), "z", ghost)

# ── friction washer (Frictiewasser): horizontal high-speed wash drum + spray ──
static func _m_friction_washer(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var steel := _mat(_STEEL, ghost, 0.55, 0.4)
	_legs(p, size, size.y * 0.5, dark)
	# horizontal wash housing (axis Z)
	_cyl(p, size.x * 0.42, size.x * 0.42, size.z * 0.8, Vector3(0.0, size.y * 0.6, 0.0), body_mat, "z")
	# inlet hopper (-Z) + outlet chute (+Z)
	_cyl(p, size.x * 0.3, size.x * 0.12, size.y * 0.4, Vector3(0.0, size.y * 0.85, -size.z * 0.32), dark)
	_box(p, Vector3(size.x * 0.4, size.y * 0.3, size.z * 0.16), Vector3(0.0, size.y * 0.42, size.z * 0.42), dark)
	# water spray pipe along the top
	_cyl(p, size.x * 0.06, size.x * 0.06, size.z * 0.7, Vector3(0.0, size.y * 0.95, 0.0), steel, "z")
	# big drive + V-belt guard
	_motor_unit(p, size.x * 0.24, size.z * 0.3, Vector3(size.x * 0.36, size.y * 0.4, -size.z * 0.28), "z", ghost)
	_guard(p, Vector3(size.x * 0.2, size.y * 0.4, size.z * 0.3), Vector3(size.x * 0.34, size.y * 0.55, -size.z * 0.08), ghost)

# ── intensive washer (Intensiefwasser): compact wash cell + top drive + pipes ─
static func _m_intensive_washer(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var steel := _mat(_STEEL, ghost, 0.55, 0.4)
	_box(p, Vector3(size.x * 0.85, 0.25, size.z * 0.85), Vector3(0.0, 0.12, 0.0), dark)
	_box(p, Vector3(size.x * 0.7, size.y * 0.6, size.z * 0.7), Vector3(0.0, size.y * 0.45, 0.0), body_mat)
	# top vertical drive
	_motor_unit(p, size.x * 0.2, size.y * 0.3, Vector3(0.0, size.y * 0.9, 0.0), "y", ghost)
	# water pipe + inlet/outlet chutes
	_cyl(p, size.x * 0.08, size.x * 0.08, size.z * 0.4, Vector3(size.x * 0.3, size.y * 0.55, size.z * 0.3), steel, "z")
	_box(p, Vector3(size.x * 0.3, size.y * 0.2, size.z * 0.16), Vector3(0.0, size.y * 0.7, -size.z * 0.42), dark)
	_box(p, Vector3(size.x * 0.3, size.y * 0.2, size.z * 0.16), Vector3(0.0, size.y * 0.3, size.z * 0.42), dark)

# ── wet film silo (vuilsnippersilo): cone silo + top distributor + extraction screw
static func _m_vuilsnippersilo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.35, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var r := size.x * 0.46
	var leg_h := size.y * 0.16
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			_box(p, Vector3(0.12, leg_h, 0.12), Vector3(sx * r * 0.7, leg_h * 0.5, sz * r * 0.7), dark)
	# conical bottom + cylindrical body
	_cyl(p, r, 0.2, size.y * 0.3, Vector3(0.0, leg_h + size.y * 0.15, 0.0), shell)
	_cyl(p, r, r, size.y * 0.45, Vector3(0.0, leg_h + size.y * 0.52, 0.0), shell)
	# top wing-distributor drive (vertical)
	_motor_unit(p, size.x * 0.16, size.y * 0.22, Vector3(0.0, leg_h + size.y * 0.8, 0.0), "y", ghost)
	# extraction screw (uittrekschroef) out the lower side
	_tube(p, size.x * 0.16, size.z * 0.7, Vector3(size.x * 0.3, leg_h + size.y * 0.18, 0.0), steel, PI / 2.0 + deg_to_rad(18.0))

# ── MAS trough: pre-extruder agglomeration trough + paddle drive ──────────────
static func _m_mas_bak(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	_legs(p, size, size.y * 0.5, dark)
	_box(p, Vector3(size.x * 0.8, size.y * 0.45, size.z * 0.92), Vector3(0.0, size.y * 0.66, 0.0), body_mat)
	# top access covers
	for i in 3:
		var zz := -size.z * 0.3 + float(i) * (size.z * 0.3)
		_box(p, Vector3(size.x * 0.6, size.y * 0.12, size.z * 0.16), Vector3(0.0, size.y * 0.92, zz), steel)
	# paddle drive
	_motor_unit(p, size.y * 0.16, size.x * 0.28, Vector3(size.x * 0.2, size.y * 0.66, size.z * 0.5), "x", ghost)
	_guard(p, Vector3(size.x * 0.22, size.y * 0.3, size.z * 0.1), Vector3(-size.x * 0.1, size.y * 0.7, size.z * 0.46), ghost)

# ── PCU = EREMA cutter/COMPACTOR: an upright cylindrical drum. The cutter disc
#    spins inside; flake is friction-heated, dried + densified, then fed out the
#    side into the extruder screw. (Labelled 3C HMI: 112 °C, 169 kW — the PCU is
#    THIS upright unit, NOT the big round laserfilter disc downstream.) ───────────
static func _m_compactor(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var steel := _mat(_STEEL, ghost, 0.55, 0.4)
	_box(p, Vector3(size.x * 0.9, 0.3, size.z * 0.9), Vector3(0.0, 0.15, 0.0), dark)
	# Upright drum body (the compaction chamber).
	var drum_r : float = size.x * 0.42
	_cyl(p, drum_r, drum_r, size.y * 0.72, Vector3(0.0, size.y * 0.5, 0.0), body_mat)
	# Reinforcing rings around the drum.
	for ry in [0.28, 0.52, 0.74]:
		_cyl(p, drum_r * 1.05, drum_r * 1.05, size.y * 0.035, Vector3(0.0, size.y * ry, 0.0), steel)
	# Top lid + feed funnel where the compactorband drops the flake in.
	_cyl(p, drum_r, drum_r, size.y * 0.05, Vector3(0.0, size.y * 0.88, 0.0), steel)
	_cyl(p, size.x * 0.28, size.x * 0.1, size.y * 0.22, Vector3(-size.x * 0.16, size.y * 0.99, -size.z * 0.16), steel)
	# Tangential outlet to the extruder screw (+Z side, low).
	_cyl(p, size.x * 0.13, size.x * 0.13, size.z * 0.36, Vector3(0.0, size.y * 0.34, size.z * 0.44), dark, "z")
	# Big cutter drive motor under the drum.
	_motor_unit(p, size.x * 0.22, size.y * 0.28, Vector3(0.0, size.y * 0.2, -size.z * 0.22), "y", ghost)

# ── Extruder (3C screw): horizontal barrel, screw drive/gearbox at the feed (-Z)
#    end, a feed throat on top fed by the PCU, TWO vacuum degas domes on the barrel
#    (the operator's 2 vacuum zones), heater bands, melt out the +Z end to the
#    laserfilter. (Labelled 3C HMI: 138 rpm, 187 kW.) ───────────────────────────
static func _m_extruder_screw(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var body_mat := _mat(color, ghost, 0.25, 0.55)
	var hz : float = size.z * 0.5
	_box(p, Vector3(size.x * 0.85, 0.35, size.z * 0.96), Vector3(0.0, 0.18, 0.0), dark)
	# Gearbox / drive housing at the feed (-Z) end + the big screw drive motor.
	_box(p, Vector3(size.x * 0.8, size.y * 0.7, size.z * 0.26), Vector3(0.0, size.y * 0.5, -hz * 0.78), body_mat)
	_motor_unit(p, size.x * 0.22, size.z * 0.18, Vector3(0.0, size.y * 0.5, -hz * 0.99), "z", ghost)
	# Feed throat on top of the gearbox where the PCU drops compacted flake in.
	_cyl(p, size.x * 0.26, size.x * 0.12, size.y * 0.4, Vector3(0.0, size.y * 0.92, -hz * 0.6), steel)
	# Barrel running toward the +Z (die) end + heater bands.
	var barrel_len : float = size.z * 0.78
	_cyl(p, size.x * 0.17, size.x * 0.17, barrel_len, Vector3(0.0, size.y * 0.5, hz * 0.08), steel, "z")
	for i in 6:
		var zz : float = -hz * 0.28 + float(i) * (barrel_len * 0.15)
		_cyl(p, size.x * 0.21, size.x * 0.21, 0.07, Vector3(0.0, size.y * 0.5, zz), dark, "z")
	# TWO vacuum degas domes on top of the barrel (the 2 vacuum zones).
	for zz in [hz * 0.02, hz * 0.42]:
		_cyl(p, size.x * 0.12, size.x * 0.12, size.y * 0.4, Vector3(0.0, size.y * 0.78, zz), steel)
		_cyl(p, size.x * 0.15, size.x * 0.15, size.y * 0.05, Vector3(0.0, size.y * 1.0, zz), dark)   # dome cap
	# Melt outlet flange at the +Z tip (to the laserfilter).
	_cyl(p, size.x * 0.13, size.x * 0.13, size.z * 0.12, Vector3(0.0, size.y * 0.5, hz * 0.96), dark, "z")

# ── Vacuum degassing zone: the already-FILTERED melt passes under a vacuum dome
#    while a vacuum pump pulls residual moisture + volatiles off. Tall chamber +
#    domed cap + a take-off pipe to a side vacuum-pump box + melt in/out. In a
#    TVEplus this sits AFTER the Laserfilter (filtration-before-degassing). ───────
static func _m_vacuum_degas(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.4, 0.4)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	_legs(p, size, size.y * 0.4, dark)
	# Melt channel housing (horizontal, along Z) the melt flows through.
	_box(p, Vector3(size.x * 0.5, size.y * 0.3, size.z * 0.95), Vector3(0.0, size.y * 0.5, 0.0), body)
	# Tall vacuum chamber/dome rising off the channel.
	_cyl(p, size.x * 0.3, size.x * 0.3, size.y * 0.5, Vector3(0.0, size.y * 0.82, 0.0), steel)
	_cyl(p, size.x * 0.32, 0.02, size.y * 0.12, Vector3(0.0, size.y * 1.07, 0.0), steel)            # domed cap
	# Vacuum take-off pipe to a side vacuum-pump box (-X).
	_cyl(p, size.x * 0.08, size.x * 0.08, size.x * 0.5, Vector3(-size.x * 0.35, size.y * 0.95, 0.0), dark, "x")
	_box(p, Vector3(size.x * 0.32, size.y * 0.3, size.z * 0.4), Vector3(-size.x * 0.52, size.y * 0.55, 0.0), body)
	_motor_unit(p, size.x * 0.12, size.z * 0.2, Vector3(-size.x * 0.52, size.y * 0.3, 0.0), "z", ghost)
	# Melt pipe in (-Z, from the laserfilter) and out (+Z, to the meltpump).
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.3, Vector3(0.0, size.y * 0.5, -size.z * 0.5), dark, "z")
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.3, Vector3(0.0, size.y * 0.5, size.z * 0.5), dark, "z")

# =============================================================================
# LINE 3C EXTRUDER BACK-END (#175)
# =============================================================================
# ── Compactorband: a steel feed belt that lifts dosed flake from the Extruder
#    Silo up into the compactor's top funnel. Inclined deck + end rollers +
#    side skirts + a discharge lip at the high (+Z) end. ────────────────────────
static func _m_compactorband(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var skirt := _mat(color, ghost, 0.3, 0.6)
	var hz := size.z * 0.45
	# Frame legs — taller at the +Z (discharge) end so the belt climbs.
	var signs : Array[float] = [-1.0, 1.0]
	for sx in signs:
		_box(p, Vector3(0.09, size.y * 0.42, 0.09), Vector3(sx * size.x * 0.4, size.y * 0.21, -hz * 0.8), steel)
		_box(p, Vector3(0.09, size.y * 0.78, 0.09), Vector3(sx * size.x * 0.4, size.y * 0.39, hz * 0.8), steel)
	# Inclined belt frame: a box tilted about X so it rises toward +Z.
	var inc := Node3D.new()
	inc.position = Vector3(0.0, size.y * 0.55, 0.0)
	inc.rotation.x = -deg_to_rad(20.0)
	p.add_child(inc)
	_box(inc, Vector3(size.x * 0.78, 0.06, size.z * 0.96), Vector3.ZERO, dark)           # belt deck
	_box(inc, Vector3(0.05, size.y * 0.16, size.z * 0.96), Vector3(size.x * 0.4, size.y * 0.1, 0.0), skirt)
	_box(inc, Vector3(0.05, size.y * 0.16, size.z * 0.96), Vector3(-size.x * 0.4, size.y * 0.1, 0.0), skirt)
	# End rollers (crosswise) at each end of the incline.
	_cyl(inc, size.y * 0.12, size.y * 0.12, size.x * 0.84, Vector3(0.0, 0.0, hz * 0.94), dark, "x")
	_cyl(inc, size.y * 0.12, size.y * 0.12, size.x * 0.84, Vector3(0.0, 0.0, -hz * 0.94), dark, "x")
	# Discharge lip at the top that drops flake into the compactor funnel.
	_box(p, Vector3(size.x * 0.5, size.y * 0.12, 0.4), Vector3(0.0, size.y * 0.82, hz * 0.85), steel)
	# Drive motor at the head pulley.
	_motor_unit(p, size.y * 0.1, size.x * 0.22, Vector3(size.x * 0.42, size.y * 0.7, hz * 0.8), "x", ghost)

# ── Kopfilter: the die-head screen-changer — a heated melt block with a
#    horizontal slide-plate (carries the screen pack) + melt pipe in/out. ───────
static func _m_kopfilter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	_legs(p, size, size.y * 0.5, dark)
	# Heated melt-adapter block. NB single-Laserfilter TVEplus has NO die-head screen
	# changer (the Laserfilter replaced it), so this is just the die head — no slide bar.
	_box(p, Vector3(size.x * 0.7, size.y * 0.55, size.z * 0.6), Vector3(0.0, size.y * 0.6, -size.z * 0.1), body)
	# Heater-band rings around the adapter.
	for zz in [-0.28, -0.08, 0.12]:
		_cyl(p, size.x * 0.2, size.x * 0.2, 0.05, Vector3(0.0, size.y * 0.6, zz * size.z), dark, "z")
	# Conical die plate at the +Z face (melt exits to the hot-face cutter / heetafslag).
	_cyl(p, size.x * 0.26, size.x * 0.34, size.z * 0.18, Vector3(0.0, size.y * 0.6, size.z * 0.38), steel, "z")
	_cyl(p, size.x * 0.34, size.x * 0.34, 0.05, Vector3(0.0, size.y * 0.6, size.z * 0.48), dark, "z")   # die face
	# Melt pipe in (-Z) from the meltpump.
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.4, Vector3(0.0, size.y * 0.6, -size.z * 0.5), dark, "z")

# ── Heetafslag: hot-face die + underwater pelletizer cutter. The melt is forced
#    through the die plate and a spinning blade head shears it into pellets in a
#    water-filled cutting chamber; the pellet-water slurry leaves out the +Z side
#    to the dewater screen. This is where the granulate first appears. ──────────
static func _m_heetafslag(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.35, 0.5)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var water := _mat(Color(0.22, 0.44, 0.52, 0.6), ghost, 0.0, 0.2)
	_legs(p, size, size.y * 0.45, dark)
	# Die plate / adapter where the melt arrives (-Z face).
	_cyl(p, size.x * 0.22, size.x * 0.22, size.z * 0.18, Vector3(0.0, size.y * 0.58, -size.z * 0.4), steel, "z")
	# Round cutting-chamber housing (the water box around the blade head).
	_cyl(p, size.x * 0.32, size.x * 0.32, size.z * 0.4, Vector3(0.0, size.y * 0.58, 0.0), body, "z")
	# Cutter drive motor on the downstream face.
	_motor_unit(p, size.x * 0.16, size.z * 0.22, Vector3(0.0, size.y * 0.58, size.z * 0.42), "z", ghost)
	# Pellet-water slurry box beneath + outlet pipe to the dewater screen (+Z).
	_box(p, Vector3(size.x * 0.6, size.y * 0.22, size.z * 0.5), Vector3(0.0, size.y * 0.2, size.z * 0.1), dark)
	_box(p, Vector3(size.x * 0.54, 0.05, size.z * 0.44), Vector3(0.0, size.y * 0.3, size.z * 0.1), water)
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.4, Vector3(0.0, size.y * 0.2, size.z * 0.5), steel, "z")

# ── Ontwaterzeef: an inclined vibrating dewater screen. Wet pellets land on the
#    sieve deck, water drains through into a sump while the pellets walk up to the
#    high (+Z) discharge; a vibratory motor sits on the deck. ───────────────────
static func _m_ontwaterzeef(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var frame := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.55, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var water := _mat(Color(0.22, 0.42, 0.5, 0.55), ghost, 0.0, 0.2)
	var hz := size.z * 0.5
	_legs(p, size, size.y * 0.4, dark)
	# Sump tray under the deck that catches the drained water.
	_box(p, Vector3(size.x * 0.86, size.y * 0.22, size.z * 0.9), Vector3(0.0, size.y * 0.42, 0.0), frame)
	_box(p, Vector3(size.x * 0.78, 0.04, size.z * 0.82), Vector3(0.0, size.y * 0.5, 0.0), water)
	# Inclined screen deck rising toward +Z (pellets walk up out of the water).
	var inc := Node3D.new()
	inc.position = Vector3(0.0, size.y * 0.62, 0.0)
	inc.rotation.x = -deg_to_rad(15.0)
	p.add_child(inc)
	_box(inc, Vector3(size.x * 0.74, 0.04, size.z * 0.92), Vector3.ZERO, steel)
	for sx in [-0.38, 0.38]:
		_box(inc, Vector3(0.04, size.y * 0.14, size.z * 0.92), Vector3(sx * size.x, size.y * 0.07, 0.0), frame)
	# Discharge lip at the high end.
	_box(p, Vector3(size.x * 0.5, size.y * 0.1, 0.35), Vector3(0.0, size.y * 0.72, hz * 0.86), steel)
	# Vibratory drive motor clamped to the deck side.
	_motor_unit(p, size.y * 0.12, size.x * 0.24, Vector3(size.x * 0.42, size.y * 0.6, 0.0), "x", ghost)

# ── Weegschaal: a 25 kg batch weigher — a feed funnel over a weigh hopper sitting
#    on load-cell legs, with a bottom discharge gate and a small readout box. ────
static func _m_weegschaal(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.55, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	# Four support posts (the load cells sit on these).
	var signs : Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			_box(p, Vector3(0.08, size.y * 0.5, 0.08), Vector3(sx * size.x * 0.38, size.y * 0.25, sz * size.z * 0.38), steel)
			# load-cell pucks on top of each post
			_cyl(p, 0.06, 0.06, 0.06, Vector3(sx * size.x * 0.38, size.y * 0.53, sz * size.z * 0.38), dark)
	# Top feed funnel (wide mouth) catching pellets from the centrifuge.
	_cyl(p, size.x * 0.42, size.x * 0.12, size.y * 0.3, Vector3(0.0, size.y * 0.85, 0.0), steel)
	# Weigh hopper (inverted-cone bin) hanging on the load cells.
	_cyl(p, size.x * 0.4, size.x * 0.1, size.y * 0.42, Vector3(0.0, size.y * 0.36, 0.0), body)
	# Bottom discharge gate.
	_box(p, Vector3(size.x * 0.2, size.y * 0.1, size.z * 0.2), Vector3(0.0, size.y * 0.12, 0.0), dark)
	# Small digital read-out box on a stalk at the front (+Z).
	if not ghost:
		_box(p, Vector3(size.x * 0.28, size.y * 0.16, 0.05), Vector3(size.x * 0.3, size.y * 0.62, size.z * 0.42),
			_mat(Color(0.10, 0.12, 0.14), false, 0.2, 0.4))

# ── steel skip (PLASTIC, sat under a chute): green-grey weathered box with
#    visible forklift pockets at the base. Forklift drives in, lifts, dumps. ──
static func _m_steel_skip(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.35, 0.65)
	var dark := _mat(_DARK, ghost, 0.45, 0.6)
	var rim := _mat(Color(color.r * 0.7, color.g * 0.7, color.b * 0.7), ghost, 0.45, 0.6)
	# Pallet base + visible forklift pockets (two horizontal tubes running -Z to +Z).
	_box(p, Vector3(size.x * 0.98, 0.14, size.z * 0.98), Vector3(0.0, 0.08, 0.0), dark)
	for sx in [-size.x * 0.30, size.x * 0.30]:
		_box(p, Vector3(0.12, 0.10, size.z), Vector3(sx, 0.10, 0.0), dark)
	# Skip body: 5 walls + open top, slightly raked outward.
	var wy: float = size.y * 0.55 + 0.18
	_box(p, Vector3(size.x * 0.95, size.y * 0.85, 0.08), Vector3(0.0, wy, size.z * 0.49), steel)
	_box(p, Vector3(size.x * 0.95, size.y * 0.85, 0.08), Vector3(0.0, wy, -size.z * 0.49), steel)
	_box(p, Vector3(0.08, size.y * 0.85, size.z * 0.96), Vector3(size.x * 0.49, wy, 0.0), steel)
	_box(p, Vector3(0.08, size.y * 0.85, size.z * 0.96), Vector3(-size.x * 0.49, wy, 0.0), steel)
	# Rolled top rim.
	_box(p, Vector3(size.x * 1.0, 0.05, 0.12), Vector3(0.0, wy + size.y * 0.425, size.z * 0.5), rim)
	_box(p, Vector3(size.x * 1.0, 0.05, 0.12), Vector3(0.0, wy + size.y * 0.425, -size.z * 0.5), rim)
	# "PLASTIC" sticker on the front face (cream label).
	if not ghost:
		var lbl_bg := _mat(Color(0.92, 0.88, 0.78), false, 0.0, 0.85)
		_box(p, Vector3(0.28, 0.18, 0.005), Vector3(0.0, wy, size.z * 0.5 + 0.01), lbl_bg)
		var lbl := Label3D.new()
		lbl.text = "PLASTIC"
		lbl.font_size = 36
		lbl.pixel_size = 0.0014
		lbl.modulate = Color(0.10, 0.10, 0.10)
		lbl.position = Vector3(0.0, wy, size.z * 0.5 + 0.018)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(lbl)

# ── fines bin (under-conveyor): black plastic bin on castors, ~1 m cube ──────
static func _m_fines_bin(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.05, 0.85)
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	# Walls + base
	_box(p, Vector3(size.x * 0.98, 0.05, size.z * 0.98), Vector3(0.0, 0.05, 0.0), dark)
	_box(p, Vector3(size.x * 0.98, size.y * 0.95, 0.04), Vector3(0.0, size.y * 0.5, size.z * 0.49), body)
	_box(p, Vector3(size.x * 0.98, size.y * 0.95, 0.04), Vector3(0.0, size.y * 0.5, -size.z * 0.49), body)
	_box(p, Vector3(0.04, size.y * 0.95, size.z * 0.96), Vector3(size.x * 0.49, size.y * 0.5, 0.0), body)
	_box(p, Vector3(0.04, size.y * 0.95, size.z * 0.96), Vector3(-size.x * 0.49, size.y * 0.5, 0.0), body)
	# 4 castors at the corners
	for sx in [-size.x * 0.4, size.x * 0.4]:
		for sz in [-size.z * 0.4, size.z * 0.4]:
			_cyl(p, 0.05, 0.05, 0.06, Vector3(sx, 0.03, sz), dark, "x")

# ── cyclone underflow bin: grey steel cube on the floor under a cyclone chute ─
static func _m_cyclone_bin(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.55, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.55)
	_box(p, Vector3(size.x * 0.98, 0.1, size.z * 0.98), Vector3(0.0, 0.05, 0.0), dark)
	_box(p, Vector3(size.x * 0.95, size.y * 0.95, 0.06), Vector3(0.0, size.y * 0.5, size.z * 0.49), steel)
	_box(p, Vector3(size.x * 0.95, size.y * 0.95, 0.06), Vector3(0.0, size.y * 0.5, -size.z * 0.49), steel)
	_box(p, Vector3(0.06, size.y * 0.95, size.z * 0.95), Vector3(size.x * 0.49, size.y * 0.5, 0.0), steel)
	_box(p, Vector3(0.06, size.y * 0.95, size.z * 0.95), Vector3(-size.x * 0.49, size.y * 0.5, 0.0), steel)

# ── IBC tote: 1 m³ caged white plastic tank on a wooden pallet (fluids) ──────
static func _m_ibc_tote(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var plastic := _mat(color, ghost, 0.0, 0.4)
	if not ghost:
		plastic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		plastic.albedo_color = Color(color.r, color.g, color.b, 0.85)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var wood := _mat(Color(0.62, 0.48, 0.30), ghost, 0.0, 0.85)
	# Wooden pallet base
	_box(p, Vector3(size.x, 0.15, size.z), Vector3(0.0, 0.075, 0.0), wood)
	# White translucent plastic tank inside the cage
	var ty := 0.15 + size.y * 0.5
	_box(p, Vector3(size.x * 0.94, size.y * 0.92, size.z * 0.94), Vector3(0.0, ty, 0.0), plastic)
	# Cage bars — outer frame + horizontal grid (signature IBC look)
	for sx in [-size.x * 0.5, size.x * 0.5]:
		_box(p, Vector3(0.04, size.y, 0.04), Vector3(sx, ty, size.z * 0.5), dark)
		_box(p, Vector3(0.04, size.y, 0.04), Vector3(sx, ty, -size.z * 0.5), dark)
	for sz in [-size.z * 0.5, size.z * 0.5]:
		_box(p, Vector3(size.x, 0.04, 0.04), Vector3(0.0, ty + size.y * 0.5, sz), dark)
		_box(p, Vector3(size.x, 0.04, 0.04), Vector3(0.0, ty - size.y * 0.5, sz), dark)
	# 3 horizontal grid bars on the front face (the IBC tell)
	for ry in [ty - size.y * 0.3, ty, ty + size.y * 0.3]:
		_box(p, Vector3(size.x, 0.03, 0.03), Vector3(0.0, ry, size.z * 0.5), dark)
	# Outlet valve nub at the bottom front
	_box(p, Vector3(0.16, 0.12, 0.18), Vector3(size.x * 0.3, 0.25, size.z * 0.5 + 0.05), dark)

# ── waste container (schraperbak skip): open-top bin, forklift-emptied ────────
static func _m_waste_container(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var wy := size.y * 0.5
	_box(p, Vector3(size.x * 0.96, 0.1, size.z * 0.96), Vector3(0.0, size.y * 0.18, 0.0), steel)
	_box(p, Vector3(0.08, size.y * 0.7, size.z * 0.96), Vector3(size.x * 0.48, wy, 0.0), steel)
	_box(p, Vector3(0.08, size.y * 0.7, size.z * 0.96), Vector3(-size.x * 0.48, wy, 0.0), steel)
	_box(p, Vector3(size.x * 0.96, size.y * 0.7, 0.08), Vector3(0.0, wy, size.z * 0.48), steel)
	_box(p, Vector3(size.x * 0.96, size.y * 0.7, 0.08), Vector3(0.0, wy, -size.z * 0.48), steel)
	# forklift pockets at the base
	_box(p, Vector3(size.x * 0.25, 0.12, size.z * 1.0), Vector3(size.x * 0.22, 0.06, 0.0), dark)
	_box(p, Vector3(size.x * 0.25, 0.12, size.z * 1.0), Vector3(-size.x * 0.22, 0.06, 0.0), dark)

# ── bunker: open-top steel pit + 4 bunker rollers at the bottom + side motor ──
##
## Bales are dumped into the top opening; the rollers at the floor meter the
## load out the discharge end onto the feeding belt of Shredder 1. Sized for
## one truck-bay of intake (~4 m × 3 m footprint, 4 m tall).
static func _m_bunker(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.45, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var wall_h := size.y * 0.95
	var wt := 0.10                                  # wall thickness
	# Floor
	_box(p, Vector3(size.x, 0.18, size.z), Vector3(0.0, 0.09, 0.0), dark)
	# Four walls (open top) — the +Z wall is shorter so a discharge mouth is
	# visible at the front.
	_box(p, Vector3(wt, wall_h, size.z), Vector3(-hx + wt * 0.5, wall_h * 0.5 + 0.1, 0.0), steel)
	_box(p, Vector3(wt, wall_h, size.z), Vector3( hx - wt * 0.5, wall_h * 0.5 + 0.1, 0.0), steel)
	_box(p, Vector3(size.x, wall_h, wt), Vector3(0.0, wall_h * 0.5 + 0.1, -hz + wt * 0.5), steel)
	# Front (discharge) wall — only the upper half, so the rollers + outgoing
	# material are visible.
	_box(p, Vector3(size.x, wall_h * 0.55, wt), \
		Vector3(0.0, wall_h * 0.6 + 0.4, hz - wt * 0.5), steel)
	# Bunker rollers — four chunky cylinders along X, evenly spaced along Z.
	# They feed material outward (+Z direction) into the discharge mouth.
	var roller_y := 0.4
	var roller_r := 0.22
	var roller_len := size.x * 0.88
	for i in 4:
		var t := float(i) / 3.0                     # 0, 1/3, 2/3, 1
		var z_pos := -hz * 0.7 + t * (size.z * 1.0)
		_cyl(p, roller_r, roller_r, roller_len, Vector3(0.0, roller_y, z_pos), dark, "x")
	# Drive motor on the +X side, low — turns the bunker-roller chain.
	_motor_unit(p, 0.28, 0.65, Vector3(hx + 0.05, roller_y, 0.0), "z", ghost)
	_guard(p, Vector3(0.6, 0.35, 0.18), Vector3(hx + 0.05, roller_y + 0.45, 0.0), ghost)
	# Top rim/lip walkway — narrow band around the top so the visual reads
	# as "you can dump bales in here".
	var rim_y := size.y - 0.05
	_box(p, Vector3(size.x + 0.1, 0.04, 0.2), Vector3(0.0, rim_y, -hz), dark)
	_box(p, Vector3(size.x + 0.1, 0.04, 0.2), Vector3(0.0, rim_y,  hz), dark)
	_box(p, Vector3(0.2, 0.04, size.z + 0.1), Vector3(-hx, rim_y, 0.0), dark)
	_box(p, Vector3(0.2, 0.04, size.z + 0.1), Vector3( hx, rim_y, 0.0), dark)

# ── Shredder 1 (coarse pre-shredder): heavy + big throat + dual rotors ────────
##
## Bigger and beefier than the generic shredder model. Two huge slow-turning
## cutter shafts visible at the throat, a massive drive motor, V-belt guard,
## heavy concrete base. Outputs ≤ 10×10 cm chunks.
static func _m_shredder_1(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var body_mat := _mat(color, ghost, 0.3, 0.55)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	# Heavy concrete-poured base
	_box(p, Vector3(size.x, 0.5, size.z), Vector3(0.0, 0.25, 0.0), dark)
	# Lower steel skirt
	_box(p, Vector3(size.x * 0.95, size.y * 0.18, size.z * 0.92), Vector3(0.0, 0.6, 0.0), steel)
	# Main cutting chamber
	_box(p, Vector3(size.x * 0.82, size.y * 0.42, size.z * 0.78), Vector3(0.0, size.y * 0.5, 0.0), body_mat)
	# Big rectangular feed hopper — wide mouth at the top
	_box(p, Vector3(size.x * 0.88, size.y * 0.28, size.z * 0.7), Vector3(0.0, size.y * 0.85, 0.0), steel)
	# Two slow-turning cutter shafts visible at the throat
	for i in 2:
		var x_off: float = (-0.20 if i == 0 else 0.20) * size.x
		_box(p, Vector3(size.x * 0.16, size.y * 0.15, size.z * 0.68), Vector3(x_off, size.y * 0.7, 0.0), dark)
		# End-cap / shaft visible on +Z face
		_cyl(p, size.y * 0.09, size.y * 0.09, 0.1, Vector3(x_off, size.y * 0.7, hz * 0.78), steel, "z")
	# Massive drive motor on the -X side
	_motor_unit(p, size.y * 0.26, size.z * 0.55, Vector3(-hx * 0.95, size.y * 0.45, 0.0), "x", ghost)
	# Large V-belt guard between motor + chamber
	_guard(p, Vector3(size.x * 0.22, size.y * 0.5, size.z * 0.32), \
		Vector3(-hx * 0.72, size.y * 0.5, hz * 0.2), ghost)
	# Discharge chute under the chamber, +Z side
	_box(p, Vector3(size.x * 0.5, size.y * 0.18, size.z * 0.18), \
		Vector3(0.0, size.y * 0.25, hz * 0.85), dark)
	# Side cooling fins on +X to differentiate from Shredder 2
	for i in 6:
		var fz := -hz * 0.45 + float(i) * (size.z * 0.18)
		_box(p, Vector3(0.06, size.y * 0.32, size.z * 0.04), Vector3(hx * 0.92, size.y * 0.5, fz), dark)

# ── Shredder 2 (compact fine shredder): smaller, faster, single rotor ─────────
static func _m_shredder_2(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var body_mat := _mat(color, ghost, 0.3, 0.5)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	# Base
	_box(p, Vector3(size.x * 0.95, 0.28, size.z * 0.95), Vector3(0.0, 0.14, 0.0), dark)
	# Compact body
	_box(p, Vector3(size.x * 0.82, size.y * 0.52, size.z * 0.78), Vector3(0.0, size.y * 0.55, 0.0), body_mat)
	# Smaller feed throat — round funnel rather than rectangular hopper
	_cyl(p, size.x * 0.34, size.x * 0.18, size.y * 0.35, Vector3(0.0, size.y * 0.92, 0.0), steel)
	# Single high-speed rotor visible
	_box(p, Vector3(size.x * 0.56, size.y * 0.09, size.z * 0.5), Vector3(0.0, size.y * 0.66, 0.0), dark)
	# Smaller drive motor — high RPM type
	_motor_unit(p, size.y * 0.18, size.z * 0.42, Vector3(-hx * 0.97, size.y * 0.55, 0.0), "x", ghost)
	_guard(p, Vector3(size.x * 0.18, size.y * 0.4, size.z * 0.22), \
		Vector3(-hx * 0.75, size.y * 0.55, hz * 0.16), ghost)
	# Discharge chute on +Z (output flake size ~1-2 cm)
	_box(p, Vector3(size.x * 0.35, size.y * 0.2, size.z * 0.16), \
		Vector3(0.0, size.y * 0.32, hz * 0.93), dark)

# ── Inclined transport belt (45°, 8 m rise) ──────────────────────────────────
##
## Sized 1 × 8.5 × 8.5 (in local X/Y/Z). The belt runs from local (0,0,0) up
## diagonally to (0, 8, 8) — a 45° incline that climbs 8 m vertically over 8 m
## of horizontal travel. Use to bring Shredder 2's flake stream up to the small
## feed hopper that drops onto the washing-line belts.
static func _m_inclined_belt(p: Node3D, _size: Vector3, _color: Color, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var rise := 8.0
	var horiz := 8.0
	var diag := sqrt(rise * rise + horiz * horiz)    # ~11.31 m
	var angle := atan2(rise, horiz)                  # PI/4
	var mid := Vector3(0.0, rise * 0.5, horiz * 0.5)
	# Diagonal belt deck — rotated about local X so its long axis lies along
	# the (Y+Z) diagonal. Inner span = 0.85 m wide.
	var deck := _box(p, Vector3(0.85, 0.06, diag), mid, dark)
	deck.rotation = Vector3(angle, 0.0, 0.0)
	# Side rails
	for sx in [-1.0, 1.0]:
		var rail := _box(p, Vector3(0.06, 0.18, diag), \
			mid + Vector3(sx * 0.42, 0.10, 0.0), steel)
		rail.rotation = Vector3(angle, 0.0, 0.0)
	# End rollers (axis along X, crossing the belt)
	_cyl(p, 0.22, 0.22, 0.95, Vector3(0.0, 0.25, 0.25), dark, "x")               # bottom roller
	_cyl(p, 0.22, 0.22, 0.95, Vector3(0.0, rise - 0.25, horiz - 0.25), dark, "x")  # top roller
	# A-frame support legs at 1/4, 1/2, 3/4 along the diagonal
	for i in [1, 2, 3]:
		var t: float = float(i) / 4.0
		var ly := t * rise
		var lz := t * horiz
		_box(p, Vector3(0.08, ly, 0.08), Vector3(-0.36, ly * 0.5, lz), steel)
		_box(p, Vector3(0.08, ly, 0.08), Vector3( 0.36, ly * 0.5, lz), steel)
		# Cross-brace at the top of each leg pair
		_box(p, Vector3(0.78, 0.06, 0.06), Vector3(0.0, ly, lz), steel)
	# Drive motor at the top (next to the top roller)
	_motor_unit(p, 0.18, 0.36, Vector3(0.55, rise - 0.25, horiz - 0.25), "x", ghost)
	# Catch-pan under the bottom roller (where stray flakes land)
	_box(p, Vector3(1.2, 0.08, 0.5), Vector3(0.0, 0.04, 0.5), dark)

# ── Small feed hopper (20 cm flanges) — sits at the top of the inclined belt ──
##
## Funnel-shaped: ~1 m square wide top, narrows down to a 20 cm outlet, with
## two angled steel flanges below the outlet that guide flakes onto the
## downstream horizontal belt. Sized 1 × 1.2 × 1 so it sits compactly on top
## of the inclined belt's terminal frame.
static func _m_feed_hopper(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.45)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	# Funnel: wide at top, narrows to a small outlet at the bottom
	_cyl(p, size.x * 0.48, size.x * 0.12, size.y * 0.78, \
		Vector3(0.0, size.y * 0.5, 0.0), steel)
	# Two angled flanges (the 20 cm "guide rails") below the outlet, directing
	# material in +Z (where the downstream horizontal belt sits)
	var flange_h := 0.20
	var flange_len := 0.35
	for sx in [-1.0, 1.0]:
		var flange := _box(p, Vector3(0.04, flange_h, flange_len), \
			Vector3(sx * 0.10, size.y * 0.15, size.z * 0.15), steel)
		flange.rotation.z = sx * deg_to_rad(28.0)
	# Small under-flange catch tray
	_box(p, Vector3(size.x * 0.45, 0.04, size.z * 0.45), \
		Vector3(0.0, size.y * 0.04, size.z * 0.1), dark)
	# 4 support legs from the funnel base down to the ground
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(0.06, size.y * 0.1, 0.06), \
				Vector3(sx * size.x * 0.35, size.y * 0.05, sz * size.z * 0.35), dark)

# ── SGA opener drum: large inclined trommel + feed hopper + fines tray + drive ─
static func _m_sga_drum(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var tilt := deg_to_rad(6.0)
	_legs(p, size, size.y * 0.5, dark)
	# rotating trommel drum (slightly inclined, runs along Z)
	_tube(p, size.x * 0.4, size.z * 0.84, Vector3(0.0, size.y * 0.62, 0.0), shell, PI / 2.0 + tilt)
	# raised drive bands around the drum
	for sz in [-0.25, 0.25]:
		_tube(p, size.x * 0.43, 0.12, Vector3(0.0, size.y * 0.62 - sz * sin(tilt) * size.z, sz * size.z), steel, PI / 2.0 + tilt)
	# feed hopper at the high (-Z) end
	_cyl(p, size.x * 0.34, size.x * 0.14, size.y * 0.4, Vector3(0.0, size.y * 0.92, -size.z * 0.4), dark)
	# fines screen tray under the drum (grit drops through)
	_box(p, Vector3(size.x * 0.72, size.y * 0.16, size.z * 0.72), Vector3(0.0, size.y * 0.28, 0.0), dark)
	# drive at the low (+Z) end
	_motor_unit(p, size.x * 0.16, size.z * 0.22, Vector3(size.x * 0.42, size.y * 0.45, size.z * 0.4), "z", ghost)

# ── overband metal separator: belt + suspended magnet gantry + tramp-metal box ─
static func _m_metal_belt(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(color, ghost, 0.5, 0.45)
	var magnet := _mat(Color(0.18, 0.20, 0.24), ghost, 0.55, 0.45)
	var hz := size.z * 0.45
	var deck_y := size.y * 0.45
	_legs(p, size, deck_y, steel)
	# belt rollers + deck
	_cyl(p, size.y * 0.12, size.y * 0.12, size.x * 0.9, Vector3(0.0, deck_y, hz), dark, "x")
	_cyl(p, size.y * 0.12, size.y * 0.12, size.x * 0.9, Vector3(0.0, deck_y, -hz), dark, "x")
	_box(p, Vector3(size.x * 0.82, 0.05, size.z * 0.9), Vector3(0.0, deck_y + size.y * 0.12, 0.0), dark)
	# overband magnet on a gantry above the belt
	_box(p, Vector3(0.08, size.y * 0.42, 0.08), Vector3(size.x * 0.4, deck_y + size.y * 0.4, 0.0), steel)
	_box(p, Vector3(0.08, size.y * 0.42, 0.08), Vector3(-size.x * 0.4, deck_y + size.y * 0.4, 0.0), steel)
	_box(p, Vector3(size.x * 0.6, size.y * 0.2, size.z * 0.4), Vector3(0.0, deck_y + size.y * 0.58, 0.0), magnet)
	# tramp-metal catch box off the +Z end
	_box(p, Vector3(size.x * 0.5, size.y * 0.28, size.z * 0.14), Vector3(0.0, deck_y * 0.6, hz * 0.92), steel)

# ── ballistic separator: inclined paddle housing + feed hopper + 2 discharge lips
static func _m_ballistic(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	_legs(p, size, size.y * 0.45, dark)
	# main inclined housing
	var house := _box(p, Vector3(size.x * 0.8, size.y * 0.5, size.z * 0.84), Vector3(0.0, size.y * 0.66, 0.0), body_mat)
	house.rotation = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
	# feed hopper at the high (-Z) end
	_cyl(p, size.x * 0.32, size.x * 0.14, size.y * 0.4, Vector3(0.0, size.y * 0.95, -size.z * 0.34), dark)
	# paddle shaft ends poking out the +X side
	for i in 3:
		var zz := -size.z * 0.25 + float(i) * (size.z * 0.25)
		_cyl(p, size.x * 0.06, size.x * 0.06, 0.12, Vector3(size.x * 0.42, size.y * 0.72, zz), steel, "x")
	# two discharge lips at the low (+Z) end — film over, heavies under
	_box(p, Vector3(size.x * 0.7, 0.06, size.z * 0.2), Vector3(0.0, size.y * 0.82, size.z * 0.42), steel)
	_box(p, Vector3(size.x * 0.7, 0.06, size.z * 0.2), Vector3(0.0, size.y * 0.46, size.z * 0.4), dark)
	# drive
	_motor_unit(p, size.x * 0.16, size.z * 0.2, Vector3(size.x * 0.42, size.y * 0.5, -size.z * 0.3), "z", ghost)

# ── windshifter (zig-zag air classifier): rising duct + blower + light-fraction duct
static func _m_windsifter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	# tall rising separation chamber
	_box(p, Vector3(size.x * 0.5, size.y * 0.78, size.z * 0.5), Vector3(0.0, size.y * 0.46, 0.0), shell)
	# feed inlet on the lower -Z side
	_box(p, Vector3(size.x * 0.4, size.y * 0.18, size.z * 0.2), Vector3(0.0, size.y * 0.42, -size.z * 0.34), dark)
	# heavies drop-out hopper at the bottom
	_cyl(p, size.x * 0.24, size.x * 0.1, size.y * 0.22, Vector3(0.0, size.y * 0.12, size.z * 0.18), dark)
	# light-fraction duct off the top (toward a cyclone)
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.5, Vector3(0.0, size.y * 0.82, size.z * 0.3), steel, "z")
	# blower at the base on the -X side
	_cyl(p, size.y * 0.14, size.y * 0.14, size.x * 0.4, Vector3(-size.x * 0.38, size.y * 0.2, 0.0), dark, "x")

# ── TITECH NIR optical sorter: accel belt + scanner hood + blue sensor + valves ─
static func _m_optical_sorter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var nir := _mat(Color(0.20, 0.50, 0.95), ghost, 0.1, 0.3)
	var hz := size.z * 0.45
	var deck_y := size.y * 0.5
	_legs(p, size, deck_y, steel)
	# acceleration belt
	_cyl(p, size.y * 0.12, size.y * 0.12, size.x * 0.9, Vector3(0.0, deck_y, hz), dark, "x")
	_cyl(p, size.y * 0.12, size.y * 0.12, size.x * 0.9, Vector3(0.0, deck_y, -hz), dark, "x")
	_box(p, Vector3(size.x * 0.82, 0.05, size.z * 0.9), Vector3(0.0, deck_y + size.y * 0.12, 0.0), dark)
	# scanner hood spanning the belt
	_box(p, Vector3(size.x * 0.92, size.y * 0.32, size.z * 0.3), Vector3(0.0, deck_y + size.y * 0.42, 0.0), body_mat)
	# blue NIR sensor strip on the underside of the hood
	_box(p, Vector3(size.x * 0.8, 0.05, size.z * 0.06), Vector3(0.0, deck_y + size.y * 0.26, 0.0), nir)
	# air-ejection valve block at the discharge (+Z) end
	_box(p, Vector3(size.x * 0.86, size.y * 0.16, size.z * 0.12), Vector3(0.0, deck_y + size.y * 0.06, hz * 0.9), steel)
	# accept/reject splitter chute below the discharge
	_box(p, Vector3(size.x * 0.7, 0.05, size.z * 0.2), Vector3(0.0, deck_y * 0.55, hz * 0.96), steel)
	# control cabinet at the -Z corner
	_box(p, Vector3(size.x * 0.2, size.y * 0.5, size.z * 0.34), Vector3(size.x * 0.42, size.y * 0.4, -hz * 0.5), dark)

# ── pre-wash drum: wash drum in a water trough + spray pipe + inlet/outlet ─────
static func _m_prewash_drum(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.4)
	var water := _mat(Color(0.20, 0.45, 0.60, 0.55), ghost, 0.0, 0.1)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var ty := size.y * 0.4
	_legs(p, size, ty, dark)
	# water trough
	_box(p, Vector3(size.x * 0.86, size.y * 0.3, size.z * 0.92), Vector3(0.0, ty + size.y * 0.12, 0.0), dark)
	_box(p, Vector3(size.x * 0.8, 0.04, size.z * 0.86), Vector3(0.0, ty + size.y * 0.24, 0.0), water)
	# horizontal wash drum (axis Z) sitting in the trough
	_cyl(p, size.x * 0.32, size.x * 0.32, size.z * 0.82, Vector3(0.0, ty + size.y * 0.34, 0.0), shell, "z")
	# inlet hopper (-Z) + outlet chute (+Z)
	_cyl(p, size.x * 0.3, size.x * 0.12, size.y * 0.36, Vector3(0.0, ty + size.y * 0.62, -size.z * 0.34), dark)
	_box(p, Vector3(size.x * 0.4, size.y * 0.26, size.z * 0.16), Vector3(0.0, ty + size.y * 0.05, size.z * 0.44), dark)
	# spray pipe along the top
	_cyl(p, size.x * 0.05, size.x * 0.05, size.z * 0.7, Vector3(0.0, ty + size.y * 0.6, 0.0), steel, "z")
	# drive
	_motor_unit(p, size.x * 0.2, size.z * 0.26, Vector3(size.x * 0.36, ty + size.y * 0.34, -size.z * 0.3), "z", ghost)

# ── Kufferath wedge-wire sieve: housing + inclined screen deck + filtrate launder
static func _m_kufferath(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var screen := _mat(Color(0.70, 0.72, 0.74), ghost, 0.6, 0.3)
	_legs(p, size, size.y * 0.5, dark)
	# enclosing housing
	_box(p, Vector3(size.x * 0.8, size.y * 0.42, size.z * 0.9), Vector3(0.0, size.y * 0.62, 0.0), steel)
	# inclined wedge-wire screen deck visible on top
	var deck := _box(p, Vector3(size.x * 0.7, 0.05, size.z * 0.84), Vector3(0.0, size.y * 0.84, 0.0), screen)
	deck.rotation = Vector3(deg_to_rad(-14.0), 0.0, 0.0)
	# feed box at the high (-Z) end
	_box(p, Vector3(size.x * 0.5, size.y * 0.2, size.z * 0.16), Vector3(0.0, size.y * 0.95, -size.z * 0.4), dark)
	# filtrate launder (drained water) along the low side
	_box(p, Vector3(size.x * 0.84, size.y * 0.16, size.z * 0.2), Vector3(0.0, size.y * 0.32, -size.z * 0.34), dark)
	# vibrator motor
	_motor_unit(p, size.x * 0.14, size.z * 0.18, Vector3(size.x * 0.42, size.y * 0.66, size.z * 0.2), "z", ghost)

# ── mixing silo (mengsilo): legs + cone bottom + body + top mixer drive + ladder
static func _m_mengsilo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.35, 0.45)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var r := size.x * 0.46
	var leg_h := size.y * 0.14
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			_box(p, Vector3(0.14, leg_h, 0.14), Vector3(sx * r * 0.72, leg_h * 0.5, sz * r * 0.72), dark)
	# conical bottom + cylindrical body + short top
	_cyl(p, r, 0.16, size.y * 0.24, Vector3(0.0, leg_h + size.y * 0.12, 0.0), shell)
	_cyl(p, r, r, size.y * 0.46, Vector3(0.0, leg_h + size.y * 0.47, 0.0), shell)
	_cyl(p, r * 0.3, r, size.y * 0.08, Vector3(0.0, leg_h + size.y * 0.74, 0.0), shell)
	# top mixer drive
	_motor_unit(p, size.x * 0.14, size.y * 0.18, Vector3(0.0, leg_h + size.y * 0.84, 0.0), "y", ghost)
	# discharge outlet under the cone + side access ladder
	_cyl(p, 0.1, 0.1, size.y * 0.12, Vector3(0.0, leg_h * 0.5, 0.0), dark)
	_box(p, Vector3(0.04, size.y * 0.6, 0.04), Vector3(r * 0.95, leg_h + size.y * 0.42, 0.0), steel)

# ── ZSS water plant: skid + buffer tanks + clarifier cone + pipe rack + dosing pumps
static func _m_zss(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.35, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var water := _mat(Color(0.20, 0.45, 0.60, 0.55), ghost, 0.0, 0.1)
	# skid base
	_box(p, Vector3(size.x * 0.96, 0.18, size.z * 0.96), Vector3(0.0, 0.09, 0.0), dark)
	# two tall buffer tanks on the -X side
	_cyl(p, size.x * 0.2, size.x * 0.2, size.y * 0.8, Vector3(-size.x * 0.28, size.y * 0.45, -size.z * 0.2), shell)
	_cyl(p, size.x * 0.2, size.x * 0.2, size.y * 0.8, Vector3(-size.x * 0.28, size.y * 0.45, size.z * 0.2), shell)
	# clarifier (conical bottom + body + water surface) on the +X side
	_cyl(p, size.x * 0.26, 0.12, size.y * 0.3, Vector3(size.x * 0.26, size.y * 0.3, 0.0), shell)
	_cyl(p, size.x * 0.26, size.x * 0.26, size.y * 0.3, Vector3(size.x * 0.26, size.y * 0.6, 0.0), shell)
	_cyl(p, size.x * 0.24, size.x * 0.24, 0.04, Vector3(size.x * 0.26, size.y * 0.73, 0.0), water)
	# interconnecting pipe rack along the top
	_cyl(p, 0.06, 0.06, size.z * 0.8, Vector3(-size.x * 0.28, size.y * 0.88, 0.0), steel, "z")
	_cyl(p, 0.06, 0.06, size.x * 0.5, Vector3(0.0, size.y * 0.88, 0.0), steel, "x")
	# dosing pump + motor on the skid
	_box(p, Vector3(size.x * 0.18, size.y * 0.22, size.z * 0.2), Vector3(size.x * 0.08, size.y * 0.24, -size.z * 0.32), steel)
	_motor_unit(p, size.y * 0.1, size.x * 0.2, Vector3(size.x * 0.08, size.y * 0.5, -size.z * 0.32), "x", ghost)

## Prints the origin name + unique code + a barcode (derived from the code) onto
## a placed bale's yellow label. Called once the bale's unique code is known.
static func add_bale_label(body: Node3D, id: String, code: String) -> void:
	var item := get_item(id)
	if item.is_empty():
		return
	var size: Vector3 = item["size"]
	var nm := String(BaleDefs.get_origin(id).get("name", id)).to_upper()
	var lx := size.x * 0.18
	var ly := size.y * 0.62
	var lz := size.z * 0.5 + 0.006

	# Printed text: origin + unique code (small enough to fit an 11×8 cm sticker).
	var lbl := Label3D.new()
	lbl.name = "BaleLabel"
	lbl.text = "%s\n%s" % [nm, code]
	lbl.font_size = 64
	lbl.pixel_size = 0.00019
	lbl.modulate = Color(0.05, 0.05, 0.05)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector3(lx, ly + 0.014, lz)
	body.add_child(lbl)

	# Barcode: stripe widths derived from the code's characters (unique per bale).
	var blk := _mat(Color(0.04, 0.04, 0.04), false, 0.0, 0.7)
	var x := lx - 0.045
	for i in code.length():
		var ch := code.unicode_at(i)
		var w := 0.0012 + float(ch % 4) * 0.0009
		_box(body, Vector3(w, 0.018, 0.002), Vector3(x + w * 0.5, ly - 0.022, lz), blk)
		x += w + 0.0018

# =============================================================================
# SURFACE / OPENING BUILDERS  (used by the 4-point surface tool + door convert)
# =============================================================================
## Interactive roller door. Box leaf is CENTRED on the node origin (so the
## caller positions by centre, not base). Carries Door.gd, group "placed_object"
## and meta "placeable_id" = "surface", so it persists and can be deleted.
static func build_door(width: float, height: float, thickness: float, label: String) -> StaticBody3D:
	var door: StaticBody3D = load("res://src/build/Door.gd").new()
	door.name = "Door" if label.is_empty() else label
	# Door.gd no longer needs `open_height` (it swings on a hinge now, not
	# slides up). Keep the height arg so callers don't have to be updated, we
	# just don't pass it into the door.
	door.set_meta("placeable_id", "surface")
	door.add_to_group("placed_object")

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(width, height, thickness)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.40, 0.25)
	mat.roughness = 0.7
	mat.metallic = 0.15
	mesh.material_override = mat
	door.add_child(mesh)

	var col := CollisionShape3D.new()
	col.name = "Col"
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, thickness)
	col.shape = shape
	door.add_child(col)
	return door

## Flat surface panel (window / sign / poster / plain). Centred on origin.
##   transparent → translucent glass-like; solid_collision → blocks the player.
static func build_panel(width: float, height: float, thickness: float, \
		col_rgba: Color, label: String, transparent: bool, solid_collision: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Panel" if label.is_empty() else label
	body.set_meta("placeable_id", "surface")
	body.add_to_group("placed_object")

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, thickness)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col_rgba
	mat.roughness = 0.2 if transparent else 0.6
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.metallic = 0.0
	mesh.material_override = mat
	body.add_child(mesh)

	# Always give a collider so the object is ray-pickable (for [X] delete). A
	# non-solid panel (a sign/poster) sits on collision layer 2 with no mask, so
	# the player walks through it while the build raycast can still hit it.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, thickness)
	col.shape = shape
	body.add_child(col)
	if not solid_collision:
		body.collision_layer = 2
		body.collision_mask = 0
	return body

## A simple welded-steel support frame: four corner legs + a top perimeter rail,
## spanning DOWN from the object's base (local origin) by `height` metres so a
## raised machine looks properly supported. Origin matches the object's base.
static func build_support_frame(footprint: Vector3, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Support"
	var beam := 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.34)
	mat.metallic = 0.7
	mat.roughness = 0.4

	var hx := maxf(footprint.x * 0.5 - beam * 0.5, 0.05)
	var hz := maxf(footprint.z * 0.5 - beam * 0.5, 0.05)

	# Four vertical legs (centre at y = -height/2, so they reach base → ground).
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(beam, height, beam)
			leg.mesh = lm
			leg.material_override = mat
			leg.position = Vector3(sx * hx, -height * 0.5, sz * hz)
			root.add_child(leg)

	# Top perimeter rails, just under the base (y ≈ -beam/2).
	var rail_y := -beam * 0.5
	_add_rail(root, mat, Vector3(footprint.x, beam, beam), Vector3(0.0, rail_y,  hz))
	_add_rail(root, mat, Vector3(footprint.x, beam, beam), Vector3(0.0, rail_y, -hz))
	_add_rail(root, mat, Vector3(beam, beam, footprint.z), Vector3( hx, rail_y, 0.0))
	_add_rail(root, mat, Vector3(beam, beam, footprint.z), Vector3(-hx, rail_y, 0.0))
	return root

static func _add_rail(root: Node3D, mat: StandardMaterial3D, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
