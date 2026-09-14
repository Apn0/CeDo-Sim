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

# Floating billboard nameplate over each placed machine. Real plants have no
# text floating over the machines, so this is OFF everywhere (operator decision
# 2026-07-11: what passes in the test gauntlet IS the main-world behaviour —
# no double bookkeeping). Kept as a flag so a debug tool can flip it on for a
# session; nothing in the shipped flow sets it true.
static var emit_name_labels : bool = false

# ── #212 Stencil-label helper ─────────────────────────────────────────────────
# Small white stencilled text decal used by brand-decal additions across this
# file (EREMA / WAVE-CUT / LINDNER POLARIS / PRESONA / WILO / TANK A …). Built
# as a Label3D parented under a tiny QuadMesh stand-in so it reads as a flat
# panel on the host machine face. `face` selects which axis the decal looks
# down ("+Z" default, "-Z", "+X", "-X"). `size` is the requested decal panel
# size (m); the Label3D font + pixel_size are auto-fit to roughly fill it.
static func _stencil_label(parent : Node3D, text : String, size : Vector3,
		face : String = "+Z") -> Node3D:
	var root := Node3D.new()
	root.name = "StencilLabel"
	parent.add_child(root)
	# Background quad — small panel the text sits on top of. Slight white tint
	# (paint stencil look) on the host's face. The panel is mostly there so the
	# decal is visible even when ghost-mat'd or seen at glancing angles.
	var qm := QuadMesh.new()
	qm.size = Vector2(maxf(size.x, 0.02), maxf(size.y, 0.02))
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var bg := StandardMaterial3D.new()
	bg.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	bg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.metallic = 0.0
	bg.roughness = 0.9
	mi.material_override = bg
	root.add_child(mi)
	# Label3D centred on the quad, slightly proud (so it z-fights nothing).
	var lbl := Label3D.new()
	lbl.text = text
	lbl.modulate = Color(1.0, 1.0, 1.0)
	lbl.outline_modulate = Color(0.0, 0.0, 0.0)
	lbl.outline_size = 4
	# pixel_size scales font→m. Aim so the text spans ~80 % of the smaller side.
	var min_side : float = minf(size.x, size.y)
	lbl.pixel_size = max(0.0008, min_side / 70.0)
	lbl.font_size = 48
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.double_sided = true
	lbl.no_depth_test = false
	lbl.position = Vector3(0.0, 0.0, 0.001)
	root.add_child(lbl)
	# Orient root so the +Z normal of the quad faces the requested face.
	match face:
		"+Z": root.rotation = Vector3.ZERO
		"-Z": root.rotation = Vector3(0.0, PI, 0.0)
		"+X": root.rotation = Vector3(0.0, PI * 0.5, 0.0)
		"-X": root.rotation = Vector3(0.0, -PI * 0.5, 0.0)
		_:    root.rotation = Vector3.ZERO
	return root

static func items() -> Array[Dictionary]:
	if _items.is_empty():
		_items = [
			# ── Structure ────────────────────────────────────────────────────
			# Note: the legacy single-click box "door" catalog entry was removed. The
			# real interactive door (hinged, carves a hole, "press E") is built via the
			# Surface tool (▣ button) — pick Door, Gate, or Window. Old saves with the
			# box-door id are auto-upgraded by _load_legacy_door() on load.
			# E-kast / PCU — the off-white 3-bay painted steel cabinet at the line head:
			# HMI screen, indicator-light bank, gauges, big rotary selector, CAUTION
			# placard. Modelled from the real CeDo cabinet photo.
			{"id": "pcu_cabinet",    "name": "E-kast (PCU control cabinet)", "category": "Structure", "size": Vector3(2.5, 2.0, 0.7), "color": Color(0.86, 0.84, 0.79)},
			{"id": "silo",           "name": "Silo",               "category": "Structure",  "size": Vector3(3.0, 6.0, 3.0),  "color": Color(0.62, 0.63, 0.66)},
			# #116 — door / gate / window placeables that DON'T require the 4-point
			# Surface tool. Use these to drop furniture into a pre-carved hole
			# (e.g. one baked by tools/solidify_building.py from captured_doors.json,
			# or an F11 capture). Same underlying builders as the Surface variants,
			# so they share interaction + collision + appearance. Size = nominal
			# dimensions for a standard industrial opening; jog/edit (K) to resize.
			{"id": "door_personnel", "name": "Personnel door (hinged)",  "category": "Structure", "size": Vector3(0.92, 2.10, 0.10), "color": Color(0.55, 0.40, 0.25)},
			{"id": "gate_roller",    "name": "Roller gate (industrial)", "category": "Structure", "size": Vector3(3.50, 3.60, 0.20), "color": Color(0.14, 0.22, 0.40)},
			{"id": "window_frame",   "name": "Window (alu frame + glass)","category": "Structure", "size": Vector3(1.40, 1.20, 0.08), "color": Color(0.72, 0.74, 0.78)},
			# Elevated extruder feed silo: a light-grey box raised on a steel frame (~2.5 m
			# clearance for the extruder + lump bin beneath), a yellow guardrail platform on
			# top, 4 inspection windows in 2 column-pairs on the front, and TWO cyclones
			# (one over each window pair) discharging down into it. size = W × total H × D.
			# Photo-calibrated from assets/reference_photos/machines/_extruder_silo.png:
			# the real elevated silo is painted in a warm cream-grey, not the cool
			# off-white that was placeholder (0.78, 0.79, 0.80).
			# Operator pass: previous footprint was 2× too wide (X) and 1.5× too long
		# (Z); height stays at 6.5 m. New size 1.80 × 6.50 × 2.13 m matches the
		# reference photo proportions (the silo is a TALL, slim box on stilts,
		# not the squat block the prior dimensions implied).
		{"id": "extruder_silo",  "name": "Extruder feed silo (elevated, 2 cyclones)", "category": "Structure", "size": Vector3(1.80, 6.5, 2.13), "color": Color(0.80, 0.77, 0.71)},
		{"id": "doseersilo",     "name": "Doseer Silo",        "category": "Structure",  "size": Vector3(3.6, 2.6, 5.5),  "color": Color(0.66, 0.67, 0.70)},
			# ── Whole-line macros ────────────────────────────────────────────
			# Placing one lays the ENTIRE line front-to-back from the click point,
			# each machine an individually-joggable placed_object (K edit mode).
			#
			# Plant 3A/3B work-flow ordering (operator-confirmed, this is the order
			# you walk the floor when stepping a bale through the plant):
			#   1.  ▶ Build Sort line                 — sorteerlijn (head end)
			#   2.  ▶ Build Transportbanden 3A/3B     — was "intake"; the dry conveyor
			#                                           network that lifts sorted bale
			#                                           material from the trilzeefs up
			#                                           through belts C1..C12 to the
			#                                           VSS metering silos
			#   3a. ▶ Build Line 3A (full)            — split wash + extrude path A
			#   3b. ▶ Build Line 3B (full)            — split wash + extrude path B
			# Line 1 has its own front-end (no shared sort/transport), so it lists
			# first as its own self-contained macro. Lines 3C and 6 share their
			# own intake macro and follow the same step pattern at the tail.
			{"id": "line_1",         "name": "▶ Build Line 1 (full)","category": "Lines",    "size": Vector3(3.0, 2.0, 3.0),  "color": Color(0.30, 0.48, 0.80)},
			{"id": "line_3a",        "name": "▶ Build Line 3A wash + extrude (step 3a)","category": "Lines",   "size": Vector3(3.0, 2.0, 3.0),  "color": Color(0.30, 0.55, 0.85)},
			{"id": "line_3b",        "name": "▶ Build Line 3B wash + extrude (step 3b)","category": "Lines",   "size": Vector3(3.0, 2.0, 3.0),  "color": Color(0.30, 0.62, 0.78)},
			# Step 1 — Sort line (sorteerlijn): opzetband + 2× trilzeef. Feeds the
			# Transportbanden network below.
			{"id": "line_sort",      "name": "▶ Build Sort line — sorteerlijn (step 1)","category": "Lines", "size": Vector3(3.0, 2.0, 3.0),  "color": Color(0.12, 0.18, 0.34)},
			# Step 2 — Transportbanden 3A/3B (was "intake"; renamed to match the
			# operator's term for the dry conveyor network). Lays the Shredder-2
			# climb, the 12 transportbanden, the switch belt diverter, the VSS
			# metering silo, and the U-bay overflow surge bay. Material flows
			# through it INTO vuilsnippersilo (head of LINE_3A_SEQ / LINE_3B_SEQ).
			# `id` kept as `line_intake_3a3b` for save-file compat — only the
			# display label changes.
			{"id": "line_intake_3a3b","name":"▶ Build Transportbanden 3A/3B (step 2)","category": "Lines", "size": Vector3(3.0, 2.0, 3.0), "color": Color(0.55, 0.30, 0.10)},
			# Lines 3C + 6 share their own front-end (opzetband_3c6 + shredder + climb + trilzeef).
			# Step 1 + step 2 are bundled here because the 3C/6 line group has its
			# own sort + transport rather than sharing the 3A/3B pair.
			{"id": "line_intake_3c6","name":"▶ Build 3C/6 sort + transport (step 1+2)","category": "Lines", "size": Vector3(3.0, 2.0, 3.0), "color": Color(0.32, 0.46, 0.56)},
			# Step 3c — the Line 3C wash + extrude spine itself (BuildMode.LINE_3C_SEQ,
			# transcribed from Line3CDef.STAGES). This is the ONLY macro whose machines
			# carry an l3c_code, so it is the only one the calibrated ProcessModel
			# currents / transfer coefficients and the Waslijn 3C HMI screen can read.
			# LAYOUT-APPROXIMATE — see the SEQ header; needs an operator K-mode pass.
			{"id": "line_3c",        "name": "▶ Build Line 3C wash + extrude (step 3c)","category": "Lines", "size": Vector3(3.0, 2.0, 3.0), "color": Color(0.30, 0.68, 0.72)},
			# ── Extruders ────────────────────────────────────────────────────
			{"id": "extruder_3a",    "name": "Extruder 3A",        "category": "Extruders",  "size": Vector3(2.6, 4.2, 14.0), "color": Color(0.26, 0.42, 0.70)},
			{"id": "extruder_3b",    "name": "Extruder 3B",        "category": "Extruders",  "size": Vector3(2.6, 4.2, 14.0), "color": Color(0.26, 0.50, 0.70)},
			{"id": "extruder_1",     "name": "Extruder 1",         "category": "Extruders",  "size": Vector3(2.6, 4.2, 14.0), "color": Color(0.26, 0.58, 0.70)},
			{"id": "extruder_3c",    "name": "Extruder 3C",        "category": "Extruders",  "size": Vector3(2.6, 4.2, 14.0), "color": Color(0.26, 0.64, 0.68)},
			{"id": "extruder_6",     "name": "Extruder 6",         "category": "Extruders",  "size": Vector3(2.6, 4.2, 14.0), "color": Color(0.26, 0.70, 0.64)},
			# Extruder train (Line 3C tail): Plasmaq dewater press, laser melt
			# filter, melt pump → pellets.
			{"id": "plasmaq",        "name": "Plasmaq (dewater press)","category": "Extruders","size": Vector3(1.6, 2.0, 3.2), "color": Color(0.40, 0.46, 0.52)},
			{"id": "laser_filter",   "name": "Laserfilter",        "category": "Extruders",  "size": Vector3(1.4, 1.6, 2.0),  "color": Color(0.34, 0.38, 0.46)},
			{"id": "melt_pump",      "name": "Meltpump",           "category": "Extruders",  "size": Vector3(1.0, 1.2, 1.2),  "color": Color(0.42, 0.40, 0.44)},
			# ── Shredders ────────────────────────────────────────────────────
			# REMOVED: shredder_3a3b + shredder_1_3c6 were the old generic 3x2.5x3
			# blobs (built via the fallback _m_shredder). Both are superseded by
			# the bespoke shredder_1 / shredder_2 models from #50 (4x9x5 + rotor/
			# stators + discharge conveyor). Catalog now has ONE shredder per
			# actual machine, not duplicate old/new pairs.
			# Per-position shredders the line actually has — Shredder 1 is the
			# big coarse pre-shredder (≤10×10 cm output), Shredder 2 is a smaller
			# compact unit that takes it down to ~1-2 cm flakes.
			{"id": "shredder_1",     "name": "Shredder 1 (coarse — Line 1 + 3C/6, big red)","category": "Shredders","size": Vector3(4.0, 9.0, 5.0),  "color": Color(0.62, 0.14, 0.11)},
			{"id": "shredder_2",     "name": "Shredder 2 (fine)",  "category": "Shredders",  "size": Vector3(3.4, 6.0, 4.2),  "color": Color(0.18, 0.30, 0.58)},
			# ── Washing / drying ─────────────────────────────────────────────
			{"id": "mech_dryer",     "name": "Mechanical dryer",   "category": "Washing",    "size": Vector3(2.4, 3.0, 4.5),  "color": Color(0.62, 0.63, 0.65)},
			# REMOVED: wash_line was the old monolithic Washing-line placeable
			# (8m long generic box). Replaced by the actual chain — friction_washer
			# / friction_sep / flotation_tank / dewater_screw / mech_dryer — laid
			# by LINE_3A_SEQ + LINE_3B_SEQ + LINE_1_SEQ. The catalog no longer
			# offers the old monolith.
			{"id": "centrifuge",     "name": "Centrifuge",         "category": "Washing",    "size": Vector3(2.0, 2.4, 2.0),  "color": Color(0.45, 0.50, 0.58)},
			# LEGACY MODEL — placed by no macro since ruling 3.1-B. The real
			# thermische droger (operator 2026-08-28, ruling 3.1-C) is a flat
			# SPIRAL CABINET: ~2×2 m from the front, 30-35 cm thick, material
			# enters mid-face, runs 4-5 spiral loops inward→outward, exits at
			# the side; heater elements sit in the REMOVABLE SIDE PANELS. See
			# thermal_dryer_decommissioned below for that geometry; this old
			# 2.6×4.5×3.0 block model is superseded and kept only for saves.
			{"id": "thermal_dryer",  "name": "Thermal dryer (thermische droger)","category": "Washing","size": Vector3(2.6, 4.5, 3.0),"color": Color(0.60, 0.60, 0.64)},
			# Ruling 3.1-C (operator 2026-08-28): 3B's thermische droger was
			# REPLACED by the plasmaq during his tenure, but the machine still
			# physically STANDS there, disconnected — "a pipe of like twenty
			# centimeters that sticks out. And then there's nothing." Built to
			# the real spiral-cabinet spec above. Role "none": plant
			# archaeology, not a flow machine.
			{"id": "thermal_dryer_decommissioned", "name": "Thermische droger (buiten gebruik, 3B)","category": "Washing","size": Vector3(2.2, 2.3, 0.7),"color": Color(0.58, 0.58, 0.60)},
			# ── Conveyance ───────────────────────────────────────────────────
			{"id": "transport_belt", "name": "Transport belt",     "category": "Conveyance", "size": Vector3(1.0, 0.9, 4.0),  "color": Color(0.34, 0.34, 0.38)},
			# Two-point variable-length / variable-angle conveyor. Click ONCE to set the
			# START point + start height (R/F adjust), then click AGAIN for the END point
			# + end height. Belt spans between the two with the correct angle + length.
			# size here is the rough footprint for the first-click ghost only.
			{"id": "variable_belt",  "name": "Conveyor (variable, 2-click)", "category": "Conveyance", "size": Vector3(1.0, 0.40, 1.0), "color": Color(0.34, 0.34, 0.38)},
			# Support poles for variable belts (or anything else that needs holding up).
			# Each is built at the size.y the catalog entry quotes (the default standing
			# height); SMART SNAP in BuildMode auto-scales the ghost so the top of the
			# pole sits exactly at whatever belt deck the crosshair is on, and rebuilds
			# at that custom height when placed.
			{"id": "pole_single",    "name": "Support pole (1 leg)",         "category": "Conveyance", "size": Vector3(0.30, 2.00, 0.30), "color": Color(0.55, 0.57, 0.61)},
			{"id": "pole_double",    "name": "Support pole (2 legs)",        "category": "Conveyance", "size": Vector3(0.70, 2.00, 0.30), "color": Color(0.55, 0.57, 0.61)},
			{"id": "pole_a_frame",   "name": "Support pole (A-frame)",       "category": "Conveyance", "size": Vector3(0.80, 2.00, 0.40), "color": Color(0.55, 0.57, 0.61)},
			# ── Platforms (steel-grating mezzanine kit) ──────────────────────────
			# Grating platform is a TWO-CLICK resizable deck (drag width × length) —
			# special-cased by BuildMode like variable_belt, so it is NOT routed in
			# build_node()'s match. Its support posts are tagged "machine_leg" so the
			# existing extend_machine_legs() runs them to the floor + hides blocked ones.
			{"id": "grating_platform", "name": "Grating platform (2-click, resizable)", "category": "Platforms", "size": Vector3(2.0, 0.25, 2.0), "color": Color(0.55, 0.57, 0.60)},
			{"id": "stairs",         "name": "Stairs (grating, guardrail)", "category": "Platforms", "size": Vector3(1.2, 2.5, 3.0),  "color": Color(0.55, 0.57, 0.60)},
			{"id": "guardrail",      "name": "Guardrail segment",           "category": "Platforms", "size": Vector3(0.06, 1.1, 2.0),  "color": Color(0.80, 0.72, 0.20)},
			# #225.2 — Low steel-grating BORDES the laserfilter + its two lump carts
			# stand on, with an oprit (ramp) on the -Z approach side so a forklift
			# rolls up to fork a cart out. Operator 2026-07-14 + photo _lumbs_cart.jpg.
			{"id": "lump_platform",  "name": "Laserfilter afvoer-bordes (met oprit)", "category": "Platforms", "size": Vector3(3.8, 0.12, 2.4), "color": Color(0.50, 0.52, 0.55)},
			# ── Walls (2-click: click START, click END → solid wall along the line) ──
			# size.x = thickness, size.y = height (metres). All three are two-click.
			{"id": "wall_low",  "name": "Wall — partition (3.5m, 2-click)",  "category": "Walls", "size": Vector3(0.20, 3.5,  1.0), "color": Color(0.82, 0.80, 0.76)},
			{"id": "wall_tall", "name": "Wall — hall (6m, 2-click)",         "category": "Walls", "size": Vector3(0.25, 6.0,  1.0), "color": Color(0.82, 0.80, 0.76)},
			{"id": "wall_full", "name": "Wall — full height (12m, 2-click)", "category": "Walls", "size": Vector3(0.30, 12.0, 1.0), "color": Color(0.82, 0.80, 0.76)},
			# ── Opzetbanden (intake/feed belts to a shredder) ────────────────────
			# Geometry is built procedurally by _build_opzetband from the id. The size
			# here is the rough bounding box (W × H × L) for the build-mode footprint.
			{"id": "opzetband_3a3b", "name": "Opzetband 3A/3B (8m flat + 10m@25° + 1m top)", "category": "Conveyance", "size": Vector3(2.0, 4.93, 18.06), "color": Color(0.20, 0.40, 0.80)},
			{"id": "opzetband_3c6",  "name": "Opzetband 3C/6 (4m flat + 8m@35°)",            "category": "Conveyance", "size": Vector3(2.5, 5.4, 10.6), "color": Color(0.20, 0.40, 0.80)},
			# westa_band_1 size re-derived 2026-08-28 (#fold). The belt's rise
			# is DERIVED in _build_opzetband from the chute/funnel port
			# helpers (lip ≈ 5.22 → run 4.52, extent 4.52+0.6 = 5.12 m of
			# one-sided geometry from the origin). y: lip + guide rails ≈ 5.6.
			# z: geometry-honest wrap (5.12 + margin). The chute is lined up
			# under the lip via LINE_1_SEQ's westa gap (derivation there), NOT
			# via this box — guarded live by test_line1_flow_conformance S4b.
			{"id": "westa_band_1",   "name": "Westa band 1 (45° feeder to SGA hoekgoot)", "category": "Conveyance", "size": Vector3(1.6, 5.6, 5.8),  "color": Color(0.20, 0.40, 0.80)},
			{"id": "opzetband_1",    "name": "Opzetband 1 (10m@25°, 4m wide, integrated magnet head)", "category": "Conveyance", "size": Vector3(4.0, 5.0, 10.0),  "color": Color(0.20, 0.40, 0.80)},
			# Inclined belt — climbs 8 m vertically over 8 m horizontal (45°).
			# Goes from Shredder 2's output up to the feed hopper at the top.
			{"id": "inclined_belt_8m","name":"Inclined belt (45°, 8 m rise)","category":"Conveyance","size": Vector3(1.0, 8.5, 8.5),  "color": Color(0.34, 0.34, 0.38)},
			# ── 3A/3B intake conveyor chain (#54) ────────────────────────────────
			# Twelve numbered belts ferry flake from the Shredder-2 climb output down
			# to the switch belt. Each one visually distinct (length, height, incline,
			# colour). All routed via build_intake_belt(spec) where the spec dict
			# encodes length/height/incline/colour. Macro-laid by BuildMode's
			# INTAKE_3A3B_SEQ so the user doesn't have to place 12 manually.
			{"id": "transportband_1",  "name": "Transportband 1 (incline 5°, shredder dump, 5m)",   "category": "Transportbanden-3A3B", "size": Vector3(1.0, 0.95, 5.0),  "color": Color(0.36, 0.38, 0.42)},
			{"id": "transportband_2",  "name": "Transportband 2 (incline 5°, transfer, 6m)",         "category": "Transportbanden-3A3B", "size": Vector3(1.0, 0.95, 6.0),  "color": Color(0.40, 0.40, 0.44)},
			{"id": "transportband_3",  "name": "Transportband 3 (incline 10°, 8m)",                  "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.30, 8.0),  "color": Color(0.32, 0.34, 0.38)},
			{"id": "transportband_4",  "name": "Transportband 4 (incline 8°, 10m, blue trim)",       "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.10, 10.0), "color": Color(0.22, 0.36, 0.62)},
			{"id": "transportband_5",  "name": "Transportband 5 (incline 15°, 8m)",                  "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.50, 8.0),  "color": Color(0.34, 0.34, 0.38)},
			{"id": "transportband_6",  "name": "Transportband 6 (incline 6°, cross-routing, 7m)",    "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.10, 7.0),  "color": Color(0.42, 0.42, 0.46)},
			{"id": "transportband_7",  "name": "Transportband 7 (incline 5°, 8m, yellow rail)",      "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.15, 8.0),  "color": Color(0.60, 0.55, 0.20)},
			{"id": "transportband_8",  "name": "Transportband 8 (bi-directional, 9m)",               "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.40, 9.0),  "color": Color(0.32, 0.34, 0.36)},
			# #136 — C8.5 is the overflow-bypass belt. Sits BELOW + BESIDE C8 and only
			# carries material when C8 reverses (both VSSs FULL → C8 ramps the other
			# way and discharges down onto 8.5, which feeds the U-bay/stortvak).
			{"id": "transportband_8_5","name": "Transportband 8.5 (overflow → U-bay, 6m)",          "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.10, 6.0),  "color": Color(0.52, 0.36, 0.18)},
			{"id": "transportband_9",  "name": "Transportband 9 (incline 4°, 12m)",                  "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.10, 12.0), "color": Color(0.38, 0.38, 0.42)},
			{"id": "transportband_10", "name": "Transportband 10 (incline 5°, 8m, green trim)",      "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.10, 8.0),  "color": Color(0.22, 0.50, 0.30)},
			{"id": "transportband_11", "name": "Transportband 11 (incline 12°, 7m)",                 "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.40, 7.0),  "color": Color(0.34, 0.34, 0.38)},
			# #136 — switch_belt IS conveyor 12. Catalog keeps both ids so legacy
			# saves still resolve, but the macro uses switch_belt only (transportband_12
			# is the same belt without the jog mechanism). Switch belt jogs along its
			# OWN conveying axis (-1.5m..+1.5m), feeding 100% to VSS_3A at left,
			# 100% to VSS_3B at right, ~50/50 at centre.
			{"id": "transportband_12", "name": "Transportband 12 (= switch_belt, legacy id)",  "category": "Transportbanden-3A3B", "size": Vector3(1.0, 1.15, 3.0),  "color": Color(0.46, 0.46, 0.50)},
			{"id": "switch_belt",    "name": "Switch belt (= C12; jogs ±1.5m → VSS_3A / VSS_3B)",  "category": "Transportbanden-3A3B", "size": Vector3(2.4, 1.40, 4.0),  "color": Color(0.55, 0.30, 0.10)},
			# VSS metering silo — primary intake buffer for the wash line.
			{"id": "vss_silo",       "name": "VSS intake silo (primary buffer)",          "category": "Transportbanden-3A3B", "size": Vector3(3.0, 6.0, 3.0),   "color": Color(0.78, 0.78, 0.82)},
			# U-bay — concrete overflow surge bay (Merlo scoops out of it).
			{"id": "u_bay",          "name": "U-bay / stortvak (overflow surge, Merlo-scoop)",       "category": "Transportbanden-3A3B", "size": Vector3(8.0, 6.25, 8.0),   "color": Color(0.62, 0.60, 0.56)},
			# Small feed hopper with 20 cm flanges — sits at the top of the
			# inclined belt and dribbles material onto the next horizontal belt.
			{"id": "feed_hopper",    "name": "Feed hopper (small)","category": "Conveyance", "size": Vector3(1.0, 1.2, 1.0),  "color": Color(0.50, 0.50, 0.55)},
			{"id": "cyclone",        "name": "Cyclone",            "category": "Conveyance", "size": Vector3(1.6, 3.0, 1.6),  "color": Color(0.58, 0.58, 0.62)},
			# #79 — tall cyclone mounted on a braced support tower so its discharge
			# spout sits HIGH enough to gravity-drop into a silo top (mengsilo of the
			# 3A recirc loop, or any standalone silo). The chain `cyclone` above stays
			# short for in-line placements; this variant is for cyclone→silo gravity
			# transitions. Frame legs reach the floor via extend_machine_legs().
			{"id": "cyclone_tower",  "name": "Cyclone on tower (gravity drop)", "category": "Conveyance", "size": Vector3(2.4, 8.0, 2.4), "color": Color(0.58, 0.58, 0.62)},
			{"id": "ringleiding",    "name": "Ringleiding (pneumatic ring main)","category": "Conveyance","size": Vector3(3.2, 3.0, 3.2),"color": Color(0.60, 0.62, 0.66)},
			# The 3A rondmeng RING — operator-identified 2026-08-28 ("it's the
			# ring") from assets/reference_photos/machines/_ringleiding_1..4:
			# a caged SERPENTINE, not the generic ring main above. Three
			# stacked ~Ø440 cream pipe runs with 180° U-bends at alternating
			# ends ("starts at the bottom … 180° turn … up a little … another
			# 180 … two loops"), clamp collars, grey cage with yellow-trimmed
			# posts + wire mesh, gauge on the top bend, vendor placard
			# "GLOBAL SPIRAL CHUTES MOD. 260". Heated air per ruling 2.1-B.
			{"id": "ringleiding_3a", "name": "Ringleiding 3A (Global Spiral Chutes MOD. 260)","category": "Conveyance","size": Vector3(1.6, 2.8, 5.0),"color": Color(0.86, 0.84, 0.78)},
			# Inter-machine transfer connectors — drop one between a machine's outlet
			# and the next machine's inlet, then jog it into place (K edit mode).
			{"id": "funnel",         "name": "Metal funnel",       "category": "Conveyance", "size": Vector3(1.2, 1.0, 1.2),  "color": Color(0.60, 0.62, 0.66)},
			{"id": "transfer_chute", "name": "Transfer chute",     "category": "Conveyance", "size": Vector3(0.8, 1.4, 1.8),  "color": Color(0.55, 0.57, 0.60)},
			{"id": "blower",         "name": "Ventilator / blower","category": "Conveyance", "size": Vector3(1.0, 1.2, 1.2),  "color": Color(0.50, 0.46, 0.40)},
			# ── Sorting (bunkers / scanners / pre-wash drum etc) ─────────────
			# Bunker REBUILT 2026-07-06 (bunker.md + operator rulings): NOT an
			# intake pit — a ~10 m long × 4 m wide BUFFER CONVEYOR downstream of
			# Shredder 1 (operator interview: shredder 1 bottom → belt → bunker →
			# belt 1040; SWI-035 front-end order). Deck ~1.25 m up (placeholder,
			# documented band 1.0-1.5 m — flag F1), walls ~3.75 m above it
			# (band 3.5-4.0 m — flag F1). Id KEPT for save-file compat (every
			# matcher substring-matches "bunker": HmiScopes/HmiOverlay/CrewManager/
			# LineFlow). Colour undocumented — flag F14.
			{"id": "bunker",         "name": "Bunker (buffer conveyor, lijn 3)", "category": "Sorting", "size": Vector3(4.0, 5.0, 10.0), "color": Color(0.55, 0.55, 0.58)},
			# ── Size reduction ───────────────────────────────────────────────
			# Mill = the fine-stage size reducer on lines 3C / 6. Lives in the
		# "Shredders" category alongside Shredder 1 / Shredder 2 so the build
		# menu groups all size-reducers together; the parenthesised role +
		# line tags match the Shredder 1 (coarse; 3A/3B) / Shredder 2 (fine;
		# 3A/3B) naming pattern. "Granulator" is the same machine class as a
		# fine mill on these lines; the previous standalone "Size reduction"
		# category + "Mill (granulator)" name confused the operator about
		# whether mill and shredder are different things. They aren't.
		{"id": "mill",           "name": "Mill (fine; 3C, 6)", "category": "Shredders",     "size": Vector3(3.6, 4.8, 4.6), "color": Color(0.60, 0.36, 0.32)},
			# ── Separation ───────────────────────────────────────────────────
			# Photo-calibrated from assets/reference_photos/machines/flotatietank_3A.png
			# and flotatietank_3B_*.png: the real tank is weathered dirty stainless
			# with heavy rust streaking, NOT the blue-grey the placeholder showed.
			{"id": "flotation_tank", "name": "Flotation tank (1.5x, Line 1/3A/3B)", "category": "Separation", "size": Vector3(4.5, 5.0, 9.0),  "color": Color(0.50, 0.48, 0.45)},
			{"id": "flotation_tank_wide", "name": "Flotation tank (wide 2x, Line 3C/6)", "category": "Separation", "size": Vector3(6.0, 5.0, 9.0),  "color": Color(0.32, 0.46, 0.56)},
			{"id": "sink_float",     "name": "Bezinkafscheider",   "category": "Separation","size": Vector3(2.6, 2.0, 4.0),"color": Color(0.34, 0.46, 0.50)},
			{"id": "friction_sep",   "name": "Friction separator", "category": "Separation", "size": Vector3(1.8, 2.0, 4.5),  "color": Color(0.52, 0.54, 0.58)},
			{"id": "dewater_screw",  "name": "Dewatering screw",   "category": "Separation", "size": Vector3(1.2, 2.6, 4.5),  "color": Color(0.56, 0.58, 0.62)},
			{"id": "overband_magnet","name": "Overband magnet",    "category": "Separation", "size": Vector3(1.6, 1.8, 3.0),  "color": Color(0.30, 0.32, 0.38)},
			{"id": "scraper_conveyor","name":"Coarse scraper conveyor","category": "Separation","size": Vector3(1.4, 2.6, 6.0), "color": Color(0.46, 0.50, 0.54)},
			{"id": "verdeelwals",    "name": "Verdeelwals (distribution roller)","category": "Separation","size": Vector3(2.0, 1.8, 1.4),"color": Color(0.55, 0.55, 0.58)},
			# Operator 2026-08-28 (line-1 HPS/SGA walk): the goot after the SGA drum is
			# NOT a straight gutter — it is a Y-splitter carrying material+water:
			# ~1 m at 30° down, then the split, then ~1 m at 60° down with the legs
			# yawed ~35° left and ~35° right, then both legs turn back straight (in
			# line with the drum axis) and keep feeding into the next machine.
			# Height raised 1.4 → 2.0 to fit the operator's real 1.37 m of total drop
			# (30° leg 0.50 m + 60° leg 0.87 m); footprint X/Z unchanged.
			{"id": "scheidingsgoot", "name": "Scheidingsgoot (Y-splitgoot, na SGA-trommel)","category": "Separation","size": Vector3(1.6, 2.0, 3.0),"color": Color(0.55, 0.57, 0.60)},
			# Operator 2026-08-28: between band 2 and the SGA drum sits a chute that
			# makes a 90° RIGHT turn off the conveyor and feeds the drum on its TOP
			# side. The flow diagrams draw blocks only, never chutes — this one is
			# operator-described, not doc-derived.
			{"id": "sga_feed_chute", "name": "SGA invoergoot (90° hoek, band → trommel)","category": "Separation","size": Vector3(1.8, 1.8, 1.8),"color": Color(0.55, 0.57, 0.60)},
			# ── Pumps ────────────────────────────────────────────────────────
			{"id": "water_pump",     "name": "Water pump",         "category": "Pumps",      "size": Vector3(0.8, 0.9, 1.3),  "color": Color(0.30, 0.45, 0.62)},
			# Small floor-mounted centrifugal pump (Wilo-style): teal-painted volute
			# + motor end-cap, grey finned motor, junction box, stainless base plate,
			# vertical stainless discharge stub. Modelled from the real CeDo photo.
			# REMOVED: waterpomp was the bespoke small Wilo-style pump model
			# (_m_waterpomp). No macro referenced it — Line 3A's Pomp C1 used
			# `water_pump` (generic _m_pump) until 2026-07-06.
			# ── Named pump stations (2026-07-06, water_small.md §3/§4) ────────
			# Distinct ids for pumps that carry their OWN names on the plant's
			# flow diagrams — the flotation_tank/_wide one-builder-many-ids
			# precedent, NOT a violation of the pump dedupe rule above (these are
			# distinct real-world stations, not model aliases; ruled in the
			# 2026-07-06 batch, water_small.md flag F10). Both reuse _m_pump with
			# a stencil station label; real pump size/appearance never
			# photographed — generic Wilo model is a stand-in (flags F7/F8).
			# Pomp C1 (3A only): glijgoot → C1 → frictiescheider M3; pumps the
			# dirty water + film ("vuil water en folie") — M3 training 101_CeDo14.
			{"id": "pomp_c1",       "name": "Pomp C1 (glijgoot → frictiescheider M3, 3A)", "category": "Pumps", "size": Vector3(0.8, 0.9, 1.3), "color": Color(0.30, 0.45, 0.62)},
			# Pomp zeefbocht (3B only): utility cluster near Blauwe tank / Pomp
			# was 3b / Pomp was 4. The ZEEFBOCHT screen it feeds is NOT drawn on
			# any diagram and is NOT modeled — flag F9, needs operator photo.
			{"id": "pomp_zeefbocht", "name": "Pomp zeefbocht (3B)",                        "category": "Pumps", "size": Vector3(0.8, 0.9, 1.3), "color": Color(0.30, 0.45, 0.62)},
			# Line-3A ring main: serpentine of off-white plastic pipes inside a yellow
			# steel safety cage (5 horizontal U-loops + vertical riser, stainless
			# band clamps at intervals). Modelled from the real CeDo photos.
			# REMOVED: ringleiding_3a was a Line-3A-specific ring main variant
			# (caged). The generic `ringleiding` (_m_ringleiding) already covers
			# this — LINE_3A_SEQ uses the generic id. Catalog now offers ONE
			# ringleiding id.
			# Compactor feed belt: heavy inclined conveyor (~28°) with black side panels,
			# yellow wire-mesh side guard, galvanized I-beam legs, stainless dust hood at
			# the discharge end, blue blower + duct routing dust up to the hood. From the
			# two CeDo photos (ground-level front-right + top rear-left).
			{"id": "compactor_belt", "name": "Compactor feed belt (inclined, dust-hooded)", "category": "Conveyance", "size": Vector3(8.0, 3.5, 2.4), "color": Color(0.10, 0.10, 0.11)},
			# REMOVED: pump_large was a generic-large alias that routed to the same
			# _m_pump builder as `water_pump`. Two ids, one model. Operator's
			# uniqueness rule — only `water_pump` remains for pumps.
			# ── Line 3B wash train ───────────────────────────────────────────
			{"id": "vuilsnippersilo","name": "Wet film silo (vuilsnipper)","category": "Size reduction","size": Vector3(3.0, 4.0, 3.0),"color": Color(0.50, 0.50, 0.55)},
			{"id": "friction_washer","name": "Frictiewasser (stirring tank)","category": "Washing","size": Vector3(1.5, 1.5, 3.0),  "color": Color(0.62, 0.64, 0.68)},
			{"id": "intensive_washer","name": "Intensive washer",  "category": "Washing",    "size": Vector3(1.6, 2.4, 2.0),  "color": Color(0.42, 0.55, 0.60)},
			# Rafter refined 2026-07-06 (eop_rafter.md Part B + operator ruling B7):
	# submerged mesh-cylinder sieve (~0.75 m ⌀) inside a ~1 m wide × 1 m high
	# water tank on a support platform. The tank has its OWN water level — it is
	# NOT a connected vessel with the flotation tank (operator-corrected 2026-07-17).
	# Platform top lowered 3.1 → 1.9 m (operator: top was 1.2 m too high).
	{"id": "rafter",         "name": "Rafter (submerged mesh-cylinder sieve, 3B)","category": "Separation", "size": Vector3(1.8, 4.8, 3.6),  "color": Color(0.55, 0.57, 0.60)},
			# #91 — Trilzeef (vibrating sieve / shaker screen): a steeply-sloped
			# perforated deck with vertical side barriers, a rubber inlet flap at
			# the top fed by a belt above, and an open-top discharge chute at the
			# bottom. Vibrating frame on coil-spring base. Splits incoming feed
			# into THROUGHS (small fines that fall through the holes) and OVERS
			# (oversize that slides down to the discharge).
			{"id": "trilzeef",       "name": "Trilzeef (vibrating sieve, 6-row)", "category": "Separation", "size": Vector3(1.8, 2.6, 4.2), "color": Color(0.12, 0.18, 0.34)},
			{"id": "transport_screw","name": "Transport screw",    "category": "Conveyance", "size": Vector3(1.0, 2.4, 4.5),  "color": Color(0.55, 0.57, 0.61)},
			# ── Extrusion prep ───────────────────────────────────────────────
			{"id": "mas_bak",        "name": "MAS trough",         "category": "Extrusion prep","size": Vector3(2.2, 1.8, 3.0),"color": Color(0.50, 0.52, 0.50)},
			# #106 — height bumped from 2.6 → 3.9 m to match real PCU footprint per
			# operator. Diameter kept (was reported correct); the +50% height makes
			# the drum read properly as a tall preconditioning unit, not a stubby
			# box. The "unwanted hopper" in the prior model was the conical funnel
			# overhead — removed in _m_compactor below.
			{"id": "compactor",      "name": "Compactor / PCU (preconditioning unit)",    "category": "Extrusion prep","size": Vector3(2.6, 3.9, 2.6),"color": Color(0.46, 0.46, 0.50)},
			{"id": "cutter_compactor","name": "Cutter-Compactor (agglomerator)",          "category": "Extrusion prep","size": Vector3(2.6, 4.2, 2.6),"color": Color(0.50, 0.46, 0.44)},
			# ── Sorting line (the dry front-end: bale opener → screens → NIR sort) ──
			# This is the section the SWIs call SORTEERLIJN. Bales are opened and
			# screened, ferrous tramp metal is magneted off, a ballistic deck splits
			# 2D film from 3D rigids, a windshifter blows out paper/dust, and the
			# TITECH/TOMRA NIR sorter positively sorts LDPE from off-spec polymer.
			{"id": "sga_drum",       "name": "SGA opener drum",    "category": "Sorting",    "size": Vector3(2.6, 2.8, 5.0),  "color": Color(0.50, 0.52, 0.56)},
			{"id": "metal_belt",     "name": "Overband metal sep.","category": "Sorting",    "size": Vector3(1.4, 1.8, 4.5),  "color": Color(0.40, 0.42, 0.48)},
			{"id": "ballistic_sep",  "name": "Ballistic separator","category": "Sorting",    "size": Vector3(2.4, 2.6, 5.5),  "color": Color(0.52, 0.50, 0.44)},
			{"id": "wind_sifter",    "name": "Windshifter (zigzag)","category": "Sorting",   "size": Vector3(1.8, 3.4, 2.0),  "color": Color(0.46, 0.52, 0.58)},
			# TOMRA Autosort: NIR sorter modelled from operator photos. The TITECH is
			# the same chassis 60 % wider (the same OEM lineage — TITECH became
			# TOMRA Sorting in 2008). Both ids route to _m_nir_sorter; size.x
			# scales everything.
			{"id": "tomra_sort",     "name": "TOMRA Autosort",     "category": "Sorting",    "size": Vector3(3.1, 2.4, 5.0),  "color": Color(0.95, 0.45, 0.10)},
			{"id": "titech_sort",    "name": "TITECH NIR sorter",  "category": "Sorting",    "size": Vector3(5.0, 2.4, 5.0),  "color": Color(0.95, 0.45, 0.10)},
			# ── Line 1 front-end additions ───────────────────────────────────
			{"id": "metaaldetector", "name": "Metal detector + reverse-reject belt","category": "Sorting",  "size": Vector3(2.0, 2.4, 5.0),  "color": Color(0.40, 0.42, 0.48)},
			# VW trommel (voorwastrommel) — Line 1 pre-wash drum. Scaled to the real
			# unit's 50,000 L capacity (~3 m ⌀ × ~7 m long). Sectional construction
			# with bolted seam rings, rotates on 2 pairs of solid rubber tires, axial
			# thrust assembly, drive shroud, drain grating tray, yellow peeling-paint
			# safety cage with embossed capacity placard. Modelled from CeDo photos.
			# Operator ruling 2026-08-28 (layout sketch): this drum IS also the
			# HPS (SGA) zware-delen scheider — one machine washes AND drops the
			# heavies. Name carries both so the K-menu/HMI read true.
			{"id": "vw_trommel",     "name": "VW trommel / HPS (SGA) — voorwas + zware delen (50,000L)","category": "Sorting","size": Vector3(3.6, 4.5, 8.0),  "color": Color(0.62, 0.62, 0.60)},
			# ── Wash line (wet section additions) ────────────────────────────
			{"id": "prewash_drum",   "name": "Pre-wash drum (2.5x scale)", "category": "Washing",    "size": Vector3(6.0, 6.5, 11.25), "color": Color(0.40, 0.54, 0.58)},
			{"id": "mas_droger",     "name": "MAS droger (dryer)", "category": "Washing",    "size": Vector3(2.0, 2.4, 3.0),  "color": Color(0.60, 0.62, 0.64)},
			{"id": "kufferath_sieve","name": "Kufferath sieve",    "category": "Separation", "size": Vector3(1.8, 2.0, 3.4),  "color": Color(0.56, 0.58, 0.60)},
			# ── Extrusion prep ───────────────────────────────────────────────
			{"id": "mengsilo",       "name": "Mixing silo (mengsilo)","category": "Extrusion prep","size": Vector3(3.0, 6.5, 3.0),"color": Color(0.60, 0.62, 0.66)},
			# ── Water / utilities (closes the wash-water loop) ────────────────
			{"id": "zss_water",      "name": "ZSS water tank (wash-water loop)","category": "Water / utilities","size": Vector3(2.4, 4.0, 2.4),"color": Color(0.40, 0.52, 0.60)},
			# Kleine LA (2026-07-06, water_small.md §1): separate small open-top
			# water tank at the 3B flotation-tank material-EXIT side (towards
			# Hal 0), floor-standing. Checklist row 16: tank level 90-92 cm =
			# "Nét overlopen kleine LA I" — kept just barely overflowing. "LA"
			# acronym unknown to the operator (flag F3). SIZE IS A PLACEHOLDER:
			# documented only as "~half of LA1" and LA1 has no size anywhere
			# (water_circuit_3a_la1.md:12 "geen volumes") — flag F1. Modeled
			# DEAD-END (no outlet documented — flag F2).
			{"id": "kleine_la",     "name": "Kleine LA (open waterbak, 3B uitloopzijde)", "category": "Water / utilities", "size": Vector3(1.5, 1.2, 1.5), "color": Color(0.40, 0.52, 0.60)},
			# Heater cabinet — operator spec 2026-08-28 (doc-walk Q2.4): "sixty
			# by sixty centimeter. And then about two meters high, which is
			# also where, like, the filters sit … from the bottom of these
			# filter stacks, the pipes go to the blower." Heats the air the
			# adjacent blower sucks in (3A rondmeng loop). Air-side utility —
			# MachineFlow role "none", placement only.
			{"id": "heater_cabinet","name": "Heater/filter cabinet (hete-lucht unit)", "category": "Water / utilities", "size": Vector3(0.6, 2.0, 0.6), "color": Color(0.52, 0.50, 0.48)},
			# Tankje tussen extruders (2026-07-06, water_small.md §2): small water
			# tank in the pellet/cooling-water cluster, ONE PER LINE (3A + 3B),
			# each with its OWN pump directly below it (flow diagrams 261_CeDo130
			# / 264_CeDo134 + interview). Composite: raised tankje + _m_pump
			# underneath. ALL DIMENSIONS PLACEHOLDER (only "tankje" = small is
			# documented — flags F4/F5); ontwaterzeef⇄tankje flow direction
			# unsure on the source photos (flag F6).
			{"id": "tankje_tussen_extruders", "name": "Tankje tussen extruders (+ pomp eronder)", "category": "Water / utilities", "size": Vector3(1.2, 2.2, 1.4), "color": Color(0.40, 0.52, 0.60)},
			# ── Logistics ────────────────────────────────────────────────────
			{"id": "waste_container","name": "Waste container (schraperbak)","category": "Logistics","size": Vector3(1.2, 1.2, 1.6),"color": Color(0.72, 0.56, 0.20)},
			{"id": "skip_steel",     "name": "Steel skip (PLASTIC, chute)",  "category": "Logistics","size": Vector3(1.6, 1.2, 1.4),  "color": Color(0.42, 0.46, 0.40)},
			{"id": "fines_bin",      "name": "Fines bin (under-conveyor)",   "category": "Logistics","size": Vector3(0.9, 1.1, 0.9),  "color": Color(0.18, 0.18, 0.20)},
			{"id": "cyclone_bin",    "name": "Cyclone underflow bin",        "category": "Logistics","size": Vector3(1.1, 1.1, 1.1),  "color": Color(0.50, 0.52, 0.54)},
			{"id": "ibc_tote",       "name": "IBC tote (1 m³, fluids)",      "category": "Logistics","size": Vector3(1.0, 1.2, 1.2),  "color": Color(0.86, 0.86, 0.84)},
			# #98 - Lumpenwagen (lump cart): wheeled blue steel dumpster the operator parks
			# under the extruder's screen-changer outlet. Unmelted polymer agglomerates
			# (gels, cross-linked chunks) drop into it as the screen pack catches them.
			# From the operator photo (desktop/_lumbs_cart.jpg).
			{"id": "lump_cart",      "name": "Lumpenwagen (extruder filter catch)", "category": "Logistics","size": Vector3(0.85, 0.95, 1.30), "color": Color(0.16, 0.30, 0.55)},
			# #98 - Yellow floor marking each extruder has, where the lump_cart parks at
			# shift start. Visual-only L-bracket outlines on the concrete.
			{"id": "lump_cart_spot", "name": "Lumpenwagen parkeervak (gele vloermarkering)", "category": "Logistics","size": Vector3(1.10, 0.05, 1.55), "color": Color(0.94, 0.78, 0.14)},
			# #154 — Wardrobe locker: walk up, press E, opens the character
			# customizer (#153). Tall blue steel cabinet, hi-vis vest hanging
			# inside the open door as a visual cue.
			{"id": "wardrobe_locker", "name": "Kleedlocker (wardrobe)",        "category": "Logistics","size": Vector3(0.60, 2.00, 0.50), "color": Color(0.10, 0.20, 0.40)},
			# U-shaped concrete buffer bay (3A/3B): when both VSS silos are full, belt
			# 8.5 dumps film here; the Merlo drives in and scoops the pile.
			{"id": "concrete_bay",   "name": "Concrete buffer bay (U, Merlo-scoop)","category": "Logistics","size": Vector3(8.0, 2.5, 8.0),  "color": Color(0.60, 0.60, 0.58)},
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
			# Bigbag station — doc-walk gap 2.2 (lijn_3a_flow.md edge 36:
			# Weegschaal → bigbag station; ruled a 3A-ONLY feature in
			# question_answers.json). Operator composite spec 2026-08-28 from
			# two reference images (sent in chat, to be archived): BOTTOM =
			# open steel frame, bag hanging by its 4 loops on corner hangers,
			# resting on a wooden EURO pallet; TOP = fill head with the bag's
			# "trunk" inlet sleeve bound to a metal fill cylinder with a BLUE
			# strap, and a small cyclone on top of the frame.
			{"id": "bigbag_station", "name": "Bigbag station (weegschaal aftap)","category": "Logistics", "size": Vector3(1.7, 3.6, 1.7),  "color": Color(0.72, 0.73, 0.75)},
			{"id": "voorraad_silo",  "name": "Voorraad silo (granulate)",    "category": "Structure",    "size": Vector3(3.0, 6.5, 3.0),  "color": Color(0.66, 0.68, 0.72)},
			# ── OUTDOOR PELLET SILOS MS/LS (2026-07-06, silos_ms_ls.md) ───────
			# Silopark: 10 silos in 2 rows of 5 (operator ruling B8 2026-07-06,
			# per the floor plan 240_CeDo127), Buitenterrein zuidwest below
			# Hal 0/Hal 1. Per-line dedicated silos; operators never interact.
			# MS = mengsilo: MIXING is a background recirculation LOOP — pellets
			# pumped backward laadsilo → mengsilo and forward again, looping per
			# pellet type (ruling B6); NO player controls, visual pipe stubs only.
			# LS = laadsilo: truck lane underneath + discharge spout.
			# Height 18.0 m + ~4 m footprint are SHELL-MESH-DERIVED PLACEHOLDERS
			# (3DBAG cluster at world ≈ (-211, +53), silos_ms_ls.md §4 — flags
			# 1/2/13); grey copied from voorraad_silo, RAL undocumented (flag 12).
			# NOT the indoor 3A flake `mengsilo` — different machine, keep apart.
			{"id": "ms_silo_buiten", "name": "Mengsilo buiten (MS — pellet blend)",   "category": "Structure", "size": Vector3(4.0, 18.0, 4.0), "color": Color(0.66, 0.68, 0.72)},
			{"id": "ls_silo_buiten", "name": "Laadsilo buiten (LS — truck loadout)",  "category": "Structure", "size": Vector3(4.0, 18.0, 4.0), "color": Color(0.66, 0.68, 0.72)},
			# EOP (End Of Pipe) — EXTERNAL ENTITY endpoint (2026-07-06,
			# eop_rafter.md Part A). Indaver-operated on-site water-treatment
			# mini-plant (sand / fine-film "paper pulp" / slib removal; goal =
			# water REUSE, not river discharge — QA:Q12). NOT a working machine:
			# role "none" in MachineFlow, no player interaction (control-room
			# visibility is the separate hmi_indaver_water wall panel). Appearance
			# UNDOCUMENTED — neutral 6×3×4 m building block + placard + the 3
			# documented pipe-stub groups (water_circuits.json edges); flags 1-3.
			{"id": "eop_endpoint",   "name": "EOP — Indaver waterzuivering (extern)", "category": "Structure", "size": Vector3(6.0, 3.0, 4.0),  "color": Color(0.55, 0.56, 0.58)},
			# #A3 — Silo level sensor. A small panel that reads the linked silo's
			# fill level and signals upstream throttle when it climbs high. The
			# operator can BRIDGE it (E) to remove the governor — peak-performance
			# trick from the transcript, at the cost of overflow risk.
			{"id": "silo_level_sensor","name": "Silo level sensor (overbruggebaar)","category": "Control","size": Vector3(0.30, 0.36, 0.12), "color": Color(0.92, 0.78, 0.18)},
			# ── Control (HMIs) ───────────────────────────────────────────────
			# 12 scoped HMI panels — one per operator-listed control panel (#165).
			# The scope table lives in HmiScopes.gd; each entry below carries the
			# hmi_id meta (Hmi.gd reads it on _ready) so the overlay knows which
			# subset of machines to expose. `mesh` selects the stand- vs
			# wall-mount geometry — both physical builds remain available.
			# These 12 are the WHOLE list. The pre-#165 cosmetic ids
			# `hmi_panel` / `hmi_wall` were RETIRED 2026-08-15 (operator order:
			# "remove unused/old HMI displays") — see RETIRED_IDS below. Do not
			# re-add a generic see-all panel; there is no such thing in the plant.
			{"id": "hmi_shredder_l1",       "name": "HMI — Shredder lijn 1",            "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.30, 0.32, 0.36), "hmi_id": "hmi_shredder_l1",       "mesh": "hmi_panel"},
			{"id": "hmi_shredder1_l3ab",    "name": "HMI — Shredder 1 lijn 3A/3B",      "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.30, 0.32, 0.36), "hmi_id": "hmi_shredder1_l3ab",    "mesh": "hmi_panel"},
			{"id": "hmi_shredder2_l3ab",    "name": "HMI — Shredder 2 lijn 3A/3B",      "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.30, 0.32, 0.36), "hmi_id": "hmi_shredder2_l3ab",    "mesh": "hmi_panel"},
			{"id": "hmi_shredder_l3c6",     "name": "HMI — Shredder lijn 3C/6",         "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.30, 0.32, 0.36), "hmi_id": "hmi_shredder_l3c6",     "mesh": "hmi_panel"},
			{"id": "hmi_sorting_l3ab",      "name": "HMI — Sorteerlijn 3A/3B",          "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.26, 0.38, 0.30), "hmi_id": "hmi_sorting_l3ab",      "mesh": "hmi_panel"},
			{"id": "hmi_transport_l3ab",    "name": "HMI — Transportbanden 3A/3B",      "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.36, 0.30, 0.18), "hmi_id": "hmi_transport_l3ab",    "mesh": "hmi_panel"},
			{"id": "hmi_transport_l3c6",    "name": "HMI — Transportbanden 3C/6",       "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.36, 0.30, 0.18), "hmi_id": "hmi_transport_l3c6",    "mesh": "hmi_panel"},
			{"id": "hmi_washing_all",       "name": "HMI — Waslijn (alle lijnen)",      "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.16, 0.30, 0.40), "hmi_id": "hmi_washing_all",       "mesh": "hmi_panel"},
			{"id": "hmi_extruder_all",      "name": "HMI — Extruder (alle lijnen)",     "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.30, 0.16, 0.34), "hmi_id": "hmi_extruder_all",      "mesh": "hmi_panel"},
			{"id": "hmi_water_l3c6",        "name": "HMI — Water lijn 3C/6",            "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.14, 0.34, 0.40), "hmi_id": "hmi_water_l3c6",        "mesh": "hmi_panel"},
			{"id": "hmi_water_extr_l1_3ab", "name": "HMI — Water extruder 1/3A/3B",     "category": "Control", "size": Vector3(0.7, 1.5, 0.5),  "color": Color(0.14, 0.34, 0.40), "hmi_id": "hmi_water_extr_l1_3ab", "mesh": "hmi_panel"},
			{"id": "hmi_indaver_water",     "name": "HMI — Indaver waterzuivering",     "category": "Control", "size": Vector3(0.6, 0.5, 0.16), "color": Color(0.22, 0.40, 0.46), "hmi_id": "hmi_indaver_water",     "mesh": "hmi_wall"},
			# Shift-leader PC: walk up + E → Balen-scanlog + Reset/Restock buttons
			# (#73 / #74). MainWorld also auto-spawns one for back-compat, but this
			# entry lets the operator place additional desks or move them via K-edit.
			{"id": "shift_leader_desk", "name": "Bedrijfsleider PC (scan log + balen)", "category": "Control",   "size": Vector3(1.60, 1.40, 0.85), "color": Color(0.30, 0.22, 0.16)},
			# Quality-analysis bench: lab-style worktop with PC + precision scale +
			# sample tray + magnifier. Walk up + E → quality terminal (live MFI /
			# colour grade / sample submit). v1 terminal is a read-out stub; full
			# wiring sits alongside #46 (MFI proxy) for a future pass.
			{"id": "qa_bench",          "name": "Kwaliteitscontrole tafel (QA bench)",  "category": "Control",   "size": Vector3(2.00, 1.50, 0.90), "color": Color(0.85, 0.85, 0.88)},
			# ── Hand tools (spawn from the menu instead of being pre-placed) ──
			{"id": "tool_shovel",    "name": "Shovel",             "category": "Tools",      "size": Vector3(0.30, 1.4, 0.30), "color": Color(0.55, 0.40, 0.25)},
			{"id": "tool_scissors",  "name": "Wire scissors",      "category": "Tools",      "size": Vector3(0.30, 0.9, 0.30), "color": Color(0.80, 0.30, 0.25)},
			{"id": "tool_scanner",   "name": "Barcode scanner",    "category": "Tools",      "size": Vector3(0.22, 0.3, 0.22), "color": Color(0.95, 0.78, 0.10)},
			{"id": "tool_line_coupler", "name": "Line coupler (PLC wire tool)", "category": "Tools", "size": Vector3(0.25, 0.35, 0.25), "color": Color(0.18, 0.75, 0.95)},
			{"id": "tool_lpg_rack",  "name": "LPG cylinder rack",  "category": "Tools",      "size": Vector3(1.2, 1.4, 0.6),   "color": Color(0.85, 0.55, 0.20)},
			{"id": "tool_leafblower","name": "Leaf blower",        "category": "Tools",      "size": Vector3(0.30, 0.40, 0.90),"color": Color(0.96, 0.42, 0.10)},
			# Jerry can — places a refuel station for the leaf blower (and any future
			# fuel-burning held tool). Infinite supply per the operator's spec;
			# operator just has to walk to it with the blower in their hotbar + press E.
			{"id": "tool_jerrycan",  "name": "Jerry can (fuel)",   "category": "Tools",      "size": Vector3(0.32, 0.42, 0.20),"color": Color(0.78, 0.16, 0.14)},
			# #210b — Maat-7 dopsleutel: 7 mm socket wrench used to swap the
			# pelletizer cutting knife. Item-only here (pickup + held visual);
			# the knife-swap interaction itself lives downstream in #210.
			{"id": "socket_wrench_7","name": "Maat-7 dopsleutel",  "category": "Tools",      "size": Vector3(0.05, 0.06, 0.20),"color": Color(0.55, 0.57, 0.60)},
			# ── Hoses, reels, compressors (housekeeping + process air supply) ────
			# Wall-mount reel holding a ~10 m thick YELLOW water hose; ball valve at the
			# base and at the nozzle tip. Used for floor wash-down.
			{"id": "reel_water_thick_yellow","name":"Water hose reel (yellow, 10 m thick)","category":"Hoses & Air","size":Vector3(0.95, 1.10, 0.60),"color":Color(0.96, 0.78, 0.16)},
			# Wall-mount reel with a ~10 m thin BLACK water hose; same ball-valve setup.
			{"id": "reel_water_black","name":"Water hose reel (black, 10 m thin)","category":"Hoses & Air","size":Vector3(0.85, 0.95, 0.55),"color":Color(0.10, 0.10, 0.11)},
			# Wall-mount reel with a ~10 m RED fire hose (same gauge as the black water hose).
			{"id": "reel_fire_red","name":"Fire hose reel (red, 10 m)","category":"Hoses & Air","size":Vector3(0.85, 0.95, 0.55),"color":Color(0.78, 0.16, 0.14)},
			# Simple wall HOOK with a coil of ~20 m translucent-white air hose draped over it.
			{"id": "hook_air_hose","name":"Air hose hook (20 m, translucent)","category":"Hoses & Air","size":Vector3(0.70, 1.00, 0.55),"color":Color(0.92, 0.92, 0.88)},
			# Mobile HIGH-PRESSURE WASHER cart (~4 m thin hose + pistol w/ elongated barrel).
			{"id": "washer_hp_mobile","name":"High-pressure washer (mobile)","category":"Hoses & Air","size":Vector3(0.60, 1.00, 0.90),"color":Color(0.86, 0.18, 0.16)},
			# Reciprocating COMPRESSOR — vertical tank + motor on top, ~1.5 × 1.5 × 3 m, 5 bar.
			{"id": "compressor_a","name":"Compressor A (vertical, ~3 m)","category":"Hoses & Air","size":Vector3(1.50, 3.00, 1.50),"color":Color(0.30, 0.46, 0.62)},
			# Screw-type COMPRESSOR cabinet — taller, narrower, ~1 × 1 × 4 m, 5 bar.
			{"id": "compressor_b","name":"Compressor B (cabinet, ~4 m)","category":"Hoses & Air","size":Vector3(1.00, 4.00, 1.00),"color":Color(0.45, 0.48, 0.52)},
			# Vacuum unit — stainless 2-door cabinet that houses the vacuum-pump control gear (#208a).
			{"id": "vacuum_unit","name":"Vacuum unit (cabinet, 2-door)","category":"Hoses & Air","size":Vector3(0.65, 1.50, 0.45),"color":Color(0.78, 0.80, 0.82)},
			# Vacuum pump — liquid-ring bronze pump w/ rear IEC motor (#208b).
			{"id": "vacuum_pump","name":"Vacuum pump (liquid-ring)","category":"Hoses & Air","size":Vector3(0.35, 0.30, 0.55),"color":Color(0.48, 0.50, 0.54)},
			# Dirt hot-spot — a floor zone that ACCUMULATES dirt over time. Place these
			# around the dryers, under chutes, on forklift lanes, etc. Water hose / HP
			# washer spray clears them. #40
			{"id": "dirt_hotspot","name":"Dirt hot-spot (auto-accumulates)","category":"Hoses & Air","size":Vector3(1.20, 0.05, 1.20),"color":Color(0.46, 0.36, 0.22)},
			# Housekeeping helpers (used WITH the blower): a corner CollectionZone
			# (frees film_scrap that drifts in) and a test PILE of loose scraps to
			# practice blowing them around the floor.
			{"id": "zone_collection","name": "Collection zone",    "category": "Tools",      "size": Vector3(5.0, 0.05, 5.0),  "color": Color(0.20, 0.60, 0.95)},
			{"id": "film_scrap_pile","name": "Film scrap pile",    "category": "Tools",      "size": Vector3(2.0, 0.05, 2.0),  "color": Color(0.78, 0.82, 0.74)},
			# ── Vehicles (X2/#181) — spawn from build menu for quick QA. id prefix
			# "vehicle_" routes through the scene-instantiation branch in build_node().
			{"id": "vehicle_forklift",   "name": "Forklift",            "category": "Vehicles", "size": Vector3(1.4, 2.4, 3.0), "color": Color(0.18, 0.40, 0.22), "scene": "res://src/scenes/vehicles/Forklift.tscn"},
			{"id": "vehicle_baleclamp",  "name": "Bale clamp",          "category": "Vehicles", "size": Vector3(1.6, 2.6, 3.6), "color": Color(0.18, 0.42, 0.22), "scene": "res://src/scenes/vehicles/BaleClamp.tscn"},
			{"id": "vehicle_merlo_p40",  "name": "Merlo P40 (far-reach)","category": "Vehicles", "size": Vector3(2.2, 2.8, 6.0), "color": Color(0.85, 0.55, 0.10), "scene": "res://src/scenes/vehicles/MerloP40.tscn"},
			{"id": "vehicle_merlo",      "name": "Merlo (compact variant)","category": "Vehicles", "size": Vector3(2.0, 2.6, 5.5), "color": Color(0.82, 0.52, 0.10), "scene": "res://src/scenes/vehicles/Merlo.tscn"},
			{"id": "vehicle_mast_lift",  "name": "Mast lift (worker platform)","category": "Vehicles", "size": Vector3(1.4, 2.2, 2.4), "color": Color(0.74, 0.40, 0.10), "scene": "res://src/scenes/vehicles/MastLift.tscn"},
			{"id": "vehicle_swift",      "name": "Suzuki Swift GLX (player car)","category": "Vehicles", "size": Vector3(1.5, 1.4, 3.7), "color": Color(0.78, 0.10, 0.10), "scene": "res://src/scenes/vehicles/cars/SuzukiSwiftGLX.tscn"},
			# ── #212 Decals (hazard placards / environment polish) ─────────────
			# Small yellow safety placards on a thin QuadMesh, faced +Z (front).
			# Builder: _m_hazard_decal — id selects the printed icon/text via
			# HAZARD_LABELS. Sized so they read clearly at walking distance.
			{"id": "hazard_moving",          "name": "Hazard placard — Moving machinery",  "category": "Decals", "size": Vector3(0.4, 0.4, 0.01), "color": Color(0.95, 0.85, 0.10)},
			{"id": "hazard_overhead",        "name": "Hazard placard — Overhead load",     "category": "Decals", "size": Vector3(0.4, 0.4, 0.01), "color": Color(0.95, 0.85, 0.10)},
			{"id": "hazard_hightemp",        "name": "Hazard placard — High temperature",  "category": "Decals", "size": Vector3(0.4, 0.4, 0.01), "color": Color(0.95, 0.85, 0.10)},
			{"id": "hazard_hardhat",         "name": "Hazard placard — Hard hat required", "category": "Decals", "size": Vector3(0.4, 0.4, 0.01), "color": Color(0.95, 0.85, 0.10)},
			{"id": "hazard_piralchute",      "name": "Hazard placard — Piral chute",       "category": "Decals", "size": Vector3(0.4, 0.4, 0.01), "color": Color(0.95, 0.85, 0.10)},
			{"id": "hazard_platformmaxload", "name": "Hazard placard — Platform max load", "category": "Decals", "size": Vector3(0.4, 0.4, 0.01), "color": Color(0.95, 0.85, 0.10)},
			# ── #212 Environment placeables ───────────────────────────────────
			{"id": "overhead_crane",         "name": "Overhead PPE gantry crane",          "category": "Structure", "size": Vector3(8.0, 4.0, 0.4),  "color": Color(0.95, 0.75, 0.10)},
			{"id": "fire_riser",             "name": "Fire-suppression riser",             "category": "Structure", "size": Vector3(0.15, 3.0, 0.15), "color": Color(0.85, 0.20, 0.18)},
			{"id": "fire_extinguisher",      "name": "Fire extinguisher (wall mount)",     "category": "Structure", "size": Vector3(0.25, 0.6, 0.25), "color": Color(0.85, 0.20, 0.18)},
			{"id": "drainage_grating",       "name": "Drainage grating section",           "category": "Structure", "size": Vector3(1.0, 0.05, 1.0), "color": Color(0.24, 0.25, 0.28)},
			{"id": "scissor_lift",           "name": "Scissor lift (yellow)",              "category": "Structure", "size": Vector3(1.4, 2.0, 1.8), "color": Color(0.95, 0.75, 0.10)},
			{"id": "riveted_steel_column",   "name": "Riveted steel arch column",          "category": "Structure", "size": Vector3(0.4, 4.0, 0.4), "color": Color(0.55, 0.57, 0.60)},
			{"id": "concrete_v_beam",        "name": "Concrete V-beam",                    "category": "Structure", "size": Vector3(1.5, 3.5, 0.4), "color": Color(0.75, 0.72, 0.70)},
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

## Map any legacy ID to its current canonical ID. Returned unchanged if no alias.
## Used so existing saves that wrote `intake_belt_3` keep loading after the
## #141 rename to `transportband_3`. Add a single line here for any future rename.
static func _canonical_id(id: String) -> String:
	if id.begins_with("intake_belt_"):
		return "transportband_" + id.substr("intake_belt_".length())
	return id

## =============================================================================
## RETIRED PLACEABLES — ids that existed in old saves and must never come back
## =============================================================================
## A retired id is NOT an alias: there is no replacement to map it to, so it is
## deliberately DROPPED on load rather than silently rebuilt as something else.
##
## `hmi_panel` / `hmi_wall` were the pre-#165 cosmetic HMI props. They opened a
## "generic" see-every-machine overlay that has no counterpart anywhere in the
## real plant — the operator's whiteboard lists exactly 12 panels (HmiScopes.gd)
## and every one of them is now a first-class catalog entry. Operator order
## 2026-08-15: "remove unused/old HMI displays … from build menu and from logic".
##
## Contract:
##   - not in `items()`      → gone from the build menu, gone from every
##                             catalog-driven UI/tool that enumerates items
##   - `build_node()` → null → an old save entry produces nothing, with ONE
##                             explanatory warning instead of the bare
##                             "Unknown id" (BuildMode counts them per load)
##   - re-saving the world drops the entry for good (the node no longer exists)
##
## The value is the reason string, printed once per id per load.
const RETIRED_IDS := {
	"hmi_panel": "legacy generic HMI stand (pre-#165) — retired 2026-08-15, place one of the 12 scoped HMI panels instead",
	"hmi_wall":  "legacy generic HMI wall panel (pre-#165) — retired 2026-08-15, place `hmi_indaver_water` or one of the 12 scoped HMI panels instead",
}

## True when `id` is a retired placeable — never buildable, never in the menu.
static func is_retired(id: String) -> bool:
	return RETIRED_IDS.has(_canonical_id(id))

## Human-readable reason a placeable was retired ("" when it wasn't).
static func retired_reason(id: String) -> String:
	return String(RETIRED_IDS.get(_canonical_id(id), ""))

## =============================================================================
## SIZE OVERRIDES (in-game 3D-model editor — K-mode "B" bake key)
## =============================================================================
## A user can resize a placed machine by scaling it (K edit + 7/4 8/5 9/6
## per-axis or +/- uniform) and then press B to BAKE the new size into a
## per-id override stored in `user://placeable_size_overrides.json`. The
## override is applied here in `get_item()` so every future `build_node(id)`
## call — both in the current run and across new worlds / saves — produces
## meshes at the new size automatically. The bake step also resets the
## instance's `.scale` to (1,1,1) and rebuilds its procedural Model subtree
## via `rebuild_in_place()` so the live world keeps a 1:1 scale and a
## subsequent reload doesn't double-multiply size × scale.
##
## Path is intentionally under `user://` (not the project tree) so each
## installation tracks its own bakes — and so the operator can hand-edit
## or delete the file to revert. Keys are placeable ids; values are
## `{"size": [x, y, z]}` dicts. JSON-encoded for human-readability.
const _SIZE_OVERRIDES_PATH := "user://placeable_size_overrides.json"
static var _size_overrides : Dictionary = {}
static var _size_overrides_loaded : bool = false

static func _ensure_overrides_loaded() -> void:
	if _size_overrides_loaded:
		return
	_size_overrides_loaded = true
	if not FileAccess.file_exists(_SIZE_OVERRIDES_PATH):
		return
	var f := FileAccess.open(_SIZE_OVERRIDES_PATH, FileAccess.READ)
	if f == null:
		return
	var raw : String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("[PlaceableCatalog] size-overrides JSON malformed; ignoring")
		return
	for k in (parsed as Dictionary).keys():
		var entry = (parsed as Dictionary)[k]
		if not (entry is Dictionary):
			continue
		var sz = (entry as Dictionary).get("size", null)
		if sz is Array and (sz as Array).size() == 3:
			_size_overrides[String(k)] = Vector3(
				float((sz as Array)[0]),
				float((sz as Array)[1]),
				float((sz as Array)[2]))

static func _save_overrides_to_disk() -> void:
	var out : Dictionary = {}
	for k in _size_overrides.keys():
		var v : Vector3 = _size_overrides[k]
		out[String(k)] = {"size": [v.x, v.y, v.z]}
	var f := FileAccess.open(_SIZE_OVERRIDES_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[PlaceableCatalog] could not write %s" % _SIZE_OVERRIDES_PATH)
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()

## Persist a new base size for `id`. Future `build_node(id)` calls return
## meshes at this size in every world / save. Pass `Vector3.ZERO` (or call
## clear_size_override) to remove the override and fall back to the
## hard-coded catalog default. Returns the size that was stored.
static func set_size_override(id: String, size: Vector3) -> Vector3:
	_ensure_overrides_loaded()
	var canon : String = _canonical_id(id)
	var clamped : Vector3 = Vector3(
		clampf(size.x, 0.05, 200.0),
		clampf(size.y, 0.05, 200.0),
		clampf(size.z, 0.05, 200.0))
	_size_overrides[canon] = clamped
	_save_overrides_to_disk()
	return clamped

static func clear_size_override(id: String) -> void:
	_ensure_overrides_loaded()
	var canon : String = _canonical_id(id)
	if _size_overrides.has(canon):
		_size_overrides.erase(canon)
		_save_overrides_to_disk()

## True if `id` has a baked-in size override active.
static func has_size_override(id: String) -> bool:
	_ensure_overrides_loaded()
	return _size_overrides.has(_canonical_id(id))

## Rebuild the procedural Model subtree (and the box CollisionShape3D) of an
## already-placed `body` to match the CURRENT catalog size — used after a
## bake so the live mesh swaps to the new dimensions without re-placing. Only
## handles the standard `StaticBody3D` + Model subtree + single BoxShape3D
## collision pattern (which covers nearly every machine catalog entry); items
## with bespoke construction (lump_cart compound collision, bales, doors,
## tools, vehicles, walls) are NOT rebuilt — the catalog override still
## affects FUTURE placements of those, just not this live instance.
## Returns true on success.
static func rebuild_in_place(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var pid : String = String(body.get_meta("placeable_id", ""))
	if pid == "":
		return false
	var item := get_item(pid)
	if item.is_empty():
		return false
	# Skip bespoke construction paths — they don't follow the Model / BoxShape3D
	# convention and a generic rewrite would break their custom collision.
	if pid == "lump_cart" or pid.begins_with("tool_") or pid.begins_with("vehicle_") \
			or pid.begins_with("wall_") \
			or pid in ["door_personnel", "gate_roller", "window_frame", "socket_wrench_7"]:
		push_warning("[PlaceableCatalog] rebuild_in_place skipped — %s uses bespoke construction" % pid)
		return false
	var category : String = String(item["category"])
	if category == "Bales":
		return false
	var size : Vector3 = item["size"]
	var color : Color = item["color"]
	# Swap the Model subtree.
	var model : Node3D = body.get_node_or_null("Model") as Node3D
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		body.add_child(model)
	else:
		for c in model.get_children():
			c.queue_free()
	_build_model(model, pid, category, size, color, false)
	# Update the box collision (if the body uses the standard pattern).
	for c in body.get_children():
		if c is CollisionShape3D:
			var cs : CollisionShape3D = c
			if cs.shape is BoxShape3D:
				(cs.shape as BoxShape3D).size = size
				cs.position = Vector3(0.0, size.y * 0.5, 0.0)
			break
	# Re-floor the legs (if any) so the new height still grounds correctly.
	extend_machine_legs(body, body.global_position.y - 0.0)
	return true

static func get_item(id: String) -> Dictionary:
	_ensure_overrides_loaded()
	var canon : String = _canonical_id(id)
	for it in items():
		if it["id"] == canon:
			# Apply the in-game size override if the operator has baked one.
			# Duplicate so we don't mutate the static catalog Dictionary.
			if _size_overrides.has(canon):
				var copy := it.duplicate(true)
				copy["size"] = _size_overrides[canon]
				return copy
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

## True when this placeable id requires two clicks (start point + end point) to
## place. BuildMode reads this and switches to a two-step flow for variable belts.
static func is_two_point(id: String) -> bool:
	return id == "variable_belt" or id == "grating_platform" or id.begins_with("wall_")

## True for the click-start/click-end wall placeables.
static func is_wall(id: String) -> bool:
	return id.begins_with("wall_")

# ── Walls (2-click solid partitions) ──────────────────────────────────────────
static var _wall_mat : StandardMaterial3D = null
static func _wall_material() -> StandardMaterial3D:
	if _wall_mat == null:
		_wall_mat = StandardMaterial3D.new()
		_wall_mat.albedo_color = Color(0.82, 0.80, 0.76)   # off-white painted block
		_wall_mat.roughness = 0.92
		_wall_mat.metallic = 0.0
	return _wall_mat

## Build a solid wall spanning start_pos → end_pos (a real box with collision, so
## it blocks movement and never leaks light). `thickness`/`height` come from the
## chosen wall placeable's size (size.x / size.y). The wall is oriented along the
## click line; the caller positions it at the span midpoint. Base sits on the floor.
static func build_wall(start_pos: Vector3, end_pos: Vector3, thickness: float, height: float, ghost: bool = false) -> Node3D:
	var diff := end_pos - start_pos
	var fwd := Vector3(diff.x, 0.0, diff.z)
	var length : float = fwd.length()
	if length < 0.3:
		return null
	if ghost:
		return _simple_ghost(Vector3(thickness, height, length))
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.add_to_group("placed_object")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thickness, height, length)
	mi.mesh = bm
	mi.material_override = _wall_material()
	mi.position = Vector3(0.0, height * 0.5, 0.0)   # base on the floor, grows up
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(thickness, height, length)
	cs.shape = shape
	cs.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(cs)
	body.rotation.y = atan2(diff.x, diff.z)   # local +Z runs start → end
	return body

# ── Steel-grating material (#64) ──────────────────────────────────────────────
## Shared SEE-THROUGH industrial grating look. Built ONCE and cached. Implemented
## as a StandardMaterial3D with a procedurally-built grid Image on albedo and
## TRANSPARENCY_ALPHA_SCISSOR: the bar pixels are opaque mid-grey metal, the cell
## centres are alpha=0 and get scissor-clipped, so you literally see through the
## holes (and there is NO per-pixel sort cost — scissor writes depth). cull set to
## DISABLED so the deck is visible from above AND below. We use an image rather
## than an inline Shader to stay robust (no separate .gdshader file, no risk of a
## silent shader compile error). Cell size is held ~constant regardless of platform
## size by the DECK builder, which sets uv1_scale so one texture tile ≈ GRID_CELL_M
## of world space (see build_grating_platform / _m_stairs).
static var _grating_mat : StandardMaterial3D = null
## World-space size of one grating cell (centre-to-centre of the bars), in metres.
const GRID_CELL_M : float = 0.22
const _GRATING_TEX_PX : int = 48     # texture is one cell; bar band is a few px of it.

static func _grating_material() -> Material:
	if _grating_mat != null:
		return _grating_mat
	# One cell tile: opaque bars along two edges (so tiling makes a continuous grid),
	# transparent (alpha 0) interior that the alpha-scissor discards.
	var px : int = _GRATING_TEX_PX
	var bar : int = maxi(2, int(round(float(px) * 0.18)))   # ~18% of the cell is steel
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var steel_a := Color(0.46, 0.48, 0.51, 1.0)             # mid-grey metal, opaque
	var steel_b := Color(0.54, 0.56, 0.59, 1.0)             # lighter top edge of the bar
	var hole := Color(0.0, 0.0, 0.0, 0.0)                   # discarded by the scissor
	for y in px:
		for x in px:
			var on_bar : bool = (x < bar) or (y < bar)
			if on_bar:
				# A 1px brighter lip on the leading edge of each bar reads as a chamfer.
				var lip : bool = (x == 0) or (y == 0)
				img.set_pixel(x, y, steel_b if lip else steel_a)
			else:
				img.set_pixel(x, y, hole)
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.55, 0.57, 0.60)
	m.metallic = 0.85
	m.roughness = 0.45
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # visible from above and below
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # crisp bars, no grey smear
	# uv1_scale is overridden per-deck so the cell size stays ~GRID_CELL_M regardless
	# of platform dimensions; this default suits a 1 m surface.
	m.uv1_scale = Vector3(1.0 / GRID_CELL_M, 1.0 / GRID_CELL_M, 1.0)
	_grating_mat = m
	return _grating_mat

## A grating MeshInstance for a flat W×L deck whose UVs are tiled so the visible
## cell size is ~GRID_CELL_M no matter the deck size. Shares the cached albedo
## texture (only the lightweight material wrapper is duplicated to carry a per-deck
## uv1_scale). Built as a thin BoxMesh so it reads as a deck from any angle.
static func _grating_deck(parent: Node3D, w: float, l: float, pos: Vector3) -> MeshInstance3D:
	# Duplicate the cached material so this deck can carry its own uv1_scale without
	# disturbing the shared one (the heavy albedo texture resource is still shared).
	var m := (_grating_material() as StandardMaterial3D).duplicate() as StandardMaterial3D
	# BoxMesh top/bottom faces span the full W×L in UV 0..1, so scale UV by size/cell.
	m.uv1_scale = Vector3(w / GRID_CELL_M, l / GRID_CELL_M, 1.0)
	return _box(parent, Vector3(w, 0.02, l), pos, m)

## Build a variable-length / variable-angle conveyor that spans WORLD-SPACE
## start_pos to end_pos. Length, angle, and (start_y, end_y) are derived from
## the two points. Belt deck has the scrolling textured material. Returns a
## StaticBody3D whose origin is at start_pos; geometry is built in local space.
static func build_variable_belt(start_pos: Vector3, end_pos: Vector3, ghost: bool = false) -> Node3D:
	var diff := end_pos - start_pos
	var length : float = diff.length()
	if length < 0.5:
		return null   # too short to bother
	if ghost:
		return _simple_ghost(Vector3(0.9, 0.4, maxf(length, 0.5)))
	var body := StaticBody3D.new()
	body.name = "VariableBelt"
	body.set_meta("placeable_id", "variable_belt")
	body.set_meta("vb_start", start_pos)
	body.set_meta("vb_end",   end_pos)
	body.add_to_group("placed_object")
	# Walkable belt deck: carry the player along local +Z (start → end) when they
	# stand on it (#59). The body is rotated below so local +Z spans the diff.
	body.add_to_group("belt")
	body.set_meta("belt_speed", _BELT_CARRY_SPEED)
	# Frame oriented so its local +Z points from start to end, height aligned with world up.
	# We compute the rotation needed to span the diff vector with the belt's local Z.
	var model := Node3D.new()
	model.name = "Model"
	body.add_child(model)
	_m_variable_belt(model, length, diff, ghost)
	# Position the body at the START; rotate so model's +Z points toward end_pos.
	var fwd_xz : Vector3 = Vector3(diff.x, 0.0, diff.z)
	var horiz_len : float = fwd_xz.length()
	var yaw : float = atan2(diff.x, diff.z) if horiz_len > 0.01 else 0.0
	# Pitch around X so the belt rises (or falls) by diff.y over horiz_len.
	var pitch : float = 0.0 if horiz_len < 0.01 else -atan2(diff.y, horiz_len)
	# Use LOCAL position/rotation here — body is not yet in the tree (the caller
	# adds it via add_child after we return). Local equals global when parented
	# under an at-origin _placed_root, which is the BuildMode usage.
	body.position = start_pos
	body.rotation = Vector3(pitch, yaw, 0.0)
	# Bounding collider — a thin slab along the deck so the player + vehicles can
	# walk on / drive across it.
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.92, 0.20, length)
	col.shape = bx
	col.position = Vector3(0.0, 0.20, length * 0.5)
	body.add_child(col)
	# AUTO-LEGS — generate single-leg supports at ~2.5 m intervals along the span
	# (world-vertical), each tall enough to reach the deck at its share of the
	# diff.y rise. These spawn as SIBLINGS via a meta hook so BuildMode can add
	# them to _placed_root (where they become independent placed_objects that the
	# operator can delete, augment, or replace).
	var legs : Array = []
	var step_m : float = 2.5
	var n_legs : int = max(2, int(round(length / step_m)) + 1)
	for i in n_legs:
		var t : float = float(i) / float(maxi(1, n_legs - 1))
		var point : Vector3 = start_pos + diff * t                # belt-deck world pos
		var leg_top_y : float = point.y + 0.20                    # match deck_y offset
		var leg_h : float = maxf(0.15, leg_top_y)                 # floor assumed at y=0
		legs.append({"pos": Vector3(point.x, 0.0, point.z), "h": leg_h})
	body.set_meta("auto_legs", legs)
	return body

## Build a resizable steel-grating mezzanine platform (#64). Like build_variable_belt,
## this returns a StaticBody3D root with geometry in LOCAL space; BuildMode adds it to
## the scene, positions it, and calls extend_machine_legs() on it. The SUPPORT POSTS are
## built spanning local y 0..BASE and tagged group "machine_leg" + meta "leg_h"=BASE, so
## the existing extend_machine_legs() lengthens them to the floor and hides any that would
## punch through another machine — we deliberately write NO pole/raycast logic here.
##   width/length : deck size in metres (clamped to [0.5, 10.0]).
##   ghost        : preview build → skip the collider; geometry + leg tagging kept.
static func build_grating_platform(width: float, length: float, ghost: bool) -> Node3D:
	const BASE : float = 0.15                  # deck top sits at local y = BASE
	width  = clampf(width,  0.5, 10.0)
	length = clampf(length, 0.5, 10.0)
	var body := StaticBody3D.new()
	body.name = "GratingPlatform"
	body.set_meta("placeable_id", "grating_platform")
	body.set_meta("gp_size", Vector2(width, length))
	body.add_to_group("placed_object")
	var model := Node3D.new()
	model.name = "Model"
	body.add_child(model)
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var hw : float = width * 0.5
	var hl : float = length * 0.5

	# Flat see-through grating DECK at y = BASE (thin box; UVs tiled to a constant cell).
	_grating_deck(model, width, length, Vector3(0.0, BASE, 0.0))

	# Perimeter EDGE FRAME — 4 thin steel beams around the rim at y = BASE.
	var fr : float = 0.06
	_box(model, Vector3(width, fr, fr), Vector3(0.0, BASE, -hl + fr * 0.5), steel)   # -Z
	_box(model, Vector3(width, fr, fr), Vector3(0.0, BASE,  hl - fr * 0.5), steel)   # +Z
	_box(model, Vector3(fr, fr, length), Vector3(-hw + fr * 0.5, BASE, 0.0), steel)  # -X
	_box(model, Vector3(fr, fr, length), Vector3( hw - fr * 0.5, BASE, 0.0), steel)  # +X

	# SUPPORT POSTS: 0.08 square, spanning local y 0..BASE, at the 4 corners AND along
	# each edge spaced ≤2.5 m. Tagged machine_leg (+ leg_h=BASE) so extend_machine_legs()
	# runs them to the floor + smart-hides blocked ones. Collected into a set of XZ
	# positions first so corners aren't double-placed.
	var post_w : float = 0.08
	var inset : float = post_w * 0.5 + 0.01            # keep posts just inside the rim
	var px : float = hw - inset
	var pz : float = hl - inset
	var nx : int = maxi(1, int(ceil((width  - 2.0 * inset) / 2.5)))   # spans → ≥1 segment
	var nz : int = maxi(1, int(ceil((length - 2.0 * inset) / 2.5)))
	var xs : Array[float] = []
	for i in nx + 1:
		xs.append(lerpf(-px, px, float(i) / float(nx)))
	var zs : Array[float] = []
	for j in nz + 1:
		zs.append(lerpf(-pz, pz, float(j) / float(nz)))
	# Place a post wherever it is on the PERIMETER (first/last row or column) — interior
	# is left open (a mezzanine is held at its edges, and open interior posts would just
	# get hidden by extend_machine_legs anyway if they hit machines below).
	for i in xs.size():
		for j in zs.size():
			var on_edge : bool = (i == 0 or i == xs.size() - 1 or j == 0 or j == zs.size() - 1)
			if not on_edge:
				continue
			var post := _box(model, Vector3(post_w, BASE, post_w),
				Vector3(xs[i], BASE * 0.5, zs[j]), steel)
			post.add_to_group("machine_leg")
			post.set_meta("leg_h", BASE)

	# WALKABLE collider — a thin slab whose TOP is flush with the deck (top at y=BASE).
	# Skipped on ghosts (preview has no collision). machine_leg tagging above is harmless
	# on a ghost, so we keep it for a faithful preview.
	if not ghost:
		var col := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(width, 0.10, length)
		col.shape = bx
		col.position = Vector3(0.0, BASE - 0.05, 0.0)
		body.add_child(col)
	return body

## Internal: build the visual mesh for a variable belt in LOCAL space — deck +
## side rails along +Z, end rollers, support legs, scrolling textured material.
static func _m_variable_belt(p: Node3D, length: float, _diff: Vector3, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var width : float = 0.92
	var deck_y : float = 0.20
	# Belt deck (scrolling textured material so the operator can see when it runs).
	var deck := _box(p, Vector3(width * 0.92, 0.05, length),
		Vector3(0.0, deck_y, length * 0.5), dark)
	if not ghost:
		deck.material_override = make_belt_material(0.5, Vector2(1.0, length * 0.5))
	# Side rails
	_box(p, Vector3(0.06, 0.18, length),
		Vector3( width * 0.46, deck_y + 0.10, length * 0.5), steel)
	_box(p, Vector3(0.06, 0.18, length),
		Vector3(-width * 0.46, deck_y + 0.10, length * 0.5), steel)
	# End rollers (cylinders along local X across the belt width).
	_cyl(p, 0.10, 0.10, width, Vector3(0.0, deck_y, 0.0), dark, "x")
	_cyl(p, 0.10, 0.10, width, Vector3(0.0, deck_y, length), dark, "x")
	# Drive motor at the top end.
	_motor_unit(p, 0.14, 0.30, Vector3(width * 0.50, deck_y + 0.06, length - 0.20), "x", ghost)
	# Support legs are intentionally skipped on this v1 model — the belt body is
	# rotated as a whole to span (start_y → end_y), so local-down legs would tilt
	# with it. Proper world-vertical legs need extra geometry; for now the deck
	# reads as a span and the bounding collider keeps the player + vehicles on it.

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
## Placeable ids whose visual is a conveyor belt — their walkable StaticBody3D is
## tagged into group "belt" with a "belt_speed" meta so the player controller can
## carry the player along the deck's local +Z (#59). Keep in sync with the belt
## builders in _build_model: _m_belt / _m_inclined_belt / _m_compactorband /
## _m_metal_belt / _m_scraper_conveyor. (variable_belt is tagged in build_variable_belt.)
const _BELT_IDS : Array[String] = [
	"transport_belt", "inclined_belt_8m", "compactorband", "metal_belt", "scraper_conveyor",
]
const _BELT_CARRY_SPEED : float = 0.4   # m/s along the belt deck's local +Z
# Single source of truth for intake transportband (1..12 + switch_belt) speed:
# the player carry speed AND the shader scroll value below both derive from
# this. Real CeDo intake belts run roughly 0.4–0.6 m/s; 0.5 m/s is the
# operator-confirmed middle. Previously the shader ran at apparent 1.2 m/s
# while the carry meta was never even set on intake belts (they weren't in
# _BELT_IDS) — visual lied, physics didn't fire at all.
const _INTAKE_BELT_SPEED_MPS : float = 0.5
# Shader scroll value passed to make_belt_material for intake belts. With the
# #140 fix below (make_belt_material no longer negates), positive caller value
# = downstream flow. *0.25 keeps the apparent slat march matching the carry
# meta (0.5 m/s) — the texture's internal slat period adds the missing factor.
const _INTAKE_BELT_SHADER_SCROLL : float = _INTAKE_BELT_SPEED_MPS * 0.25
const _RM_SCRIPT := preload("res://src/sim/RotatingMechanism.gd")
## `simple` builds a cheap LOD model for bales (single box + minimal wire bands)
## instead of the full ~10-sheet + 24-wire-segment model — used to fill bale
## yards (hundreds of bales) without thousands of draw calls. A simple bale is
## upgraded to full detail by detail_bale() the moment it's grabbed.
## Tag a freshly-built placeable so the rest of the game can find it:
## - stamps `placeable_id` so save/load + K-edit + delete know what it is
## - adds the `placed_object` group so the K-mode raycast resolver, the
##   save serialiser, and LineFlow's `_discover()` all see it
##
## EVERY early-return branch in `build_node()` MUST call this before returning,
## otherwise that placeable becomes "invisible" to the build pipeline. The
## `door_personnel`, `gate_roller`, and `window_frame` branches historically
## set the meta but not the group — silently breaking K-edit / delete on
## doors. Repeating the same two lines per branch is what allowed that bug
## to drift; consolidating here closes it.
##
## Returns `node` for fluent use: `return _finalize_placeable(node, id)`.
## No-op on a null node (ghost paths and missing-asset paths return null
## upstream).
static func _finalize_placeable(node: Node3D, id: String) -> Node3D:
	if node == null:
		return null
	node.set_meta("placeable_id", id)
	if not node.is_in_group("placed_object"):
		node.add_to_group("placed_object")
	return node

static func build_node(id: String, ghost: bool = false, simple: bool = false) -> Node3D:
	# Retired ids (see RETIRED_IDS) are dropped on purpose, with the REASON, so a
	# vanished object from an old save is never mistaken for a load bug.
	if is_retired(id):
		push_warning("[PlaceableCatalog] Retired placeable '%s' not built — %s" % [id, retired_reason(id)])
		return null
	var item := get_item(id)
	if item.is_empty():
		push_warning("[PlaceableCatalog] Unknown id: %s" % id)
		return null

	# Hand tools — spawn the real tool node (or a translucent box for the ghost). #28
	# Mirrors the opzetband fix at line ~786: tag placeable_id + placed_object so
	# BuildMode's K-edit / delete / save-load can find tools after placement.
	# Belt-carry tag + BeltSurface only attach if the catalog item actually marks
	# this tool as a belt (none currently do, but the guard keeps the path safe).
	# The "tool_" prefix is the legacy convention; newer hand-tool ids that
	# don't carry it (e.g. socket_wrench_7 / #210b) are routed explicitly.
	if id.begins_with("tool_") or id == "socket_wrench_7":
		var tn : Node3D = _build_tool(id, Vector3(item["size"]), ghost)
		if tn != null and not ghost:
			_finalize_placeable(tn, id)
			if bool(item.get("belt", false)):
				if not tn.is_in_group("belt"):
					tn.add_to_group("belt")
				var deck : StaticBody3D = tn.get_node_or_null("Deck") as StaticBody3D
				if deck != null and deck.get_node_or_null("BeltSurface") == null:
					var bs : Node = load("res://src/sim/BeltSurface.gd").new()
					bs.name = "BeltSurface"
					deck.add_child(bs)
		return tn
	# #116 — door / gate / window catalog placeables (NOT carved into a wall
	# here; the operator drops them into a pre-existing hole). Builders are
	# shared with the 4-point Surface tool, so behaviour + collision + paint
	# are identical to the Surface variants.
	if id == "door_personnel":
		if ghost:
			return _simple_ghost(Vector3(item["size"]))
		var sz : Vector3 = item["size"]
		# #194 — _finalize_placeable stamps the real catalog id so saves record
		# "door_personnel" (not the legacy generic "surface" that was un-routable
		# on reload) AND adds the placed_object group so K-edit / delete work.
		return _finalize_placeable(build_door(sz.x, sz.y, sz.z, "Door"), "door_personnel")
	if id == "gate_roller":
		if ghost:
			return _simple_ghost(Vector3(item["size"]))
		var gsz : Vector3 = item["size"]
		# anchor_base: BuildMode places a catalog gate at the wall hit point, which
		# is the BOTTOM of the cut, not its middle.
		return _finalize_placeable(build_gate(gsz.x, gsz.y, "Gate", true), "gate_roller")
	if id == "window_frame":
		if ghost:
			return _simple_ghost(Vector3(item["size"]))
		var wsz : Vector3 = item["size"]
		return _finalize_placeable(build_window(wsz.x, wsz.y, "Window"), "window_frame")
	# X2/#181 — Vehicles. The ghost is a translucent box (cheap); the real
	# placement instantiates the scene so the operator gets a fully-driveable
	# unit on the floor. Used for QA spawns — no need to walk to find a Merlo.
	if id.begins_with("vehicle_"):
		if ghost:
			return _simple_ghost(Vector3(item["size"]))
		var scene_path : String = String(item.get("scene", ""))
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			push_warning("[PlaceableCatalog] Vehicle scene missing: %s" % scene_path)
			return _simple_ghost(Vector3(item["size"]))
		var packed := load(scene_path) as PackedScene
		if packed == null:
			return _simple_ghost(Vector3(item["size"]))
		var v : Node3D = packed.instantiate() as Node3D
		if v == null:
			return null
		return _finalize_placeable(v, id)
	# Shift-leader PC + QA bench — each is a self-contained StaticBody3D with its
	# own model + collision + interaction trigger. Build the script-backed node
	# directly and tag it as a placeable so save/load + delete handle it like any
	# other placed object. Ghost preview falls back to a translucent box because
	# instantiating + tearing down the full body per cursor move is wasteful.
	if id == "shift_leader_desk" or id == "qa_bench":
		if ghost:
			return _simple_ghost(Vector3(item["size"]))
		var script_path : String = "res://src/scenes/world/ShiftLeaderDesk.gd" \
			if id == "shift_leader_desk" else "res://src/scenes/world/QualityAnalysisBench.gd"
		# Renamed from `body` — the outer build_node() reuses that name later for
		# the generic PhysicsBody3D path; CONFUSABLE_LOCAL_DECLARATION fired here.
		var desk_body : Node3D = load(script_path).new()
		return _finalize_placeable(desk_body, id)
	# Bale stack — a 5x5 footprint stacked to the origin's allowance. #33
	if id.ends_with("_stack5"):
		return _build_bale_stack(id.trim_suffix("_stack5"), ghost)
	# Collection zone for the leaf blower (just an Area3D; ghost is a flat translucent slab).
	# D4 fix (mirrors the opzetband patch ~line 802): tag the returned node
	# with placeable_id + placed_object group BEFORE returning, otherwise
	# BuildMode's K-edit / delete / save-load pipelines can't see the zone.
	# Not a belt — no group("belt") or BeltSurface attachment needed.
	if id == "zone_collection":
		var cz : Node3D = _build_collection_zone(Vector3(item["size"]), ghost)
		if cz != null and not ghost:
			_finalize_placeable(cz, id)
		return cz
	# Test pile of loose film scraps (so the operator can practice blowing them around).
	# D4 fix (mirrors opzetband / zone_collection pattern): tag the returned
	# node with placeable_id + placed_object group BEFORE returning, otherwise
	# BuildMode's K-edit / delete / save-load pipelines can't see the pile at
	# all (the early return skipped the generic body's tagging at line ~895).
	# Not a belt — no group("belt") or BeltSurface attachment needed.
	if id == "film_scrap_pile":
		var pile : Node3D = _build_scrap_pile(Vector3(item["size"]), ghost)
		if pile != null and not ghost:
			_finalize_placeable(pile, id)
		return pile
	# Opzetbanden — feed-belt variants per operator spec (4 specific geometries).
	# D4 fix: tag the returned node with placeable_id + placed_object group
	# BEFORE returning. Without these, BuildMode's K-edit / delete / save-load
	# pipelines can't see the opzetband at all (the early return skipped the
	# generic body's tagging at line ~895). Also attach a BeltSurface so dropped
	# material is physically carried.
	if id == "opzetband_3a3b" or id == "opzetband_3c6" or id == "westa_band_1" or id == "opzetband_1":
		var op : Node3D = _build_opzetband(id, Vector3(item["size"]), ghost)
		if op != null and not ghost:
			_finalize_placeable(op, id)
			# Light belt carry tag so the legacy belt-carry fallback in
			# PlayerController.gd:249 also drags the operator. Real belt
			# surfaces are inside the opzetband sub-tree (deck StaticBody3D).
			if not op.is_in_group("belt"):
				op.add_to_group("belt")
			# #conveyorphysics — attach BeltSurface to the deck StaticBody3D
			# inside the opzetband sub-tree so RigidBody3Ds dropped on the belt
			# get dragged by constant_linear_velocity (same treatment as the
			# generic belt path at ~line 867-877). The deck is exposed by the
			# ShredderFeedBelt script as `_belt_body`. Skip if already scripted.
			#
			# #172-opzetband — DO NOT use the generic _BELT_CARRY_SPEED (0.4 m/s)
			# here: opzetband is a portion-feeder ramp tuned to a slow creep
			# (ShredderFeedBelt.belt_speed = 0.12 m/s per operator). The previous
			# override was ~3.3× too fast and the player was getting dragged at
			# transport-belt speed while the slat shader scrolled at the creep
			# speed — visual lied, physics lied differently, three sources of
			# truth. Read the live belt_speed off the ShredderFeedBelt so the
			# BeltSurface physical carry, the legacy meta, the rider-bale travel,
			# and the shader scroll all come from a single number.
			var deck_body : StaticBody3D = op.get("_belt_body") as StaticBody3D
			if deck_body != null and is_instance_valid(deck_body) and deck_body.get_script() == null:
				var belt_script_op : Resource = load("res://src/sim/BeltSurface.gd")
				if belt_script_op != null:
					var op_speed : float = float(op.get("belt_speed"))
					deck_body.set_script(belt_script_op)
					deck_body.set("belt_speed_mps", op_speed)
					# #214 — ShredderFeedBelt drives the setpoint through its OWN
					# 2.5 s outer ramp (see _belt_speed_smooth) and writes the
					# already-ramped live_speed into this body's belt_speed_mps each
					# tick. So the inner BeltSurface low-pass needs only a very
					# short tau to track that live signal without double-smoothing
					# (which would add a visible second-order lag).
					deck_body.set("belt_ramp_tau_s", 0.1)
					deck_body.add_to_group("belt")
					deck_body.set_meta("belt_speed", op_speed)
					deck_body.set_meta("belt_ramp_tau_s", 0.1)
			# D4 fix: node is tagged + group before returning.
		return op

	var size: Vector3 = item["size"]
	var color: Color  = item["color"]
	var category := String(item["category"])

	# Bales are dynamic (stack physics: lift the bottom of a 3-stack with strong
	# clamp force and you take all three; misalignment shifts COM and they tip).
	# Control-category placeables (HMI panels) get an Hmi.gd script attached so
	# the player can interact with them — proximity prompt + UI overlay.
	# Everything else is a plain StaticBody3D (machines / surfaces don't move).
	var body : PhysicsBody3D
	if id == "silo_level_sensor":
		# Operator-anecdote mechanic (#A3). Attach SiloLevelSensor.gd so the body
		# exposes the bridge toggle + level read; upstream feed scripts call
		# wants_throttle() to decide whether to clamp output.
		#
		# MUST BE TESTED BEFORE the `category == "Control"` arm below, not after.
		# This entry's category IS "Control" (see its row in items()), so while the
		# id test sat lower in the chain it was UNREACHABLE and this line was dead:
		# `:1407` was the only instantiation of SiloLevelSensor.gd in the repo, so
		# LineFlow's `get_nodes_in_group("silo_level_sensor")` lookup was
		# permanently empty and #A3 had never run in any build. TagMap.gd:60
		# already recorded the downstream symptom ("current_level_pct IS A DEAD
		# SOURCE") without anyone tracing it back to this ordering.
		body = load("res://src/sim/SiloLevelSensor.gd").new()
	elif category == "Control":
		body = load("res://src/build/Hmi.gd").new()
	elif id == "waste_container" or id == "skip_steel" or id == "fines_bin" or id == "cyclone_bin" or id == "ibc_tote":
		# Real physical buffer entity — has capacity / density / overflow state,
		# accepts only its configured stream class(es), routes spillover to the
		# nearest floor pile. See src/sim/WasteContainer.gd for the model.
		body = load("res://src/sim/WasteContainer.gd").new()
	elif id == "wardrobe_locker":
		# #154 — wardrobe locker: StaticBody3D with a script that exposes
		# crosshair_prompt + crosshair_interact, opening the customizer (#153)
		# on E.
		body = load("res://src/build/WardrobeLocker.gd").new()
	elif id == "shredder_1" or id == "shredder_2":
		# Coarse/fine shredder sim brain (ShredderMachine.gd): throughput physics
		# (feed→shred capped at rated, motor load, overfeed buffer + overload trip),
		# relay-panel states (key I/II/III · start · e-stop), rotor-spin gating, and
		# the SWI open/clean/block-rotor procedures as crosshair interactions. Slots
		# in as a StaticBody3D so the model + leg/collision/group plumbing keep working.
		body = load("res://src/sim/ShredderMachine.gd").new()
	elif id == "laser_filter":
		# Rotary-disc melt filter. The script (LaserFilter.gd) holds ΔP /
		# scraper-RPM / screen-thickness state and exposes the multi-step
		# filter-change procedure as a crosshair interaction. It still
		# slots in as a StaticBody3D so the rest of the catalog's leg /
		# collision / group plumbing keeps working unchanged.
		body = load("res://src/sim/LaserFilter.gd").new()
	elif id == "kopfilter":
		# Slide-plate head-filter screen-changer. HeadFilter.gd models two
		# screen-pack cavities (online + offline), monotonically-rising ΔP
		# on the online cavity (no self-clean), and the two operator
		# procedures: SWAP (~5 s line dip) and REPACK (no line dip).
		body = load("res://src/sim/HeadFilter.gd").new()
	elif id == "lump_cart":
		# #98 — Real-life mass ~40 kg. Operator can either shove it by walking
		# into it (slow at this weight), or grab the handle (crosshair + E) for
		# active steering via LumpCart.gd — the script velocity-targets the
		# handle to a point in front of the player and yaws the cart to match
		# their facing. Friction stays high so it doesn't drift after release.
		var rb_cart : RigidBody3D = load("res://src/sim/LumpCart.gd").new()
		# #223 audit: one source of truth for empty-cart mass. LumpCart._sync_mass
		# sets mass = EMPTY_MASS_KG + lumps_kg; at spawn lumps_kg=0 → EMPTY_MASS_KG.
		rb_cart.call("_sync_mass")
		rb_cart.linear_damp = 0.9
		rb_cart.angular_damp = 3.0
		rb_cart.can_sleep = true
		var pm_cart := PhysicsMaterial.new()
		pm_cart.friction = 0.9
		pm_cart.bounce = 0.02
		rb_cart.physics_material_override = pm_cart
		# Pin the centre of mass LOW + CENTRED so the cart rests stably and
		# settles deterministically regardless of the compound collision layout
		# (the fork-pocket rework shifted the auto-computed CoM and made the cart
		# roll a little on spawn → save/reload drift). A real cart's mass is in its
		# base/wheels anyway.
		rb_cart.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		rb_cart.center_of_mass = Vector3(0.0, 0.18, 0.0)   # just above the underframe
		# #198 — tag so NpcAutonomyBoard's lump-cart scanner finds this cart.
		rb_cart.add_to_group("lump_cart")
		body = rb_cart
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
	# #165 — Control category placeables (HMI panels) carry a scope id so the
	# Hmi.gd interaction script and HmiOverlay can look up which subset of the
	# plant this physical panel governs. Every buildable HMI carries one — the
	# generic see-all scope died with the retired `hmi_panel` / `hmi_wall` ids.
	if category == "Control" and item.has("hmi_id"):
		body.set_meta("hmi_id", String(item["hmi_id"]))

	# Belt-type placeables: tag the walkable StaticBody3D so the player controller
	# carries the player along the deck's local +Z when standing on it (#59). Only
	# belts get this — non-belt machines stay solid ground. Intake transportbands
	# (1..12) and the switch belt run a different m/s than the generic belts and
	# are detected by id prefix so we don't have to list all 13 explicitly.
	var _is_intake : bool = id.begins_with("transportband_") or id == "switch_belt"
	if not ghost and (id in _BELT_IDS or _is_intake):
		body.add_to_group("belt")
		var carry : float = _INTAKE_BELT_SPEED_MPS if _is_intake else _BELT_CARRY_SPEED
		body.set_meta("belt_speed", carry)
		# #214 belt-speed ramp — per-belt coast-down time-constant. Heavy intake
		# belts (the C3 climb from the U-bay and similar lift conveyors with
		# loaded inclines + drive motor inertia) coast for ~2.5 s; light flat
		# transfer belts coast for ~1.5 s. Tuned so the player + bales + lump
		# cart resting on a belt slow visibly instead of teleport-freezing when
		# the cascade-stop signal flips the setpoint to 0. BeltSurface reads
		# this meta in _ready() and uses it as its low-pass tau.
		var _is_heavy_intake : bool = (id == "transportband_3" or id == "transportband_5" or id == "transportband_11")
		var ramp_tau : float = 2.5 if _is_heavy_intake else 1.5
		body.set_meta("belt_ramp_tau_s", ramp_tau)
		# #conveyorphysics — attach BeltSurface so Godot's built-in
		# StaticBody3D.constant_linear_velocity actually drags any RigidBody3D
		# (bales, lump_cart, dropped tools) sitting on the deck. Previously the
		# belt visual moved but the surface was physically static; only the
		# player carry hack masked that. The script refreshes the surface
		# velocity from the body's live transform each tick, so a yawed belt
		# carries rigid bodies in the right world direction.
		var belt_script : Resource = load("res://src/sim/BeltSurface.gd")
		if belt_script != null:
			body.set_script(belt_script)
			body.set("belt_speed_mps", carry)
			body.set("belt_ramp_tau_s", ramp_tau)

	# Composite procedural model (base sits at the local origin), not a plain box.
	var model := Node3D.new()
	model.name = "Model"
	body.add_child(model)
	if category == "Bales" and simple and not ghost:
		# LOD: cheap yard-fill bale. Marked so detail_bale() can upgrade it to the
		# full sheet/wire model when the player grabs it.
		_m_bale_simple(model, id, size, color, ghost)
		body.set_meta("simple_bale", true)
	else:
		_build_model(model, id, category, size, color, ghost)
		# #224 — STATIC-MERGE: bake the machine's static parts into one mesh per
		# material look so it renders in a few draw calls instead of one-per-part
		# (#221 perf; enables adding detail without tanking the framerate). Rotors /
		# HMI / comp-tagged / particles / scripted parts stay separate & keep
		# working. Ghosts skip it; opt out per-model via set_meta("no_merge", true).
		if not ghost and category != "Bales":
			StaticMerge.merge_static(model)

	if not ghost:
		# Floor-paint placeables (lump_cart_spot, etc.) are purely visual — skip
		# collision so wheels/carts don't ride up on the paint stripe.
		# stairs skip the generic full-size AABB collider — that solid box filled the
		# whole flight and made it impassable, and it hid the per-tread StaticBody
		# colliders _m_stairs builds (bughunt 2026-07-17). Walk on the treads instead.
		var skip_collision : bool = id == "lump_cart_spot" or id == "stairs"
		if not skip_collision:
			if id == "lump_cart":
				# #201 — operator spec: the cart's underframe has TWO 150 × 80 mm
				# fork pockets (left + right) running the full length so a forklift
				# enters from either short end. A single AABB box can't model a
				# hole, so build the collision as a compound: 3 underframe strips
				# (outer-left | between-pockets | outer-right), the cart floor, 4
				# walls, and 4 corner posts. Forks slide into the cavities; the
				# spreader widens from 0.20 m centerline to clamp the outer pocket
				# walls. NOTHING is parented under the fork — pure contact physics.
				_lump_cart_compound_collision(body, size)
			elif id == "extruder_silo":
				# The silo body sits ~2.6 m up on 4 legs with open walk-under
				# clearance. A generic AABB filled that clearance solid (couldn't
				# pass under it); build legs + raised-body collision instead so the
				# operator can walk under and park a discharge cart (bughunt
				# 2026-07-17).
				_extruder_silo_compound_collision(body, size)
			else:
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

		# Tag the bale with its feedstock origin (BaleClamp etc. still read this).
		if category == "Bales":
			body.set_meta("material_origin", id)
			body.add_to_group("bale")
			# Realistic paper shipping label on one side face. Position cycles
			# per bale so the sticker doesn't always end up in the same spot —
			# the operator has to walk around the stack to find it. The card
			# has printed text + a barcode (drawn flat on the surface, NO
			# floating billboards), and the BarcodeScanner reads label_info
			# off it.
			if not ghost:
				# Per-bale weight jitter ±50 kg so no two labels read identically
				# (real bales vary with fill/moisture). Seeded off the running
				# label sequence so each spawned bale gets its own value but it
				# stays fixed once built.
				var jitter_rng := RandomNumberGenerator.new()
				jitter_rng.seed = hash(id) + _bale_label_seq * 7919
				var weight_kg : int = int(round(BaleDefs.estimated_weight(size))) \
					+ jitter_rng.randi_range(-50, 50)
				var info := {
					"item":       String(item["name"]),
					"origin":     id,
					"weight_kg":  weight_kg,
					"batch":      "B-%05d" % (jitter_rng.randi() % 100000),
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
					2:   # right (+X) — card front (+Z local) must face +X (outward)
						label_pos   = Vector3(size.x * 0.5 + eps, ly, 0.0)
						label_basis = Basis(Vector3.UP, PI * 0.5)
					_:   # left (-X) — card front must face -X (outward)
						label_pos   = Vector3(-size.x * 0.5 - eps, ly, 0.0)
						label_basis = Basis(Vector3.UP, -PI * 0.5)
				var label_item_script := preload("res://src/scenes/world/LabelItem.gd")
				label_item_script.attach_to(body, info, label_pos, label_basis)
		# Floating billboard Label3D + yellow shipping label sticker REMOVED for
		# bales per operator: real bales have no floating text and the yellow
		# barcode sticker is the wrong colour/size to look realistic — both have
		# to be re-done as a true paper-style sticker before being added back.
		# Non-bale placeables keep the small floating name label so build-mode
		# users can still tell what they placed — UNLESS emit_name_labels is off
		# (immersive contexts like the extruder bench).
		if category != "Bales" and emit_name_labels:
			var label := Label3D.new()
			label.text = String(item["name"])
			label.position = Vector3(0.0, size.y + 0.45, 0.0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.fixed_size = false
			label.font_size = 48
			label.outline_size = 8
			label.modulate = Color.WHITE
			body.add_child(label)

		# Sim brain. Some placeables are not just geometry: an extruder owns an
		# ExtruderModel, joins the "extruder_machine" group the HMI enumerates,
		# and drives the vacuum cascade. Before this hook nothing in a configured
		# world ever created one — see MachineBrains.gd for the measurement.
		# We are already inside `if not ghost`, so ghosts never get a brain, and
		# attach() is idempotent so rebuild_in_place() cannot stack two.
		MachineBrains.attach(body, id, size)

	return body

# =============================================================================
# DETAILED MACHINE MODELS  (composite primitives, base at the local origin)
# =============================================================================
const _STEEL : Color = Color(0.60, 0.63, 0.67)
const _DARK  : Color = Color(0.24, 0.25, 0.28)
# Photo-calibrated safety yellow from assets/reference_photos/building/
# yellow_ladders_railings_lines.png (handrails) and _wooden_V_shape_support_beams.png
# (caution cage). Slightly more saturated than the previous (0.86, 0.70, 0.16);
# the real CeDo paint reads as a vivid green-leaning industrial yellow, not the
# orange-leaning amber the old value gave.
const _SAFETY: Color = Color(0.94, 0.78, 0.14)

static func _build_model(p: Node3D, id: String, category: String, size: Vector3, color: Color, ghost: bool) -> void:
	# #165 — the 12 scoped HMI ids ("hmi_shredder_l1" etc.) route to the mesh
	# chosen by their catalog `mesh` field ("hmi_panel" stand or "hmi_wall"
	# wall). `mesh` is a GEOMETRY key, not a placeable id — the placeables that
	# once carried those two ids are retired (RETIRED_IDS) and can never reach
	# here, so no id exclusions are needed.
	if category == "Control" and id.begins_with("hmi_"):
		var hmi_item := get_item(id)
		var mesh_key := String(hmi_item.get("mesh", "hmi_panel"))
		if mesh_key == "hmi_wall":
			_m_hmi_wall(p, size, color, ghost)
		else:
			_m_hmi(p, size, color, ghost)
		return
	match id:
		"silo":           _m_silo(p, size, color, ghost)
		"extruder_silo":  _m_extruder_silo(p, size, color, ghost)
		"lump_cart":      _m_lump_cart(p, size, color, ghost)
		"lump_cart_spot": _m_lump_cart_spot(p, size, color, ghost)
		"lump_platform":  _m_lump_platform(p, size, color, ghost)
		"wardrobe_locker": _m_wardrobe_locker(p, size, color, ghost)
		"doseersilo":     _m_doseersilo(p, size, color, ghost)
		"transport_belt": _m_belt(p, size, color, ghost)
		"cyclone":        _m_cyclone(p, size, color, ghost)
		"cyclone_tower":  _m_cyclone_tower(p, size, color, ghost)
		"funnel":         _m_funnel(p, size, color, ghost)
		"transfer_chute": _m_chute(p, size, color, ghost)
		"blower":         _m_blower(p, size, color, ghost)
		"centrifuge":     _m_centrifuge(p, size, color, ghost)
		# wash_line catalog id removed — see comment at the catalog entry
		"mech_dryer":     _m_dryer(p, size, color, ghost)
		"pcu_cabinet":    _m_cabinet(p, size, color, ghost)
		"door":           _m_door(p, size, color, ghost)
		"mill":           _m_mill(p, size, color, ghost)
		"flotation_tank": _m_flotation(p, size, color, ghost, false)
		"flotation_tank_wide": _m_flotation(p, size, color, ghost, true)
		"sink_float":     _m_sinkfloat(p, size, color, ghost)
		"friction_sep":   _m_friction(p, size, color, ghost)
		"dewater_screw":  _m_dewater(p, size, color, ghost)
		"water_pump":     _m_pump(p, size, color, ghost)
		# pump_large / waterpomp / ringleiding_3a removed — see comments at
		# their (formerly) catalog entries. water_pump + ringleiding are the
		# canonical singletons.
		# Named pump stations (2026-07-06): _m_pump + stencil station label —
		# the flotation_tank/_wide shared-builder precedent (water_small.md §3/§4).
		"pomp_c1":        _m_pump_labeled(p, size, color, ghost, "C1")
		"pomp_zeefbocht": _m_pump_labeled(p, size, color, ghost, "ZEEFBOCHT")
		"compactor_belt": _m_compactor_belt(p, size, color, ghost)
		# (no "hmi_panel" / "hmi_wall" arms — those placeable ids are retired.
		#  The 12 scoped panels are dispatched by the `mesh` key above.)
		"vuilsnippersilo":_m_vuilsnippersilo(p, size, color, ghost)
		"friction_washer":_m_friction_washer(p, size, color, ghost)
		"intensive_washer":_m_intensive_washer(p, size, color, ghost)
		"rafter":         _m_rafter(p, size, color, ghost)
		"trilzeef":       _m_trilzeef(p, size, color, ghost)
		"transport_screw":_m_transport_screw(p, size, color, ghost)
		"mas_bak":        _m_mas_bak(p, size, color, ghost)
		"compactor":      _m_compactor(p, size, color, ghost)
		"cutter_compactor": _m_compactor(p, size, color, ghost)
		"waste_container":_m_waste_container(p, size, color, ghost)
		"skip_steel":     _m_steel_skip(p, size, color, ghost)
		"fines_bin":      _m_fines_bin(p, size, color, ghost)
		"cyclone_bin":    _m_cyclone_bin(p, size, color, ghost)
		"ibc_tote":       _m_ibc_tote(p, size, color, ghost)
		"concrete_bay":   _m_concrete_bay(p, size, color, ghost)
		"bunker":         _m_bunker(p, size, color, ghost)
		"shredder_1":     _m_shredder_1(p, size, color, ghost)
		"shredder_2":     _m_shredder_2(p, size, color, ghost)
		"inclined_belt_8m":_m_inclined_belt(p, size, color, ghost)
		"feed_hopper":    _m_feed_hopper(p, size, color, ghost)
		# #54 intake conveyor network — 12 distinct belts + diverter + buffers.
		"transportband_1", "transportband_2", "transportband_3", "transportband_4", \
		"transportband_5", "transportband_6", "transportband_7", "transportband_8", "transportband_8_5", \
		"transportband_9", "transportband_10", "transportband_11", "transportband_12":
			_m_intake_belt(p, id, size, color, ghost)
		"switch_belt":    _m_switch_belt(p, size, color, ghost)
		"vss_silo":       _m_vss_silo(p, size, color, ghost)
		"u_bay":          _m_u_bay(p, size, color, ghost)
		"sga_drum":       _m_sga_drum(p, size, color, ghost)
		"metal_belt":     _m_metal_belt(p, size, color, ghost)
		"ballistic_sep":  _m_ballistic(p, size, color, ghost)
		"wind_sifter":    _m_windsifter(p, size, color, ghost)
		"titech_sort", "tomra_sort": _m_nir_sorter(p, size, color, ghost)
		"prewash_drum":   _m_prewash_drum(p, size, color, ghost)
		"kufferath_sieve":_m_kufferath(p, size, color, ghost)
		"mengsilo":       _m_mengsilo(p, size, color, ghost)
		"zss_water":      _m_zss_water(p, size, color, ghost)
		# Small water fixtures 2026-07-06 (water_small.md §1/§2) — role "none",
		# never enter LineFlow / the HMI.
		"kleine_la":               _m_kleine_la(p, size, color, ghost)
		"heater_cabinet":          _m_heater_cabinet(p, size, color, ghost)
		"tankje_tussen_extruders": _m_tankje_extruders(p, size, color, ghost)
		# ── Hoses & Air (visual placeables, do NOT enter LineFlow / the HMI) ──
		"reel_water_thick_yellow": _m_hose_reel(p, size, color, ghost, 0.045)
		"reel_water_black":        _m_hose_reel(p, size, color, ghost, 0.025)
		"reel_fire_red":           _m_hose_reel(p, size, color, ghost, 0.028)
		"hook_air_hose":           _m_air_hose_hook(p, size, ghost)
		"washer_hp_mobile":        _m_washer_hp_mobile(p, size, ghost)
		"compressor_a":            _m_compressor_a(p, size, color, ghost)
		"compressor_b":            _m_compressor_b(p, size, color, ghost)
		"vacuum_unit":             _m_vacuum_unit(p, size, color, ghost)
		"vacuum_pump":             _m_vacuum_pump(p, size, color, ghost)
		"dirt_hotspot":            _m_dirt_hotspot(p, size, color, ghost)
		"pole_single":             _m_pole_single(p, size, ghost)
		"pole_double":             _m_pole_double(p, size, ghost)
		"pole_a_frame":            _m_pole_a_frame(p, size, ghost)
		# ── Platforms (grating_platform is special-cased by BuildMode, not here) ──
		"stairs":                  _m_stairs(p, size, color, ghost)
		"guardrail":               _m_guardrail(p, size, color, ghost)
		"plasmaq":        _m_plasmaq(p, size, color, ghost)
		"laser_filter":   _m_laser_filter(p, size, color, ghost)
		"melt_pump":      _m_melt_pump(p, size, color, ghost)
		"overband_magnet":_m_overband_magnet(p, size, color, ghost)
		"scraper_conveyor":_m_scraper_conveyor(p, size, color, ghost)
		"verdeelwals":    _m_verdeelwals(p, size, color, ghost)
		"ringleiding":    _m_ringleiding(p, size, color, ghost)
		"ringleiding_3a": _m_ringleiding_3a(p, size, color, ghost)
		"thermal_dryer":  _m_thermal_dryer(p, size, color, ghost)
		"thermal_dryer_decommissioned": _m_thermal_dryer_decommissioned(p, size, color, ghost)
		# ── Line 3C extruder back-end (#175) ──────────────────────────────────
		"compactorband":  _m_compactorband(p, size, color, ghost)
		"extruder": _m_extruder_unit(p, size, color, ghost)
		# 3C's screw entry is ONLY the barrel section — the PCU (compactor,
		# idx 21), kopfilter (26), vacuum_degas (24) and melt_pump (25) are
		# STANDALONE machines in LINE_3C_SEQ. Routing this id through the
		# full unit builder doubled all of them in miniature (doc-walk
		# follow-on to gap 1.3, verified 2026-08-28). The purpose-built
		# barrel-only _m_extruder_screw had existed UNDISPATCHED all along —
		# orphaned-model disease case #4 (after sga_drum, vw_trommel and the
		# fixed-equipment water blocks).
		"extruder_screw": _m_extruder_screw(p, size, color, ghost)
		"vacuum_degas":   _m_vacuum_degas(p, size, color, ghost)
		"kopfilter":      _m_kopfilter(p, size, color, ghost)
		"heetafslag":     _m_heetafslag(p, size, color, ghost)
		"ontwaterzeef":   _m_ontwaterzeef(p, size, color, ghost)
		"weegschaal":     _m_weegschaal(p, size, color, ghost)
		"bigbag_station": _m_bigbag_station(p, size, color, ghost)
		"voorraad_silo":  _m_silo(p, size, color, ghost)
		# Outdoor MS/LS pellet silos + EOP endpoint (2026-07-06 batch).
		"ms_silo_buiten": _m_silo_buiten(p, size, color, ghost, "ms")
		"ls_silo_buiten": _m_silo_buiten(p, size, color, ghost, "ls")
		"eop_endpoint":   _m_eop_endpoint(p, size, color, ghost)
		# ── Line 1 machines (#62) ─────────────────────────────────────────────
		"metaaldetector": _m_metaaldetector(p, size, color, ghost)
		"vw_trommel":     _m_vw_trommel(p, size, color, ghost)
		"scheidingsgoot": _m_scheidingsgoot(p, size, color, ghost)
		"sga_feed_chute": _m_sga_feed_chute(p, size, color, ghost)
		"mas_droger":     _m_mas_droger(p, size, color, ghost)
		# ── Consolidated single-model extruder unit (#92): feed tower → barrel →
		#    C-2 laser-filter → twin filter modules → meltpump → Wave-Cut pelletizer ─
		"extruder_3a": _m_extruder_unit(p, size, color, ghost, "3A")   # #223 docs->code: line-only barrel stencil
		"extruder_3b": _m_extruder_unit(p, size, color, ghost, "3B")
		"extruder_1":  _m_extruder_unit(p, size, color, ghost, "1")
		"extruder_3c": _m_extruder_unit(p, size, color, ghost, "3C")
		"extruder_6":  _m_extruder_unit(p, size, color, ghost, "6")
		# ── #212 Decals (yellow hazard placards) ──────────────────────────────
		"hazard_moving", "hazard_overhead", "hazard_hightemp", \
		"hazard_hardhat", "hazard_piralchute", "hazard_platformmaxload":
			_m_hazard_decal(p, id, size, color, ghost)
		# ── #212 Environment placeables ──────────────────────────────────────
		"overhead_crane":       _m_overhead_crane(p, size, color, ghost)
		"fire_riser":           _m_fire_riser(p, size, color, ghost)
		"fire_extinguisher":    _m_fire_extinguisher(p, size, color, ghost)
		"drainage_grating":     _m_drainage_grating(p, size, color, ghost)
		"scissor_lift":         _m_scissor_lift(p, size, color, ghost)
		"riveted_steel_column": _m_riveted_steel_column(p, size, color, ghost)
		"concrete_v_beam":      _m_concrete_v_beam(p, size, color, ghost)
		_:
			match category:
				"Extruders": _m_extruder_unit(p, size, color, ghost)
				"Shredders": _m_shredder_1(p, size, color, ghost)
				"Bales":     _m_bale(p, id, size, ghost)
				_:           _box(p, size, Vector3(0.0, size.y * 0.5, 0.0), _mat(color, ghost))

# ── primitive helpers ───────────────────────────────────────────────────────
# ── Belt textures (#texturedbelts) ────────────────────────────────────────────
## Procedurally-generated rubber-slat belt texture: a 64×128 image of repeating
## horizontal dark/light bands, sampled per-belt-surface and SCROLLED via the
## belt_scroll.gdshader so a running belt visibly moves. Cached statically so
## every belt instance shares the same GPU texture.
static var _belt_albedo_tex   : ImageTexture = null
static var _belt_roughness_tex: ImageTexture = null
static var _belt_normal_tex   : ImageTexture = null
static var _belt_shader_res   : Shader = null

const _BELT_SLAT_PERIOD : int = 16    # px between slats
const _BELT_SLAT_BAND   : int = 3     # px-thick slat band
const _BELT_TEX_W       : int = 64
const _BELT_TEX_H       : int = 128

static func _belt_albedo_texture() -> ImageTexture:
	if _belt_albedo_tex != null:
		return _belt_albedo_tex
	var img := Image.create(_BELT_TEX_W, _BELT_TEX_H, false, Image.FORMAT_RGB8)
	for y in _BELT_TEX_H:
		var is_slat : bool = (y % _BELT_SLAT_PERIOD) < _BELT_SLAT_BAND
		var base : Color = Color(0.20, 0.20, 0.21) if is_slat else Color(0.085, 0.085, 0.09)
		# A faint highlight on the very first row of each slat picks out the leading edge
		# under work-lights, which sells the "ridged rubber" read.
		if is_slat and (y % _BELT_SLAT_PERIOD) == 0:
			base = Color(0.30, 0.30, 0.32)
		for x in _BELT_TEX_W:
			# Tiny per-pixel speckle so the surface isn't flat-color clean.
			var n := (float((x * 17 + y * 31) % 11) / 11.0 - 0.5) * 0.020
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n))
	_belt_albedo_tex = ImageTexture.create_from_image(img)
	return _belt_albedo_tex

static func _belt_roughness_texture() -> ImageTexture:
	if _belt_roughness_tex != null:
		return _belt_roughness_tex
	var img := Image.create(_BELT_TEX_W, _BELT_TEX_H, false, Image.FORMAT_RGB8)
	for y in _BELT_TEX_H:
		var is_slat : bool = (y % _BELT_SLAT_PERIOD) < _BELT_SLAT_BAND
		# Slats catch the light a bit more (lower roughness); webs are matte.
		var r : float = 0.60 if is_slat else 0.92
		for x in _BELT_TEX_W:
			img.set_pixel(x, y, Color(r, r, r))
	_belt_roughness_tex = ImageTexture.create_from_image(img)
	return _belt_roughness_tex

## Normal map approximating the slat ridges — leading edge faces +Z (light hits
## it brighter when scrolling toward the camera). RGB encodes the tangent-space
## normal: 0.5 = neutral; >0.5 in green channel = +Z tilt.
static func _belt_normal_texture() -> ImageTexture:
	if _belt_normal_tex != null:
		return _belt_normal_tex
	var img := Image.create(_BELT_TEX_W, _BELT_TEX_H, false, Image.FORMAT_RGB8)
	for y in _BELT_TEX_H:
		var phase : int = y % _BELT_SLAT_PERIOD
		var ny : float = 0.5
		if phase < _BELT_SLAT_BAND:
			# Leading face: tilt up in V (away from belt direction).
			ny = 0.5 + 0.25 * (1.0 - float(phase) / float(_BELT_SLAT_BAND))
		elif phase >= _BELT_SLAT_PERIOD - _BELT_SLAT_BAND:
			# Trailing face: tilt down.
			ny = 0.5 - 0.25 * (1.0 - float(_BELT_SLAT_PERIOD - 1 - phase) / float(_BELT_SLAT_BAND))
		for x in _BELT_TEX_W:
			img.set_pixel(x, y, Color(0.5, ny, 1.0))
	_belt_normal_tex = ImageTexture.create_from_image(img)
	return _belt_normal_tex

## Build a ShaderMaterial set up for a scrolling textured belt. `scroll_speed`
## is signed — positive = forward, negative = reverse; 0 = stopped. `tile.y` is
## the texture repeats along the belt's length axis (set roughly to belt length
## / texture height ≈ length_m × 2 so a 5 m belt has ~10 slat-spacings visible).
static func make_belt_material(scroll_speed: float = 0.8,
		tile: Vector2 = Vector2(1.0, 5.0)) -> ShaderMaterial:
	if _belt_shader_res == null:
		_belt_shader_res = load("res://src/build/belt_scroll.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _belt_shader_res
	m.set_shader_parameter("belt_albedo",    _belt_albedo_texture())
	m.set_shader_parameter("belt_roughness", _belt_roughness_texture())
	m.set_shader_parameter("belt_normal",    _belt_normal_texture())
	# #140 — Godot's BoxMesh +Y face has V increasing in -Z, so a POSITIVE
	# #140 — convention: POSITIVE caller value = belt flows DOWNSTREAM. The
	# previous negation here was a one-shot fix for the intake belts but left
	# every other caller (variable_belt 0.5, opzetband 0.6, conveyor_8 0.6,
	# the wash-line belts) flowing UPSTREAM, which is what the operator was
	# reporting "across the board." Dropping the negation here + flipping the
	# leading minus on _INTAKE_BELT_SHADER_SCROLL together restore consistency
	# without changing any callsite's sign.
	m.set_shader_parameter("scroll_speed",   scroll_speed)
	m.set_shader_parameter("uv_tile",        tile)
	m.set_shader_parameter("uv_offset",      Vector2.ZERO)
	return m

# ── Roller stripe texture (#214 spin visibility) ──────────────────────────────
## Procedural radial-stripe texture for end rollers. CylinderMesh's default UV
## wraps U around the circumference, so vertical stripes in the texture become
## RADIAL stripes around the cylinder — exactly what the operator asked for so
## that roller spin is visible at any distance. 6 dark + 6 light bands give
## ~30° of arc per stripe: chunky enough to read across the floor without
## reading as moiré on close-up. The texture is cached statically, shared by
## every belt's roller mesh.
static var _roller_stripe_tex : ImageTexture = null
const _ROLLER_STRIPE_TEX_W : int = 96    # circumferential resolution (12 bands × 8 px)
const _ROLLER_STRIPE_TEX_H : int = 8     # axial resolution (small — stripes are vertical so axial is constant)
const _ROLLER_STRIPE_COUNT : int = 6     # 6 dark stripes around the drum (12 bands total counting the light gaps)

static func _roller_stripe_texture() -> ImageTexture:
	if _roller_stripe_tex != null:
		return _roller_stripe_tex
	var img := Image.create(_ROLLER_STRIPE_TEX_W, _ROLLER_STRIPE_TEX_H, false, Image.FORMAT_RGB8)
	var bands : int = _ROLLER_STRIPE_COUNT * 2   # alternating dark/light bands
	var band_w : int = _ROLLER_STRIPE_TEX_W / bands
	# Dark = nearly-black rubber drum surface; light = exposed metal stripe paint.
	# High contrast so spin reads from across the gauntlet platform.
	var dark : Color = Color(0.06, 0.06, 0.07)
	var light : Color = Color(0.94, 0.94, 0.92)
	for x in _ROLLER_STRIPE_TEX_W:
		var band_idx : int = int(x / float(band_w))
		var is_dark : bool = (band_idx % 2) == 0
		var col : Color = dark if is_dark else light
		for y in _ROLLER_STRIPE_TEX_H:
			img.set_pixel(x, y, col)
	_roller_stripe_tex = ImageTexture.create_from_image(img)
	return _roller_stripe_tex

## A StandardMaterial3D that paints the end-roller cylinder with 6 radial
## dark/light stripes so the operator can SEE the roller spinning. Used by
## BeltBuilder.build_rollers() in place of the plain dark material.
static func make_roller_stripe_material(ghost: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _roller_stripe_texture()
	m.metallic = 0.35
	m.roughness = 0.55
	# Texture filter — nearest gives crisp stripe edges; linear washes them out
	# at distance into a uniform mid-grey that hides the spin entirely.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if ghost:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0.40)
	return m

# ── #226 GLOBAL DIRTY FILTER ─────────────────────────────────────────────────
# Operator 2026-07-14: NOTHING should read as brand-new one-colour paint — every
# machine gets a LIGHT grime patina by default (until told otherwise per-machine).
# A single shared procedural grime NoiseTexture, multiplied onto the flat albedo
# via object-space triplanar UV1 (works on the procedural box meshes with no UV
# unwrap) + a small roughness bump. Cached → one texture for the whole plant.
# Skips ghosts (build previews) and translucent colours (glass / tank water).
# Pass clean=true to opt a material out (lenses, emissive dots, decals).
static var _grime_cache : NoiseTexture2D = null
static func _grime_tex() -> NoiseTexture2D:
	if _grime_cache != null:
		return _grime_cache
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.016                       # bigger, softer blobs (less busy)
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.noise = n
	# noise → colour ramp: mostly clean with occasional LIGHT warm-grey grime.
	# Darkest patch is 0.80 → only a ~20% darkening in the dirtiest spots (subtle).
	var g := Gradient.new()
	# Operator 2026-07-16 "dirt accumulates way too fast" — the patina is static
	# (cached, no growth), so "too fast" = too dirty. Confine grime to the top
	# ~30% of the noise range and halve the darkening (0.80 → 0.91) so surfaces
	# read lightly used, not filthy.
	g.set_offsets(PackedFloat32Array([0.0, 0.70, 1.0]))
	g.set_colors(PackedColorArray([
		Color(0.91, 0.90, 0.88), Color(0.96, 0.95, 0.93), Color(1.0, 1.0, 1.0)]))
	nt.color_ramp = g
	_grime_cache = nt
	return _grime_cache

static func _mat(c: Color, ghost: bool, metallic: float = 0.15, rough: float = 0.7, clean: bool = false) -> StandardMaterial3D:
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
		elif not clean:
			# #226 global dirty filter — subtle grime patina on every opaque surface.
			m.albedo_texture = _grime_tex()
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)               # sparser grime blobs
			m.roughness = clampf(rough + 0.02, 0.0, 1.0)       # was +0.05 — less grimy sheen
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

## 4 vertical walls forming a HOLLOW box (open top + bottom) — for feed hoppers,
## throats and funnels that should read as open, not a solid block.
static func _hollow_box(parent: Node3D, w: float, h: float, d: float, center: Vector3, t: float, mat: StandardMaterial3D) -> void:
	var hw : float = w * 0.5
	var hd : float = d * 0.5
	_box(parent, Vector3(t, h, d), center + Vector3(-hw + t * 0.5, 0.0, 0.0), mat)
	_box(parent, Vector3(t, h, d), center + Vector3( hw - t * 0.5, 0.0, 0.0), mat)
	_box(parent, Vector3(w - t * 2.0, h, t), center + Vector3(0.0, 0.0, -hd + t * 0.5), mat)
	_box(parent, Vector3(w - t * 2.0, h, t), center + Vector3(0.0, 0.0,  hd - t * 0.5), mat)

## `_box` with a StaticBody3D + BoxShape3D wrapper so the box is COLLIDABLE
## (player can stand on it / push against it). Use this for things the player
## needs to walk up — stair treads and ladder rungs — instead of bare meshes
## that look like geometry but pass right through the capsule. Returns the
## inner MeshInstance3D for callers that want to keep mutating it. Note
## `parent` receives the StaticBody3D; the mesh hangs underneath it.
static func _box_static_body(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	body.add_child(col)
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
			var lg := _box(parent, Vector3(0.08, top_y, 0.08), Vector3(sx * hx, top_y * 0.5, sz * hz), mat)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", top_y)

## Extend a placed machine's OWN support legs (tagged "machine_leg" by the builders)
## down to the floor when the machine is raised `drop` metres off it, and drop any
## foot pads (group "machine_foot") with them. This REPLACES the old bolt-on support
## frame: a raised machine now stands on its own (lengthened) legs instead of getting
## a separate pole structure. Idempotent — always recomputes from each leg's stored
## base height, so it's safe to call every frame while jogging the height. Returns how
## many legs it extended (0 → this machine has no taggable legs, so the caller may
## fall back to a frame).
static func extend_machine_legs(root: Node3D, drop: float) -> int:
	if root == null:
		return 0
	var dw : float = maxf(0.0, drop)                  # world-space drop down to the floor
	var sy : float = maxf(0.01, root.scale.y)
	var d : float = dw / sy                            # same drop in machine-local space
	var base_world_y : float = root.global_position.y
	var floor_world_y : float = base_world_y - dw
	# Obstacle raycast: a leg that would run straight down THROUGH another machine is
	# hidden rather than clipping through it. Exclude THIS machine's own bodies so a leg
	# never trips on its own belt/housing.
	var space : PhysicsDirectSpaceState3D = null
	if root.is_inside_tree():
		space = root.get_world_3d().direct_space_state
	var exclude : Array[RID] = []
	if root is CollisionObject3D:
		exclude.append((root as CollisionObject3D).get_rid())
	var n := 0
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var is_leg : bool = mi.is_in_group("machine_leg")
		var is_foot : bool = mi.is_in_group("machine_foot")
		if not is_leg and not is_foot:
			continue
		# Cast down the leg's descent path. A hit >0.4 m above the floor = the leg would
		# punch ~straight through a machine → hide it. A graze near the floor → run it to
		# the floor anyway (accept the minor clip — "we can only do so much").
		var blocked : bool = false
		if space != null and d > 0.01:
			var fx : Vector3 = mi.global_position
			var from := Vector3(fx.x, base_world_y + 0.05, fx.z)
			var to := Vector3(fx.x, floor_world_y - 0.05, fx.z)
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = exclude
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (float((hit["position"] as Vector3).y) - floor_world_y) > 0.4:
				blocked = true
		if is_leg:
			var base_h : float = float(mi.get_meta("leg_h", 0.0))
			if base_h <= 0.001:
				continue
			if blocked:
				mi.visible = false
			else:
				mi.visible = true
				mi.scale.y = (base_h + d) / base_h      # top stays at the machine base, bottom drops to -d
				mi.position.y = (base_h - d) * 0.5
			n += 1
		else:
			mi.visible = not blocked
			mi.position.y = float(mi.get_meta("foot_y", 0.0)) - d
	return n

## A TEFC electric motor: finned body cylinder + terminal box on top. axis as _cyl.
static func _motor_unit(parent: Node3D, r: float, length: float, pos: Vector3, axis: String, ghost: bool) -> void:
	# PLANT-WIDE RULE (operator 2026-08-28, flotation-tank walk): "All motors
	# in the factory are blue, by the way, dark blue. If you look at the CeDo
	# logo, it would be the blue from that logo." cedo_logo.svg fill #191E6C.
	var motor_blue := _mat(Color(0.098, 0.118, 0.424), ghost, 0.35, 0.5)
	var blk := _mat(Color(0.12, 0.12, 0.13), ghost, 0.3, 0.6)
	_cyl(parent, r, r, length, pos, motor_blue, axis)
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
## A LadderZone Area3D is embedded so PlayerController.enter_ladder/exit_ladder fire
## automatically — no manual wiring needed per-silo.
static func _caged_ladder(parent: Node3D, base: Vector3, height: float, mat: StandardMaterial3D, ghost: bool = false) -> void:
	var W := 0.46
	_box(parent, Vector3(0.05, height, 0.05), base + Vector3(-W * 0.5, height * 0.5, 0.0), mat)
	_box(parent, Vector3(0.05, height, 0.05), base + Vector3( W * 0.5, height * 0.5, 0.0), mat)
	# Rungs are collidable ledges. Step-up alone can't drive a full ladder ascent;
	# the LadderZone Area3D below switches the player to climb mode (W/S = vertical).
	# Ghost previews get visual-only rungs — BuildMode assumes a collision-less ghost.
	const RUNG_TREAD_DEPTH : float = 0.18
	var rungs := int(height / 0.3)
	for i in range(1, rungs):
		if ghost:
			_box(parent,
				Vector3(W, 0.03, RUNG_TREAD_DEPTH),
				base + Vector3(0.0, float(i) * 0.3, RUNG_TREAD_DEPTH * 0.5),
				mat)
		else:
			_box_static_body(parent,
				Vector3(W, 0.03, RUNG_TREAD_DEPTH),
				base + Vector3(0.0, float(i) * 0.3, RUNG_TREAD_DEPTH * 0.5),
				mat)
	# Cage hoops and bars — size increased 10% vs original for operator clearance.
	var hoop_y := 2.2
	while hoop_y < height - 0.1:
		_torus(parent, 0.396, 0.484, base + Vector3(0.0, hoop_y, 0.33), mat)
		hoop_y += 0.5
	var cage_h : float = maxf(height - 2.2, 0.2)
	for bz in [Vector3(0.0, 0.0, 0.792), Vector3(-0.462, 0.0, 0.33), Vector3(0.462, 0.0, 0.33)]:
		_box(parent, Vector3(0.03, cage_h, 0.03), base + bz + Vector3(0.0, 2.2 + cage_h * 0.5, 0.0), mat)

	# LadderZone Area3D — PlayerController.enter_ladder / exit_ladder are called
	# automatically when the player's CharacterBody3D overlaps this volume.
	# NEVER in ghosts: a live zone inside the mouse-following preview flipped the
	# player into gravity-off climb mode whenever the ghost swept over them.
	if ghost:
		return
	var area := Area3D.new()
	area.name = "LadderZone"
	area.position = base + Vector3(0.0, height * 0.5, 0.20)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(W + 0.4, height + 0.2, 0.7)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body.has_method("enter_ladder"): body.enter_ladder())
	area.body_exited.connect(func(body: Node3D) -> void:
		if body.has_method("exit_ladder"): body.exit_ladder())
	parent.add_child(area)

## A straight ground stair climbing `rise` in +Z from its foot `base`, `width`
## wide. Grating treads + side posts + sloped handrails.
static func _stair(parent: Node3D, base: Vector3, rise: float, width: float, _tread_mat: StandardMaterial3D, rail_mat: StandardMaterial3D) -> void:
	var steps := maxi(int(rise / 0.22), 4)
	var step_h := rise / float(steps)
	var tread := 0.27
	# Operator 2026-07-16: treads must be see-through METAL GRATING (not solid
	# slabs) and the flight must be SUPPORTED to the floor (not floating). Each
	# tread = a grating-deck visual + a hidden StaticBody collider (so you can walk
	# up but see through it); two sloped stringers carry it down to the ground.
	for i in range(steps):
		var tpos : Vector3 = base + Vector3(0.0, float(i + 1) * step_h, float(i) * tread + tread * 0.5)
		_grating_deck(parent, width, tread * 0.92, tpos)           # see-through grating (visual)
		# Collision ONLY — a bare StaticBody+CollisionShape with NO mesh. The old
		# code used a hidden mesh, but StaticMerge re-bakes hidden meshes VISIBLE,
		# so every tread rendered a solid box UNDER the grating → z-fight "seizure"
		# (operator 2026-07-17). No mesh = nothing for StaticMerge to re-show.
		var tb := StaticBody3D.new()
		tb.position = tpos
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(width, 0.06, tread)
		cs.shape = bs
		tb.add_child(cs)
		parent.add_child(tb)
	var run := float(steps) * tread
	# Sloped side stringers reaching the floor — visible support under the flight.
	var diag : float = sqrt(run * run + rise * rise)
	var pitch : float = atan2(rise, run)
	for sx in [-1.0, 1.0]:
		var stringer := _box(parent, Vector3(0.06, 0.20, diag),
			base + Vector3(sx * width * 0.5, rise * 0.5, run * 0.5), rail_mat)
		stringer.rotation.x = -pitch
	for sx in [-1.0, 1.0]:
		_box(parent, Vector3(0.05, 1.0, 0.05), base + Vector3(sx * width * 0.5, 0.5, 0.2), rail_mat)
		_box(parent, Vector3(0.05, 1.0, 0.05), base + Vector3(sx * width * 0.5, rise + 1.0, run - 0.2), rail_mat)
		var rail := _box(parent, Vector3(0.04, 0.04, diag), base + Vector3(sx * width * 0.5, rise * 0.5 + 1.0, run * 0.5), rail_mat)
		rail.rotation.x = -pitch

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

## A spinning auger/screw: the same flighting as _auger, but parented under a
## RotatingMechanism so it actually ROTATES about its Z (length) axis in-game.
## Ghost previews build it static (no spinning node in the placement ghost).
static func _spinning_auger(parent: Node3D, length: float, pos: Vector3, shaft_r: float, flight_r: float, shaft_mat: StandardMaterial3D, flight_mat: StandardMaterial3D, ghost: bool, rpm: float = 60.0, comp: String = "") -> void:
	if ghost:
		_auger(parent, length, pos, shaft_r, flight_r, shaft_mat, flight_mat)
		return
	var rm = _RM_SCRIPT.new()
	rm.axis = Vector3.BACK            # spin about the screw's long (Z) axis
	rm.rpm = rpm
	rm.nominal_rpm = rpm
	rm.capacity_kg_s = 2.0
	rm.position = pos
	# Tie this rotor to its own HMI component (its own motor) so it can be driven
	# independently — the dosing silo's 3 augers each have a separate motor.
	if comp != "":
		rm.set_meta("comp", comp)
	parent.add_child(rm)
	_auger(rm, length, Vector3.ZERO, shaft_r, flight_r, shaft_mat, flight_mat)

## A spinning drum/rotor: builds a cylinder under a RotatingMechanism so it
## actually rotates in-game. `cyl_axis` is the cylinder's long-axis string for
## _cyl ("x"/"y"/"z"); `spin_axis` is the world rotation axis (usually matching).
## Returns the RotatingMechanism so the caller can parent blades/end-caps/flights
## under it (they spin too). Ghost builds a static cylinder (no spin node).
static func _spinning_cyl(parent: Node3D, r_top: float, r_bot: float, length: float, pos: Vector3, mat: StandardMaterial3D, cyl_axis: String, spin_axis: Vector3, ghost: bool, rpm: float = 45.0) -> Node3D:
	if ghost:
		_cyl(parent, r_top, r_bot, length, pos, mat, cyl_axis)
		return parent
	var rm = _RM_SCRIPT.new()
	rm.axis = spin_axis
	rm.rpm = rpm
	rm.nominal_rpm = rpm
	rm.capacity_kg_s = 2.0
	rm.position = pos
	parent.add_child(rm)
	_cyl(rm, r_top, r_bot, length, Vector3.ZERO, mat, cyl_axis)
	return rm

## Attach N radial blades to a spinning shaft node (returned by _spinning_cyl).
## Shaft axis is X (matches the flotation paddle layout). Blades are flat slats
## oriented along the shaft length, spaced evenly around the shaft, anchored at
## the shaft centre so a quarter-turn flips them through the water surface.
##   shaft           — the parent RotatingMechanism node from _spinning_cyl
##   n               — number of blades (typically 4)
##   blade_len_x     — slat length along the shaft (X)
##   blade_t         — slat thickness (radial direction at the blade plane)
##   blade_radial    — how far the blade extends from the shaft centreline
##   mat             — material to use
static func _attach_paddle_blades(shaft: Node3D, n: int, blade_len_x: float,
		blade_t: float, blade_radial: float, mat: StandardMaterial3D) -> void:
	if shaft == null or n <= 0:
		return
	for i in n:
		var ang : float = TAU * float(i) / float(n)
		# Blade local frame: shaft is along X. Each blade is a thin slab in the
		# Y-Z plane (size along X = blade_len_x, thickness in radial dir, span = 2 * blade_radial).
		var b := _box(shaft, Vector3(blade_len_x, blade_t, blade_radial * 2.0),
				Vector3.ZERO, mat)
		# Offset along the radial direction so the blade's inner edge sits at the
		# shaft surface (centre + half-span outward). Combined with rotation_x = ang,
		# the blades fan out evenly around the X axis.
		b.position = Vector3(0.0, 0.0, 0.0)
		b.rotation.x = ang
		# Push the blade outward along the post-rotation Y so it's centred on its
		# own half-span (otherwise the blade straddles the shaft instead of
		# extending out from it).
		b.position = Vector3(0.0,
				cos(ang) * blade_radial * 0.5,
				sin(ang) * blade_radial * 0.5)

## Like _spinning_cyl but for a _tube (closed drum shell, e.g. a trommel). Returns
## the RotatingMechanism so the caller can parent drive-bands/cleats under it.
static func _spinning_tube(parent: Node3D, radius: float, length: float, pos: Vector3, mat: StandardMaterial3D, rot_x: float, spin_axis: Vector3, ghost: bool, rpm: float = 30.0) -> Node3D:
	if ghost:
		_tube(parent, radius, length, pos, mat, rot_x)
		return parent
	var rm = _RM_SCRIPT.new()
	rm.axis = spin_axis
	rm.rpm = rpm
	rm.nominal_rpm = rpm
	rm.capacity_kg_s = 2.0
	rm.position = pos
	parent.add_child(rm)
	_tube(rm, radius, length, Vector3.ZERO, mat, rot_x)
	return rm

## Adds an interactive hinged inspection hatch/door that the player can open/close with [E].
static func _interactive_hatch(p: Node3D, size: Vector3, pos: Vector3, name: String, angle_deg: float, hinge_side: float, mat: StandardMaterial3D, ghost: bool) -> Node3D:
	if ghost:
		return _box(p, size, pos, mat)
	var hatch_script := preload("res://src/build/InteractiveHatch.gd")
	var h : AnimatableBody3D = hatch_script.new()
	h.hatch_name = name
	h.open_angle_deg = angle_deg * hinge_side
	# Pivot sits at hinge side
	var pivot_x : float = pos.x + hinge_side * size.x * 0.5
	h.position = Vector3(pivot_x, pos.y, pos.z)
	p.add_child(h)

	# Door leaf mesh centered relative to hinge
	var leaf_x : float = -hinge_side * size.x * 0.5
	_box(h, size, Vector3(leaf_x, 0.0, 0.0), mat)

	# Collision box so the player's crosshair ray hits it
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size + Vector3(0.04, 0.04, 0.04)
	col.shape = sh
	col.position = Vector3(leaf_x, 0.0, 0.0)
	h.add_child(col)
	return h

# ── Overband magnet: suspended self-cleaning cross-belt separator above the conveyor ────
static func _m_overband_magnet(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var dark := _mat(_DARK, ghost, 0.5, 0.55)
	var magnet_mat := _mat(Color(0.12, 0.13, 0.16), ghost, 0.3, 0.65)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)
	var hz := size.z * 0.5
	var leg_h := size.y * 0.82

	# Four heavy structural uprights with triangular gusset base plates
	for sx in [-0.45, 0.45]:
		for sz in [-0.4, 0.4]:
			var lg := _box(p, Vector3(0.12, leg_h, 0.12),
				Vector3(sx * size.x, leg_h * 0.5, sz * size.z), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_h)
			_box(p, Vector3(0.24, 0.04, 0.24), Vector3(sx * size.x, 0.02, sz * size.z), steel)

	# Cross gantry beams connecting top of legs
	_box(p, Vector3(size.x * 0.94, 0.10, 0.10), Vector3(0.0, leg_h, -hz * 0.8), dark)
	_box(p, Vector3(size.x * 0.94, 0.10, 0.10), Vector3(0.0, leg_h,  hz * 0.8), dark)
	_box(p, Vector3(0.10, 0.10, size.z * 0.82), Vector3(-size.x * 0.45, leg_h, 0.0), dark)
	_box(p, Vector3(0.10, 0.10, size.z * 0.82), Vector3( size.x * 0.45, leg_h, 0.0), dark)

	# Suspension turnbuckles / threaded tie rods from gantry to magnet core
	for sx2 in [-0.28, 0.28]:
		for sz2 in [-0.28, 0.28]:
			_cyl(p, 0.022, 0.022, 0.22, Vector3(sx2 * size.x, size.y * 0.88, sz2 * size.z), steel, "y")
			_cyl(p, 0.040, 0.040, 0.06, Vector3(sx2 * size.x, size.y * 0.88, sz2 * size.z), dark, "y")

	# Heavy electromagnetic core housing with lateral cooling fins
	_box(p, Vector3(size.x * 0.58, size.y * 0.20, size.z * 0.72),
		Vector3(0.0, size.y * 0.80, 0.0), magnet_mat)
	for fi in 7:
		var fz : float = -size.z * 0.30 + float(fi) * (size.z * 0.10)
		_box(p, Vector3(size.x * 0.62, size.y * 0.22, 0.015), Vector3(0.0, size.y * 0.80, fz), steel)

	# Rotating cross-belt drums & cleated rubber belt
	if not ghost:
		for zz in [-hz * 0.75, hz * 0.75]:
			var rm = _RM_SCRIPT.new()
			rm.axis = Vector3.RIGHT; rm.rpm = 40.0; rm.nominal_rpm = 40.0; rm.capacity_kg_s = 1.0
			rm.position = Vector3(0.0, size.y * 0.80, zz)
			p.add_child(rm)
			_cyl(rm, size.y * 0.11, size.y * 0.11, size.x * 0.62, Vector3.ZERO, steel, "x")
			_cyl(rm, size.y * 0.13, size.y * 0.13, 0.03, Vector3(-size.x * 0.31, 0.0, 0.0), dark, "x")
			_cyl(rm, size.y * 0.13, size.y * 0.13, 0.03, Vector3( size.x * 0.31, 0.0, 0.0), dark, "x")

		# Captured tramp ferrous metal scrap held on the magnetic bottom belt
		for i in range(7):
			var scrap_x : float = float(i - 3) * 0.09
			var scrap_z : float = (float(i % 3) - 1.0) * 0.18
			_box(p, Vector3(0.05, 0.04, 0.07), Vector3(scrap_x, size.y * 0.68, scrap_z), steel)

	# Side discharge chute flinging scrap into collection hopper (+X)
	_box(p, Vector3(0.55, size.y * 0.24, size.z * 0.44),
		Vector3(size.x * 0.58, size.y * 0.58, hz * 0.65), dark)
	# Rubber deflector skirt on chute mouth
	_box(p, Vector3(0.03, size.y * 0.16, size.z * 0.40),
		Vector3(size.x * 0.84, size.y * 0.50, hz * 0.65), magnet_mat)

	# Electric drive motor + torque reaction arm on +X side
	_motor_unit(p, size.x * 0.14, size.z * 0.20, Vector3(size.x * 0.38, size.y * 0.80, -hz * 0.75), "x", ghost)
	_box(p, Vector3(0.18, 0.06, 0.06), Vector3(size.x * 0.38, size.y * 0.72, -hz * 0.75), dark)

	# Safety warning hazard decal
	if not ghost:
		_box(p, Vector3(0.01, 0.12, 0.28), Vector3(size.x * 0.46, leg_h * 0.7, 0.0), yellow)

# ── Coarse scraper conveyor (#156): submerged horizontal drag along a tank
#    bottom, climbing a ~50° incline, discharging off the top into a chute ──────
static func _m_scraper_conveyor(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var spec : Dictionary = BeltBuilder.make_spec()
	spec.deck_kind = "none"
	spec.rollers = "none"
	spec.side_rails = "none"
	spec.has_legs = false
	spec.motor = "none"
	spec.chute = "none"
	spec.belt_speed_mps = _BELT_CARRY_SPEED
	spec.tag_as_belt = true
	spec.extras = [Callable(PlaceableCatalog, "_scraper_conveyor_extras")]
	BeltBuilder.build(p, "scraper_conveyor", size, spec, ghost)

static func _scraper_conveyor_extras(p: Node3D, _deck_root: Node3D, size: Vector3, _spec: Dictionary, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var water := _mat(Color(0.20, 0.40, 0.34, 0.6), ghost, 0.0, 0.2)
	var hz := size.z * 0.5
	_legs(p, size, size.y * 0.05, dark)
	_box(p, Vector3(size.x * 0.9, size.y * 0.3, size.z * 0.6), Vector3(0.0, size.y * 0.2, -hz * 0.4), steel)
	_box(p, Vector3(size.x * 0.72, 0.04, size.z * 0.55), Vector3(0.0, size.y * 0.34, -hz * 0.4), water)
	var inc := Node3D.new()
	inc.position = Vector3(0.0, size.y * 0.2, -hz * 0.1)
	inc.rotation.x = -deg_to_rad(50.0)
	p.add_child(inc)
	_box(inc, Vector3(size.x * 0.7, size.y * 0.25, size.z * 0.7), Vector3(0.0, 0.0, size.z * 0.35), steel)
	_box(p, Vector3(size.x * 0.5, size.y * 0.2, 0.5), Vector3(0.0, size.y * 0.92, hz * 0.9), dark)
	if not ghost:
		for zz in [-hz * 0.7, hz * 0.05]:
			var rm = _RM_SCRIPT.new()
			rm.axis = Vector3.RIGHT; rm.rpm = 12.0; rm.nominal_rpm = 12.0; rm.capacity_kg_s = 3.0
			rm.position = Vector3(0.0, size.y * 0.25, zz)
			p.add_child(rm)
			_cyl(rm, size.x * 0.12, size.x * 0.12, size.x * 0.75, Vector3.ZERO, dark, "x")
			for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				_box(rm, Vector3(size.x * 0.78, 0.05, 0.08),
					Vector3(0.0, sin(a) * size.x * 0.12, cos(a) * size.x * 0.12), steel)

# ── Plasmaq: heavy dewatering mechanical squeeze press with conical screw & screen ──────
static func _m_plasmaq(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.3, 0.5)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var dark := _mat(_DARK, ghost, 0.5, 0.55)
	var water := _mat(Color(0.22, 0.44, 0.52, 0.65), ghost, 0.0, 0.2)
	var gauge_dial := _mat(Color(0.92, 0.92, 0.90), ghost, 0.1, 0.7)

	var leg_h : float = size.y * 0.38
	_legs(p, size, leg_h, dark)
	_box(p, Vector3(size.x * 0.94, 0.08, size.z * 0.96), Vector3(0.0, leg_h, 0.0), steel)

	# Main hexagonal squeeze press housing with reinforced bolted rib flanges
	var press_cy : float = leg_h + size.y * 0.32
	_box(p, Vector3(size.x * 0.84, size.y * 0.50, size.z * 0.78), Vector3(0.0, press_cy, -size.z * 0.05), body)

	# Bolted reinforcement ribs along the press barrel
	for i in 4:
		var rib_z : float = -size.z * 0.35 + float(i) * (size.z * 0.20)
		_box(p, Vector3(size.x * 0.88, size.y * 0.54, 0.04), Vector3(0.0, press_cy, rib_z), dark)

	# Perforated dewatering screen basket visible under the press
	_cyl(p, size.x * 0.32, size.x * 0.26, size.z * 0.72, Vector3(0.0, press_cy, -size.z * 0.05), steel, "z")

	# Heavy conical squeeze screw inside
	_cyl(p, size.x * 0.18, size.x * 0.24, size.z * 0.74, Vector3(0.0, press_cy, -size.z * 0.05), steel, "z")

	# Front hydraulic cone back-pressure thrust cylinder at +Z
	var cyl_z : float = size.z * 0.38
	_cyl(p, size.x * 0.14, size.x * 0.14, size.z * 0.22, Vector3(0.0, press_cy, cyl_z), dark, "z")
	_cyl(p, size.x * 0.07, size.x * 0.07, size.z * 0.16, Vector3(0.0, press_cy, cyl_z + size.z * 0.14), steel, "z")

	# Dual hydraulic pressure gauge panel on +X flank
	_box(p, Vector3(0.04, 0.22, 0.32), Vector3(size.x * 0.44, press_cy + 0.10, 0.0), dark)
	_cyl(p, 0.045, 0.045, 0.02, Vector3(size.x * 0.46, press_cy + 0.14, -0.08), gauge_dial, "x")
	_cyl(p, 0.045, 0.045, 0.02, Vector3(size.x * 0.46, press_cy + 0.14,  0.08), gauge_dial, "x")

	# Rear planetary gearbox and electric drive motor at -Z
	_box(p, Vector3(size.x * 0.65, size.y * 0.45, size.z * 0.18), Vector3(0.0, press_cy, -size.z * 0.48), dark)
	_motor_unit(p, size.x * 0.22, size.z * 0.24, Vector3(0.0, press_cy, -size.z * 0.62), "z", ghost)

	# Effluent water collection sump underneath with drain pipe
	_box(p, Vector3(size.x * 0.78, 0.16, size.z * 0.70), Vector3(0.0, leg_h + 0.08, -size.z * 0.05), dark)
	_box(p, Vector3(size.x * 0.72, 0.04, size.z * 0.64), Vector3(0.0, leg_h + 0.14, -size.z * 0.05), water)
	_cyl(p, 0.06, 0.06, 0.35, Vector3(-size.x * 0.32, leg_h * 0.5, 0.0), steel, "y")
	_cyl(p, 0.08, 0.08, 0.04, Vector3(-size.x * 0.32, 0.04, 0.0), dark, "y")

# ── Laserfilter: melt-filter housing + two breaker/filter discs + melt pipe ───
static func _m_laser_filter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# The Laserfilter is the big ROTARY DISC melt filter — the prominent concentric
	# circle on the 3C HMI (259 bar in, ~81% loaded). A large disc faces sideways
	# (axis = X) so the concentric rings read in side elevation; melt flows through
	# along Z, the disc rotates to self-clean. (This is the big circle — NOT the PCU.)
	var body := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	_legs(p, size, size.y * 0.14, dark)
	var cy : float = size.y * 0.6
	var disc_r : float = size.y * 0.46
	# #233 — the 4 corner legs sit at the footprint corners, but the disc housing is
	# CENTRED, so it read as floating above detached legs (operator "disc disc disc").
	# Tie them with a base plate + a central pedestal up to the disc bottom.
	if not ghost:
		var lf_base_y : float = size.y * 0.14
		var lf_disc_bot : float = cy - disc_r
		_box(p, Vector3(size.x * 0.92, 0.09, size.z * 0.86), Vector3(0.0, lf_base_y, 0.0), dark)
		_box(p, Vector3(size.x * 0.46, maxf(lf_disc_bot - lf_base_y, 0.06), size.z * 0.52),
			Vector3(0.0, (lf_base_y + lf_disc_bot) * 0.5, 0.0), dark)
	# Concentric disc faces toward ±X (the big circle), built from nested rings.
	# The outer housing is a real RotatingMechanism (spins about X to self-clean);
	# the inner rings/hub are parented UNDER it so they rotate together. On ghost,
	# disc_rm == p so the rings fall back to their absolute (0, cy, 0) position.
	var disc_rm := _spinning_cyl(p, disc_r, disc_r, size.x * 0.50, Vector3(0.0, cy, 0.0), body, "x", Vector3.RIGHT, ghost)   # outer housing
	var ring_y : float = 0.0 if not ghost else cy
	_cyl(disc_rm, disc_r * 0.72, disc_r * 0.72, size.x * 0.58, Vector3(0.0, ring_y, 0.0), steel, "x")   # filter ring (proud)
	# #223 docs->code: EREMA LF 2/406 — the "2" = TWO zeefschijven (screen discs).
	# docs/plant/swi/TRAIN-laserfilter-p3A__112_CeDo32.md: contaminated melt is forced
	# BETWEEN the 2 discs and through both; a small co-axial gap on the spin (X) axis.
	var lf_gap : float = size.x * 0.11
	_cyl(disc_rm, disc_r * 0.42, disc_r * 0.42, size.x * 0.12, Vector3(-lf_gap, ring_y, 0.0), body, "x")   # zeefschijf A
	_cyl(disc_rm, disc_r * 0.42, disc_r * 0.42, size.x * 0.12, Vector3( lf_gap, ring_y, 0.0), body, "x")   # zeefschijf B
	_cyl(disc_rm, disc_r * 0.10, disc_r * 0.10, size.x * 0.66, Vector3(0.0, ring_y, 0.0), dark,  "x")   # centre hub
	# Melt pipe in from the extruder (-Z) and out to the meltpump (+Z).
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.5, Vector3(0.0, cy, -size.z * 0.45), dark, "z")
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.5, Vector3(0.0, cy,  size.z * 0.45), dark, "z")
	# Disc self-clean drive motor off the +X face.
	_motor_unit(p, size.x * 0.13, size.y * 0.28, Vector3(size.x * 0.52, cy, 0.0), "x", ghost)

	# Interactive scraper disc maintenance inspection hatch on the top (+Y)
	var lf_hatch := _interactive_hatch(p, Vector3(size.x * 0.38, 0.04, size.z * 0.38),
		Vector3(0.0, cy + disc_r + 0.02, 0.0), "Laserfilter Inspection Hatch", 95.0, 1.0, steel, ghost)
	if not ghost:
		# Transparent grimy sight-glass viewing port into the rotating scraper chamber
		_box(lf_hatch, Vector3(size.x * 0.18, 0.02, size.z * 0.18),
			Vector3(-size.x * 0.19, 0.02, 0.0), MaterialPalette.mat_glass_inspection_grime())
		_box(lf_hatch, Vector3(0.04, 0.06, 0.12), Vector3(-size.x * 0.19, 0.04, 0.10), dark)
	# #225.2 docs->code: TWIN afvoervijzel discharge (operator 2026-07-14 + photos
	# machines/laserfilter_lump_cart_discharge.jpg, _lumbs_cart.jpg).
	# A VERTICAL discharge nozzle drops into a lump cart on BOTH sides of the disc:
	# achter (+X — under the macro yaw this mouth lands over the bordes/raised
	# cart in MainWorld) and voor (-X — ground cart). Naming sweep 2026-08-07;
	# the old labels called +X "aisle" and -X "wall", crossed vs plant vocabulary.
	# Each side augers UP a corrugated riser beside the disc, ACROSS a short top
	# arm, then DOWN a prominent vertical corrugated spout to a funnel mouth whose
	# lip (~1.13 m) clears the cart rim — so the rope drops straight down IN the
	# bucket, never on the housing or extruder. Mirrors LaserFilter.
	# eject_achter_local (+X, 1.30, 1.13) and eject_voor_local (-X, -1.30, 1.13)
	# — keep in sync.
	var lf_disch_r   : float = size.x * 0.13
	var lf_mouth_x   : float = 1.30                   # cart centre (= eject offset X)
	# #234 afvoerschroef (operator 2026-07-15 + 3A "De Laserfilter" poster): a HORIZONTAL
	# uitvoerschroef (discharge screw in a corrugated tube) runs out from the disc to over
	# the cart, then a small (~8 cm dia) VERTICAL tube drops the lump DOWN into the cart.
	# ASYMMETRIC as BUILT: the -X screw is HIGHER, the +X screw is LOWER — but
	# measured 2026-08-03 the +X mouth is the ACHTER/bordes (raised-cart) side in
	# MainWorld, so these visual heights sit on the WRONG sides under the macro
	# yaw (the LOW +X funnel lip at 0.98 m is even below a bordes-cart rim at
	# ~0.95+0.12 m). Geometry fix pending an operator render + confirm — see
	# extruder_line_layout.md "Still open" item 3. Naming sweep 2026-08-07
	# Both forward (-X voor) and rear (+X achter) discharge screws (afvoervijzels)
	# exit symmetrically from the centre of the circular disc at the exact same height (cy).
	for lf_s in [1.0, -1.0]:                           # +X achter mouth, -X voor mouth (symmetrical)
		var screw_y  : float = cy                       # Symmetrical center-height (matches disc center)
		var tube_bot : float = maxf(cy - 0.25, 1.05)    # drop-tube bottom, clears cart rim cleanly
		var disc_x : float = lf_s * size.x * 0.34          # screw inlet at the disc face
		var mx     : float = lf_s * lf_mouth_x             # cart centre
		var screw_len : float = absf(mx - disc_x)
		var screw_cx  : float = (mx + disc_x) * 0.5
		# corrugated tube housing of the horizontal uitvoerschroef
		var n_seg : int = maxi(int(screw_len / 0.12), 1)
		for si in range(n_seg):
			_cyl(p, lf_disch_r, lf_disch_r, 0.10, Vector3(disc_x + lf_s * (float(si) * 0.12 + 0.05), screw_y, 0.0), steel, "x")
		# internal screw (auger shaft)
		_cyl(p, lf_disch_r * 0.5, lf_disch_r * 0.5, screw_len, Vector3(screw_cx, screw_y, 0.0), dark, "x")
		# VERTICAL drop tube (~8 cm dia) at the screw end, straight down into the cart
		var tube_r : float = 0.04
		_cyl(p, tube_r, tube_r, maxf(screw_y - tube_bot, 0.08), Vector3(mx, (screw_y + tube_bot) * 0.5, 0.0), steel)
		_cyl(p, tube_r * 1.6, tube_r, 0.08, Vector3(mx, tube_bot, 0.0), dark)   # funnel lip over the cart
		# uitvoerschroef drive motor at the disc end of the screw
		_motor_unit(p, size.x * 0.07, size.x * 0.12, Vector3(disc_x - lf_s * lf_disch_r * 1.2, screw_y, 0.0), "x", ghost)
	# #212.8 S-curve flow-direction decal on the +X face of the disc cover.
	# Drawn as a sequence of small black box segments tracing an S shape over
	# a white backing panel — reads as a flow-arrow at the operator's eye-level.
	if not ghost:
		var bw := _mat(Color(0.92, 0.92, 0.92), ghost, 0.0, 0.7)
		var bk := _mat(Color(0.05, 0.05, 0.06), ghost, 0.0, 0.8)
		_box(p, Vector3(0.005, 0.24, 0.24),
			Vector3(size.x * 0.55, cy, size.z * 0.10), bw)
		# 5 segments hand-drawn along S-curve y offsets.
		var s_pts : Array = [
			Vector3(size.x * 0.555, cy + 0.10, size.z * 0.04),
			Vector3(size.x * 0.555, cy + 0.05, size.z * 0.08),
			Vector3(size.x * 0.555, cy + 0.00, size.z * 0.10),
			Vector3(size.x * 0.555, cy - 0.05, size.z * 0.12),
			Vector3(size.x * 0.555, cy - 0.10, size.z * 0.16),
		]
		for sp in s_pts:
			_box(p, Vector3(0.005, 0.025, 0.05), sp, bk)
	# #212.8 Sick-style red laser sensor: small box with red emissive material
	# on a thin bracket above the disc cover.
	if not ghost:
		var bracket := _mat(_DARK, ghost, 0.5, 0.6)
		_box(p, Vector3(0.04, 0.08, 0.04),
			Vector3(size.x * 0.20, cy + disc_r + 0.10, 0.0), bracket)
		var sick_red := _mat(Color(0.92, 0.18, 0.14), ghost, 0.2, 0.4)
		sick_red.emission_enabled = true
		sick_red.emission = Color(0.92, 0.18, 0.14)
		sick_red.emission_energy_multiplier = 0.6
		_box(p, Vector3(0.03, 0.04, 0.05),
			Vector3(size.x * 0.20, cy + disc_r + 0.16, 0.0), sick_red)

# ── Meltpump: high-precision heated gear-pump block with P1/P2 melt transducers & cardan drive ────
static func _m_melt_pump(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.35, 0.5)
	var steel := _mat(_STEEL, ghost, 0.65, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var digital_scr := _mat(Color(0.08, 0.12, 0.08), ghost, 0.1, 0.8)
	var digit_green := _mat(Color(0.2, 0.9, 0.3), ghost, 0.2, 0.4)
	digit_green.emission_enabled = true
	digit_green.emission = Color(0.2, 0.9, 0.3)
	digit_green.emission_energy_multiplier = 0.5

	var leg_h : float = size.y * 0.35
	_legs(p, size, leg_h, dark)
	_box(p, Vector3(size.x * 0.88, 0.08, size.z * 0.88), Vector3(0.0, leg_h, 0.0), steel)

	# Heavy insulated heater blanket jacket around the gear pump block
	var pump_cy : float = leg_h + size.y * 0.32
	_box(p, Vector3(size.x * 0.74, size.y * 0.52, size.z * 0.74), Vector3(0.0, pump_cy, 0.0), body)

	# Inner hardened tool-steel gear pump casing protruding
	_cyl(p, size.x * 0.28, size.x * 0.28, size.z * 0.76, Vector3(0.0, pump_cy, 0.0), steel, "z")

	# Twin intermeshing gear shafts with bearing caps at ±X
	for sx in [-0.22, 0.22]:
		_cyl(p, size.x * 0.13, size.x * 0.13, size.z * 0.82, Vector3(sx * size.x, pump_cy, 0.0), dark, "z")
		# Cardan universal joints driving the gear shaft
		_cyl(p, size.x * 0.08, size.x * 0.08, size.z * 0.25, Vector3(sx * size.x, pump_cy, -size.z * 0.48), steel, "z")

	# Heating cartridge element terminals on the top face
	for hx in [-0.20, 0.0, 0.20]:
		_cyl(p, 0.025, 0.025, 0.12, Vector3(hx * size.x, pump_cy + size.y * 0.28, 0.0), dark, "y")
		_cyl(p, 0.035, 0.035, 0.04, Vector3(hx * size.x, pump_cy + size.y * 0.33, 0.0), steel, "y")

	# P1 (inlet pressure) and P2 (discharge pressure) digital transducers on +X side
	for pz in [-0.18, 0.18]:
		var pt_z : float = pz * size.z
		_cyl(p, 0.035, 0.035, 0.16, Vector3(size.x * 0.42, pump_cy + 0.12, pt_z), steel, "x")
		_box(p, Vector3(0.04, 0.14, 0.10), Vector3(size.x * 0.52, pump_cy + 0.12, pt_z), dark)
		_box(p, Vector3(0.005, 0.06, 0.08), Vector3(size.x * 0.545, pump_cy + 0.12, pt_z), digital_scr)
		_box(p, Vector3(0.006, 0.02, 0.05), Vector3(size.x * 0.546, pump_cy + 0.12, pt_z), digit_green)

	# Inlet melt pipe (-Z) and outlet melt pipe (+Z) with heavy 8-bolt flanged collars
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.28, Vector3(0.0, pump_cy, -size.z * 0.46), dark, "z")
	_cyl(p, size.x * 0.20, size.x * 0.20, 0.06, Vector3(0.0, pump_cy, -size.z * 0.52), steel, "z")
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.28, Vector3(0.0, pump_cy,  size.z * 0.46), dark, "z")
	_cyl(p, size.x * 0.20, size.x * 0.20, 0.06, Vector3(0.0, pump_cy,  size.z * 0.52), steel, "z")

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
	# Legs must reach UP to the CONE-CYLINDER JUNCTION (top of the cone, bottom of the
	# main body) — not stop at the cone's narrow tip leaving the cone hanging in the
	# legs' midst. Total leg height = floor clearance + cone height.
	#   floor_clear = 16% of size.y  (the original leg_h — clearance under the hopper tip)
	#   cone_h      = 22% of size.y  (the conical hopper section)
	#   total       = leg_top spans 0 .. (clear + cone_h)
	# Each leg is tagged "machine_leg" + meta "leg_h" so extend_machine_legs() lengthens
	# it to the floor when the user raises the silo (e.g., 2 m up so lorries fit underneath).
	var floor_clear : float = size.y * 0.16
	var cone_h      : float = size.y * 0.22
	var leg_top     : float = floor_clear + cone_h
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			var lg := _box(p, Vector3(0.12, leg_top, 0.12),
				Vector3(sx * r * 0.7, leg_top * 0.5, sz * r * 0.7), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_top)
	# Conical hopper bottom (narrow at the bottom). Sits ABOVE the floor clearance,
	# bottom at floor_clear (tip), top at leg_top (where it meets the main cylinder).
	_cyl(p, r, 0.15, cone_h, Vector3(0.0, floor_clear + cone_h * 0.5, 0.0), shell)
	# Main body cylinder (stacks on top of the cone-cylinder junction).
	_cyl(p, r, r, size.y * 0.5, Vector3(0.0, leg_top + size.y * 0.25, 0.0), shell)
	# Domed/short top.
	_cyl(p, r * 0.25, r, size.y * 0.10, Vector3(0.0, leg_top + size.y * 0.55, 0.0), shell)
	# #101 — hanging plastic-cloth/rag enclosure around the discharge area.
	# Per operator: the extraction screws themselves are NOT visible from outside;
	# what's actually seen is a rectangular cloth skirt hung from partway up the
	# cone down to where it touches the compactor belt under the silo. Cloth is
	# the only visible part — the screws (plural, hidden behind it) are out of
	# scope.
	#
	# Material is alpha-translucent off-white so the rag reads as soft fabric
	# instead of a sheet-steel wall, and the panels are 1.2 cm thick so they
	# don't dominate at grazing angles. Sides (±X) stay panel-free so the
	# silo's horizontal discharge has somewhere to actually go.
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(0.88, 0.84, 0.74, 0.78)
	cloth_mat.metallic = 0.0
	cloth_mat.roughness = 0.95
	cloth_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloth_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cloth_half_w : float = r * 0.90
	var cloth_half_d : float = r * 0.90
	var cloth_top_y : float = floor_clear + cone_h * 0.45
	var cloth_bot_y : float = 0.02
	var cloth_h : float = cloth_top_y - cloth_bot_y
	var cloth_cy : float = (cloth_top_y + cloth_bot_y) * 0.5
	# Only the +Z and -Z facing rag panels are hung (the ones perpendicular to
	# the screw's conveying axis). The ±X sides stay open — the screws are
	# horizontal and discharge OUT the side onto a compactor belt; blocking
	# them with cloth would defeat the whole point. Top + bottom stay open
	# so material falls down through the enclosure.
	_box(p, Vector3(cloth_half_w * 2.0, cloth_h, 0.012),
		Vector3(0.0, cloth_cy, -cloth_half_d), cloth_mat)   # front (-Z)
	_box(p, Vector3(cloth_half_w * 2.0, cloth_h, 0.012),
		Vector3(0.0, cloth_cy,  cloth_half_d), cloth_mat)   # back  (+Z)

	# ── voorraad_silo: industrial caged ladder + self-closing push-gate ─────────
	# Mirrors the proven _m_extruder_silo treatment (#98 block, see lines 7822+):
	# operators need a modelled climb to the top of this 6.5 m tank, with a
	# safety gate at the landing edge. Round-silo geometry forces a small
	# landing platform hugging the shell (no flat top deck like the box silo).
	# Climber side = -X.
	var steel  := _mat(_STEEL,  ghost, 0.6, 0.4)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)
	# Top of the main cylindrical body — sits just below the dome. We anchor
	# the landing platform here so the ladder lands at the highest practical
	# point on the shell that's still flush with vertical sheet.
	var body_top : float = leg_top + size.y * 0.50
	# Small steel landing platform cantilevered off the -X face of the shell.
	# Roughly 0.8 m × 0.8 m, sits with its inner edge tucked against the shell
	# (shell radius r at this Y), outer edge clear for the climber to step on.
	# deck_half must exceed the dome base radius (r) so the player walks on flat
	# steel AROUND the dome, not inside it.  r = size.x * 0.46 ≈ 1.38 m.
	var deck_half : float = r + 0.70                            # e.g. ~2.08 m — clear of dome on all sides
	var deck_x : float = 0.0                                    # centred on the silo top
	_box(p, Vector3(deck_half * 2.0, 0.05, deck_half * 2.0),
		Vector3(deck_x, body_top, 0.0), steel)
	# Guardrail on ±Z sides only — leaves -X (ladder) and +X (walkthrough) open
	# so the player can traverse the full silo top without hitting a wall.
	_railing(p, deck_half, deck_half, body_top + 0.025, yellow, ["-x", "+x"])
	# Caged ladder climbing from the floor to just above the landing. Same
	# rotated-root trick as the extruder silo: _caged_ladder builds the cage
	# opening toward +Z by default, so we yaw the parent -90° about Y so the
	# cage opens toward +X (the direction the climber steps off onto the deck).
	var ladder_h : float = body_top + 0.10
	var ladder_x : float = -r - 0.30                            # clear of the shell
	var ladder_root := Node3D.new()
	ladder_root.name = "VoorraadSiloAccessLadder"
	ladder_root.rotation.y = -PI * 0.5
	ladder_root.position = Vector3(ladder_x, 0.0, 0.0)
	p.add_child(ladder_root)
	_caged_ladder(ladder_root, Vector3.ZERO, ladder_h, steel, ghost)
	# Self-closing push-gate at the landing edge directly above the ladder
	# top. Pushes open into +X (onto the deck) and auto-closes behind the
	# climber. Free side index 1 = -X (the ladder side, free to swing
	# through); platform side +X requires E to open.
	var gate_y : float = body_top + 0.05                        # deck top
	var gate_x_edge : float = -r - 0.05                         # at the shell-side edge
	var gate_root : Node3D
	if ghost:
		gate_root = Node3D.new()
	else:
		var pg_script := load("res://src/build/PushGate.gd")
		gate_root = StaticBody3D.new()
		if pg_script != null:
			(gate_root as StaticBody3D).set_script(pg_script)
			gate_root.set("free_side_idx", 1)
	gate_root.name = "VoorraadSiloPushGate"
	gate_root.position = Vector3(gate_x_edge, gate_y, 0.0)
	p.add_child(gate_root)
	# Two yellow vertical posts at ±Z half-width, one mid-rail + one top-rail.
	_box(gate_root, Vector3(0.05, 1.05, 0.05),
		Vector3(0.0, 0.525,  0.23), yellow)
	_box(gate_root, Vector3(0.05, 1.05, 0.05),
		Vector3(0.0, 0.525, -0.23), yellow)
	_box(gate_root, Vector3(0.04, 0.04, 0.46),
		Vector3(0.0, 1.00, 0.0), yellow)
	_box(gate_root, Vector3(0.04, 0.04, 0.46),
		Vector3(0.0, 0.55, 0.0), yellow)
	# Small spring-hinge cue at the hinge edge (visual only).
	_cyl(gate_root, 0.02, 0.02, 0.10,
		Vector3(0.0, 0.20, 0.23), steel)
	# Collision body for the gate leaf so the player can't walk through it
	# closed (PushGate re-parents this under HingePivot on _ready).
	if not ghost:
		var col := CollisionShape3D.new()
		var col_box := BoxShape3D.new()
		col_box.size = Vector3(0.08, 1.05, 0.46)
		col.shape = col_box
		col.position = Vector3(0.0, 0.525, 0.0)
		gate_root.add_child(col)

# ── OUTDOOR MS/LS PELLET SILO (2026-07-06, silos_ms_ls.md §5/§6) ─────────────
## Shared builder for `ms_silo_buiten` (variant "ms") and `ls_silo_buiten`
## (variant "ls"). Skeleton = the proven _m_silo legs+cone+body+dome, MINUS the
## #101 cloth discharge skirt (indoor extruder-feed dressing — not documented
## outdoors), PLUS the voorraad_silo caged-ladder/landing/push-gate access
## (photo 125_CeDo40: "tall grey outdoor silos with access stair/ladder and
## ducting" — ladder-vs-stair ambiguous, ladder pattern reused; flag 10).
##
## Height 18.0 m + proportions are placeholders (shell-mesh measurement,
## silos_ms_ls.md §4 — flags 1/2/3). Capacity is deliberately NOT modelled:
## pellet bulk density undocumented (open Q19 stortgewicht — flag 11).
##
## Variant extras:
##  "ms" — blower-transfer pipe stub at the TOP (the MS-defining feature):
##         mixing = background meng⇄laad recirculation LOOP (operator ruling B6
##         2026-07-06) — NO player controls, stub geometry only (flag 8/9).
##  "ls" — legs lengthened for the drive-under truck lane (hopper tip clearance
##         4.5 m = neutral EU-truck placeholder, flag 6) + discharge tube /
##         slide-valve / flexible spout to truck-hatch height (mechanism type
##         undocumented — neutral tube+valve+spout, flag 7) + top infeed elbow
##         (pneumatic from the weegschaal line, 125_CeDo40) but NO silo-to-silo
##         stub (MS→LS topology unconfirmed — flag 9).
## Ghost-safe: _caged_ladder handles its own ghost mode (visual rungs, no
## LadderZone); the push-gate collapses to a plain Node3D + meshes in ghosts.
static func _m_silo_buiten(p: Node3D, size: Vector3, color: Color, ghost: bool, variant: String) -> void:
	var shell := _mat(color, ghost, 0.3, 0.5)
	var dark  := _mat(_DARK, ghost, 0.4, 0.6)
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)
	var r := size.x * 0.46
	var is_ls : bool = variant == "ls"
	# Vertical zones. MS keeps the _m_silo fractions; LS fixes the floor
	# clearance at 4.5 m so a truck fits under the hopper tip (flag 6).
	var floor_clear : float = 4.5 if is_ls else size.y * 0.16
	var cone_h : float = size.y * 0.20
	var dome_h : float = size.y * 0.08
	var leg_top : float = floor_clear + cone_h
	var body_h : float = size.y - leg_top - dome_h
	var body_top : float = leg_top + body_h
	# ── Legs + bracing (photo: "elevated steel platform structure" — brace
	# pattern is a neutral placeholder). Tagged for floor-snap (#70).
	var signs : Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			var lg := _box(p, Vector3(0.16, leg_top, 0.16),
				Vector3(sx * r * 0.72, leg_top * 0.5, sz * r * 0.72), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_top)
	for frac in [0.35, 0.70]:
		var by : float = floor_clear * frac
		for sz2 in signs:
			_box(p, Vector3(r * 1.44, 0.08, 0.08), Vector3(0.0, by, sz2 * r * 0.72), dark)
		for sx2 in signs:
			_box(p, Vector3(0.08, 0.08, r * 1.44), Vector3(sx2 * r * 0.72, by, 0.0), dark)
	# ── Shell: conical hopper + main cylinder + domed top (_m_silo proportions,
	# re-anchored — proportions at 18 m are placeholders, flag 3).
	_cyl(p, r, 0.18, cone_h, Vector3(0.0, floor_clear + cone_h * 0.5, 0.0), shell)
	_cyl(p, r, r, body_h, Vector3(0.0, leg_top + body_h * 0.5, 0.0), shell)
	_cyl(p, r * 0.25, r, dome_h, Vector3(0.0, body_top + dome_h * 0.5, 0.0), shell)
	# ── Access: landing deck + guardrail + caged ladder + self-closing push-gate
	# (exact voorraad_silo block, body_top recomputed for the 18 m shell).
	var deck_half : float = r + 0.70
	_box(p, Vector3(deck_half * 2.0, 0.05, deck_half * 2.0),
		Vector3(0.0, body_top, 0.0), steel)
	_railing(p, deck_half, deck_half, body_top + 0.025, yellow, ["-x", "+x"])
	var ladder_h : float = body_top + 0.10
	var ladder_root := Node3D.new()
	ladder_root.name = "SiloBuitenAccessLadder"
	ladder_root.rotation.y = -PI * 0.5
	ladder_root.position = Vector3(-r - 0.30, 0.0, 0.0)
	p.add_child(ladder_root)
	_caged_ladder(ladder_root, Vector3.ZERO, ladder_h, steel, ghost)
	var gate_root : Node3D
	if ghost:
		gate_root = Node3D.new()
	else:
		var pg_script := load("res://src/build/PushGate.gd")
		gate_root = StaticBody3D.new()
		if pg_script != null:
			(gate_root as StaticBody3D).set_script(pg_script)
			gate_root.set("free_side_idx", 1)
	gate_root.name = "SiloBuitenPushGate"
	gate_root.position = Vector3(-r - 0.05, body_top + 0.05, 0.0)
	p.add_child(gate_root)
	_box(gate_root, Vector3(0.05, 1.05, 0.05), Vector3(0.0, 0.525,  0.23), yellow)
	_box(gate_root, Vector3(0.05, 1.05, 0.05), Vector3(0.0, 0.525, -0.23), yellow)
	_box(gate_root, Vector3(0.04, 0.04, 0.46), Vector3(0.0, 1.00, 0.0), yellow)
	_box(gate_root, Vector3(0.04, 0.04, 0.46), Vector3(0.0, 0.55, 0.0), yellow)
	_cyl(gate_root, 0.02, 0.02, 0.10, Vector3(0.0, 0.20, 0.23), steel)
	if not ghost:
		var gcol := CollisionShape3D.new()
		var gcol_box := BoxShape3D.new()
		gcol_box.size = Vector3(0.08, 1.05, 0.46)
		gcol.shape = gcol_box
		gcol.position = Vector3(0.0, 0.525, 0.0)
		gate_root.add_child(gcol)
	# ── Pneumatic top infeed elbow (both variants): the weegschaal line lands
	# on the silo TOP (training slide 125_CeDo40: air blower → leidingwerk →
	# silo). Pipe diameter/routing = placeholder (flag 8).
	var apex_y : float = body_top + dome_h
	_cyl(p, 0.12, 0.12, 1.0, Vector3(0.0, apex_y + 0.45, 0.0), steel)
	_cyl(p, 0.12, 0.12, 0.9, Vector3(-0.45, apex_y + 0.90, 0.0), steel, "x")
	if is_ls:
		# ── LS discharge (documented existence only — neutral tube + slide-valve
		# + hanging flexible spout to ~2.5 m truck-hatch height; flag 7).
		_cyl(p, 0.14, 0.14, 0.50, Vector3(0.0, floor_clear - 0.25, 0.0), dark)
		_box(p, Vector3(0.45, 0.25, 0.45), Vector3(0.0, floor_clear - 0.60, 0.0), steel)
		var spout_top : float = floor_clear - 0.72
		var spout_h : float = maxf(spout_top - 2.5, 0.3)
		_cyl(p, 0.10, 0.16, spout_h, Vector3(0.0, spout_top - spout_h * 0.5, 0.0), dark)
	else:
		# ── MS blower-transfer stub at the top (the mengsilo-defining feature):
		# pellets are blown from one silo INTO THE TOP of another; piping visible
		# (interview + 125_CeDo40 "Leidingwerk"). Stub only — do NOT model a full
		# inter-silo pipe run (routing undocumented, flag 8; mixing loop itself is
		# background-only per ruling B6).
		_cyl(p, 0.15, 0.15, 1.5, Vector3(0.9, apex_y + 0.90, 0.0), steel, "x")
		_cyl(p, 0.19, 0.19, 0.05, Vector3(1.67, apex_y + 0.90, 0.0), steel, "x")   # open flange

# ── EOP (End Of Pipe) — Indaver water-treatment EXTERNAL ENTITY endpoint ─────
## 2026-07-06 (eop_rafter.md Part A). Appearance UNDOCUMENTED — every dimension
## is a neutral placeholder (flags 1-3): one flat-roofed building block +
## "EOP — INDAVER" placard + EXACTLY the 3 documented pipe-stub groups from
## water_circuits.json / DIAG-blauwe-watertank 232_CeDo138:
##   1. -Z low, largest ⌀ : "Riool naar EOP" dirty-water main IN (thick line)
##   2. +Z              : purified return → Blauwe tank
##   3. -X, 2 small     : ZSS exchange pair (2nd line marked unsure in the json)
## No fence (a fence would be invented detail). No MachineFlow role, no player
## interaction — the hmi_indaver_water wall panel is the control-room view.
## EOP malfunction as a future plant-wide water event: backlog hook (QA:Q12).
static func _m_eop_endpoint(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.2, 0.7)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var white := _mat(Color(0.92, 0.92, 0.90), ghost, 0.1, 0.7)
	# Flat-roofed rectangular building block (container-cabin scale placeholder).
	_box(p, Vector3(size.x, size.y, size.z), Vector3(0.0, size.y * 0.5, 0.0), shell)
	# Placard on the +Z face — text is the documented name (QA:Q12 / HmiScopes
	# "Indaver waterzuivering" wording).
	_box(p, Vector3(1.7, 0.55, 0.03), Vector3(0.0, size.y * 0.72, size.z * 0.5 + 0.02), white)
	if not ghost:
		var lbl := _stencil_label(p, "EOP — INDAVER", Vector3(1.6, 0.45, 0.01), "+Z")
		lbl.position = Vector3(0.0, size.y * 0.72, size.z * 0.5 + 0.045)
	# 1. Sewer main IN (-Z face, low, largest diameter of the three).
	_cyl(p, 0.18, 0.18, 0.60, Vector3(0.0, 0.45, -size.z * 0.5 - 0.30), dark, "z")
	# 2. Purified-water return → Blauwe tank (+Z face).
	_cyl(p, 0.10, 0.10, 0.60, Vector3(size.x * 0.28, 0.65, size.z * 0.5 + 0.30), dark, "z")
	# 3. ZSS exchange pair (-X face; second stub = the `unsure` json edge).
	_cyl(p, 0.07, 0.07, 0.50, Vector3(-size.x * 0.5 - 0.25, 0.75, -0.40), dark, "x")
	_cyl(p, 0.07, 0.07, 0.50, Vector3(-size.x * 0.5 - 0.25, 0.75,  0.40), dark, "x")

# ── #201 lump_cart compound collision: real fork-pocket cavities ────────────
# The lump_cart body needs 2 horizontal tunnels (150 × 80 mm) in its underframe
# so a forklift can slide its tines straight through and then widen the
# spreader to clamp the outer pocket walls. A single AABB collision can't
# express a hole, so we synthesize the cart shape out of multiple boxes that
# COLLECTIVELY occupy the cart's volume EVERYWHERE EXCEPT the two pocket
# cavities. Dimensions match _m_lump_cart's visual mesh code so the player
# sees what the physics is doing. Pure contact physics — no joints, no
# parent-of-load magic.
static func _lump_cart_compound_collision(body: PhysicsBody3D, size: Vector3) -> void:
	# Mirror of _m_lump_cart's local frame (origin = bottom-centre of the cart).
	var wheel_r  : float = 0.07
	var frame_h  : float = 0.10
	var frame_y0 : float = wheel_r * 2.0
	var cart_w   : float = size.x * 0.88
	var cart_d   : float = size.z * 0.88
	var cart_base_y : float = frame_y0 + frame_h
	var cart_h   : float = size.y * 0.52
	var wall_t   : float = 0.025
	var pocket_w : float = 0.15
	var pocket_h : float = 0.08
	var pocket_cx : float = 0.10
	var floor_h : float = 0.0
	# ── Underframe split into 3 longitudinal strips (outer-L | between | outer-R)
	#    leaving the 2 pocket lanes open. ───────────────────────────────────────
	var fy : float = frame_y0 + frame_h * 0.5
	var l_outer_x : float = -cart_w * 0.5
	var l_inner_x : float = -pocket_cx - pocket_w * 0.5
	var r_inner_x : float =  pocket_cx + pocket_w * 0.5
	var r_outer_x : float =  cart_w * 0.5
	var mid_l_x   : float = -pocket_cx + pocket_w * 0.5
	var mid_r_x   : float =  pocket_cx - pocket_w * 0.5
	_col_box(body, Vector3(l_inner_x - l_outer_x, frame_h, cart_d + 0.10),
		Vector3((l_outer_x + l_inner_x) * 0.5, fy, 0.0))
	_col_box(body, Vector3(mid_r_x - mid_l_x, frame_h, cart_d + 0.10),
		Vector3((mid_l_x + mid_r_x) * 0.5, fy, 0.0))
	_col_box(body, Vector3(r_outer_x - r_inner_x, frame_h, cart_d + 0.10),
		Vector3((r_inner_x + r_outer_x) * 0.5, fy, 0.0))
	# ── Top cap of the underframe above the pocket cavity. The pocket is only
	#    80 mm tall; anything above pocket_h within frame_h is solid so a fork
	#    inserted in the slot bottoms out on the cavity roof. ─────────────────
	var cap_h : float = max(frame_h - pocket_h - floor_h, 0.001)
	var cap_y : float = frame_y0 + floor_h + pocket_h + cap_h * 0.5
	# Roof cap per lane (the fork lifts against it). The pocket FLOOR is visual-
	# only — a collision floor plate here penetrated the cart's own rest pose and
	# ejected the live cart on reload (round-trip drift); the wheels already carry
	# the cart, so no extra collision floor is needed.
	for px in [-pocket_cx, pocket_cx]:
		_col_box(body, Vector3(pocket_w, cap_h, cart_d + 0.10), Vector3(px, cap_y, 0.0))
	# ── Cart floor ───────────────────────────────────────────────────────────
	_col_box(body, Vector3(cart_w, wall_t, cart_d),
		Vector3(0.0, cart_base_y + wall_t * 0.5, 0.0))
	# ── Cart walls (4 sides) ─────────────────────────────────────────────────
	var cart_cy : float = cart_base_y + cart_h * 0.5
	_col_box(body, Vector3(cart_w, cart_h - wall_t, wall_t),
		Vector3(0.0, cart_cy, -cart_d * 0.5 + wall_t * 0.5))
	_col_box(body, Vector3(cart_w, cart_h - wall_t, wall_t),
		Vector3(0.0, cart_cy,  cart_d * 0.5 - wall_t * 0.5))
	_col_box(body, Vector3(wall_t, cart_h - wall_t, cart_d - wall_t * 2.0),
		Vector3(-cart_w * 0.5 + wall_t * 0.5, cart_cy, 0.0))
	_col_box(body, Vector3(wall_t, cart_h - wall_t, cart_d - wall_t * 2.0),
		Vector3( cart_w * 0.5 - wall_t * 0.5, cart_cy, 0.0))
	# ── #223 audit (critical): WHEEL contact shapes ──────────────────────────
	# Without these the lowest collision box was the underframe strip at local
	# y ≈ 0.14 (= wheel_r*2), so a cart spawned with its origin on the floor
	# free-fell 0.14 m until the underframe hit concrete — burying the visual
	# wheels (which span y 0-0.14) ENTIRELY inside the floor. That is the
	# "wheels embedded in concrete, yet draggable" bug. Four sphere contacts at
	# the visual wheel centres put the compound's lowest point at y=0 so the
	# cart rests ON the slab with wheels visible. Spheres = cheap 4-point roll.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wcol := CollisionShape3D.new()
			var wsh := SphereShape3D.new()
			wsh.radius = wheel_r
			wcol.shape = wsh
			wcol.position = Vector3(sx * cart_w * 0.42, wheel_r, sz * cart_d * 0.42)
			body.add_child(wcol)

## Compound collision for the elevated extruder feed silo. The generic single
## AABB (size.y tall, centred at size.y*0.5) filled the whole footprint from the
## floor up — including the ~2.6 m designed WALK-UNDER clearance beneath the
## raised silo box, so the operator couldn't pass under it (bughunt 2026-07-17).
## Instead: 4 slim corner-leg colliders (floor→frame underside) + the silo BODY
## box up top. The bay between the legs is left open so you can walk through and
## park a discharge cart under it, exactly as the model geometry promises.
## Mirrors the local frame of _m_extruder_silo 1:1 (frame_top / box / bw / bd).
static func _extruder_silo_compound_collision(body: PhysicsBody3D, size: Vector3) -> void:
	var frame_top : float = size.y * 0.40                # silo underside / leg top ≈ 2.6 m
	var box_top   : float = size.y * 0.92                # top of the silo box ≈ 5.98 m
	var box_h     : float = box_top - frame_top
	var box_cy    : float = (frame_top + box_top) * 0.5
	var body_scale_x : float = 2.25
	var bw : float = size.x * 0.96 * body_scale_x        # widened body (radial) — matches shell
	var bd : float = size.z * 0.96 * body_scale_x
	# ── SILO BODY: solid box occupying the upper portion only (frame_top→box_top).
	_col_box(body, Vector3(bw, box_h, bd), Vector3(0.0, box_cy, 0.0))
	# ── 4 CORNER LEGS floor→frame underside. Slightly fattened (leg_w×1.6) so the
	#    player firmly bumps them instead of threading between mesh and collider.
	var leg_w : float = 0.14 * 1.6
	var lx : float = bw * 0.5 - 0.14 * 0.6
	var lz : float = bd * 0.5 - 0.14 * 0.6
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_col_box(body, Vector3(leg_w, frame_top, leg_w),
				Vector3(sx * lx, frame_top * 0.5, sz * lz))

static func _col_box(parent: PhysicsBody3D, size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	col.shape = sh
	col.position = pos
	parent.add_child(col)

# ── #98 lumps cart (lumpenwagen): wheeled blue steel dumpster the operator
# parks under the extruder's screen-changer / melt-filter outlet. The screen
# pack catches unmelted polymer agglomerates (gels, cross-linked chunks); they
# drop into this cart. Modelled from operator photo desktop/_lumbs_cart.jpg —
# blue paint, open top, reinforced corners, steel handle bar across the front
# face, yellow hot-surface warning sticker, sits on a wooden pallet so a
# forklift can shift it once full.
static func _m_lump_cart(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	# Per operator's paint sketch: wooden pallet was wrong. The cart sits on a
	# metal under-frame plate (painted the same blue as the body) carrying TWO
	# horizontal forklift-fork pockets (one on each lateral side) and rolls on
	# 4 wheels. A push-handle made of two angled risers + a horizontal grip bar
	# sticks up off the back face so the operator can wheel the cart around.
	var blue   := _mat(Color(0.16, 0.30, 0.55), ghost, 0.30, 0.55)  # cart paint
	var _steel  := _mat(_STEEL, ghost, 0.55, 0.35)
	var grip   := _mat(Color(0.72, 0.74, 0.77), ghost, 0.95, 0.12)  # #punch: shiny grey hand-grip
	var rubber := _mat(Color(0.08, 0.08, 0.10), ghost, 0.15, 0.85)  # hard rubber wheels
	var dark   := _mat(_DARK, ghost, 0.40, 0.60)                    # pocket bores
	var yellow := _mat(_SAFETY, ghost, 0.25, 0.70)
	var wheel_r  : float = 0.07
	var wheel_d  : float = 0.05
	var frame_h  : float = 0.10
	var frame_y0 : float = wheel_r * 2.0          # frame bottom rides above wheel diameters
	var cart_w   : float = size.x * 0.88
	var cart_d   : float = size.z * 0.88
	var cart_base_y : float = frame_y0 + frame_h  # top of frame = bottom of cart body
	var cart_h   : float = size.y * 0.52
	var cart_cy  : float = cart_base_y + cart_h * 0.5
	var wall_t   : float = 0.025
	var post_t   : float = 0.05
	# ── 4 hard-rubber wheels at frame corners ────────────────────────────────
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(p, wheel_r, wheel_r, wheel_d,
				Vector3(float(sx) * (cart_w * 0.42), wheel_r,
					float(sz) * (cart_d * 0.42)), rubber, "x")
	# ── Metal under-frame: 3 longitudinal rails (outer-L | centre | outer-R)
	#    that leave TWO genuine OPEN fork channels (150 mm wide, centred ±0.10 m)
	#    running the full length — so a forklift tine slides through a real
	#    rectangular hole, NOT a solid slab. Geometry mirrors
	#    _lump_cart_compound_collision() 1:1, so what the operator sees is exactly
	#    what the physics is (operator #201-fix: "rectangular holes with guidance
	#    strips, not solid blocks — you can't put forks into a solid block").
	# ── FORK POCKETS (operator 2026-07-16: "pockets below the cart, not grooves;
	#    invisible holes are illegal"). Two ENCLOSED rectangular tube sockets under
	#    the cart — top + FLOOR + dark-lined bore so each reads as a real visible
	#    opening a fork slides into (not an open-bottom slot). Sized from real
	#    fork-pocket specs (~200 × 100 mm) and spaced 0.56 m apart (realistic fork
	#    spread), not the old 10 cm. Geometry mirrors _lump_cart_compound_collision.
	# Two PROMINENT fork-pocket housings at the base near the wheels, each a blue
	# box with a DARK rectangular OPENING on the front + back face — matching the
	# operator's rear-view sketch (2026-07-17): visible pockets + wheels + tub, not
	# invisible slots. (Physical fork-entry collision stays at the stable narrow
	# layout in _lump_cart_compound_collision; moving collision to this wide spacing
	# without save/reload drift needs a freeze-on-spawn cart redesign — flagged.)
	var uf_d  : float = cart_d + 0.10
	var uf_fy : float = frame_y0 + frame_h * 0.5
	var pv_cx : float = cart_w * 0.32                   # housing centre, just inside the wheels
	var pv_w  : float = 0.18                             # housing outer width
	var pv_ow : float = 0.11                             # pocket mouth width
	var pv_oh : float = 0.06                             # pocket mouth height
	# Cross-beam tying both housings to the tub base so they don't read as floating.
	_box(p, Vector3(pv_cx * 2.0 + pv_w, frame_h * 0.55, uf_d * 0.7),
		Vector3(0.0, uf_fy + frame_h * 0.22, 0.0), blue)
	for px in [-pv_cx, pv_cx]:
		_box(p, Vector3(pv_w, frame_h, uf_d), Vector3(px, uf_fy, 0.0), blue)                          # blue housing
		# dark opening proud of the front/back faces → reads as a real pocket mouth
		_box(p, Vector3(pv_ow, pv_oh, uf_d + 0.02), Vector3(px, frame_y0 + frame_h * 0.5, 0.0), dark)
	# ── Cart body: blue steel, open top, 4 walls + 1 bottom ──────────────────
	_box(p, Vector3(cart_w, wall_t, cart_d),
		Vector3(0.0, cart_base_y + wall_t * 0.5, 0.0), blue)
	_box(p, Vector3(cart_w, cart_h - wall_t, wall_t),
		Vector3(0.0, cart_cy, -cart_d * 0.5 + wall_t * 0.5), blue)   # front (-Z)
	_box(p, Vector3(cart_w, cart_h - wall_t, wall_t),
		Vector3(0.0, cart_cy,  cart_d * 0.5 - wall_t * 0.5), blue)   # back  (+Z)
	_box(p, Vector3(wall_t, cart_h - wall_t, cart_d - wall_t * 2.0),
		Vector3(-cart_w * 0.5 + wall_t * 0.5, cart_cy, 0.0), blue)   # left  (-X)
	_box(p, Vector3(wall_t, cart_h - wall_t, cart_d - wall_t * 2.0),
		Vector3( cart_w * 0.5 - wall_t * 0.5, cart_cy, 0.0), blue)   # right (+X)
	# ── 4 reinforced corner posts ─────────────────────────────────────────────
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(post_t, cart_h, post_t),
				Vector3(float(sx) * (cart_w * 0.5 - post_t * 0.3),
					cart_cy,
					float(sz) * (cart_d * 0.5 - post_t * 0.3)), blue)   # #punch: 4 side-pulls BLUE
	# ── Push handle: two angled risers off the back (+Z) of the cart, meeting
	#    a horizontal grip bar above. Anchored via a Node3D so the rotation
	#    handles the local-frame axis math cleanly. ──────────────────────────
	var handle_root := Node3D.new()
	handle_root.name = "Handle"
	handle_root.position = Vector3(0.0, cart_base_y + cart_h - 0.05, cart_d * 0.5 + 0.04)
	handle_root.rotation.x = deg_to_rad(-32.0)
	p.add_child(handle_root)
	var riser_len : float = size.y * 0.45
	for sx in [-1.0, 1.0]:
		_box(handle_root, Vector3(0.028, 0.028, riser_len),
			Vector3(float(sx) * cart_w * 0.40, 0.0, riser_len * 0.5), blue)   # #punch: handlebar risers BLUE
	_cyl(handle_root, 0.024, 0.024, cart_w * 0.95,
		Vector3(0.0, 0.0, riser_len), grip, "x")   # #punch: hand-grip = shiny grey metal
	# ── Hot-surface warning decal (ISO 7010 W017): yellow triangle with black
	#    border + flame/hand icon. 18 cm — readable at arm's length. Mounted on
	#    the back (+Z) face where operator approaches the handle.
	var deco_y : float = cart_cy
	var deco_z : float = cart_d * 0.5 + wall_t * 0.5 + 0.004
	var sticker_w : float = 0.18
	# Yellow triangular base
	var sticker := MeshInstance3D.new()
	var prism_y := PrismMesh.new()
	prism_y.size = Vector3(sticker_w, sticker_w, 0.006)
	sticker.mesh = prism_y
	sticker.material_override = yellow
	sticker.position = Vector3(0.0, deco_y, deco_z)
	p.add_child(sticker)
	# Black border triangle (slightly smaller, sits proud)
	var border := MeshInstance3D.new()
	var prism_border := PrismMesh.new()
	prism_border.size = Vector3(sticker_w * 0.88, sticker_w * 0.88, 0.007)
	border.mesh = prism_border
	var black_mat := _mat(Color(0.05, 0.05, 0.06), ghost, 0.20, 0.70)
	border.material_override = black_mat
	border.position = Vector3(0.0, deco_y - sticker_w * 0.03, deco_z + 0.002)
	p.add_child(border)
	# Inner yellow triangle (the ISO "field")
	var field := MeshInstance3D.new()
	var prism_field := PrismMesh.new()
	prism_field.size = Vector3(sticker_w * 0.72, sticker_w * 0.72, 0.008)
	field.mesh = prism_field
	field.material_override = yellow
	field.position = Vector3(0.0, deco_y - sticker_w * 0.06, deco_z + 0.004)
	p.add_child(field)
	# Flame icon: tall narrow box (flame body) + small wavy top
	var flame_h : float = sticker_w * 0.30
	var flame_w : float = sticker_w * 0.14
	_box(p, Vector3(flame_w, flame_h, 0.009),
		Vector3(0.0, deco_y - sticker_w * 0.18, deco_z + 0.005), black_mat)
	# Flame tip (narrower box on top)
	_box(p, Vector3(flame_w * 0.6, flame_h * 0.35, 0.009),
		Vector3(0.0, deco_y - sticker_w * 0.18 + flame_h * 0.55, deco_z + 0.005), black_mat)
	# Hand silhouette above the flame (flat box = palm)
	var hand_w : float = sticker_w * 0.18
	_box(p, Vector3(hand_w, hand_w * 0.6, 0.009),
		Vector3(0.0, deco_y - sticker_w * 0.02, deco_z + 0.005), black_mat)

# ── #98 lump_cart_spot: yellow L-bracket floor marking where the lump_cart
# is parked at shift start. Every extruder in the centre hall has one near
# its screen-changer / laser_filter discharge. Operator (extruder op) checks
# this is filled before starting the extruders.
static func _m_lump_cart_spot(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var yellow := _mat(_SAFETY, ghost, 0.10, 0.85)
	# 4 L-shaped corner brackets — thin painted stripes on concrete (4 mm tall,
	# 12 mm wide). Collision removed at build_node level so the cart rolls over.
	var bar_len : float = 0.32
	var bar_thk : float = 0.06
	var paint_h : float = 0.004
	var hx : float = size.x * 0.5
	var hz : float = size.z * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(bar_len, paint_h, bar_thk),
				Vector3(float(sx) * (hx - bar_len * 0.5), paint_h * 0.5,
					float(sz) * (hz - bar_thk * 0.5)), yellow)
			_box(p, Vector3(bar_thk, paint_h, bar_len),
				Vector3(float(sx) * (hx - bar_thk * 0.5), paint_h * 0.5,
					float(sz) * (hz - bar_len * 0.5)), yellow)

# ── #225.2 lump_platform: low steel-grating bordes the laserfilter + its two
# lump carts stand on, with an oprit (ramp) on the -Z approach side so a
# forklift rolls up to fork a cart out. Deck top = size.y (default box collision
# spans 0→size.y, so carts placed at y=size.y rest on it). Operator 2026-07-14 +
# photo _lumbs_cart.jpg (cart on a raised skid beside floor grating).
static func _m_lump_platform(p: Node3D, _size: Vector3, _color: Color, ghost: bool) -> void:
	var size : Vector3 = _size
	var grate := _mat(Color(0.50, 0.52, 0.55), ghost, 0.55, 0.45)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var dark  := _mat(_DARK, ghost, 0.4, 0.6)
	# #225.3 — the logical deck top is size.y (carts placed at y=size.y rest on the
	# box collision that spans 0→size.y). Previously the whole size.y box was drawn
	# solid, so at size.y=0.12 it read as a floor sliver. Now: a THIN walkable slab
	# at the top, standing on SHORT legs, so it reads as a real (if low) raised
	# bordes with open space beneath — and the ramp run scales with the deck height.
	var deck_top : float = size.y
	var slab_h   : float = minf(0.05, deck_top)          # thin walking plate at the top
	var slab_cy  : float = deck_top - slab_h * 0.5
	# ── Thin raised deck slab ─────────────────────────────────────────────────
	_box(p, Vector3(size.x, slab_h, size.z), Vector3(0.0, slab_cy, 0.0), grate)
	# grating slats — thin dark lines across the top so it reads as open grating
	var n_slat : int = int(size.x / 0.25)
	for si in range(n_slat):
		var sxp : float = -size.x * 0.5 + 0.125 + float(si) * 0.25
		_box(p, Vector3(0.02, 0.012, size.z * 0.98), Vector3(sxp, deck_top + 0.004, 0.0), dark)
	# ── Short legs standing the slab up into a bordes ─────────────────────────
	var leg_h : float = maxf(deck_top - slab_h, 0.0)     # floor → slab underside
	if leg_h > 0.005:
		for fx in [-1.0, 1.0]:
			for fz in [-1.0, 1.0]:
				_box(p, Vector3(0.10, leg_h, 0.10),
					Vector3(float(fx) * (size.x * 0.5 - 0.12), leg_h * 0.5, float(fz) * (size.z * 0.5 - 0.12)), steel)
		# perimeter skirt rail along the two long (±X) edges so the raised deck
		# reads as a solid bordes lip rather than a floating plate.
		for sx7 in [-1.0, 1.0]:
			_box(p, Vector3(0.03, leg_h, size.z * 0.9),
				Vector3(float(sx7) * (size.x * 0.5 - 0.02), leg_h * 0.5, 0.0), dark)
	# ── Ramp (oprit) on the -Z approach side ─────────────────────────────────
	# Wedge from the floor up to the deck edge; -Z end low, +Z (deck) end high.
	# Run scales with deck height at a walkable ~18° incline (was a fixed 0.60).
	var ramp_ang : float = deg_to_rad(18.0)
	var ramp_run : float = deck_top / tan(ramp_ang)
	var ramp_w   : float = min(size.x * 0.55, 1.4)
	var ramp_len : float = sqrt(ramp_run * ramp_run + deck_top * deck_top)
	var ramp_root := Node3D.new()
	ramp_root.name = "Ramp"
	ramp_root.position = Vector3(0.0, deck_top * 0.5, -size.z * 0.5 - ramp_run * 0.5)
	ramp_root.rotation.x = -ramp_ang     # -X rot tilts the +Z (deck) end UP
	p.add_child(ramp_root)
	_box(ramp_root, Vector3(ramp_w, 0.04, ramp_len), Vector3.ZERO, grate)
	# ramp side kerbs so a fork/wheel doesn't slide off
	for kx in [-1.0, 1.0]:
		_box(ramp_root, Vector3(0.04, 0.08, ramp_len),
			Vector3(float(kx) * ramp_w * 0.5, 0.04, 0.0), steel)

# ── #154 wardrobe locker: tall blue steel cabinet with a hi-vis vest hanging ──
## Body is a thin upright box (the size.x × size.y × size.z catalog dims).
## Right edge is the door — a slightly proud slab so the silhouette reads as
## "openable" even though we keep it static for now. A small orange rectangle
## hangs inside the upper third as a stand-in for the hi-vis vest peeking out.
static func _m_wardrobe_locker(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var paint  := _mat(color, ghost, 0.45, 0.45)                       # cabinet blue
	var dark   := _mat(_DARK, ghost, 0.45, 0.55)
	var orange := _mat(Color(0.96, 0.45, 0.12), ghost, 0.10, 0.85)     # hi-vis vest
	var hinge  := _mat(Color(0.65, 0.65, 0.68), ghost, 0.55, 0.4)      # galv hinges
	# Cabinet shell — back + 2 sides + top + bottom + (slightly recessed) front.
	# All built as a single box for now; a hollow shell is the polish pass.
	_box(p, Vector3(size.x, size.y, size.z),
		Vector3(0.0, size.y * 0.5, 0.0), paint)
	# Door slab on the +Z face, proud by ~1 cm so the seam is readable.
	var door_thk : float = 0.012
	_box(p, Vector3(size.x * 0.96, size.y * 0.96, door_thk),
		Vector3(0.0, size.y * 0.5, size.z * 0.5 + door_thk * 0.5), paint)
	# Two galvanised hinges on the right edge of the door.
	for hy in [size.y * 0.20, size.y * 0.80]:
		_box(p, Vector3(0.025, 0.05, 0.025),
			Vector3(size.x * 0.46, float(hy), size.z * 0.5 + door_thk + 0.013), hinge)
	# Dark grille slot at top (ventilation) — a thin recessed strip.
	_box(p, Vector3(size.x * 0.45, 0.035, 0.012),
		Vector3(0.0, size.y * 0.94, size.z * 0.5 + door_thk + 0.006), dark)
	# Door handle — small horizontal grip on the left edge.
	_box(p, Vector3(0.045, 0.08, 0.025),
		Vector3(-size.x * 0.36, size.y * 0.50, size.z * 0.5 + door_thk + 0.013), dark)
	# Hi-vis vest stand-in: orange rectangle floating just inside the door at
	# shoulder height. Visual cue this is the wardrobe locker.
	_box(p, Vector3(size.x * 0.45, size.y * 0.22, 0.010),
		Vector3(0.0, size.y * 0.65, size.z * 0.5 + door_thk + 0.018), orange)
	# Small label plate above the door.
	var lbl := Label3D.new()
	lbl.text = "WARDROBE"
	lbl.font_size = 24
	lbl.outline_size = 4
	lbl.pixel_size = 0.0025
	lbl.position = Vector3(0.0, size.y + 0.05, size.z * 0.5 + 0.02)
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	p.add_child(lbl)

# ── mechanical dryer: tank cylinder + top duct + base ─────────────────────────
## Mechanical dryer — modelled from operator photos (Line 3A/3B drying section):
## a HORIZONTAL drum lying on its side (long axis = Z), galvanised grey, with a
## big BLUE bolted end-flange + central square gearbox on each end, an angled
## grey discharge chute on the +Z face down to a small blue geared motor, a steel
## support cradle, blue side inspection covers, and a tall STAINLESS exhaust
## stack fed by a grey duct off the top. (The stack overshoots the bbox — that's
## fine; collision is the footprint box.)
## X3/#182 — localized steam/smoke plume rising from the given local position.
## Replaces what the mislabeled "Volumetric Fog" setting falsely promised: a
## REAL volumetric effect attached to the source, not a global haze. Cheap
## sphere-billboard GPUParticles; ~28 particles aloft at a time, drifting up
## with a slight outward spread + opacity fade over their 2.5 s lifetime.
## `radius` sizes the emission disc (~drum exhaust = 0.15, extruder die = 0.10).
## `tint` is the steam colour (white-grey for water steam; warmer for extruder).
## Skipped on ghost builds (placement preview shouldn't churn particles).
static func _install_steam_plume(parent: Node3D, local_pos: Vector3,
		radius: float, height: float, tint: Color, ghost: bool) -> void:
	if ghost or parent == null:
		return
	var emitter := GPUParticles3D.new()
	emitter.name = "SteamPlume"
	# Group tag so a machine's run-state controller (or an immersive bench that
	# wants a COLD machine) can find and gate every plume without knowing the
	# model's internal node layout. A real extruder/dryer only steams when hot.
	emitter.add_to_group("steam_plume")
	# Idle machines emit NOTHING (operator 2026-07-16: steam invented from nothing).
	# LineFlow flips .emitting true per-tick only while real material flows.
	emitter.emitting = false
	emitter.amount = 80                              # more puffs, lower alpha each → volumetric density
	emitter.lifetime = 7.0                           # long life so column fills out
	emitter.one_shot = false
	emitter.preprocess = 3.5
	emitter.explosiveness = 0.0
	emitter.fixed_fps = 30
	emitter.visibility_aabb = AABB(
		Vector3(-radius * 6.0, 0.0, -radius * 6.0),
		Vector3( radius * 12.0, height + 5.0, radius * 12.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_radius = radius * 0.6
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.05
	pm.direction = Vector3.UP
	pm.spread = 16.0
	pm.initial_velocity_min = height * 0.14
	pm.initial_velocity_max = height * 0.26
	pm.gravity = Vector3(0.0, 0.20, 0.0)
	pm.damping_min = 0.15
	pm.damping_max = 0.40
	# Per-puff rotation — critical for organic look; without this all puffs are identical.
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	pm.scale_min = radius * 0.9
	pm.scale_max = radius * 1.8
	# Puffs born tight, expand as they rise — mimics real smoke buoyancy.
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.18))
	sc.add_point(Vector2(0.35, 0.85))
	sc.add_point(Vector2(1.0, 2.2))
	pm.scale_curve = CurveTexture.new()
	(pm.scale_curve as CurveTexture).curve = sc
	# Turbulence breaks up the straight column into convincing wisps.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_noise_speed_random = 0.4
	# Color: born dark-grey at base (dense, shadowed), lightens as it rises and disperses.
	var col_base := Color(0.80, 0.82, 0.86)
	col_base = col_base.lerp(tint, 0.20)
	var dark := Color(col_base.r * 0.55, col_base.g * 0.56, col_base.b * 0.60)
	var mid  := Color(col_base.r * 0.78, col_base.g * 0.80, col_base.b * 0.84)
	var lite := col_base
	var grad := Gradient.new()
	grad.set_color(0, Color(dark.r, dark.g, dark.b, 0.0))
	grad.set_color(1, Color(lite.r, lite.g, lite.b, 0.0))
	grad.add_point(0.06, Color(dark.r, dark.g, dark.b, 0.10))
	grad.add_point(0.25, Color(mid.r,  mid.g,  mid.b,  0.13))
	grad.add_point(0.55, Color(lite.r, lite.g, lite.b, 0.09))
	grad.add_point(0.82, Color(lite.r, lite.g, lite.b, 0.04))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	emitter.process_material = pm
	# Bake a radial-falloff smoke puff texture at runtime.
	# Hard spheres were the "white circles" problem — a soft quad with a radial
	# alpha gradient reads as a genuine volumetric puff.
	var tex_sz := 64
	var img := Image.create(tex_sz, tex_sz, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(tex_sz * 0.5, tex_sz * 0.5)
	var max_r := tex_sz * 0.5
	for py in range(tex_sz):
		for px in range(tex_sz):
			var d : float = Vector2(px, py).distance_to(ctr) / max_r
			# Gaussian-ish falloff: full opacity at centre, zero at rim.
			var a : float = clampf(exp(-d * d * 3.2) - 0.04, 0.0, 1.0)
			# Subtle sine ripple breaks the perfect-circle silhouette.
			var angle : float = atan2(py - ctr.y, px - ctr.x)
			a *= 0.88 + 0.12 * sin(angle * 5.0 + d * 8.0)
			img.set_pixel(px, py, Color(1.0, 1.0, 1.0, a))
	var smoke_tex := ImageTexture.create_from_image(img)
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Operator 2026-07-16 "smoke ugly and FAKE": the depth-pre-pass alpha-scissored
	# each puff to a hard silhouette (no soft stacking) and a razor seam sliced
	# through machines. Plain ALPHA + SOFT-PARTICLE proximity fade dissolves the
	# intersection and lets low-alpha puffs blend into soft density = real vapour.
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.proximity_fade_enabled = true       # fade where a puff meets solid geometry (no clip seam)
	pmat.proximity_fade_distance = 0.6
	pmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pmat.albedo_texture = smoke_tex
	pmat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # per-particle alpha comes from color_ramp × texture
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pmat.no_depth_test = false
	# Drop the dithered near-camera fade (0.5–2 m band) — it stippled to noise
	# exactly where the player inspects a machine. proximity_fade handles clipping.
	pmat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	qm.material = pmat
	emitter.draw_pass_1 = qm
	# Back-to-front sort so low-alpha puffs blend into density instead of popping.
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.position = local_pos
	parent.add_child(emitter)
	# Player-passage disturbance: an Area3D that, while a body is inside, bumps
	# the emitter's spread + radial velocity outward so the column visibly
	# breaks. Cheaper than a real fluid sim and answers "not volumetric".
	var disturb := Area3D.new()
	disturb.name = "PlumeDisturb"
	disturb.position = Vector3(local_pos.x, local_pos.y + height * 0.5, local_pos.z)
	disturb.collision_mask = 1
	disturb.monitoring = true
	var dcs := CollisionShape3D.new()
	var dsh := SphereShape3D.new()
	dsh.radius = maxf(radius * 4.0, 1.2)
	dcs.shape = dsh
	disturb.add_child(dcs)
	parent.add_child(disturb)
	disturb.body_entered.connect(func(_b: Node3D) -> void:
		if not is_instance_valid(emitter):
			return
		var ppm : ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
		if ppm == null:
			return
		ppm.spread = 60.0
		ppm.radial_accel_min = 1.2
		ppm.radial_accel_max = 2.2
		emitter.amount_ratio = 1.0)
	disturb.body_exited.connect(func(_b: Node3D) -> void:
		if not is_instance_valid(emitter):
			return
		var ppm : ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
		if ppm == null:
			return
		ppm.spread = 22.0
		ppm.radial_accel_min = 0.0
		ppm.radial_accel_max = 0.0)

static func _m_dryer(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var galv      := _mat(color, ghost, 0.55, 0.5)                    # galvanised drum
	var blue      := _mat(Color(0.12, 0.28, 0.55), ghost, 0.45, 0.45) # RAL-blue flanges/motors
	var dark      := _mat(_DARK, ghost, 0.4, 0.6)
	var _stainless := _mat(Color(0.74, 0.76, 0.78), ghost, 0.7, 0.3)
	var hz : float = size.z * 0.5
	var rad : float = size.x * 0.42                  # drum radius
	var clear : float = 0.7                          # frame clearance under the drum
	var drum_cy : float = clear + rad                # drum centre height
	var drum_len : float = size.z * 0.84

	# ── Support cradle / skid ────────────────────────────────────────────────
	_box(p, Vector3(size.x * 0.95, 0.25, size.z * 0.95), Vector3(0.0, 0.125, 0.0), dark)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(0.18, clear, 0.18),
				Vector3(float(sx) * size.x * 0.4, clear * 0.5, float(sz) * hz * 0.78), galv)
			# Simple vertical floor legs → lengthen to the floor when raised (#70).
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", clear)
			# Heavy-duty spring vibration isolator at each foot
			_cyl(p, 0.11, 0.11, 0.14, Vector3(float(sx) * size.x * 0.4, 0.07, float(sz) * hz * 0.78), dark, "y")
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(size.x * 0.7, 0.25, 0.32),
			Vector3(0.0, drum_cy - rad * 0.7, float(sz) * hz * 0.55), galv)

	# ── Drum (horizontal cylinder along Z) — spins about its long (Z) axis ────
	_spinning_cyl(p, rad, rad, drum_len, Vector3(0.0, drum_cy, 0.0), galv, "z", Vector3.BACK, ghost)
	# Perforated stainless steel reinforcement bands along drum
	for bi in [-0.3, 0.0, 0.3]:
		_cyl(p, rad * 1.02, rad * 1.02, 0.08, Vector3(0.0, drum_cy, drum_len * bi), _stainless, "z")

	# ── Gates (Beschickungsschieber + Entleerschieber) ───────────────────────
	# Inlet on top (-Z end), outlet on bottom (+Z end)
	# Beschickungsschieber (Inlet, top, -Z)
	var besch_box := _box(p, Vector3(0.6, 0.05, 0.6), Vector3(0.0, drum_cy + rad + 0.05, -drum_len * 0.4), dark)
	var besch_gate := _box(p, Vector3(0.5, 0.05, 0.5), Vector3(0.0, drum_cy + rad + 0.05, -drum_len * 0.4), blue)
	besch_gate.name = "besch_gate"

	# Entleerschieber (Outlet, bottom, +Z)
	var entleer_box := _box(p, Vector3(0.6, 0.05, 0.6), Vector3(0.0, drum_cy - rad - 0.05, drum_len * 0.4), dark)
	var entleer_gate := _box(p, Vector3(0.5, 0.05, 0.5), Vector3(0.0, drum_cy - rad - 0.05, drum_len * 0.4), blue)
	entleer_gate.name = "entleer_gate"

	# ── Blue bolted end-flanges (both ends) + central gearbox + bolt ring ────
	for sz in [-1.0, 1.0]:
		var fz : float = float(sz) * drum_len * 0.5
		_cyl(p, rad * 1.08, rad * 1.08, 0.12, Vector3(0.0, drum_cy, fz + float(sz) * 0.06), blue, "z")
		var nb := 12
		for i in nb:
			var a : float = TAU * float(i) / float(nb)
			_box(p, Vector3(0.07, 0.07, 0.05),
				Vector3(cos(a) * rad * 0.92, drum_cy + sin(a) * rad * 0.92, fz + float(sz) * 0.12), dark)
		# central square gearbox housing + bearing boss
		_box(p, Vector3(rad * 0.5, rad * 0.5, 0.35), Vector3(0.0, drum_cy, fz + float(sz) * 0.26), blue)
		_cyl(p, rad * 0.16, rad * 0.16, 0.22, Vector3(0.0, drum_cy, fz + float(sz) * 0.46), dark, "z")

	# ── Angled discharge chute (+Z face) down to a small blue geared motor ───
	var chute := _box(p, Vector3(rad * 0.9, 1.2, 0.5), Vector3(0.0, drum_cy - rad * 0.6, hz * 0.5), galv)
	chute.rotation.x = deg_to_rad(22.0)
	_box(p, Vector3(0.5, 0.5, 0.5), Vector3(0.0, drum_cy - rad * 1.25, hz * 0.66), blue)
	_cyl(p, 0.18, 0.18, 0.4, Vector3(0.0, drum_cy - rad * 1.25, hz * 0.9), dark, "z")

	# ── Blue side inspection covers along BOTH sides of the drum (±X) ────────
	for sx in [-1.0, 1.0]:
		for i in 3:
			var iz : float = -drum_len * 0.3 + float(i) * (drum_len * 0.3)
			_box(p, Vector3(0.1, rad * 0.5, rad * 0.6), Vector3(float(sx) * rad * 1.0, drum_cy, iz), blue)

	# ── Air outlet stub (+Z face, low) — connects to blower suction duct ────
	# Mechanical dryers have no exhaust chimney (no combustion heat); air is
	# pulled through by the downstream blower. A short round stub on the +Z
	# face marks the duct connection point.
	_cyl(p, rad * 0.22, rad * 0.22, 0.30,
		Vector3(0.0, drum_cy - rad * 0.5, hz + 0.15), galv, "z")
	# X3/#182 — water-vapour plume at the air outlet. Even though the blower
	# pulls most of it downstream, a real CeDo dryer puffs a small visible
	# steam halo at the outlet stub. Cool blue-white tint.
	_install_steam_plume(p,
		Vector3(0.0, drum_cy - rad * 0.5 + 0.05, hz + 0.30),
		rad * 0.16, 1.4, Color(0.92, 0.94, 0.96), ghost)

# ── centrifuge: frame + big horizontal drum + motor + outlet ──────────────────
static func _m_centrifuge(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	_box(p, Vector3(size.x * 0.9, 0.3, size.z * 0.9), Vector3(0.0, 0.15, 0.0), dark)
	# 4 rubber vibration dampener pads under base
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(p, 0.12, 0.12, 0.06, Vector3(float(sx) * size.x * 0.38, 0.03, float(sz) * size.z * 0.38), dark, "y")
	# screen drum (lengthwise along X) — SPINS fast about X
	var cf_rm := _spinning_cyl(p, size.y * 0.38, size.y * 0.38, size.x * 0.78, Vector3(0.0, size.y * 0.6, 0.0), body_mat, "x", Vector3.RIGHT, ghost, 120.0)
	# end caps (ride with the drum so they spin too)
	_cyl(cf_rm, size.y * 0.42, size.y * 0.42, size.x * 0.08, Vector3(size.x * 0.4, 0.0, 0.0) if not ghost else Vector3(size.x * 0.4, size.y * 0.6, 0.0), dark, "x")
	# Interactive top inspection hatch with transparent grimy sight glass & latch handle
	var hatch_node := _interactive_hatch(p, Vector3(size.x * 0.35, 0.04, size.z * 0.35),
		Vector3(0.0, size.y * 0.99, 0.0), "Centrifuge Inspection Hatch", 95.0, 1.0, steel, ghost)
	if not ghost:
		# Transparent glass window in the hatch door with polymer residue/grime
		_box(hatch_node, Vector3(size.x * 0.20, 0.02, size.z * 0.20),
			Vector3(-size.x * 0.175, 0.02, 0.0), MaterialPalette.mat_glass_inspection_grime())
		_box(hatch_node, Vector3(0.04, 0.08, 0.14), Vector3(-size.x * 0.175, 0.04, 0.12), dark)

	# drive: motor + V-belt guard at -Z + cooling fins
	_motor_unit(p, size.y * 0.2, size.z * 0.3, Vector3(0.0, size.y * 0.45, -size.z * 0.45), "z", ghost)
	for fi in 6:
		var fz : float = -size.z * 0.45 + (float(fi) - 2.5) * 0.04
		_box(p, Vector3(size.y * 0.42, size.y * 0.42, 0.01), Vector3(0.0, size.y * 0.45, fz), dark)
	_guard(p, Vector3(size.x * 0.3, size.y * 0.35, size.z * 0.16), Vector3(0.0, size.y * 0.52, -size.z * 0.26), ghost)

# ── transport belt: end rollers + belt surface + side rails + legs ────────────
static func _m_belt(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	# Migrated to BeltBuilder — the spec below captures every parameter the
	# legacy in-function geometry hardcoded:
	#   deck_kind = 'flat'            (no incline pivot — flat deck)
	#   deck_y_frac = 0.75            (deck top = size.y * 0.75)
	#   deck_width_frac = 0.82        (skin = size.x * 0.82 wide)
	#   deck_thickness_m = 0.05       (skin = 0.05 m tall)
	#   deck_material = 'DARK'        (legacy used _DARK directly)
	#   deck_scroll = 0.6             (legacy make_belt_material(0.6, ...))
	#   deck_uv_tile_y_frac = 0.5     (legacy Vector2(1.0, size.z * 0.5))
	#   rollers = 'spinning_cyl'      (end rollers spin at omega = v / r)
	#   roller_radius_frac = 0.22     (legacy size.y * 0.22)
	#   side_rails = 'steel_simple'   (legacy used _STEEL → _resolve_mat 'STEEL')
	#   side_rail_thickness_m = 0.06  (legacy 0.06)
	#   side_rail_height_frac = 0.18  (legacy size.y * 0.18)
	#   has_legs = true               (legacy _legs(p, size, deck_y, steel))
	#   leg_style = 'simple'          (standard 4-leg frame)
	#   leg_material = 'STEEL'        (legacy used _STEEL)
	#   motor = 'none' / chute = 'none' / decorations = []  (legacy had none)
	#   belt_speed_mps = _BELT_CARRY_SPEED (0.4 m/s — roller rpm matches)
	# Every field above is the BeltBuilder.make_spec() default — so the entire
	# transport_belt visual collapses to the bare default spec.
	#
	# _m_belt is called from _build_model with `p` = the Model Node3D (NOT the
	# body). build_node() handles the 'belt' group + 'belt_speed' meta + the
	# BeltSurface script attachment on the BODY at a higher scope, so we use
	# build_internal() here — which builds the visual only and skips
	# apply_tagging() / placeable_id meta. Result is byte-for-byte equivalent
	# to the legacy in-function geometry: 4 legs, 2 spinning end rollers,
	# 1 scrolling deck skin, 2 steel side rails.
	var spec : Dictionary = BeltBuilder.make_spec()
	BeltBuilder.build_internal(p, "transport_belt", size, spec, ghost)

# ── funnel: wide top cone narrowing to a spout — drops material from a machine
# outlet into the next machine's inlet. Base at the local origin. ──────────────
static func _m_funnel(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.4)
	var rim   := _mat(_STEEL, ghost, 0.6, 0.35)
	var top_r   := size.x * 0.5
	var spout_r := size.x * 0.13
	var spout_h := size.y * 0.30
	var cone_h  := size.y * 0.70
	# Spout (narrow tube at the bottom)
	_cyl(p, spout_r, spout_r, spout_h, Vector3(0.0, spout_h * 0.5, 0.0), steel)
	# Cone: wide at the top, narrowing down to the spout
	_cyl(p, top_r, spout_r, cone_h, Vector3(0.0, spout_h + cone_h * 0.5, 0.0), steel)
	# Top rim ring
	_cyl(p, top_r * 1.06, top_r * 1.06, 0.06, Vector3(0.0, spout_h + cone_h, 0.0), rim)

# ── transfer chute: an angled enclosed slide that guides material from a higher
# outlet to a lower inlet. Base at the local origin; slopes toward +Z. ─────────
## Transfer chute redesigned to a proper U-trough with a flared overflow hood
## at the upstream end. Used wherever the line drops material between two
## machines at different heights — the typical case is frictiewasser →
## flotation tank, where the chute catches material spilling over the wash
## tank's +Z weir and slides it down into the flotation inlet.
##
## Geometry:
##   * Hood at the HIGH end (−Z): a wide flared mouth ~40 % wider than the
##     chute itself, top edge sitting at roughly the upstream tank's wall
##     height (≈ 1.55 m at default size). Two trapezoidal side cheeks taper
##     IN as the material funnels into the trough.
##   * Trough: a tilted floor + 2 short side walls. Open top so the player
##     can see the wash water + flake mix sliding through. Tilt is gentle
##     (≈ 18°) — wet film slides easily, no need for the steep 35° the old
##     model used (which read as a "ramp," not a chute).
##   * Outlet at the LOW end (+Z): a short rectangular spout matching the
##     downstream machine's inlet footprint.
static func _m_chute(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.45, 0.5)
	var w := size.x                                   # 0.8
	var h := size.y                                   # 1.4
	var d := size.z                                   # 1.8
	# Anchor points: high end (-Z) sits at hood_y; low end (+Z) sits at out_y.
	var hood_y : float = h * 1.10                     # ≈ 1.55 — matches frictiewasser wall top
	var out_y  : float = h * 0.30                     # ≈ 0.42 — lands above flotation inlet
	var tilt_deg : float = 18.0
	var floor_t : float = 0.06
	var wall_h  : float = 0.30
	var wall_t  : float = 0.05
	var hood_w_top  : float = w * 1.40                # flared MOUTH wider than the chute body
	var _hood_w_bot  : float = w                       # matches trough opening
	var hood_h      : float = 0.40
	var hood_d      : float = 0.45
	var hood_cz     : float = -d * 0.42
	var hood_cy     : float = hood_y - hood_h * 0.10
	# ── Hood: a thin back panel + two angled side cheeks. No mesh top — open
	#    so the player can SEE material falling into the hood. ───────────────
	# Back wall (-Z face of hood, almost vertical), painted dark so it reads
	# as a splash plate against the tank wall.
	_box(p, Vector3(hood_w_top, hood_h, wall_t),
		Vector3(0.0, hood_cy, hood_cz - hood_d * 0.50), steel)
	# Two trapezoidal side cheeks tapering hood_w_top → hood_w_bot front-to-back.
	# Cheap visual: thin angled walls that splay outward at the top.
	for sx in [-1.0, 1.0]:
		var cheek := _box(p, Vector3(wall_t, hood_h, hood_d),
			Vector3(float(sx) * hood_w_top * 0.5, hood_cy, hood_cz), steel)
		cheek.rotation.y = deg_to_rad(float(sx) * 7.0)   # splay outward
	# ── Trough floor: tilted box riding from hood mouth down to outlet. The
	#    centre rests at the midpoint of (hood_y, out_y) and ((d*0.45) wide.
	var trough_d : float = d * 1.00
	var trough_cy : float = (hood_y + out_y) * 0.5
	var slide := _box(p, Vector3(w, floor_t, trough_d),
		Vector3(0.0, trough_cy, 0.0), steel)
	slide.rotation.x = deg_to_rad(-tilt_deg)
	# ── Trough sidewalls (just along the slide so material stays in the lane).
	for sx in [-1.0, 1.0]:
		var wall := _box(p, Vector3(wall_t, wall_h, trough_d),
			Vector3(float(sx) * (w * 0.5 - wall_t * 0.5),
				trough_cy + wall_h * 0.35, 0.0), steel)
		wall.rotation.x = deg_to_rad(-tilt_deg)
	# ── Outlet spout at the +Z low end — a short rectangular collar pointing
	#    down at the next machine's inlet.
	_box(p, Vector3(w * 0.88, 0.18, 0.30),
		Vector3(0.0, out_y - 0.05, d * 0.42), steel)

# ── concrete buffer bay: a U of stacked concrete blocks (open front, +Z) that a
#    Merlo drives into to scoop the overflow film pile. ──────────────────────────
static func _m_concrete_bay(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var c1 := _mat(color, ghost, 0.15, 0.95)
	var c2 := _mat(Color(color.r * 0.9, color.g * 0.9, color.b * 0.88), ghost, 0.15, 0.95)
	var wall_t : float = 0.8
	var hx : float = size.x * 0.5
	var hz : float = size.z * 0.5
	# Ground slab.
	_box(p, Vector3(size.x, 0.2, size.z), Vector3(0.0, 0.1, 0.0), c2)
	# Back wall (-Z) + the two side walls (-X / +X); front (+Z) left open.
	_bay_wall(p, size.x, size.y, wall_t, Vector3(0.0, 0.0, -hz + wall_t * 0.5), false, c1, c2)
	_bay_wall(p, size.z - wall_t * 2.0, size.y, wall_t, Vector3(-hx + wall_t * 0.5, 0.0, 0.0), true, c1, c2)
	_bay_wall(p, size.z - wall_t * 2.0, size.y, wall_t, Vector3( hx - wall_t * 0.5, 0.0, 0.0), true, c1, c2)

## One wall of a concrete bay, built from big stacked blocks (checkerboard tint
## so the courses read). `along_z` lays the blocks along Z (a side wall) vs X.
static func _bay_wall(p: Node3D, length: float, height: float, thick: float, center: Vector3, along_z: bool, m1: StandardMaterial3D, m2: StandardMaterial3D) -> void:
	var blocks : int = maxi(int(length / 1.6), 1)
	var courses : int = maxi(int(height / 1.2), 1)
	var bl : float = length / float(blocks)
	var ch : float = height / float(courses)
	for c in courses:
		for b in blocks:
			var mat : StandardMaterial3D = m1 if (b + c) % 2 == 0 else m2
			var off : float = -length * 0.5 + (float(b) + 0.5) * bl
			if along_z:
				_box(p, Vector3(thick, ch * 0.96, bl * 0.96), center + Vector3(0.0, ch * (float(c) + 0.5), off), mat)
			else:
				_box(p, Vector3(bl * 0.96, ch * 0.96, thick), center + Vector3(off, ch * (float(c) + 0.5), 0.0), mat)

# ── #54 INTAKE CONVEYOR NETWORK ────────────────────────────────────────────────
# Twelve distinct numbered belts ferry flake from Shredder-2's climb output down
# to the switch belt. Each is a shared frame (rollers + slats + side rails)
# whose length, height, incline, and trim colour comes from the id-keyed spec
# table — that's what makes them visually distinct without 12 separate builders.
static func _transportband_spec(id: String) -> Dictionary:
	# (incline_deg, side_trim_color)
	# Incline is applied as a rotation about the X axis of the deck assembly so
	# the upstream end (-Z) sits lower or higher than the downstream end (+Z).
	match id:
		# Operator note (#141): EVERY transport belt needs some incline to actually
		# convey loose film — a truly flat belt won't push material forward. The
		# "flat" 0° values used to be wrong. Switch belt (12) stays at 0° because
		# its whole deck slides along its conveying axis for the VSS feed-split,
		# and an incline would fight that mechanism.
		"transportband_1":  return {"incline": 5.0,   "rail": Color(0.65, 0.55, 0.18)}
		"transportband_2":  return {"incline": 5.0,   "rail": Color(0.20, 0.20, 0.22)}
		"transportband_3":  return {"incline": 10.0,  "rail": Color(0.20, 0.20, 0.22)}
		"transportband_4":  return {"incline": 8.0,   "rail": Color(0.25, 0.50, 0.80)}
		"transportband_5":  return {"incline": 15.0,  "rail": Color(0.20, 0.20, 0.22)}
		"transportband_6":  return {"incline": 6.0,   "rail": Color(0.40, 0.40, 0.42)}
		"transportband_7":  return {"incline": 5.0,   "rail": Color(0.85, 0.75, 0.18)}
		"transportband_8":  return {"incline": -8.0,  "rail": Color(0.30, 0.30, 0.32)}
		# C8.5: slight DOWNHILL toward the U-bay (material is dropped on by C8 and
		# slides toward the bay). Brown rail matches the catalog colour so it reads
		# as a different belt from the numbered chain even at distance.
		"transportband_8_5":return {"incline": -6.0,  "rail": Color(0.52, 0.36, 0.18)}
		"transportband_9":  return {"incline": 4.0,   "rail": Color(0.42, 0.42, 0.46)}
		"transportband_10": return {"incline": 5.0,   "rail": Color(0.25, 0.60, 0.35)}
		"transportband_11": return {"incline": 12.0,  "rail": Color(0.20, 0.20, 0.22)}
		"transportband_12": return {"incline": 0.0,   "rail": Color(0.55, 0.55, 0.60)}
	return {"incline": 0.0, "rail": Color(0.30, 0.30, 0.34)}

static func _m_intake_belt(p: Node3D, id: String, size: Vector3, _color: Color, ghost: bool) -> void:
	# Migrated to BeltBuilder. The legacy _transportband_spec() table still
	# supplies the per-id incline + rail accent colour; here we translate that
	# into a BeltSpec dict that the central builder consumes.
	#
	# Legacy behaviour preserved 1:1 — same legs (simple steel, deck_y = size.y *
	# 0.75), same DeckPivot (tilted about X by -incline_deg), same spinning end
	# rollers (radius 0.20 * size.y, rpm tracking _INTAKE_BELT_SPEED_MPS), same
	# 0.82-width deck with the _INTAKE_BELT_SHADER_SCROLL scrolling material,
	# same painted-accent rails (0.08 thick × 0.22 high × 0.95 length, at ±0.44 *
	# size.x), same upstream motor housing, same four-wall discharge chute
	# parented under `p` so it hangs vertical.
	#
	# Tagging is left to the existing build_node() block (line 862) which
	# already adds the body to the 'belt' group, sets belt_speed meta, and
	# attaches BeltSurface for intake belts. We therefore set tag_as_belt=false
	# AND has_legs=false would skip BOTH — but we still want legs, so we keep
	# has_legs=true and only mute tagging to avoid double-tagging.
	var tspec : Dictionary = _transportband_spec(id)
	var s : Dictionary = BeltBuilder.make_spec()
	s.deck_kind = "tilted"
	s.incline_deg = float(tspec["incline"])
	s.deck_y_frac = 0.75
	s.deck_width_frac = 0.82
	s.deck_thickness_m = 0.05
	s.deck_material = "DARK"
	s.deck_scroll = _INTAKE_BELT_SHADER_SCROLL
	s.deck_uv_tile_y_frac = 0.5
	s.rollers = "spinning_cyl"
	s.roller_radius_frac = 0.20
	s.side_rails = "painted_accent"
	s.rail_color = tspec["rail"]
	s.side_rail_thickness_m = 0.08
	s.side_rail_height_frac = 0.22
	s.has_legs = true
	s.leg_style = "simple"
	s.leg_material = "STEEL"
	s.motor = "small_housing"
	s.chute = "discharge_intake"
	s.chute_size_m = Vector3(0.30, 0.25, 0.30)
	s.belt_speed_mps = _INTAKE_BELT_SPEED_MPS
	# Caller (build_node) already tags the body as a belt and attaches
	# BeltSurface — disable the builder's tagging path so we don't run the same
	# work twice and (incidentally) overwrite metas the caller already set.
	s.tag_as_belt = false
	BeltBuilder.build(p, id, size, s, ghost)

# ── switch_belt (= conveyor 12, operator-spec #137): flat belt whose ENTIRE
#    DECK slides along its conveying axis ±1.5 m, feeding either VSS_3A
#    (at -1.5 m) or VSS_3B (at +1.5 m), with a smooth blend at intermediate
#    positions. The legs / pulleys stay put; only the deck assembly under the
#    "Deck" node moves. A pair of position-rail markers along the chassis
#    show how far the deck has jogged off-centre.
static func _m_switch_belt(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	# Migrated to BeltBuilder (see BeltBuilder.gd). The spec captures every
	# legacy magic number 1:1 — deck_y_frac 0.72, deck_width_frac 0.85, deck_t
	# 0.05, scrolling belt material (scroll 0.6, uv_y_frac 0.5), static cyl
	# rollers of radius 0.18 * size.y, deck-side steel rails (0.08 ×
	# 0.20 * size.y × 0.95 * size.z), standard 4-leg steel frame, sliding inner
	# 'Deck' Node3D for SwitchBelt.gd, and the 'switch_belt' marker meta via
	# the decoration token.
	#
	# Two switch-belt features are NOT covered by BeltBuilder primitives and
	# run through the `extras` callable below:
	#   1. Orange position-rail chassis housings (parented to `p`, NOT the
	#      sliding Deck — they stay rigid while the deck jogs through them).
	#
	# Tagging contract is left to PlaceableCatalog.build_node()'s existing
	# belt-tagging block (around line 862) — tag_as_belt=false here avoids
	# double-tagging while the rest of the belt family is still on the legacy
	# path. The 'switch_belt' marker meta IS written by BeltBuilder via the
	# 'switch_belt_marker_meta' decoration, preserving the legacy contract for
	# LineFlow.
	var spec := BeltBuilder.make_spec()
	spec.deck_kind = "flat"
	spec.deck_y_frac = 0.72
	spec.deck_width_frac = 0.85
	spec.deck_thickness_m = 0.05
	spec.deck_material = "DARK"
	spec.deck_scroll = 0.6
	spec.deck_uv_tile_y_frac = 0.5
	spec.sliding_deck = true            # builds inner 'Deck' Node3D
	spec.rollers = "static_cyl"         # legacy used non-spinning _cyl
	spec.roller_radius_frac = 0.18
	spec.side_rails = "steel_simple"
	spec.side_rail_thickness_m = 0.08
	spec.side_rail_height_frac = 0.20
	spec.has_legs = true
	spec.leg_style = "simple"
	spec.leg_material = "STEEL"
	spec.motor = "none"
	spec.chute = "none"
	spec.decorations = ["switch_belt_marker_meta"]   # sets meta('switch_belt')
	spec.extras = [Callable(PlaceableCatalog, "_switch_belt_chassis_extras")]
	spec.tag_as_belt = false            # build_node() still owns belt tagging
	BeltBuilder.build(p, "switch_belt", size, spec, ghost)

# `extras` callable for switch_belt — builds the two orange position-rail
# chassis housings under `p` (NOT the sliding Deck root). These are wider than
# the deck travel range so the operator can see the jog at a glance, and they
# stay rigid while SwitchBelt.gd translates the Deck child ±1.5 m through them.
# Signature matches BeltBuilder.build_internal's extras dispatch:
#   f(p, deck_root, size, spec, ghost).
static func _switch_belt_chassis_extras(p: Node3D, _deck_root: Node3D,
		size: Vector3, spec: Dictionary, ghost: bool) -> void:
	var orange := _mat(Color(0.85, 0.45, 0.10), ghost, 0.4, 0.5)
	var deck_y : float = size.y * float(spec.get("deck_y_frac", 0.72))
	_box(p, Vector3(0.08, size.y * 0.10, size.z * 1.30),
		Vector3( size.x * 0.48, deck_y - 0.05, 0.0), orange)
	_box(p, Vector3(0.08, size.y * 0.10, size.z * 1.30),
		Vector3(-size.x * 0.48, deck_y - 0.05, 0.0), orange)

# ── vss_silo: tall round metering silo with a conical bottom and side feed
#    ports near the top. Smaller cousin of the main extruder silo. ─────────────
static func _m_vss_silo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var dark  := _mat(_DARK, ghost, 0.3, 0.7)
	var rim   := _mat(_STEEL, ghost, 0.55, 0.4)
	var r : float = size.x * 0.5
	var body_h : float = size.y * 0.65
	var cone_h : float = size.y * 0.20
	var leg_h  : float = size.y * 0.15
	# Four legs holding the cone up off the floor (tagged 'machine_leg' so extend_machine_legs() can raise the silo for a discharge cart).
	_legs(p, size, leg_h, dark)
	# Cone bottom — narrow at the bottom (discharge), wide at the top.
	_cyl(p, r, 0.12, cone_h, Vector3(0.0, leg_h + cone_h * 0.5, 0.0), shell)
	# Cylindrical body.
	_cyl(p, r, r, body_h, Vector3(0.0, leg_h + cone_h + body_h * 0.5, 0.0), shell)
	# Top rim.
	_cyl(p, r * 1.05, r * 1.05, 0.08, Vector3(0.0, leg_h + cone_h + body_h, 0.0), rim)
	# Side feed inlet near the top (+X side).
	_cyl(p, 0.18, 0.18, 0.5, Vector3(r + 0.20, leg_h + cone_h + body_h * 0.85, 0.0), dark, "x")
	# Discharge stub at the bottom of the cone.
	_cyl(p, 0.14, 0.14, 0.3, Vector3(0.0, leg_h - 0.05, 0.0), dark)

# ── u_bay (stortvak): operator-spec 6.25 m tall stacked-concrete-block surge pit.
#    Walls are built BRICK-BY-BRICK with the standard 1/2 overlap pattern (each
#    course offset by half a block from the one below) so the masonry reads as
#    real building-code stacked concrete, not a smooth box. The two outer ends
#    of the side walls are removed (per operator) — the side walls only extend
#    ~50% of the depth from the back wall, giving the "small u" silhouette while
#    keeping the same overall X width. Floor still a poured-concrete slab with a
#    centre drain so washing water has somewhere to go. ──
## Block + wall geometry (operator-tuned, second pass). Blocks are 150 % larger
## in every dimension than the first pass — that's the Legioblock / industrial
## precast-concrete size (~1.5 m × 0.6 m × 0.9 m) you'd actually build a surge
## pit with. Wall heights differ per face: BACK is the retaining wall (taller),
## SIDES are lower so a Merlo can scoop over them; both fractions are of the
## catalog size.y. SIDE_FRAC is the proportion of the bay depth each side wall
## covers from the back inward — leaving the front and a chunk of the sides
## open ("small u" silhouette per operator).
const _UBAY_BRICK_W       : float = 1.50
const _UBAY_BRICK_H       : float = 0.60
const _UBAY_WALL_T        : float = 0.90
const _UBAY_SIDE_FRAC     : float = 0.575   # 50% × 1.15 (sides extended 15%)
const _UBAY_BACK_HEIGHT_F : float = 0.85    # back wall is 15% lower than size.y
const _UBAY_SIDE_HEIGHT_F : float = 0.60    # side walls are 40% lower

static func _m_u_bay(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var c1 := _mat(color, ghost, 0.15, 0.95)
	var c2 := _mat(Color(color.r * 0.9, color.g * 0.9, color.b * 0.88), ghost, 0.15, 0.95)
	var hx : float = size.x * 0.5
	var hz : float = size.z * 0.5
	# Poured-concrete floor slab.
	_box(p, Vector3(size.x, 0.25, size.z), Vector3(0.0, 0.125, 0.0), c2)
	# Drain grate in the centre.
	var drain := _mat(Color(0.35, 0.35, 0.38), ghost, 0.6, 0.4)
	_box(p, Vector3(0.5, 0.05, 0.5), Vector3(0.0, 0.255, 0.0), drain)
	# BACK wall (full width along X, the bottom of the letter u). Centred on -Z
	# edge. Taller than the sides so material doesn't slosh out the back.
	var back_h : float = size.y * _UBAY_BACK_HEIGHT_F
	var back_centre := Vector3(0.0, 0.25, -hz + _UBAY_WALL_T * 0.5)
	_ubay_brick_wall(p, size.x, back_h, _UBAY_WALL_T, back_centre, true,  c1, c2, ghost)
	# SIDE walls — 40% lower than back, and only cover SIDE_FRAC of the depth
	# (front portion of each side stays open). Operator's "small u" silhouette.
	var side_h : float = size.y * _UBAY_SIDE_HEIGHT_F
	var side_len : float = (size.z - _UBAY_WALL_T) * _UBAY_SIDE_FRAC
	# Place the side wall so its NEAR end is flush with the back wall, then it
	# extends forward (+Z) by side_len.
	var side_centre_z : float = -hz + _UBAY_WALL_T + side_len * 0.5
	var left_centre  := Vector3(-hx + _UBAY_WALL_T * 0.5, 0.25, side_centre_z)
	var right_centre := Vector3( hx - _UBAY_WALL_T * 0.5, 0.25, side_centre_z)
	_ubay_brick_wall(p, _UBAY_WALL_T, side_h, side_len, left_centre,  false, c1, c2, ghost)
	_ubay_brick_wall(p, _UBAY_WALL_T, side_h, side_len, right_centre, false, c1, c2, ghost)

## Procedural stacked-block wall. `x_aligned` true → wall runs along X (back
## wall, narrow on Z); false → wall runs along Z (side wall, narrow on X). Rows
## alternate offset by half a block, matching real masonry. Per-row tone
## alternates between the two materials so the joints read even at distance.
static func _ubay_brick_wall(parent: Node3D, sx: float, sy: float, sz: float,
		centre: Vector3, x_aligned: bool,
		mat_light: StandardMaterial3D, mat_dark: StandardMaterial3D, _ghost: bool) -> void:
	var brick_w : float = _UBAY_BRICK_W
	var brick_h : float = _UBAY_BRICK_H
	# Number of rows; round up so we cover sy fully (the top row clips slightly).
	var n_rows : int = int(ceil(sy / brick_h))
	var wall_length : float = sx if x_aligned else sz
	var wall_thick  : float = sz if x_aligned else sx
	for row in n_rows:
		var row_y : float = brick_h * (float(row) + 0.5)
		# Row top can't poke above sy — clip the topmost row.
		var h_used : float = brick_h * 0.95
		if row_y + brick_h * 0.5 > sy:
			h_used = (sy - brick_h * float(row)) * 0.95
			if h_used <= 0.0:
				continue
		# Half-block offset on alternating rows ─ that's the building-code 1/2
		# overlap pattern the operator asked for.
		var offset : float = brick_w * 0.5 if row % 2 == 1 else 0.0
		var row_mat : StandardMaterial3D = mat_dark if row % 2 == 1 else mat_light
		# Lay bricks across the wall length; clip the end bricks so the wall ends
		# stay square rather than poking out.
		var pos : float = -wall_length * 0.5 + offset
		# Pre-roll: a half-brick stub at the START of odd rows so the row begins
		# flush with the wall's edge.
		if offset > 0.0:
			var stub : float = offset
			var stub_pos : float = -wall_length * 0.5 + stub * 0.5
			_ubay_lay_brick(parent, stub * 0.96, h_used, wall_thick,
				centre, stub_pos, row_y, x_aligned, row_mat)
		while pos + brick_w <= wall_length * 0.5:
			var bw : float = brick_w
			_ubay_lay_brick(parent, bw * 0.96, h_used, wall_thick,
				centre, pos + bw * 0.5, row_y, x_aligned, row_mat)
			pos += brick_w
		# Tail half-brick at the END of the row if a partial fits.
		var tail : float = wall_length * 0.5 - pos
		if tail > 0.05:
			var tail_pos : float = pos + tail * 0.5
			_ubay_lay_brick(parent, tail * 0.96, h_used, wall_thick,
				centre, tail_pos, row_y, x_aligned, row_mat)

static func _ubay_lay_brick(parent: Node3D, length: float, h_used: float, thick: float,
		centre: Vector3, pos_along: float, row_y: float, x_aligned: bool,
		mat: StandardMaterial3D) -> void:
	var brick_size : Vector3
	var brick_pos : Vector3
	if x_aligned:
		brick_size = Vector3(length, h_used, thick)
		brick_pos  = centre + Vector3(pos_along, row_y, 0.0)
	else:
		brick_size = Vector3(thick, h_used, length)
		brick_pos  = centre + Vector3(0.0, row_y, pos_along)
	_box(parent, brick_size, brick_pos, mat)

# ── cyclone: cylinder body + downward cone + top outlet + tangential inlet ─────
static func _m_cyclone(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var r := size.x * 0.42
	# #107 — 3 support legs reach the cone's WIDE end. Cone has its narrow tip
	# DOWN and the wide flange at +Y; legs ride from the floor up to a ring
	# bracket bolted around the cone's wide end. Previous version used short
	# 7% legs that didn't even touch the cone (legs only reached 7% size.y but
	# the cone wide-end sat at 53% size.y, leaving an obvious floating gap).
	# Removed the "soda can" discharge stub that was just visual clutter under
	# the cone tip.
	var leg_h : float = size.y * 0.55                  # legs reach the cone's wide-end ring
	var cone_h : float = size.y * 0.45
	var body_h : float = size.y * 0.40
	var ring_r : float = r * 0.92                      # bracket ring radius around cone wide-end
	for li in 3:
		var ang : float = TAU * float(li) / 3.0
		# Square-tube leg from the floor (y=0) up to leg_h.
		var lg := _box(p, Vector3(0.10, leg_h, 0.10),
			Vector3(cos(ang) * ring_r, leg_h * 0.5, sin(ang) * ring_r), dark)
		lg.add_to_group("machine_leg")
		lg.set_meta("leg_h", leg_h)
		# Diagonal brace from each leg back to the cone tip — reads as a real
		# tripod stand rather than 3 isolated posts.
		var brace_len : float = sqrt(ring_r * ring_r + leg_h * leg_h)
		var brace := _box(p, Vector3(0.06, 0.06, brace_len),
			Vector3(cos(ang) * ring_r * 0.5, leg_h * 0.35,
					sin(ang) * ring_r * 0.5), steel)
		brace.rotation = Vector3(0.0, ang + PI * 0.5, atan2(leg_h, ring_r))
	# Ring bracket at the top of the legs — sits at leg_h, hugs the cone's
	# widest section so the legs visibly carry the cyclone.
	_cyl(p, ring_r * 1.03, ring_r * 1.03, 0.06, Vector3(0.0, leg_h, 0.0), steel)
	# Cone (narrow tip DOWN, wide flange at the top resting on the bracket).
	_cyl(p, r, 0.10, cone_h, Vector3(0.0, leg_h + cone_h * 0.5 - cone_h * 0.05, 0.0), shell)
	# Upper cylindrical body sits ON the cone's wide end.
	var body_cy : float = leg_h + cone_h + body_h * 0.5
	_cyl(p, r, r, body_h, Vector3(0.0, body_cy, 0.0), shell)
	# Central clean-air outlet pipe up the middle.
	_cyl(p, r * 0.35, r * 0.35, size.y * 0.18,
		Vector3(0.0, body_cy + body_h * 0.5 + size.y * 0.08, 0.0), steel)
	# Tangential inlet near the top of the body (+X side).
	_box(p, Vector3(size.x * 0.5, size.y * 0.16, size.z * 0.28),
		Vector3(size.x * 0.36, body_cy + body_h * 0.15, 0.0), steel)

# #79 ── CYCLONE ON SUPPORT TOWER ──────────────────────────────────────────────
# A standalone elevated cyclone for cyclone→silo gravity-drop placements: the
# top half of the model is a normal cyclone (cone + cylinder + clean-air outlet
# + tangential feed inlet); the bottom half is a 4-leg braced steel tower that
# raises the cone tip up above the floor so material falling out the spout
# lands on whatever silo top is placed underneath. The 3A recirc loop uses this
# (cyclone drops back into the mengsilo from above) but it works anywhere a
# cyclone is needed at silo-top height instead of belt-deck height.
static func _m_cyclone_tower(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell  := _mat(color, ghost, 0.4, 0.45)
	var steel  := _mat(_STEEL, ghost, 0.5, 0.45)
	var dark   := _mat(_DARK, ghost, 0.4, 0.6)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)

	# Cyclone body lives in the TOP ~40% of size.y; the support tower fills the
	# bottom ~60%. With size.y=8 → tower from 0→4.8 m, cyclone from 4.8→8.0 m.
	var tower_top : float = size.y * 0.55
	var cyc_h     : float = size.y - tower_top      # 3.6 m of cyclone above
	var hw        : float = size.x * 0.5
	var hd        : float = size.z * 0.5
	var r         : float = size.x * 0.40

	# ── SUPPORT TOWER: 4 corner legs to the floor + horizontal + diagonal braces ─
	var leg_w : float = 0.16
	var lx : float = hw - leg_w * 0.6
	var lz : float = hd - leg_w * 0.6
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(leg_w, tower_top, leg_w),
				Vector3(sx * lx, tower_top * 0.5, sz * lz), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", tower_top)
	# Three horizontal brace bands around the perimeter.
	for by in [tower_top * 0.30, tower_top * 0.60, tower_top * 0.95]:
		_box(p, Vector3(lx * 2.0, 0.08, 0.08), Vector3(0.0, by,  lz), steel)
		_box(p, Vector3(lx * 2.0, 0.08, 0.08), Vector3(0.0, by, -lz), steel)
		_box(p, Vector3(0.08, 0.08, lz * 2.0), Vector3( lx, by, 0.0), steel)
		_box(p, Vector3(0.08, 0.08, lz * 2.0), Vector3(-lx, by, 0.0), steel)
	# Diagonal X-bracing on the two side faces (±X) — a single \-brace each.
	var brace_len : float = sqrt(tower_top * tower_top + (lz * 2.0) * (lz * 2.0))
	for sx2 in [-1.0, 1.0]:
		var diag := _box(p, Vector3(0.06, 0.06, brace_len),
			Vector3(sx2 * lx, tower_top * 0.5, 0.0), steel)
		diag.rotation.x = atan2(lz * 2.0, tower_top)
	# Landing deck at tower top so the cyclone visually sits on something solid.
	_box(p, Vector3(hw * 2.0 + 0.10, 0.06, hd * 2.0 + 0.10),
		Vector3(0.0, tower_top + 0.03, 0.0), steel)
	# Safety-yellow guardrails around the landing.
	_railing(p, hw + 0.05, hd + 0.05, tower_top + 0.06, yellow)

	# ── CYCLONE BODY on top of the tower ────────────────────────────────────────
	# Cone (narrow at the bottom) — its TIP sits a touch below the tower top so
	# discharge happens right at deck level, dropping material straight down past
	# the deck (through a central well) onto whatever sits under the tower.
	var tip_y : float = tower_top - 0.10            # tip just under the deck
	var cone_h : float = cyc_h * 0.42
	_cyl(p, r, 0.08, cone_h, Vector3(0.0, tip_y + cone_h * 0.5, 0.0), shell)
	# Discharge well — a short pipe through the deck so the spout reads as
	# CONNECTED to whatever's below, not just floating over a hole.
	_cyl(p, 0.10, 0.10, 0.40, Vector3(0.0, tower_top - 0.20, 0.0), dark)
	# Upper cylindrical body sitting on the cone.
	var body_h : float = cyc_h * 0.46
	var body_cy : float = tip_y + cone_h + body_h * 0.5
	_cyl(p, r, r, body_h, Vector3(0.0, body_cy, 0.0), shell)
	# Central clean-air outlet up the top.
	_cyl(p, r * 0.35, r * 0.35, cyc_h * 0.18,
		Vector3(0.0, body_cy + body_h * 0.5 + cyc_h * 0.08, 0.0), steel)
	# Tangential feed inlet on the +X side near the top of the body.
	_box(p, Vector3(size.x * 0.45, body_h * 0.40, size.z * 0.26),
		Vector3(size.x * 0.32, body_cy + body_h * 0.20, 0.0), steel)

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
	# Spinning impeller visible at the +X inlet eye: a hub + radial blades on a
	# RotatingMechanism (axis X) so the fan obviously turns.
	if not ghost:
		var imp := _RM_SCRIPT.new()
		imp.axis = Vector3.RIGHT; imp.rpm = 220.0; imp.nominal_rpm = 220.0; imp.capacity_kg_s = 1.0
		imp.position = Vector3(size.x * 0.24, size.y * 0.5, 0.0)
		p.add_child(imp)
		_cyl(imp, size.y * 0.1, size.y * 0.1, 0.06, Vector3.ZERO, dark, "x")   # hub
		for b in 6:
			var a : float = TAU * float(b) / 6.0
			_box(imp, Vector3(0.04, size.y * 0.34, 0.05),
				Vector3(0.0, sin(a) * size.y * 0.18, cos(a) * size.y * 0.18), body_mat)

# ── control cabinet (PCU): housing + HMI screen + vents + handle ──────────────
## E-kast (PCU control cabinet) — modelled from the real CeDo photo. Three off-white
## painted-steel bays on a dark plinth: left blank door, centre control panel with
## HMI screen + indicator-light bank + two analog gauges + big rotary selector,
## right blank door. Vertical door seams and stainless handles on every bay. The
## yellow CAUTION placard is a thin proud-sticker. Geometry all procedural; the
## bay bodies carry the photo-extracted cream-steel palette mat, the rest stays
## flat _mat colours (lenses / lamps / decals opt out per the palette doc).
static func _m_cabinet(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat  := _mat(color, ghost, 0.25, 0.55)               # off-white painted steel
	if not ghost:
		# Photo-extracted cream painted steel — MaterialPalette grounds the
		# machines/paint_cream_steel triplet in _extruder_silo.png + _e_kast.png
		# and names the E-kast as a consumer. Shared opaque singleton, so ghosts
		# keep the translucent _mat above.
		body_mat = MaterialPalette.mat_paint_cream_steel()
	var plinth    := _mat(Color(0.28, 0.25, 0.22), ghost, 0.15, 0.85)  # dirty concrete-coloured base
	var dark      := _mat(_DARK, ghost, 0.2, 0.4)                 # door seams + HMI bezel
	var steel     := _mat(_STEEL, ghost, 0.7, 0.25)               # handles, screws, gauge bezels
	var screen    := _mat(Color(0.16, 0.22, 0.16), ghost, 0.05, 0.20)  # HMI panel (off, faint glow)
	var hmi_glow  := _mat(Color(0.45, 0.85, 0.55), ghost, 0.0, 0.10)   # HMI on screen
	var selector  := _mat(Color(0.08, 0.08, 0.09), ghost, 0.3, 0.45)
	var caution   := _mat(Color(0.95, 0.78, 0.10), ghost, 0.1, 0.85)
	# Indicator-light colours (small bulbs on the lamp bank).
	var red       := _mat(Color(0.85, 0.18, 0.16), ghost, 0.0, 0.45)
	var green     := _mat(Color(0.25, 0.78, 0.32), ghost, 0.0, 0.45)
	var amber     := _mat(Color(0.95, 0.65, 0.10), ghost, 0.0, 0.45)
	# White face        : Color(0.86, 0.84, 0.79)  ← `color`
	# Dimensions are in metres. Origin: centre-bottom of footprint; +Z is front face.
	var W := size.x; var H := size.y; var D := size.z
	var plinth_h := 0.18
	var body_h   := H - plinth_h
	# ── plinth (dirty rust-stained concrete look) ─────────────────────────────
	_box(p, Vector3(W * 0.98, plinth_h, D * 0.98), Vector3(0.0, plinth_h * 0.5, 0.0), plinth)
	# ── main body (three side-by-side bays merged into one box) ───────────────
	_box(p, Vector3(W, body_h, D), Vector3(0.0, plinth_h + body_h * 0.5, 0.0), body_mat)
	# Door seams: thin dark strips dividing the three bays on the front face.
	var seam_z : float = D * 0.5 + 0.003   # poke proud of the front face
	_box(p, Vector3(0.012, body_h * 0.96, 0.004), Vector3(-W / 6.0, plinth_h + body_h * 0.5, seam_z), dark)
	_box(p, Vector3(0.012, body_h * 0.96, 0.004), Vector3( W / 6.0, plinth_h + body_h * 0.5, seam_z), dark)
	# Bay centres (in X) — left, centre, right.
	var bay_x : Array[float] = [-W / 3.0, 0.0, W / 3.0]
	# Door handles: vertical stainless bar on each bay, near the adjacent seam.
	var handle_y : float = plinth_h + body_h * 0.45
	_box(p, Vector3(0.03, body_h * 0.20, 0.045), Vector3(bay_x[0] + 0.30, handle_y, seam_z + 0.022), steel)
	_box(p, Vector3(0.03, body_h * 0.20, 0.045), Vector3(bay_x[1] + 0.30, handle_y, seam_z + 0.022), steel)
	_box(p, Vector3(0.03, body_h * 0.20, 0.045), Vector3(bay_x[2] - 0.30, handle_y, seam_z + 0.022), steel)
	# Hinge pins (small dark dots near the opposite edge of each bay).
	for bi in bay_x.size():
		var hinge_x : float = bay_x[bi] - 0.30 if bi < 2 else bay_x[bi] + 0.30
		for hy in [0.4, 1.2]:
			_box(p, Vector3(0.02, 0.04, 0.01), Vector3(hinge_x, plinth_h + hy, seam_z), dark)
	# ── CENTRE BAY: HMI screen + indicator lights + gauges + selector + sticker ──
	var cx : float = bay_x[1]
	var front : float = D * 0.5 + 0.008
	# HMI screen (recessed bezel + glowing panel inside).
	_box(p, Vector3(0.62, 0.34, 0.012), Vector3(cx, plinth_h + body_h * 0.78, front), dark)
	_box(p, Vector3(0.56, 0.28, 0.020), Vector3(cx, plinth_h + body_h * 0.78, front + 0.005), screen)
	_box(p, Vector3(0.46, 0.20, 0.024), Vector3(cx, plinth_h + body_h * 0.78, front + 0.008), hmi_glow)
	# Indicator-light bank: 2 rows × 8 columns of small bulbs (RGB pattern).
	var lamp_y0 : float = plinth_h + body_h * 0.58
	var lamps : Array = [red, green, amber, red, green, green, amber, red]
	for row in 2:
		for i in 8:
			var lx : float = cx + (float(i) - 3.5) * 0.060
			_cyl(p, 0.014, 0.014, 0.012, Vector3(lx, lamp_y0 + float(row) * 0.058, front + 0.006), lamps[i], "z")
	# Two analog gauges (top-right of the centre bay).
	for gi in 2:
		var gx : float = cx + 0.22 + float(gi) * 0.16
		var gy : float = plinth_h + body_h * 0.78
		_cyl(p, 0.055, 0.055, 0.020, Vector3(gx, gy, front + 0.010), steel, "z")
		_cyl(p, 0.045, 0.045, 0.022, Vector3(gx, gy, front + 0.015), screen, "z")
	# Big black rotary selector (bottom-right of the centre bay).
	_cyl(p, 0.045, 0.045, 0.025, Vector3(cx + 0.30, plinth_h + body_h * 0.40, front + 0.012), selector, "z")
	_box(p, Vector3(0.06, 0.012, 0.020), Vector3(cx + 0.30, plinth_h + body_h * 0.40, front + 0.025), steel)
	# Yellow CAUTION placard, slightly left of selector.
	_box(p, Vector3(0.18, 0.10, 0.005), Vector3(cx - 0.20, plinth_h + body_h * 0.40, front + 0.008), caution)
	# Small steel push-button strip below the lamps.
	for i in 6:
		var bx : float = cx + (float(i) - 2.5) * 0.075
		_cyl(p, 0.018, 0.018, 0.014, Vector3(bx, plinth_h + body_h * 0.50, front + 0.007), steel, "z")
	# ── Top rim / shadow line (thin dark cap) ─────────────────────────────────
	_box(p, Vector3(W * 1.005, 0.025, D * 1.005), Vector3(0.0, H - 0.012, 0.0), dark)

# ── _m_waterpomp + _m_ringleiding_3a DELETED ─────────────────────────────────
# Both builders had no live caller after the catalog dedupe (waterpomp + ringleiding_3a
# catalog ids removed). The canonical ids are water_pump (→ _m_pump) and ringleiding
# (→ _m_ringleiding). The detailed teal/grey Wilo pump model and the caged Line-3A
# ring-main model are in git history at this file if a future variant ever needs them.


# ── Compactor feed belt (inclined, dust-hooded) ───────────────────────────────
## Heavy inclined conveyor that feeds material UP into a compactor: black side
## panels with yellow guard, galvanized I-beam legs anchored to the floor, a
## stainless dust extraction hood at the discharge end, and a blue blower at
## ground level whose stainless duct routes up + across to the hood. Modelled
## from the two CeDo photos (ground-level front-right + top rear-left).
##
## Layout in LOCAL space (origin = mid-footprint, +X toward the discharge end):
##   feed end at x = -size.x*0.5 (low), discharge at x = +size.x*0.30 (high)
##   belt runs along the local X axis, inclined ~28° from horizontal
static func _m_compactor_belt(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	# Migrated to BeltBuilder. The compactor_belt is a Z-axis-rotated inclined
	# conveyor with bespoke I-beam legs, yellow wire-mesh guard rail, stainless
	# dust hood + flue, and a blue blower with ducts. None of these match the
	# stock BeltBuilder deck/leg/rail/chute primitives 1:1 (the belt runs along
	# local X, not Z; legs sit at fractional-W intervals along the inclined
	# axis; the guard rail is a free-standing mesh in front of the belt).
	#
	# Rather than balloon BeltBuilder's decoration vocabulary for a single-id
	# placeable, we use deck_kind='none' + every component 'none' and route
	# ALL legacy geometry through an `extras` callable that produces the same
	# byte-for-byte primitives as the legacy builder.
	#
	# tag_as_belt=false preserves the legacy contract: compactor_belt is not in
	# _BELT_IDS (line 688) and not _is_intake, so it was never tagged 'belt' /
	# never got meta('belt_speed') / never got BeltSurface — it's a static
	# visual. BeltBuilder still writes meta('placeable_id') and adds the body
	# to 'placed_object' so K-edit / delete / save-load find it.
	var spec := BeltBuilder.make_spec()
	spec.deck_kind = "none"           # caller owns the deck (built in extras)
	spec.has_legs = false             # bespoke I-beam legs in extras
	spec.rollers = "none"             # head/tail pulley housings in extras
	spec.side_rails = "none"          # wire-mesh guard rail is in extras
	spec.motor = "none"               # drive motor box in extras
	spec.chute = "none"
	spec.tag_as_belt = false          # static visual — preserve legacy no-carry
	spec.extras = [Callable(PlaceableCatalog, "_compactor_belt_extras")]
	BeltBuilder.build(p, "compactor_belt", size, spec, ghost)

# `extras` callable for compactor_belt — builds the full bespoke geometry
# (Z-rotated belt body + I-beam legs + drive-motor box + wire-mesh guard rail +
# stainless dust hood + blue blower with ducts). Signature matches
# BeltBuilder.build_internal's extras dispatch:
#   f(p, deck_root, size, spec, ghost).
# `_deck_root` and `_spec` are unused — the geometry below is identical to the
# pre-migration _m_compactor_belt body, just relocated.
static func _compactor_belt_extras(p: Node3D, _deck_root: Node3D, size: Vector3, _spec: Dictionary, ghost: bool) -> void:
	var black     := _mat(Color(0.10, 0.10, 0.11), ghost, 0.05, 0.85)   # belt side panels
	var rubber    := _mat(Color(0.06, 0.06, 0.07), ghost, 0.00, 0.95)   # belt rubber surface
	var galv      := _mat(Color(0.56, 0.59, 0.63), ghost, 0.65, 0.32)   # galvanized I-beam legs
	var yellow    := _mat(_SAFETY, ghost, 0.18, 0.70)                   # safety mesh + guards
	var blue      := _mat(Color(0.14, 0.32, 0.58), ghost, 0.20, 0.55)   # blower housing
	var steel     := _mat(_STEEL, ghost, 0.72, 0.28)                    # stainless hood + ducts
	var motor     := _mat(Color(0.32, 0.34, 0.36), ghost, 0.40, 0.45)   # blower drive motor
	var dark      := _mat(_DARK, ghost, 0.25, 0.55)                     # bolt heads + shadows
	var W := size.x; var H := size.y; var _D := size.z
	var belt_w   : float = 0.80                                          # belt strip width
	var body_thk : float = 0.40                                          # side-panel height
	var feed_y   : float = 0.30                                          # belt low-end Y
	var disc_y   : float = H - 0.40                                      # belt high-end Y
	var x0 : float = -W * 0.50                                           # feed end X
	var x1 : float =  W * 0.30                                           # head pulley X
	var dx := x1 - x0
	var dy := disc_y - feed_y
	var angle    : float = atan2(dy, dx)
	var belt_len : float = sqrt(dx * dx + dy * dy)
	var bx_mid : float = (x0 + x1) * 0.5
	var by_mid : float = (feed_y + disc_y) * 0.5

	# ── INCLINED BELT BODY (parented to a node rotated around Z) ──────────────
	var belt = Node3D.new()
	belt.name = "BeltBody"
	p.add_child(belt)
	belt.position = Vector3(bx_mid, by_mid, 0.0)
	belt.rotation = Vector3(0.0, 0.0, angle)
	# Side panels (black, runs along local X = inclined direction).
	_box(belt, Vector3(belt_len, body_thk, belt_w + 0.18), Vector3.ZERO, black)
	# Belt strip (slightly proud, dark rubber).
	_box(belt, Vector3(belt_len * 0.96, 0.04, belt_w),
		Vector3(0.0, body_thk * 0.5 + 0.02, 0.0), rubber)
	# Yellow side guards above the belt surface.
	for sz in [-1.0, 1.0]:
		_box(belt, Vector3(belt_len * 0.94, 0.06, 0.04),
			Vector3(0.0, body_thk * 0.5 + 0.30, sz * (belt_w * 0.5 + 0.06)), yellow)
	# Head pulley housing at the discharge end.
	_box(belt, Vector3(0.35, body_thk + 0.12, belt_w + 0.22),
		Vector3(belt_len * 0.5 + 0.18, 0.0, 0.0), black)
	# Tail pulley + small feed cowl at the bottom end.
	_box(belt, Vector3(0.35, body_thk + 0.12, belt_w + 0.22),
		Vector3(-belt_len * 0.5 - 0.18, 0.0, 0.0), black)

	# Drive motor box mounted above the head pulley (in world XY).
	_box(p, Vector3(0.55, 0.55, belt_w + 0.18), Vector3(W * 0.34, H - 0.10, 0.0), black)
	_box(p, Vector3(0.40, 0.12, 0.04), Vector3(W * 0.34, H - 0.39, belt_w * 0.5 + 0.10), yellow)

	# ── GALVANIZED I-BEAM SUPPORT LEGS at intervals along the belt ─────────────
	# Each leg is two flanges + a web (an actual I-section) on each side, joined
	# by a perpendicular cross-tie under the conveyor body.
	var n_legs : int = 4
	for k in n_legs:
		var tt : float = (float(k) + 0.5) / float(n_legs)
		var lx : float = x0 + dx * tt
		var ly : float = feed_y + dy * tt - body_thk * 0.5 - 0.04   # under the body
		if ly < 0.40: continue                                       # skip if too short
		for sz in [-1.0, 1.0]:
			var lz : float = sz * (belt_w * 0.5 + 0.40)
			_box(p, Vector3(0.14, ly, 0.02), Vector3(lx, ly * 0.5, lz - 0.06), galv)  # outer flange
			_box(p, Vector3(0.14, ly, 0.02), Vector3(lx, ly * 0.5, lz + 0.06), galv)  # inner flange
			_box(p, Vector3(0.04, ly, 0.10), Vector3(lx, ly * 0.5, lz), galv)         # web
			_box(p, Vector3(0.22, 0.025, 0.22), Vector3(lx, 0.013, lz), galv)         # base plate
			# Bolt heads at the corners of the base plate.
			for sxx in [-0.085, 0.085]:
				for szz in [-0.085, 0.085]:
					_box(p, Vector3(0.025, 0.020, 0.025), Vector3(lx + sxx, 0.035, lz + szz), dark)
		# Cross-tie under the belt body.
		_box(p, Vector3(0.08, 0.08, belt_w + 0.70), Vector3(lx, ly + 0.04, 0.0), galv)

	# ── YELLOW WIRE-MESH SIDE GUARD RAIL (in front of the belt's -Z side) ──────
	var rail_z : float = -(belt_w * 0.5 + 0.55)
	var rail_h : float = 1.10
	_box(p, Vector3(W * 0.85, 0.05, 0.05), Vector3(0.0, rail_h, rail_z), yellow)   # top rail
	_box(p, Vector3(W * 0.85, 0.05, 0.05), Vector3(0.0, 0.05, rail_z), yellow)     # bottom rail
	for sx_p in [-W * 0.42, -W * 0.15, W * 0.12, W * 0.38]:
		_box(p, Vector3(0.06, rail_h, 0.06), Vector3(sx_p, rail_h * 0.5, rail_z), yellow)
	# Mesh: vertical thin bars across the bay.
	var n_bars : int = 26
	for k in n_bars:
		var bx : float = -W * 0.42 + float(k) * (W * 0.85 / float(n_bars - 1))
		_box(p, Vector3(0.012, rail_h - 0.10, 0.010), Vector3(bx, rail_h * 0.5, rail_z), yellow)
	# A couple of horizontal mesh wires too (so it reads as proper mesh, not bars).
	for hy in [rail_h * 0.30, rail_h * 0.70]:
		_box(p, Vector3(W * 0.85, 0.010, 0.012), Vector3(0.0, hy, rail_z), yellow)

	# ── STAINLESS DUST EXTRACTION HOOD over the discharge ──────────────────────
	var hood_x : float = W * 0.30
	var hood_y : float = H + 0.55
	_box(p, Vector3(1.40, 0.50, belt_w + 0.45), Vector3(hood_x, hood_y, 0.0), steel)   # hood body
	_box(p, Vector3(0.70, 0.55, 0.70), Vector3(hood_x, hood_y + 0.55, 0.0), steel)     # tapered neck (boxy)
	_cyl(p, 0.24, 0.24, 1.20, Vector3(hood_x, hood_y + 1.40, 0.0), steel)              # rising flue

	# ── BLUE BLOWER UNIT at base of the feed end + ducts up to the hood ────────
	var bl_x : float = -W * 0.58
	var bl_z : float =  belt_w * 0.5 + 0.70
	_box(p, Vector3(0.65, 0.70, 0.95), Vector3(bl_x, 0.45, bl_z), blue)                # blower housing
	_cyl(p, 0.22, 0.22, 0.50, Vector3(bl_x + 0.50, 0.65, bl_z + 0.10), motor, "x")     # drive motor barrel
	# Skid base under the blower (stainless).
	_box(p, Vector3(0.85, 0.06, 1.10), Vector3(bl_x, 0.03, bl_z), steel)
	# Stainless duct: vertical riser → horizontal cross over the belt → drop into hood.
	var duct_top_y : float = H + 1.05
	_cyl(p, 0.18, 0.18, duct_top_y - 0.10, Vector3(bl_x, duct_top_y * 0.5 + 0.10, bl_z), steel)
	var run_dx : float = hood_x - bl_x - 0.30
	_cyl(p, 0.18, 0.18, run_dx, Vector3((bl_x + hood_x) * 0.5, duct_top_y, bl_z), steel, "x")
	_cyl(p, 0.18, 0.18, duct_top_y - hood_y - 0.10,
		Vector3(hood_x - 0.10, (duct_top_y + hood_y) * 0.5, bl_z), steel)
	# Dark sphere fittings at the 90° bends so the route reads as elbows.
	_cyl(p, 0.20, 0.20, 0.10, Vector3(bl_x, duct_top_y, bl_z), dark, "x")
	_cyl(p, 0.20, 0.20, 0.10, Vector3(hood_x - 0.10, duct_top_y, bl_z), dark, "x")

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

## Four converging panels forming a REAL TAPERED HOPPER (a flare) — not a tilted
## box. A rectangular mouth (`tw` x `td`) at `y_top` narrows to a throat
## (`bw` x `bd`) at `y_bot`, centred on (`cx`, ., `cz`). Each wall is a slab
## rotated onto the taper line, the way a folded-plate hopper is actually made.
## Panel spans are widened 6 % (the same trick `_half_pipe` uses) so the corner
## mitres close instead of showing daylight.
static func _flare4(parent: Node3D, cx: float, cz: float, y_bot: float, y_top: float,
		bw: float, bd: float, tw: float, td: float, thick: float, mat: StandardMaterial3D) -> void:
	var h : float = y_top - y_bot
	var cy : float = (y_bot + y_top) * 0.5
	var dx : float = (tw - bw) * 0.5
	var dz : float = (td - bd) * 0.5
	for sx in [-1.0, 1.0]:
		var pnx := _box(parent, Vector3(thick, sqrt(h * h + dx * dx), (bd + td) * 0.53),
			Vector3(cx + float(sx) * (bw + tw) * 0.25, cy, cz), mat)
		pnx.rotation.z = -float(sx) * atan2(dx, h)
	for sz in [-1.0, 1.0]:
		var pnz := _box(parent, Vector3((bw + tw) * 0.53, sqrt(h * h + dz * dz), thick),
			Vector3(cx, cy, cz + float(sz) * (bd + td) * 0.25), mat)
		pnz.rotation.x = float(sz) * atan2(dz, h)

# ── mill / granulator (maalmolen) — line 3C's L3C.6, also placed on line 1 ────
## NEUE HERBOLD granulator on an elevated, railed, grated work platform.
##
## SOURCING (vocabulary per docs/DETAIL_STANDARD_audit_2026-08-18.md Q1):
##   DOC (primary) docs/plant/maalmolen_3c_photo_reading_2026-08-29.md — the
##            operator's own reading of a real photograph of THIS machine, taken
##            while the line was still being built. Read it before editing here.
##   OPERATOR + PHOTO  brand "NEUE HERBOLD" in BLUE lettering on the angled
##            infeed hopper; body and hopper are CREAM/WHITE; elevated grating
##            platform; YELLOW railings; caged vertical ladder; the drive belts
##            are covered by a yellow guard; yellow equipment sticker reading
##            MAALMOLEN; a light-grey `+BP2` control cabinet and a yellow tool
##            shadow board on the deck.
##   OPERATOR (2026-08-30 CORRECTIONS — two earlier readings were WRONG)
##            (1) the rust-coloured drum on the deck is NOT a flywheel or a
##            pulley. It is a MOBILE INDUSTRIAL FAN on two wheels with a tilt
##            pivot — a prop parked on the platform, not part of the machine.
##            (2) the yellow object on the deck is NOT a chute and NOT a mesh.
##            It is a flat PLATE standing inside the railing. Both are built
##            that way below. Do not "restore" the flywheel or the chute.
##   OPERATOR (2026-08-29 ruling — the CLAUDE.md rule 8b EXCEPTION)  the mill's
##            OWN shaft motor is CREAM, the same colour as the mill body. It is
##            the one motor in the plant that is not CeDo dark blue, so it is
##            built by hand below instead of through `_motor_unit`, which
##            hard-codes the blue and MUST keep doing so for every other
##            machine. The blue motors visible under this platform in the photo
##            drive the two FRICTION SEPARATORS (`friction_sep` -> `_m_friction`,
##            which builds its own rule-8b blue `_motor_unit`) — they are not
##            this machine's and are not modelled here.
##   OPERATOR  the stairs lie flat on the floor in the photo only because the
##            line was under construction. Their INSTALLED position (ruled
##            2026-08-30): "starts pretty much next to the ladder" — same face
##            as the caged ladder, climbing straight onto the deck's open +X
##            edge. The earlier "square landing at a gap in the -Z railing"
##            reading was a guess and is superseded; landing and gap are gone.
##            The red/white barrier tape and the contractor's blue forklift in
##            the same photo are construction-only — not modelled.
##   DOC      Line3CDef.gd:66 records this unit as L3C.6, but the tag NUMBER on
##            the yellow sticker was NOT readable and the operator was
##            explicitly unsure ("8-point-something"), so the sticker carries
##            the WORD ONLY. Do not stencil a guessed number.
##   TYPICAL (invented — flagged) the stair's 0.30 m -Z offset from the ladder
##            (picked for cage clearance) and its 0.90 m width — the SIDE it is
##            on is now OPERATOR, only the exact offset is invented; the
##            belt-drive layout (motor offset in -Z, twin pulleys, three
##            V-belts); the discharge chute below the deck; the `+BP2` cabinet's
##            dimensions and its E-stop; the concrete footing pads; the size and
##            parking spot of the fan and of the yellow plate; the tool board's
##            size and bay; the weathering grade of each finish.
static func _m_mill(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var P = MaterialPalette
	# Ghost previews must stay see-through (BuildMode drags them across the
	# world), so the palette finishes are used only for the real build and
	# `_mat(..., ghost, ...)` supplies the translucent stand-in during placement.
	var cream    : StandardMaterial3D = _mat(Color(0.82, 0.80, 0.74), ghost, 0.10, 0.55) if ghost else P.mat_paint_cream_steel()
	var aged     : StandardMaterial3D = _mat(_DARK, ghost, 0.25, 0.60) if ghost else P.mat_steel_dark_aged()
	var galv     : StandardMaterial3D = _mat(_STEEL, ghost, 0.55, 0.35) if ghost else P.mat_steel_galvanised()
	var yellow   : StandardMaterial3D = _mat(_SAFETY, ghost, 0.0, 0.92) if ghost else P.mat_paint_yellow_peeling()
	var yellow_f : StandardMaterial3D = _mat(_SAFETY, ghost, 0.0, 0.60) if ghost else P.mat_paint_safety_yellow()
	var rustplate: StandardMaterial3D = _mat(Color(0.30, 0.26, 0.22), ghost, 0.30, 0.65) if ghost else P.mat_steel_riveted_rust()
	# GAP: MaterialPalette has no BRIGHT rust. `mat_steel_riveted_rust` is a dark
	# rust-streaked plate and reads near-black across a 1.25 m flywheel disc,
	# which contradicts the operator's "rust-coloured flywheel". Keeping the
	# original measured-from-photo colour here until the palette gains one.
	var rust     : StandardMaterial3D = _mat(Color(0.46, 0.30, 0.24), ghost, 0.35, 0.70)
	var castiron : StandardMaterial3D = _mat(Color(0.18, 0.19, 0.21), ghost, 0.40, 0.75) if ghost else P.mat_cast_iron_rough()
	var rubber   : StandardMaterial3D = _mat(Color(0.07, 0.07, 0.08), ghost, 0.0, 0.95) if ghost else P.mat_rubber_tire_solid()
	var placard  : StandardMaterial3D = _mat(Color(0.20, 0.20, 0.20), ghost, 0.30, 0.85) if ghost else P.mat_text_embossed_dark()
	var concrete : StandardMaterial3D = _mat(Color(0.40, 0.40, 0.38), ghost, 0.0, 0.90) if ghost else P.mat_concrete_worn()
	var grease   : StandardMaterial3D = _mat(Color(0.10, 0.09, 0.07), ghost, 0.10, 0.35) if ghost else P.mat_oil_grease()
	var tray     : StandardMaterial3D = _mat(Color(0.42, 0.43, 0.44), ghost, 0.55, 0.55) if ghost else P.mat_grating_steel()

	# ── Derived frame of reference — every extent below is checked against these ─
	var deck_y : float = size.y * 0.40                 # grating deck mid-plane
	var hw : float = size.x * 0.40                     # deck half-width  (X)
	var hd : float = size.z * 0.34                     # deck half-depth  (Z)
	var deck_top : float = deck_y + 0.01               # walkable surface (grating is 0.02 thick)
	var base_y : float = deck_y + 0.06                 # machine skid top = chamber underside
	var ch_h : float = size.y * 0.26                   # cutting-chamber height
	var ch_hx : float = hw * 0.55                      # chamber half-X
	var ch_hz : float = hd * 0.50                      # chamber half-Z
	var ch_cy : float = base_y + ch_h * 0.5            # rotor axis height
	var ch_top : float = base_y + ch_h
	var rail_base : float = deck_y - 0.02              # so the toe board lands ON the grating

	# ── Elevated platform: 4 legs on poured pads + perimeter beams + grating ──
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(0.34, 0.08, 0.34), Vector3(float(sx) * hw, 0.04, float(sz) * hd), concrete)
			_box(p, Vector3(0.14, deck_y, 0.14), Vector3(float(sx) * hw, deck_y * 0.5, float(sz) * hd), galv)
	# Beams raised to deck_y - 0.06 so their tops meet the grating underside; at
	# the old deck_y - 0.12 they hung 0.06 m clear of the deck they carry.
	_box(p, Vector3(hw * 2.0, 0.10, 0.10), Vector3(0, deck_y - 0.06,  hd), galv)
	_box(p, Vector3(hw * 2.0, 0.10, 0.10), Vector3(0, deck_y - 0.06, -hd), galv)
	_box(p, Vector3(0.10, 0.10, hd * 2.0), Vector3( hw, deck_y - 0.06, 0), galv)
	_box(p, Vector3(0.10, 0.10, hd * 2.0), Vector3(-hw, deck_y - 0.06, 0), galv)
	# Real see-through walkway grating (this used to be a flat grey slab).
	_grating_deck(p, hw * 2.0, hd * 2.0, Vector3(0, deck_y, 0))

	# ── Access: stair beside the LADDER on the +X face (OPERATOR 2026-08-30) ──────
	# CORRECTION. The flight used to run along the -Z deck edge and turn onto a
	# square landing that met a hand-built gap in the -Z railing. That put the
	# stair on the OPPOSITE side of the machine from the ladder, and the operator
	# said so:
	#
	#   "I think the model is a bit weird. because the stairs should come up next
	#    to it. Right?"  ...  "note stairs location, starts pretty much next to
	#    the ladder"
	#
	# So the stair now stands on the SAME face as the caged ladder, immediately
	# -Z of it, and climbs in -X straight onto the deck. The +X edge already
	# carries no railing (it is the ladder's climb-out), so the flight tops out
	# flush with the deck edge and the player walks straight on -- no landing and
	# no railing gap are needed any more, and the -Z railing is now continuous.
	#
	# Clearances, computed not eyeballed. `_caged_ladder` at (hw+0.10, 0, hd*0.35)
	# = (1.54, 0, 0.547) occupies X [1.056, 2.024] (0.484 hoop radius) and
	# Z [0.394, 1.362] (hoops offset +0.33, cage bar at +0.792). The flight is
	# 0.90 wide centred on z = -0.30, i.e. Z [-0.75, 0.15] -- clear of the
	# ladder's -Z face by 0.244 m, so the two never touch even though they share
	# the +X aisle.
	#
	# Stair foot lands at world (3.60, 0, -0.30); the ladder's foot is at
	# (1.54, 0, 0.547). They are 2.23 m apart on the same side of the machine,
	# against 2.69 m apart around a corner before. `_stair` climbs in local +Z
	# only, so it is built under a pivot yawed -90 deg: local +Z -> world -X,
	# local +X -> world +Z. The run is taken from `_stair`'s own step maths so
	# the top tread's nominal edge lands EXACTLY on the deck edge, x = hw.
	#
	# OPERATOR: which side the stair is on, and that its foot is beside the
	# ladder's. TYPICAL: the 0.30 m -Z offset (chosen for ladder clearance) and
	# the 0.90 m flight width.
	_railing(p, hw, hd, rail_base, yellow, ["+x"])
	# `_railing` hard-codes this same height; the tool shadow board below hangs
	# itself off rail_base + rail_h, so it is kept as a named constant.
	var rail_h := 1.05

	var stair_pivot := Node3D.new()
	stair_pivot.name = "StairPivot"
	stair_pivot.rotation.y = -PI * 0.5
	p.add_child(stair_pivot)
	var stair_run : float = float(maxi(int(deck_y / 0.22), 4)) * 0.27
	var stair_z : float = -0.30                        # flight centreline, world Z
	# world (x, z) = (-local_z, local_x) under the -90 deg yaw above.
	_stair(stair_pivot, Vector3(stair_z, 0.0, -(hw + stair_run)), deck_y, 0.90, tray, yellow)

	# ── Granulator body ON the deck ───────────────────────────────────────────
	# Skid rails bridge the 0.05 m between the grating top and the chamber
	# underside (the chamber used to hover over that gap) and leave the middle
	# clear for the discharge throat.
	for sk1 in [-1.0, 1.0]:
		_box(p, Vector3(ch_hx * 2.15, 0.05, 0.14),
			Vector3(0, (deck_top + base_y) * 0.5, float(sk1) * ch_hz * 0.92), aged)
		_box(p, Vector3(0.14, 0.05, ch_hz * 2.12),
			Vector3(float(sk1) * ch_hx * 0.95, (deck_top + base_y) * 0.5, 0), aged)
	_box(p, Vector3(ch_hx * 2.0, ch_h, ch_hz * 2.0), Vector3(0, ch_cy, 0), cream)   # cutting chamber
	# Split-line flange + bolt heads — a granulator housing opens on this seam.
	_box(p, Vector3(ch_hx * 2.06, 0.07, ch_hz * 2.06), Vector3(0, ch_cy + ch_h * 0.18, 0), aged)
	for bk in 12:
		_box(p, Vector3(0.06, 0.05, 0.06),
			Vector3(-ch_hx + float(bk) / 12.0 * ch_hx * 2.0, ch_cy + ch_h * 0.18, -ch_hz * 1.04), aged)

	# Interactive hinged screen cradle access door on the front (+Z) face
	var mill_door := _interactive_hatch(p, Vector3(hw * 0.85, ch_h * 0.75, 0.04),
		Vector3(0.0, ch_cy, ch_hz + 0.02), "Granulator Screen Cradle Door", 100.0, 1.0, cream, ghost)
	if not ghost:
		# Transparent grimy viewing window on the door
		_box(mill_door, Vector3(hw * 0.45, ch_h * 0.35, 0.02),
			Vector3(-hw * 0.425, 0.0, 0.02), MaterialPalette.mat_glass_inspection_grime())
		# Heavy tightening clamping bolts
		_cyl(mill_door, 0.025, 0.025, 0.06, Vector3(-hw * 0.425, ch_h * 0.25, 0.03), castiron, "z")
		_cyl(mill_door, 0.025, 0.025, 0.06, Vector3(-hw * 0.425, -ch_h * 0.25, 0.03), castiron, "z")

	# Rotating internal granulator rotor with 3 heavy rotary blades
	var mill_rotor := _spinning_cyl(p, ch_h * 0.35, ch_h * 0.35, hw * 0.95,
		Vector3(0.0, ch_cy, 0.0), galv, "x", Vector3.RIGHT, ghost, 120.0)
	if not ghost:
		for bi in 3:
			var b_ang : float = TAU * float(bi) / 3.0
			var blade := _box(mill_rotor, Vector3(hw * 0.92, 0.025, 0.08),
				Vector3(0.0, cos(b_ang) * ch_h * 0.30, sin(b_ang) * ch_h * 0.30), rustplate)
			blade.rotation.x = b_ang

	# ── Angled infeed hopper — a REAL converging flare, not a rotated crate ────
	# PHOTO: wide-mouth funnel narrowing into the cutting chamber. Its four walls
	# lean outward as they rise; that lean IS the "angled hopper" the brand sits
	# on. (It used to be a plain box tipped 20 deg, which read as a tilted crate.)
	var hop_h : float = 0.99
	var hop_cz : float = -0.10
	var mouth_hx : float = 1.12
	var mouth_hz : float = 0.68
	var throat_d : float = 0.66
	_flare4(p, 0.0, hop_cz, ch_top, ch_top + hop_h, 0.90, throat_d, mouth_hx * 2.0, mouth_hz * 2.0, 0.06, cream)
	for sz4 in [-1.0, 1.0]:
		_box(p, Vector3(mouth_hx * 2.11, 0.06, 0.10),
			Vector3(0, ch_top + hop_h + 0.03, hop_cz + float(sz4) * mouth_hz), galv)
		_box(p, Vector3(0.10, 0.06, mouth_hz * 2.15),
			Vector3(float(sz4) * mouth_hx, ch_top + hop_h + 0.03, hop_cz), galv)

	# ── PHOTO: hopper-lid CLAMP BANK on the +X wall (2026-09-06) ──────────────
	# Section 9b of the photo reading: "a row of white clamp cylinders /
	# hinged-lid hardware along the top-right edge of the infeed hopper". Zoomed
	# on the filed photograph it resolves into a bank of THREE cream clamp
	# brackets — each a gusset rib, a top plate, and a DARK contact pad at the
	# outer tip — with TWO spindles between them, each a galvanised stem through
	# a cast barrel nut, and a hose trailing off the -Z spindle. On a Neue
	# Herbold granulator this is the hardware that locks the hinged hopper
	# section down for knife changes.
	#
	# The +X wall is the one the ladder side looks at: the brand is stencilled
	# on +Z, and in the photograph the clamp wall is the face clockwise from the
	# brand wall, i.e. toward the ladder, which the model puts at +X.
	#
	# Built under a pivot that reuses `_flare4`'s OWN +X panel transform, so the
	# bank stays welded to the wall if the hopper is ever re-proportioned:
	#   local +X = wall outward normal, +Y = up-slope, +Z = world Z.
	var hop_dx : float = (mouth_hx * 2.0 - 0.90) * 0.5         # _flare4's dx
	var hop_lean : float = atan2(hop_dx, hop_h)                # _flare4's own angle
	var up_s := Vector3(sin(hop_lean), cos(hop_lean), 0.0)
	var out_n := Vector3(cos(hop_lean), -sin(hop_lean), 0.0)
	var clamps := Node3D.new()
	clamps.name = "HopperClamps"
	p.add_child(clamps)
	clamps.rotation.z = -hop_lean
	clamps.position = Vector3((0.90 + mouth_hx * 2.0) * 0.25, ch_top + hop_h * 0.5, hop_cz) \
		+ up_s * 0.40 + out_n * 0.03                           # just under the rim, on the face
	for cz3 in [-0.44, 0.0, 0.44]:
		_box(clamps, Vector3(0.17, 0.31, 0.020), Vector3(0.085, 0.0, float(cz3)), cream)      # gusset rib
		_box(clamps, Vector3(0.22, 0.032, 0.105), Vector3(0.110, 0.150, float(cz3)), cream)   # top plate
		_box(clamps, Vector3(0.050, 0.040, 0.105), Vector3(0.196, 0.150, float(cz3)), placard)  # dark pad
	for cz2 in [-0.22, 0.22]:
		_cyl(clamps, 0.024, 0.024, 0.22, Vector3(0.125, 0.030, float(cz2)), galv)             # spindle stem
		_cyl(clamps, 0.058, 0.058, 0.080, Vector3(0.125, -0.055, float(cz2)), castiron)       # barrel nut
		_cyl(clamps, 0.042, 0.042, 0.032, Vector3(0.125, 0.150, float(cz2)), galv)            # hex head
	# The hose off the -Z spindle, trailing down the wall (PHOTO).
	var hose_a := _cyl(clamps, 0.016, 0.016, 0.24, Vector3(0.100, -0.20, -0.255), rubber)
	hose_a.rotation.x = 0.30
	var hose_b := _cyl(clamps, 0.016, 0.016, 0.22, Vector3(0.075, -0.38, -0.330), rubber)
	hose_b.rotation.x = 0.62

	var hop_tilt : float = atan2((mouth_hz * 2.0 - throat_d) * 0.5, hop_h)
	var hop_wall : float = (throat_d + mouth_hz * 2.0) * 0.25
	if not ghost:
		# Grimy sight strip on the rear wall, laid onto the panel's own angle.
		var sight := _box(p, Vector3(0.70, 0.30, 0.02),
			Vector3(0.0, ch_top + hop_h * 0.5 - sin(hop_tilt) * 0.045,
				hop_cz - hop_wall - cos(hop_tilt) * 0.045), MaterialPalette.mat_glass_inspection_grime())
		sight.rotation.x = -hop_tilt
		# OPERATOR + PHOTO: "NEUE HERBOLD" in BLUE lettering on the angled hopper.
		var brand := _stencil_label(p, "NEUE HERBOLD", Vector3(1.30, 0.20, 0.01), "+Z")
		brand.position = Vector3(0.0, ch_top + hop_h * 0.5 - sin(hop_tilt) * 0.05,
			hop_cz + hop_wall + cos(hop_tilt) * 0.05)
		brand.rotation.x = hop_tilt
		for ch in brand.get_children():
			if ch is Label3D:
				(ch as Label3D).modulate = Color(0.098, 0.118, 0.424)      # NEUE HERBOLD blue
				(ch as Label3D).outline_modulate = Color(1.0, 1.0, 1.0, 0.85)
		# PHOTO: the full mark is `NEUE HERBOLD.com` — the suffix is a separate,
		# much smaller lockup low and right of the wordmark, so it is a second
		# label rather than four more characters on the first (one Label3D can
		# only carry one glyph size). `_stencil_label` derives glyph size from
		# the SMALLER side, so size.y is what sets it: 0.08 against the
		# wordmark's 0.20 gives the ~40 % suffix the photograph shows.
		# STILL NOT MODELLED: the stylised blue globe standing in for the O.
		# A Label3D cannot express it and faking it with an emissive disc would
		# be a guess at its artwork — ask before adding one.
		var brand_com := _stencil_label(p, ".com", Vector3(0.34, 0.08, 0.01), "+Z")
		brand_com.position = brand.position \
			+ Vector3(0.72, -0.070 * cos(hop_tilt), -0.070 * sin(hop_tilt))
		brand_com.rotation.x = hop_tilt
		for ch2 in brand_com.get_children():
			if ch2 is Label3D:
				(ch2 as Label3D).modulate = Color(0.098, 0.118, 0.424)
				(ch2 as Label3D).outline_modulate = Color(1.0, 1.0, 1.0, 0.85)

	# ── PROP: mobile industrial FAN standing on the deck (OPERATOR 2026-08-30) ────────
	# CORRECTION. This used to be a "rust flywheel/pulley" keyed to the mill's
	# shaft. It is nothing of the kind. The operator, looking at the same photo:
	#
	#   "the rusty thing is a industrial fan. You can see the two wheels in its
	#    bottom right. And you can see the pivot point [...] in the center above
	#    the wheels."
	#
	# Confirmed by zooming the filed photograph: a barrel shroud with a wire
	# finger-guard on one end, two rubber wheels under a tubular trolley, and a
	# black spoked hand-knob on the side trunnion for locking the tilt. It is the
	# "blower fan at the top of the bordes/catwalk" already listed among the props
	# in section 5 of the photo-reading doc -- a loose object parked on the
	# platform, NOT part of the granulator. It is deliberately still built here
	# (rather than as its own placeable) so the mill reads as the photo does; if
	# it ever needs to be moved independently, lift it out to its own id.
	#
	# The mill's real drive is the +X belt run below -- motor, twin pulleys and
	# V-belts. Nothing was removed from the drivetrain by this change; what went
	# was an invented flywheel disc that the machine never had.
	#
	# OPERATOR + PHOTO: that it is a fan, the wheels, the tilt pivot, the rust.
	# TYPICAL: a 560 mm drum (no scale reference near it in the photo), and the
	# fan's exact parking spot on the deck.
	# 500 mm drum, not 560: the -X deck strip between the railing (-1.44) and the
	# cutting chamber (-0.792) is only 0.648 m wide, and the trunnions and the
	# tilt knob have to fit inside it too. Measured, not guessed -- the first
	# attempt at 560 mm overhung the deck by 0.035 m and pushed the knob 0.030 m
	# into the chamber's footprint.
	var fan_r : float = 0.25
	var fan_len : float = 0.62
	var fan_x : float = -1.115                      # centred in the -X deck strip
	var fan_z : float = -0.55
	var fan_cy : float = deck_top + 0.55
	var fan_face : float = fan_z + fan_len * 0.5 + 0.03
	# Trolley: two rubber wheels + a tubular frame + a push handle.
	for fwx in [-1.0, 1.0]:
		_cyl(p, 0.085, 0.085, 0.05,
			Vector3(fan_x + float(fwx) * 0.19, deck_top + 0.085, fan_z + 0.16), rubber, "x")
		_box(p, Vector3(0.045, 0.50, 0.045),
			Vector3(fan_x + float(fwx) * 0.19, deck_top + 0.30, fan_z + 0.16), aged)
	_box(p, Vector3(0.42, 0.05, 0.045), Vector3(fan_x, deck_top + 0.055, fan_z - 0.22), aged)
	_box(p, Vector3(0.42, 0.045, 0.045), Vector3(fan_x, deck_top + 0.86, fan_z + 0.16), aged)
	# Barrel shroud, rusted, with the two rolled rim bands.
	_cyl(p, fan_r, fan_r, fan_len, Vector3(fan_x, fan_cy, fan_z), rust, "z")
	for fbz in [-1.0, 1.0]:
		_cyl(p, fan_r * 1.05, fan_r * 1.05, 0.05,
			Vector3(fan_x, fan_cy, fan_z + float(fbz) * fan_len * 0.45), rust, "z")
	# Tilt pivot: a trunnion boss each side, and the black spoked locking knob.
	for ftx in [-1.0, 1.0]:
		_cyl(p, 0.05, 0.05, 0.05,
			Vector3(fan_x + float(ftx) * (fan_r + 0.015), fan_cy, fan_z + 0.16), castiron, "x")
	_cyl(p, 0.070, 0.070, 0.024,
		Vector3(fan_x + fan_r + 0.045, fan_cy, fan_z + 0.16), rubber, "x")
	for fkn in 6:
		var knob := _box(p, Vector3(0.024, 0.125, 0.020),
			Vector3(fan_x + fan_r + 0.045, fan_cy, fan_z + 0.16), rubber)
		knob.rotation.x = PI * float(fkn) / 6.0
	# Motor can behind the impeller.
	_cyl(p, 0.10, 0.10, 0.20, Vector3(fan_x, fan_cy, fan_z - fan_len * 0.5 - 0.09), castiron, "z")
	if not ghost:
		# Impeller: hub + 3 blades, set back inside the shroud.
		_cyl(p, 0.055, 0.055, 0.10, Vector3(fan_x, fan_cy, fan_z + 0.10), castiron, "z")
		for fbl in 3:
			var blade := _box(p, Vector3(0.015, fan_r * 1.5, 0.10),
				Vector3(fan_x, fan_cy, fan_z + 0.10), aged)
			blade.rotation.z = TAU * float(fbl) / 3.0
		# Wire finger-guard: three concentric rings + eight radial spokes. Built
		# under a pivot because `_torus` lays its ring in the XZ plane.
		var fan_guard := Node3D.new()
		fan_guard.name = "FanGuard"
		p.add_child(fan_guard)
		fan_guard.position = Vector3(fan_x, fan_cy, fan_face)
		fan_guard.rotation.x = PI * 0.5
		# Wire gauge is deliberately over-scale. A real finger-guard is ~4 mm wire.
		# Built at 13 mm first and the operator could not see it at all ("i cant
		# see the mesh shroud?"); 26 mm was legible but read as a chunky cage at
		# close range, not a wire guard -- `_torus` only gives 6 rings x 18
		# segments, so a fat tube shows its polygons. 17 mm is the compromise:
		# visible from the walkway, still wire-like with your nose against it.
		for fgr in [0.068, 0.130, 0.190, 0.245]:
			_torus(fan_guard, float(fgr), float(fgr) + 0.017, Vector3.ZERO, galv)
		for fgs in 10:
			var spoke2 := _box(fan_guard, Vector3(0.014, 0.014, fan_r * 2.06), Vector3.ZERO, galv)
			spoke2.rotation.y = PI * float(fgs) / 10.0

	# ── A3 + B1: drive on the +X end — CREAM motor, twin pulleys, V-belts ─────
	# The old `_motor_unit` sat at x = 1.757 with a 1.008 m body: it spanned
	# 1.25..2.26 against a deck edge of 1.44, i.e. mostly off the platform.
	# EXCEPTION to CLAUDE.md rule 8b (operator 2026-08-29): this motor is CREAM,
	# the same colour as the mill body — the one motor in the plant that is not
	# CeDo dark blue. That is why it is built by hand here; `_motor_unit` stays
	# blue for everything else. Do NOT "fix" this back to blue.
	# The drive sits on the -Z half so the guard clears the ladder cage hoops.
	var belt_x : float = hw * 0.833                    # common pulley plane
	var mot_r : float = 0.26
	var mot_len : float = 0.62
	var mot_z : float = -(ch_hz + 0.36)
	var mot_x : float = belt_x - 0.40
	var skid_y : float = deck_top + 0.03
	_box(p, Vector3(0.80, 0.06, 0.66), Vector3(mot_x, skid_y, mot_z), aged)                 # motor skid
	var mot_y : float = skid_y + 0.03 + mot_r
	_cyl(p, mot_r, mot_r, mot_len, Vector3(mot_x, mot_y, mot_z), cream, "x")                # CREAM motor body
	for fk in 5:
		_cyl(p, mot_r * 1.06, mot_r * 1.06, 0.03,
			Vector3(mot_x - mot_len * 0.36 + float(fk) * mot_len * 0.18, mot_y, mot_z), cream, "x")
	_box(p, Vector3(mot_r * 0.8, mot_r * 0.5, mot_len * 0.45),
		Vector3(mot_x, mot_y + mot_r * 0.95, mot_z), aged)                                  # terminal box
	# ── PHOTO: fan cowl, its wire grille, and the YELLOW STICKER (2026-09-06) ──
	# Section 9b recorded only "a small yellow sticker on the motor's fan cowl",
	# but the model had no cowl at all — just the body and its fin rings — so
	# there was nothing for the sticker to sit on. Zoomed, the photograph shows
	# the whole non-drive end: a smooth cream cowl, a fine crosshatch grille
	# with a square hub at its centre, the sticker high on the cowl's shoulder,
	# a lifting eye on the body, and a dark nameplate on the fin block.
	# The cowl is on the -X end because the shaft and pulley leave on +X. That
	# end faces the `+BP2` cabinet, and adding the cowl put the grille 10 mm
	# INSIDE it: the cabinet's +X face was at x 0.35 and the new grille plane at
	# x 0.333. The cabinet moved 130 mm -X (`bp_x`) and the cowl 20 mm toward the
	# motor body, which restores the gap the photograph shows between the two.
	# `verify_mill_photo_details_2026_09_06` now asserts they do not intersect.
	var cowl_r : float = mot_r * 1.10
	var cowl_x : float = mot_x - mot_len * 0.5 - 0.05
	_cyl(p, cowl_r, cowl_r, 0.16, Vector3(cowl_x, mot_y, mot_z), cream, "x")                # fan cowl
	# Grille: this file's crosshatch idiom (thin bars), chord-fitted to a disc so
	# the bars stop at the cowl rim instead of overhanging it as a square patch.
	var gr : float = cowl_r * 0.72
	var grille_x : float = cowl_x - 0.086
	for gk in 7:
		var gt : float = (float(gk) + 0.5) / 7.0 * 2.0 - 1.0
		var chord : float = 2.0 * gr * sqrt(maxf(1.0 - gt * gt, 0.0))
		_box(p, Vector3(0.005, 0.009, chord), Vector3(grille_x, mot_y + gt * gr, mot_z), castiron)
		_box(p, Vector3(0.005, chord, 0.009), Vector3(grille_x, mot_y, mot_z + gt * gr), castiron)
	_box(p, Vector3(0.012, 0.076, 0.076), Vector3(grille_x - 0.005, mot_y, mot_z), galv)     # square hub
	# Sticker on the cowl shoulder, laid tangent to the barrel (PHOTO). A box
	# whose normal is +Y is rotated about X by (angle - 90 deg) to sit radial.
	var st_a : float = deg_to_rad(52.0)
	var mot_sticker := _box(p, Vector3(0.105, 0.003, 0.070),
		Vector3(cowl_x + 0.012, mot_y + cowl_r * sin(st_a), mot_z + cowl_r * cos(st_a)), yellow_f)
	mot_sticker.rotation.x = st_a - PI * 0.5
	# Lifting eye. `_torus` lies in the XZ plane, so it needs a pivot to stand up.
	_cyl(p, 0.017, 0.017, 0.07, Vector3(mot_x + 0.02, mot_y + mot_r + 0.030, mot_z), galv)
	var eye := Node3D.new()
	eye.name = "MotorLiftEye"
	p.add_child(eye)
	eye.position = Vector3(mot_x + 0.02, mot_y + mot_r + 0.088, mot_z)
	eye.rotation.x = PI * 0.5
	_torus(eye, 0.021, 0.039, Vector3.ZERO, galv)
	var mot_plate := _box(p, Vector3(0.10, 0.055, 0.003),
		Vector3(mot_x + 0.15, mot_y + mot_r * 0.86, mot_z + 0.13), placard)                  # nameplate
	mot_plate.rotation.x = -atan2(0.13, mot_r * 0.86)
	_cyl(p, 0.055, 0.055, 0.20, Vector3(belt_x - 0.02, mot_y, mot_z), galv, "x")            # motor shaft
	_cyl(p, 0.16, 0.16, 0.09, Vector3(belt_x, mot_y, mot_z), castiron, "x")                 # driving pulley
	_cyl(p, 0.085, 0.085, (belt_x - ch_hx) + 0.14,
		Vector3((belt_x + ch_hx) * 0.5 - 0.07, ch_cy, 0), galv, "x")                        # rotor shaft out
	_cyl(p, 0.30, 0.30, 0.09, Vector3(belt_x, ch_cy, 0), castiron, "x")                     # driven pulley
	# Three V-belts, each drawn as the two straight runs between the pulleys.
	var b_dy : float = mot_y - ch_cy
	var b_len : float = sqrt(b_dy * b_dy + mot_z * mot_z)
	var b_ang : float = atan2(-b_dy, mot_z)
	for bi2 in 3:
		for off in [0.23, -0.23]:
			var belt := _box(p, Vector3(0.055, 0.022, b_len),
				Vector3(belt_x - 0.03 + float(bi2) * 0.03,
					ch_cy + b_dy * 0.5 + float(off) * cos(b_ang),
					mot_z * 0.5 + float(off) * sin(b_ang)), rubber)
			belt.rotation.x = b_ang
	# Grease staining on the grating under the drive — every plant has it.
	_box(p, Vector3(0.60, 0.006, 0.44), Vector3(hw * 0.764, deck_top + 0.004, mot_z * 0.92), grease)

	# ── B2: drive-belt guard = FINE YELLOW MESH (OPERATOR + PHOTO) ────────────
	# Built with this file's established mesh stand-in idiom (N thin bars — see
	# the vw_trommel cage), not the single solid yellow plate `_guard` gives.
	var g_y0 : float = deck_top + 0.06
	var g_y1 : float = ch_cy + 0.36
	var g_z0 : float = mot_z - 0.26
	var g_z1 : float = 0.32
	var g_cy : float = (g_y0 + g_y1) * 0.5
	var g_cz : float = (g_z0 + g_z1) * 0.5
	var g_h : float = g_y1 - g_y0
	var g_d : float = g_z1 - g_z0
	var g_face : float = belt_x + 0.09
	_box(p, Vector3(0.18, 0.04, g_d), Vector3(belt_x, g_y1, g_cz), yellow_f)
	_box(p, Vector3(0.18, 0.04, g_d), Vector3(belt_x, g_y0, g_cz), yellow_f)
	for gz in [g_z0, g_z1]:
		_box(p, Vector3(0.18, g_h, 0.04), Vector3(belt_x, g_cy, float(gz)), yellow_f)
		_box(p, Vector3(0.06, 0.10, 0.06), Vector3(belt_x, deck_top + 0.05, float(gz) + (0.08 if gz < 0.0 else -0.08)), yellow_f)
	for mk in 14:
		_box(p, Vector3(0.010, g_h - 0.04, 0.012),
			Vector3(g_face, g_cy, g_z0 + (float(mk) + 0.5) * g_d / 14.0), yellow_f)
	for mk2 in 8:
		_box(p, Vector3(0.010, 0.012, g_d - 0.04),
			Vector3(g_face, g_y0 + (float(mk2) + 0.5) * g_h / 8.0, g_cz), yellow_f)
	# Grating drip tray under the belt run.
	_box(p, Vector3(0.34, 0.02, 0.60), Vector3(belt_x, deck_top + 0.005, -0.35), tray)

	# ── A4: discharge chute — now MEETS the chamber it drains ─────────────────
	# Its top used to stop at y = 1.488 with the machine underside at 1.98: a
	# 0.40 m air gap between the chute and the mill it is supposed to empty.
	# Now a converging flare straight off the chamber underside, down through the
	# deck, into a straight outlet duct with a flange.
	# Finish corrected 2026-09-06: this was `aged` (mat_steel_dark_aged), which
	# renders near-black. The photograph shows the under-deck discharge as a
	# mid-GREY box, the same family as the galvanised frame it hangs in — so it
	# is `galv`. The bolted access plate and yellow name sticker on its +Z face
	# are built below, and the trunk splits into the Y further down.
	#
	# WARNING to a future reader: between these two facts a 2026-09-06 pass
	# briefly RETRACTED section 9b's "ending in pointed outlets", on a reading
	# that the pointed shapes were gusset tops of support posts. The operator
	# corrected that the same day — it is a splitter chute and the outlets are
	# real. Do not re-derive the retraction from the photograph alone; the
	# structure is genuinely ambiguous at that resolution.
	_flare4(p, 0.0, 0.0, base_y - deck_y * 0.45, base_y, 0.44, 0.38, ch_hx * 1.24, ch_hz * 1.10, 0.05, galv)
	# ── OPERATOR 2026-09-06: it is an UPSIDE-DOWN Y SPLITTER ──────────────────
	#   "the frame under the mill is the chute that is an upside down Y splitter,
	#    dividing material from the mill left and right again to the friction
	#    separators > transportation screws towards the flotation tank inlet
	#    paddle"
	#
	# This REINSTATES what a 2026-09-06 re-reading of the photograph had wrongly
	# retracted. Section 9b's original "ending in pointed outlets" was right; the
	# retraction that called the pointed shapes "gusset tops of support posts"
	# was the error. See §9h/§9i of the photo reading.
	#
	# The split axis is +/-X, and that is not a guess: `BuildMode.LINE_3C_SEQ`
	# places L3C.9L at x -3.0 and L3C.9R at x +3.0 relative to the mill, and
	# `Line3CDef.LINKS` carries ["L3C.6","L3C.9L"] and ["L3C.6","L3C.9R"]. The
	# sim topology already matched the operator's description exactly — only the
	# geometry was missing.
	#
	# Replaces a single straight outlet duct + flange on the centreline, which
	# fed nothing and split nothing.
	var y_thr : float = base_y - deck_y * 0.45          # trunk throat, 1.116
	# The divider: two plates meeting in a ridge on the centreline, apex UP into
	# the falling stream. This is the "pointed" element in the photograph.
	for sxd in [-1.0, 1.0]:
		var divp := _box(p, Vector3(0.30, 0.016, 0.38),
			Vector3(float(sxd) * 0.105, y_thr - 0.10, 0.0), galv)
		divp.rotation.z = -float(sxd) * 0.62
	# The two legs. Each is a duct under its own pivot: `_hollow_box` is
	# axis-aligned, so the lean has to come from the parent transform.
	var leg_ang : float = atan2(0.51, 0.55)             # 42.8 deg off vertical
	for sxl in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "DischargeLeg" + ("L" if sxl < 0.0 else "R")
		p.add_child(leg)
		leg.position = Vector3(float(sxl) * 0.365, y_thr - 0.375, 0.0)
		leg.rotation.z = float(sxl) * leg_ang
		_hollow_box(leg, 0.36, 0.78, 0.38, Vector3.ZERO, 0.05, galv)
		_box(leg, Vector3(0.46, 0.04, 0.48), Vector3(0.0, -0.41, 0.0), castiron)
	# Bolted access plate + name sticker, laid on `_flare4`'s own +Z panel using
	# that panel's own centre and tilt, so it tracks any re-proportioning.
	var dis_h : float = deck_y * 0.45
	var dis_bd : float = 0.38
	var dis_td : float = ch_hz * 1.10
	var dis_dz : float = (dis_td - dis_bd) * 0.5
	var dis_tilt : float = atan2(dis_dz, dis_h)
	var acc := Node3D.new()
	acc.name = "DischargeAccessPlate"
	p.add_child(acc)
	acc.position = Vector3(0.0, base_y - dis_h * 0.5, (dis_bd + dis_td) * 0.25) \
		+ Vector3(0.0, -sin(dis_tilt), cos(dis_tilt)) * 0.028
	acc.rotation.x = dis_tilt
	_box(acc, Vector3(0.42, 0.34, 0.012), Vector3.ZERO, galv)
	for bxi in [-0.18, -0.06, 0.06, 0.18]:
		for byi in [-0.14, 0.14]:
			_cyl(acc, 0.011, 0.011, 0.016, Vector3(float(bxi), float(byi), 0.012), castiron, "z")
	for bsi in [-0.18, 0.18]:
		_cyl(acc, 0.011, 0.011, 0.016, Vector3(float(bsi), 0.0, 0.012), castiron, "z")
	_box(acc, Vector3(0.11, 0.07, 0.004), Vector3(0.27, 0.22, 0.010), yellow_f)   # yellow name sticker

	# ── PHOTO: loose yellow PLATE standing on the deck (OPERATOR 2026-08-30) ────
	# CORRECTION. This used to be a converging yellow chute/hopper hanging
	# through the deck, built from the narration-only reading "yellow chute on
	# the platform's near side". The operator, on seeing it: "you also drew like
	# a yellow shoot like thing? which is not anywhere on the image and also
	# doesn't make sense" -- and, of the yellow object that IS in the photo:
	# "that yellow [...] is not a mesh. It is a plate."
	#
	# So: one flat yellow sheet-steel panel standing on the grating just inside
	# the near railing, leaning back very slightly, with a folded lip along its
	# top edge at one end. It carries nothing and drains nothing. In a photo taken
	# mid-construction a loose guard panel parked on the deck is exactly what you
	# would expect, but its PURPOSE is unknown and is not guessed at here.
	#
	# PHOTO: that it is flat, yellow, full-height-ish, stands on the deck inside
	# the railing, and has a folded top lip.
	# TYPICAL: its size, its lean angle, and where along the railing it stands.
	# Pulled to the -X end and cut to 0.95 x 0.95 m. Spanning the full deck front
	# at the photo's apparent size, it became an opaque billboard that hid the
	# machine from every near-side camera AND stood in front of the granulator's
	# interactive screen-cradle door (X -0.612..0.612 on the +Z face), which a
	# player has to reach. This is a deliberate deviation from the photo's exact
	# placement, for playability -- flagged here rather than silently made.
	var yp_len : float = 0.95
	var yp_h : float = 0.95
	var yp_x : float = -0.95
	var yp_z : float = hd * 0.80
	var yp := _box(p, Vector3(yp_len, yp_h, 0.03),
		Vector3(yp_x, deck_top + yp_h * 0.5, yp_z), yellow_f)
	yp.rotation.x = deg_to_rad(4.0)
	_box(p, Vector3(yp_len * 0.42, 0.05, 0.15),
		Vector3(yp_x - yp_len * 0.26, deck_top + yp_h - 0.03, yp_z - 0.07), yellow_f)

	# ── PHOTO: tool shadow board hung inside the -X railing ───────────────
	# A yellow board hangs off the railing carrying two numbered tool
	# silhouettes. Position 1 still has its big open-ended spanner ON the board;
	# position 2 has lost its spanner and only the painted outline is left.
	# That gap is modelled deliberately -- it is what the photograph shows, and
	# a shadow board with a missing tool is what a working shadow board looks
	# like. This is very likely the "tools (probably for opening the mill)" the
	# operator listed among the environment items.
	#
	# PHOTO: existence, the railing mounting, the yellow board, two positions,
	# the 1 / 2 numbering, tool 1 present and tool 2 missing, and the two shapes
	# (1 = single open-ended spanner, 2 = combination spanner, ring + open jaw).
	# TYPICAL: the board size, sized to one railing bay, and which bay it hangs in.
	var tb_x : float = -hw + 0.03
	var tb_z : float = hd * 0.48
	var tb_cy : float = rail_base + rail_h * 0.52
	var tb_w : float = 0.80                            # board spans Z
	var tb_h : float = 0.78                            # board spans Y
	var tb_face : float = tb_x + 0.0125                # painted, deck-facing (+X) surface
	var tb_pnt : float = tb_face + 0.002               # silhouette paint plane
	var tb_tool : float = tb_face + 0.018              # a real tool hangs proud of the board
	_box(p, Vector3(0.025, tb_h, tb_w), Vector3(tb_x, tb_cy, tb_z), yellow_f)
	for tbz in [-1.0, 1.0]:
		_box(p, Vector3(0.05, 0.06, 0.05),
			Vector3(tb_x - 0.018, tb_cy + tb_h * 0.46, tb_z + float(tbz) * tb_w * 0.42), aged)
	# Position 1 -- painted silhouette WITH the actual spanner still on it.
	var t1_z : float = tb_z - 0.19
	_box(p, Vector3(0.006, 0.52, 0.078), Vector3(tb_pnt, tb_cy - 0.02, t1_z), placard)
	_box(p, Vector3(0.028, 0.40, 0.052), Vector3(tb_tool, tb_cy + 0.04, t1_z), rust)
	_box(p, Vector3(0.030, 0.09, 0.125), Vector3(tb_tool, tb_cy - 0.19, t1_z), rust)
	for tbj in [-1.0, 1.0]:
		_box(p, Vector3(0.030, 0.085, 0.040),
			Vector3(tb_tool, tb_cy - 0.272, t1_z + float(tbj) * 0.042), rust)
	# Position 2 -- the SECOND wrench. OPERATOR 2026-08-30: "please model the
	# second [wrench] [...] it's not on the photo, but you can see that it's just
	# the same one, but [...] smaller". So it is the same single open-ended
	# spanner as position 1 at 0.72 scale, and it is PRESENT on the board -- the
	# earlier build left this position empty because the tool is not legible in
	# the photograph, which the operator has now settled from his own knowledge
	# of the machine. Silhouette matches: a smaller copy of position 1's, not the
	# ring-ended combination spanner the low-resolution outline suggested.
	var t2_z : float = tb_z + 0.19
	var t2_s : float = 0.72                            # scale vs position 1
	_box(p, Vector3(0.006, 0.52 * t2_s, 0.078 * t2_s),
		Vector3(tb_pnt, tb_cy + 0.03, t2_z), placard)
	_box(p, Vector3(0.026, 0.40 * t2_s, 0.052 * t2_s),
		Vector3(tb_tool, tb_cy + 0.085, t2_z), rust)
	_box(p, Vector3(0.028, 0.09 * t2_s, 0.125 * t2_s),
		Vector3(tb_tool, tb_cy - 0.075, t2_z), rust)
	for tbj2 in [-1.0, 1.0]:
		_box(p, Vector3(0.028, 0.085 * t2_s, 0.040 * t2_s),
			Vector3(tb_tool, tb_cy - 0.134, t2_z + float(tbj2) * 0.042 * t2_s), rust)
	if not ghost:
		for tbi in 2:
			var num := _stencil_label(p, "1" if tbi == 0 else "2", Vector3(0.07, 0.07, 0.01), "+X")
			num.position = Vector3(tb_pnt + 0.004, tb_cy + tb_h * 0.40, (t1_z if tbi == 0 else t2_z))
			for ch4 in num.get_children():
				if ch4 is Label3D:
					(ch4 as Label3D).modulate = Color(0.17, 0.15, 0.10)
					(ch4 as Label3D).outline_modulate = Color(1.0, 1.0, 1.0, 0.0)

	# ── B4: yellow MAALMOLEN equipment sticker on the landing-facing (-Z) wall ─
	# WORD ONLY. Line3CDef.gd:66 says L3C.6, but the operator could not read the
	# number on the real sticker and was explicitly unsure, so none is stencilled.
	_box(p, Vector3(0.66, 0.24, 0.012), Vector3(0.0, ch_cy + ch_h * 0.32, -ch_hz - 0.006), yellow_f)
	if not ghost:
		var tag := _stencil_label(p, "MAALMOLEN", Vector3(0.58, 0.15, 0.01), "-Z")
		tag.position = Vector3(0.0, ch_cy + ch_h * 0.32, -ch_hz - 0.016)
		for ch2 in tag.get_children():
			if ch2 is Label3D:
				(ch2 as Label3D).modulate = Color(0.12, 0.12, 0.12)
				(ch2 as Label3D).outline_modulate = Color(1.0, 1.0, 1.0, 0.0)

	# ── +BP2 control cabinet on the deck (PHOTO 2026-08-29) ─────────────────
	# REPLACES an invented TYPICAL 0.30 x 0.42 x 0.22 box that used to stand on
	# the +Z edge with no source behind it. The operator photograph
	# (docs/plant/photos/maalmolen_3c_construction_2026-08-29.jpg, read in
	# docs/plant/maalmolen_3c_photo_reading_2026-08-29.md section 9b) shows the
	# real thing: a light-grey PAINTED sheet-steel enclosure standing on the
	# grating BETWEEN the belt drive and the cream motor -- the face is smooth,
	# with none of galvanising's spangle, so it is a RAL 7035 painted cabinet,
	# not raw galvanised steel. Stencilled +BP2, with a row of
	# three devices across the door -- grey button, GREEN lamp, grey button --
	# a fourth device lower down, and a bundle of black cable leaving the bottom
	# and running off along the deck toward the motor.
	#
	# PHOTO: existence, position, the light-grey painted livery, the +BP2
	# stencil, the device layout and the cable bundle.
	# TYPICAL: the enclosure dimensions (a standard ~600 x 800 x 300 mm floor
	# box -- the photo gives no scale reference near it) and the red mushroom
	# E-stop, which is mandatory on a granulator panel but is not legible in the
	# photograph. Both are labelled as such rather than passed off as sourced.
	#
	# Clearances, computed not eyeballed: the motor skid starts at X 0.3995 and
	# the cabinet ends at X 0.35 (0.05 m); the chamber -Z face is at -0.782 and
	# the cabinet +Z face at -0.90 (0.12 m); the -Z railing is at -1.564 and the
	# cabinet -Z face at -1.20 (0.36 m). Nothing on the drive reaches X < 0.80.
	var bp_w : float = 0.60
	var bp_h : float = 0.80
	var bp_d : float = 0.30
	var bp_x : float = -0.08              # -X of the motor: see the cowl clearance note
	var bp_z : float = -1.05
	var bp_y : float = deck_top + bp_h * 0.5
	var bp_f : float = bp_z - bp_d * 0.5 - 0.004       # door plane, faces -Z
	# GAP: the palette has no light-grey enclosure paint. Electrical cabinets are
	# finished RAL 7035 light grey, and the photo shows a SMOOTH light-grey face
	# with none of galvanising's spangle -- so `galv` reads far too dark and too
	# mottled here. Local material until MaterialPalette gains one.
	var cabgrey : StandardMaterial3D = _mat(Color(0.74, 0.74, 0.72), ghost, 0.20, 0.45)
	_box(p, Vector3(bp_w, bp_h, bp_d), Vector3(bp_x, bp_y, bp_z), cabgrey)
	_box(p, Vector3(bp_w * 0.90, bp_h * 0.92, 0.012), Vector3(bp_x, bp_y, bp_f), cabgrey)
	_box(p, Vector3(bp_w * 0.96, 0.022, 0.024),
		Vector3(bp_x, bp_y + bp_h * 0.5 - 0.011, bp_z - bp_d * 0.5 + 0.012), aged)
	for bph in [-1.0, 1.0]:
		_box(p, Vector3(0.05, 0.07, 0.05),
			Vector3(bp_x + bp_w * 0.46, bp_y + float(bph) * bp_h * 0.32, bp_z - bp_d * 0.40), aged)
	_box(p, Vector3(bp_w * 1.02, 0.03, bp_d * 1.02), Vector3(bp_x, deck_top + 0.015, bp_z), aged)
	# Cable bundle out of the bottom, running off toward the motor.
	_cyl(p, 0.05, 0.05, 0.24, Vector3(bp_x + 0.14, deck_top + 0.06, bp_z), rubber, "x")
	_cyl(p, 0.05, 0.05, 0.34, Vector3(bp_x + 0.26, deck_top + 0.06, bp_z - 0.17), rubber, "z")
	if not ghost:
		# Row of three across the door: grey, GREEN lamp, grey.
		for bpi in 3:
			var bpx : float = bp_x + (float(bpi) - 1.0) * 0.15
			var bpm : StandardMaterial3D = P.mat_indicator_green() if bpi == 1 else galv
			_cyl(p, 0.026, 0.026, 0.022, Vector3(bpx, bp_y + 0.05, bp_f - 0.008), bpm, "z")
		# Fourth device, lower left.
		_cyl(p, 0.026, 0.026, 0.022, Vector3(bp_x - 0.11, bp_y - 0.26, bp_f - 0.008), galv, "z")
		# TYPICAL -- red mushroom emergency stop (see the note above).
		_cyl(p, 0.042, 0.042, 0.026, Vector3(bp_x + 0.17, bp_y - 0.26, bp_f - 0.010), P.mat_indicator_red(), "z")
		var bp_tag := _stencil_label(p, "+BP2", Vector3(0.20, 0.09, 0.01), "-Z")
		bp_tag.position = Vector3(bp_x + 0.13, bp_y + 0.25, bp_f - 0.006)
		for ch3 in bp_tag.get_children():
			if ch3 is Label3D:
				(ch3 as Label3D).modulate = Color(0.13, 0.13, 0.14)
				(ch3 as Label3D).outline_modulate = Color(1.0, 1.0, 1.0, 0.0)

	# ── Caged access ladder on the +X face ────────────────────────────────────
	_caged_ladder(p, Vector3(hw + 0.10, 0.0, hd * 0.35), deck_y + 0.9, galv, ghost)

	# NOTE — the two bare blue 0.5 x 0.6 x 0.5 cubes that used to stand on the
	# ground here are GONE on purpose. The operator (2026-08-29) identified the
	# blue motors under this platform as the drives of the two FRICTION
	# SEPARATORS, which are their own catalog placeable (`friction_sep` ->
	# `_m_friction`, which already builds its own rule-8b blue `_motor_unit`).
	# Modelling them here duplicated another machine's drives, dragged them along
	# whenever the mill was moved, and had no photo detail behind them at all.


## DOSEER (dosing) SILO — NOT a vertical round silo. It's a round silo laid on its
## side, cut horizontally in half: a long HALF-CYLINDER TROUGH (open top) with 3
## screw augers along the bottom that meter material out the bottom discharge. The
## outer two augers ride higher up the curved walls than the centre one (operator:
## "the 3 screws are angled upwards from the side walls"). Output is at the bottom.
static func _m_doseersilo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell  := _mat(color, ghost, 0.45, 0.45)
	var steel  := _mat(_STEEL, ghost, 0.60, 0.35)
	var dark   := _mat(_DARK, ghost, 0.5, 0.55)
	var flight := _mat(Color(0.78, 0.55, 0.16), ghost, 0.3, 0.5)   # auger flighting (brassy)
	var grating := _mat(Color(0.36, 0.40, 0.38), ghost, 0.3, 0.85)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)

	var radius : float = size.x * 0.46
	var length : float = size.z * 0.92
	var leg_h : float = size.y * 0.34
	var axis_y : float = leg_h + radius            # trough axis height; bottom sits at leg_h
	var axis := Vector3(0.0, axis_y, 0.0)

	# ── Heavy Structural Support Legs with Diagonal K-Bracing ─────────────────
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(0.16, leg_h, 0.16), Vector3(sx * radius * 0.8, leg_h * 0.5, sz * length * 0.42), steel)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_h)
			_box(p, Vector3(0.26, 0.04, 0.26), Vector3(sx * radius * 0.8, 0.02, sz * length * 0.42), dark)
	_box(p, Vector3(radius * 1.8, 0.12, 0.12), Vector3(0, leg_h - 0.08,  length * 0.42), steel)
	_box(p, Vector3(radius * 1.8, 0.12, 0.12), Vector3(0, leg_h - 0.08, -length * 0.42), steel)
	# Diagonal sway braces
	for sx2 in [-1.0, 1.0]:
		_box(p, Vector3(0.08, 0.08, length * 0.85), Vector3(sx2 * radius * 0.8, leg_h * 0.45, 0.0), steel)

	# ── Half-cylinder trough (open top) + heavy bolted end plates + rim ───────
	_half_pipe(p, radius, length, axis, shell, 9)
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(radius * 2.0, radius, 0.08), Vector3(0, axis_y - radius * 0.5, sz * length * 0.5), shell)
		_cyl(p, radius * 1.02, radius * 1.02, 0.04, Vector3(0, axis_y, sz * length * 0.5), steel, "z")
	# Top rim flanges along the open edges
	_box(p, Vector3(0.14, 0.10, length), Vector3( radius, axis_y, 0), steel)
	_box(p, Vector3(0.14, 0.10, length), Vector3(-radius, axis_y, 0), steel)

	# Safety walk-on grating & yellow safety borders covering open top
	if not ghost:
		_box(p, Vector3(radius * 1.9, 0.04, length * 0.96), Vector3(0, axis_y + 0.02, 0), grating)
		_box(p, Vector3(radius * 2.0, 0.02, 0.08), Vector3(0, axis_y + 0.05,  length * 0.48), yellow)
		_box(p, Vector3(radius * 2.0, 0.02, 0.08), Vector3(0, axis_y + 0.05, -length * 0.48), yellow)

	# ── 3 independent augers along the bottom: centre lowest, outer two ride up walls ──
	var shaft_r : float = radius * 0.06
	var flight_r : float = radius * 0.17
	var clr : float = flight_r * 1.15
	var side_x : float = radius * 0.5
	var side_y : float = axis_y - sqrt(maxf(radius * radius - side_x * side_x, 0.0)) + clr
	_spinning_auger(p, length, Vector3(0.0, axis_y - radius + clr, 0.0), shaft_r, flight_r, steel, flight, ghost, 60.0, "auger_1")
	_spinning_auger(p, length, Vector3(-side_x, side_y, 0.0), shaft_r, flight_r, steel, flight, ghost, 60.0, "auger_2")
	_spinning_auger(p, length, Vector3( side_x, side_y, 0.0), shaft_r, flight_r, steel, flight, ghost, 60.0, "auger_3")

	# ── Bottom discharge hopper & metered slide gate between legs ─────────────
	_box(p, Vector3(radius * 0.95, leg_h * 0.72, length * 0.32), Vector3(0, leg_h * 0.5, 0), dark)
	_box(p, Vector3(radius * 1.05, 0.06, length * 0.38), Vector3(0, leg_h * 0.15, 0), steel)

	# ── 3 independent auger drive gearmotors on the rear (+Z) face ─────────────
	_motor_unit(p, radius * 0.16, radius * 0.38, Vector3(0, axis_y - radius + clr, length * 0.5 + radius * 0.28), "z", ghost)
	_motor_unit(p, radius * 0.14, radius * 0.34, Vector3(-side_x, side_y, length * 0.5 + radius * 0.25), "z", ghost)
	_motor_unit(p, radius * 0.14, radius * 0.34, Vector3( side_x, side_y, length * 0.5 + radius * 0.25), "z", ghost)

# ── flotation tank: long water bath, inlet roll, transport rolls, big outlet roll
# Survey-fixed (#230): raised on a real ~3.5 m stand, side profile tapered inward
# to a ~6 m flat bottom ~1 m above ground, slow paddles (≈4× slower than the old
# default 45 rpm), bespoke per-position paddles (small inlet / 9 transport with
# subtle variation / large drum-style outlet), a slow scraper bar above the +Z
# outlet that drags floating material into a discharge container, and a visible
# chain+sprocket drive on the outlet paddle (other paddles get small motor stubs).
static func _m_flotation(p: Node3D, size: Vector3, color: Color, ghost: bool, wide : bool = false) -> void:
	var tank := _mat(color, ghost, 0.4, 0.4)
	var water := _mat(Color(0.20, 0.45, 0.60, 0.55), ghost, 0.0, 0.1)
	var roller := _mat(_DARK, ghost, 0.4, 0.6)
	var legmat := _mat(_DARK, ghost, 0.5, 0.6)
	if not ghost:
		# Photo-extracted weathered stainless (flotatietank_3A.png) — the palette
		# triplet was calibrated for THIS tank (catalog colour == palette fallback,
		# see MaterialPalette.mat_stainless_weathered). Palette mats are shared
		# opaque singletons, so ghosts keep the translucent _mat above. The wide
		# 3C/6 variant keeps its flat colour until it has photo grounding of its own.
		if not wide:
			tank = MaterialPalette.mat_stainless_weathered()
		legmat = MaterialPalette.mat_steel_dark_aged()
	var hz := size.z * 0.5
	# ── HEIGHT PROFILE (operator survey #230) ─────────────────────────────────
	# Stand top at 3.5 m; tank rim ~0.6 m higher; flat tank bottom ~1 m above
	# ground. Side walls taper inward from rim to flat bottom.
	var flat_bot_y : float = 1.0
	var stand_top_y : float = 3.5
	var rim_y : float = stand_top_y + 0.6
	var tank_depth : float = rim_y - flat_bot_y
	var roll_y : float = rim_y - 0.35         # paddle shafts just under the rim
	# ── RAISED STAND (4 heavy posts + cross braces + top ring) ────────────────
	var hx_l : float = size.x * 0.45
	var hz_l : float = size.z * 0.45
	var leg_w : float = 0.18
	var leg_signs : Array[Vector2] = [
		Vector2(-1.0, -1.0), Vector2(1.0, -1.0),
		Vector2(-1.0,  1.0), Vector2(1.0,  1.0),
	]
	for s in leg_signs:
		var lg := _box(p, Vector3(leg_w, stand_top_y, leg_w),
				Vector3(s.x * hx_l, stand_top_y * 0.5, s.y * hz_l), legmat)
		lg.add_to_group("machine_leg")
		lg.set_meta("leg_h", stand_top_y)
	# X-direction cross braces (low & mid) at -Z and +Z ends
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(hx_l * 2.0, 0.06, 0.06),
				Vector3(0.0, stand_top_y * 0.35, sz * hz_l), legmat)
		_box(p, Vector3(hx_l * 2.0, 0.06, 0.06),
				Vector3(0.0, stand_top_y * 0.70, sz * hz_l), legmat)
	# Z-direction cross braces along the long sides
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(0.06, 0.06, hz_l * 2.0),
				Vector3(sx * hx_l, stand_top_y * 0.35, 0.0), legmat)
		_box(p, Vector3(0.06, 0.06, hz_l * 2.0),
				Vector3(sx * hx_l, stand_top_y * 0.70, 0.0), legmat)
	# Perimeter top ring beam at the stand top
	_box(p, Vector3(hx_l * 2.0 + leg_w, 0.12, 0.16),
			Vector3(0.0, stand_top_y + 0.06, -hz_l), legmat)
	_box(p, Vector3(hx_l * 2.0 + leg_w, 0.12, 0.16),
			Vector3(0.0, stand_top_y + 0.06,  hz_l), legmat)
	_box(p, Vector3(0.16, 0.12, hz_l * 2.0),
			Vector3(-hx_l, stand_top_y + 0.06, 0.0), legmat)
	_box(p, Vector3(0.16, 0.12, hz_l * 2.0),
			Vector3( hx_l, stand_top_y + 0.06, 0.0), legmat)
	# ── TAPERED TANK BODY ─────────────────────────────────────────────────────
	# Narrow flat bottom band (~6 m × ~30 % of size.x) sits at flat_bot_y.
	var flat_bot_x : float = size.x * 0.30
	var flat_bot_z : float = 6.0
	_box(p, Vector3(flat_bot_x, 0.08, flat_bot_z),
			Vector3(0.0, flat_bot_y, 0.0), tank)
	# End walls (vertical) close the flat-bottom ends and rise to the rim
	_box(p, Vector3(flat_bot_x, tank_depth, 0.08),
			Vector3(0.0, flat_bot_y + tank_depth * 0.5,  flat_bot_z * 0.5), tank)
	_box(p, Vector3(flat_bot_x, tank_depth, 0.08),
			Vector3(0.0, flat_bot_y + tank_depth * 0.5, -flat_bot_z * 0.5), tank)
	# Tapered side panels: long thin _boxes rotated about Z so their inside face
	# slopes from the rim (full size.x*0.92 width) down to flat_bot_x.
	var top_hx : float = size.x * 0.46         # half-width at rim
	var bot_hx : float = flat_bot_x * 0.5      # half-width at flat bottom
	var panel_dx : float = top_hx - bot_hx
	var panel_dy : float = tank_depth
	var panel_len : float = sqrt(panel_dx * panel_dx + panel_dy * panel_dy)
	var slope_ang : float = atan2(panel_dx, panel_dy)
	for sx in [-1.0, 1.0]:
		var panel := _box(p, Vector3(0.08, panel_len, size.z * 0.96),
				Vector3(sx * (bot_hx + panel_dx * 0.5),
						flat_bot_y + panel_dy * 0.5,
						0.0), tank)
		# Operator report 2026-07-05: the tank body read UPSIDE DOWN — the sign
		# below was +sx, which tipped each panel TOP inward (wide at the floor,
		# narrow at the rim). -sx tips the top OUTWARD: narrow flat bottom
		# flaring to the wide rim, as surveyed (#230). Correction per panel =
		# slope_ang (24.2° for the 4.5 m tank, 31.0° for the 6 m wide variant),
		# flipped across vertical.
		panel.rotation.z = -sx * slope_ang
	# Outer rim cap boxes — short vertical lips at the rim
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(0.10, 0.18, size.z * 0.96),
				Vector3(sx * top_hx, rim_y + 0.05, 0.0), tank)
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(size.x * 0.92, 0.18, 0.10),
				Vector3(0.0, rim_y + 0.05, sz * hz * 0.96), tank)
	var surf_y : float = rim_y - 0.10
	# #235 — WATER restored (operator 2026-07-16: removing the flat surface "sheet" left
	# the tanks looking drained/leaked). Model the actual water BODY filling the tank from
	# near the bottom up to the surface (translucent), NOT the flat lid-like plane that was
	# removed earlier. The paddles + film raft still ride on the surface at surf_y.
	if not ghost:
		# Operator 2026-07-16: the old single straight box hung OUTSIDE the sloped
		# V-hopper walls and poked past the end walls = "water contained by nothing,
		# floating in the air". Rebuild as interior-CLIPPED slabs (each sized to the
		# wall at its own bottom edge so no slab crosses a sloped wall, and bounded
		# by the end walls on Z) + a REAL Waterbox physics volume so bodies actually
		# float (buoyancy + drag), per the installed addons/waterbox plugin.
		var wtr_bot : float = flat_bot_y + 0.12
		var wvol_h : float = maxf(surf_y - wtr_bot, 0.2)
		var inset : float = 0.08
		var z_half : float = flat_bot_z * 0.5 - inset
		var n_slab : int = 6
		for si in n_slab:
			var y0 : float = lerpf(wtr_bot, surf_y, float(si) / float(n_slab))
			var y1 : float = lerpf(wtr_bot, surf_y, float(si + 1) / float(n_slab))
			var wall_hx : float = bot_hx + (top_hx - bot_hx) * (y0 - flat_bot_y) / tank_depth
			var x_half : float = maxf(wall_hx - inset, 0.05)
			_box(p, Vector3(x_half * 2.0, (y1 - y0) + 0.02, z_half * 2.0),
				Vector3(0.0, (y0 + y1) * 0.5, 0.0), water)
		var surf_hx : float = maxf(bot_hx + (top_hx - bot_hx) * (surf_y - flat_bot_y) / tank_depth - inset, 0.05)
		_box(p, Vector3(surf_hx * 2.0, 0.04, z_half * 2.0), Vector3(0.0, surf_y, 0.0), water)
		# Real water physics — WaterBox addon (buoyancy + drag on any RigidBody3D
		# inside). Build the Area3D child FIRST, then parent wbox, or WaterBox._ready
		# connects to a null water_area and crashes.
		var wbox := WaterBox.new()
		wbox.name = "TankWater"
		wbox.water_density = 1.0
		wbox.water_drag = 0.5
		wbox.require_buoyancy_component = false
		var warea := Area3D.new()
		warea.name = "WaterVolume"
		warea.position = Vector3(0.0, (surf_y + wtr_bot) * 0.5, 0.0)
		var wshape := CollisionShape3D.new()
		var wbs := BoxShape3D.new()
		wbs.size = Vector3((bot_hx + top_hx) * 0.9, wvol_h, z_half * 2.0)
		wshape.shape = wbs
		warea.add_child(wshape)
		wbox.add_child(warea)
		p.add_child(wbox)
	# ── PADDLE LAYOUT (operator 2026-07-15, per line) ─────────────────────────
	# 3A/3B (standard) = 7 paddles: a LARGE 1st (hidden under a metal plate) + 5
	# small + a LARGE last. 3C/6 (wide) = 11: LARGE 1st + 9 small + LARGE last.
	# 1st & last are ~double the small diameter. ONE motor per paddle, IN LINE with
	# the axle (large motor on the large end paddles, small on the middle). comp
	# tags kept for the LineFlow sim (inlet / transport_* / outlet).
	var blade_t : float = 0.025
	var small_r : float = 0.06
	var large_r : float = 0.12
	var side_x  : float = size.x * 0.41                 # shaft end near the +X wall
	var n_mid : int = 9 if wide else 5
	var padz : Array = [-hz * 0.85]                     # LARGE 1st paddle
	for i in n_mid:
		padz.append(lerp(-hz * 0.58, hz * 0.58, float(i) / float(n_mid - 1)))
	padz.append(hz * 0.85)                              # LARGE last paddle
	var n_pad : int = padz.size()
	for pi in n_pad:
		var pz : float = float(padz[pi])
		var is_end : bool = (pi == 0 or pi == n_pad - 1)
		var pr : float = large_r if is_end else small_r
		var comp : String = "inlet" if pi == 0 else ("outlet" if pi == n_pad - 1 else "transport_%d" % (1 + (pi - 1) % 3))
		var rpm : float = 9.0 if is_end else 5.0
		var pad := _spinning_cyl(p, pr, pr, size.x * 0.82,
				Vector3(0.0, roll_y, pz), roller, "x", Vector3.RIGHT, ghost, rpm)
		if not ghost:
			pad.set_meta("comp", comp)
			_attach_paddle_blades(pad, (6 if is_end else 4), size.x * 0.76,
					(0.035 if is_end else blade_t), (0.42 if is_end else 0.28), roller)
			pad.rotation.x = TAU * (float(pi) * 0.13)   # phase offset so they don't flap in unison
			# per-paddle drive motor, IN LINE with the axle, just outside the +X wall
			# Operator 2026-08-28: each paddle has its own motor; the two large
			# paddles get motors ~TWICE the small ones; a small paddle motor is
			# ~10 cm dia or less ("smaller than a pipe from a blower").
			var mr : float = 0.10 if is_end else 0.05
			var ml : float = 0.40 if is_end else 0.20
			_motor_unit(p, mr, ml, Vector3(side_x + ml * 0.5 + 0.06, roll_y, pz), "x", ghost)
	# Metal cover plate hiding the LARGE 1st paddle — 3A/3B only (operator).
	if not ghost and not wide:
		_box(p, Vector3(size.x * 0.9, 0.05, hz * 0.30),
				Vector3(0.0, roll_y + large_r + 0.12, -hz * 0.85), tank)
	# ── NO SURFACE SCRAPER, NO SECOND CONTAINER (operator 2026-08-28) ─────────
	# #230's "slow scraper bar above the +Z outlet + discharge container" was a
	# MIS-SURVEY of the uittrek PADDLE: "the outlet pedal … pushes film
	# basically over the edge of the flotation tank into the dewatering screw.
	# There is no container involved there, and it's not a scraper." Removed;
	# the ONE container is the bottom scraper's (below its downspout).

	# ── WEIR-SCOOP OVERFLOW CHUTE (kept; #100) ────────────────────────────────
	# On the OUTSIDE of the +Z wall — overflow path to the downstream dewater_screw.
	if not ghost:
		var wall_top_y : float = rim_y + 0.10
		var chute_root := Node3D.new()
		chute_root.name = "WeirChute"
		chute_root.position = Vector3(0.0, wall_top_y - 0.02, hz * 0.96 + 0.04)
		chute_root.rotation.x = deg_to_rad(35.0)
		p.add_child(chute_root)
		var chute_l : float = 0.90
		var chute_w : float = size.x * 0.78
		var chute_t : float = 0.03
		_box(chute_root, Vector3(chute_w, chute_t, chute_l),
			Vector3(0.0, 0.0, chute_l * 0.5), tank)
		_box(chute_root, Vector3(chute_t, 0.22, chute_l),
			Vector3( chute_w * 0.5, 0.11, chute_l * 0.5), tank)
		_box(chute_root, Vector3(chute_t, 0.22, chute_l),
			Vector3(-chute_w * 0.5, 0.11, chute_l * 0.5), tank)
	# ── PHYSICALIZED FILM (#161, #82) ─────────────────────────────────────────
	# Float-raft + sinkers, pinned to the new water surface y.
	if not ghost:
		var field_surf_y : float = surf_y + 0.04
		var field : Node3D = preload("res://src/sim/FilmFlakeField.gd").new()
		field.name = "FilmField"
		field.flake_count = clampi(int(round(size.x * 26.0)), 80, 200)
		field.area = Vector2(size.x * 0.78, size.z * 0.85)
		field.surface_y = field_surf_y
		field.flow_speed = 0.4
		field.flake_size = 0.075
		field.set_floor_y(flat_bot_y + 0.06)      # heavies fall to the narrow flat bottom
		field.set_mat_mode(true)
		p.add_child(field)

	# ── BOTTOM SCRAPER + 45° INCLINE + CONTAINER (Q2.3 + operator side-view
	# drawing flotation_tank_sketch_2026-08-28.png) ────────────────────────────
	# "the heavy parts can sink to the bottom. Then the scraper at the bottom
	# removes it … then up like a forty-five degree thing … into the container
	# below." The DRAWING settles the geometry the voice left open: the chain
	# runs the flat bottom, the incline starts MID-BOTTOM and climbs at 45°
	# toward the OUTLET (+Z) side (my first build had it at the infeed end —
	# corrected), enclosed in a chute HOUSING that rises above the waterline
	# ("so that the water doesn't exit through the scraper chute"), then a
	# bend-over downspout drops the sediment into an open container standing
	# on the floor past the tank. Assembly offset to -X so the weir chute +
	# surface-scraper furniture keep the centreline.
	if not ghost:
		var ch_mat := _mat(Color(0.30, 0.30, 0.33), ghost, 0.6, 0.5)
		var sc_x : float = -0.9
		var run_half : float = flat_bot_z * 0.5 - 0.3
		var ch_y : float = flat_bot_y + 0.14
		var inc_start_z : float = 0.5
		# Lower + upper chain runs along the bottom (idler turn at the -Z end).
		_box(p, Vector3(0.05, 0.03, run_half + inc_start_z), Vector3(sc_x, ch_y, (inc_start_z - run_half) * 0.5), ch_mat)
		_box(p, Vector3(0.05, 0.03, run_half + inc_start_z), Vector3(sc_x, ch_y + 0.18, (inc_start_z - run_half) * 0.5), ch_mat)
		var n_fl : int = int((run_half + inc_start_z) / 0.9)
		for fi in n_fl:
			var fz : float = -run_half + 0.45 + float(fi) * 0.9
			_box(p, Vector3(flat_bot_x * 0.62, 0.05, 0.06), Vector3(sc_x, ch_y - 0.02, fz), ch_mat)
		_cyl(p, 0.10, 0.10, flat_bot_x * 0.5, Vector3(sc_x, ch_y + 0.09, -run_half), ch_mat, "x")
		# 45° incline from mid-bottom up past the waterline at the +Z side.
		var inc_len : float = 4.6
		var inc := Node3D.new()
		inc.position = Vector3(sc_x, ch_y, inc_start_z)
		inc.rotation.x = deg_to_rad(45.0)
		p.add_child(inc)
		var tr_w : float = flat_bot_x * 0.62
		# Chute HOUSING: floor, two side walls AND a lid — enclosed so the tank
		# water cannot escape up the scraper path (operator).
		_box(inc, Vector3(tr_w, 0.04, inc_len), Vector3(0.0, 0.0, inc_len * 0.5), tank)
		for sx3 in [-1.0, 1.0]:
			_box(inc, Vector3(0.04, 0.34, inc_len), Vector3(float(sx3) * tr_w * 0.5, 0.17, inc_len * 0.5), tank)
		_box(inc, Vector3(tr_w, 0.04, inc_len), Vector3(0.0, 0.34, inc_len * 0.5), tank)
		# Chain + flights riding the incline (visible at the open head end).
		_box(inc, Vector3(0.05, 0.03, inc_len * 0.96), Vector3(0.0, 0.10, inc_len * 0.5), ch_mat)
		for fi2 in 4:
			_box(inc, Vector3(tr_w * 0.8, 0.05, 0.06), Vector3(0.0, 0.09, inc_len * (0.16 + 0.24 * float(fi2))), ch_mat)
		# Head: drive sprocket + motor above the rim, past the +Z wall.
		var head := Vector3(sc_x, ch_y + inc_len * sin(deg_to_rad(45.0)), inc_start_z + inc_len * cos(deg_to_rad(45.0)))
		var drv := _spinning_cyl(p, 0.10, 0.10, flat_bot_x * 0.5, head, ch_mat, "x", Vector3.RIGHT, ghost, 4.0)
		drv.set_meta("comp", "bottom_scraper")
		_motor_unit(p, 0.10, 0.30, head + Vector3(flat_bot_x * 0.35, 0.0, 0.0), "x", ghost)
		# Bend-over DOWNSPOUT (the drawing's orange hook): short forward roof +
		# vertical drop duct over the container.
		_box(p, Vector3(tr_w, 0.04, 0.55), head + Vector3(0.0, 0.16, 0.24), tank)
		var spout_z : float = head.z + 0.55
		_box(p, Vector3(0.30, 1.1, 0.04), Vector3(sc_x - 0.15 + 0.15, head.y - 0.35, spout_z + 0.17), tank)
		_box(p, Vector3(0.04, 1.1, 0.34), Vector3(sc_x - 0.17, head.y - 0.35, spout_z), tank)
		_box(p, Vector3(0.04, 1.1, 0.34), Vector3(sc_x + 0.17, head.y - 0.35, spout_z), tank)
		# The CONTAINER below the spout, on the floor past the tank (pink in the
		# drawing).
		var bcont := Node3D.new()
		bcont.name = "BottomScraperContainer"
		bcont.position = Vector3(sc_x, 0.0, spout_z + 0.1)
		p.add_child(bcont)
		var bbin := _mat(Color(0.42, 0.44, 0.30), ghost, 0.5, 0.5)
		_box(bcont, Vector3(1.2, 0.06, 1.2), Vector3(0.0, 0.03, 0.0), bbin)
		for sx4 in [-1.0, 1.0]:
			_box(bcont, Vector3(0.06, 1.0, 1.2), Vector3(float(sx4) * 0.6, 0.5, 0.0), bbin)
			_box(bcont, Vector3(1.2, 1.0, 0.06), Vector3(0.0, 0.5, float(sx4) * 0.6), bbin)

	# ── #232 PHOTO-ACCURATE HOPPER EXTERIOR (flotatietank_3A.png) ──────────────
	# Operator 2026-07-15: "HOPPER 4A" IS the flotation tank — rebuild faithfully.
	# Operator revision 2026-07-15: TOP OPEN (no collar) so water + paddles stay
	# visible; per-line paddle counts (7 for 3A/3B, 11 for 3C/6) with per-paddle
	# aligned motors are built in the paddle loop above. This block adds only the
	# operator CATWALK (1.2 m lower) + placards. The survey-calibrated bath, sim
	# comp tags, water/film field + rafter level link (rim 4.1 / surf 4.0) stay intact.
	if not ghost:
		var blue_mat := _mat(Color(0.14, 0.30, 0.55), ghost, 0.35, 0.5)   # blue structural supports
		var yel_mat  := _mat(_SAFETY, ghost, 0.2, 0.6)
		var grt_mat  := _mat(Color(0.36, 0.40, 0.38), ghost, 0.3, 0.85)
		# TOP OPEN (operator 2026-07-15) — no enclosing collar; water + paddles stay
		# visible. Operator CATWALK 1.2 m LOWER than the first pass, yellow railing
		# on BLUE legs, alongside the -X wall.
		var cw_top : float = rim_y - 0.25                # ≈ 3.85 m (was 5.05)
		var cw_hx : float = 0.60
		var cw_cx : float = -(top_hx + 0.16 + cw_hx)
		var cw_hz : float = hz * 0.82
		for wsx in [-1.0, 1.0]:
			for wsz in [-1.0, 1.0]:
				_box(p, Vector3(0.12, cw_top, 0.12),
					Vector3(cw_cx + float(wsx) * (cw_hx - 0.10), cw_top * 0.5, float(wsz) * (cw_hz - 0.2)), blue_mat)
		# WALKABLE deck → real collision (operator 2026-07-16: "impossible to walk
		# through a mesh"). _box_static_body wraps a StaticBody3D+BoxShape (survives
		# StaticMerge); 0.10 m thick so a fast capsule can't tunnel it.
		_box_static_body(p, Vector3(cw_hx * 2.0, 0.10, cw_hz * 2.0), Vector3(cw_cx, cw_top - 0.025, 0.0), grt_mat)
		var cw_rail := Node3D.new()
		cw_rail.position = Vector3(cw_cx, cw_top + 0.03, 0.0)
		p.add_child(cw_rail)
		_railing(cw_rail, cw_hx, cw_hz, 0.0, yel_mat, ["+x", "-z"])   # open +x (toward tank) + -z (stair)
		# Grating stair from the catwalk -Z end down to the floor.
		var fst_run : float = float(maxi(int(cw_top / 0.22), 4)) * 0.27
		var fst_pivot := Node3D.new()
		fst_pivot.position = Vector3(cw_cx, 0.0, -(cw_hz + fst_run))
		p.add_child(fst_pivot)
		_stair(fst_pivot, Vector3.ZERO, cw_top, 0.9, grt_mat, yel_mat)
		# Placards on the upper +X wall (HOPPER 4A only on the 3A/3B standard tank).
		var lbl_b := _stencil_label(p, "MAX LOAD 500KG", Vector3(1.05, 0.20, 0.01), "+X")
		lbl_b.position = Vector3(top_hx * 0.96, rim_y - 0.22, hz * 0.22)
		if not wide:
			var lbl_a := _stencil_label(p, "HOPPER 4A", Vector3(1.15, 0.30, 0.01), "+X")
			lbl_a.position = Vector3(top_hx * 0.96, rim_y - 0.55, -hz * 0.08)

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

	# ── Dimensions / anchors ──────────────────────────────────────────────────
	var hx     := size.x * 0.5
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
		# WALKABLE walkway → real collision (0.10 m so the capsule can't tunnel it).
		_box_static_body(p, Vector3(deck_w, 0.10, size.z * 0.96),
				Vector3(deck_cx, deck_y - 0.03, 0.0), grating)
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
	# Tube underside sits at ~size.y*0.25 (center size.y*0.62 minus radius size.x*0.42).
	# Legs were running half a metre up THROUGH the tube and motor — terminate at the underside.
	_legs(p, size, size.y * 0.25, dark)
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
	# A-frame supports: short legs at -Z (low/inlet), tall at +Z (high/outlet)
	# Leg heights match the tilted tube's underside at each end: at z=±size.z*0.35
	# the tube bottom sits at size.y*0.55 + z*tan(20°) - (size.x*0.3)/cos(20°), which
	# for size.y=2.6 lands at y≈0.47 (low) and y≈1.62 (high) → fractions 0.18 / 0.62.
	var lo_h : float = size.y * 0.18
	var hi_h : float = size.y * 0.62
	var lg_lo_r := _box(p, Vector3(0.1, lo_h, 0.1), Vector3( size.x * 0.3, lo_h * 0.5, -size.z * 0.35), dark)
	var lg_lo_l := _box(p, Vector3(0.1, lo_h, 0.1), Vector3(-size.x * 0.3, lo_h * 0.5, -size.z * 0.35), dark)
	var lg_hi_r := _box(p, Vector3(0.1, hi_h, 0.1), Vector3( size.x * 0.3, hi_h * 0.5, size.z * 0.35), dark)
	var lg_hi_l := _box(p, Vector3(0.1, hi_h, 0.1), Vector3(-size.x * 0.3, hi_h * 0.5, size.z * 0.35), dark)
	for _lg in [lg_lo_r, lg_lo_l]:
		_lg.add_to_group("machine_leg")
		_lg.set_meta("leg_h", lo_h)
	for _lg in [lg_hi_r, lg_hi_l]:
		_lg.add_to_group("machine_leg")
		_lg.set_meta("leg_h", hi_h)
	# inclined dewatering tube (low at -Z, high at +Z) — the encapsulated screw
	# lives INSIDE this tube (not visible from outside, per the operator's spec
	# for plant screws). The tube IS the encapsulation. Tilts UPWARD (+Z end is
	# the high/discharge end; -Z is the low/inlet where the catch bowl sits).
	_tube(p, size.x * 0.3, size.z * 0.95, Vector3(0.0, size.y * 0.55, 0.0), steel, PI / 2.0 - tilt)
	# water collection trough at the bottom end
	_box(p, Vector3(size.x * 0.55, 0.15, size.z * 0.35), Vector3(0.0, size.y * 0.18, -size.z * 0.3), dark)
	# drive motor at the top (+Z) end — uses _spinning_cyl so the motor coupling
	# visibly TURNS via RotatingMechanism, matching the other powered screws on
	# the line (rafter, transport_screw). Was a static _motor_unit cylinder
	# before; the dewater_screw is one of the line's driven machines so a still
	# motor reads as "broken" to the operator.
	_spinning_cyl(p, size.x * 0.18, size.x * 0.18, size.z * 0.18,
		Vector3(0.0, size.y * 0.9, size.z * 0.42),
		_mat(_DARK, ghost, 0.55, 0.5), "z", Vector3.BACK, ghost, 60.0)
	# Junction box on top of the motor (same as _motor_unit gave).
	_box(p, Vector3(size.x * 0.15, size.x * 0.09, size.z * 0.08),
		Vector3(0.0, size.y * 0.9 + size.x * 0.17, size.z * 0.42),
		_mat(Color(0.12, 0.12, 0.13), ghost, 0.3, 0.6))
	# #100 — weir-scoop catch bowl at the inlet (-Z, low) end. Sits BELOW the
	# flotation tank's outlet wall so overflow actually drops into it by gravity.
	var scoop_z      : float = -size.z * 0.42
	var scoop_y_lo   : float = size.y * 0.12
	var scoop_h      : float = size.y * 0.35
	var scoop_w      : float = size.x * 0.95
	var scoop_d      : float = size.z * 0.22
	var scoop_t      : float = 0.03
	_box(p, Vector3(scoop_w, scoop_t, scoop_d),
		Vector3(0.0, scoop_y_lo, scoop_z), steel)                                # floor
	_box(p, Vector3(scoop_w, scoop_h, scoop_t),
		Vector3(0.0, scoop_y_lo + scoop_h * 0.5, scoop_z - scoop_d * 0.5), steel)  # back wall (-Z)
	_box(p, Vector3(scoop_t, scoop_h, scoop_d),
		Vector3( scoop_w * 0.5, scoop_y_lo + scoop_h * 0.5, scoop_z), steel)     # right wall
	_box(p, Vector3(scoop_t, scoop_h, scoop_d),
		Vector3(-scoop_w * 0.5, scoop_y_lo + scoop_h * 0.5, scoop_z), steel)     # left wall
	# #212.6 PRESONA brand decal — 0.4 × 0.08 m white-on-blue on the +X face
	# of the catch-bowl / tank end of the dewater press.
	if not ghost:
		var prsona_blue := _mat(Color(0.10, 0.30, 0.60), ghost, 0.3, 0.55)
		_box(p, Vector3(0.005, 0.08, 0.40),
			Vector3(size.x * 0.31, size.y * 0.55, -size.z * 0.10), prsona_blue)
		var ps_lbl := _stencil_label(p, "PRESONA",
			Vector3(0.36, 0.07, 0.01), "+X")
		ps_lbl.position = Vector3(size.x * 0.315, size.y * 0.55, -size.z * 0.10)

# ── centrifugal pump: baseplate + volute + motor + coupling guard + piping ─────
static func _m_pump(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# #212.7 — operator wants the small floor-mounted Wilo-style pump: a teal
	# volute on a stainless skid with 4 floor-anchor feet, a tiny "WILO" decal
	# on the volute, and the existing motor / coupling / piping kept intact.
	# Pump body uses teal regardless of the catalog colour so it reads as the
	# Wilo unit. The caller's `color` is preserved as the base colour family
	# elsewhere on the model (e.g. skid wear).
	var teal_body := Color(0.20, 0.65, 0.65)
	var body_mat := _mat(teal_body, ghost, 0.4, 0.45)
	var _legacy_color := color  # noted for legacy callers
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var stainless := _mat(Color(0.78, 0.80, 0.83), ghost, 0.75, 0.25)
	# Bolt-flanged stainless skid base (slightly wider than the pump footprint).
	_box(p, Vector3(size.x * 1.2, 0.02, size.z * 1.2),
		Vector3(0.0, 0.01, 0.0), stainless)
	# 4 floor-anchor feet (CylinderMesh) at the corners of the skid.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(p, 0.015, 0.015, 0.06,
				Vector3(float(sx) * size.x * 0.58, 0.03, float(sz) * size.z * 0.58),
				stainless, "y")
	# baseplate (original) — sits proud of the new stainless skid.
	_box(p, Vector3(size.x * 0.95, 0.12, size.z * 0.95), Vector3(0.0, 0.08, 0.0), dark)
	# volute casing (snail) at the +Z end, axis along X — teal Wilo body.
	_cyl(p, size.y * 0.4, size.y * 0.4, size.x * 0.42, Vector3(0.0, size.y * 0.42, size.z * 0.3), body_mat, "x")
	# discharge pipe up from the volute
	_cyl(p, size.x * 0.14, size.x * 0.14, size.y * 0.5, Vector3(0.0, size.y * 0.75, size.z * 0.3), dark)
	# suction pipe out the front (+Z), axis Z
	_cyl(p, size.x * 0.16, size.x * 0.16, size.z * 0.3, Vector3(0.0, size.y * 0.42, size.z * 0.5), dark, "z")
	# coupling guard then motor at the -Z end
	_guard(p, Vector3(size.x * 0.32, size.y * 0.32, size.z * 0.16), Vector3(0.0, size.y * 0.42, size.z * 0.04), ghost)
	_motor_unit(p, size.y * 0.3, size.z * 0.4, Vector3(0.0, size.y * 0.42, -size.z * 0.25), "z", ghost)
	# Tiny "WILO" decal on the +X face of the volute body.
	if not ghost:
		var wilo_lbl := _stencil_label(p, "WILO",
			Vector3(size.x * 0.18, 0.04, 0.01), "+X")
		wilo_lbl.position = Vector3(size.x * 0.22, size.y * 0.42, size.z * 0.3)

# ── Named pump station: _m_pump + a stencil STATION label on the -X volute face
# (2026-07-06, water_small.md shared note 1). Used by pomp_c1 ("C1") and
# pomp_zeefbocht ("ZEEFBOCHT") so the stations are identifiable in-world while
# sharing the photo-verified Wilo model — the real C1 / zeefbocht pumps were
# never photographed (flags F7/F8), so the generic model is a marked stand-in.
static func _m_pump_labeled(p: Node3D, size: Vector3, color: Color, ghost: bool, station: String) -> void:
	_m_pump(p, size, color, ghost)
	if not ghost:
		var st_lbl := _stencil_label(p, station,
			Vector3(size.x * 0.30, 0.05, 0.01), "-X")
		st_lbl.position = Vector3(-size.x * 0.22, size.y * 0.42, size.z * 0.3)

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
		"tool_line_coupler": return load("res://src/scenes/world/LineCouplerTool.gd").new()
		"tool_lpg_rack": return load("res://src/scenes/world/LPGRack.gd").new()
		"tool_leafblower": return load("res://src/operator/LeafBlower.gd").new()
		"tool_jerrycan":   return load("res://src/scenes/world/JerryCan.gd").new()
		"socket_wrench_7": return load("res://src/scenes/world/SocketWrench7.gd").new()
	return null

## Build one of the four operator-spec opzetband variants. Each is a ShredderFeedBelt
## with the deck_length / incline_run / incline_deg / deck_width / top_flat_m / funnel
## params set per the geometry the operator gave. Lengths the user gave are slope
## lengths; we convert to horizontal run (incline_run = slope * cos(angle)).
## Ghost preview falls back to a translucent box.
##
##   • opzetband_3a3b — 4 m flat + 6 m at 40° + 0.5 m horizontal top
##   • opzetband_3c6  — 4 m flat + 8 m at 35°
##   • westa_band_1   — 45° climb + 0.6 m top flat, run DERIVED from the
##                     hoekgoot/funnel port helpers (NOT the operator's old
##                     "8 m at 35°" — that stale bullet outlived two rewrites
##                     of the branch below; review finding 2026-08-28)
##   • opzetband_1    — 5 m at 25°, 3 m wide, funnel walls
##                     (0–0.75 m straight wide, 0.75–3.0 m narrowing to 1.5 m wide,
##                      3.0–5.0 m straight narrow)
static func _build_opzetband(id: String, size: Vector3, ghost: bool) -> Node3D:
	if ghost:
		return _simple_ghost(size)
	var belt = load("res://src/scenes/world/ShredderFeedBelt.gd").new()
	belt.require_shredder = false   # build-menu placements run standalone unless wired up
	match id:
		"opzetband_3a3b":
			# Operator-spec: 8 m horizontal flat → 10 m inclined at 25° → 1 m top flat.
			# Total horizontal Z = 8 + 10·cos(25°) + 1 = 18.06 m
			# Vertical rise from incline = 10·sin(25°) = 4.23 m
			belt.deck_length = 8.0
			belt.incline_deg = 25.0
			belt.incline_run = 10.0 * cos(deg_to_rad(25.0))
			belt.top_flat_m  = 1.0
			belt.deck_width  = 2.0
		"opzetband_3c6":
			belt.deck_length = 4.0
			belt.incline_deg = 35.0
			belt.incline_run = 8.0 * cos(deg_to_rad(35.0))
			belt.deck_width  = 2.5
		"westa_band_1":
			# #196 — the 45° feeder belt at the end of the wash-feed group.
			# #fold 2026-08-28: with the line-1 fold laid out, the belt climbs
			# leg C (north) and discharges into the sga_feed_chute's IN port;
			# the chute makes the operator's "90 deg right turn" and drops
			# into the vw_trommel funnel on leg D. The whole height chain is
			# DERIVED here from the two shared port helpers — no baked height:
			#   chute lift = funnel mouth + 0.30 drop − chute OUT height
			#   belt lip   = chute IN height at that lift + 0.15 drop
			# (Before the fold this spec briefly aimed the lip at the funnel
			# directly; before THAT it was a stale 6.5 m constant aimed at a
			# deleted stub — measured 3.05 m too high. Guarded live by
			# test_line1_flow_conformance S4/S4b.)
			belt.deck_length = 0.0
			belt.incline_deg = 45.0
			belt.deck_width  = 1.2
			# Short flat at the top so material drops cleanly INTO the chute's
			# infeed rather than skidding off the end of the slope.
			belt.top_flat_m  = 0.6
			var vt_mouth_y : float = vw_trommel_funnel_mouth_local(
				Vector3(get_item("vw_trommel")["size"])).y
			var c_ports : Dictionary = sga_feed_chute_ports_local(
				Vector3(get_item("sga_feed_chute")["size"]))
			var chute_lift : float = vt_mouth_y + 0.30 - (c_ports["out"] as Vector3).y
			var lip_y : float = (c_ports["in"] as Vector3).y + chute_lift + 0.15
			belt.incline_run = (lip_y - belt.deck_height) \
				/ tan(deg_to_rad(belt.incline_deg))
		"opzetband_1":
			# #196 — 2× scale: 10 m @ 25° (was 5 m), 4 m wide (was 3 m). Metal
			# detector + reverse-reject head is built INTO this belt at 3/4 along
			# (see _attach_metaaldetector_head below) so the legacy standalone
			# metaaldetector entry was dropped from LINE_1_SEQ.
			belt.deck_length = 0.0
			belt.incline_deg = 25.0
			belt.incline_run = 10.0 * cos(deg_to_rad(25.0))
			belt.deck_width  = 4.0
			belt.funnel_start_m   = 1.5    # parallel-and-wide for the first 1.5 m
			belt.funnel_narrow_m  = 4.5    # then narrows linearly for 4.5 m
			belt.funnel_min_width = 2.0    # to a 2.0 m passage, then straight to the top
			# Marker meta so the post-build pass knows to graft on the metal-detector
			# head at 3/4 along the slope. Read by the caller in build_node().
			belt.set_meta("attach_metaaldetector_head_at_frac", 0.75)
	# #196 — if this belt asked for an integrated metal-detector head (currently
	# only opzetband_1), graft it onto the incline at the requested fraction.
	if not ghost and belt.has_meta("attach_metaaldetector_head_at_frac"):
		_attach_metaaldetector_head_to_opzetband(belt,
			float(belt.get_meta("attach_metaaldetector_head_at_frac")))
	return belt

## #196 — Build a simplified search-coil + reverse-reject head and parent it onto
## the inclined section of a ShredderFeedBelt so the belt passes THROUGH the coil
## tunnel. `frac` ∈ (0,1) selects how far along the slope the head sits (0.75 =
## three-quarters of the way to the top — the operator-specified location). The
## belt itself is the conveyor; the head adds only the coil tunnel, indicator
## cabinet, REJECT placard, and a small side-reject chute that throws ferrous
## off the belt to the local +X side.
static func _attach_metaaldetector_head_to_opzetband(belt: Node, frac: float) -> void:
	# Compute slope-local position of the head along the incline.
	# The belt's inc_pivot is rotated about X by -incline_deg and lives at
	# (0, deck_height, deck_length). Mesh runs along its local +Z for
	# _incline_hyp metres. So a point at fraction `frac` along the slope is at
	# inc_pivot-local (0, 0, frac * _incline_hyp). We parent the head under
	# inc_pivot so its X-tilt matches the slope.
	var inc_pivot : Node3D = belt.get_node_or_null("InclinePivot") as Node3D
	if inc_pivot == null:
		# Fallback: scan children for the rotated pivot. ShredderFeedBelt names it
		# "InclinePivot" by convention, but some forks may differ.
		for c in belt.get_children():
			if c is Node3D and absf(c.rotation.x) > 0.01:
				inc_pivot = c as Node3D
				break
	if inc_pivot == null:
		return
	var slope_hyp : float = float(belt.get("incline_run")) / maxf(cos(deg_to_rad(float(belt.get("incline_deg")))), 0.01)
	var deck_w   : float  = float(belt.get("deck_width"))
	var z_along  : float  = clampf(frac, 0.05, 0.95) * slope_hyp
	# Parent for all head parts; sits ABOVE the belt deck (which is at y≈0 in the
	# pivot's local frame; belt mesh thickness ~0.10).
	var head := Node3D.new()
	head.name = "MetaalDetectorHead"
	inc_pivot.add_child(head)
	head.position = Vector3(0.0, 0.0, z_along)
	# Materials.
	var coil_b := _mat(Color(0.12, 0.14, 0.18), false, 0.35, 0.55)
	var copper := _mat(Color(0.78, 0.42, 0.18), false, 0.65, 0.50)
	var steel  := _mat(_STEEL, false, 0.55, 0.4)
	var dark   := _mat(_DARK, false, 0.4, 0.6)
	var yellow := _mat(_SAFETY, false, 0.2, 0.6)
	var screen := _mat(Color(0.07, 0.10, 0.14), false, 0.1, 0.25)
	# ── Search-coil tunnel: 4 thick coil tubes forming a rectangle the belt runs
	# through. Coil tube radius scales with belt width so the tunnel always
	# clears the slats. ───────────────────────────────────────────────────────
	var coil_r : float = 0.12
	var tunnel_w : float = deck_w + 0.4   # slightly wider than belt for clearance
	var tunnel_h : float = 0.9            # vertical opening above the belt
	var coil_len : float = 0.4            # tube length along the belt
	# Top + bottom rails (along X).
	for sy in [0.0, tunnel_h]:
		_cyl(head, coil_r, coil_r, tunnel_w,
			Vector3(0.0, float(sy), 0.0), coil_b, "x")
	# Left + right rails (along Y).
	for sx in [-tunnel_w * 0.5, tunnel_w * 0.5]:
		_cyl(head, coil_r, coil_r, tunnel_h,
			Vector3(float(sx), tunnel_h * 0.5, 0.0), coil_b, "y")
	# Copper-wrap visual band on the top rail — gives the head its "coil" read.
	_cyl(head, coil_r * 1.05, coil_r * 1.05, tunnel_w * 0.85,
		Vector3(0.0, tunnel_h, 0.0), copper, "x")
	# ── Coil casing box wrapped around the rails — solid frame that pops as the
	# inspection head. ─────────────────────────────────────────────────────
	_box(head, Vector3(tunnel_w + 0.18, 0.18, coil_len),
		Vector3(0.0, tunnel_h + 0.10, 0.0), steel)
	_box(head, Vector3(0.18, tunnel_h + 0.18, coil_len),
		Vector3(-(tunnel_w * 0.5) - 0.10, tunnel_h * 0.5, 0.0), steel)
	_box(head, Vector3(0.18, tunnel_h + 0.18, coil_len),
		Vector3( (tunnel_w * 0.5) + 0.10, tunnel_h * 0.5, 0.0), steel)
	# ── REJECT placard on the +X coil leg, facing the operator side. ──────────
	_box(head, Vector3(0.5, 0.3, 0.04),
		Vector3((tunnel_w * 0.5) + 0.20, tunnel_h * 0.6, 0.0), yellow)
	# ── Indicator cabinet ahead of the coil on +X (HMI face). ─────────────────
	var cab_w : float = 0.5; var cab_h : float = 0.7; var cab_d : float = 0.35
	_box(head, Vector3(cab_w, cab_h, cab_d),
		Vector3((tunnel_w * 0.5) + 0.45, tunnel_h * 0.5, -coil_len * 0.5 - cab_d * 0.5), dark)
	_box(head, Vector3(cab_w * 0.7, cab_h * 0.45, 0.02),
		Vector3((tunnel_w * 0.5) + 0.45, tunnel_h * 0.55, -coil_len * 0.5 - cab_d - 0.011), screen)
	# Two indicator dots (CLEAR / METAL) below the screen.
	var green_mat := _mat(Color(0.20, 0.78, 0.30), false, 0.0, 0.5)
	var red_mat   := _mat(Color(0.82, 0.16, 0.14), false, 0.0, 0.5)
	_box(head, Vector3(0.07, 0.07, 0.03),
		Vector3((tunnel_w * 0.5) + 0.45 - 0.10, tunnel_h * 0.25, -coil_len * 0.5 - cab_d - 0.016), green_mat)
	_box(head, Vector3(0.07, 0.07, 0.03),
		Vector3((tunnel_w * 0.5) + 0.45 + 0.10, tunnel_h * 0.25, -coil_len * 0.5 - cab_d - 0.016), red_mat)
	# ── Side-reject chute: a small angled gutter on +X just past the coil that
	# catches the ferrous reject when the belt reverses momentarily. ──────────
	var chute_l : float = 1.0
	var chute := Node3D.new()
	chute.name = "RejectChute"
	head.add_child(chute)
	chute.position = Vector3((tunnel_w * 0.5) + 0.4, 0.15, coil_len * 0.5 + 0.2)
	chute.rotation.z = deg_to_rad(-25.0)   # tilt toward +X (operator side)
	_box(chute, Vector3(0.6, 0.04, chute_l), Vector3.ZERO, dark)
	for sx in [-0.3, 0.3]:
		_box(chute, Vector3(0.04, 0.18, chute_l),
			Vector3(float(sx), 0.08, 0.0), steel)
	# Small reject bin under the chute end (on the floor).
	# Bin sits in world coords; positioning under the rotated chute is a
	# rough approximation — operator can jog it post-place if it reads wrong.
	# Skipped here to avoid double-anchoring; the chute end + side-reject placard
	# already telegraph the function.


## A placeable CollectionZone (Area3D): film scraps that enter are removed and the
## zone's scrap_count goes up. The visible footprint is a flat translucent slab so
## the operator can see where they're aiming the wind.
static func _build_collection_zone(size: Vector3, ghost: bool) -> Node3D:
	if ghost:
		return _simple_ghost(size)
	var zone : Area3D = load("res://src/sim/CollectionZone.gd").new()
	zone.name = "CollectionZone"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, maxf(size.y, 0.5), size.z)
	cs.shape = box
	cs.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	zone.add_child(cs)
	# Visible floor pad — translucent blue so the boundary reads on the ground.
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(size.x, 0.04, size.z)
	pad.mesh = pm
	pad.position = Vector3(0.0, 0.02, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.60, 0.95, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.9
	pad.material_override = mat
	zone.add_child(pad)
	return zone

## A test "pile" of loose film scraps — drops ~30 FilmScrap rigid bodies in a
## random spread on the floor so the operator can practice blowing them around.
## The pile root has no collider itself; the scraps do.
static func _build_scrap_pile(size: Vector3, ghost: bool) -> Node3D:
	if ghost:
		return _simple_ghost(size)
	var root := Node3D.new()
	root.name = "FilmScrapPile"
	var scrap_scene := load("res://src/sim/FilmScrap.tscn") as PackedScene
	if scrap_scene == null:
		return root
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("scrap_pile") + Time.get_ticks_msec()
	for i in 30:
		var s := scrap_scene.instantiate() as Node3D
		if s == null:
			continue
		var x := rng.randf_range(-size.x * 0.5, size.x * 0.5)
		var z := rng.randf_range(-size.z * 0.5, size.z * 0.5)
		var y := 0.05 + rng.randf_range(0.0, 0.20)
		s.position = Vector3(x, y, z)
		s.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(s)
	return root

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
		var info := {
			"item":       "%s bale" % String(o.get("name", origin)),
			"origin":     origin,
			"weight_kg":  int(round(BaleDefs.estimated_weight(size))),
			"batch":      "B-%04d" % (hash(origin + str(size)) & 0xFFFF),
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
		var label_item_script := preload("res://src/scenes/world/LabelItem.gd")
		label_item_script.attach_to(rb, info, label_pos, label_basis)
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
	var wires := Node3D.new()
	wires.name = "Wires"
	rb.add_child(wires)
	_build_wires(wires, size, ghost, _wire_count_for(origin))
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
## Distance-cull a mesh beyond `dist` metres of the camera, with a 2 m cross-fade
## band so it eases in/out instead of hard-popping. Engine-side (no per-frame
## script).
static func _lod_cull(mi: MeshInstance3D, dist: float) -> void:
	mi.visibility_range_end = dist
	mi.visibility_range_end_margin = 2.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

## LOD bale: a single tinted box + 3 thin dark bands over the top. ~4 meshes vs
## ~34 for the full model. Used to fill bale yards cheaply; upgraded to the full
## model by detail_bale() when grabbed. Keeps the same tint so it reads as the
## right supplier from a distance.
static func _m_bale_simple(p: Node3D, id: String, size: Vector3, color: Color, ghost: bool) -> void:
	var o := BaleDefs.get_origin(id)
	var tint: Color = o.get("tint", color)
	# ── FAR-LOD body ─────────────────────────────────────────────────────────
	# A single tinted box, visible from spawn to LOD_CULL_FAR_M. Past CLOSE_LOD
	# the layered stack below is invisible and only this box renders, so far-
	# away yards stay cheap (1 box per bale).
	# #243 — pull a hint of the dominant slab tint into the far box. The
	# close-LOD slabs use alternating ±jitter around `tint`, so the far box
	# was reading slightly flatter / greyer than the slabs averaged. A
	# saturation nudge (×1.08 around the mid) keeps the bale's supplier
	# colour identifiable from a distance instead of fading to a uniform grey.
	var body_tint := Color(
		clampf(0.5 + (tint.r - 0.5) * 1.08, 0.0, 1.0),
		clampf(0.5 + (tint.g - 0.5) * 1.08, 0.0, 1.0),
		clampf(0.5 + (tint.b - 0.5) * 1.08, 0.0, 1.0),
		1.0)
	var body_mat := _mat(body_tint, ghost, 0.0, 0.9)
	var box := _box(p, Vector3(size.x * 0.98, size.y * 0.98, size.z * 0.98), \
		Vector3(0.0, size.y * 0.5, 0.0), body_mat)
	box.name = "SimpleBody"
	box.set_meta("no_merge", true)
	if not ghost:
		_lod_cull(box, 54.0)

	# ── CLOSE-LOD layered stack (compressed-film slabs) ──────────────────────
	if not ghost:
		var N_LAYERS : int = 5
		var CLOSE_LOD_M : float = 28.0
		var slab_h : float = size.y * 0.965 / float(N_LAYERS)
		var slab_w : float = size.x * 0.985
		var slab_d : float = size.z * 0.985
		# #243 — far-LOD body stays VISIBLE at ALL distances (begin = 0). The
		# close-LOD slabs render OVER it under CLOSE_LOD_M and fade out past it,
		# so there's no longer a "disappears at ~20 m" gap between the slabs
		# fading out and the body box fading in. Z-fighting is avoided because
		# the slabs sit at +0.015 y offset and are 0.985× the body box scale.
		box.visibility_range_begin = 0.0
		box.visibility_range_begin_margin = 0.0
		box.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for li in N_LAYERS:
			# Per-layer tint jitter: alternate slightly darker / lighter so seams
			# read even on a single-colour supplier (e.g. all-white film). The
			# jitter amount is small (±6%) so the bale still reads as one colour.
			var _t_off : float = (float(li) - float(N_LAYERS - 1) * 0.5) / float(N_LAYERS)
			# Two-tone pattern: even layers slightly darker, odd layers slightly
			# lighter — gives clean visible seams without random sparkle.
			var jitter : float = -0.08 if li % 2 == 0 else 0.04
			var slab_tint := Color(
				clampf(tint.r + jitter, 0.0, 1.0),
				clampf(tint.g + jitter, 0.0, 1.0),
				clampf(tint.b + jitter, 0.0, 1.0),
				1.0
			)
			var slab_mat := _mat(slab_tint, ghost, 0.0, 0.92)
			var y : float = slab_h * (float(li) + 0.5) + size.y * 0.015
			var slab := _box(p, Vector3(slab_w, slab_h * 0.94, slab_d), Vector3(0.0, y, 0.0), slab_mat)
			# Engine-side cull: only render the layered detail close up. Past
			# CLOSE_LOD_M the slabs fade out and the single FAR body box takes
			# over, so the per-bale draw-call cost drops back to 1.
			slab.visibility_range_end = CLOSE_LOD_M
			slab.visibility_range_end_margin = 3.0
			slab.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			# Thin dark "seam line" between slabs — a 6 mm strip wrapping the
			# bale at every layer boundary. Drops out at CLOSE_LOD_M too.
			if li > 0:
				var seam_mat := _mat(Color(0.10, 0.10, 0.10), ghost, 0.7, 0.4)
				var seam_y : float = slab_h * float(li) + size.y * 0.015
				var seam := _box(p, Vector3(slab_w * 1.004, 0.006, slab_d * 1.004),
					Vector3(0.0, seam_y, 0.0), seam_mat)
				seam.visibility_range_end = CLOSE_LOD_M
				seam.visibility_range_end_margin = 3.0
				seam.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	# ── WIRES (very-close LOD) ───────────────────────────────────────────────
	# #243 — wire direction now MATCHES the detail-LOD bale's _build_wires:
	# 3 loops in the XY-plane (Top/Bottom run the FULL LENGTH along X, Side
	# caps along Y on the ±X end faces), spaced across Z (the width). The
	# old code laid 3 horizontal bands in the XZ-plane stacked along Y AND
	# 3 stray top-straps running across the width — both visually
	# orthogonal to the detail-LOD wires. Now the simple bale's wires look
	# the same as the detail bale's, just with no knots/sag.
	if not ghost:
		var wire := _mat(Color(0.18, 0.17, 0.16), ghost, 0.85, 0.30)
		var band_r : float = 0.018
		var top_y : float = size.y + band_r * 0.5
		var bot_y : float = -band_r * 0.5
		var end_x : float = size.x * 0.5 + band_r * 0.5
		var horiz_len : float = size.x + band_r * 2.0
		var vert_len  : float = size.y + band_r * 2.0
		for wz in _wire_positions(size, _wire_count_for(id)):
			# Top — runs the full LENGTH (X) over every sheet edge.
			var b_top := _cyl(p, band_r, band_r, horiz_len,
				Vector3(0.0, top_y, wz), wire, "x")
			b_top.name = "SimpleWireTop_%d" % int((wz / size.z) * 100.0)
			_lod_cull(b_top, 24.0)
			# Bottom — runs the full LENGTH (X) under every sheet edge.
			var b_bot := _cyl(p, band_r, band_r, horiz_len,
				Vector3(0.0, bot_y, wz), wire, "x")
			_lod_cull(b_bot, 24.0)
			# Right end cap — along Y on the +X face.
			var b_r := _cyl(p, band_r, band_r, vert_len,
				Vector3(end_x, size.y * 0.5, wz), wire, "y")
			_lod_cull(b_r, 24.0)
			# Left end cap — along Y on the -X face.
			var b_l := _cyl(p, band_r, band_r, vert_len,
				Vector3(-end_x, size.y * 0.5, wz), wire, "y")
			_lod_cull(b_l, 24.0)
		# #243 — film-piece overlays on ALL faces, not just +Z. Operator: small
		# slabs randomly oriented within ±10° of the face plane, varying tints
		# derived from the supplier color. The +Z face has fewer overlays so
		# the paper sticker stays readable; the opposite face (-Z) is also
		# reduced for symmetry; top, bottom, and ±X get the full 12-18 count.
		var overlay_rng := RandomNumberGenerator.new()
		overlay_rng.seed = hash(id + "_overlay_v2")
		# Six faces: +Z (front, sticker face), -Z (back), +X, -X, +Y (top), -Y (bottom).
		# Each entry: face_name, normal, in_plane_axis_a, in_plane_axis_b, count, half_size_a, half_size_b
		var face_specs := [
			{"name":"px", "n":Vector3(1,0,0),  "a":Vector3(0,1,0), "b":Vector3(0,0,1), "count":14,
				"ha":size.y * 0.5, "hb":size.z * 0.5, "skin":size.x * 0.5},
			{"name":"nx", "n":Vector3(-1,0,0), "a":Vector3(0,1,0), "b":Vector3(0,0,1), "count":14,
				"ha":size.y * 0.5, "hb":size.z * 0.5, "skin":size.x * 0.5},
			{"name":"pz", "n":Vector3(0,0,1),  "a":Vector3(1,0,0), "b":Vector3(0,1,0), "count":6,
				"ha":size.x * 0.5, "hb":size.y * 0.5, "skin":size.z * 0.5},
			{"name":"nz", "n":Vector3(0,0,-1), "a":Vector3(1,0,0), "b":Vector3(0,1,0), "count":6,
				"ha":size.x * 0.5, "hb":size.y * 0.5, "skin":size.z * 0.5},
			{"name":"py", "n":Vector3(0,1,0),  "a":Vector3(1,0,0), "b":Vector3(0,0,1), "count":14,
				"ha":size.x * 0.5, "hb":size.z * 0.5, "skin":size.y * 0.5},
			{"name":"ny", "n":Vector3(0,-1,0), "a":Vector3(1,0,0), "b":Vector3(0,0,1), "count":14,
				"ha":size.x * 0.5, "hb":size.z * 0.5, "skin":size.y * 0.5},
		]
		for fs in face_specs:
			var n_count : int = int(fs["count"])
			for _k in n_count:
				# Random in-plane position, 70 % covers the face skin.
				var u : float = overlay_rng.randf_range(-0.7, 0.7) * float(fs["ha"])
				var v : float = overlay_rng.randf_range(-0.7, 0.7) * float(fs["hb"])
				# Face center: half-size along the face normal + lift bale to y∈[0,size.y].
				var face_center : Vector3 = (fs["n"] as Vector3) * float(fs["skin"]) \
					+ Vector3(0.0, size.y * 0.5, 0.0)
				var pos : Vector3 = face_center \
					+ (fs["a"] as Vector3) * u \
					+ (fs["b"] as Vector3) * v \
					+ (fs["n"] as Vector3) * 0.003   # 3 mm proud so it doesn't z-fight
				# Small thin slab: random size 4-12 cm on each in-plane axis,
				# 4 mm thick along the face normal.
				var sx : float = overlay_rng.randf_range(0.04, 0.12)
				var sy : float = overlay_rng.randf_range(0.04, 0.12)
				var thk : float = 0.004
				# Tint variation derived from supplier color (±10 % per channel).
				var ot := Color(
					clampf(tint.r + overlay_rng.randf_range(-0.10, 0.10), 0.0, 1.0),
					clampf(tint.g + overlay_rng.randf_range(-0.10, 0.10), 0.0, 1.0),
					clampf(tint.b + overlay_rng.randf_range(-0.10, 0.10), 0.0, 1.0),
					1.0)
				var omat := _mat(ot, ghost, 0.0, 0.85)
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				# Box size in local (in-plane × thickness) frame. We then orient
				# via a basis built from the face's in-plane axes + normal.
				bm.size = Vector3(sx, sy, thk)
				mi.mesh = bm
				mi.material_override = omat
				# Face basis: x = in-plane a, y = in-plane b, z = face normal.
				var fb := Basis((fs["a"] as Vector3), (fs["b"] as Vector3), (fs["n"] as Vector3))
				# Random twist within ±10° around the face normal.
				var twist : float = overlay_rng.randf_range(-PI / 18.0, PI / 18.0)
				fb = fb * Basis(Vector3(0, 0, 1), twist)
				mi.transform = Transform3D(fb, pos)
				p.add_child(mi)
				_lod_cull(mi, 24.0)
		# #117 — paper sticker quad on the +Z face. Small off-white card so the
		# close-LOD bale reads like one of the labelled ones from the detail tier.
		var sticker_mat := _mat(Color(0.93, 0.90, 0.78), ghost, 0.0, 0.85)
		var sticker := _box(p, Vector3(size.x * 0.18, size.y * 0.12, 0.004),
			Vector3(size.x * 0.18, size.y * 0.62, size.z * 0.5 + 0.005), sticker_mat)
		sticker.name = "CloseLODSticker"
		_lod_cull(sticker, 24.0)

		# Merge all close-LOD static parts (slabs, seams, wires, overlays, sticker)
		# into a single merged mesh instance to collapse ~90 draw calls into 1.
		StaticMerge.merge_static(p)
		var merged_node := p.get_node_or_null("StaticMerged") as GeometryInstance3D
		if merged_node != null:
			_lod_cull(merged_node, 28.0)

## Upgrade a simple (LOD) yard bale to the full sheet/wire model on demand. Called
## when a bale is grabbed, so the cut→film-pile feature works on any bale the
## player actually handles while idle yard bales stay cheap. No-op for bales that
## are already detailed.
##
## #61 yard-multimesh path: a yard bale has NO Model children of its own — its
## visible body is one instance inside a per-yard MultiMesh. detail_bale here
## also hides the multimesh slot (transform → identity-scaled-to-zero) and
## rebuilds the full visual into the body's empty Model node, so a grabbed
## bale becomes a normal full-detail node and the yard's draw call shrinks
## by one instance (effectively the same cost: the buffer slot stays).
static func detail_bale(body: Node3D) -> void:
	if body == null or not body.has_meta("simple_bale"):
		return
	if not bool(body.get_meta("simple_bale")):
		return
	body.set_meta("simple_bale", false)
	# Hide our slot in the yard multimesh, if we're a multimesh-backed bale.
	if body.has_meta("yard_mm_inst") and body.has_meta("yard_mm_idx"):
		var mmi := body.get_meta("yard_mm_inst") as MultiMeshInstance3D
		var idx := int(body.get_meta("yard_mm_idx"))
		if mmi != null and mmi.multimesh != null \
				and idx >= 0 and idx < mmi.multimesh.instance_count:
			# Collapse the instance to a zero-scale transform at the same origin —
			# render-cheap and avoids reallocating the multimesh buffer.
			mmi.multimesh.set_instance_transform(idx, Transform3D(
				Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	var model := body.get_node_or_null("Model")
	if model == null:
		# Yard-multimesh bales spawn without a Model node — create one now so the
		# detailed builder has somewhere to put its meshes.
		model = Node3D.new()
		model.name = "Model"
		body.add_child(model)
	for ch in model.get_children():
		ch.queue_free()
	var id := String(body.get_meta("placeable_id", ""))
	var item := get_item(id)
	if item.is_empty():
		return
	_m_bale(model, id, Vector3(item["size"]), false)

# =============================================================================
# YARD MULTIMESH  (#61)
# =============================================================================
## Build a MultiMeshInstance3D pre-sized to hold every body box for one yard,
## using the supplier's bale-size + tint. Each yard gets ONE of these instead
## of N×13 MeshInstance3Ds — collapses 30k draw calls (one per bale-piece) into
## one per yard.
static func build_yard_multimesh(id: String, instance_count: int) -> MultiMeshInstance3D:
	var item := get_item(id)
	if item.is_empty():
		return null
	var size: Vector3 = item["size"]
	var color: Color = item["color"]
	var o := BaleDefs.get_origin(id)
	var tint: Color = o.get("tint", color)
	var bm := BoxMesh.new()
	# Match the close-LOD body proportions (`_m_bale_simple` uses 0.98).
	bm.size = Vector3(size.x * 0.98, size.y * 0.98, size.z * 0.98)
	# #243 — saturation-boost tint by 1.08 around mid-gray so the far MM
	# picks up the dominant supplier colour instead of reading flat / grey
	# at distance. Matches the saturation lift applied to the close MM and
	# the standalone simple bale body.
	var body_tint := Color(
		clampf(0.5 + (tint.r - 0.5) * 1.08, 0.0, 1.0),
		clampf(0.5 + (tint.g - 0.5) * 1.08, 0.0, 1.0),
		clampf(0.5 + (tint.b - 0.5) * 1.08, 0.0, 1.0),
		1.0)
	var mat := _mat(body_tint, false, 0.0, 0.9)
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	mm.mesh = bm
	mm.instance_count = instance_count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BaleMM"
	mmi.multimesh = mm
	return mmi

# #117 — Close-LOD bale multimesh. Same box footprint as the far MM (so we can
# share transform writes), but its material has a procedural normal map with
# three horizontal wire-shadow grooves baked in — visible only at near range
# thanks to the visibility-range swap MainWorld sets on the two MMs. At
# distance the far MM (flat shaded box) wins; under ~35 m the close MM (groove-
# shaded box) takes over. One extra draw call per yard for the closer detail.
const _BALE_CLOSE_TEX_W : int = 32
const _BALE_CLOSE_TEX_H : int = 128
const _BALE_CLOSE_WIRE_COUNT : int = 3
static var _bale_close_normal_tex : ImageTexture = null

## Generate (once) a normal-map texture with `_BALE_CLOSE_WIRE_COUNT` thin dark
## grooves running horizontally across the bale's face — reads as wire-shadow
## bindings at close range. Shared across every supplier so memory is cheap.
static func _bale_close_normal_texture() -> ImageTexture:
	if _bale_close_normal_tex != null:
		return _bale_close_normal_tex
	var img := Image.create(_BALE_CLOSE_TEX_W, _BALE_CLOSE_TEX_H, false, Image.FORMAT_RGB8)
	var groove_band : int = 3
	for y in _BALE_CLOSE_TEX_H:
		var ny : float = 0.5
		# Wire centres at 25 %, 50 %, 75 % of the texture height.
		for w in _BALE_CLOSE_WIRE_COUNT:
			var centre : int = int(float(_BALE_CLOSE_TEX_H)
				* (float(w + 1) / float(_BALE_CLOSE_WIRE_COUNT + 1)))
			var dy : int = abs(y - centre)
			if dy < groove_band:
				# Sharp dark groove dip: bias the normal Y down slightly (reads
				# as shadow). Falls off across `groove_band` pixels each side.
				var k : float = 1.0 - float(dy) / float(groove_band)
				ny = 0.5 - 0.30 * k
				break
		for x in _BALE_CLOSE_TEX_W:
			img.set_pixel(x, y, Color(0.5, ny, 1.0))
	_bale_close_normal_tex = ImageTexture.create_from_image(img)
	return _bale_close_normal_tex

static func build_yard_multimesh_close(id: String, instance_count: int) -> MultiMeshInstance3D:
	var item := get_item(id)
	if item.is_empty():
		return null
	var size: Vector3 = item["size"]
	var color: Color = item["color"]
	var o := BaleDefs.get_origin(id)
	var tint: Color = o.get("tint", color)
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x * 0.98, size.y * 0.98, size.z * 0.98)
	# #243 — was `tint.darkened(0.06)` which made the close MM look duller
	# than the standalone _m_bale_simple body (operator: "far LOD reads
	# grayscale"). Use the same saturation-boosted body tint as the
	# standalone simple bale so they match perfectly across the LOD swap.
	# Reduced normal_scale so the wire grooves still read but don't bake
	# in a strong specular hit that desaturates the bale's colour at
	# distance.
	var body_tint := Color(
		clampf(0.5 + (tint.r - 0.5) * 1.08, 0.0, 1.0),
		clampf(0.5 + (tint.g - 0.5) * 1.08, 0.0, 1.0),
		clampf(0.5 + (tint.b - 0.5) * 1.08, 0.0, 1.0),
		1.0)
	var mat := _mat(body_tint, false, 0.0, 0.85)
	mat.normal_enabled = true
	mat.normal_texture = _bale_close_normal_texture()
	mat.normal_scale = 0.35
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	mm.mesh = bm
	mm.instance_count = instance_count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BaleMM_Close"
	mmi.multimesh = mm
	return mmi

## #125 — Proximity-loaded sticker MultiMesh per yard. One QuadMesh per bale,
## placed on the bale's +Z face (the side that faces the aisle in our yards),
## shown only within ~12 m of the player so far yards don't pay any sticker
## cost. A single shared off-white sticker texture for all instances (per-bale
## unique batch codes are unreadable at distance anyway; the operator gets the
## real code via the detail-bale promotion when they walk up and grab one).
const _BALE_STICKER_TEX_W : int = 192
const _BALE_STICKER_TEX_H : int = 128

## D2 — Tiny 3×5 bitmap font for A-Z, 0-9 and a few symbols. Each glyph is 5
## packed uint8 rows; bit 2 = leftmost column, bit 0 = rightmost. Drawn into
## the bale sticker so the operator sees actual letterforms instead of the
## dashed-pixel placeholders that read as "MMM" from any distance.
const _STICKER_FONT_3x5 : Dictionary = {
	"A":[0b010,0b101,0b111,0b101,0b101], "B":[0b110,0b101,0b110,0b101,0b110],
	"C":[0b011,0b100,0b100,0b100,0b011], "D":[0b110,0b101,0b101,0b101,0b110],
	"E":[0b111,0b100,0b110,0b100,0b111], "F":[0b111,0b100,0b110,0b100,0b100],
	"G":[0b011,0b100,0b101,0b101,0b011], "H":[0b101,0b101,0b111,0b101,0b101],
	"I":[0b111,0b010,0b010,0b010,0b111], "J":[0b001,0b001,0b001,0b101,0b010],
	"K":[0b101,0b110,0b100,0b110,0b101], "L":[0b100,0b100,0b100,0b100,0b111],
	# M needs the classic peak silhouette with a visible DIP in the middle row,
	# otherwise it's indistinguishable from N at 3×5 (both used to read [101,
	# 111, 111, 101, 101] / [101, 111, 111, 111, 101] — single-row diff, so
	# "ROTTERDAM" rendered as "ROTTERDAN" on the sticker). Restored the M peak.
	"M":[0b101,0b111,0b101,0b101,0b101], "N":[0b101,0b111,0b111,0b111,0b101],
	"O":[0b010,0b101,0b101,0b101,0b010], "P":[0b110,0b101,0b110,0b100,0b100],
	"Q":[0b010,0b101,0b101,0b110,0b011], "R":[0b110,0b101,0b110,0b101,0b101],
	"S":[0b011,0b100,0b010,0b001,0b110], "T":[0b111,0b010,0b010,0b010,0b010],
	"U":[0b101,0b101,0b101,0b101,0b011], "V":[0b101,0b101,0b101,0b010,0b010],
	"W":[0b101,0b101,0b111,0b111,0b101], "X":[0b101,0b101,0b010,0b101,0b101],
	"Y":[0b101,0b101,0b010,0b010,0b010], "Z":[0b111,0b001,0b010,0b100,0b111],
	"0":[0b010,0b101,0b101,0b101,0b010], "1":[0b010,0b110,0b010,0b010,0b111],
	"2":[0b110,0b001,0b010,0b100,0b111], "3":[0b110,0b001,0b010,0b001,0b110],
	"4":[0b101,0b101,0b111,0b001,0b001], "5":[0b111,0b100,0b110,0b001,0b110],
	"6":[0b011,0b100,0b110,0b101,0b010], "7":[0b111,0b001,0b010,0b010,0b010],
	"8":[0b010,0b101,0b010,0b101,0b010], "9":[0b010,0b101,0b011,0b001,0b110],
	"-":[0b000,0b000,0b111,0b000,0b000], ".":[0b000,0b000,0b000,0b000,0b010],
	" ":[0b000,0b000,0b000,0b000,0b000], "/":[0b001,0b001,0b010,0b100,0b100],
}

## Draw `text` into `img` at top-left (x0, y0), scaled by `scale` (1 = native
## 3px×5px, 2 = 6×10, etc.) using `ink` colour. Characters outside the font
## render as a blank space. Used by _bale_sticker_texture; safe to call with
## any string length — caller is responsible for sizing the texture wide enough.
static func _draw_text_into_image(img: Image, x0: int, y0: int, text: String, scale: int, ink: Color) -> void:
	var cx : int = x0
	for ci in text.length():
		var ch : String = text[ci].to_upper()
		var glyph : Array = _STICKER_FONT_3x5.get(ch, [0,0,0,0,0])
		for row in 5:
			var bits : int = int(glyph[row])
			for col in 3:
				if (bits >> (2 - col)) & 1 == 1:
					for dy in scale:
						for dx in scale:
							var px : int = cx + col * scale + dx
							var py : int = y0 + row * scale + dy
							if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
								img.set_pixel(px, py, ink)
		cx += 4 * scale       # 3px char + 1px gap
static var _bale_sticker_tex_by_id : Dictionary = {}

static func _bale_sticker_texture(id: String = "rotterdam") -> ImageTexture:
	if _bale_sticker_tex_by_id.has(id):
		return _bale_sticker_tex_by_id[id]
	# #labelyard — sticker text is now per-SUPPLIER (pulled from BaleDefs) instead
	# of the old hardcoded "ROTTERDAM / ID B-00482 / 250 KG NETTO" baked into one
	# shared texture. That global bake made every yard (Alba Marl, Zwolle, Forst+)
	# read the Rotterdam sticker — and 250 kg was wrong even for Rotterdam. We
	# still bake ONE texture per supplier (not per bale — the MultiMesh shares it);
	# true per-instance ids would need a per-instance UV atlas.
	var o := BaleDefs.get_origin(id)
	var supplier_name : String = String(o.get("name", id)).to_upper()
	var sz : Vector3 = o.get("size", Vector3(1.45, 1.25, 1.25))
	var net_kg : int = int(round(BaleDefs.estimated_weight(sz)))
	var img := Image.create(_BALE_STICKER_TEX_W, _BALE_STICKER_TEX_H, false, Image.FORMAT_RGB8)
	# #170 — yellow shipping label, matching the LabelItem sticker colour the
	# operator confirmed earlier.
	var paper := Color(0.93, 0.82, 0.15)
	var ink   := Color(0.10, 0.10, 0.10)
	img.fill(paper)
	# Header band: dark strip with white-on-black supplier name, reads as a
	# shipping label even at 20 m camera distance.
	for y in range(4, 22):
		for x in range(_BALE_STICKER_TEX_W):
			img.set_pixel(x, y, ink)
	# D2 — REAL letterforms instead of dashed-pixel placeholders. Default to
	# generic copy ("ROTTERDAM" supplier, batch id, mass, grade) — every bale
	# in the MultiMesh shares one bake, so this stands in for "a sticker that
	# reads as text" rather than per-bale unique IDs. Per-bale uniqueness is
	# its own task (would need a per-instance UV offset into a sprite atlas).
	# #203 — operator: scale-2 text overflowed the sticker bounds AND the
	# dimensions/grade line ("LDPE FILM PE") doesn't belong on a shipping
	# label. Dropped that line; scale 1 (native 3×5 glyphs, 4px char-cell)
	# leaves the longest line ("250 KG NETTO" = 48 px) well inside the 192 px
	# texture width with plenty of horizontal margin.
	_draw_text_into_image(img, 10,  8, supplier_name,                    1, paper)   # white on header strip
	_draw_text_into_image(img,  8, 30, "ID B-%05d" % (hash(id) % 100000), 1, ink)
	_draw_text_into_image(img,  8, 50, "%d KG NETTO" % net_kg,           1, ink)
	# Barcode band at the bottom — alternating black bars of varying width.
	var bx : int = 8
	while bx < _BALE_STICKER_TEX_W - 8:
		var w : int = 1 + (bx * 7919) % 4
		for x in range(bx, mini(bx + w, _BALE_STICKER_TEX_W - 8)):
			for y in range(95, 120):
				img.set_pixel(x, y, ink)
		bx += w + 1 + (bx * 3) % 3
	var tex := ImageTexture.create_from_image(img)
	_bale_sticker_tex_by_id[id] = tex
	return tex

static func build_yard_sticker_multimesh(id: String, instance_count: int) -> MultiMeshInstance3D:
	var item := get_item(id)
	if item.is_empty():
		return null
	var size: Vector3 = item["size"]
	# Sticker is ~10 cm wide × 7 cm tall — same proportion the detail bale uses.
	var qm := QuadMesh.new()
	qm.size = Vector2(min(size.x, size.z) * 0.30, size.y * 0.30)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.albedo_texture = _bale_sticker_texture(id)
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED       # readable from either side
	qm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	mm.mesh = qm
	mm.instance_count = instance_count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BaleStickerMM"
	mmi.multimesh = mm
	return mmi

## Spawn the COLLIDER-ONLY RigidBody3D for a single yard bale and bind it to
## its slot in the shared MultiMesh. The body has no visual children — its
## look comes from the multimesh; only when the player grabs it does
## detail_bale() promote it to a full-detail node.
static func build_yard_bale_mm(id: String, mmi: MultiMeshInstance3D, idx: int) -> Node3D:
	var item := get_item(id)
	if item.is_empty():
		return null
	var size: Vector3 = item["size"]
	var rb := RigidBody3D.new()
	rb.freeze = true
	rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rb.gravity_scale = 1.0
	rb.can_sleep = true
	rb.sleeping = true
	rb.contact_monitor = false
	rb.mass = maxf(BaleDefs.estimated_weight(size), 1.0)
	rb.linear_damp = 0.4
	rb.angular_damp = 1.2
	rb.name = String(item["name"])
	rb.set_meta("placeable_id", id)
	rb.set_meta("simple_bale", true)
	rb.set_meta("yard_mm_inst", mmi)
	rb.set_meta("yard_mm_idx", idx)
	# Same meta the regular Bales-path in build_node() sets — the rest of the
	# game (BaleClamp, BarcodeScanner, wire cutter, feeder workers) reads these
	# off every bale, so the MM-yard bales need them too or they look "unscanned"
	# or "wire-cut" by accident.
	rb.set_meta("material_origin", id)
	rb.set_meta("wires_cut", false)
	rb.set_meta("wire_compliance", 0.55)
	rb.set_meta("scanned", false)
	rb.set_meta("sheet_count", _sheet_count_for(size))
	rb.set_meta("clamp_force_needed", 0.30)
	# Physics material — high friction so stacks grip + tiny bounce so dropped
	# bales settle softly. Same values as build_node() Bales path.
	var pm := PhysicsMaterial.new()
	pm.friction = 0.85
	pm.bounce   = 0.05
	rb.physics_material_override = pm
	# Collision — same shape as in build_node()'s Bales path (slight X/Z give).
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x * 0.9, size.y, size.z * 0.9)
	col.shape = shape
	col.position = Vector3(0.0, size.y * 0.5, 0.0)
	rb.add_child(col)
	rb.add_to_group("placed_object")
	# `bale` group — feeders, scanners, LineFlow, vehicle grab all look it up here.
	rb.add_to_group("bale")
	return rb

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
	var patch_blue := _mat(Color(0.30, 0.45, 0.85), ghost, 0.0, 0.85)
	var patch_warm := _mat(Color(tint.r * 0.8, tint.g * 0.8, tint.b * 0.72), ghost, 0.0, 0.9)
	var x := -inner_len * 0.5
	for i in thicks.size():
		var t: float = thicks[i]
		# Sample a sheet colour from the full-spectrum palette (green dominates,
		# dark+black are rare and pull quality down). Net stack reads greenish-grey.
		var col := _sample_sheet_color(rng)
		# LAG OPTIMISATION (operator suggestion): force every OTHER sheet fully
		# opaque. Transparent (alpha-blend) materials are the expensive part of a
		# stacked bale — they force back-to-front sorting and heavy overdraw. The
		# inner sheets are hidden behind the outer ones anyway, so making every
		# second one opaque roughly halves the transparent overdraw with almost
		# no visible difference.
		if i % 2 == 1:
			col.a = 1.0
		# Transparent films use the alpha-blend material path so the colours
		# layer realistically when stacked.
		var sheet_mat := _mat(col, ghost, 0.0, 0.85)
		if col.a < 0.99 and not ghost:
			sheet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var sheet := _box(sheets_root, Vector3(t * 0.95, size.y * 0.98, size.z * 0.98), \
			Vector3(x + t * 0.5, size.y * 0.5, 0.0), sheet_mat)
		sheet.name = "Sheet_%02d" % i
		# Distance-cull sheets: translucent ones drop at 15 m, the opaque ones at
		# 28 m — so a full bale fully vanishes beyond 28 m (far yards cost nothing)
		# while still reading as a solid block in the mid range.
		if not ghost:
			_lod_cull(sheet, 15.0 if col.a < 0.99 else 28.0)
		# Roughly every 3rd sheet picks up a face patch (recycled = never uniform).
		# #243 — patches now spawn on ALL faces, not just +Z. The patch face is
		# chosen by `i % 6` so each sheet contributes to a different face, and
		# the +Z face (which gets the paper label) is skipped on the sheets
		# whose stack-x position would put a patch right on the label. The
		# patch's normal becomes the face normal, with a 4 mm proud-of-skin
		# offset to avoid z-fighting the sheet body.
		if not ghost and (i % 3) == 1:
			var use_blue := rng.randf() < blue
			var pm := patch_blue if use_blue else patch_warm
			var face_pick : int = i % 6
			var patch_y : float = size.y * (0.25 + rng.randf() * 0.55)
			var patch_size : Vector3
			var patch_pos : Vector3
			match face_pick:
				0:   # +Z front — keep as before
					patch_size = Vector3(t * 0.7, size.y * 0.12, 0.008)
					patch_pos  = Vector3(x + t * 0.5, patch_y, size.z * 0.495)
				1:   # -Z back
					patch_size = Vector3(t * 0.7, size.y * 0.12, 0.008)
					patch_pos  = Vector3(x + t * 0.5, patch_y, -size.z * 0.495)
				2:   # +Y top — patch in XZ plane, thin in Y
					patch_size = Vector3(t * 0.7, 0.008, size.z * 0.18)
					patch_pos  = Vector3(x + t * 0.5, size.y * 0.985, \
						(rng.randf() - 0.5) * size.z * 0.7)
				3:   # -Y bottom — patch in XZ plane, thin in Y
					patch_size = Vector3(t * 0.7, 0.008, size.z * 0.18)
					patch_pos  = Vector3(x + t * 0.5, size.y * 0.015, \
						(rng.randf() - 0.5) * size.z * 0.7)
				4:   # +X end — patch in YZ plane, thin in X (only on the
					 # first/last sheets does this hit the actual bale skin;
					 # for inner sheets it sits inside but is hidden by the
					 # opaque outer sheets, so cost is wasted there. Keep it
					 # for the i % 6 cadence simplicity)
					patch_size = Vector3(0.008, size.y * 0.12, size.z * 0.18)
					patch_pos  = Vector3(x + t * 0.495, patch_y, \
						(rng.randf() - 0.5) * size.z * 0.7)
				_:   # -X end
					patch_size = Vector3(0.008, size.y * 0.12, size.z * 0.18)
					patch_pos  = Vector3(x - t * 0.005 + t * 0.5, patch_y, \
						(rng.randf() - 0.5) * size.z * 0.7)
			_box(sheets_root, patch_size, patch_pos, pm)
		x += t

	# ── Three iron wires wrapping in the YZ plane, evenly spaced along X ─────
	var wires_root := Node3D.new()
	wires_root.name = "Wires"
	p.add_child(wires_root)
	_build_wires(wires_root, size, ghost, _wire_count_for(id))
	# Distance-cull the metal wires beyond 15 m of the camera (engine-side, faded).
	if not ghost:
		for w in wires_root.find_children("*", "MeshInstance3D", true, false):
			_lod_cull(w as MeshInstance3D, 15.0)

	# LAG: a bale is built from ~10 sheets + ~24 wire segments. Having every one
	# of those tiny meshes cast a real-time shadow is a huge GPU cost for ~zero
	# visual gain (they're inside the bale). Turn shadow CASTING off for all of
	# a bale's sub-meshes — the bale still RECEIVES shadows from the building.
	if not ghost:
		for node in p.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# (Removed: dark "strapping bands" that ran across the bale's full height.
	#  They were leaving two inseparable vertical black sheets behind whenever a
	#  cut bale opened — bug #95. The 3 iron wires already serve as visible
	#  strapping, so removing these bands is a clean fix.)

## Builds 3 iron wires (Wire_0/1/2), each a full loop around the bale's length+height
## (Top/Bottom run the full length over every sheet edge; Left/Right cap the ±X ends),
## spaced across the width (Z) so all three bind the whole sheet stack.
## Each wire is 4 darkened steel cylinders (top, right, bottom, left) plus 4
## small corner knots that overlap the segment ends so the wire reads as one
## continuous loop instead of disconnected sticks. Parented under a Node3D
## named "Wire_i" so the cutter can `queue_free` an entire wire, and the
## clamp-force bulge can lift the top segment alone.
## Number of binding wires for a supplier's bales. Rotterdam + Fostplus ship
## 3-wire bales; Alba and Zwolle ship 5-wire bales (tighter-bound, more straps).
## Anything else defaults to 3.
static func _wire_count_for(id: String) -> int:
	match id:
		"alba_marl", "zwolle":
			return 5
		_:
			return 3

## Evenly-spaced wire-band Z positions for `count` wires across the bale width.
## 3 wires keep the historical ±0.30·width spread; 5 wires use ±0.36·width so
## they don't crowd. Single-wire degenerate case sits on the centreline.
static func _wire_positions(size: Vector3, count: int) -> Array[float]:
	var out : Array[float] = []
	if count <= 1:
		out.append(0.0)
		return out
	var span : float = 0.30 if count <= 3 else 0.36
	for i in count:
		var f : float = float(i) / float(count - 1)   # 0 .. 1
		out.append((-span + f * (2.0 * span)) * size.z)
	return out

static func _build_wires(root: Node3D, size: Vector3, ghost: bool, count: int = 3) -> void:
	var wire := _mat(Color(0.18, 0.17, 0.16), ghost, 0.85, 0.30)
	# Thicker than the original 1.2 cm so the loops are clearly visible — real
	# bale-binding wire is ~3-4 mm but visually it needs to read at 5+ metres.
	var r := 0.018
	# `count` wires spaced across the WIDTH (Z). Each is a full loop around the
	# bale's length+height: Top and Bottom run the FULL LENGTH (X), crossing EVERY
	# sheet's edge; Left and Right cap the two end faces (±X). So each wire binds
	# the whole stack — cutting it releases all the sheets, not just one edge.
	# (Was: a loop around a single YZ slice, which only wrapped one sheet's worth.)
	var positions: Array[float] = _wire_positions(size, count)
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

# ── rafter: SUBMERGED mesh-cylinder sieve in a water tank on a raised stand ──
## Header fixed 2026-07-06 (the "inclined vibrating sieve deck (zeefdek)" text
## was stale — QA:Q4 flags it explicitly).
## #87 core kept: horizontal ENCAPSULATED SCREW inside a 1.5 mm steel-mesh
## cylinder, semi-transparent so the rotating auger is visible.
## Refinement 2026-07-06 (eop_rafter.md Part B + operator ruling B7):
##  • Mesh cylinder ~0.75 m ⌀, encapsulated in a water tank ~1 m wide × 1 m
##    high; everything below the tank is PLATFORM (ruling B7).
##  • The tank has its OWN water level. (CORRECTION 2026-07-17: an earlier pass
##    wrongly claimed the rafter and flotation tank were "connected vessels" at a
##    shared 4.0 m surface — the operator confirmed that is not a thing. They are
##    separate tanks; nothing ties their levels.)
##  • Reliability: the operator NEVER saw the rafter malfunction (interview /
##    QA:Q4) — exclude it from random-breakdown pools / lowest failure tier
##    when a per-machine failure system lands (no such hook exists yet).
## Material path: doseerschroef M11a → +Z inlet hopper → auger through the
## submerged mesh → -Z discharge chute → ontwaterschroef van rafter.
static func _m_rafter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel  := _mat(color, ghost, 0.5, 0.45)
	var dark   := _mat(_DARK, ghost, 0.5, 0.6)
	var bronze := _mat(Color(0.50, 0.40, 0.22), ghost, 0.4, 0.6)   # rusted-bronze auger
	# Translucent water — same material look as the other tanks (this tank has its
	# OWN level; not tied to the flotation tank).
	var water := _mat(Color(0.20, 0.45, 0.60, 0.55), ghost, 0.0, 0.1)
	# Steel-mesh cylinder material: pale grey, semi-transparent, slight wire-pattern
	# look via lower roughness — reads as fine perforated metal screen.
	var mesh_mat : StandardMaterial3D = StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.62, 0.64, 0.68, 0.55)
	mesh_mat.metallic = 0.6
	mesh_mat.roughness = 0.35
	if not ghost:
		mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # see the auger from outside
	else:
		mesh_mat.albedo_color = Color(0.62, 0.64, 0.68, 0.30)
		mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# ── Height ladder (world metres). Operator 2026-07-17: top was 1.2 m too high
	# (3.1 → 1.9). The rafter's water level is its OWN tank — it is NOT a connected
	# vessel with the flotation tank (that earlier claim was wrong; operator-
	# corrected 2026-07-17). "plat_top" = height of the support platform, nothing
	# more. Tank rim/surface follow from this tank's own geometry.
	var plat_top : float = 1.9            # support-platform top height
	var tank_h   : float = 1.0            # tank ~1 m high
	var tank_w   : float = 1.0            # tank ~1 m wide
	var rim_y    : float = plat_top + tank_h        # this tank's own rim
	var surf_y   : float = rim_y - 0.10             # this tank's own water surface
	var _hx : float = size.x * 0.5
	var hz : float = size.z * 0.5

	# ── RAISED STAND — _m_flotation pattern (4 heavy posts + braces + ring).
	var leg_w : float = 0.18
	var hx_l : float = size.x * 0.40
	var hz_l : float = size.z * 0.45
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(leg_w, plat_top, leg_w),
				Vector3(float(sx) * hx_l, plat_top * 0.5, float(sz) * hz_l), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", plat_top)
	for sz3 in [-1.0, 1.0]:
		_box(p, Vector3(hx_l * 2.0, 0.06, 0.06), Vector3(0.0, plat_top * 0.35, float(sz3) * hz_l), dark)
		_box(p, Vector3(hx_l * 2.0, 0.06, 0.06), Vector3(0.0, plat_top * 0.70, float(sz3) * hz_l), dark)
	for sx3 in [-1.0, 1.0]:
		_box(p, Vector3(0.06, 0.06, hz_l * 2.0), Vector3(float(sx3) * hx_l, plat_top * 0.35, 0.0), dark)
		_box(p, Vector3(0.06, 0.06, hz_l * 2.0), Vector3(float(sx3) * hx_l, plat_top * 0.70, 0.0), dark)
	# Platform plate at the stand top (tank bottom).
	_box(p, Vector3(size.x * 0.9, 0.10, size.z * 0.98), Vector3(0.0, plat_top - 0.05, 0.0), steel)

	# ── WATER TANK (open top) enclosing the mesh cylinder — ruling B7 dims.
	var tank_l : float = size.z * 0.96
	var twt : float = 0.05
	_box(p, Vector3(twt, tank_h, tank_l), Vector3(-tank_w * 0.5 + twt * 0.5, plat_top + tank_h * 0.5, 0.0), steel)
	_box(p, Vector3(twt, tank_h, tank_l), Vector3( tank_w * 0.5 - twt * 0.5, plat_top + tank_h * 0.5, 0.0), steel)
	_box(p, Vector3(tank_w, tank_h, twt), Vector3(0.0, plat_top + tank_h * 0.5, -tank_l * 0.5 + twt * 0.5), steel)
	_box(p, Vector3(tank_w, tank_h, twt), Vector3(0.0, plat_top + tank_h * 0.5,  tank_l * 0.5 - twt * 0.5), steel)
	# Water surface at 4.0 m — ABOVE the mesh-cylinder top so the cylinder is
	# fully submerged (interview "SUBMERGED"); alpha ≈ 0.55 keeps the auger
	# readable through water + mesh (#87 design intent preserved).
	_box(p, Vector3(tank_w - twt * 2.0, 0.04, tank_l - twt * 2.0),
		Vector3(0.0, surf_y, 0.0), water)

	# ── 1.5 mm STEEL-MESH CYLINDER, ~0.75 m ⌀ (ruling B7), axis LEVEL along Z.
	# The old ~5° head-down tilt is dropped: a tilted cylinder would break the
	# submerged read inside the 1 m tank (top would pierce the water surface).
	var cyl_r : float = 0.375                      # ~0.75 m diameter, ruling B7
	var cyl_l : float = size.z * 0.86
	var cyl_y : float = plat_top + 0.45            # top at 3.925 < water 4.0 → submerged
	var cyl_pivot := Node3D.new()
	cyl_pivot.position = Vector3(0.0, cyl_y, 0.0)
	p.add_child(cyl_pivot)
	# Mesh cylinder shell (along Z axis).
	_cyl(cyl_pivot, cyl_r, cyl_r, cyl_l, Vector3.ZERO, mesh_mat, "z")
	# End caps — solid steel rings, not perforated.
	_cyl(cyl_pivot, cyl_r * 1.05, cyl_r * 1.05, 0.06, Vector3(0.0, 0.0,  cyl_l * 0.5 + 0.03), steel, "z")
	_cyl(cyl_pivot, cyl_r * 1.05, cyl_r * 1.05, 0.06, Vector3(0.0, 0.0, -cyl_l * 0.5 - 0.03), steel, "z")
	# Three reinforcing bands around the mesh (visual stiffeners / weld lines).
	for rk in [-0.35, 0.0, 0.35]:
		_cyl(cyl_pivot, cyl_r * 1.04, cyl_r * 1.04, 0.04, Vector3(0.0, 0.0, cyl_l * float(rk)), steel, "z")

	# ── ROTATING AUGER inside the mesh — unchanged from #87 (QA:Q4 confirms the
	# auger + mesh cylinder match reality). comp "rafter_auger", 35 rpm.
	_spinning_auger(cyl_pivot, cyl_l * 0.96, Vector3.ZERO,
		cyl_r * 0.25, cyl_r * 0.78, dark, bronze, ghost, 35.0, "rafter_auger")

	# ── INLET HOPPER above the tank rim at the +Z end (feed from doseerschroef
	# M11a drops straight down through the water surface into the cylinder).
	_cyl(p, cyl_r * 0.60, cyl_r * 0.22, 0.45, Vector3(0.0, rim_y + 0.22, cyl_l * 0.4), steel)
	_box(p, Vector3(cyl_r * 1.2, 0.04, cyl_r * 1.2), Vector3(0.0, rim_y + 0.47, cyl_l * 0.4), steel)

	# ── DRIVE MOTOR + GEARBOX at the +Z end, outside the tank end wall, at
	# auger-shaft height.
	_motor_unit(p, 0.17, 0.25, Vector3(0.0, cyl_y, tank_l * 0.5 + 0.18), "z", ghost)

	# ── DISCHARGE CHUTE at the -Z end: dewatered flake exits over/through the
	# -Z tank end down a 35° chute toward the ontwaterschroef van rafter.
	var chute_w : float = cyl_r * 1.6
	var chute_l : float = size.z * 0.30
	var chute_y : float = plat_top - 0.10
	var chute_z : float = -hz * 1.02
	var chute := _box(p, Vector3(chute_w, 0.06, chute_l), Vector3(0.0, chute_y, chute_z), steel)
	chute.rotation = Vector3(deg_to_rad(-35.0), 0.0, 0.0)
	for sxr in [-1.0, 1.0]:
		var rail := _box(p, Vector3(0.04, 0.22, chute_l),
			Vector3(float(sxr) * chute_w * 0.5, chute_y + 0.09, chute_z), steel)
		rail.rotation = Vector3(deg_to_rad(-35.0), 0.0, 0.0)
	# Outlet lip at the bottom of the chute (the actual material drop point).
	_box(p, Vector3(chute_w * 0.95, 0.05, 0.10),
		Vector3(0.0, chute_y - chute_l * 0.30, chute_z - chute_l * 0.45), dark)

	# ── #231 MAINTENANCE WALKWAY + STAIRCASE on the -X (outtake) side, at the
	# rafter's bottom level. Operator 2026-07-15: "same as the 3C/6 mill" — a
	# grated bordes + yellow railing + a grating stair, lining up with the rafter
	# bottom, stair toward the +Z (material inlet) end. Mirrors the _m_mill
	# deck/_railing/_stair pattern using the shared helpers.
	var grating := _mat(Color(0.36, 0.40, 0.38), ghost, 0.3, 0.85)
	var yellow  := _mat(_SAFETY, ghost, 0.2, 0.6)
	var wk_hx : float = 0.50                                   # walkway half-width (X)
	var wk_hz : float = hz * 0.94                              # runs the tank length (Z)
	var wk_cx : float = -(tank_w * 0.5 + 0.12 + wk_hx)         # just outside the -X tank wall
	# Four support legs from the floor to the deck (auto-extend with the machine).
	for wsx in [-1.0, 1.0]:
		for wsz in [-1.0, 1.0]:
			var wlg := _box(p, Vector3(0.12, plat_top, 0.12),
				Vector3(wk_cx + float(wsx) * (wk_hx - 0.10), plat_top * 0.5, float(wsz) * (wk_hz - 0.15)), dark)
			wlg.add_to_group("machine_leg")
			wlg.set_meta("leg_h", plat_top)
	# Perimeter beams under the deck edge + grated deck at the rafter-bottom level.
	_box(p, Vector3(wk_hx * 2.0, 0.08, 0.08), Vector3(wk_cx, plat_top - 0.10,  wk_hz), dark)
	_box(p, Vector3(wk_hx * 2.0, 0.08, 0.08), Vector3(wk_cx, plat_top - 0.10, -wk_hz), dark)
	_box(p, Vector3(0.08, 0.08, wk_hz * 2.0), Vector3(wk_cx - wk_hx, plat_top - 0.10, 0.0), dark)
	_box(p, Vector3(0.08, 0.08, wk_hz * 2.0), Vector3(wk_cx + wk_hx, plat_top - 0.10, 0.0), dark)
	_box(p, Vector3(wk_hx * 2.0, 0.05, wk_hz * 2.0), Vector3(wk_cx, plat_top, 0.0), grating)
	# Yellow guardrail — open on +X (toward the rafter, for servicing access).
	var wk_rail := Node3D.new()
	wk_rail.position = Vector3(wk_cx, plat_top + 0.03, 0.0)
	p.add_child(wk_rail)
	_railing(wk_rail, wk_hx, wk_hz, 0.0, yellow, ["+x", "+z"])   # open +x (tank) + +z (stair landing)
	# Grating staircase off the +Z (inlet) END, descending AWAY from the machine in
	# +Z (operator 2026-07-15: stair "at the end, going down" — not running back
	# alongside the tank). Rotated 180° so the flight lands on the deck's +Z edge.
	var st_run : float = float(maxi(int(plat_top / 0.22), 4)) * 0.27
	var st_pivot := Node3D.new()
	st_pivot.position = Vector3(wk_cx, 0.0, wk_hz + st_run)
	st_pivot.rotation.y = PI
	p.add_child(st_pivot)
	_stair(st_pivot, Vector3.ZERO, plat_top, 0.9, grating, yellow)

# #91 ── TRILZEEF (vibrating sieve / shaker screen) ────────────────────────────
# Steep navy-painted sloped deck with vertical side barriers. Material enters
# at the high (+Z, top) end through a rubber flap from a belt above, vibrates
# down across the perforated deck — small fines drop through 10×20 cm holes
# (~1 cm bars between) into a collection trough below, oversize slides off the
# low (-Z) end into an open-top discharge chute. Coil-spring base + eccentric
# drive motor (the source of the vibration), DANGER placard, floor-snap legs.
# Operator access platform mounted off the +X side of the upper section.
static func _m_trilzeef(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var navy    := _mat(color, ghost, 0.3, 0.55)                              # painted navy steel
	var bar_mat := _mat(Color(0.45, 0.46, 0.48), ghost, 0.55, 0.45)           # grating bar / rib steel
	var deck_dk := _mat(Color(0.07, 0.07, 0.09), ghost, 0.4, 0.65)            # near-black base behind the holes
	var dark    := _mat(_DARK, ghost, 0.5, 0.6)                               # frame, legs
	var steel   := _mat(_STEEL, ghost, 0.55, 0.4)                             # springs, motor cradle
	var yellow  := _mat(_SAFETY, ghost, 0.2, 0.6)                             # safety bollard + DANGER
	var rubber  := _mat(Color(0.10, 0.10, 0.12), ghost, 0.85, 0.30)           # rubber inlet flap
	var white   := _mat(Color(0.94, 0.94, 0.92), ghost, 0.1, 0.7)             # DANGER plate base
	var red     := _mat(Color(0.82, 0.16, 0.14), ghost, 0.2, 0.6)             # DANGER ribbon

	# ── Frame + spring base — the WHOLE sieve mounts on coil springs so it
	# vibrates as a rigid body. Build the spring cradle at the floor; everything
	# else hangs off a "vibrating" pivot above. (Static at runtime — the
	# vibration is implied by the visible springs + eccentric motor.) ──
	var base_h : float = size.y * 0.18
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# Floor-snap leg under each corner spring.
			var lg := _box(p, Vector3(0.12, base_h * 0.4, 0.12),
				Vector3(sx * size.x * 0.42, base_h * 0.2, sz * size.z * 0.42), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", base_h * 0.4)
			# Coil spring above the leg (visualized as a stack of 4 thin rings).
			var sp_y_base : float = base_h * 0.4 + 0.03
			for k in 4:
				_cyl(p, 0.10, 0.10, 0.025,
					Vector3(sx * size.x * 0.42, sp_y_base + float(k) * 0.04, sz * size.z * 0.42),
					steel, "y")
			# Spring top cap.
			_box(p, Vector3(0.18, 0.03, 0.18),
				Vector3(sx * size.x * 0.42, base_h * 0.4 + 0.20, sz * size.z * 0.42), steel)

	# ── Tilted deck assembly (the moving body) ──
	# Slope: ~22° head-down toward -Z so material flows from the +Z inlet to the
	# -Z discharge. The whole assembly tilts as one rigid body about X, and the
	# eccentric motor visibly DRIVES the deck via VibratingPivot.gd: 4 cm peak
	# (8 cm peak-to-peak) vertical wobble at 8 Hz, matching the operator's
	# spec for a real trilzeef. Ghost previews use a static Node3D so the
	# placement ghost doesn't dance under the cursor.
	var deck_w : float = size.x * 0.86
	var deck_l : float = size.z * 0.92
	var deck_y : float = base_h + size.y * 0.30
	var deck_pivot : Node3D
	if ghost:
		deck_pivot = Node3D.new()
	else:
		deck_pivot = load("res://src/sim/VibratingPivot.gd").new()
		# Operator spec: 8 cm displacement = 4 cm zero-to-peak amplitude.
		deck_pivot.set("amplitude_m", 0.04)
		deck_pivot.set("frequency_hz", 8.0)
	deck_pivot.name = "DeckPivot"
	deck_pivot.position = Vector3(0.0, deck_y, 0.0)
	deck_pivot.rotation = Vector3(deg_to_rad(-22.0), 0.0, 0.0)
	p.add_child(deck_pivot)

	# 1) Dark base plate behind the holes — anything that "falls through" is
	# absorbed into this dark surface visually. Thin so the player reads the
	# bar grid as the structural deck.
	_box(deck_pivot, Vector3(deck_w, 0.025, deck_l), Vector3.ZERO, deck_dk)

	# 2) PERFORATED BAR GRID — 10×20 cm holes with 1 cm bars between them.
	# Long bars span the full deck dimension, so we get the grid look from
	# ~30 boxes instead of 168 (one per hole). Spacing matches the spec.
	var bar_t : float = 0.012                              # 1 cm bar thickness
	var hole_w_pitch : float = 0.11                        # 10 cm hole + 1 cm bar
	var hole_l_pitch : float = 0.21                        # 20 cm hole + 1 cm bar
	# Longitudinal bars (running along the length, equally-spaced across width).
	var n_long : int = int(floor(deck_w / hole_w_pitch)) + 1
	for li in n_long:
		var lx : float = -deck_w * 0.5 + float(li) * hole_w_pitch + hole_w_pitch * 0.5
		# Clamp the last bar to sit at the +X edge if it overshoots.
		lx = clampf(lx, -deck_w * 0.5 + bar_t * 0.5, deck_w * 0.5 - bar_t * 0.5)
		_box(deck_pivot, Vector3(bar_t, 0.018, deck_l),
			Vector3(lx, 0.018, 0.0), bar_mat)
	# Transverse bars (running across the width, equally-spaced along length —
	# these are the "6-7 layers" the operator can count from the side).
	var n_trans : int = int(floor(deck_l / hole_l_pitch)) + 1
	for ti in n_trans:
		var tz : float = -deck_l * 0.5 + float(ti) * hole_l_pitch + hole_l_pitch * 0.5
		tz = clampf(tz, -deck_l * 0.5 + bar_t * 0.5, deck_l * 0.5 - bar_t * 0.5)
		_box(deck_pivot, Vector3(deck_w, 0.018, bar_t),
			Vector3(0.0, 0.018, tz), bar_mat)

	# 3) Side barriers — tall vertical navy walls along the ±X edges, running
	# the full deck length. Keep material on the sieve and read as the dark
	# walls visible in the operator's photo.
	var barrier_h : float = size.y * 0.50
	for sx2 in [-1.0, 1.0]:
		_box(deck_pivot, Vector3(0.05, barrier_h, deck_l + 0.10),
			Vector3(sx2 * (deck_w * 0.5 + 0.025), barrier_h * 0.5, 0.0), navy)
		# A horizontal stiffener band along the top of each barrier.
		_box(deck_pivot, Vector3(0.08, 0.04, deck_l + 0.10),
			Vector3(sx2 * (deck_w * 0.5 + 0.04), barrier_h, 0.0), dark)

	# 4) Top-end rubber inlet flap — hangs at the +Z high end where the upstream
	# belt drops material in. Slight outward curve so it deflects the feed onto
	# the deck rather than off the +Z edge.
	var flap_w : float = deck_w * 0.85
	var flap_h : float = barrier_h * 0.75
	var flap_z : float = deck_l * 0.5 + 0.04
	var flap := _box(deck_pivot, Vector3(flap_w, flap_h, 0.02),
		Vector3(0.0, barrier_h * 0.30, flap_z), rubber)
	flap.rotation = Vector3(deg_to_rad(8.0), 0.0, 0.0)   # leans inward over the deck
	# A steel mounting bar across the top of the flap (where it hangs from).
	_box(deck_pivot, Vector3(flap_w + 0.10, 0.04, 0.04),
		Vector3(0.0, barrier_h * 0.75, flap_z - 0.02), steel)

	# 5) Eccentric drive motor on the +X side of the deck (the source of the
	# vibration). Plus a guard housing around it.
	_motor_unit(deck_pivot, size.y * 0.10, size.z * 0.16,
		Vector3(deck_w * 0.5 + 0.20, 0.05, deck_l * 0.30), "z", ghost)
	_box(deck_pivot, Vector3(0.30, size.y * 0.22, size.z * 0.20),
		Vector3(deck_w * 0.5 + 0.20, 0.05, deck_l * 0.30), dark)

	# ── Static items that DON'T move with the deck (operator platform, signs,
	# discharge chute, fines trough below) sit on the main parent `p`. ──

	# 6) Fines collection trough UNDER the deck — catches the throughs as they
	# fall through the holes. Visible from the side as a dark drop pan.
	var trough_y : float = base_h + 0.02
	var trough_h : float = size.y * 0.18
	_box(p, Vector3(size.x * 0.85, trough_h, size.z * 0.86),
		Vector3(0.0, trough_y + trough_h * 0.5, 0.0), dark)
	# Drain stub coming out the -X side (carries fines to a waste container).
	_cyl(p, 0.06, 0.06, 0.30,
		Vector3(-size.x * 0.50, trough_y + trough_h * 0.30, -size.z * 0.30), dark, "x")

	# 7) Discharge chute at the -Z low end (open-top, sized to land on the
	# downstream conveyor). The operator described this as "looks like a paddle
	# but actually an open-top chute".
	var chute_w : float = deck_w * 0.78
	var chute_l : float = size.z * 0.28
	var chute_y : float = base_h + size.y * 0.06
	var chute_z : float = -size.z * 0.52
	var chute := _box(p, Vector3(chute_w, 0.05, chute_l),
		Vector3(0.0, chute_y, chute_z), navy)
	chute.rotation = Vector3(deg_to_rad(-30.0), 0.0, 0.0)
	# Two rails on the chute sides so material doesn't spill.
	for sxc in [-1.0, 1.0]:
		var crail := _box(p, Vector3(0.05, size.y * 0.12, chute_l),
			Vector3(sxc * chute_w * 0.5, chute_y + size.y * 0.06, chute_z), navy)
		crail.rotation = Vector3(deg_to_rad(-30.0), 0.0, 0.0)
	# Outlet lip at the bottom of the chute.
	_box(p, Vector3(chute_w * 0.95, 0.04, 0.10),
		Vector3(0.0, chute_y - chute_l * 0.30, chute_z - chute_l * 0.45), dark)

	# 8) Operator access platform (grating deck on the +X side, mid-height) +
	# guardrail. Matches the photo where the operator stands beside the sieve.
	var plat_w : float = size.x * 0.42
	var plat_y : float = size.y * 0.55
	var plat_z : float = size.z * 0.05
	_grating_deck(p, plat_w, size.z * 0.42,
		Vector3(size.x * 0.5 + plat_w * 0.5, plat_y, plat_z))
	# Guardrail on the +X side of the platform.
	_box(p, Vector3(0.06, 1.05, size.z * 0.42),
		Vector3(size.x * 0.5 + plat_w + 0.03, plat_y + 0.52, plat_z), yellow)
	for grx in [0.0, 0.30]:
		_box(p, Vector3(size.x * 0.5 + plat_w + 0.06 - grx, 0.04, size.z * 0.42),
			Vector3(size.x * 0.5 + plat_w * 0.5 - grx * 0.25, plat_y + 0.50, plat_z), yellow)

	# 9) DANGER MOVING MACHINERY plate — small white-and-red placard on the +X
	# barrier. The operator's photo showed this prominently next to him.
	_box(p, Vector3(0.02, 0.22, 0.32),
		Vector3(size.x * 0.5 + 0.04, plat_y + 0.55, plat_z - size.z * 0.05), white)
	_box(p, Vector3(0.025, 0.05, 0.32),
		Vector3(size.x * 0.5 + 0.045, plat_y + 0.66, plat_z - size.z * 0.05), red)

	# 10) Yellow safety bollard at the +X near corner (the photo shows one of
	# these emergency-stop posts next to the platform).
	_cyl(p, 0.10, 0.10, plat_y * 0.55,
		Vector3(size.x * 0.5 + plat_w + 0.05, plat_y * 0.275, -size.z * 0.40), yellow)
	# E-stop mushroom button on top of the bollard.
	_cyl(p, 0.05, 0.05, 0.04,
		Vector3(size.x * 0.5 + plat_w + 0.05, plat_y * 0.55 + 0.02, -size.z * 0.40), red, "y")

# ── stairs (#64): steel staircase, grating treads, guardrail BOTH sides ───────
# size = (width, total RISE, total RUN). Climbs from y≈0 at -Z to y≈size.y at +Z,
# all geometry kept inside the size box. Treads use the see-through grating material.
static func _m_stairs(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.6, 0.4)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)
	var width : float = size.x
	var rise  : float = size.y
	var run   : float = size.z
	var hw : float = width * 0.5
	var steps : int = clampi(int(round(rise / 0.21)), 10, 14)   # ~21 cm risers, 10-14 steps
	var step_rise : float = rise / float(steps)
	var step_run  : float = run / float(steps)
	var tread_w : float = width * 0.86
	var tread_t : float = 0.04
	var stringer_t : float = 0.06
	# Diagonal length + pitch of the flight (for the sloped stringers + rails).
	var diag : float = sqrt(rise * rise + run * run)
	var pitch : float = atan2(rise, run)
	# 2 side stringers — sloped boxes running the full diagonal, centred on the flight.
	for sx in [-1.0, 1.0]:
		var st := _box(p, Vector3(stringer_t, 0.20, diag),
			Vector3(float(sx) * hw, rise * 0.5 - 0.05, 0.0), steel)
		st.rotation = Vector3(-pitch, 0.0, 0.0)
	# Grating treads — each centred at its step; front nosing at -Z climbs toward +Z.
	for i in steps:
		var cz : float = -run * 0.5 + (float(i) + 0.5) * step_run
		var cy : float = (float(i) + 1.0) * step_rise
		_grating_deck(p, tread_w, step_run * 0.92, Vector3(0.0, cy, cz))
		# Per-tread collision so the player can actually walk up (operator
		# 2026-07-16: _grating_deck is a bare mesh — walk-through without this).
		if not ghost:
			var tb := StaticBody3D.new()
			tb.position = Vector3(0.0, cy, cz)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(tread_w, 0.06, step_run * 0.92)
			cs.shape = bs
			tb.add_child(cs)
			p.add_child(tb)
		# thin riser plate closing the back of each step (cosmetic; uses steel not grating)
		_box(p, Vector3(tread_w, step_rise, tread_t),
			Vector3(0.0, cy - step_rise * 0.5, cz - step_run * 0.46), steel)
	# Guardrail on BOTH sides: a sloped TOP rail following the flight + vertical posts.
	var rail_h : float = 1.0          # rail height above the tread nosing
	var post_n : int = 4
	for sx2 in [-1.0, 1.0]:
		var rx : float = float(sx2) * hw
		# Sloped top rail, parallel to the stringer but lifted by rail_h.
		var rail := _box(p, Vector3(0.04, 0.04, diag),
			Vector3(rx, rise * 0.5 + rail_h, 0.0), yellow)
		rail.rotation = Vector3(-pitch, 0.0, 0.0)
		# Vertical posts from the stair line up to the rail, spaced along the run.
		for k in post_n:
			var t : float = float(k) / float(post_n - 1)
			var pz2 : float = lerpf(-run * 0.5, run * 0.5, t)
			var py2 : float = lerpf(0.0, rise, t)           # tread height at this point
			_box(p, Vector3(0.04, rail_h, 0.04),
				Vector3(rx, py2 + rail_h * 0.5, pz2), yellow)

# ── guardrail segment (#64): a single railing panel, placed per-edge ──────────
# size = (thickness, height, length along Z). 2 end posts + top rail + mid rail +
# a low toe board (kick plate). Safety-yellow.
static func _m_guardrail(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var rail_mat := _mat(color, ghost, 0.3, 0.55)
	var t : float = maxf(size.x, 0.04)
	var h : float = size.y
	var length : float = size.z
	var hl : float = length * 0.5
	var post_r : float = t * 0.5
	# 2 end posts (vertical cylinders) at each end of the length.
	for sz in [-1.0, 1.0]:
		_cyl(p, post_r, post_r, h, Vector3(0.0, h * 0.5, float(sz) * (hl - post_r)), rail_mat, "y")
	# TOP rail + MID rail — horizontal boxes spanning the length.
	_box(p, Vector3(t, t, length), Vector3(0.0, h,        0.0), rail_mat)
	_box(p, Vector3(t, t, length), Vector3(0.0, h * 0.5,  0.0), rail_mat)
	# Low TOE board (kick plate) near the floor, a bit taller than the rails are thick.
	_box(p, Vector3(t * 0.6, 0.12, length), Vector3(0.0, 0.06, 0.0), rail_mat)

# ── transport screw: closed auger tube with spinning internal screw & cleanout hatch ─
static func _m_transport_screw(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var tilt := deg_to_rad(18.0)

	_box(p, Vector3(0.1, size.y * 0.45, 0.1), Vector3(size.x * 0.3, size.y * 0.22, -size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.45, 0.1), Vector3(-size.x * 0.3, size.y * 0.22, -size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.9, 0.1), Vector3(size.x * 0.3, size.y * 0.45, size.z * 0.35), dark)
	_box(p, Vector3(0.1, size.y * 0.9, 0.1), Vector3(-size.x * 0.3, size.y * 0.45, size.z * 0.35), dark)
	# tube must ASCEND from the low inlet (-Z, short legs) to the high drive (+Z,
	# tall legs): that's PI/2 - tilt. (It was PI/2 + tilt, which tipped the +Z end
	# DOWN — the tube ran opposite its own support frame, so the screw read as
	# "rotated 180°" / running the wrong way. Operator: it goes from low → up.)
	_tube(p, size.x * 0.28, size.z * 0.95, Vector3(0.0, size.y * 0.55, 0.0), steel, PI / 2.0 - tilt)
	# feed inlet box at the LOW end (-Z) — sits under the friction-separator outlet
	_box(p, Vector3(size.x * 0.5, size.y * 0.25, size.z * 0.18), Vector3(0.0, size.y * 0.35, -size.z * 0.42), dark)
	# drive at the HIGH end (+Z)
	_motor_unit(p, size.x * 0.18, size.z * 0.18, Vector3(0.0, size.y * 0.9, size.z * 0.42), "z", ghost)

# ── frictiewasser (stirring tank): open-top rectangular tank split by a centre
#    baffle into two chambers, each with a top-mounted vertical motor driving a
#    vigorous stirrer shaft + blades. Material passes UNDER the baffle (0.2 m gap)
#    from chamber to chamber. Different mechanism from the friction SEPARATOR. ────
static func _m_friction_washer(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.55, 0.4)        # stainless tank shell
	var dark := _mat(_DARK, ghost, 0.5, 0.6)          # motors / shafts / blades
	# Translucent wash water — milky, slight blue cast. Alpha-blended so the
	# stirrer blades and the baffle gap are visible THROUGH the surface, which
	# is how an operator sees them when leaning over the tank rail.
	var water := _mat(Color(0.62, 0.74, 0.74, 0.42), ghost, 0.0, 0.35)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var wall_t : float = 0.08
	var inner_x : float = size.x - wall_t * 2.0       # ≈ 1.34 at X=1.5
	var inner_z : float = size.z - wall_t * 2.0
	# OPEN-TOP TANK: floor + 4 full-height walls (no top lid).
	_box(p, Vector3(size.x, wall_t, size.z), Vector3(0.0, wall_t * 0.5, 0.0), steel)
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(wall_t, size.y, size.z),
			Vector3(float(sx) * (hx - wall_t * 0.5), size.y * 0.5, 0.0), steel)
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(inner_x, size.y, wall_t),
			Vector3(0.0, size.y * 0.5, float(sz) * (hz - wall_t * 0.5)), steel)
	# Wash water — 80 % of the tank's inner volume. The baffle clips through it
	# but that's how it looks in real life: the baffle is a steel wall standing
	# in the water, dividing the surface into two pools. Water surface sits just
	# below the overflow weir lip; material rides on top to the +Z discharge.
	var water_h : float = (size.y - wall_t) * 0.80
	var water_cy : float = wall_t + water_h * 0.5
	_box(p, Vector3(inner_x, water_h, inner_z),
		Vector3(0.0, water_cy, 0.0), water)
	# CENTRE BAFFLE at Z=0 — spans the inner width, from y=0.2 up to the tank top,
	# leaving a 0.2 m gap along the bottom for material to pass under.
	var baffle_h : float = size.y - 0.2
	_box(p, Vector3(inner_x, baffle_h, 0.06),
		Vector3(0.0, 0.2 + baffle_h * 0.5, 0.0), steel)
	# Two chambers along the length, one motor + stirrer over each.
	var motor_r : float = 0.175                       # 35 cm dia
	var motor_h : float = 0.45
	var shaft_r : float = 0.04
	var shaft_len : float = size.y * 0.85
	var stirrer_i : int = 0
	for cz in [-1.0, 1.0]:
		var zc : float = float(cz) * size.z * 0.25     # ≈ ∓0.75
		# Vertical motor sitting ABOVE the tank top, over this chamber.
		_cyl(p, motor_r, motor_r, motor_h, Vector3(0.0, size.y + motor_h * 0.5, zc), dark, "y")
		_box(p, Vector3(0.12, 0.08, 0.12), Vector3(0.0, size.y + motor_h + 0.04, zc), dark)
		# Vertical stirrer shaft dropping into the chamber (spins about Y, vigorous).
		# Two distinct comps so each motor gets its own RPM slider (#68). On ghost,
		# _spinning_cyl returns the parent (not a rotor), so guard the tag.
		var shaft_rm := _spinning_cyl(p, shaft_r, shaft_r, shaft_len,
			Vector3(0.0, size.y * 0.45, zc), dark, "y", Vector3.UP, ghost, 90.0)
		stirrer_i += 1
		if not ghost:
			shaft_rm.set_meta("comp", "stirrer_%d" % stirrer_i)
		# 4 stirrer blades near the lower end, parented UNDER the shaft so they spin
		# with it. The shaft RM sits at world (0, size.y*0.45, zc), so blade offsets
		# are RELATIVE to it. On ghost, shaft_rm == p, so fall back to absolute world
		# coords (Y = lower band, Z = chamber centre).
		var blade_y : float = size.y * 0.18           # target world height of blades
		for i in 4:
			var ang : float = TAU * float(i) / 4.0
			var by : float = (blade_y - size.y * 0.45) if not ghost else blade_y
			var bz : float = 0.0 if not ghost else zc
			var blade := _box(shaft_rm, Vector3(0.35, 0.04, 0.08),
				Vector3(0.0, by, bz), dark)
			blade.rotation.y = ang

# ── intensive washer (Intensiefwasser): compact wash cell + top drive + pipes ─
# ── Intensive Washer: high-speed vertical washing vessel with interactive inspection door ────
static func _m_intensive_washer(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.65, 0.35)

	# Heavy machine plinth with vibration dampeners
	_box(p, Vector3(size.x * 0.88, 0.18, size.z * 0.88), Vector3(0.0, 0.09, 0.0), dark)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(p, 0.08, 0.08, 0.06, Vector3(sx * size.x * 0.36, 0.03, sz * size.z * 0.36), dark, "y")

	# Stainless vertical washing chamber
	var cyl_cy : float = size.y * 0.48
	_cyl(p, size.x * 0.36, size.x * 0.36, size.y * 0.62, Vector3(0.0, cyl_cy, 0.0), body_mat)
	_cyl(p, size.x * 0.38, size.x * 0.38, 0.06, Vector3(0.0, cyl_cy + size.y * 0.31, 0.0), steel)

	# Interactive side inspection hatch with transparent grimy sight-window
	var int_hatch := _interactive_hatch(p, Vector3(0.04, size.y * 0.32, 0.32),
		Vector3(size.x * 0.36, cyl_cy, 0.0), "Intensive Washer Inspection Door", 100.0, 1.0, steel, ghost)
	if not ghost:
		_cyl(int_hatch, 0.09, 0.09, 0.02, Vector3(0.02, 0.0, 0.0), MaterialPalette.mat_glass_inspection_grime(), "x")
		_box(int_hatch, Vector3(0.02, 0.10, 0.03), Vector3(0.03, 0.0, 0.12), dark)

	# High-speed vertical washing rotor inside with staggered radial wear paddles
	var wash_rotor := _spinning_cyl(p, size.x * 0.06, size.x * 0.06, size.y * 0.58, Vector3(0.0, cyl_cy, 0.0), steel, "y", Vector3.UP, ghost, 140.0)
	if not ghost:
		for pi in 6:
			var py : float = -size.y * 0.22 + float(pi) * (size.y * 0.08)
			var p_ang : float = TAU * float(pi) / 6.0
			var pad := _box(wash_rotor, Vector3(size.x * 0.26, 0.02, 0.06), Vector3(cos(p_ang) * size.x * 0.16, py, sin(p_ang) * size.x * 0.16), steel)
			pad.rotation.y = -p_ang

	# Top electric vertical drive motor + gearbox
	_motor_unit(p, size.x * 0.20, size.y * 0.28, Vector3(0.0, size.y * 0.88, 0.0), "y", ghost)

	# High-pressure wash water manifold ring around top + supply pipe
	_torus(p, size.x * 0.37, size.x * 0.40, Vector3(0.0, cyl_cy + size.y * 0.26, 0.0), steel)
	_cyl(p, size.x * 0.06, size.x * 0.06, size.y * 0.45, Vector3(size.x * 0.42, cyl_cy + size.y * 0.10, 0.0), steel, "y")

	# Infeed chute at -Z and discharge chute at +Z
	_box(p, Vector3(size.x * 0.32, size.y * 0.20, size.z * 0.18), Vector3(0.0, size.y * 0.70, -size.z * 0.42), dark)
	_box(p, Vector3(size.x * 0.32, size.y * 0.20, size.z * 0.18), Vector3(0.0, size.y * 0.28,  size.z * 0.42), dark)

# ── wet film silo (vuilsnippersilo): cone silo + top distributor + extraction screw
static func _m_vuilsnippersilo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.35, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var r := size.x * 0.46
	# #103 — legs now reach the BOTTOM of the cone (was 16% high, cone started at
	# 31% → 15% gap, body floated and legs read as "4 detached beams"). Match the
	# proven _m_silo layout: leg_top = floor_clear + cone_h. With floor_clear at
	# 16% and cone height 22%, leg_h = 38% so the cone's narrow tip rests on the
	# leg cap. Cone + cylinder positions follow from leg_top.
	var floor_clear : float = size.y * 0.16
	var cone_h : float = size.y * 0.22
	var cyl_h  : float = size.y * 0.45
	var leg_h : float = floor_clear + cone_h
	# Tag legs as machine_leg so #70's floor-snap extends them when the silo sits
	# above the operating floor.
	var signs: Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			var lg := _box(p, Vector3(0.12, leg_h, 0.12), Vector3(sx * r * 0.7, leg_h * 0.5, sz * r * 0.7), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_h)
	# Cone: tip at leg_top (= leg_h), wide end at leg_h + cone_h. CylinderMesh's
	# pos is the CENTRE of its height, so place it at leg_h + cone_h/2.
	_cyl(p, r, 0.20, cone_h, Vector3(0.0, leg_h + cone_h * 0.5, 0.0), shell)
	# Cylindrical body sits on TOP of the cone's wide end.
	var cyl_cy : float = leg_h + cone_h + cyl_h * 0.5
	_cyl(p, r, r, cyl_h, Vector3(0.0, cyl_cy, 0.0), shell)

	# Transparent vertical level sight-glass strip along the cylinder
	_box(p, Vector3(0.14, cyl_h * 0.85, 0.03),
		Vector3(0.0, cyl_cy, r + 0.01), MaterialPalette.mat_glass_inspection_grime())

	# Interactive cone bottom extraction cleanout hatch
	var _silo_hatch := _interactive_hatch(p, Vector3(0.35, 0.35, 0.04),
		Vector3(0.0, floor_clear + 0.15, r * 0.40), "Vuilsnippersilo Cleanout Hatch", 95.0, 1.0, steel, ghost)
	if not ghost:
		_box(_silo_hatch, Vector3(0.18, 0.18, 0.02), Vector3(0.0, 0.0, 0.02), MaterialPalette.mat_glass_inspection_grime())

	# top wing-distributor drive (vertical) — sits on the cylindrical roof.
	_motor_unit(p, size.x * 0.16, size.y * 0.22, Vector3(0.0, leg_h + cone_h + cyl_h + size.y * 0.02, 0.0), "y", ghost)
	# #81 — extraction screw (uittrekschroef) out the lower side. The previous
	# version was a STATIC tube; the real screw is a slow-turning helical auger
	# pulling dirty flake out the side of the cone. Visible casing tube + visible
	# rotating helical flighting inside, plus a drive motor at the outboard end.
	# Pulled out the side at 18° down from horizontal, so the flake slides down
	# the flight into whatever sits below the +X face of the silo.
	var screw_len  : float = size.z * 0.7
	var screw_tube_r : float = size.x * 0.16
	# Screw comes out of the LOWER THIRD of the cylindrical body (just above
	# where the cone meets the cylinder), so it reads as pulling flake from the
	# cone discharge zone — not floating mid-cylinder.
	var screw_pos  : Vector3 = Vector3(size.x * 0.42, leg_h + cone_h + cyl_h * 0.18, 0.0)
	var screw_tilt : float = deg_to_rad(18.0)
	# Outer casing tube — keeps the look of a sealed screw conveyor.
	var casing : Node3D = Node3D.new()
	casing.name = "ScrewCasing"
	casing.position = screw_pos
	casing.rotation = Vector3(0.0, 0.0, -screw_tilt)         # tilt down the +X axis
	p.add_child(casing)
	# Tube of `_tube`-equivalent built manually: cylinder along X with end caps.
	_cyl(casing, screw_tube_r, screw_tube_r, screw_len, Vector3.ZERO, steel, "x")
	# Rotating helical flighting INSIDE the casing — uses the shared _spinning_auger
	# helper, which builds a RotatingMechanism + the tilted-flight-disc visual.
	var flight_mat := _mat(Color(0.40, 0.32, 0.20), ghost, 0.3, 0.7)   # rust-stained steel
	# _spinning_auger lays the auger along Z; orient the casing so its Z aligns
	# with the screw's discharge axis (the screw runs +X in casing-local, but the
	# auger helper wants Z, so we wrap one more node rotated 90° about Y).
	var auger_pivot : Node3D = Node3D.new()
	auger_pivot.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	casing.add_child(auger_pivot)
	_spinning_auger(auger_pivot, screw_len * 0.96, Vector3.ZERO,
		screw_tube_r * 0.30, screw_tube_r * 0.78, dark, flight_mat, ghost, 45.0, "uittrekschroef")
	# Drive motor on the outboard end of the casing (+X side).
	_motor_unit(casing, screw_tube_r * 1.2, screw_len * 0.18,
		Vector3(screw_len * 0.5 + screw_len * 0.10, 0.0, 0.0), "x", ghost)

# ── MAS trough: pre-extruder agglomeration trough + paddle drive ──────────────
static func _m_mas_bak(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	_legs(p, size, size.y * 0.435, dark)
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
	# Base pad → real collision so there IS a mesh under the compactor to stand on
	# / that connects to the floor (operator 2026-07-16: "not a mesh underneath").
	_box_static_body(p, Vector3(size.x * 0.9, 0.3, size.z * 0.9), Vector3(0.0, 0.15, 0.0), dark)
	# Upright drum body (the compaction chamber).
	var drum_r : float = size.x * 0.42
	_cyl(p, drum_r, drum_r, size.y * 0.72, Vector3(0.0, size.y * 0.5, 0.0), body_mat)
	# Reinforcing rings around the drum.
	for ry in [0.28, 0.52, 0.74]:
		_cyl(p, drum_r * 1.05, drum_r * 1.05, size.y * 0.035, Vector3(0.0, size.y * ry, 0.0), steel)
	# Top lid (flat, no feed hopper — the upstream compactorband sits over the lid
	# and drops directly through a flush top inlet; #106 removed the conical
	# funnel that read as an unwanted "hat" on the drum).
	_cyl(p, drum_r, drum_r, size.y * 0.05, Vector3(0.0, size.y * 0.88, 0.0), steel)
	# Flush top inlet — a short collar around a hole in the lid.
	_cyl(p, drum_r * 0.32, drum_r * 0.32, size.y * 0.04,
		Vector3(-size.x * 0.16, size.y * 0.91, -size.z * 0.16), steel)
	# ── PCU AFZUIGING vent (operator ruling B5 2026-07-06 — OVERRIDES the
	# kitchen-hood geometry in afzuiging.md): ONE ~30 cm ⌀ vent hole in the
	# compactor's TOP CENTRE with the extraction fan visible inside behind a
	# mesh. ONE unit per PCU (the checklist's "unit 2" reading is superseded).
	# The % setpoint drives THIS fan: default 55 (FORM-008 rows 21/22 "Compactor
	# rand afzuiging EN reiniging — 55%", extruder_3a_setpoints.json); forcing
	# 0 % AND 100 % both harm drying (0 = sauna effect / moisture stays, 100 =
	# moisture removed the wrong way — ruling B5). The vent SHAFT above the
	# machine is a separate building system — out of scope. The "EN reiniging"
	# cleaning half of the checklist row has no separate mechanic yet
	# (afzuiging.md flag 7). Sits clear of the off-centre flush inlet collar
	# above and keeps the #106 no-funnel silhouette (nothing rises off the lid).
	var vent_r : float = 0.15                        # ~30 cm diameter (ruling B5)
	var lid_top_y : float = size.y * 0.905
	p.set_meta("afzuiging_pct", 55.0)                # HMI/sim hook — default 55 %
	# Dark recess = the hole read (slightly proud so it doesn't z-fight the lid).
	_cyl(p, vent_r, vent_r, size.y * 0.012, Vector3(0.0, lid_top_y + 0.005, 0.0),
		_mat(Color(0.06, 0.06, 0.07), ghost, 0.2, 0.8))
	# Fan: spinning hub + 4 blades just below the mesh, visible down the hole.
	var fan := _spinning_cyl(p, 0.030, 0.030, 0.05,
		Vector3(0.0, lid_top_y - 0.06, 0.0), dark, "y", Vector3.UP, ghost, 120.0)
	if not ghost:
		for fb in 4:
			var fan_ang : float = TAU * float(fb) / 4.0
			var blade := _box(fan, Vector3(vent_r * 0.85, 0.010, 0.055),
				Vector3(cos(fan_ang) * vent_r * 0.45, 0.0, sin(fan_ang) * vent_r * 0.45), steel)
			blade.rotation.y = -fan_ang
	# Protective mesh disc over the hole (semi-transparent — fan visible behind it).
	var vent_mesh_mat := StandardMaterial3D.new()
	vent_mesh_mat.albedo_color = Color(0.55, 0.57, 0.60, 0.40 if not ghost else 0.22)
	vent_mesh_mat.metallic = 0.6
	vent_mesh_mat.roughness = 0.4
	vent_mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vent_mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cyl(p, vent_r * 0.98, vent_r * 0.98, 0.008, Vector3(0.0, lid_top_y + 0.015, 0.0), vent_mesh_mat)
	# Collar ring around the vent rim (torus — a solid disc would hide the mesh).
	_torus(p, vent_r * 1.0, vent_r * 1.2, Vector3(0.0, lid_top_y + 0.01, 0.0), steel)
	# Interactive side cleanout door on the drum (+X)
	var pcu_hatch := _interactive_hatch(p, Vector3(0.04, 0.45, 0.45),
		Vector3(drum_r * 0.98, size.y * 0.50, 0.0), "PCU Compactor Cleanout Door", 105.0, 1.0, steel, ghost)
	if not ghost:
		# Transparent grimy circular sight-glass into the compaction chamber
		_cyl(pcu_hatch, 0.12, 0.12, 0.02, Vector3(0.02, 0.0, 0.0), MaterialPalette.mat_glass_inspection_grime(), "x")
		_cyl(pcu_hatch, 0.14, 0.14, 0.015, Vector3(0.01, 0.0, 0.0), dark, "x")
		_box(pcu_hatch, Vector3(0.02, 0.12, 0.04), Vector3(0.03, 0.0, 0.18), steel)

	# High-speed rotating bottom cutter disc with 4 carbide knives inside the drum
	var cutter_y : float = size.y * 0.32
	var cutter_disc := _spinning_cyl(p, drum_r * 0.85, drum_r * 0.85, 0.06, Vector3(0.0, cutter_y, 0.0), steel, "y", Vector3.UP, ghost, 180.0)
	if not ghost:
		var knife_mat := _mat(Color(0.85, 0.88, 0.90), ghost, 0.9, 0.15)
		for ki in 4:
			var k_ang : float = TAU * float(ki) / 4.0
			var knife := _box(cutter_disc, Vector3(drum_r * 0.32, 0.02, 0.08),
				Vector3(cos(k_ang) * drum_r * 0.48, 0.04, sin(k_ang) * drum_r * 0.48), knife_mat)
			knife.rotation.y = -k_ang

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
# ── Vacuum degassing zone: dual-chamber TVEplus vacuum degassing with catch-pots & liquid ring pump ───
static func _m_vacuum_degas(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.35, 0.45)
	var steel := _mat(_STEEL, ghost, 0.65, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var glass := _mat(Color(0.12, 0.18, 0.22, 0.7), ghost, 0.05, 0.2)
	var dial_mat := _mat(Color(0.92, 0.92, 0.90), ghost, 0.1, 0.7)

	var leg_h : float = size.y * 0.35
	_legs(p, size, leg_h, dark)
	_box(p, Vector3(size.x * 0.92, 0.08, size.z * 0.96), Vector3(0.0, leg_h, 0.0), steel)

	# Melt channel housing (horizontal, along Z) the melt flows through
	var chan_cy : float = leg_h + size.y * 0.20
	_box(p, Vector3(size.x * 0.52, size.y * 0.32, size.z * 0.96), Vector3(0.0, chan_cy, 0.0), body)

	# Twin tall vacuum domes rising off the channel (Zone 1 coarse degas, Zone 2 deep vacuum)
	var polymer_melt := _mat(Color(0.85, 0.78, 0.52), ghost, 0.1, 0.25)
	for z_dome in [-size.z * 0.22, size.z * 0.22]:
		_cyl(p, size.x * 0.22, size.x * 0.22, size.y * 0.48, Vector3(0.0, chan_cy + size.y * 0.36, z_dome), steel)
		_cyl(p, size.x * 0.25, size.x * 0.25, size.y * 0.08, Vector3(0.0, chan_cy + size.y * 0.60, z_dome), dark)
		# Transparent grimy quartz glass observation dome on top of each degassing tower
		_cyl(p, size.x * 0.14, size.x * 0.14, 0.06, Vector3(0.0, chan_cy + size.y * 0.65, z_dome), MaterialPalette.mat_glass_inspection_grime())
		if not ghost:
			# Molten degassing polymer core visible through the quartz dome
			_cyl(p, size.x * 0.12, size.x * 0.12, 0.04, Vector3(0.0, chan_cy + size.y * 0.58, z_dome), polymer_melt)
		# Vacuum take-off pipe with pneumatic isolation valve to the side
		_cyl(p, 0.035, 0.035, size.x * 0.45, Vector3(-size.x * 0.30, chan_cy + size.y * 0.50, z_dome), dark, "x")
		_box(p, Vector3(0.08, 0.10, 0.08), Vector3(-size.x * 0.25, chan_cy + size.y * 0.50, z_dome), steel)

	# Side vacuum catch-pot canister (traps volatile oil/wax condensates) at -X
	var pot_x : float = -size.x * 0.52
	_cyl(p, size.x * 0.16, size.x * 0.16, size.y * 0.55, Vector3(pot_x, leg_h + size.y * 0.35, 0.0), steel)
	_cyl(p, size.x * 0.18, size.x * 0.18, 0.04, Vector3(pot_x, leg_h + size.y * 0.63, 0.0), dark)
	# Transparent vertical level sight-gauge tube on catch-pot
	_cyl(p, 0.015, 0.015, size.y * 0.36, Vector3(pot_x + size.x * 0.16, leg_h + size.y * 0.35, 0.0), MaterialPalette.mat_glass_sight_gauge(), "y")
	# Manual drain ball-valve at bottom of catch-pot
	_cyl(p, 0.025, 0.025, 0.12, Vector3(pot_x, leg_h + 0.06, 0.0), dark, "y")
	_box(p, Vector3(0.08, 0.02, 0.03), Vector3(pot_x + 0.04, leg_h + 0.06, 0.0), _mat(Color(0.85, 0.15, 0.12), ghost, 0.2, 0.6))

	# Vacuum dial gauge (-1.0 to 0 bar) on front face
	_box(p, Vector3(0.02, 0.14, 0.14), Vector3(pot_x, leg_h + size.y * 0.48, size.z * 0.18), dark)
	_cyl(p, 0.05, 0.05, 0.02, Vector3(pot_x, leg_h + size.y * 0.48, size.z * 0.20), dial_mat, "z")

	# Liquid-ring vacuum pump skid on floor beneath the catch-pot
	_box(p, Vector3(size.x * 0.36, 0.24, size.z * 0.45), Vector3(pot_x, 0.12, 0.0), dark)
	_motor_unit(p, size.x * 0.14, size.z * 0.22, Vector3(pot_x, 0.24, -size.z * 0.12), "z", ghost)

	# Melt pipe in (-Z, from laserfilter) and out (+Z, to meltpump) with flanged joints
	_cyl(p, size.x * 0.11, size.x * 0.11, size.z * 0.24, Vector3(0.0, chan_cy, -size.z * 0.48), dark, "z")
	_cyl(p, size.x * 0.18, size.x * 0.18, 0.05, Vector3(0.0, chan_cy, -size.z * 0.52), steel, "z")
	_cyl(p, size.x * 0.11, size.x * 0.11, size.z * 0.24, Vector3(0.0, chan_cy,  size.z * 0.48), dark, "z")
	_cyl(p, size.x * 0.18, size.x * 0.18, 0.05, Vector3(0.0, chan_cy,  size.z * 0.52), steel, "z")

# =============================================================================
# LINE 3C EXTRUDER BACK-END (#175)
# =============================================================================
# ── Compactorband: a steel feed belt that lifts dosed flake from the Extruder
#    Silo up into the compactor's top funnel. Inclined deck + end rollers +
#    side skirts + a discharge lip at the high (+Z) end. ────────────────────────
static func _m_compactorband(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# Migrated to BeltBuilder. The legacy geometry is fully bespoke (deck box
	# sits AT the pivot origin not +0.22*size.y above it; rollers at ±hz*0.94
	# not ±hz; tapered legs; custom-radius motor at a specific Y; discharge lip
	# at Y=size.y*0.82). BeltBuilder's primitive deck/rollers/rails/legs/motor/
	# chute hardcode positions that don't match this belt, so we set every
	# component to 'none'/false and build the entire visual inside the `extras`
	# callable. BeltBuilder still owns the placeable_id meta + 'placed_object'
	# group + 'belt' group + 'belt_speed' meta + BeltSurface script (the single
	# tagging path — see judge spec). Geometry is byte-for-byte equivalent.
	var spec : Dictionary = BeltBuilder.make_spec()
	spec.deck_kind          = "none"                  # skip BeltBuilder's deck box (wrong Y/length)
	spec.rollers            = "none"                  # legacy uses ±hz*0.94, length 0.84 (generic = ±hz, 0.9)
	spec.side_rails         = "none"                  # legacy skirts in `color` at unique offsets
	spec.has_legs           = false                   # legacy uses tapered legs (short -Z, tall +Z)
	spec.motor              = "none"                  # legacy motor has custom r/length and position
	spec.chute              = "none"                  # legacy discharge lip at Y=size.y*0.82 (not relative to deck_y)
	spec.belt_speed_mps     = _BELT_CARRY_SPEED       # legacy tagging at build_node line 862-877 already handles this
	# NB call-site at line 1100 still passes the child Model node (not the
	# StaticBody3D). The parent body is already tagged at build_node (lines
	# 862-877) so we go through build_internal (geometry only) — calling
	# BeltBuilder.build here would re-tag the Model child with 'placed_object'
	# / 'placeable_id', polluting group iteration. The full single-tagging-path
	# collapse waits until build_node itself moves to BELT_SPECS dispatch.

	# One-off geometry callable — reproduces the legacy primitives 1:1.
	var build_extras : Callable = func(body: Node3D, _deck_root: Node3D, eff_size: Vector3, _spec: Dictionary, is_ghost: bool) -> void:
		var ldark : StandardMaterial3D = PlaceableCatalog._mat(PlaceableCatalog._DARK, is_ghost, 0.3, 0.7)
		var lsteel : StandardMaterial3D = PlaceableCatalog._mat(PlaceableCatalog._STEEL, is_ghost, 0.5, 0.45)
		var lskirt : StandardMaterial3D = PlaceableCatalog._mat(color, is_ghost, 0.3, 0.6)
		var hz : float = eff_size.z * 0.45
		# Frame legs — taller at the +Z (discharge) end so the belt climbs.
		# Leg tops meet the inclined deck centerline at z=±hz*0.8:
		#   deck Y(z) = eff_size.y*0.55 + sin(-20°)*z  →  at z=-hz*0.8 we lose hz*0.8*sin(20°),
		#   at z=+hz*0.8 we gain it. Tag both pairs so extend_machine_legs() lengthens them
		#   when the machine is raised.
		var _incline_drop : float = hz * 0.8 * sin(deg_to_rad(20.0))   # >=0
		var _short_h : float = maxf(0.05, eff_size.y * 0.55 - _incline_drop)
		var _tall_h : float  = eff_size.y * 0.55 + _incline_drop
		var leg_signs : Array[float] = [-1.0, 1.0]
		for sx in leg_signs:
			var _lg_s : MeshInstance3D = PlaceableCatalog._box(body, Vector3(0.09, _short_h, 0.09),
				Vector3(sx * eff_size.x * 0.4, _short_h * 0.5, -hz * 0.8), lsteel)
			_lg_s.add_to_group("machine_leg")
			_lg_s.set_meta("leg_h", _short_h)
			var _lg_t : MeshInstance3D = PlaceableCatalog._box(body, Vector3(0.09, _tall_h, 0.09),
				Vector3(sx * eff_size.x * 0.4, _tall_h * 0.5, hz * 0.8), lsteel)
			_lg_t.add_to_group("machine_leg")
			_lg_t.set_meta("leg_h", _tall_h)
		# Inclined belt frame: a Node3D tilted -20° about X so it rises toward +Z.
		var inc := Node3D.new()
		inc.position = Vector3(0.0, eff_size.y * 0.55, 0.0)
		inc.rotation.x = -deg_to_rad(20.0)
		body.add_child(inc)
		PlaceableCatalog._box(inc, Vector3(eff_size.x * 0.78, 0.06, eff_size.z * 0.96),
			Vector3.ZERO, ldark)                                                       # belt deck
		PlaceableCatalog._box(inc, Vector3(0.05, eff_size.y * 0.16, eff_size.z * 0.96),
			Vector3(eff_size.x * 0.4, eff_size.y * 0.1, 0.0), lskirt)
		PlaceableCatalog._box(inc, Vector3(0.05, eff_size.y * 0.16, eff_size.z * 0.96),
			Vector3(-eff_size.x * 0.4, eff_size.y * 0.1, 0.0), lskirt)
		# End rollers (crosswise) at each end of the incline. D4 — spin at v/r.
		var cb_r : float = eff_size.y * 0.12
		var cb_rpm : float = (_BELT_CARRY_SPEED * 60.0) / (TAU * cb_r)
		PlaceableCatalog._spinning_cyl(inc, cb_r, cb_r, eff_size.x * 0.84,
			Vector3(0.0, 0.0,  hz * 0.94), ldark, "x", Vector3.RIGHT, is_ghost, cb_rpm)
		PlaceableCatalog._spinning_cyl(inc, cb_r, cb_r, eff_size.x * 0.84,
			Vector3(0.0, 0.0, -hz * 0.94), ldark, "x", Vector3.RIGHT, is_ghost, cb_rpm)
		# Discharge lip at the top that drops flake into the compactor funnel.
		PlaceableCatalog._box(body, Vector3(eff_size.x * 0.5, eff_size.y * 0.12, 0.4),
			Vector3(0.0, eff_size.y * 0.82, hz * 0.85), lsteel)
		# Drive motor at the head pulley.
		PlaceableCatalog._motor_unit(body, eff_size.y * 0.1, eff_size.x * 0.22,
			Vector3(eff_size.x * 0.42, eff_size.y * 0.7, hz * 0.8), "x", is_ghost)
	spec.extras = [build_extras]

	# Geometry-only path — build_node already tagged the parent StaticBody3D at
	# lines 862-877. Calling BeltBuilder.build here would re-tag the child Model
	# node passed as `p`, polluting 'placed_object' / 'belt' group iteration.
	BeltBuilder.build_internal(p, "compactorband", size, spec, ghost)

# ── Kopfilter: the die-head screen-changer — a heated melt block with a
#    horizontal slide-plate (carries the screen pack) + melt pipe in/out. ───────
# ── Kopfilter: die-head screen-changer with interactive slide pack changer ──────
static func _m_kopfilter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	_legs(p, size, size.y * 0.325, dark)

	_box(p, Vector3(size.x * 0.7, size.y * 0.55, size.z * 0.6), Vector3(0.0, size.y * 0.6, -size.z * 0.1), body)

	# Interactive horizontal screen-pack slide plate
	var slide_w : float = size.x * 1.30
	var slide_h : float = size.y * 0.18
	var slide_d : float = size.z * 0.20
	var _slide_hatch := _interactive_hatch(p, Vector3(slide_w * 0.6, slide_h, slide_d),
		Vector3(size.x * 0.10, size.y * 0.60, -size.z * 0.05), "Screen Pack Slide Changer", 35.0, 1.0, steel, ghost)

	for sx in [-0.42, 0.42]:
		_cyl(p, size.x * 0.10, size.x * 0.10, slide_h * 1.4,
			Vector3(size.x * 0.10 + sx * slide_w * 0.45, size.y * 0.60, -size.z * 0.05), dark, "y")

	# Hydraulic ram cylinder
	_cyl(p, size.x * 0.08, size.x * 0.08, size.x * 0.42,
		Vector3(size.x * 0.85, size.y * 0.60, -size.z * 0.05), steel, "x")

	# Heater-band rings
	for zz in [-0.28, -0.08, 0.12]:
		_cyl(p, size.x * 0.2, size.x * 0.2, 0.05, Vector3(0.0, size.y * 0.6, zz * size.z), dark, "z")

	# Conical die plate
	_cyl(p, size.x * 0.26, size.x * 0.34, size.z * 0.18, Vector3(0.0, size.y * 0.6, size.z * 0.38), steel, "z")
	_cyl(p, size.x * 0.34, size.x * 0.34, 0.05, Vector3(0.0, size.y * 0.6, size.z * 0.48), dark, "z")
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.4, Vector3(0.0, size.y * 0.6, -size.z * 0.5), dark, "z")

# ── Heetafslag: hot die-face pelletizer with spinning cutter blades & sight port ─
static func _m_heetafslag(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.35, 0.5)
	var steel := _mat(_STEEL, ghost, 0.6, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var water := _mat(Color(0.22, 0.44, 0.52, 0.6), ghost, 0.0, 0.2)
	_legs(p, size, size.y * 0.45, dark)
	_box(p, Vector3(size.x * 0.92, size.y * 0.04, size.z * 0.92), Vector3(0.0, size.y * 0.45 - size.y * 0.02, 0.0), steel)
	_cyl(p, size.x * 0.22, size.x * 0.22, size.z * 0.18, Vector3(0.0, size.y * 0.58, -size.z * 0.4), steel, "z")

	# Cutting chamber housing
	_cyl(p, size.x * 0.32, size.x * 0.32, size.z * 0.4, Vector3(0.0, size.y * 0.58, 0.0), body, "z")

	# Rotating 4-arm pelletizer knife hub spinning against die face
	var knife_hub := _spinning_cyl(p, size.x * 0.08, size.x * 0.08, 0.05,
		Vector3(0.0, size.y * 0.58, -size.z * 0.12), steel, "z", Vector3.FORWARD, ghost, 150.0)
	if not ghost:
		for ki in 4:
			var kang : float = TAU * float(ki) / 4.0
			var kblade := _box(knife_hub, Vector3(size.x * 0.20, 0.015, 0.03),
				Vector3(cos(kang) * size.x * 0.10, sin(kang) * size.x * 0.10, 0.0), steel)
			kblade.rotation.z = kang

	# Transparent grimy quartz sight window into the water cutting chamber
	_cyl(p, size.x * 0.14, size.x * 0.14, 0.02,
		Vector3(size.x * 0.33, size.y * 0.58, 0.0), MaterialPalette.mat_glass_inspection_grime(), "x")

	# Cutter drive motor
	_motor_unit(p, size.x * 0.16, size.z * 0.22, Vector3(0.0, size.y * 0.58, size.z * 0.42), "z", ghost)

	# Water slurry box
	_box(p, Vector3(size.x * 0.6, size.y * 0.22, size.z * 0.5), Vector3(0.0, size.y * 0.2, size.z * 0.1), dark)
	_box(p, Vector3(size.x * 0.54, 0.05, size.z * 0.44), Vector3(0.0, size.y * 0.3, size.z * 0.1), water)
	_cyl(p, size.x * 0.1, size.x * 0.1, size.z * 0.4, Vector3(0.0, size.y * 0.2, size.z * 0.5), steel, "z")

	if not ghost:
		var navy := _mat(Color(0.16, 0.22, 0.42), ghost, 0.25, 0.55)
		var teal := _mat(Color(0.16, 0.55, 0.55), ghost, 0.4, 0.4)
		_box(p, Vector3(0.005, 0.08, 0.60), Vector3(size.x * 0.42, size.y * 0.62, 0.0), navy)
		_cyl(p, 0.045, 0.045, 0.012, Vector3(size.x * 0.43, size.y * 0.62, -0.22), teal, "x")
		_cyl(p, 0.025, 0.025, 0.015, Vector3(size.x * 0.435, size.y * 0.62, -0.22), navy, "x")
		var wc_lbl := _stencil_label(p, "WAVE-CUT SYSTEMS", Vector3(0.42, 0.08, 0.01), "+X")
		wc_lbl.position = Vector3(size.x * 0.43, size.y * 0.62, 0.08)

		var dark_arm := _mat(_DARK, ghost, 0.5, 0.6)
		_box(p, Vector3(0.10, 0.25, 0.30), Vector3(size.x * 0.62, size.y * 0.78, 0.0), dark_arm)
		_box(p, Vector3(0.18, 0.06, 0.06), Vector3(size.x * 0.52, size.y * 0.78, 0.0), dark_arm)

		var ind_r := _mat(Color(0.85, 0.10, 0.10), ghost, 0.2, 0.4)
		var ind_g := _mat(Color(0.10, 0.78, 0.20), ghost, 0.2, 0.4)
		var ind_y := _mat(Color(0.92, 0.82, 0.10), ghost, 0.2, 0.4)
		ind_r.emission_enabled = true
		ind_r.emission = Color(0.85, 0.10, 0.10)
		ind_g.emission_enabled = true
		ind_g.emission = Color(0.10, 0.78, 0.20)
		ind_y.emission_enabled = true
		ind_y.emission = Color(0.92, 0.82, 0.10)
		_cyl(p, 0.04, 0.04, 0.04, Vector3(size.x * 0.66, size.y * 0.84, -0.08), ind_r, "x")
		_cyl(p, 0.04, 0.04, 0.04, Vector3(size.x * 0.66, size.y * 0.84, 0.0), ind_g, "x")
		_cyl(p, 0.04, 0.04, 0.04, Vector3(size.x * 0.66, size.y * 0.84, 0.08), ind_y, "x")

# ── Ontwaterzeef: inclined vibrating screen with interactive splash cover ───
static func _m_ontwaterzeef(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var frame := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.55, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var water := _mat(Color(0.22, 0.42, 0.5, 0.55), ghost, 0.0, 0.2)
	var hz := size.z * 0.5
	_legs(p, size, size.y * 0.31, dark)

	_box(p, Vector3(size.x * 0.86, size.y * 0.22, size.z * 0.9), Vector3(0.0, size.y * 0.42, 0.0), frame)
	_box(p, Vector3(size.x * 0.78, 0.04, size.z * 0.82), Vector3(0.0, size.y * 0.5, 0.0), water)

	var inc := Node3D.new()
	inc.position = Vector3(0.0, size.y * 0.62, 0.0)
	inc.rotation.x = -deg_to_rad(15.0)
	p.add_child(inc)
	_box(inc, Vector3(size.x * 0.74, 0.04, size.z * 0.92), Vector3.ZERO, steel)
	for sx in [-0.38, 0.38]:
		_box(inc, Vector3(0.04, size.y * 0.14, size.z * 0.92), Vector3(sx * size.x, size.y * 0.07, 0.0), frame)

	# Interactive top splash cover hatch with transparent sight glass
	var _zeef_cover := _interactive_hatch(p, Vector3(size.x * 0.76, 0.04, size.z * 0.85),
		Vector3(0.0, size.y * 0.76, 0.0), "Dewater Sieve Splash Cover", 85.0, 1.0, steel, ghost)
	if not ghost:
		_box(_zeef_cover, Vector3(size.x * 0.45, 0.02, size.z * 0.45),
			Vector3(-size.x * 0.30, 0.02, 0.0), MaterialPalette.mat_glass_inspection_grime())

	_box(p, Vector3(size.x * 0.5, size.y * 0.1, 0.35), Vector3(0.0, size.y * 0.72, hz * 0.86), steel)
	_motor_unit(p, size.y * 0.12, size.x * 0.24, Vector3(size.x * 0.42, size.y * 0.6, 0.0), "x", ghost)

# ── Weegschaal: batch weigher with interactive pneumatic dump valve ────
static func _m_weegschaal(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.4, 0.45)
	var steel := _mat(_STEEL, ghost, 0.55, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)

	var signs : Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			_box(p, Vector3(0.08, size.y * 0.5, 0.08), Vector3(sx * size.x * 0.38, size.y * 0.25, sz * size.z * 0.38), steel)
			_cyl(p, 0.06, 0.06, 0.04, Vector3(sx * size.x * 0.38, size.y * 0.52, sz * size.z * 0.38), dark, "y")

	# Hopper cone body
	_cyl(p, size.x * 0.42, size.x * 0.15, size.y * 0.45, Vector3(0.0, size.y * 0.72, 0.0), body, "y")

	# Interactive bottom dump slide gate
	var _weigh_gate := _interactive_hatch(p, Vector3(0.28, 0.03, 0.28),
		Vector3(0.0, size.y * 0.48, 0.0), "Weigher Discharge Slide Gate", 80.0, 1.0, steel, ghost)

	# Digital weight indicator display on the front
	_box(p, Vector3(0.30, 0.20, 0.08), Vector3(0.0, size.y * 0.65, size.z * 0.44), dark)
	var disp_mat := _mat(Color(0.12, 0.92, 0.32), ghost, 0.0, 0.5)
	disp_mat.emission_enabled = true
	disp_mat.emission = Color(0.12, 0.92, 0.32)
	_box(p, Vector3(0.24, 0.12, 0.01), Vector3(0.0, size.y * 0.65, size.z * 0.485), disp_mat)

# ── Heater/filter cabinet — operator spec 2026-08-28 (doc-walk Q2.4): 60×60 cm,
#    ~2 m high; the filter stacks sit inside, and pipes run from the BOTTOM of
#    the stacks to the adjacent blower. Heats the air the blower sucks in (3A
#    rondmeng loop; 3B's plasmaq-heater question still open). Air-side utility,
#    role "none". ─────────────────────────────────────────────────────────────
static func _m_heater_cabinet(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.5)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var warn  := _mat(Color(0.85, 0.55, 0.10), ghost, 0.2, 0.6)   # hot-surface accent

	# Cabinet body on a low plinth.
	_box(p, Vector3(size.x, 0.06, size.z), Vector3(0.0, 0.03, 0.0), dark)
	_box(p, Vector3(size.x * 0.96, size.y - 0.10, size.z * 0.96),
		Vector3(0.0, (size.y - 0.10) * 0.5 + 0.06, 0.0), shell)
	# Louvre vent panel on the front (+Z) upper half — the air intake.
	for vy in [0.62, 0.70, 0.78, 0.86]:
		_box(p, Vector3(size.x * 0.70, 0.02, 0.02),
			Vector3(0.0, size.y * vy, size.z * 0.49), dark)
	# Filter-stack access door (lower front) with a handle.
	_box(p, Vector3(size.x * 0.72, size.y * 0.38, 0.02),
		Vector3(0.0, size.y * 0.28, size.z * 0.485), steel)
	_box(p, Vector3(0.03, 0.10, 0.03), Vector3(size.x * 0.28, size.y * 0.28, size.z * 0.50), dark)
	# Hot-surface warning band near the top.
	_box(p, Vector3(size.x * 0.97, 0.05, size.z * 0.97), Vector3(0.0, size.y * 0.93, 0.0), warn)
	# The pipe from the filter-stack BOTTOM out the -X flank toward the blower
	# (operator: "from the bottom of these filter stacks, the pipes go to the
	# blower"). Elbow: short vertical drop + horizontal run.
	_cyl(p, 0.09, 0.09, 0.25, Vector3(-size.x * 0.30, 0.30, 0.0), steel, "y")
	_cyl(p, 0.09, 0.09, size.x * 1.4, Vector3(-size.x * 0.95, 0.18, 0.0), steel, "x")
	# Small electrical junction box on the +X flank.
	_box(p, Vector3(0.04, 0.18, 0.14), Vector3(size.x * 0.50, size.y * 0.55, 0.0), dark)

# ── Bigbag station (gap 2.2, lijn_3a_flow.md edge 36) — operator composite
#    spec 2026-08-28 from two chat reference images: BOTTOM per image 1 (open
#    square-tube frame, bag hanging by its 4 loops on corner strap hangers,
#    resting on a wooden EURO pallet), TOP per image 2 (metal fill cylinder
#    with the bag's "trunk" inlet sleeve bound around it with a BLUE strap,
#    small cyclone on top of the frame). Q&A behaviour fact, NOT built here:
#    after a knife/screen change the extruder runs out to bigbag until quality
#    is OK — gameplay hook for a later pass. size = (1.7, 3.6, 1.7). ─────────
static func _m_bigbag_station(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel  := _mat(color, ghost, 0.55, 0.4)                      # galvanized frame
	var dark   := _mat(_DARK, ghost, 0.5, 0.6)
	var wood   := _mat(Color(0.62, 0.47, 0.30), ghost, 0.0, 0.85)    # pallet timber
	var fabric := _mat(Color(0.90, 0.90, 0.88), ghost, 0.0, 0.92)    # woven PP bag
	var strap  := _mat(Color(0.94, 0.94, 0.92), ghost, 0.0, 0.85)    # lifting loops
	var blue   := _mat(Color(0.16, 0.32, 0.75), ghost, 0.1, 0.6)     # trunk clamp strap
	var inox   := _mat(_STEEL, ghost, 0.7, 0.3)                      # fill head / cyclone

	var post_x : float = size.x * 0.44
	var frame_top : float = size.y * 0.68                            # ≈ 2.45 m

	# ── EURO pallet on the floor (image 1): 3 bearers + deck boards. ─────────
	for bx in [-0.45, 0.0, 0.45]:
		_box(p, Vector3(0.14, 0.10, 1.00), Vector3(bx, 0.05, 0.0), wood)
	for bz in [-0.44, -0.22, 0.0, 0.22, 0.44]:
		_box(p, Vector3(1.18, 0.022, 0.12), Vector3(0.0, 0.111, bz), wood)

	# ── Big bag: bulged white cube on the pallet. ────────────────────────────
	var bag_base : float = 0.125
	var bag_h : float = size.y * 0.335                               # ≈ 1.2 m
	var bag_top : float = bag_base + bag_h
	_box(p, Vector3(0.94, bag_h, 0.94), Vector3(0.0, bag_base + bag_h * 0.5, 0.0), fabric)
	# low-belly bulge (a filled bag bellies out at the BOTTOM; keeping the
	# band low and tall tucks its edge under the straps instead of reading as
	# a second stacked box — first render showed a hard mid-bag step)
	_box(p, Vector3(1.04, bag_h * 0.62, 1.04), Vector3(0.0, bag_base + bag_h * 0.33, 0.0), fabric)

	# ── Trunk inlet sleeve (slurf) up to the fill cylinder, blue strap bound. ─
	var cyl_bot : float = frame_top - 0.28                           # fill cylinder lower lip
	_cyl(p, 0.115, 0.20, cyl_bot - bag_top, Vector3(0.0, (bag_top + cyl_bot) * 0.5, 0.0), fabric, "y")
	_cyl(p, 0.135, 0.135, 0.05, Vector3(0.0, cyl_bot + 0.06, 0.0), blue, "y")   # the blue strap

	# ── Fill head (image 2): metal cylinder through the frame deck + clamp. ──
	_cyl(p, 0.115, 0.115, 0.55, Vector3(0.0, cyl_bot + 0.24, 0.0), inox, "y")
	_cyl(p, 0.145, 0.145, 0.04, Vector3(0.0, cyl_bot + 0.14, 0.0), dark, "y")   # clamp collar

	# ── Cyclone on top of the frame (image 2 style). ─────────────────────────
	var cy_body : float = frame_top + 0.62
	_cyl(p, 0.30, 0.12, 0.32, Vector3(0.0, frame_top + 0.30, 0.0), inox, "y")   # cone down to the fill pipe
	_cyl(p, 0.30, 0.30, 0.42, Vector3(0.0, cy_body, 0.0), inox, "y")            # body
	_cyl(p, 0.07, 0.07, size.x * 0.42, Vector3(size.x * 0.26, cy_body + 0.10, 0.0), inox, "x")  # tangential inlet stub
	_cyl(p, 0.09, 0.09, 0.24, Vector3(0.0, cy_body + 0.32, 0.0), inox, "y")     # top vent stub

	# ── Open steel frame (image 1): 4 posts + top perimeter + head beams. ────
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := _box(p, Vector3(0.08, frame_top, 0.08),
				Vector3(sx * post_x, frame_top * 0.5, sz * post_x), steel)
			post.add_to_group("machine_leg")
			post.set_meta("leg_h", frame_top)
	for sz2 in [-1.0, 1.0]:
		_box(p, Vector3(post_x * 2.0 + 0.08, 0.10, 0.08),
			Vector3(0.0, frame_top + 0.05, sz2 * post_x), steel)
		_box(p, Vector3(0.08, 0.10, post_x * 2.0 + 0.08),
			Vector3(sz2 * post_x, frame_top + 0.05, 0.0), steel)
	# head beams carrying the fill cylinder
	for sx3 in [-1.0, 1.0]:
		_box(p, Vector3(0.08, 0.08, post_x * 2.0),
			Vector3(sx3 * 0.20, frame_top + 0.12, 0.0), steel)
	# base rails along two sides with foot pads
	for sz3 in [-1.0, 1.0]:
		_box(p, Vector3(post_x * 2.0 + 0.16, 0.06, 0.10),
			Vector3(0.0, 0.03, sz3 * post_x), steel)

	# ── 4 lifting loops (image 2): bag corners up to hangers at the posts. ───
	for sx4 in [-1.0, 1.0]:
		for sz4 in [-1.0, 1.0]:
			var a := Vector3(sx4 * 0.40, bag_top - 0.06, sz4 * 0.40)
			var b := Vector3(sx4 * (post_x - 0.06), frame_top - 0.12, sz4 * (post_x - 0.06))
			var d := b - a
			var loop := _box(p, Vector3(0.055, d.length(), 0.012),
				(a + b) * 0.5, strap)
			loop.rotation = Vector3(atan2(d.z, d.y), 0.0, -atan2(d.x, d.y))
			# hanger ratchet block at the top of each strap (image 1 detail)
			_box(p, Vector3(0.07, 0.12, 0.05), b + Vector3(0.0, 0.06, 0.0), dark)

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

# ── fines bin (under-conveyor): black plastic bin on castors with interactive lid ──────
static func _m_fines_bin(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body := _mat(color, ghost, 0.05, 0.85)
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)

	# Walls + base
	_box(p, Vector3(size.x * 0.98, 0.05, size.z * 0.98), Vector3(0.0, 0.05, 0.0), dark)
	_box(p, Vector3(size.x * 0.98, size.y * 0.95, 0.04), Vector3(0.0, size.y * 0.5, size.z * 0.49), body)
	_box(p, Vector3(size.x * 0.98, size.y * 0.95, 0.04), Vector3(0.0, size.y * 0.5, -size.z * 0.49), body)
	_box(p, Vector3(0.04, size.y * 0.95, size.z * 0.96), Vector3(size.x * 0.49, size.y * 0.5, 0.0), body)
	_box(p, Vector3(0.04, size.y * 0.95, size.z * 0.96), Vector3(-size.x * 0.49, size.y * 0.5, 0.0), body)

	# Interactive split flip-lid on top
	var bin_lid := _interactive_hatch(p, Vector3(size.x * 0.96, 0.02, size.z * 0.96),
		Vector3(0.0, size.y * 0.98, 0.0), "Fines Bin Lid", 85.0, 1.0, dark, ghost)
	if not ghost:
		_box(bin_lid, Vector3(size.x * 0.40, 0.015, size.z * 0.40),
			Vector3(-size.x * 0.24, 0.02, 0.0), MaterialPalette.mat_glass_inspection_grime())
		_box(bin_lid, Vector3(0.12, 0.04, 0.04), Vector3(-size.x * 0.45, 0.04, 0.0), steel)

	# 4 castors at the corners
	for sx in [-size.x * 0.4, size.x * 0.4]:
		for sz in [-size.z * 0.4, size.z * 0.4]:
			_cyl(p, 0.05, 0.05, 0.06, Vector3(sx, 0.03, sz), dark, "x")

# ── cyclone underflow bin: grey steel cube with interactive cleanout flap ──────
static func _m_cyclone_bin(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.55, 0.4)
	var dark := _mat(_DARK, ghost, 0.4, 0.55)
	_box(p, Vector3(size.x * 0.98, 0.1, size.z * 0.98), Vector3(0.0, 0.05, 0.0), dark)
	_box(p, Vector3(size.x * 0.95, size.y * 0.95, 0.06), Vector3(0.0, size.y * 0.5, size.z * 0.49), steel)
	_box(p, Vector3(size.x * 0.95, size.y * 0.95, 0.06), Vector3(0.0, size.y * 0.5, -size.z * 0.49), steel)
	_box(p, Vector3(0.06, size.y * 0.95, size.z * 0.95), Vector3(size.x * 0.49, size.y * 0.5, 0.0), steel)
	_box(p, Vector3(0.06, size.y * 0.95, size.z * 0.95), Vector3(-size.x * 0.49, size.y * 0.5, 0.0), steel)

	# Interactive front cleanout flap door
	var cyc_door := _interactive_hatch(p, Vector3(size.x * 0.65, size.y * 0.55, 0.03),
		Vector3(0.0, size.y * 0.45, size.z * 0.50), "Cyclone Bin Cleanout Flap", 100.0, 1.0, steel, ghost)
	if not ghost:
		_box(cyc_door, Vector3(size.x * 0.35, size.y * 0.25, 0.02),
			Vector3(-size.x * 0.15, 0.0, 0.02), MaterialPalette.mat_glass_inspection_grime())

# ── IBC tote: 1 m³ caged white plastic tank on a wooden pallet with operable valve ──────
static func _m_ibc_tote(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var plastic := _mat(color, ghost, 0.0, 0.4)
	if not ghost:
		plastic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		plastic.albedo_color = Color(color.r, color.g, color.b, 0.85)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var wood := _mat(Color(0.62, 0.48, 0.30), ghost, 0.0, 0.85)
	var red := _mat(Color(0.85, 0.15, 0.12), ghost, 0.2, 0.5)

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
	for ry in [ty - size.y * 0.3, ty, ty + size.y * 0.3]:
		_box(p, Vector3(size.x, 0.03, 0.03), Vector3(0.0, ry, size.z * 0.5), dark)

	# Top screw cap (interactive)
	var _cap := _interactive_hatch(p, Vector3(0.24, 0.06, 0.24),
		Vector3(0.0, ty + size.y * 0.48, 0.0), "IBC Fill Cap", 75.0, 1.0, red, ghost)

	# Outlet valve with interactive ball valve lever
	_box(p, Vector3(0.16, 0.12, 0.18), Vector3(size.x * 0.3, 0.25, size.z * 0.5 + 0.05), dark)
	var _ibc_valve := _interactive_hatch(p, Vector3(0.18, 0.03, 0.04),
		Vector3(size.x * 0.3, 0.32, size.z * 0.5 + 0.12), "IBC Drain Valve Handle", 90.0, 1.0, red, ghost)

# ── waste container (schraperbak skip): open-top bin with interactive front swing gate ────────
static func _m_waste_container(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var wy := size.y * 0.5
	_box(p, Vector3(size.x * 0.96, 0.1, size.z * 0.96), Vector3(0.0, size.y * 0.18, 0.0), steel)
	_box(p, Vector3(0.08, size.y * 0.7, size.z * 0.96), Vector3(size.x * 0.48, wy, 0.0), steel)
	_box(p, Vector3(0.08, size.y * 0.7, size.z * 0.96), Vector3(-size.x * 0.48, wy, 0.0), steel)
	_box(p, Vector3(size.x * 0.96, size.y * 0.7, 0.08), Vector3(0.0, wy, -size.z * 0.48), steel)

	# Interactive front swing dump-door
	var _waste_door := _interactive_hatch(p, Vector3(size.x * 0.94, size.y * 0.68, 0.06),
		Vector3(0.0, wy, size.z * 0.48), "Waste Container Dump Door", 95.0, 1.0, steel, ghost)

	# forklift pockets at the base
	_box(p, Vector3(size.x * 0.25, 0.12, size.z * 1.0), Vector3(size.x * 0.22, 0.06, 0.0), dark)
	_box(p, Vector3(size.x * 0.25, 0.12, size.z * 1.0), Vector3(-size.x * 0.22, 0.06, 0.0), dark)

# ── bunker: lijn-3 BUFFER CONVEYOR downstream of Shredder 1 with interactive doors ──────
static func _m_bunker(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.45, 0.5)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var wt := 0.10
	var deck_y : float = 1.25
	var wall_top : float = size.y

	p.set_meta("bunker_speed_setting", 600.0)
	p.set_meta("bunker_speed_min", 200.0)
	p.set_meta("bunker_speed_max", 1000.0)
	p.set_meta("bunker_relay_trip_below", 200.0)
	p.set_meta("bunker_fill_setting_cm", 115.0)
	p.set_meta("bunker_fill_min_cm", 100.0)
	p.set_meta("bunker_fill_max_cm", 130.0)
	p.set_meta("bunker_fill_miscal_offset_cm", 40.0)

	# ── Support legs
	var leg_zs : Array[float] = [-hz + 0.4, -hz * 0.5, 0.0, hz * 0.5, hz - 0.4]
	for lz in leg_zs:
		for sx in [-1.0, 1.0]:
			var lg := _box(p, Vector3(0.12, deck_y, 0.12),
				Vector3(float(sx) * (hx - 0.10), deck_y * 0.5, lz), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", deck_y)

	for sx2 in [-1.0, 1.0]:
		_box(p, Vector3(0.14, 0.14, size.z * 0.98),
			Vector3(float(sx2) * (hx - 0.10), deck_y - 0.20, 0.0), dark)

	# Travelling deck
	var deck_w : float = size.x - wt * 2.0
	var belt_mat := _mat(Color(0.10, 0.10, 0.12), ghost, 0.85, 0.3)
	if ghost:
		_box(p, Vector3(deck_w, 0.12, size.z * 0.98), Vector3(0.0, deck_y - 0.06, 0.0), belt_mat)
	else:
		var deck_body := StaticBody3D.new()
		deck_body.name = "BunkerDeck"
		deck_body.position = Vector3(0.0, deck_y - 0.06, 0.0)
		p.add_child(deck_body)
		var dmi := MeshInstance3D.new()
		var dbm := BoxMesh.new()
		dbm.size = Vector3(deck_w, 0.12, size.z * 0.98)
		dmi.mesh = dbm
		dmi.material_override = belt_mat
		deck_body.add_child(dmi)
		var dcol := CollisionShape3D.new()
		var dsh := BoxShape3D.new()
		dsh.size = Vector3(deck_w, 0.12, size.z * 0.98)
		dcol.shape = dsh
		deck_body.add_child(dcol)
		deck_body.add_to_group("belt")
		var carry : float = 600.0 / 36000.0
		deck_body.set_meta("belt_speed", carry)
		deck_body.set_meta("belt_ramp_tau_s", 2.5)
		var belt_script : Resource = load("res://src/sim/BeltSurface.gd")
		if belt_script != null:
			deck_body.set_script(belt_script)
			deck_body.set("belt_speed_mps", carry)
			deck_body.set("belt_ramp_tau_s", 2.5)

	# Walls
	var wall_h : float = wall_top - deck_y
	var wall_cy : float = deck_y + wall_h * 0.5
	_box(p, Vector3(wt, wall_h, size.z), Vector3(-hx + wt * 0.5, wall_cy, 0.0), steel)
	_box(p, Vector3(wt, wall_h, size.z), Vector3( hx - wt * 0.5, wall_cy, 0.0), steel)
	_box(p, Vector3(size.x, wall_h, wt), Vector3(0.0, wall_cy, -hz + wt * 0.5), steel)

	var mouth_h : float = 1.0
	_box(p, Vector3(size.x, wall_h - mouth_h, wt),
		Vector3(0.0, deck_y + mouth_h + (wall_h - mouth_h) * 0.5, hz - wt * 0.5), steel)

	# Interactive Bunkerdeuren (person-height hinged doors on -Z infeed)
	var door_w : float = 0.90
	var door_h : float = 2.00
	var door_z : float = -hz - 0.03
	var dy0 : float = deck_y + 0.05
	for dx in [-0.65, 0.65]:
		var dcx := float(dx)
		var sx_sign : float = 1.0 if dx > 0 else -1.0
		var bunker_door := _interactive_hatch(p, Vector3(door_w, door_h, 0.05),
			Vector3(dcx, dy0 + door_h * 0.5, door_z), "Bunker Infeed Door %s" % ("Right" if dx > 0 else "Left"), 95.0, sx_sign, steel, ghost)
		if not ghost:
			# Grimy viewing window on the door
			_box(bunker_door, Vector3(door_w * 0.70, door_h * 0.28, 0.02),
				Vector3(-sx_sign * door_w * 0.15, door_h * 0.20, 0.02), MaterialPalette.mat_glass_inspection_grime())

	# Rotating bunkerrol across discharge end
	var roll := _spinning_cyl(p, 0.25, 0.25, size.x * 0.88,
		Vector3(0.0, deck_y + 0.20, hz - 0.45), dark, "x", Vector3.RIGHT, ghost, 12.0)
	if not ghost:
		roll.set_meta("comp", "uittrekrol")
	# ── Deck drive motor, low on the +X side at the discharge end (flag F10). ─
	_motor_unit(p, 0.24, 0.60, Vector3(hx + 0.05, deck_y - 0.35, hz - 0.8), "z", ghost)
	_guard(p, Vector3(0.5, 0.35, 0.18), Vector3(hx + 0.05, deck_y + 0.05, hz - 0.8), ghost)
	# ── Fill sensor ("Bunker sensor", FORM-018_p2 wipe item): small box ~3 m
	# above the deck at the discharge end (ruling B4 "sensor ~3 m up"; mount
	# placeholder, flag F12).
	_box(p, Vector3(0.18, 0.24, 0.12),
		Vector3(hx - wt - 0.10, deck_y + 3.0, hz - 0.8), _mat(_SAFETY, ghost, 0.2, 0.6))

# ── Shredder 1 (coarse pre-shredder): heavy + big throat + dual rotors ────────
##
## Bigger and beefier than the generic shredder model. Two huge slow-turning
## cutter shafts visible at the throat, a massive drive motor, V-belt guard,
## heavy concrete base. Outputs ≤ 10×10 cm chunks.
## Shredder 1 — the big COARSE pre-shredder on Line 3A/3B. Operator spec:
## ~4 m wide (X) · 5 m long (Z) · 9 m tall (Y, INCLUDING the feed hopper on top).
## Internals: a horizontal ROTOR (shaft + knife discs) across the width, with
## fixed STATOR counter-knife bars. A discharge CONVEYOR runs dead-centre under
## the machine along the 5 m length (Z): level at ~0.75 m from under the chamber
## to 1 m past the +Z edge, then 35° up to ~4.5 m to feed the bunker at the far
## end. (Conveyor extends beyond the bbox; collision is the 4×9×5 body box.)
static func _m_shredder_1(p: Node3D, size: Vector3, color: Color, ghost: bool, wide_hopper: bool = true) -> void:
	var dark    := _mat(_DARK, ghost, 0.4, 0.6)
	var steel   := _mat(_STEEL, ghost, 0.5, 0.45)
	var body_mat := _mat(color, ghost, 0.3, 0.55)
	var belt_mat := _mat(Color(0.08, 0.08, 0.10), ghost, 0.85, 0.3)
	var hx := size.x * 0.5     # 2.0
	var hz := size.z * 0.5     # 2.5

	# ── Vertical zones (total height = size.y) ───────────────────────────────
	var leg_top    : float = 1.3                  # clearance for the under-conveyor
	var chamber_h  : float = size.y * 0.42        # cutting-chamber height
	var chamber_cy : float = leg_top + chamber_h * 0.5
	var chamber_top: float = leg_top + chamber_h

	# Support legs (4 corners) — centre left open so the conveyor passes under.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(0.3, leg_top, 0.3),
				Vector3(float(sx) * hx * 0.86, leg_top * 0.5, float(sz) * hz * 0.82), steel)
			# Simple vertical floor legs under the body → lengthen to the floor when
			# raised (#70). (The discharge-conveyor posts below are NOT tagged — that
			# sub-frame extends past the bbox and must not be stretched.)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_top)
	# Base deck — SPLIT to leave a centre drop slot (X) over the discharge conveyor
	# so material drawn down between the two rotors drops through onto the belt below
	# (operator 2026-07-14: "centre of the 2 rotors opens on the bottom onto the
	# conveyor"). Was a single solid plate that sealed the chamber bottom.
	var slot_hw : float = 0.55                          # half-width of the drop slot (X)
	var base_hw : float = size.x * 0.48
	var plate_w : float = base_hw - slot_hw
	for sx0 in [-1.0, 1.0]:
		_box(p, Vector3(plate_w, 0.22, size.z * 0.92),
			Vector3(float(sx0) * (slot_hw + plate_w * 0.5), leg_top, 0.0), steel)

	# Cutting-chamber housing — 3 solid walls + 1 interactive hinged maintenance door (+X side)
	# -X wall (motor side)
	_box(p, Vector3(0.18, chamber_h, size.z * 0.9), Vector3(-hx * 0.9, chamber_cy, 0.0), body_mat)
	# +X wall — interactive hinged maintenance access door
	var shred_door := _interactive_hatch(p, Vector3(0.08, chamber_h * 0.85, size.z * 0.75),
		Vector3(hx * 0.9, chamber_cy, 0.0), "Shredder Cutting Chamber Door", 100.0, -1.0, body_mat, ghost)
	if not ghost:
		# Transparent grimy polycarbonate sight window in the shredder door
		_box(shred_door, Vector3(0.02, chamber_h * 0.35, size.z * 0.35),
			Vector3(0.04, 0.0, 0.0), MaterialPalette.mat_glass_inspection_grime())
		# Heavy door latch handles
		_box(shred_door, Vector3(0.04, 0.12, 0.04), Vector3(0.06, 0.0, size.z * 0.30), steel)
	# Perimeter frame on +X around the door opening
	_box(p, Vector3(0.14, chamber_h, 0.12), Vector3(hx * 0.9, chamber_cy, -size.z * 0.42), steel)
	_box(p, Vector3(0.14, chamber_h, 0.12), Vector3(hx * 0.9, chamber_cy,  size.z * 0.42), steel)
	_box(p, Vector3(0.14, 0.10, size.z * 0.9), Vector3(hx * 0.9, chamber_top - 0.05, 0.0), steel)

	for sz in [-1.0, 1.0]:
		_box(p, Vector3(size.x * 0.9, chamber_h, 0.18),
			Vector3(0.0, chamber_cy, float(sz) * hz * 0.9), body_mat)

	# TWIN ROTORS — two counter-rotating horizontal shafts (X), offset in Z, whose
	# knife discs interleave so material is drawn DOWN into the centre gap and drops
	# through the base slot onto the conveyor (operator 2026-07-14: "2 rotors, centre
	# opens onto the conveyor"). Each shaft is a real RotatingMechanism; the discs
	# parented UNDER it turn with it. On ghost, the RM == p so discs fall back to
	# absolute Y/Z.
	var rotor_y  : float = leg_top + chamber_h * 0.34
	var rotor_r  : float = 0.34
	var rotor_dz : float = rotor_r * 1.15               # one shaft either side of centre
	var n_knives : int = 6
	var disc_pitch : float = (hx * 1.56) / float(n_knives - 1)
	for ri in [0, 1]:
		var rz : float = (-1.0 if ri == 0 else 1.0) * rotor_dz
		var spin : Vector3 = Vector3.RIGHT if ri == 0 else Vector3.LEFT   # counter-rotate inward
		var rrm := _spinning_cyl(p, rotor_r, rotor_r, size.x * 0.86, Vector3(0.0, rotor_y, rz), steel, "x", spin, ghost)
		if not ghost:
			rrm.set_meta("comp", "rotor")
		for i in n_knives:
			# offset shaft-2's discs half a pitch so the two disc sets interleave
			var kx : float = lerp(-hx * 0.78, hx * 0.78, float(i) / float(n_knives - 1)) + (disc_pitch * 0.5 if ri == 1 else 0.0)
			var d_y : float = 0.0 if not ghost else rotor_y
			var d_z : float = 0.0 if not ghost else rz
			_cyl(rrm, rotor_r * 1.5, rotor_r * 1.5, 0.10, Vector3(kx, d_y, d_z), dark, "x")
	# STATORS — fixed counter-knife bars along the OUTER side of each rotor.
	for sz in [-1.0, 1.0]:
		_box(p, Vector3(size.x * 0.82, 0.16, 0.14),
			Vector3(0.0, rotor_y - rotor_r * 0.35, float(sz) * (rotor_dz + rotor_r * 0.95)), dark)

	# FEED HOPPER on top — a HOLLOW funnel (open top to feed, open bottom into the
	# chamber), NOT a solid block (operator 2026-07-14). Coarse shredder = a tall
	# throat + a wider flared collar; wide_hopper=false (Shredder 2) = single throat.
	var hopper_h : float = size.y - chamber_top
	var lo_h : float = hopper_h * (0.5 if wide_hopper else 1.0)
	_hollow_box(p, size.x * 0.92, lo_h, size.z * 0.88, Vector3(0.0, chamber_top + lo_h * 0.5, 0.0), 0.10, steel)
	if wide_hopper:
		var up_h : float = hopper_h * 0.5
		_hollow_box(p, size.x * 1.12, up_h, size.z * 1.04, Vector3(0.0, chamber_top + lo_h + up_h * 0.5, 0.0), 0.10, steel)
		# Structural reinforcement ribs along hopper exterior
		for iz in [-0.8, 0.0, 0.8]:
			_box(p, Vector3(size.x * 1.14, 0.04, 0.04), Vector3(0.0, chamber_top + lo_h + up_h * 0.5, iz), dark)

	# Heavy hydraulic pusher ram cylinder on +Z side
	var ram_body := _cyl(p, 0.12, 0.12, 1.2, Vector3(0.0, chamber_cy, hz + 0.45), dark, "z")
	var ram_rod  := _cyl(p, 0.06, 0.06, 0.9, Vector3(0.0, chamber_cy, hz + 0.05), steel, "z")
	# Pressure gauge & emergency pull cord safety switch
	var gauge := _cyl(p, 0.09, 0.09, 0.04, Vector3(hx * 0.92, chamber_cy + 0.35, hz * 0.92), steel, "x")
	var dial := _cyl(p, 0.075, 0.075, 0.01, Vector3(hx * 0.945, chamber_cy + 0.35, hz * 0.92), _mat(Color(0.95, 0.95, 0.95), ghost), "x")
	# Red emergency stop pull-cord bar across maintenance access
	var estop_mat := _mat(Color(0.85, 0.12, 0.12), ghost, 0.3, 0.4)
	_box(p, Vector3(0.03, 0.03, size.z * 0.95), Vector3(hx * 0.95, chamber_cy - 0.2, 0.0), estop_mat)

	# Drive motor + V-belt guard on the -X side of the chamber.
	_motor_unit(p, 0.5, size.z * 0.5, Vector3(-hx * 1.02, chamber_cy, 0.0), "x", ghost)
	_guard(p, Vector3(size.x * 0.2, chamber_h * 0.6, size.z * 0.3),
		Vector3(-hx * 0.78, chamber_cy, hz * 0.2), ghost)

	# ── DISCHARGE CONVEYOR — dead-centre under the shredder, along Z ──────────
	var conv_w : float = 1.0
	var conv_y0 : float = 0.75            # deck height under the chamber
	var level_z0 : float = -hz            # starts under the far (-Z) edge
	var level_z1 : float = hz + 1.0       # level until 1 m past the +Z edge
	var level_len : float = level_z1 - level_z0
	var level_cz : float = (level_z0 + level_z1) * 0.5
	_box(p, Vector3(conv_w, 0.12, level_len), Vector3(0.0, conv_y0, level_cz), belt_mat)
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(0.05, 0.18, level_len),
			Vector3(float(sx) * conv_w * 0.5, conv_y0 + 0.09, level_cz), steel)
	# 35° incline up to ~4.5 m, feeding the bunker at the far end.
	var top_y : float = 4.5
	var rise : float = top_y - conv_y0
	var ang : float = deg_to_rad(35.0)
	var run : float = rise / tan(ang)
	var slope_len : float = rise / sin(ang)
	var inc_cz : float = level_z1 + run * 0.5
	var inc_cy : float = conv_y0 + rise * 0.5
	var inc := _box(p, Vector3(conv_w, 0.12, slope_len), Vector3(0.0, inc_cy, inc_cz), belt_mat)
	inc.rotation.x = -ang
	for sx in [-1.0, 1.0]:
		var r := _box(p, Vector3(0.05, 0.18, slope_len),
			Vector3(float(sx) * conv_w * 0.5, inc_cy + 0.09, inc_cz), steel)
		r.rotation.x = -ang
	# Conveyor support legs + head pulley.
	_box(p, Vector3(0.12, conv_y0, 0.12), Vector3(0.0, conv_y0 * 0.5, level_z1 - 0.2), steel)
	var top_z : float = level_z1 + run
	_box(p, Vector3(0.16, top_y, 0.16), Vector3(0.0, top_y * 0.5, top_z - 0.25), steel)
	_cyl(p, 0.2, 0.2, conv_w + 0.12, Vector3(0.0, top_y, top_z), steel, "x")

# ── Shredder 2 (compact fine shredder): smaller, faster, single rotor ─────────
static func _m_shredder_2(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# Operator 2026-07-14: the real Shredder 2 looks like Shredder 1 (dark blue,
	# dirty), just a bit smaller — NOT the compact red "Lindner Polaris" box the
	# placeholder showed. Reuse the Shredder-1 geometry at this (smaller) size with
	# the blue body colour, then add a "SCHINDLER'S" name stencil. The global dirty
	# filter (_mat) makes the blue read as worn, not brand-new. wide_hopper=false
	# drops the wider top hopper tier (operator: "halve the top grey part").
	_m_shredder_1(p, size, color, ghost, false)
	if ghost:
		return
	# Nameplate on the +X chamber face (mirror of Shredder-1's chamber geometry:
	# leg_top 1.3, chamber_h = size.y*0.42, wall at x = ±size.x*0.45).
	var chamber_cy : float = 1.3 + (size.y * 0.42) * 0.5
	# The +X chamber wall is a 0.18 m-thick slab centred at x = size.x*0.45, so its
	# OUTER face is at size.x*0.45 + 0.09. Mount the nameplate proud of THAT (the
	# old plate was buried inside the wall → invisible).
	var plate_x : float = size.x * 0.45 + 0.10
	var grey_bg := _mat(Color(0.55, 0.57, 0.60), ghost, 0.3, 0.6)
	_box(p, Vector3(0.02, 0.26, 1.35), Vector3(plate_x, chamber_cy, 0.0), grey_bg)
	var lbl := _stencil_label(p, "SCHINDLER'S", Vector3(1.20, 0.20, 0.015), "+X")
	lbl.position = Vector3(plate_x + 0.02, chamber_cy, 0.0)

	# Hydraulic screen cradle drop cylinder under chamber
	var steel_mat := _mat(_STEEL, ghost, 0.5, 0.45)
	var dark_mat := _mat(_DARK, ghost, 0.4, 0.6)
	_cyl(p, 0.08, 0.08, 0.7, Vector3(size.x * 0.35, 1.0, -size.z * 0.35), dark_mat, "y")
	_cyl(p, 0.04, 0.04, 0.5, Vector3(size.x * 0.35, 0.75, -size.z * 0.35), steel_mat, "y")

	# Interactive hinged inspection hatch door on +X wall
	var _shred2_hatch := _interactive_hatch(p, Vector3(0.03, 0.45, 0.45),
		Vector3(plate_x, chamber_cy - 0.4, 0.4), "Shredder 2 Inspection Door", 100.0, 1.0, steel_mat, ghost)
	if not ghost:
		_box(_shred2_hatch, Vector3(0.02, 0.22, 0.22),
			Vector3(0.02, 0.0, -0.10), MaterialPalette.mat_glass_inspection_grime())
		_box(_shred2_hatch, Vector3(0.03, 0.06, 0.12), Vector3(0.03, 0.0, 0.16), dark_mat)

	# Digital rotor load / ammeter gauge
	_box(p, Vector3(0.04, 0.16, 0.20), Vector3(plate_x + 0.01, chamber_cy + 0.35, -0.4), dark_mat)
	_box(p, Vector3(0.01, 0.10, 0.14), Vector3(plate_x + 0.032, chamber_cy + 0.35, -0.4), _mat(Color(0.1, 0.85, 0.2), ghost))

# ── Inclined transport belt (45°, 8 m rise) ──────────────────────────────────
##
## Sized 1 × 8.5 × 8.5 (in local X/Y/Z). The belt runs from local (0,0,0) up
## diagonally to (0, 8, 8) — a 45° incline that climbs 8 m vertically over 8 m
## of horizontal travel. Use to bring Shredder 2's flake stream up to the small
## feed hopper that drops onto the washing-line belts.
static func _m_inclined_belt(p: Node3D, _size: Vector3, _color: Color, ghost: bool) -> void:
	# Migrated to BeltBuilder. The diagonal deck_kind path in BeltBuilder.build_deck
	# is not yet fully implemented (it builds a flat horizontal box rather than the
	# Y+Z rotated diagonal one this belt needs), so all visual geometry is delivered
	# through a single `extras` callable that replays the legacy build verbatim.
	# Standard pipeline parts are forced to no-op via the spec (rollers/side_rails/
	# motor/chute = none, has_legs = false, deck_width_frac = 0, deck_thickness_m = 0)
	# so build_internal only emits a degenerate (zero-volume, invisible) deck-skin
	# box plus the geometry our extras callable spawns. Visual result is byte-
	# equivalent to the pre-migration function.
	#
	# `p` here is the Model Node3D (build_node passes the Model child, NOT the
	# body). build_node already tags the body — _BELT_IDS membership at line 863
	# adds 'belt' group, belt_speed meta, and BeltSurface script to the StaticBody3D.
	# So we use build_internal() directly (NOT build()), which builds geometry only
	# without re-running tagging or stamping placeable_id/placed_object onto the
	# Model node (which would duplicate the body's tagging).
	var spec : Dictionary = BeltBuilder.make_spec()
	spec.deck_kind = "diagonal"
	spec.rise = 8.0
	spec.horizontal_run = 8.0
	spec.length_override_m = sqrt(8.0 * 8.0 + 8.0 * 8.0)  # ~11.31 m diagonal
	# Suppress standard pipeline parts — the extras callable below builds everything.
	spec.deck_width_frac = 0.0
	spec.deck_thickness_m = 0.0
	spec.deck_scroll = 0.0
	spec.rollers = "none"
	spec.side_rails = "none"
	spec.has_legs = false
	spec.motor = "none"
	spec.chute = "none"
	# Legacy verbatim geometry — diagonal deck + rails, A-frame legs + cross-braces,
	# spinning end rollers, top motor, and bottom catch-pan.
	# Callable must reference the class (not `self` — this is a static func, so
	# `self` is null). PlaceableCatalog._inclined_belt_extras is itself static.
	spec.extras = [Callable(PlaceableCatalog, "_inclined_belt_extras")]
	BeltBuilder.build_internal(p, "inclined_belt_8m", _size, spec, ghost)

# Extras callable for inclined_belt_8m — invoked by BeltBuilder after standard
# geometry. Signature: (p, deck_root, size, spec, ghost). We don't need
# deck_root / size / spec here because the legacy build uses hardcoded 8 m
# rise / 8 m run; we just reproduce it as-was.
static func _inclined_belt_extras(p: Node3D, _deck_root: Node3D, _size: Vector3, _spec: Dictionary, ghost: bool) -> void:
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var rise := 8.0
	var horiz := 8.0
	var diag := sqrt(rise * rise + horiz * horiz)    # ~11.31 m
	var angle := atan2(rise, horiz)                  # PI/4
	var mid := Vector3(0.0, rise * 0.5, horiz * 0.5)
	# Diagonal belt deck — rotated about local X so its long axis lies along
	# the (Y+Z) diagonal. Inner span = 0.85 m wide. Textured scrolling material
	# so the inclined belt visibly moves when it's running.
	var deck := _box(p, Vector3(0.85, 0.06, diag), mid, dark)
	deck.rotation = Vector3(angle, 0.0, 0.0)
	if not ghost:
		deck.material_override = make_belt_material(0.5, Vector2(1.0, diag * 0.5))
	# Side rails
	for sx in [-1.0, 1.0]:
		var rail := _box(p, Vector3(0.06, 0.18, diag), \
			mid + Vector3(sx * 0.42, 0.10, 0.0), steel)
		rail.rotation = Vector3(angle, 0.0, 0.0)
	# End rollers (axis along X, crossing the belt). D4 — spin at v/r.
	var ib_rpm : float = (_BELT_CARRY_SPEED * 60.0) / (TAU * 0.22)
	_spinning_cyl(p, 0.22, 0.22, 0.95, Vector3(0.0, 0.25, 0.25), dark, "x", Vector3.RIGHT, ghost, ib_rpm)               # bottom roller
	_spinning_cyl(p, 0.22, 0.22, 0.95, Vector3(0.0, rise - 0.25, horiz - 0.25), dark, "x", Vector3.RIGHT, ghost, ib_rpm)  # top roller
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
# ── Small feed hopper with interactive slide gate & viewing window ──────────
static func _m_feed_hopper(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.45)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)

	# Conical funnel
	_cyl(p, size.x * 0.48, size.x * 0.12, size.y * 0.78,
		Vector3(0.0, size.y * 0.5, 0.0), steel)

	# Transparent grimy sight strip on funnel front
	_box(p, Vector3(size.x * 0.22, size.y * 0.35, 0.02),
		Vector3(0.0, size.y * 0.55, size.x * 0.30), MaterialPalette.mat_glass_inspection_grime())

	# Interactive slide-gate cutoff valve below outlet
	var _gate := _interactive_hatch(p, Vector3(0.25, 0.03, 0.25),
		Vector3(0.0, size.y * 0.18, 0.0), "Hopper Slide Gate", 75.0, 1.0, dark, ghost)

	# Two angled flanges
	var flange_h := 0.20
	var flange_len := 0.35
	for sx in [-1.0, 1.0]:
		var flange := _box(p, Vector3(0.04, flange_h, flange_len),
			Vector3(sx * 0.10, size.y * 0.15, size.z * 0.15), steel)
		flange.rotation.z = sx * deg_to_rad(28.0)

	# Catch tray & legs
	_box(p, Vector3(size.x * 0.45, 0.04, size.z * 0.45),
		Vector3(0.0, size.y * 0.04, size.z * 0.1), dark)
	var _hopper_leg_h := size.y * 0.1
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(0.06, _hopper_leg_h, 0.06),
				Vector3(sx * size.x * 0.35, _hopper_leg_h * 0.5, sz * size.z * 0.35), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", _hopper_leg_h)

# ── SGA opener drum: large inclined trommel + interactive fines cleanout hatch ─
static func _m_sga_drum(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.4)
	var tilt := deg_to_rad(6.0)
	_legs(p, size, size.y * 0.2, dark)

	# Rotating trommel drum
	var drum_rm := _spinning_tube(p, size.x * 0.4, size.z * 0.84, Vector3(0.0, size.y * 0.62, 0.0), shell, PI / 2.0 + tilt, Vector3.BACK, ghost, 16.0)
	for sz in [-0.25, 0.25]:
		var band_pos : Vector3 = Vector3(0.0, -sz * sin(tilt) * size.z, sz * size.z) if not ghost \
			else Vector3(0.0, size.y * 0.62 - sz * sin(tilt) * size.z, sz * size.z)
		_tube(drum_rm, size.x * 0.43, 0.12, band_pos, steel, PI / 2.0 + tilt)

	# Feed hopper at high (-Z) end
	_cyl(p, size.x * 0.34, size.x * 0.14, size.y * 0.4, Vector3(0.0, size.y * 0.92, -size.z * 0.4), dark)

	# Fines screen tray with interactive cleanout flap
	_box(p, Vector3(size.x * 0.72, size.y * 0.16, size.z * 0.72), Vector3(0.0, size.y * 0.28, 0.0), dark)
	var _sga_flap := _interactive_hatch(p, Vector3(size.x * 0.45, size.y * 0.12, 0.02),
		Vector3(0.0, size.y * 0.28, size.z * 0.37), "SGA Fines Tray Door", 90.0, 1.0, steel, ghost)

	# Drive at low (+Z) end
	_motor_unit(p, size.x * 0.16, size.z * 0.22, Vector3(size.x * 0.42, size.y * 0.45, size.z * 0.4), "z", ghost)

# ── overband metal separator: belt + suspended magnet gantry + tramp-metal box ─
static func _m_metal_belt(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var spec : Dictionary = BeltBuilder.make_spec()
	spec.deck_kind = "none"
	spec.deck_width_frac = 0.0
	spec.deck_thickness_m = 0.0
	spec.deck_scroll = 0.0
	spec.rollers = "none"
	spec.side_rails = "none"
	spec.has_legs = false
	spec.motor = "none"
	spec.chute = "none"
	spec.belt_speed_mps = _BELT_CARRY_SPEED
	spec.extras = [Callable(PlaceableCatalog, "_metal_belt_extras").bind(color)]
	BeltBuilder.build_internal(p, "metal_belt", size, spec, ghost)

static func _metal_belt_extras(p: Node3D, _deck_root: Node3D, size: Vector3, _spec: Dictionary, ghost: bool, color: Color) -> void:
	var dark := _mat(_DARK, ghost, 0.3, 0.7)
	var steel := _mat(color, ghost, 0.5, 0.45)
	var magnet := _mat(Color(0.18, 0.20, 0.24), ghost, 0.55, 0.45)
	var hz := size.z * 0.45
	var deck_y := size.y * 0.45
	_legs(p, size, deck_y, steel)
	_spinning_cyl(p, size.y * 0.12, size.y * 0.12, size.x * 0.9, Vector3(0.0, deck_y, hz), dark, "x", Vector3.RIGHT, ghost, 45.0)
	_spinning_cyl(p, size.y * 0.12, size.y * 0.12, size.x * 0.9, Vector3(0.0, deck_y, -hz), dark, "x", Vector3.RIGHT, ghost, 45.0)
	_box(p, Vector3(size.x * 0.82, 0.05, size.z * 0.9), Vector3(0.0, deck_y + size.y * 0.12, 0.0), dark)
	_box(p, Vector3(0.08, size.y * 0.42, 0.08), Vector3(size.x * 0.4, deck_y + size.y * 0.4, 0.0), steel)
	_box(p, Vector3(0.08, size.y * 0.42, 0.08), Vector3(-size.x * 0.4, deck_y + size.y * 0.4, 0.0), steel)
	_box(p, Vector3(size.x * 0.6, size.y * 0.2, size.z * 0.4), Vector3(0.0, deck_y + size.y * 0.58, 0.0), magnet)
	_box(p, Vector3(size.x * 0.5, size.y * 0.28, size.z * 0.14), Vector3(0.0, deck_y * 0.6, hz * 0.92), steel)

# ── ZSS / water tank: vertical cylindrical tank with interactive top manhole ──
static func _m_zss_water(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.4)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)

	_cyl(p, size.x * 0.45, size.x * 0.45, size.y * 0.8, Vector3(0.0, size.y * 0.5, 0.0), shell)
	_cyl(p, size.x * 0.46, size.x * 0.46, size.y * 0.04, Vector3(0.0, size.y * 0.92, 0.0), steel)
	_cyl(p, size.x * 0.47, size.x * 0.47, size.y * 0.1, Vector3(0.0, size.y * 0.05, 0.0), dark)

	# Interactive top inspection manhole hatch
	var _zss_manhole := _interactive_hatch(p, Vector3(0.38, 0.04, 0.38),
		Vector3(size.x * 0.18, size.y * 0.94, 0.0), "ZSS Tank Top Manway", 85.0, 1.0, steel, ghost)

	# Transparent vertical level sight gauge tube on side
	_cyl(p, 0.025, 0.025, size.y * 0.70, Vector3(size.x * 0.46, size.y * 0.50, 0.0), MaterialPalette.mat_glass_sight_gauge(), "y")

	# Recirculation pump & discharge stub
	_box(p, Vector3(size.x * 0.3, size.y * 0.18, size.z * 0.3), Vector3(size.x * 0.5, size.y * 0.12, 0.0), steel)
	_cyl(p, size.x * 0.06, size.x * 0.06, size.x * 0.5, Vector3(size.x * 0.6, size.y * 0.3, 0.0), steel, "x")

# ── Kleine LA: open-top water basin with interactive ball valve lever ──
static func _m_kleine_la(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var red   := _mat(Color(0.85, 0.15, 0.12), ghost, 0.2, 0.5)
	var water := _mat(Color(0.32, 0.40, 0.34, 0.78), ghost, 0.0, 0.2)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var wt := 0.05

	_box(p, Vector3(size.x, 0.06, size.z), Vector3(0.0, 0.03, 0.0), dark)
	_box(p, Vector3(wt, size.y, size.z), Vector3(-hx + wt * 0.5, size.y * 0.5, 0.0), shell)
	_box(p, Vector3(wt, size.y, size.z), Vector3( hx - wt * 0.5, size.y * 0.5, 0.0), shell)
	_box(p, Vector3(size.x, size.y, wt), Vector3(0.0, size.y * 0.5, -hz + wt * 0.5), shell)
	_box(p, Vector3(size.x, size.y, wt), Vector3(0.0, size.y * 0.5,  hz - wt * 0.5), shell)
	_box(p, Vector3(size.x - wt * 2.0, 0.03, size.z - wt * 2.0), Vector3(0.0, size.y - 0.04, 0.0), water)

	# Outlet stub + interactive drain ball valve lever
	_cyl(p, 0.05, 0.05, 0.16, Vector3(-hx - 0.08, 0.25, 0.0), dark, "x")
	_cyl(p, 0.065, 0.065, 0.03, Vector3(-hx - 0.17, 0.25, 0.0), dark, "x")
	var _la_valve := _interactive_hatch(p, Vector3(0.04, 0.03, 0.16),
		Vector3(-hx - 0.10, 0.33, 0.0), "Kleine LA Drain Valve", 90.0, 1.0, red, ghost)

# ── Tankje tussen extruders: small raised tank with interactive inspection lid ─────
static func _m_tankje_extruders(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.5, 0.45)

	var pump_size := Vector3(0.8, 0.9, 1.3)
	var pump_root := Node3D.new()
	pump_root.name = "TankjePomp"
	p.add_child(pump_root)
	_m_pump(pump_root, pump_size, color, ghost)

	var stand_top := 1.0
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(0.08, stand_top, 0.08),
				Vector3(float(sx) * (hx - 0.06), stand_top * 0.5, float(sz) * (hz - 0.06)), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", stand_top)

	var tank_h : float = size.y - stand_top - 0.05
	_box(p, Vector3(size.x * 0.94, 0.05, size.z * 0.94), Vector3(0.0, stand_top + 0.025, 0.0), steel)
	_box(p, Vector3(size.x * 0.9, tank_h, size.z * 0.9),
		Vector3(0.0, stand_top + 0.05 + tank_h * 0.5, 0.0), shell)

	# Interactive top inspection lid with transparent sight window
	var _tank_lid := _interactive_hatch(p, Vector3(size.x * 0.42, 0.04, size.z * 0.42),
		Vector3(0.0, size.y + 0.02, 0.0), "Extruder Tank Inspection Lid", 85.0, 1.0, steel, ghost)
	if not ghost:
		_box(_tank_lid, Vector3(size.x * 0.22, 0.02, size.z * 0.22),
			Vector3(-size.x * 0.20, 0.02, 0.0), MaterialPalette.mat_glass_inspection_grime())

	_cyl(p, 0.05, 0.05, 0.35, Vector3(0.0, size.y + 0.12, -size.z * 0.25), steel)
	_cyl(p, 0.05, 0.05, 0.40, Vector3(size.x * 0.55, 0.45, 0.0), steel, "x")
	_cyl(p, 0.045, 0.045, stand_top, Vector3(0.0, stand_top * 0.5 + 0.05, hz * 0.75), steel)

# ── ballistic separator: inclined paddle housing + feed hopper + 2 discharge lips
# ── Ballistic Separator: inclined eccentric sorting paddles with interactive inspection door ───
static func _m_ballistic(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var body_mat := _mat(color, ghost, 0.35, 0.5)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var paddle_mat := _mat(Color(0.25, 0.35, 0.45), ghost, 0.4, 0.6)
	var leg_h : float = size.y * 0.28
	_legs(p, size, leg_h, dark)
	_box(p, Vector3(size.x * 0.92, 0.08, size.z * 0.92), Vector3(0.0, leg_h, 0.0), steel)

	# Main inclined sorting chamber housing
	var house_cy : float = leg_h + size.y * 0.38
	var house := _box(p, Vector3(size.x * 0.84, size.y * 0.52, size.z * 0.86), Vector3(0.0, house_cy, 0.0), body_mat)
	house.rotation = Vector3(deg_to_rad(-12.0), 0.0, 0.0)

	# Interactive top inspection hatch with transparent grimy viewing window
	var bal_hatch := _interactive_hatch(p, Vector3(size.x * 0.42, 0.04, size.z * 0.42),
		Vector3(0.0, house_cy + size.y * 0.28, 0.0), "Ballistic Separator Inspection Door", 100.0, 1.0, steel, ghost)
	if not ghost:
		_box(bal_hatch, Vector3(size.x * 0.22, 0.02, size.z * 0.22),
			Vector3(-size.x * 0.21, 0.02, 0.0), MaterialPalette.mat_glass_inspection_grime())
		# Crankshaft driven eccentric sorting paddles visible inside
		var crank_rm := _spinning_cyl(p, size.x * 0.04, size.x * 0.04, size.x * 0.76, Vector3(0.0, house_cy, 0.0), steel, "x", Vector3.RIGHT, ghost, 60.0)
		for pi in 4:
			var px : float = -size.x * 0.30 + float(pi) * (size.x * 0.20)
			_box(crank_rm, Vector3(0.14, 0.02, size.z * 0.65), Vector3(px, (float(pi % 2) - 0.5) * 0.08, 0.0), paddle_mat)

	# Feed hopper at high (-Z) end
	_cyl(p, size.x * 0.30, size.x * 0.16, size.y * 0.38, Vector3(0.0, size.y * 0.95, -size.z * 0.34), dark)

	# Dual discharge chutes at low (+Z) end: 2D light films climb upwards/over, 3D heavies roll downwards/under
	_box(p, Vector3(size.x * 0.74, 0.06, size.z * 0.22), Vector3(0.0, size.y * 0.82, size.z * 0.44), steel)
	_box(p, Vector3(size.x * 0.74, 0.06, size.z * 0.22), Vector3(0.0, size.y * 0.44, size.z * 0.42), dark)

	# Heavy drive motor + V-belt guard on +X flank
	_motor_unit(p, size.x * 0.16, size.z * 0.22, Vector3(size.x * 0.44, house_cy, -size.z * 0.25), "z", ghost)

# ── Windsifter (zig-zag air classifier): rising duct + transparent window + blower ────
static func _m_windsifter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.4, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var flake_mat := _mat(Color(0.88, 0.85, 0.76), ghost, 0.05, 0.8)

	_legs(p, size, size.y * 0.16, dark)

	# Tall rising zig-zag classification channel
	var col_cy : float = size.y * 0.52
	_box(p, Vector3(size.x * 0.52, size.y * 0.74, size.z * 0.52), Vector3(0.0, col_cy, 0.0), shell)

	# Transparent grimy observation window along the zig-zag channel (+X side)
	var win_h : float = size.y * 0.50
	_box(p, Vector3(0.02, win_h, size.z * 0.32), Vector3(size.x * 0.265, col_cy, 0.0), MaterialPalette.mat_glass_inspection_grime())
	_box(p, Vector3(0.04, win_h + 0.06, size.z * 0.36), Vector3(size.x * 0.26, col_cy, 0.0), dark)

	if not ghost:
		# Floating light-fraction film flakes swirling upwards in the air stream
		for fi in 5:
			var fy : float = col_cy - win_h * 0.35 + float(fi) * (win_h * 0.18)
			var fz : float = (float(fi % 3) - 1.0) * (size.z * 0.08)
			_box(p, Vector3(0.04, 0.03, 0.05), Vector3(size.x * 0.18, fy, fz), flake_mat)

	# Infeed chute at -Z
	_box(p, Vector3(size.x * 0.42, size.y * 0.18, size.z * 0.24), Vector3(0.0, size.y * 0.42, -size.z * 0.36), dark)

	# Heavies drop-out hopper at bottom with interactive clean-out hatch
	_cyl(p, size.x * 0.24, size.x * 0.12, size.y * 0.22, Vector3(0.0, size.y * 0.14, size.z * 0.18), dark)
	var ws_hatch := _interactive_hatch(p, Vector3(0.24, 0.20, 0.03),
		Vector3(0.0, size.y * 0.14, size.z * 0.30), "Windsifter Heavies Cleanout Door", 95.0, 1.0, steel, ghost)

	# Top light-fraction discharge duct to cyclone
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.50, Vector3(0.0, size.y * 0.86, size.z * 0.30), steel, "z")

	# Heavy centrifugal blower at the base on -X side
	_cyl(p, size.y * 0.16, size.y * 0.16, size.x * 0.38, Vector3(-size.x * 0.38, size.y * 0.22, 0.0), dark, "x")
	_motor_unit(p, size.y * 0.10, size.x * 0.18, Vector3(-size.x * 0.55, size.y * 0.22, 0.0), "x", ghost)

# ── TITECH NIR optical sorter: accel belt + scanner hood + blue sensor + valves ─
## TOMRA Autosort / TITECH NIR sorter — modelled from operator photos of the
## real machine on the line. Layout along Z (origin at machine centre):
##   Z- end : acceleration conveyor (≈ 55 % of total length, narrower than X)
##   Z 0    : main scanner hood (orange) straddles the belt; small front sensor
##            box just before it; camera apertures visible on the front face
##   Z+ end : black ejector-valve housing + compressed-air manifold + control
##            cabinet with red E-stop on the side, then a dark discharge chute
## The TITECH variant is the same chassis 60 % wider (caller passes a bigger
## size.x). All proportions scale with `size` so both ids share this code.
static func _m_nir_sorter(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# ── Palette ────────────────────────────────────────────────────────────
	var frame      := _mat(_DARK, ghost, 0.45, 0.55)                          # frame & legs
	var belt       := _mat(Color(0.08, 0.08, 0.10), ghost, 0.85, 0.30)        # near-black belt
	var orange     := _mat(color, ghost, 0.25, 0.60)                          # TOMRA orange shells
	var steel      := _mat(_STEEL, ghost, 0.55, 0.40)                         # rollers, manifold pipe
	var dark_panel := _mat(Color(0.10, 0.11, 0.13), ghost, 0.45, 0.55)        # ejector cabinet, chute
	var blue_lens  := _mat(Color(0.06, 0.18, 0.36), ghost, 0.05, 0.20)        # NIR sensor slit
	var red_estop  := _mat(Color(0.82, 0.10, 0.10), ghost, 0.30, 0.40)        # E-stop button

	# ── Layout constants ──────────────────────────────────────────────────
	# The ORANGE apparatus (scanner hood / ejector / chute) stays keyed to `size`
	# so it keeps the proportions the operator approved. The acceleration BELT,
	# however, is decoupled: it's ~5× longer than the apparatus and extends in
	# the -Z direction (AWAY from the orange, into the feed approach), so the
	# whole machine reads as a long conveyor with the sorter mounted at the far
	# (+Z) end — matching the real TITECH / TOMRA install.
	var belt_w     := size.x * 0.80              # belt fills most of the width; housing/valve block sticks ~0.5 m proud each side (TITECH belt = 4 m at size.x = 5 m)
	var deck_y     := size.y * 0.42              # belt top surface
	var feed_z0    := -size.z * 0.50             # feed-end (Z-) extreme of the apparatus bbox
	var feed_len   := size.z * 0.55              # (legacy apparatus anchor span)
	# Apparatus anchored at the +Z portion exactly as before.
	var scan_cz    := feed_z0 + feed_len + size.z * 0.04
	var ejector_cz := feed_z0 + feed_len + size.z * 0.20
	var chute_cz   := size.z * 0.50 - size.z * 0.10
	# Belt: discharge end meets the scanner; feed end runs far into -Z.
	var belt_discharge_z := feed_z0 + feed_len            # junction with the scanner
	var belt_len         := feed_len * 5.0                # 5× longer than before
	var belt_cz          := belt_discharge_z - belt_len * 0.5

	# ── 1. ACCELERATION BELT (long, extends away from the orange apparatus) ──
	# Belt deck (the visible black surface)
	_box(p, Vector3(belt_w, 0.05, belt_len),
		Vector3(0.0, deck_y, belt_cz), belt)
	# Walkable collider for the FULL belt — build_node's bounding-box collider only
	# spans the catalog `size`, but the acceleration belt extends ~5x beyond it, so
	# without this you fall through most of the belt and other machines' leg raycasts
	# (extend_machine_legs) can't see it. #67
	if not ghost:
		var belt_col := CollisionShape3D.new()
		var belt_box := BoxShape3D.new()
		belt_box.size = Vector3(belt_w, 0.4, belt_len)
		belt_col.shape = belt_box
		belt_col.position = Vector3(0.0, deck_y - 0.2, belt_cz)
		p.add_child(belt_col)
	# Side rails left + right
	var rail_h := size.y * 0.10
	_box(p, Vector3(0.05, rail_h, belt_len),
		Vector3(-belt_w * 0.5 - 0.025, deck_y + rail_h * 0.5, belt_cz), frame)
	_box(p, Vector3(0.05, rail_h, belt_len),
		Vector3( belt_w * 0.5 + 0.025, deck_y + rail_h * 0.5, belt_cz), frame)
	# End rollers (visible cylinders at both ends, axis X) — spinning drums driving
	# the acceleration belt. Both tagged comp "belt" so one slider turns both.
	var roller_r := size.y * 0.06
	var nir_drum_a := _spinning_cyl(p, roller_r, roller_r, belt_w + 0.08,
		Vector3(0.0, deck_y - roller_r * 0.3, belt_cz - belt_len * 0.5 + 0.04), steel, "x", Vector3.RIGHT, ghost)
	var nir_drum_b := _spinning_cyl(p, roller_r, roller_r, belt_w + 0.08,
		Vector3(0.0, deck_y - roller_r * 0.3, belt_cz + belt_len * 0.5 - 0.04), steel, "x", Vector3.RIGHT, ghost)
	if not ghost:
		nir_drum_a.set_meta("comp", "belt")
		nir_drum_b.set_meta("comp", "belt")
	# Drive motor + gearbox, mounted off the +X side at the far feed (-Z) end
	_motor_unit(p, size.y * 0.10, size.x * 0.32,
		Vector3(belt_w * 0.5 + size.x * 0.14, deck_y - roller_r * 0.4, belt_cz - belt_len * 0.5 + 0.05),
		"x", ghost)
	# Shaft-wrap visual — a thin cylinder coaxial with the DISCHARGE-end drum
	# (where fibrous material first contacts the metal shaft and starts winding
	# on). NirSorter.tick() drives diameter via set_shaft_wrap_visual(): hidden
	# at 0.0 (no wrap), grown from radius 0.04 → 0.10 at 1.0 (FULL_WRAP_G).
	# Parented under an internal anchor node so we can find it back by name and
	# so it never gets confused with the real drum cylinders. Built for both
	# real placements AND ghosts so the wrap state survives ghost→placeable
	# promotion without a rebuild.
	var shaft_wrap_anchor := Node3D.new()
	shaft_wrap_anchor.name = "ShaftWrapVisual"
	shaft_wrap_anchor.position = Vector3(0.0, deck_y - roller_r * 0.3, belt_cz + belt_len * 0.5 - 0.04)
	p.add_child(shaft_wrap_anchor)
	var wrap_mat := _mat(Color(0.55, 0.50, 0.40), ghost, 0.10, 0.85)  # grey-brown fibrous
	var wrap_mi := MeshInstance3D.new()
	wrap_mi.name = "wrap_mesh"
	var wrap_cm := CylinderMesh.new()
	wrap_cm.top_radius = 0.04
	wrap_cm.bottom_radius = 0.04
	wrap_cm.height = belt_w + 0.06
	wrap_cm.radial_segments = 16
	wrap_mi.mesh = wrap_cm
	wrap_mi.material_override = wrap_mat
	# Rotate the cylinder onto the X axis to match the drum it wraps.
	wrap_mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	wrap_mi.visible = false
	shaft_wrap_anchor.add_child(wrap_mi)
	# Stash references on the placement root so set_shaft_wrap_visual() can find
	# them in O(1) without descending the subtree on every tick.
	p.set_meta("shaft_wrap_anchor", shaft_wrap_anchor)
	p.set_meta("shaft_wrap_mesh",   wrap_mi)

	# ── 2. ADJUSTABLE LEGS WITH FOOT PADS ─────────────────────────────────
	# Legs spread evenly along the LONG belt + one pair under the ejector cabinet.
	var legs_z := PackedFloat32Array([
		belt_cz - belt_len * 0.44,
		belt_cz - belt_len * 0.26,
		belt_cz - belt_len * 0.08,
		belt_cz + belt_len * 0.10,
		belt_cz + belt_len * 0.28,
		belt_cz + belt_len * 0.44,
		ejector_cz,
		chute_cz,
	])
	var leg_w := 0.08
	var leg_h := deck_y - 0.02
	var pad_w := 0.18
	for lz in legs_z:
		for sx in [-1.0, 1.0]:
			var x: float = float(sx) * belt_w * 0.45
			var lg := _box(p, Vector3(leg_w, leg_h, leg_w),
				Vector3(x, leg_h * 0.5, lz), steel)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_h)
			var pad := _box(p, Vector3(pad_w, 0.02, pad_w),
				Vector3(x, 0.01, lz), frame)
			pad.add_to_group("machine_foot")
			pad.set_meta("foot_y", 0.01)

	# ── 3. FRONT SMALL ORANGE SENSOR BOX (mounted on a bridge over the belt
	# just BEFORE the main scanner — the auxiliary sensor / illuminator). ─
	var front_box_z := belt_discharge_z - 0.45
	# Bridge crossbeam
	_box(p, Vector3(size.x * 0.75, size.y * 0.06, 0.05),
		Vector3(0.0, deck_y + size.y * 0.40, front_box_z), frame)
	# The small orange box, off-centre toward -X like in the photo
	_box(p, Vector3(size.x * 0.22, size.y * 0.30, size.z * 0.07),
		Vector3(-size.x * 0.10, deck_y + size.y * 0.28, front_box_z), orange)
	# Small window/aperture on the front of the box
	_box(p, Vector3(size.x * 0.10, size.y * 0.08, 0.02),
		Vector3(-size.x * 0.10, deck_y + size.y * 0.26, front_box_z + size.z * 0.04), blue_lens)

	# ── 4. MAIN ORANGE SCANNER HOOD ────────────────────────────────────────
	# Large box straddling the belt, with cameras facing down at the gap.
	_box(p, Vector3(size.x * 0.92, size.y * 0.34, size.z * 0.18),
		Vector3(0.0, deck_y + size.y * 0.36, scan_cz), orange)
	# NIR sensor strip / aperture on the underside facing the belt
	_box(p, Vector3(size.x * 0.78, 0.03, size.z * 0.08),
		Vector3(0.0, deck_y + size.y * 0.19, scan_cz), blue_lens)
	# Two camera bulges visible on the front face
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(size.x * 0.14, size.y * 0.10, size.z * 0.04),
			Vector3(sx * size.x * 0.22, deck_y + size.y * 0.32, scan_cz - size.z * 0.10), frame)
	# Top ridge cap (the visible darker top edge in the photo)
	_box(p, Vector3(size.x * 0.94, size.y * 0.03, size.z * 0.20),
		Vector3(0.0, deck_y + size.y * 0.53, scan_cz), frame)

	# ── 5. EJECTOR VALVE HOUSING (the dark cabinet immediately after the
	# scanner — contains the bank of compressed-air valves and nozzles). ─
	_box(p, Vector3(size.x * 0.88, size.y * 0.62, size.z * 0.20),
		Vector3(0.0, deck_y + size.y * 0.18, ejector_cz), dark_panel)
	# Lid cap
	_box(p, Vector3(size.x * 0.92, size.y * 0.04, size.z * 0.22),
		Vector3(0.0, deck_y + size.y * 0.51, ejector_cz), frame)
	# Interactive inspection door panel with grimy transparent window
	var ejector_door := _interactive_hatch(p, Vector3(size.x * 0.45, size.y * 0.44, 0.03),
		Vector3(0.0, deck_y + size.y * 0.18, ejector_cz + size.z * 0.10), "NIR Valve Inspection Door", 100.0, 1.0, dark_panel, ghost)
	if not ghost:
		_box(ejector_door, Vector3(size.x * 0.22, size.y * 0.20, 0.01),
			Vector3(-size.x * 0.225, 0.0, 0.01), MaterialPalette.mat_glass_inspection_grime())
		# Row of high-speed air blast nozzles visible inside the ejector
		for ni in 8:
			var nx : float = -size.x * 0.35 + float(ni) * (size.x * 0.10)
			_cyl(p, 0.015, 0.008, 0.08, Vector3(nx, deck_y + size.y * 0.14, ejector_cz), steel, "z")

	# ── 6. COMPRESSED-AIR MANIFOLD (visible piping at the base on the +X
	# side of the ejector, with a row of small distribution valves). ─────
	var manifold_y := deck_y * 0.55
	_cyl(p, 0.035, 0.035, size.z * 0.34,
		Vector3(belt_w * 0.5 + 0.05, manifold_y, ejector_cz), steel, "z")
	for i in range(5):
		var off := (float(i) - 2.0) * size.z * 0.05
		_box(p, Vector3(0.05, 0.10, 0.04),
			Vector3(belt_w * 0.5 + 0.06, manifold_y + 0.08, ejector_cz + off), steel)

	# ── 7. CONTROL CABINET WITH E-STOP (small box mounted near the ejector,
	# off the -X side) ──────────────────────────────────────────────────────
	var ctrl_x := -size.x * 0.45
	_box(p, Vector3(size.x * 0.10, size.y * 0.22, size.z * 0.06),
		Vector3(ctrl_x, deck_y + size.y * 0.10, ejector_cz + size.z * 0.04), frame)
	_cyl(p, 0.025, 0.025, 0.025,
		Vector3(ctrl_x - 0.025, deck_y + size.y * 0.16, ejector_cz + size.z * 0.07),
		red_estop, "x")
	# 3-tier status beacon tower (Green / Amber / Red) on top of control cabinet
	var pole_y := deck_y + size.y * 0.21
	_cyl(p, 0.015, 0.015, 0.35, Vector3(ctrl_x, pole_y + 0.175, ejector_cz + size.z * 0.04), steel, "y")
	_cyl(p, 0.035, 0.035, 0.06, Vector3(ctrl_x, pole_y + 0.26, ejector_cz + size.z * 0.04), _mat(Color(0.1, 0.9, 0.2), ghost), "y") # green
	_cyl(p, 0.035, 0.035, 0.06, Vector3(ctrl_x, pole_y + 0.33, ejector_cz + size.z * 0.04), _mat(Color(0.95, 0.7, 0.1), ghost), "y") # amber
	_cyl(p, 0.035, 0.035, 0.06, Vector3(ctrl_x, pole_y + 0.40, ejector_cz + size.z * 0.04), _mat(Color(0.9, 0.15, 0.15), ghost), "y") # red
	# Pneumatic filter regulator & gauge
	_cyl(p, 0.04, 0.04, 0.14, Vector3(belt_w * 0.5 + 0.14, manifold_y + 0.12, ejector_cz - 0.2), steel, "y")
	_cyl(p, 0.03, 0.03, 0.02, Vector3(belt_w * 0.5 + 0.18, manifold_y + 0.15, ejector_cz - 0.2), _mat(Color(0.95, 0.95, 0.95), ghost), "x")

	# ── 8. DISCHARGE CHUTE — angled dark housing at the +Z end ────────────
	var chute := _box(p, Vector3(size.x * 0.88, size.y * 0.55, size.z * 0.20),
		Vector3(0.0, deck_y * 0.55, chute_cz), dark_panel)
	chute.rotation = Vector3(deg_to_rad(-8.0), 0.0, 0.0)
	# Splitter divider visible at the very top of the chute
	_box(p, Vector3(size.x * 0.82, 0.03, size.z * 0.12),
		Vector3(0.0, deck_y + size.y * 0.02, chute_cz - size.z * 0.04), frame)

	# ── 9. POST-DISCHARGE: SEPARATOR WALL + ROLLING DRUM + REJECT BELT + ACCEPT
	# CATCH. Per operator: material leaves the main belt at the discharge edge.
	# REJECT falls straight down onto a perpendicular conveyor running under the
	# discharge (carries reject toward the camera / -X end of the row). GOOD
	# material gets pneumatically ejected by the nozzles, arcs FORWARD over the
	# reject conveyor + separator wall, and lands on a lower-level catch deck on
	# the far side (~1.5 m below the main belt). The separator wall has a slow
	# 5-RPM roller on top spinning CCW (toward the reject side) that nudges any
	# half-strength ejections that landed on the wall back into the reject. ──
	# Reject conveyor — perpendicular to the main belt, axis along X, sits below
	# the discharge edge so reject falls onto it. Belt material so it reads as
	# scrolling (toward -X = "toward the camera" per the photo POV).
	var rej_w     : float = size.x * 1.10
	var rej_d     : float = size.z * 0.18
	var rej_z     : float = chute_cz + size.z * 0.08
	var rej_y_top : float = deck_y * 0.30
	var rej_deck  : MeshInstance3D = _box(p, Vector3(rej_w, 0.05, rej_d),
		Vector3(0.0, rej_y_top, rej_z), belt)
	if not ghost:
		rej_deck.material_override = make_belt_material(0.6, Vector2(rej_w * 0.25, 1.0))
	# End rollers of the reject conveyor — slow spin, axis along Z, both tagged
	# so the rotation system drives them as one belt.
	var rej_roll_r : float = size.y * 0.05
	var rej_end_a := _spinning_cyl(p, rej_roll_r, rej_roll_r, rej_d + 0.04,
		Vector3(-rej_w * 0.5 + 0.04, rej_y_top - rej_roll_r * 0.3, rej_z),
		steel, "z", Vector3.BACK, ghost, 18.0)
	var rej_end_b := _spinning_cyl(p, rej_roll_r, rej_roll_r, rej_d + 0.04,
		Vector3( rej_w * 0.5 - 0.04, rej_y_top - rej_roll_r * 0.3, rej_z),
		steel, "z", Vector3.BACK, ghost, 18.0)
	if not ghost:
		rej_end_a.set_meta("comp", "reject_belt")
		rej_end_b.set_meta("comp", "reject_belt")
	# Reject conveyor side rails (-Z and +Z sides).
	for srz in [-1.0, 1.0]:
		_box(p, Vector3(rej_w, rej_roll_r * 1.0, 0.04),
			Vector3(0.0, rej_y_top + rej_roll_r * 0.5, rej_z + srz * (rej_d * 0.5 + 0.02)), frame)
	# Reject conveyor support legs (tagged machine_leg → reach the floor).
	for srx in [-1.0, 1.0]:
		var rlx : float = srx * rej_w * 0.42
		var rlg := _box(p, Vector3(0.07, rej_y_top - 0.02, 0.07),
			Vector3(rlx, (rej_y_top - 0.02) * 0.5, rej_z), frame)
		rlg.add_to_group("machine_leg")
		rlg.set_meta("leg_h", rej_y_top - 0.02)

	# Separator wall — a vertical steel plate spanning the belt width, between
	# the reject conveyor and the accept catch deck. Top edge ~30 cm above the
	# main belt deck so only properly-ejected material clears it.
	var wall_z : float = chute_cz + size.z * 0.20
	var wall_h : float = deck_y * 0.85               # rises ABOVE the main belt
	var wall_y : float = wall_h * 0.5
	_box(p, Vector3(size.x * 0.94, wall_h, 0.06),
		Vector3(0.0, wall_y, wall_z), frame)
	# 5-RPM CCW rotating drum mounted ON TOP of the separator wall. Axis along
	# X. CCW from the operator's POV (rolling "toward the left" = toward the
	# reject side, which is -Z in our frame) — Vector3.RIGHT base + the negative
	# direction gives that. Tagged `comp: separator_roller` so RPM is exposed.
	var drum_r : float = size.y * 0.08
	var drum_y : float = wall_h + drum_r * 0.85
	# Sign on Vector3.RIGHT controls spin direction. CCW viewed from +X means
	# the top surface moves toward -Z (i.e. back into the reject conveyor side).
	var sep_drum := _spinning_cyl(p, drum_r, drum_r, size.x * 0.96,
		Vector3(0.0, drum_y, wall_z), steel, "x", Vector3.LEFT, ghost, 5.0)
	if not ghost:
		sep_drum.set_meta("comp", "separator_roller")

	# Accept catch deck — a lower-level surface where ejected GOOD material
	# lands after arcing over the wall. Drops ~1.5 m below the main belt per
	# the operator. Stainless, slightly sloped toward the +Z far edge so the
	# material naturally migrates onto whatever downstream conveyor is placed
	# at the catch's discharge edge.
	# The operator describes the catch deck as ~1.5 m below the main belt, but the
	# machine sits on a flat floor at y=0 and deck_y is only ~1.0 m up, so a literal
	# 1.5 m drop puts the deck and its legs UNDERGROUND. Clamp the drop so the catch
	# deck always sits at least 0.25 m above the floor (still reads as a clear
	# lower-level catch relative to the main belt at deck_y ~ 1.0 m). #leg-fix
	var catch_y : float = maxf(deck_y - 1.50, 0.25)
	var catch_z : float = chute_cz + size.z * 0.42
	var catch_d : float = size.z * 0.30
	var catch_deck := _box(p, Vector3(size.x * 0.96, 0.06, catch_d),
		Vector3(0.0, catch_y, catch_z), steel)
	catch_deck.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)   # gentle slope toward +Z
	# Walkable collider so the player / next machine's leg-snap doesn't fall
	# through this lower deck.
	if not ghost:
		var catch_col := CollisionShape3D.new()
		var catch_box := BoxShape3D.new()
		catch_box.size = Vector3(size.x * 0.96, 0.2, catch_d)
		catch_col.shape = catch_box
		catch_col.position = Vector3(0.0, catch_y - 0.1, catch_z)
		p.add_child(catch_col)
	# Catch deck side rails so loose flake doesn't spill off the X-edges.
	for sxe in [-1.0, 1.0]:
		var crail := _box(p, Vector3(0.05, size.y * 0.10, catch_d),
			Vector3(sxe * size.x * 0.49, catch_y + size.y * 0.04, catch_z), frame)
		crail.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)
	# Four legs holding up the catch deck to the floor.
	for sxl in [-1.0, 1.0]:
		for szl in [-1.0, 1.0]:
			var cly : float = catch_y - 0.05
			var cl := _box(p, Vector3(0.10, cly, 0.10),
				Vector3(sxl * size.x * 0.42, cly * 0.5, catch_z + szl * catch_d * 0.40), frame)
			cl.add_to_group("machine_leg")
			cl.set_meta("leg_h", cly)

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
	# horizontal wash drum (axis Z) sitting in the trough — SPINS about Z
	_spinning_cyl(p, size.x * 0.32, size.x * 0.32, size.z * 0.82, Vector3(0.0, ty + size.y * 0.34, 0.0), shell, "z", Vector3.BACK, ghost, 28.0)
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
	var shell := _mat(color, ghost, 0.40, 0.45)
	var dark := _mat(_DARK, ghost, 0.45, 0.6)
	var steel := _mat(_STEEL, ghost, 0.65, 0.35)
	var flight := _mat(Color(0.78, 0.55, 0.16), ghost, 0.3, 0.5)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)
	var r := size.x * 0.46
	var leg_h := size.y * 0.14
	var signs: Array[float] = [-1.0, 1.0]

	# Support legs with foot plates
	for sx in signs:
		for sz in signs:
			var lg := _box(p, Vector3(0.16, leg_h, 0.16), Vector3(sx * r * 0.72, leg_h * 0.5, sz * r * 0.72), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", leg_h)
			_box(p, Vector3(0.26, 0.04, 0.26), Vector3(sx * r * 0.72, 0.02, sz * r * 0.72), steel)

	# Conical bottom + cylindrical body + short top dome
	_cyl(p, r, 0.16, size.y * 0.24, Vector3(0.0, leg_h + size.y * 0.12, 0.0), shell)
	_cyl(p, r, r, size.y * 0.46, Vector3(0.0, leg_h + size.y * 0.47, 0.0), shell)
	_cyl(p, r * 0.3, r, size.y * 0.08, Vector3(0.0, leg_h + size.y * 0.74, 0.0), shell)

	# Transparent vertical level sight-glass strip on +Z face
	var win_h : float = size.y * 0.42
	_box(p, Vector3(0.12, win_h + 0.04, 0.02), Vector3(0.0, leg_h + size.y * 0.47, r + 0.01), steel)
	_box(p, Vector3(0.08, win_h, 0.025), Vector3(0.0, leg_h + size.y * 0.47, r + 0.015), MaterialPalette.mat_glass_sight_gauge())

	# Interactive clean-out maintenance hatch on the bottom cone (-X side)
	var hatch_y : float = leg_h + size.y * 0.10
	var clean_hatch := _interactive_hatch(p, Vector3(0.04, 0.32, 0.32),
		Vector3(-r * 0.45, hatch_y, 0.0), "Mixing Silo Cleanout Hatch", 105.0, 1.0, steel, ghost)
	if not ghost:
		_box(clean_hatch, Vector3(0.02, 0.12, 0.04), Vector3(-0.02, 0.0, 0.12), yellow)

	# Top mixer drive gearmotor
	_motor_unit(p, size.x * 0.14, size.y * 0.18, Vector3(0.0, leg_h + size.y * 0.84, 0.0), "y", ghost)

	# Internal central mixing auger shaft with spinning flighting
	var mix_len : float = size.y * 0.65
	var mix_cy : float = leg_h + size.y * 0.40
	_spinning_auger(p, mix_len, Vector3(0.0, mix_cy, 0.0), size.x * 0.04, size.x * 0.14, steel, flight, ghost, 45.0, "mix_auger")

	# Bottom slide-gate discharge outlet under cone
	_cyl(p, 0.12, 0.12, size.y * 0.12, Vector3(0.0, leg_h * 0.5, 0.0), dark)
	_box(p, Vector3(0.35, 0.06, 0.35), Vector3(0.0, leg_h * 0.15, 0.0), steel)

	# Caged access ladder up the side (+X face)
	_caged_ladder(p, Vector3(r + 0.15, 0.0, 0.0), leg_h + size.y * 0.74, steel, ghost)

# ── Hoses & Air (visual placeables) ─────────────────────────────────────────
## Wall-mount hose reel ("haspel"): bracket + axle + drum + a stack of torus rings
## representing the coiled hose. `hose_r` is the hose tube radius (0.045 m for the
## thick yellow water hose; 0.025 m for the thin black water hose; 0.028 m for the
## red fire hose). A ball valve sits at the base (where the supply pipe joins the
## reel) and another at the loose hose-tip dangling off the side — both ball valves
## per the operator spec (open-a-little / open-a-lot).
static func _m_hose_reel(p: Node3D, size: Vector3, color: Color, ghost: bool, hose_r: float) -> void:
	var hose := _mat(color, ghost, 0.05, 0.7)
	var dark := _mat(_DARK, ghost, 0.55, 0.55)
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var brass := _mat(Color(0.76, 0.62, 0.20), ghost, 0.85, 0.30)
	var valve_red := _mat(Color(0.82, 0.18, 0.16), ghost, 0.2, 0.45)
	# Wall mount + bracket (the back plate that bolts to the wall + 2 arms).
	_box(p, Vector3(size.x * 0.85, size.y * 0.9, 0.05), Vector3(0.0, size.y * 0.5, -size.z * 0.45), dark)
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(0.06, 0.06, size.z * 0.7),
			Vector3(sx * size.x * 0.32, size.y * 0.5, -size.z * 0.10), steel)
	# Horizontal axle through the drum (axis along X, perpendicular to the wall — drum spins on it).
	var axle_y := size.y * 0.55
	_cyl(p, 0.035, 0.035, size.x * 0.7, Vector3(0.0, axle_y, 0.0), steel, "x")
	# Drum body (squat cylinder, axis along X).
	var drum_r := size.y * 0.30
	_cyl(p, drum_r, drum_r, size.x * 0.55, Vector3(0.0, axle_y, 0.0), dark, "x")
	# Coiled hose: stack many torus rings, each at a different X position along the
	# drum so they read as a thick coil. Rings sit JUST outside the drum diameter.
	var ring_outer := drum_r + hose_r * 1.1
	var ring_inner := drum_r + hose_r * 0.1
	var ring_count := int(round(size.x * 0.55 / (hose_r * 2.0)))
	ring_count = clampi(ring_count, 4, 14)
	var step := (size.x * 0.55) / float(ring_count)
	for i in ring_count:
		var rx := -size.x * 0.275 + step * (float(i) + 0.5)
		# Torus default axis is +Y; we want the loop's plane perpendicular to +X.
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = ring_inner
		tm.outer_radius = ring_outer
		# `rings` = slices around the main loop; 6 read as a literal hexagon.
		# Bumped high so each coil reads as a smooth round hose. `ring_segments`
		# is the tube cross-section roundness.
		tm.rings = 48
		tm.ring_segments = 24
		mi.mesh = tm
		mi.material_override = hose
		mi.position = Vector3(rx, axle_y, 0.0)
		mi.rotation.z = PI / 2.0
		p.add_child(mi)
	# Hand-crank on the +X side of the drum.
	_cyl(p, 0.04, 0.04, 0.14, Vector3(size.x * 0.36, axle_y, 0.0), steel, "x")
	_cyl(p, 0.025, 0.025, 0.10, Vector3(size.x * 0.43, axle_y - 0.10, 0.0), steel, "y")
	# Supply pipe + ball valve at the base where mains meets the spindle.
	_cyl(p, 0.04, 0.04, 0.30, Vector3(0.0, 0.30, -size.z * 0.35), steel, "y")
	_cyl(p, 0.06, 0.06, 0.10, Vector3(0.0, 0.18, -size.z * 0.35), brass, "y")    # ball-valve body
	_box(p, Vector3(0.18, 0.02, 0.02), Vector3(0.0, 0.18, -size.z * 0.35), valve_red)   # ball-valve handle
	# Loose hose tip hanging off the +X side (with the operator's end-of-hose valve).
	_cyl(p, hose_r, hose_r, 0.6, Vector3(size.x * 0.48, axle_y - 0.50, 0.0), hose, "y")
	_cyl(p, 0.045, 0.045, 0.08, Vector3(size.x * 0.48, axle_y - 0.85, 0.0), brass, "y")  # tip valve body
	_box(p, Vector3(0.14, 0.02, 0.02), Vector3(size.x * 0.48, axle_y - 0.85, 0.0), valve_red)  # tip valve handle
	_cyl(p, hose_r * 0.7, 0.012, 0.10, Vector3(size.x * 0.48, axle_y - 0.95, 0.0), steel, "y")  # nozzle taper
	# Attach the HoseReel controller — proximity prompt, base-valve cycle, nozzle
	# deploy/recall. The visual reel above is just chrome; the script makes it usable. #40
	if not ghost:
		var ctrl : Node = load("res://src/scenes/world/HoseReel.gd").new()
		ctrl.name = "HoseReelController"
		# Brass nozzle handle for water hoses (red would clash with the fire hose).
		ctrl.set("nozzle_tint", Color(0.76, 0.62, 0.20))
		ctrl.set("prompt_label", "Take hose tip")
		p.add_child(ctrl)

## Wall hook for air hoses: a plate + an L-shaped hook + a coil of translucent
## white hose draped over it. No drum mechanism — the operator just slings the
## coil over the hook. (Simpler than a reel per the operator spec.)
static func _m_air_hose_hook(p: Node3D, size: Vector3, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var dark := _mat(_DARK, ghost, 0.55, 0.55)
	# Air hose visual: opaque-but-not-fully translucent whitish.
	var hose_mat := _mat(Color(0.92, 0.93, 0.90, 0.85), ghost, 0.05, 0.55)
	hose_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Wall plate.
	_box(p, Vector3(size.x * 0.6, size.y * 0.4, 0.04), Vector3(0.0, size.y * 0.65, -size.z * 0.45), dark)
	# L-hook: horizontal stub out from the wall + a vertical lip at the tip.
	_cyl(p, 0.04, 0.04, size.z * 0.7, Vector3(0.0, size.y * 0.65, -size.z * 0.10), steel, "z")
	_cyl(p, 0.04, 0.04, 0.20, Vector3(0.0, size.y * 0.65 + 0.10, size.z * 0.22), steel, "y")
	# Coil of air hose (~20 m): a stack of torus rings hanging from the hook,
	# centred just below the hook horizontal where the coil would rest.
	var hose_r := 0.022
	var coil_outer := size.y * 0.30
	var coil_inner := coil_outer - hose_r * 1.6
	var rings := 12
	var step := 0.022
	for i in rings:
		var ry : float = size.y * 0.30 - float(i) * step
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = coil_inner
		tm.outer_radius = coil_outer
		# 6 slices around the loop looked like a hexagon — make the coil round.
		tm.rings = 48
		tm.ring_segments = 22
		mi.mesh = tm
		mi.material_override = hose_mat
		mi.position = Vector3(0.0, ry, size.z * 0.05)
		# Torus default axis is +Y; tilt so the coil "hangs" forward off the hook.
		mi.rotation.x = PI / 2.0
		p.add_child(mi)
	# Coupler / quick-connect fitting at the tip of the coil.
	_cyl(p, 0.03, 0.03, 0.08, Vector3(0.0, size.y * 0.05, size.z * 0.08), steel, "y")
	# HoseReel controller — proximity prompt + E deploys the AIR blow gun (20 m
	# tether, no water, blows film_scrap forward).
	if not ghost:
		var ctrl : Node = load("res://src/scenes/world/HoseReel.gd").new()
		ctrl.name = "HoseReelController"
		ctrl.set("nozzle_air_mode", true)
		ctrl.set("nozzle_hose_length_m", 20.0)   # 20 m air hose per spec
		ctrl.set("nozzle_max_kg_per_s", 5.0)
		ctrl.set("nozzle_range_m", 5.0)
		ctrl.set("nozzle_cone_deg", 14.0)
		ctrl.set("nozzle_tint", Color(0.92, 0.93, 0.90))
		ctrl.set("prompt_label", "Take air hose tip")
		p.add_child(ctrl)

## Mobile high-pressure washer cart: 2-wheel base + motor + small pressure tank +
## ~4 m thin coiled hose hanging on the side + pistol nozzle with elongated barrel.
## Sits on castors so the player can roll it around (collision is the bounding box).
static func _m_washer_hp_mobile(p: Node3D, size: Vector3, ghost: bool) -> void:
	var red := _mat(Color(0.86, 0.18, 0.16), ghost, 0.2, 0.5)
	var dark := _mat(_DARK, ghost, 0.55, 0.55)
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	# Hose mat: very thin (HP washer hoses are 2-3× thinner than the black water hose).
	var hose_mat := _mat(Color(0.10, 0.10, 0.11), ghost, 0.1, 0.5)
	# Cart base
	_box(p, Vector3(size.x * 0.95, 0.10, size.z * 0.95), Vector3(0.0, 0.06, 0.0), dark)
	# 2 wheels at the back, 2 castors at the front
	for sx in [-1.0, 1.0]:
		_cyl(p, 0.10, 0.10, 0.06, Vector3(sx * size.x * 0.42, 0.10, -size.z * 0.38), dark, "x")
		_cyl(p, 0.05, 0.05, 0.04, Vector3(sx * size.x * 0.32,  0.04, size.z * 0.40), dark, "y")
	# Main red housing (motor + pump enclosure).
	_box(p, Vector3(size.x * 0.85, size.y * 0.55, size.z * 0.80), Vector3(0.0, size.y * 0.38, 0.0), red)
	# Vent grille on top.
	_box(p, Vector3(size.x * 0.50, 0.02, size.z * 0.50), Vector3(0.0, size.y * 0.66, 0.0), dark)
	# Handle bar at the back, ergonomic push.
	_cyl(p, 0.035, 0.035, size.x * 0.72, Vector3(0.0, size.y * 0.95, -size.z * 0.38), steel, "x")
	for sx in [-1.0, 1.0]:
		_cyl(p, 0.035, 0.035, 0.35, Vector3(sx * size.x * 0.36, size.y * 0.78, -size.z * 0.38), steel, "y")
	# Small pressure tank tucked under the housing on the +X side.
	_cyl(p, 0.12, 0.12, size.z * 0.50, Vector3(size.x * 0.30, size.y * 0.20, 0.0), steel, "z")
	# Coiled HP hose hanging on the -X side (5 small torus rings).
	for i in 5:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.10
		tm.outer_radius = 0.10 + 0.013
		tm.rings = 6
		tm.ring_segments = 18
		mi.mesh = tm
		mi.material_override = hose_mat
		mi.position = Vector3(-size.x * 0.50, size.y * 0.30 + float(i) * 0.022, 0.0)
		mi.rotation.z = PI / 2.0
		p.add_child(mi)
	# Pistol with elongated barrel — leans against the +Z face of the housing.
	var pistol := Node3D.new()
	pistol.position = Vector3(size.x * 0.25, size.y * 0.10, size.z * 0.45)
	pistol.rotation.x = deg_to_rad(-12.0)
	p.add_child(pistol)
	_box(pistol, Vector3(0.06, 0.05, 0.16), Vector3(0.0, 0.06, 0.0), dark)     # pistol body
	_box(pistol, Vector3(0.04, 0.12, 0.05), Vector3(0.0, -0.02, 0.0), dark)    # pistol grip
	_cyl(pistol, 0.018, 0.012, 0.55, Vector3(0.0, 0.06, 0.36), steel, "z")     # elongated barrel
	_cyl(pistol, 0.013, 0.013, 0.04, Vector3(0.0, 0.06, 0.66), dark, "z")      # nozzle tip
	# A few meters of hose connecting the housing to the pistol — visual only.
	_cyl(p, 0.013, 0.013, size.z * 0.20, Vector3(size.x * 0.25, size.y * 0.18, size.z * 0.30), hose_mat, "y")
	# Attach the HoseReel controller with HP-tuned parameters — tighter cone, faster
	# clear rate. Same interaction (E grab tip; E again to cycle base valve). #40
	if not ghost:
		var ctrl : Node = load("res://src/scenes/world/HoseReel.gd").new()
		ctrl.name = "HoseReelController"
		ctrl.set("nozzle_max_kg_per_s", 12.0)
		ctrl.set("nozzle_range_m", 3.0)
		ctrl.set("nozzle_cone_deg", 8.0)
		ctrl.set("nozzle_tint", Color(0.82, 0.18, 0.16))
		ctrl.set("prompt_label", "Take HP washer pistol")
		p.add_child(ctrl)

## Vertical industrial compressor (Model A): upright tank with interactive ball valve & spinning pulley
static func _m_compressor_a(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var blue := _mat(color, ghost, 0.35, 0.45)
	var dark := _mat(_DARK, ghost, 0.55, 0.55)
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var brass := _mat(Color(0.76, 0.62, 0.20), ghost, 0.85, 0.30)
	var red := _mat(Color(0.82, 0.18, 0.16), ghost, 0.2, 0.45)

	# Stand legs
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(0.06, 0.20, 0.06), Vector3(sx * size.x * 0.36, 0.10, sz * size.z * 0.36), dark)

	# Main vertical pressure tank
	var tank_r := size.x * 0.32
	var tank_h := size.y * 0.70
	_cyl(p, tank_r, tank_r, tank_h, Vector3(0.0, 0.20 + tank_h * 0.5, 0.0), blue)
	_cyl(p, tank_r * 0.95, tank_r, 0.10, Vector3(0.0, 0.20 + tank_h, 0.0), blue)
	_cyl(p, tank_r, tank_r * 0.95, 0.10, Vector3(0.0, 0.20, 0.0), blue)

	# Motor + belt drive with spinning dual flywheel pulleys
	var top_y := 0.20 + tank_h + 0.05
	_box(p, Vector3(size.x * 0.55, 0.40, size.z * 0.55), Vector3(0.0, top_y + 0.20, 0.0), blue)
	_box(p, Vector3(0.12, 0.40, size.z * 0.30), Vector3(size.x * 0.30, top_y + 0.20, size.z * 0.16), dark)

	var _comp_pulley := _spinning_cyl(p, 0.14, 0.14, 0.08,
		Vector3(size.x * 0.28, top_y + 0.20, size.z * 0.16), dark, "x", Vector3.RIGHT, ghost, 90.0)

	# Twin pistons / heads
	for sx in [-1.0, 1.0]:
		_cyl(p, 0.10, 0.10, 0.18, Vector3(sx * 0.18, top_y + 0.50, 0.0), steel)
		_cyl(p, 0.08, 0.08, 0.06, Vector3(sx * 0.18, top_y + 0.62, 0.0), dark)

	# Pressure gauge cluster
	var gauge_y := 0.20 + tank_h * 0.6
	for sx in [-1.0, 1.0]:
		_cyl(p, 0.06, 0.06, 0.02, Vector3(sx * 0.12, gauge_y, size.z * 0.36), steel, "z")
		_cyl(p, 0.055, 0.055, 0.01, Vector3(sx * 0.12, gauge_y, size.z * 0.37), brass, "z")

	# Outlet pipe + interactive ball valve lever
	_cyl(p, 0.04, 0.04, 0.35, Vector3(size.x * 0.36, 0.40, 0.0), steel, "y")
	_cyl(p, 0.06, 0.06, 0.08, Vector3(size.x * 0.36, 0.20, 0.0), brass, "y")
	var _comp_valve := _interactive_hatch(p, Vector3(0.16, 0.02, 0.03),
		Vector3(size.x * 0.36, 0.20, 0.0), "Compressor Air Supply Valve", 90.0, 1.0, red, ghost)

	# Label panel
	_box(p, Vector3(0.30, 0.16, 0.005), Vector3(0.0, gauge_y - 0.20, size.z * 0.36), dark)

# ── Compressor Model B: industrial screw-compressor cabinet with interactive service door ──────
static func _m_compressor_b(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.3, 0.5)
	var dark := _mat(_DARK, ghost, 0.55, 0.55)
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var brass := _mat(Color(0.76, 0.62, 0.20), ghost, 0.85, 0.30)
	var red := _mat(Color(0.82, 0.18, 0.16), ghost, 0.2, 0.45)

	# Base plinth
	_box(p, Vector3(size.x * 0.95, 0.20, size.z * 0.95), Vector3(0.0, 0.10, 0.0), dark)
	# Main upright cabinet enclosure
	_box(p, Vector3(size.x * 0.92, size.y * 0.82, size.z * 0.92), Vector3(0.0, 0.20 + size.y * 0.41, 0.0), shell)

	# Interactive hinged front service access door
	var comp_door := _interactive_hatch(p, Vector3(size.x * 0.84, size.y * 0.72, 0.03),
		Vector3(0.0, 0.20 + size.y * 0.40, size.z * 0.46), "Compressor Service Door", 100.0, 1.0, shell, ghost)
	if not ghost:
		# Lower vent louvers on door
		for i in 3:
			_box(comp_door, Vector3(size.x * 0.55, 0.04, 0.01),
				Vector3(-size.x * 0.42, -size.y * 0.22 + float(i) * 0.10, 0.02), dark)
		# Internal rotary screw air-end and oil separator visible when door is open
		_cyl(p, size.x * 0.18, size.x * 0.18, size.y * 0.45, Vector3(0.0, 0.20 + size.y * 0.32, 0.0), steel, "y")
		_cyl(p, size.x * 0.12, size.x * 0.12, size.y * 0.25, Vector3(-size.x * 0.20, 0.20 + size.y * 0.25, 0.0), dark, "y")

	# Air intake mesh near top
	_box(p, Vector3(size.x * 0.70, 0.14, 0.01), Vector3(0.0, size.y * 0.88, size.z * 0.46), dark)

	# Outlet pipe + ball valve down the side
	_cyl(p, 0.035, 0.035, size.y * 0.40, Vector3(size.x * 0.36, size.y * 0.30, 0.0), steel, "y")
	_cyl(p, 0.06, 0.06, 0.08, Vector3(size.x * 0.36, 0.30, 0.0), brass, "y")
	_box(p, Vector3(0.14, 0.02, 0.02), Vector3(size.x * 0.36, 0.30, 0.0), red)

	# Digital pressure readout & analog gauge
	_cyl(p, 0.08, 0.08, 0.02, Vector3(-size.x * 0.18, 1.55, size.z * 0.46), steel, "z")
	_cyl(p, 0.075, 0.075, 0.01, Vector3(-size.x * 0.18, 1.55, size.z * 0.47), brass, "z")

	# Top exhaust cooling fan grille
	_box(p, Vector3(size.x * 0.65, 0.04, size.z * 0.65), Vector3(0.0, 0.20 + size.y * 0.82 + 0.04, 0.0), dark)

## Vacuum unit — brushed stainless 2-door cabinet that houses the vacuum-pump control gear (#208a).
static func _m_vacuum_unit(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var stainless := _mat(Color(0.78, 0.80, 0.82), ghost, 0.85, 0.4)
	var darker := _mat(Color(0.62, 0.64, 0.66), ghost, 0.85, 0.45)
	var chrome := _mat(Color(0.92, 0.93, 0.95), ghost, 0.95, 0.15)
	var dark := _mat(_DARK, ghost, 0.55, 0.55)
	var face_white := _mat(Color(0.95, 0.95, 0.95), ghost, 0.1, 0.3)

	_box_static_body(p, Vector3(size.x, size.y, size.z), Vector3(0.0, size.y * 0.5, 0.0), stainless)
	var door_w : float = size.x * 0.48
	var door_h : float = size.y - 0.35
	var door_y : float = size.y * 0.5 - 0.05

	# Interactive double doors
	for sx in [-1.0, 1.0]:
		var dx : float = sx * (door_w * 0.5 + 0.01)
		var vac_door := _interactive_hatch(p, Vector3(door_w, door_h, 0.02),
			Vector3(dx, door_y, size.z * 0.5 + 0.01), "Vacuum Cabinet Door %s" % ("Left" if sx < 0 else "Right"), 95.0, sx, darker, ghost)
		if not ghost:
			_cyl(vac_door, 0.012, 0.012, 0.5,
				Vector3(-sx * door_w * 0.18, 0.0, 0.02), chrome, "y")
	for gx in [-size.x * 0.22, size.x * 0.22]:
		_cyl(p, 0.06, 0.06, 0.02, Vector3(gx, size.y + 0.011, 0.0), face_white, "y")
		_cyl(p, 0.055, 0.055, 0.005, Vector3(gx, size.y + 0.024, 0.0), face_white, "y")
	for sx2 in [-1.0, 1.0]:
		var lg := _box(p, Vector3(0.05, 0.10, 0.05), Vector3(sx2 * (size.x * 0.5 - 0.04), 0.05, size.z * 0.5 - 0.04), dark)
		lg.add_to_group("machine_leg")
		lg.set_meta("leg_h", 0.10)
		var lg2 := _box(p, Vector3(0.05, 0.10, 0.05), Vector3(sx2 * (size.x * 0.5 - 0.04), 0.05, -size.z * 0.5 + 0.04), dark)
		lg2.add_to_group("machine_leg")
		lg2.set_meta("leg_h", 0.10)
	if not ghost:
		var sticker_y := StandardMaterial3D.new()
		sticker_y.albedo_color = Color(1.0, 0.85, 0.05)
		sticker_y.emission_enabled = true
		sticker_y.emission = Color(1.0, 0.85, 0.05)
		sticker_y.emission_energy_multiplier = 0.25
		sticker_y.roughness = 0.7
		for sx3 in [-1.0, 1.0]:
			var st_dx : float = sx3 * (door_w * 0.5 + 0.01)
			var qm := MeshInstance3D.new()
			var qmsh := QuadMesh.new()
			qmsh.size = Vector2(0.08, 0.05)
			qm.mesh = qmsh
			qm.material_override = sticker_y
			qm.position = Vector3(st_dx, door_y + door_h * 0.30, size.z * 0.5 + 0.012)
			p.add_child(qm)
		var tab_mat := StandardMaterial3D.new()
		tab_mat.albedo_color = Color(0.10, 0.12, 0.14)
		tab_mat.emission_enabled = true
		tab_mat.emission = Color(0.10, 0.85, 0.95)
		tab_mat.emission_energy_multiplier = 0.30
		tab_mat.roughness = 0.5
		for sx4 in [-1.0, 1.0]:
			var tq := MeshInstance3D.new()
			var tqm := QuadMesh.new()
			tqm.size = Vector2(0.10, 0.07)
			tq.mesh = tqm
			tq.material_override = tab_mat
			tq.position = Vector3(sx4 * (size.x * 0.5 + 0.001), size.y * 0.55, 0.0)
			tq.rotation = Vector3(0.0, sx4 * PI * 0.5, 0.0)
			p.add_child(tq)
	_finalize_placeable(p, "vacuum_unit")

## Vacuum pump — bronze liquid-ring pump with spinning impeller & sight window (#208b).
static func _m_vacuum_pump(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var bronze := _mat(Color(0.55, 0.40, 0.20), ghost, 0.9, 0.5)
	var motor_grey := _mat(Color(0.48, 0.50, 0.54), ghost, 0.45, 0.5)
	var foot := _mat(Color(0.20, 0.21, 0.23), ghost, 0.3, 0.7)
	var dark := _mat(_DARK, ghost, 0.55, 0.55)
	var brass := _mat(Color(0.76, 0.62, 0.20), ghost, 0.85, 0.30)

	_box(p, Vector3(size.x + 0.04, 0.01, size.z + 0.04), Vector3(0.0, -size.y * 0.5 + 0.005, 0.0), foot)
	var pump_r : float = size.x * 0.5
	_cyl(p, pump_r, pump_r, size.z, Vector3(0.0, 0.0, 0.0), bronze, "z")

	# Rotating internal bronze liquid ring impeller with radial curved vanes
	var _impeller := _spinning_cyl(p, pump_r * 0.75, pump_r * 0.75, size.z * 0.8,
		Vector3(0.0, 0.0, 0.0), bronze, "z", Vector3.FORWARD, ghost, 120.0)

	# Transparent grimy circular sight glass on front face
	_cyl(p, pump_r * 0.60, pump_r * 0.60, 0.01, Vector3(0.0, 0.0, size.z * 0.5 + 0.005),
		MaterialPalette.mat_glass_inspection_grime(), "z")

	# Interactive service drain cock valve
	var _drain_cock := _interactive_hatch(p, Vector3(0.08, 0.03, 0.04),
		Vector3(0.0, -pump_r * 0.8, size.z * 0.45), "Vacuum Pump Drain Cock", 90.0, 1.0, brass, ghost)

	for sx in [-1.0, 1.0]:
		_cyl(p, 0.025, 0.025, 0.04, Vector3(sx * pump_r * 0.45, pump_r * 0.25, size.z * 0.5 + 0.02), dark, "z")
	_box(p, Vector3(0.18, 0.18, size.z * 0.6), Vector3(0.0, pump_r * 0.6, -size.z * 0.3), motor_grey)
	_finalize_placeable(p, "vacuum_pump")

## A floor "hot spot" placeable that accumulates dirt over time. Visual is just a
## small brown wear mark on the floor; the actual dirt pile (cone) is spawned by
## the DirtHotspot controller and grows until a hose / HP washer / shovel clears it.
static func _m_dirt_hotspot(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	# Visible wear patch on the floor — operator should know one is here.
	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.02, size.z)
	mark.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.55)
	m.roughness = 0.95
	if ghost:
		m.albedo_color.a = 0.30
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark.material_override = m
	mark.position = Vector3(0.0, 0.01, 0.0)
	p.add_child(mark)
	if not ghost:
		var ctrl : Node = load("res://src/sim/DirtHotspot.gd").new()
		ctrl.name = "DirtHotspot"
		p.add_child(ctrl)

# ── Support poles (catalog + custom-height builder) ─────────────────────────
## True for pole placeables. BuildMode reads this to trigger smart snap (raycast
## hit on a belt deck → pole top aligns to the deck, height auto-stretches down
## to the floor).
static func is_pole(id: String) -> bool:
	return id == "pole_single" or id == "pole_double" or id == "pole_a_frame"

## Build a pole at a custom HEIGHT (overrides the catalog default size.y so the
## same pole id can land at any required height — e.g. a tall pole under the top
## of a steep inclined belt, a short one under a horizontal belt at deck level).
## Returns a placed-object-tagged StaticBody3D ready for the build root.
static func build_pole(id: String, height: float, ghost: bool = false) -> Node3D:
	if not is_pole(id):
		return null
	var item := get_item(id)
	if item.is_empty():
		return null
	var size : Vector3 = item["size"]
	# Override the size.y so the model builder draws the right standing height.
	size.y = maxf(0.10, height)
	if ghost:
		return _simple_ghost(size)
	var body := StaticBody3D.new()
	body.name = String(item["name"])
	body.set_meta("placeable_id", id)
	body.set_meta("pole_height", size.y)
	body.add_to_group("placed_object")
	var model := Node3D.new()
	model.name = "Model"
	body.add_child(model)
	_build_model(model, id, "Conveyance", size, item.get("color", Color(0.55, 0.57, 0.61)), false)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(size.x, size.y, size.z)
	col.shape = bx
	col.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(col)
	return body

## Single vertical post + base plate. Top of the post = size.y.
static func _m_pole_single(p: Node3D, size: Vector3, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	_box(p, Vector3(0.18, 0.02, 0.18), Vector3(0.0, 0.01, 0.0), dark)
	_cyl(p, 0.04, 0.04, size.y, Vector3(0.0, size.y * 0.5, 0.0), steel)
	# Saddle plate at the top so the belt rests cleanly.
	_box(p, Vector3(0.18, 0.04, 0.08), Vector3(0.0, size.y - 0.02, 0.0), steel)

## Two vertical posts side by side + cross-brace + saddle plate.
static func _m_pole_double(p: Node3D, size: Vector3, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var half : float = size.x * 0.5 - 0.05
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(0.16, 0.02, 0.18), Vector3(sx * half, 0.01, 0.0), dark)
		_cyl(p, 0.04, 0.04, size.y, Vector3(sx * half, size.y * 0.5, 0.0), steel)
	# Cross-brace at 60% of height.
	_box(p, Vector3(half * 2.0, 0.04, 0.04), Vector3(0.0, size.y * 0.60, 0.0), steel)
	# Saddle plate spanning both posts.
	_box(p, Vector3(half * 2.0 + 0.08, 0.04, 0.10), Vector3(0.0, size.y - 0.02, 0.0), steel)

## A-frame — two legs angled inward, joined at the top by a saddle plate.
static func _m_pole_a_frame(p: Node3D, size: Vector3, ghost: bool) -> void:
	var steel := _mat(_STEEL, ghost, 0.6, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var half : float = size.x * 0.5 - 0.05
	# Each leg's straight-line length (the longer the height, the more vertical).
	var leg_len : float = sqrt(half * half + size.y * size.y)
	var lean : float = atan2(half, size.y)
	for sx in [-1.0, 1.0]:
		_box(p, Vector3(0.16, 0.02, 0.18), Vector3(sx * half, 0.01, 0.0), dark)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.04
		cm.height = leg_len
		cm.radial_segments = 8
		mi.mesh = cm
		mi.material_override = steel
		mi.position = Vector3(sx * half * 0.5, size.y * 0.5, 0.0)
		mi.rotation.z = sx * lean
		p.add_child(mi)
	# Cross-brace at the apex.
	_box(p, Vector3(0.16, 0.04, 0.10), Vector3(0.0, size.y - 0.02, 0.0), steel)

## Records the origin name + unique code onto the bale's label metadata only.
## No more floating Label3D — operator said real bales just have a paper sticker
## you have to walk up to and squint at. The barcode-stripe sticker mesh stays
## (added by attach_to() in _m_bale); the floating yellow billboard text does NOT.
## Call sites kept so spawn code can still record codes for the scan log.
static func add_bale_label(body: Node3D, id: String, code: String) -> void:
	var item := get_item(id)
	if item.is_empty():
		return
	var _nm := String(BaleDefs.get_origin(id).get("name", id)).to_upper()
	var label_node := body.get_node_or_null("Label")
	if label_node == null:
		return
	if label_node.has_meta("label_info"):
		var info = label_node.get_meta("label_info")
		info["batch"] = code
		label_node.set_meta("label_info", info)
	var old_lbl := label_node.get_node_or_null("BaleLabel")
	if old_lbl:
		old_lbl.queue_free()

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
	# #194 — placeable_id intentionally NOT set here. Two callers:
	#   • the 4-point Surface tool (_make_surface in BuildMode) — uses
	#     surface_data meta and ignores placeable_id at save time.
	#   • the single-click "door_personnel" catalog branch — overrides the
	#     meta to "door_personnel" so the loader can reproduce the placement.
	# Stamping "surface" here was the root cause of #194's silent door loss.
	door.set_meta("door_w", width)
	door.set_meta("door_h", height)
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

## Industrial roller / sectional gate — drum on top, dark-blue steel leaf that
## rolls UP into the drum to open. Centred on origin like build_door so the
## caller positions by centre. Includes a wall-mounted 3-button push-button
## control station (UP / STOP / DOWN) offset to one side of the leaf, with
## each button wired to the Gate via its `gate` field.
##
## The Gate node carries `placeable_id` = "surface" and group "placed_object",
## so it deletes + persists exactly like a door.
## `anchor_base` selects where the gate's ORIGIN sits relative to its opening,
## because the two callers disagree and always have:
##   * false (default) — origin at the opening's CENTRE. The 4-point Surface
##     tool places a gate on the quad centroid, so a surface gate's origin is
##     the middle of its own hole.
##   * true — origin at the opening's BASE. The catalog branch (:1246) places
##     `gate_roller` at the wall hit point, i.e. the bottom of the cut.
## Measured 2026-09-03 with the default on a catalog gate: the carved opening
## spanned y -8.000 .. -4.400 while the leaf (visual AND collision) spanned
## -9.800 .. -6.200 — a full half-height low, 1.8 m of leaf underground and the
## top half of the doorway standing open. Invisible until the leaf gained
## collision, because a ghost covering the wrong half looks identical to a
## ghost covering the right one. See docs/audit/jam_baseline_2026-09-03.md.
static func build_gate(width: float, height: float, label: String, anchor_base: bool = false) -> StaticBody3D:
	var gate: StaticBody3D = load("res://src/build/Gate.gd").new()
	gate.name = "Gate" if label.is_empty() else label
	# #194 — see build_door note; the catalog "gate_roller" branch sets
	# placeable_id, the 4-point Surface tool uses surface_data instead.
	gate.set_meta("door_w", width)
	gate.set_meta("door_h", height)
	gate.add_to_group("placed_object")

	# ── Leaf material: dark industrial blue, painted steel ────────────────────
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.12, 0.20, 0.36)   # dark navy blue
	leaf_mat.metallic = 0.4
	leaf_mat.roughness = 0.55
	# Horizontal sectional ribs — fake-them with a slight roughness variation by
	# stacking the box (single mesh is fine, leave for the polish pass).

	# ── LeafScaler: anchored at the TOP edge of the opening ───────────────────
	# Y-scale on this node shrinks the VISUAL leaf upward into the drum (top
	# stays put, bottom rises).
	# The scaler sits ON the opening's top edge; everything else is derived from
	# it, so the anchor convention lives in exactly this one number.
	var leaf_top_y : float = height if anchor_base else height * 0.5
	var scaler := Node3D.new()
	scaler.name = "LeafScaler"
	scaler.position = Vector3(0.0, leaf_top_y, 0.0)   # top of the opening
	gate.add_child(scaler)
	# Gate._apply_open_t derives the collision box from this, so the physics leaf
	# can never drift from the visual one regardless of which anchor was used.
	gate.set_meta("leaf_top_y", leaf_top_y)

	var leaf := MeshInstance3D.new()
	leaf.name = "Leaf"
	var lmesh := BoxMesh.new()
	lmesh.size = Vector3(width, height, 0.10)
	leaf.mesh = lmesh
	leaf.material_override = leaf_mat
	leaf.position = Vector3(0.0, -height * 0.5, 0.0)    # top edge at scaler origin
	scaler.add_child(leaf)

	# Collision must be a DIRECT child of the StaticBody3D or Godot never
	# registers it (measured 2026-08-31: shape owners 0, closed gates blocked
	# nothing — vehicles and the route grid drove straight through the leaf).
	# Gate._apply_open_t resizes this box to track the visual leaf.
	var col := CollisionShape3D.new()
	col.name = "LeafCol"
	var lshape := BoxShape3D.new()
	lshape.size = Vector3(width, height, 0.10)
	col.shape = lshape
	col.position = Vector3(0.0, leaf_top_y - height * 0.5, 0.0)  # closed: fills the opening
	gate.add_child(col)

	# ── Drum housing (the visible roll on top) ────────────────────────────────
	var drum_mat := StandardMaterial3D.new()
	drum_mat.albedo_color = Color(0.20, 0.20, 0.22)
	drum_mat.metallic = 0.7
	drum_mat.roughness = 0.45

	var drum := MeshInstance3D.new()
	drum.name = "Drum"
	var dm := CylinderMesh.new()
	dm.height = width + 0.25
	dm.top_radius = 0.28
	dm.bottom_radius = 0.28
	drum.mesh = dm
	drum.material_override = drum_mat
	# Lay the cylinder horizontally along X (default cylinder is along Y).
	drum.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
	drum.position = Vector3(0.0, height * 0.5 + 0.30, 0.0)
	gate.add_child(drum)

	# Two end brackets bolted to the wall, holding the drum.
	var bracket_mat := StandardMaterial3D.new()
	bracket_mat.albedo_color = Color(0.32, 0.32, 0.34)
	bracket_mat.metallic = 0.6
	bracket_mat.roughness = 0.5
	for sx in [-1.0, 1.0]:
		var br := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.55, 0.45)
		br.mesh = bm
		br.material_override = bracket_mat
		br.position = Vector3(sx * (width * 0.5 + 0.08), height * 0.5 + 0.20, 0.0)
		gate.add_child(br)

	# ── 3-button control station, mounted on the wall beside the gate ─────────
	# Offset to +X past the leaf edge; sits at chest height ~1.3 m above floor
	# (so its centre is ~ -height/2 + 1.3 in gate-local Y, since gate is centred).
	var station := _build_gate_button_station(gate)
	# 1.30 m above the OPENING'S FLOOR, whichever anchor this gate uses. The
	# constant used to be `-height * 0.5 + 1.30`, which silently assumed the
	# centre anchor: on a base-anchored catalog gate (origin y -8.000, opening
	# -8.000..-4.400) that put the buttons at y -8.500 — half a metre under the
	# floor, unreachable even for the player. Derived from leaf_top_y so it can
	# never drift from the leaf again.
	var station_y : float = leaf_top_y - height + 1.30
	# Push +X past the drum bracket so it sits cleanly on the wall.
	var station_x : float = width * 0.5 + 0.45
	station.position = Vector3(station_x, station_y, 0.0)
	gate.add_child(station)

	return gate

## Build the wall-mounted push-button station and wire each button to `gate`.
static func _build_gate_button_station(gate: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "ButtonStation"

	# Back box — cast aluminium, IP65 industrial look.
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.55, 0.56, 0.58)
	box_mat.metallic = 0.5
	box_mat.roughness = 0.55
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.16, 0.32, 0.08)
	box.mesh = bm
	box.material_override = box_mat
	root.add_child(box)

	# Three buttons stacked vertically on the front face (+Z side of the box).
	# Layout to the operator's description, 2026-09-03: top carries an UP arrow
	# and runs the gate open, the centre stops it mid-travel, the bottom carries
	# a DOWN arrow and is red ("usually red") and runs it shut. One press each.
	# STOP keeps the wide mushroom head so two red caps are never confusable by
	# shape — the thing your hand finds without looking.
	var GateButton_t : Script = load("res://src/build/GateButton.gd")
	var BTN_DEFS := [
		{"kind": 0, "y":  0.10, "color": Color(0.20, 0.65, 0.25), "mushroom": false, "arrow":  1},  # UP green, up arrow
		{"kind": 1, "y":  0.00, "color": Color(0.78, 0.10, 0.10), "mushroom": true,  "arrow":  0},  # STOP red mushroom
		{"kind": 2, "y": -0.10, "color": Color(0.72, 0.11, 0.11), "mushroom": false, "arrow": -1},  # DOWN red, down arrow
	]
	for def in BTN_DEFS:
		var btn : StaticBody3D = GateButton_t.new()
		btn.kind = int(def["kind"])
		btn.gate = gate
		btn.position = Vector3(0.0, float(def["y"]), 0.05)
		# Cap mesh — either a dome (UP/DOWN) or a mushroom (STOP).
		var visual := Node3D.new()
		visual.name = "Visual"
		var cap_mat := StandardMaterial3D.new()
		cap_mat.albedo_color = def["color"]
		cap_mat.roughness = 0.45
		cap_mat.metallic = 0.1
		var cap := MeshInstance3D.new()
		if bool(def["mushroom"]):
			# Wide mushroom head for the E-stop.
			var cm := CylinderMesh.new()
			cm.height = 0.018
			cm.top_radius = 0.04
			cm.bottom_radius = 0.04
			cap.mesh = cm
			cap.position = Vector3(0.0, 0.0, 0.01)
			cap.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
		else:
			var sm := SphereMesh.new()
			sm.radius = 0.028
			sm.height = 0.036
			cap.mesh = sm
			cap.position = Vector3(0.0, 0.0, 0.01)
		cap.material_override = cap_mat
		visual.add_child(cap)
		# Direction arrow on the cap face. A flat triangular prism, off-white so
		# it reads against both the green and the red cap; +Y points up, so the
		# DOWN button is the same mesh rolled 180 degrees.
		var arrow_dir : int = int(def.get("arrow", 0))
		if arrow_dir != 0:
			var arrow_mat := StandardMaterial3D.new()
			arrow_mat.albedo_color = Color(0.94, 0.94, 0.92)
			arrow_mat.roughness = 0.6
			var arrow := MeshInstance3D.new()
			arrow.name = "Arrow"
			var pm := PrismMesh.new()
			pm.size = Vector3(0.030, 0.030, 0.006)
			arrow.mesh = pm
			arrow.material_override = arrow_mat
			arrow.position = Vector3(0.0, 0.0, 0.036)
			if arrow_dir < 0:
				arrow.rotation = Vector3(0.0, 0.0, deg_to_rad(180.0))
			visual.add_child(arrow)
		btn.add_child(visual)
		# Collision so the player's interact ray hits it.
		var bcs := CollisionShape3D.new()
		var bsh := BoxShape3D.new()
		bsh.size = Vector3(0.07, 0.07, 0.04)
		bcs.shape = bsh
		bcs.position = Vector3(0.0, 0.0, 0.01)
		btn.add_child(bcs)
		root.add_child(btn)
	return root

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

## Industrial glazed window — aluminium frame + central mullion + two glass
## panes. Centred on origin like build_panel so the 4-point surface tool can
## place it flush in the carved opening. Solid collision so the player can't
## walk through, but the build raycast can still hit it for [X] delete.
##
## Visually: brushed-aluminium rectangular frame (4 strips + 1 vertical
## mullion). Two translucent blue-tinted glass panes sit inside the L/R bays.
## No vertical mullion if the window is too narrow (< 1.0 m) — would look
## ridiculous on a porthole.
static func build_window(width: float, height: float, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Window" if label.is_empty() else label
	# #194 — see build_door note; "window_frame" catalog branch stamps the id.
	body.set_meta("door_w", width)
	body.set_meta("door_h", height)
	body.add_to_group("placed_object")

	# ── Materials ─────────────────────────────────────────────────────────────
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.62, 0.64, 0.67)   # brushed aluminium
	frame_mat.metallic = 0.7
	frame_mat.roughness = 0.40
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.62, 0.76, 0.86, 0.35)   # same pale blue as panel
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.metallic = 0.0
	glass_mat.roughness = 0.18

	var frame_w   : float = 0.06       # frame strip thickness (visible width)
	var frame_d   : float = 0.06       # depth into the wall
	var glass_d   : float = 0.02       # glass pane depth
	var has_mull  : bool  = width >= 1.0

	# ── Glass pane(s): one big pane or two flanking the mullion ───────────────
	if has_mull:
		var pane_w : float = (width - frame_w * 3.0) * 0.5   # 2 frame edges + 1 mullion
		var bay_w  : float = pane_w + 0.001
		var bay_h  : float = height - frame_w * 2.0
		for sx in [-1.0, 1.0]:
			var pane := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(bay_w, bay_h, glass_d)
			pane.mesh = pm
			pane.material_override = glass_mat
			# Centre of each bay = quarter-width offset on the framed side.
			var bx : float = sx * (frame_w * 0.5 + pane_w * 0.5)
			pane.position = Vector3(bx, 0.0, 0.0)
			body.add_child(pane)
	else:
		var pane := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(width - frame_w * 2.0, height - frame_w * 2.0, glass_d)
		pane.mesh = pm
		pane.material_override = glass_mat
		body.add_child(pane)

	# ── Frame strips: top, bottom, left, right ────────────────────────────────
	var top := MeshInstance3D.new()
	top.mesh = _box_mesh(Vector3(width, frame_w, frame_d))
	top.material_override = frame_mat
	top.position = Vector3(0.0, height * 0.5 - frame_w * 0.5, 0.0)
	body.add_child(top)

	var bot := MeshInstance3D.new()
	bot.mesh = _box_mesh(Vector3(width, frame_w, frame_d))
	bot.material_override = frame_mat
	bot.position = Vector3(0.0, -height * 0.5 + frame_w * 0.5, 0.0)
	body.add_child(bot)

	var lf := MeshInstance3D.new()
	lf.mesh = _box_mesh(Vector3(frame_w, height - frame_w * 2.0, frame_d))
	lf.material_override = frame_mat
	lf.position = Vector3(-width * 0.5 + frame_w * 0.5, 0.0, 0.0)
	body.add_child(lf)

	var rt := MeshInstance3D.new()
	rt.mesh = _box_mesh(Vector3(frame_w, height - frame_w * 2.0, frame_d))
	rt.material_override = frame_mat
	rt.position = Vector3(width * 0.5 - frame_w * 0.5, 0.0, 0.0)
	body.add_child(rt)

	# ── Vertical mullion (only if wide enough) ────────────────────────────────
	if has_mull:
		var mull := MeshInstance3D.new()
		mull.mesh = _box_mesh(Vector3(frame_w, height - frame_w * 2.0, frame_d))
		mull.material_override = frame_mat
		mull.position = Vector3(0.0, 0.0, 0.0)
		body.add_child(mull)

	# Single block collider sized to the carved opening, so the player can't
	# walk through and [X] delete still ray-hits cleanly.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, frame_d)
	col.shape = shape
	body.add_child(col)
	return body

static func _box_mesh(sz: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = sz
	return bm

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

# ── verdeelwals (distribution roller): paddled roller in an open frame over a
#    short chute, spreads material across a width. SINGLE-DRIVE — the roller is a
#    real RotatingMechanism so RPM control + visible spin work (#58). ────────────
static func _m_verdeelwals(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.55, 0.4)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	# Open frame: four thin uprights + a top cross-member spanning the width (X).
	var roll_y : float = size.y * 0.55
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(0.08, size.y * 0.9, 0.08),
				Vector3(float(sx) * size.x * 0.42, size.y * 0.45, float(sz) * size.z * 0.4), dark)
	_box(p, Vector3(size.x * 0.92, 0.08, 0.1), Vector3(0.0, size.y * 0.88, 0.0), dark)
	# Roller spanning the WIDTH (axis X), spinning about X. radius ~0.35,
	# length ~size.x*0.8, centred at roll_y. Single-drive (no "comp" meta — the
	# LineFlow fallback drives it). Default rpm ~60.
	var roll_r : float = 0.35
	var roll_rm := _spinning_cyl(p, roll_r, roll_r, size.x * 0.8,
		Vector3(0.0, roll_y, 0.0), steel, "x", Vector3.RIGHT, ghost, 60.0)
	# 6 radial paddle fins parented UNDER the roller so they spin with it. On
	# ghost, roll_rm == p, so fall back to the absolute roller height for Y.
	var n_pad := 6
	for i in n_pad:
		var ang : float = TAU * float(i) / float(n_pad)
		var off_y : float = cos(ang) * roll_r
		var off_z : float = sin(ang) * roll_r
		var base_y : float = 0.0 if not ghost else roll_y
		var pad := _box(roll_rm, Vector3(size.x * 0.78, 0.16, 0.03),
			Vector3(0.0, base_y + off_y, off_z), steel)
		pad.rotation.x = ang
	# Short hopper/chute beneath the roller (open box flared by angled side walls).
	_box(p, Vector3(size.x * 0.7, size.y * 0.22, size.z * 0.5),
		Vector3(0.0, size.y * 0.22, 0.0), dark)
	for sz2 in [-1.0, 1.0]:
		var wall := _box(p, Vector3(size.x * 0.7, size.y * 0.3, 0.04),
			Vector3(0.0, size.y * 0.34, float(sz2) * size.z * 0.28), dark)
		wall.rotation.x = float(sz2) * deg_to_rad(22.0)
	_legs(p, size, size.y * 0.12, dark)

# ── ringleiding (pneumatic ring main): a horizontal smooth-pipe loop up high that
#    feeds conveying air to drop points. Cosmetic — NO rotor. ────────────────────
# ── Ringleiding 3A — the rondmeng serpentine, photo-accurate from
#    _ringleiding_1..4.png (operator 2026-08-28: "it's the ring"). Three
#    stacked horizontal runs of Ø ~440 cream pipe joined by 180° U-bends at
#    alternating ends; clamp collars along the runs; grey square-tube cage
#    with YELLOW-trimmed posts + wire-mesh panels; pressure gauge on the top
#    bend flange; entry riser at the bottom, exit continuing up from the top
#    run (to the shared silo-top cyclone); vendor placard "GLOBAL SPIRAL
#    CHUTES MOD. 260". size = (1.6, 2.8, 5.0), runs along Z. ─────────────────
static func _m_ringleiding_3a(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var pipe  := _mat(color, ghost, 0.15, 0.55)                     # cream GRP/steel pipe
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var frame := _mat(Color(0.48, 0.50, 0.53), ghost, 0.5, 0.5)     # grey cage tube
	var trim  := _mat(_SAFETY, ghost, 0.2, 0.6)                     # yellow post trim
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)

	var pr : float = 0.22                                           # pipe radius (Ø 440)
	var run_len : float = size.z * 0.78
	var ys : Array[float] = [0.62, 1.40, 2.18]                      # the three run heights
	var bend_r : float = (ys[1] - ys[0]) * 0.5                      # U-bend radius

	# ── The three runs with clamp collars. ───────────────────────────────────
	for yi in ys.size():
		_cyl(p, pr, pr, run_len, Vector3(0.0, ys[yi], 0.0), pipe, "z")
		for cz in [-0.30, -0.10, 0.10, 0.30]:
			_cyl(p, pr + 0.015, pr + 0.015, 0.05, Vector3(0.0, ys[yi], run_len * float(cz)), dark, "z")

	# ── 180° U-bends at ALTERNATING ends (bottom→mid at -Z, mid→top at +Z),
	# each approximated by 5 short segments on a half-circle arc. ────────────
	for bi in [0, 1]:
		var y_lo : float = ys[bi]
		var end_sign : float = -1.0 if bi == 0 else 1.0
		var cz2 : float = end_sign * run_len * 0.5
		var cy2 : float = y_lo + bend_r
		for si in 5:
			var a0 : float = PI * float(si) / 5.0
			var a1 : float = PI * float(si + 1) / 5.0
			var p0 := Vector3(0.0, cy2 - cos(a0) * bend_r, cz2 + end_sign * sin(a0) * bend_r)
			var p1 := Vector3(0.0, cy2 - cos(a1) * bend_r, cz2 + end_sign * sin(a1) * bend_r)
			var seg_mid := (p0 + p1) * 0.5
			var d := p1 - p0
			var seg := _cyl(p, pr, pr, d.length() + pr * 0.6, seg_mid, pipe, "y")
			seg.rotation.x = atan2(d.z, d.y)

	# ── Entry riser (floor → bottom run, -Z end) + exit up from the top run
	# (+Z end, toward the silo-top cyclone). ─────────────────────────────────
	_cyl(p, pr, pr, ys[0], Vector3(0.0, ys[0] * 0.5, -run_len * 0.38), pipe, "y")
	_cyl(p, pr, pr, size.y - ys[2], Vector3(0.0, (ys[2] + size.y) * 0.5, run_len * 0.38), pipe, "y")

	# ── Gauge on a flanged joint at the top bend. ────────────────────────────
	_cyl(p, pr + 0.03, pr + 0.03, 0.06, Vector3(0.0, ys[2], run_len * 0.42), steel, "z")
	_cyl(p, 0.03, 0.03, 0.10, Vector3(0.0, ys[2] + pr + 0.05, run_len * 0.42), dark, "y")
	_cyl(p, 0.07, 0.07, 0.03, Vector3(0.0, ys[2] + pr + 0.13, run_len * 0.42), _mat(Color(0.92, 0.92, 0.90), ghost, 0.1, 0.7), "y")

	# ── Cage: grey posts with yellow trim, top rails, wire-mesh side panels. ─
	var px : float = size.x * 0.46
	var pz : float = size.z * 0.47
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := _box(p, Vector3(0.07, size.y * 0.92, 0.07),
				Vector3(float(sx) * px, size.y * 0.46, float(sz) * pz), frame)
			post.add_to_group("machine_leg")
			post.set_meta("leg_h", size.y * 0.92)
			_box(p, Vector3(0.075, size.y * 0.92, 0.02),
				Vector3(float(sx) * px, size.y * 0.46, float(sz) * pz + 0.045), trim)
	for sx2 in [-1.0, 1.0]:
		_box(p, Vector3(0.06, 0.06, pz * 2.0), Vector3(float(sx2) * px, size.y * 0.92, 0.0), frame)
		# Open cage rails (a solid grating panel rendered as an opaque slab
		# and hid the serpentine — thin horizontal wires read as mesh better).
		for ry in [0.25, 0.85, 1.45, 2.05, 2.45]:
			_box(p, Vector3(0.02, 0.02, pz * 1.94), Vector3(float(sx2) * px, ry, 0.0), frame)
	_box(p, Vector3(px * 2.0, 0.06, 0.06), Vector3(0.0, size.y * 0.92, pz), frame)
	_box(p, Vector3(px * 2.0, 0.06, 0.06), Vector3(0.0, size.y * 0.92, -pz), frame)

	# ── Vendor placard on the +X top rail. ───────────────────────────────────
	if not ghost:
		var plc := _stencil_label(p, "GLOBAL SPIRAL CHUTES  MOD. 260",
			Vector3(0.9, 0.10, 0.01), "+X")
		plc.position = Vector3(px + 0.05, size.y * 0.86, -pz * 0.4)

static func _m_ringleiding(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var pipe := _mat(color, ghost, 0.7, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var ring_y : float = size.y * 0.85
	var pipe_r : float = 0.18
	var half : float = size.x * 0.4          # half side-length of the square loop
	# Four straight pipe runs forming the rectangle: two along X, two along Z.
	for sz in [-1.0, 1.0]:
		_cyl(p, pipe_r, pipe_r, half * 2.0, Vector3(0.0, ring_y, float(sz) * half), pipe, "x")
	for sx in [-1.0, 1.0]:
		_cyl(p, pipe_r, pipe_r, half * 2.0, Vector3(float(sx) * half, ring_y, 0.0), pipe, "z")
	# Small corner blocks to close the loop visually at each junction.
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_box(p, Vector3(pipe_r * 2.2, pipe_r * 2.2, pipe_r * 2.2),
				Vector3(float(cx) * half, ring_y, float(cz) * half), pipe)
	# Three vertical drop pipes hanging from the loop toward the floor.
	var drop_r : float = 0.14
	for drop in [Vector3(half, 0.0, 0.0), Vector3(-half * 0.5, 0.0, half), Vector3(-half, 0.0, -half * 0.5)]:
		_cyl(p, drop_r, drop_r, ring_y * 0.9, Vector3(drop.x, ring_y * 0.55, drop.z), dark)
	# Four support uprights holding the ring up (at the corners, just inside).
	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			_box(p, Vector3(0.08, ring_y, 0.08),
				Vector3(float(sx2) * half, ring_y * 0.5, float(sz2) * half), dark)
	# #212.10 — yellow wire-mesh safety cage around the loops (4 vertical posts
	# + 3 horizontal rails forming a cuboid frame). All cylinders for that
	# fabricated-tube safety-cage look.
	var safety_yel := _mat(Color(0.95, 0.75, 0.10), ghost, 0.2, 0.6)
	var cage_h : float = ring_y * 1.20
	var ch : float = half * 1.10
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_cyl(p, 0.025, 0.025, cage_h,
				Vector3(float(cx) * ch, cage_h * 0.5, float(cz) * ch),
				safety_yel, "y")
	# 3 horizontal rails at varying heights running both directions.
	for ry in [cage_h * 0.18, cage_h * 0.55, cage_h * 0.95]:
		for sz in [-1.0, 1.0]:
			_cyl(p, 0.025, 0.025, ch * 2.0,
				Vector3(0.0, ry, float(sz) * ch), safety_yel, "x")
		for sx in [-1.0, 1.0]:
			_cyl(p, 0.025, 0.025, ch * 2.0,
				Vector3(float(sx) * ch, ry, 0.0), safety_yel, "z")
	# Small wall-mounted manifold: BoxMesh 0.3 × 0.4 × 0.15 grey, with 2 small
	# ball-valves and 1 round gauge on the front face.
	var grey_man := _mat(Color(0.55, 0.57, 0.60), ghost, 0.3, 0.5)
	var mx : float = ch * 0.98
	var my : float = ring_y * 0.85
	_box(p, Vector3(0.15, 0.40, 0.30),
		Vector3(mx, my, 0.0), grey_man)
	# 2 ball valves (small cylinder bodies with red handles).
	var valve_red := _mat(Color(0.82, 0.16, 0.14), ghost, 0.3, 0.5)
	for vz in [-0.08, 0.08]:
		_cyl(p, 0.04, 0.04, 0.10,
			Vector3(mx + 0.08, my - 0.10, vz), grey_man, "x")
		_box(p, Vector3(0.04, 0.10, 0.02),
			Vector3(mx + 0.15, my - 0.10, vz), valve_red)
	# Round gauge above the valves.
	_cyl(p, 0.05, 0.05, 0.03,
		Vector3(mx + 0.08, my + 0.10, 0.0), grey_man, "x")

# ── thermal_dryer (thermische droger): a TALL vertical insulated hot-air column
#    (fluid-bed tower) on a tapered hopper bottom. Visually distinct from the
#    horizontal-drum mech_dryer. Primarily a vessel — no required rotor. ─────────
# ── Thermal dryer: tall insulated cyclone drying tower with rotary airlock valve ────
# ── Thermische droger, BUITEN GEBRUIK (3B) — ruling 3.1-C, operator 2026-08-28.
#    The REAL machine form (both lines had this model): a flat SPIRAL CABINET,
#    ~2×2 m from the front and 30-35 cm thick. Material enters mid-face, runs
#    4-5 spiral loops from the inside outward, and exits at the side. The
#    heater elements sit in the REMOVABLE SIDE PANELS. On 3B it was replaced
#    by the plasmaq and stands DISCONNECTED: a ~20 cm pipe stub sticks out
#    into nothing. (3A's working twin IS the rondmeng "ring" — the ringleiding
#    placeable's remodel to this spec is a detail-program item.) ──────────────
static func _m_thermal_dryer_decommissioned(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.45, 0.5)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var seam  := _mat(Color(0.42, 0.42, 0.45), ghost, 0.5, 0.5)

	var cab_w : float = size.x * 0.94       # ~2.0 m face width
	var cab_h : float = 2.0                 # ~2 m face height
	var cab_t : float = 0.34                # 30-35 cm thick
	var base_y : float = 0.18
	var cy : float = base_y + cab_h * 0.5

	# Four stubby feet + the flat cabinet body.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(p, Vector3(0.08, base_y, 0.08),
				Vector3(float(sx) * cab_w * 0.42, base_y * 0.5, float(sz) * cab_t * 0.35), dark)
	_box(p, Vector3(cab_w, cab_h, cab_t), Vector3(0.0, cy, 0.0), shell)

	# Removable SIDE PANELS (the heater elements live behind them): seam lines
	# + two lift handles per panel on both ±X flanks.
	for sx2 in [-1.0, 1.0]:
		var px : float = float(sx2) * (cab_w * 0.5 + 0.005)
		_box(p, Vector3(0.015, cab_h * 0.92, cab_t * 0.92), Vector3(px, cy, 0.0), seam)
		for hy in [-0.3, 0.3]:
			_box(p, Vector3(0.05, 0.03, 0.12), Vector3(px + float(sx2) * 0.02, cy + cab_h * hy, 0.0), dark)

	# NO spiral shown on the face: the 4-5-loop spiral is INTERNAL (operator:
	# "it's basically like a spiral" describing the inside) — the real
	# exterior is plain sheet metal. Two render attempts at a spiral "hint"
	# (stacked discs, then ring collars) both read as a speaker cone; plain
	# panels with the blanked inlet + stub are the doc-faithful exterior.

	# Mid-face inlet: BLANKED OFF (the feed was rerouted to the plasmaq) — a
	# bolted blind flange where the entry pipe used to be.
	_cyl(p, 0.11, 0.11, 0.05, Vector3(0.0, cy, cab_t * 0.5 + 0.03), steel, "z")
	_cyl(p, 0.13, 0.13, 0.015, Vector3(0.0, cy, cab_t * 0.5 + 0.06), dark, "z")

	# THE 20 cm STUB — the side exit pipe that "sticks out. And then there's
	# nothing." Open flange, no duct: the signature of the decommissioning.
	_cyl(p, 0.10, 0.10, 0.20, Vector3(cab_w * 0.5 + 0.10, cy + cab_h * 0.28, 0.0), steel, "x")
	_cyl(p, 0.125, 0.125, 0.02, Vector3(cab_w * 0.5 + 0.21, cy + cab_h * 0.28, 0.0), dark, "x")

static func _m_thermal_dryer(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.45, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.55)
	var steel := _mat(_STEEL, ghost, 0.65, 0.35)
	var orange := _mat(Color(0.85, 0.42, 0.12), ghost, 0.3, 0.5)
	var dial_mat := _mat(Color(0.92, 0.92, 0.90), ghost, 0.1, 0.7)

	var leg_top : float = size.y * 0.14
	_legs(p, size, leg_top, dark)
	_box(p, Vector3(size.x * 0.92, 0.06, size.z * 0.92), Vector3(0.0, leg_top, 0.0), steel)

	# Motorized rotary airlock star-valve at the bottom hopper discharge
	_cyl(p, size.x * 0.14, size.x * 0.14, size.z * 0.28, Vector3(0.0, leg_top + 0.12, 0.0), dark, "z")
	_motor_unit(p, size.x * 0.10, size.z * 0.18, Vector3(0.0, leg_top + 0.12, size.z * 0.22), "z", ghost)

	# Conical cyclone bottom hopper
	var col_r : float = size.x * 0.38
	var hop_h : float = size.y * 0.18
	_cyl(p, col_r, col_r * 0.32, hop_h, Vector3(0.0, leg_top + 0.24 + hop_h * 0.5, 0.0), shell)

	# Tall insulated vertical drying column
	var body_h : float = size.y * 0.52
	var body_cy : float = leg_top + 0.24 + hop_h + body_h * 0.5
	_cyl(p, col_r, col_r, body_h, Vector3(0.0, body_cy, 0.0), shell)

	# Interactive cone inspection & cleanout door on the lower cyclone
	var _td_hatch := _interactive_hatch(p, Vector3(0.03, 0.35, 0.35),
		Vector3(col_r * 0.85, leg_top + 0.24 + hop_h * 0.5, 0.0), "Thermal Dryer Cyclone Hatch", 95.0, 1.0, steel, ghost)
	if not ghost:
		_box(_td_hatch, Vector3(0.02, 0.18, 0.18), Vector3(0.02, 0.0, 0.0), MaterialPalette.mat_glass_inspection_grime())

	# Flanged insulation clamp rings along the column
	for t in [0.25, 0.5, 0.75]:
		var ry : float = leg_top + 0.24 + hop_h + body_h * float(t)
		_cyl(p, col_r * 1.05, col_r * 1.05, 0.08, Vector3(0.0, ry, 0.0), steel)

	# Dual analog temperature dials on the column face (+Z)
	for ty in [body_cy - size.y * 0.12, body_cy + size.y * 0.12]:
		_cyl(p, 0.045, 0.045, 0.02, Vector3(0.0, ty, col_r + 0.02), dial_mat, "z")
		_cyl(p, 0.055, 0.055, 0.015, Vector3(0.0, ty, col_r + 0.01), dark, "z")

	# Hot-air supply heating duct & blower connection (+X)
	var duct_len : float = size.x * 0.24
	var duct_cx : float = minf(col_r + duct_len * 0.5, size.x * 0.5 - duct_len * 0.5)
	_cyl(p, size.x * 0.11, size.x * 0.11, duct_len,
		Vector3(duct_cx, leg_top + 0.24 + hop_h + body_h * 0.10, 0.0), orange, "x")
	_cyl(p, size.x * 0.16, size.x * 0.16, 0.04,
		Vector3(duct_cx + duct_len * 0.45, leg_top + 0.24 + hop_h + body_h * 0.10, 0.0), steel, "x")

	# Top exhaust cyclone collector head with weather cowl
	var top_y : float = leg_top + 0.24 + hop_h + body_h
	_cyl(p, col_r * 0.65, col_r * 0.90, size.y * 0.06, Vector3(0.0, top_y + size.y * 0.03, 0.0), shell)
	_cyl(p, size.x * 0.12, size.x * 0.12, size.y * 0.09, Vector3(0.0, top_y + size.y * 0.10, 0.0), dark)
	_cyl(p, size.x * 0.20, size.x * 0.04, size.y * 0.04, Vector3(0.0, top_y + size.y * 0.16, 0.0), steel)

# ══════════════════════════════════════════════════════════════════════════════
# LINE 1 MACHINES (#62)
# ══════════════════════════════════════════════════════════════════════════════

# ── metal detector: a rectangular steel PORTAL/arch a belt passes through ────
static func _m_metaaldetector(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel  := _mat(color, ghost, 0.55, 0.4)
	var dark   := _mat(_DARK, ghost, 0.4, 0.6)
	var coil_b := _mat(Color(0.12, 0.14, 0.18), ghost, 0.35, 0.55)
	var copper := _mat(Color(0.78, 0.42, 0.18), ghost, 0.65, 0.50)
	var bin    := _mat(Color(0.42, 0.45, 0.50), ghost, 0.45, 0.55)
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)
	var red    := _mat(Color(0.82, 0.16, 0.14), ghost, 0.2, 0.6)
	var green  := _mat(Color(0.20, 0.78, 0.30), ghost, 0.0, 0.5)
	var screen := _mat(Color(0.07, 0.10, 0.14), ghost, 0.1, 0.25)

	var deck_y : float = size.y * 0.34
	var belt_w : float = size.x * 0.50
	var belt_l : float = size.z * 0.94
	var belt_deck := _box(p, Vector3(belt_w, 0.05, belt_l),
		Vector3(0.0, deck_y, 0.0), dark)
	if not ghost:
		belt_deck.material_override = make_belt_material(0.5, Vector2(1.0, belt_l * 0.5))

	if not ghost:
		var belt_col := CollisionShape3D.new()
		var belt_box := BoxShape3D.new()
		belt_box.size = Vector3(belt_w, 0.4, belt_l)
		belt_col.shape = belt_box
		belt_col.position = Vector3(0.0, deck_y - 0.2, 0.0)
		p.add_child(belt_col)

	for sxr in [-1.0, 1.0]:
		_box(p, Vector3(0.05, 0.12, belt_l),
			Vector3(float(sxr) * (belt_w * 0.5 + 0.025), deck_y + 0.10, 0.0), steel)

	var roller_r : float = size.y * 0.06
	var det_belt_a := _spinning_cyl(p, roller_r, roller_r, belt_w + 0.06,
		Vector3(0.0, deck_y - roller_r * 0.3, -belt_l * 0.5 + 0.04),
		steel, "x", Vector3.RIGHT, ghost, 30.0)
	var det_belt_b := _spinning_cyl(p, roller_r, roller_r, belt_w + 0.06,
		Vector3(0.0, deck_y - roller_r * 0.3,  belt_l * 0.5 - 0.04),
		steel, "x", Vector3.RIGHT, ghost, 30.0)
	if not ghost:
		det_belt_a.set_meta("comp", "belt")
		det_belt_b.set_meta("comp", "belt")

	_legs(p, size, deck_y - 0.1, dark)
	_motor_unit(p, size.y * 0.10, size.x * 0.28,
		Vector3(belt_w * 0.5 + size.x * 0.18, deck_y - roller_r * 0.4, belt_l * 0.32),
		"x", ghost)

	var coil_z      : float = size.z * 0.10
	var coil_thick  : float = size.y * 0.16
	var coil_inner_w : float = belt_w + 0.20
	var coil_inner_h : float = size.y * 0.50
	var coil_outer_w : float = coil_inner_w + coil_thick * 2.0
	var coil_depth   : float = size.z * 0.20
	var coil_cy      : float = deck_y + coil_inner_h * 0.5 + 0.05

	_box(p, Vector3(coil_outer_w, coil_thick, coil_depth),
		Vector3(0.0, coil_cy + coil_inner_h * 0.5 + coil_thick * 0.5, coil_z), coil_b)
	_box(p, Vector3(coil_outer_w, coil_thick, coil_depth),
		Vector3(0.0, deck_y - coil_thick * 0.6, coil_z), coil_b)
	for sxc in [-1.0, 1.0]:
		_box(p, Vector3(coil_thick, coil_inner_h, coil_depth),
			Vector3(float(sxc) * (coil_inner_w * 0.5 + coil_thick * 0.5), coil_cy, coil_z), coil_b)

	for cb in [-coil_depth * 0.30, 0.0, coil_depth * 0.30]:
		_box(p, Vector3(coil_outer_w + 0.04, coil_thick * 0.40, 0.04),
			Vector3(0.0, coil_cy + coil_inner_h * 0.5 + coil_thick * 0.5, coil_z + cb), copper)
		_box(p, Vector3(coil_outer_w + 0.04, coil_thick * 0.40, 0.04),
			Vector3(0.0, deck_y - coil_thick * 0.6, coil_z + cb), copper)
		for sxw in [-1.0, 1.0]:
			_box(p, Vector3(0.04, coil_inner_h, 0.04),
				Vector3(float(sxw) * (coil_inner_w * 0.5 + coil_thick * 0.5), coil_cy, coil_z + cb), copper)

	# Reject bin
	var bin_w : float = belt_w + 0.30
	var bin_h : float = size.y * 0.28
	var bin_d : float = size.z * 0.18
	var bin_y : float = deck_y - bin_h - 0.05
	var bin_z : float = -belt_l * 0.5 - bin_d * 0.55
	var bin_t : float = 0.04
	_box(p, Vector3(bin_w, bin_t, bin_d), Vector3(0.0, bin_y + bin_t * 0.5, bin_z), bin)
	_box(p, Vector3(bin_w, bin_h, bin_t), Vector3(0.0, bin_y + bin_h * 0.5, bin_z - bin_d * 0.5 + bin_t * 0.5), bin)
	_box(p, Vector3(bin_w, bin_h, bin_t), Vector3(0.0, bin_y + bin_h * 0.5, bin_z + bin_d * 0.5 - bin_t * 0.5), bin)
	for sxb in [-1.0, 1.0]:
		_box(p, Vector3(bin_t, bin_h, bin_d),
			Vector3(float(sxb) * (bin_w * 0.5 - bin_t * 0.5), bin_y + bin_h * 0.5, bin_z), bin)
	for sxl in [-1.0, 1.0]:
		for szl in [-1.0, 1.0]:
			var blg := _box(p, Vector3(0.08, bin_y, 0.08),
				Vector3(float(sxl) * bin_w * 0.40, bin_y * 0.5,
						bin_z + float(szl) * bin_d * 0.40), dark)
			blg.add_to_group("machine_leg")
			blg.set_meta("leg_h", bin_y)
	_box(p, Vector3(bin_w * 0.55, bin_h * 0.45, 0.02),
		Vector3(0.0, bin_y + bin_h * 0.70, bin_z + bin_d * 0.5 + 0.012), yellow)
	_box(p, Vector3(bin_w * 0.50, bin_h * 0.08, 0.025),
		Vector3(0.0, bin_y + bin_h * 0.70, bin_z + bin_d * 0.5 + 0.018), red)

	# Interactive HMI Cabinet on +X
	var hmi_x : float = belt_w * 0.5 + size.x * 0.22
	var hmi_cy : float = coil_cy
	_box(p, Vector3(0.10, size.y * 0.55, size.z * 0.16),
		Vector3(hmi_x, hmi_cy, coil_z + size.z * 0.04), steel)

	var _hmi_door := _interactive_hatch(p, Vector3(0.02, size.y * 0.50, size.z * 0.14),
		Vector3(hmi_x + 0.05, hmi_cy, coil_z + size.z * 0.04), "Metal Detector HMI Door", 100.0, 1.0, steel, ghost)
	if not ghost:
		_box(_hmi_door, Vector3(0.01, size.y * 0.30, size.z * 0.10),
			Vector3(0.01, size.y * 0.05, 0.0), screen)

	_cyl(p, 0.025, 0.025, 0.05, Vector3(hmi_x + 0.07, hmi_cy - size.y * 0.14, coil_z + size.z * 0.04 + 0.04), green, "x")
	_cyl(p, 0.025, 0.025, 0.05, Vector3(hmi_x + 0.07, hmi_cy - size.y * 0.20, coil_z + size.z * 0.04 + 0.04), red,   "x")
	# Big red E-stop near the bottom of the panel.
	_cyl(p, 0.04, 0.04, 0.04, Vector3(hmi_x + 0.07, hmi_cy - size.y * 0.26, coil_z + size.z * 0.04 - 0.04), red, "x")

# ── VW trommel (drum screen): a large rotating perforated DRUM, slightly inclined,
#    held in a support frame. Drum SPINS about its long (Z) axis. Single-drive (no
#    "comp" tag — the LineFlow fallback drives it). size = (2.4, 2.6, 4.5). ───────
## VW trommel (voorwastrommel) — Line 1 pre-wash drum, photo-accurate rebuild.
## A large 50,000 L stainless drum (~3 m ⌀ × ~7 m long) rotating slowly about its
## long (Z) axis with a ~4° downhill incline. Built from 3 bolted sections.
## Supported on FOUR SOLID INDUSTRIAL RUBBER TIRES in two pairs (one near each
## end), not stainless rollers. Drive end has a bolted flange ring, axial-thrust
## bracket, and a stainless discharge collar; the drum exhausts into a grated
## drain tray underneath. Enclosed by a yellow peeling-paint safety cage with
## an embossed capacity placard reading "TANK A-4 / MAX CAP 50,000 L".
##
## All materials pulled from MaterialPalette so future visual passes stay
## consistent. The drum still uses _spinning_cyl so it animates at runtime.

## Local position of the TOP of the vw_trommel's feed-funnel mouth (the -Z
## intake cone) for a trommel of `size`. SINGLE SOURCE OF TRUTH shared by
## _m_vw_trommel (which places the cone with it) and the westa_band_1 spec in
## _build_opzetband (which aims its 45° discharge at it) — so the belt and the
## funnel can never drift apart when the trommel is resized (the 2026-08-28
## C5 swap did exactly that: the belt kept aiming at the old stub's 6.5 m top
## while the real trommel's mouth sits at ~4.15 m).
static func vw_trommel_funnel_mouth_local(size: Vector3) -> Vector3:
	var drum_r  : float = minf(size.x * 0.46, 1.55)
	var drum_cy : float = size.y * 0.12 + drum_r + 0.18     # leg_top + r + clearance
	var drum_len : float = size.z * 0.85
	# Cone centre sits at drum_cy + r*0.75; the cone is size.y*0.32 tall, so the
	# mouth (top face) is half that above the centre.
	return Vector3(0.0, drum_cy + drum_r * 0.75 + size.y * 0.16, -drum_len * 0.55)

static func _m_vw_trommel(p: Node3D, size: Vector3, _color: Color, ghost: bool) -> void:
	var P = MaterialPalette
	var shell    : StandardMaterial3D = P.mat_stainless_weathered()
	var seam     : StandardMaterial3D = P.mat_steel_dark_aged()
	var tire     : StandardMaterial3D = P.mat_rubber_tire_solid()
	var cage_yel : StandardMaterial3D = P.mat_paint_yellow_peeling()
	var frame_bl : StandardMaterial3D = P.mat_paint_blue_oxidised()
	var aged     : StandardMaterial3D = P.mat_steel_dark_aged()
	var stainless: StandardMaterial3D = P.mat_steel_galvanised()
	var grating  : StandardMaterial3D = P.mat_grating_steel()
	var placard  : StandardMaterial3D = P.mat_text_embossed_dark()
	var i_red    : StandardMaterial3D = P.mat_indicator_red()
	var i_grn    : StandardMaterial3D = P.mat_indicator_green()
	var i_blu    : StandardMaterial3D = P.mat_indicator_blue()

	var W := size.x; var H := size.y; var D := size.z
	var drum_r   : float = minf(W * 0.46, 1.55)                 # ~1.5 m for 50,000 L
	var drum_len : float = D * 0.85                              # leave space for collars
	var leg_top  : float = H * 0.12                              # foundation height
	var drum_cy  : float = leg_top + drum_r + 0.18               # drum centre Y

	# ── SPINNING DRUM (stainless, weathered, 3 sections with raised seam rings) ─
	var drum := _spinning_cyl(p, drum_r, drum_r, drum_len,
		Vector3(0.0, drum_cy, 0.0), shell, "z", Vector3.BACK, ghost, 14.0)
	if not ghost:
		drum.rotation.x = deg_to_rad(-4.0)                       # downhill incline
	var band_y : float = 0.0 if not ghost else drum_cy
	# Three raised seam rings (proud discs) at the section joints, plus an end
	# ring at each end (typical for a sectional welded shell).
	for t_band in [-0.40, -0.13, 0.13, 0.40]:
		_cyl(drum, drum_r * 1.06, drum_r * 1.06, 0.10,
			Vector3(0.0, band_y, drum_len * float(t_band)), seam, "z")
	# Embossed text placard (capacity / TANK ID) on the drum side — dark recessed.
	_box(drum, Vector3(1.40, 0.30, 0.012),
		Vector3(0.0, band_y + drum_r * 0.55, drum_len * -0.32), placard)
	_box(drum, Vector3(0.95, 0.18, 0.012),
		Vector3(0.0, band_y + drum_r * 0.40, drum_len * -0.32), placard)

	# ── BOLTED FLANGE DRIVE RING at the +Z end (segmented circle with bolt heads) ─
	var flange_z : float = drum_len * 0.5 + 0.10
	_cyl(drum, drum_r * 1.18, drum_r * 1.18, 0.14, Vector3(0.0, band_y, flange_z), aged, "z")
	# Bolt heads ringing the flange.
	for k in 16:
		var ang : float = float(k) * TAU / 16.0
		var bx : float = cos(ang) * drum_r * 1.10
		var by : float = sin(ang) * drum_r * 1.10
		_box(drum, Vector3(0.06, 0.06, 0.04),
			Vector3(bx, band_y + by, flange_z + 0.08), aged)
	# Stainless discharge collar (shroud) just past the flange.
	_cyl(p, drum_r * 0.95, drum_r * 0.95, 0.50,
		Vector3(0.0, drum_cy, drum_len * 0.5 + 0.50), stainless, "z")

	# ── FEED HOPPER + INPUT CHUTE at the -Z (high) end ─────────────────────────
	# Placed via vw_trommel_funnel_mouth_local() (mouth = cone TOP, so the cone
	# centre is half its height below it) — the same function the westa_band_1
	# spec aims at. Change the cone there, not here.
	var funnel_mouth := vw_trommel_funnel_mouth_local(size)
	_cyl(p, drum_r * 0.55, drum_r * 0.30, H * 0.32,
		funnel_mouth - Vector3(0.0, H * 0.16, 0.0), aged)

	# ── SOLID-TIRE SUPPORT ROLLERS (two pairs, one near each end) ──────────────
	# Each pair has TWO tires below the drum, angled inward like trommel cradle
	# wheels. They sit on heavy steel pedestals on the foundation slab.
	var tire_r : float = 0.45
	var tire_w : float = 0.30
	var ped_h  : float = drum_cy - drum_r * 0.65 - tire_r
	for sz in [-0.32, 0.32]:                                    # near each drum end
		for sx in [-1.0, 1.0]:                                  # left + right cradle
			var tx : float = float(sx) * (drum_r * 0.65)
			var tz : float = float(sz) * drum_len
			# Pedestal box.
			_box(p, Vector3(0.30, ped_h, 0.40), Vector3(tx, ped_h * 0.5 + 0.12, tz), frame_bl)
			# Tire (solid rubber, axle along X).
			_cyl(p, tire_r, tire_r, tire_w,
				Vector3(tx, ped_h + 0.12 + tire_r, tz), tire, "x")
			# Bright steel hub at axle.
			_cyl(p, 0.10, 0.10, tire_w + 0.02,
				Vector3(tx, ped_h + 0.12 + tire_r, tz), stainless, "x")

	# ── AXIAL THRUST ASSEMBLY UNIT — small bolted bracket with ID plate ────────
	var thrust_x : float = drum_r * 1.30
	var thrust_y : float = drum_cy
	var thrust_z : float = drum_len * 0.40
	_box(p, Vector3(0.30, 0.40, 0.30), Vector3(thrust_x, thrust_y, thrust_z), frame_bl)
	# ID plate on the thrust bracket (dark recessed).
	_box(p, Vector3(0.20, 0.14, 0.008),
		Vector3(thrust_x + 0.16, thrust_y, thrust_z), placard)

	# ── FOUNDATION SLAB + DRAIN GRATING TRAY underneath the drum ───────────────
	var slab := _box(p, Vector3(W * 0.95, 0.10, D * 0.92),
		Vector3(0.0, 0.07, 0.0), aged)                          # slab base
	slab.add_to_group("machine_foot")
	slab.set_meta("foot_y", 0.07)
	# Grating bars running along Z, ten parallel bars across the X span.
	var n_bars : int = 11
	for k in n_bars:
		var bx : float = -drum_r * 0.9 + float(k) * (drum_r * 1.8 / float(n_bars - 1))
		_box(p, Vector3(0.05, 0.04, drum_len * 0.85),
			Vector3(bx, leg_top, 0.0), grating)

	# ── STATUS DISPLAY PANEL on the drive base (3 dark dials + indicator LEDs) ─
	var disp_x : float = -drum_r * 1.10
	var disp_y : float = drum_cy * 0.55
	var disp_z : float = drum_len * 0.42
	_box(p, Vector3(0.55, 0.20, 0.04), Vector3(disp_x, disp_y, disp_z), placard)
	for k in 3:
		var dx : float = disp_x - 0.18 + float(k) * 0.18
		_cyl(p, 0.012, 0.012, 0.012, Vector3(dx, disp_y, disp_z + 0.025),
			[i_red, i_grn, i_blu][k], "z")

	# ── YELLOW PEELING-PAINT SAFETY CAGE (front + back rails with interactive access gate) ──
	var cage_h : float = drum_cy + drum_r * 1.10
	for sx in [-1.0, 1.0]:
		var cx : float = float(sx) * (drum_r + 0.45)
		# Vertical posts at each end.
		_box(p, Vector3(0.06, cage_h, 0.06), Vector3(cx, cage_h * 0.5, -drum_len * 0.5), cage_yel)
		_box(p, Vector3(0.06, cage_h, 0.06), Vector3(cx, cage_h * 0.5,  drum_len * 0.5), cage_yel)
		if sx < 0.0:
			# Interactive safety cage access gate on -X side
			var cage_gate := _interactive_hatch(p, Vector3(0.04, cage_h * 0.85, drum_len * 0.45),
				Vector3(cx, cage_h * 0.5, 0.0), "Trommel Safety Cage Gate", 95.0, 1.0, cage_yel, ghost)
			if not ghost:
				# Grimy transparent viewing window in the gate
				_box(cage_gate, Vector3(0.02, cage_h * 0.35, drum_len * 0.25),
					Vector3(0.02, 0.0, 0.0), MaterialPalette.mat_glass_inspection_grime())
				_box(cage_gate, Vector3(0.03, 0.12, 0.03), Vector3(0.03, 0.0, drum_len * 0.18), aged)
		else:
			# Fixed horizontal rails on +X side
			_box(p, Vector3(0.06, 0.10, drum_len * 1.00), Vector3(cx, cage_h - 0.12, 0.0), cage_yel)
			_box(p, Vector3(0.06, 0.08, drum_len * 1.00), Vector3(cx, cage_h * 0.55, 0.0), cage_yel)
			_box(p, Vector3(0.06, 0.08, drum_len * 1.00), Vector3(cx, 0.20, 0.0), cage_yel)
		# Wire-mesh stand-in: 14 vertical thin bars per side.
		for k in 14:
			var bz : float = -drum_len * 0.46 + float(k) * (drum_len * 0.92 / 13.0)
			_box(p, Vector3(0.012, cage_h - 0.40, 0.010),
				Vector3(cx, cage_h * 0.5 + 0.10, bz), stainless)

	# Floor legs (auto-extend on raise per #70).
	_legs(p, size, leg_top, aged)
	# #212.9 — large solid rubber drive contact wheel pressing against the
	# trommel shell perpendicular to the drum axis. Real prewash trommels are
	# driven by a friction wheel against the outer shell; this adds the
	# missing visual.
	if not ghost:
		var rubber := _mat(Color(0.15, 0.15, 0.15), ghost, 0.0, 0.95)
		_cyl(p, 0.18, 0.18, 0.12,
			Vector3(drum_r + 0.18, drum_cy - drum_r * 0.55, 0.0), rubber, "z")
		# Hub at the centre of the drive wheel.
		_cyl(p, 0.04, 0.04, 0.14,
			Vector3(drum_r + 0.18, drum_cy - drum_r * 0.55, 0.0), stainless, "z")
		# Capacity stencil "TANK A   MAX CAP 50000(L)" on the side of the
		# trommel (uses the file-top helper).
		var cap_lbl := _stencil_label(p, "TANK A   MAX CAP 50000(L)",
			Vector3(1.40, 0.20, 0.01), "+X")
		cap_lbl.position = Vector3(drum_r + 0.02, drum_cy + drum_r * 0.20, drum_len * -0.10)

	# ── BORDES (grate) + STAIRS — operator's line-1 drawing 2026-08-28
	# (line1_washing_flow_sketch: yellow grate walkway along the drum with
	# stairs at the upstream end). Rafter-#231 idiom: grated deck at working
	# height on the -X aisle flank, safety-yellow railing on the outer edge,
	# grating stair descending at the -Z (chute/upstream) end.
	var bordes_y : float = drum_cy - drum_r * 0.55          # deck under the drum's belly line
	var bordes_w : float = 0.95
	var bordes_x : float = -(drum_r + bordes_w * 0.5 + 0.05)
	var bordes_len : float = drum_len * 0.92
	var safety := _mat(_SAFETY, ghost, 0.2, 0.6)
	var b_dark := _mat(_DARK, ghost, 0.5, 0.6)
	var b_steel := _mat(_STEEL, ghost, 0.5, 0.4)
	_grating_deck(p, bordes_w, bordes_len, Vector3(bordes_x, bordes_y, 0.0))
	# Deck support legs to the floor.
	for szb in [-0.42, 0.0, 0.42]:
		_box(p, Vector3(0.07, bordes_y, 0.07),
			Vector3(bordes_x - bordes_w * 0.35, bordes_y * 0.5, bordes_len * szb), b_dark)
	# Railing along the OUTER (-X) edge + the two ends; open toward the drum.
	for szr in [-1.0, 1.0]:
		_box(p, Vector3(0.05, 0.05, bordes_len), Vector3(bordes_x - bordes_w * 0.48, bordes_y + 1.0, 0.0), safety)
		_box(p, Vector3(0.05, 1.0, 0.05), Vector3(bordes_x - bordes_w * 0.48, bordes_y + 0.5, float(szr) * bordes_len * 0.48), safety)
	_box(p, Vector3(0.05, 0.05, bordes_len), Vector3(bordes_x - bordes_w * 0.48, bordes_y + 0.55, 0.0), safety)
	# Stair down at the -Z (upstream/chute) end, descending away from the drum.
	_stair(p, Vector3(bordes_x, bordes_y, -bordes_len * 0.5 - 0.1), bordes_y, bordes_w * 0.8, b_steel, safety)

# ── scheidingsgoot — the Y-SPLITGOOT at the discharge end of the SGA drum. ────
# Operator spec 2026-08-28 (line-1 HPS/SGA doc walk), verbatim:
#   "at the end of the drum there is a Y-shaped shute also, which splits the
#    material+water stream left and right (about 1m long 30 deg down angle, then
#    the split, then a steeper 60 deg down angle, where left is about 35 deg to
#    the left and the right side about 35 deg to the right, both for about 1m,
#    then both sides turn straight (in line with the drum orientation) while
#    still feeding material+water into the next machine)"
# Open U-channel throughout — it carries WATER as well as film, so no lid.
# Was a plain straight U-trough until this walk; the split was faked entirely by
# LineFlow's scheidingsgoot→friction_sep connector rule, so the machine that
# actually does the splitting had no splitting geometry.
# #196's direction is preserved: material enters at +Z (under the drum's
# discharge) and runs downhill toward -Z, where LineFlow still spawns the
# glijgoot connectors on to the two friction washers.
static func _m_scheidingsgoot(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.4)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)

	var leg_w : float = size.x * 0.44            # channel width of ONE branch (~0.70 m)
	var wall_h : float = 0.22
	var inlet_y : float = size.y * 0.92          # under the SGA drum's discharge mouth
	var start := Vector3(0.0, inlet_y, size.z * 0.48)

	# 1) STEM — ~1 m at 30° down, straight. Double width: both legs still share
	#    one channel until the split.
	var stem_end := _goot_segment(p, start, 1.0, 30.0, 0.0, leg_w * 2.0, wall_h, steel)

	# Splitter nose — the wedge that divides the stream left/right.
	_box(p, Vector3(0.06, wall_h * 1.4, 0.34),
		stem_end + Vector3(0.0, wall_h * 0.7, -0.16), dark)

	# 2) BRANCHES — ~1 m at 60° down, yawed ~35° out, then
	# 3) RUN-OUTS — each leg turns back straight (yaw 0, in line with the drum
	#    axis) and keeps feeding the next machine.
	# +yaw is toward -X (see _goot_segment), so 35.0 = left leg, -35.0 = right.
	for yaw in [35.0, -35.0]:
		var br_end := _goot_segment(p, stem_end, 1.0, 60.0, yaw, leg_w, wall_h, steel)
		var out_end := _goot_segment(p, br_end, 0.8, 15.0, 0.0, leg_w, wall_h, steel)
		# Open discharge lip so the leg reads as feeding, not holding.
		_box(p, Vector3(leg_w * 1.05, 0.05, 0.08), out_end + Vector3(0.0, -0.02, 0.0), dark)

	# Four floor legs that lengthen to the floor when raised (#70).
	_legs(p, size, size.y * 0.28, dark)

## One straight open-U segment of a goot: floor plate + two side walls, pitched
## `pitch_deg` below horizontal and yawed `yaw_deg` (POSITIVE = toward -X).
## Travel runs along the pivot's local -Z. Returns the segment's END point in
## `parent` space so segments chain without hand-baked coordinates.
static func _goot_segment(parent: Node3D, start: Vector3, length: float, \
		pitch_deg: float, yaw_deg: float, width: float, wall_h: float, \
		mat: StandardMaterial3D) -> Vector3:
	var pitch := deg_to_rad(pitch_deg)
	var yaw   := deg_to_rad(yaw_deg)
	var piv := Node3D.new()
	piv.position = start
	# Godot's default YXZ euler order: a NEGATIVE x-rotation tips local -Z DOWN.
	piv.rotation = Vector3(-pitch, yaw, 0.0)
	parent.add_child(piv)
	_box(piv, Vector3(width, 0.05, length), Vector3(0.0, 0.0, -length * 0.5), mat)
	for sx in [-1.0, 1.0]:
		_box(piv, Vector3(0.05, wall_h, length),
			Vector3(float(sx) * width * 0.5, wall_h * 0.5, -length * 0.5), mat)
	# End point = start + R·(0,0,-L), with R = Ry(yaw)·Rx(-pitch).
	return start + Vector3(
		-sin(yaw) * cos(pitch),
		-sin(pitch),
		-cos(yaw) * cos(pitch)) * length

# ── SGA invoergoot — the 90° corner chute at the drum head. ───────────────────
# Operator 2026-08-28: "there is actually a chute after the belt that feeds
# material into the drum on the top side (and it makes a 90 deg right turn from
# the conveyor to the drum)". The flow diagrams draw BLOCKS only and never show
# chutes, so this one is operator-described, not doc-derived. The layout sketch
# places it at the head of the ONE drum (vw_trommel), at the leg-C → leg-D
# corner of the line-1 fold.

## Port geometry for the sga_feed_chute. Placed nodes face the flow (rotation
## leg_rot+PI), so local -Z is the UPSTREAM face and local -X is the RIGHT of
## the flow — the operator's "90 deg right turn".
##   in     — top of the infeed leg, on the upstream (-Z) face (westa's lip
##            discharges onto this point + a small drop).
##   corner — the corner pan where the stream turns.
##   out    — discharge lip end of the outfeed leg (-X side), hangs over the
##            vw_trommel feed funnel.
## SINGLE SOURCE OF TRUTH shared by _m_sga_feed_chute (geometry), the
## westa_band_1 spec (aims its lip at `in`), and the derivations behind
## LINE_1_SEQ's baked y/gap/turn_advance numbers — all guarded live by
## test_line1_flow_conformance S4/S4b.
static func sga_feed_chute_ports_local(size: Vector3) -> Dictionary:
	var infeed_len := 0.62
	var infeed_pitch := deg_to_rad(20.0)
	var out_len := 0.85
	var out_pitch := deg_to_rad(28.0)
	var p_in := Vector3(0.0, size.y * 0.88, -size.z * 0.46)
	var corner := p_in + Vector3(0.0, -infeed_len * sin(infeed_pitch), infeed_len * cos(infeed_pitch))
	var p_out := corner + Vector3(-out_len * cos(out_pitch), -out_len * sin(out_pitch), 0.0)
	return {"in": p_in, "corner": corner, "out": p_out,
		"infeed_len": infeed_len, "out_len": out_len}

static func _m_sga_feed_chute(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.5, 0.4)
	var dark  := _mat(_DARK, ghost, 0.5, 0.6)

	var w : float = size.x * 0.42
	var wall_h : float = 0.24
	var ports := sga_feed_chute_ports_local(size)
	var p_in : Vector3 = ports["in"]
	var corner : Vector3 = ports["corner"]
	var p_out : Vector3 = ports["out"]

	# 1) INFEED leg — from the upstream (-Z) face down to the corner
	#    (_goot_segment yaw 180 → travel +Z), mild 20° drop.
	_goot_segment(p, p_in, float(ports["infeed_len"]), 20.0, 180.0, w, wall_h, steel)

	# 2) CORNER PAN + deflector plates that turn the stream 90° RIGHT (-X).
	_box(p, Vector3(w * 1.25, 0.05, w * 1.25), corner + Vector3(0.0, -0.03, 0.0), steel)
	_box(p, Vector3(w * 1.25, wall_h * 1.5, 0.05),
		corner + Vector3(0.0, wall_h * 0.75, w * 0.60), dark)     # splash plate, far (+Z) side
	_box(p, Vector3(0.05, wall_h * 1.5, w * 1.25),
		corner + Vector3(w * 0.60, wall_h * 0.75, 0.0), steel)    # outer cheek, +X (opposite the exit)

	# 3) OUTFEED leg — the right turn itself: _goot_segment yaw +90 → travel
	#    -X, 28° down, ending over the drum's feed funnel.
	_goot_segment(p, corner, float(ports["out_len"]), 28.0, 90.0, w, wall_h, steel)
	# Downward-facing discharge lip over the funnel mouth.
	_box(p, Vector3(0.06, 0.18, w * 1.05), p_out + Vector3(-0.03, -0.09, 0.0), dark)

	_legs(p, size, size.y * 0.30, dark)

# ── MAS droger (dryer): a compact horizontal drying drum unit (smaller / different
#    proportions than mech_dryer). Drum SPINS about its long (Z) axis. End flanges,
#    a small heater/blower box on one side, floor legs. Single-drive. size = (2.0,
#    2.4, 3.0). ──────────────────────────────────────────────────────────────────
# ── MAS droger (dryer): high-efficiency mechanical centrifugal dryer with sound-insulated casing ──────
static func _m_mas_droger(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell := _mat(color, ghost, 0.45, 0.45)
	var dark := _mat(_DARK, ghost, 0.5, 0.6)
	var steel := _mat(_STEEL, ghost, 0.65, 0.35)
	var orange := _mat(Color(0.85, 0.45, 0.12), ghost, 0.3, 0.55)   # heater/blower accent
	var drum_r : float = size.x * 0.42
	var drum_len : float = size.z * 0.78
	var leg_top : float = size.y * 0.22
	var drum_cy : float = leg_top + drum_r

	# Heavy structural skid with vibration damping mounts
	_box(p, Vector3(size.x * 0.94, 0.10, size.z * 0.94), Vector3(0.0, leg_top - 0.05, 0.0), dark)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(p, 0.10, 0.10, 0.08, Vector3(sx * size.x * 0.42, 0.04, sz * size.z * 0.42), dark, "y")
	_legs(p, size, leg_top, dark)

	# Main octagonal dryer casing along Z — high-speed rotating rotor inside
	var drum_rm := _spinning_cyl(p, drum_r, drum_r, drum_len,
		Vector3(0.0, drum_cy, 0.0), shell, "z", Vector3.BACK, ghost, 60.0)

	# Reinforcing circumferential ribs along the casing
	var band_base_y : float = 0.0 if not ghost else drum_cy
	for bi in [-0.28, 0.0, 0.28]:
		_cyl(drum_rm, drum_r * 1.04, drum_r * 1.04, 0.08, Vector3(0.0, band_base_y, drum_len * bi), steel, "z")

	# Bolted end flanges with machined seal faces
	for sz in [-1.0, 1.0]:
		_cyl(p, drum_r * 1.10, drum_r * 1.10, 0.10,
			Vector3(0.0, drum_cy, float(sz) * drum_len * 0.5), dark, "z")

	# Interactive hinged maintenance door on the -X side with 4 stainless locking handwheels
	var door_node := _interactive_hatch(p, Vector3(0.04, drum_r * 1.2, drum_len * 0.65),
		Vector3(-drum_r * 0.96, drum_cy, 0.0), "MAS Dryer Maintenance Door", 115.0, 1.0, shell, ghost)
	if not ghost:
		for dhy in [-0.25, 0.25]:
			for dhz in [-0.18, 0.18]:
				_cyl(door_node, 0.035, 0.035, 0.05,
					Vector3(-0.02, dhy * drum_r, dhz * drum_len), steel, "x")
				_box(door_node, Vector3(0.015, 0.08, 0.02),
					Vector3(-0.04, dhy * drum_r, dhz * drum_len), dark)

	# Tangential pneumatic infeed chute at -Z and dry flake discharge cyclone at +Z
	_cyl(p, size.x * 0.12, size.x * 0.12, size.z * 0.26, Vector3(size.x * 0.25, drum_cy + drum_r * 0.5, -size.z * 0.42), steel, "z")
	_box(p, Vector3(size.x * 0.40, size.y * 0.32, size.z * 0.20),
		Vector3(0.0, drum_cy + drum_r * 0.4, size.z * 0.44), steel)

	# Water drainage siphon trap at the bottom of the drum
	_cyl(p, 0.06, 0.06, 0.28, Vector3(0.0, leg_top + 0.05, 0.0), dark, "y")
	_cyl(p, 0.05, 0.05, size.x * 0.45, Vector3(size.x * 0.22, leg_top + 0.05, 0.0), steel, "x")

	# Blower / motor drive unit at -Z
	_motor_unit(p, size.x * 0.18, size.z * 0.20,
		Vector3(-size.x * 0.36, drum_cy, -size.z * 0.44), "z", ghost)

# ── Extruder feed silo (#89): elevated light-grey BOX on a steel frame, with a
#    yellow guardrail platform on top, 4 inspection windows in 2 column-pairs on
#    the front, and TWO cyclones (one over each window pair) discharging DOWN into
#    the silo. The whole assembly fits inside size = W(X) × total-H(Y) × D(Z).
#    Underside of the box sits at ~size.y*0.40 (≈2.5 m) so the extruder + a lump
#    bin live beneath. The 4 corner legs are tagged "machine_leg" + meta "leg_h"
#    so the shared extend_machine_legs() runs them to the floor when raised (#70).
static func _m_extruder_silo(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var shell  := _mat(color, ghost, 0.35, 0.55)               # light-grey silo skin
	var steel  := _mat(_STEEL, ghost, 0.6, 0.4)                # frame / ribs / cyclones
	var dark   := _mat(_DARK, ghost, 0.4, 0.6)                 # legs / outlet / window frame
	var glass  := _mat(Color(0.10, 0.12, 0.16), ghost, 0.3, 0.4)  # dark inspection windows
	var yellow := _mat(_SAFETY, ghost, 0.2, 0.6)               # safety-yellow guardrails
	var white  := _mat(Color(0.92, 0.92, 0.90), ghost, 0.1, 0.7)  # danger-sign plate
	var red    := _mat(Color(0.82, 0.14, 0.12), ghost, 0.2, 0.6)  # danger-sign strip
	if not ghost:
		# Photo-extracted cream painted steel — the machines/paint_cream_steel
		# triplet was cut from _extruder_silo.png, i.e. this exact machine's
		# photo; guardrails get the calibrated equipment yellow (same colour as
		# _SAFETY). Palette mats are shared opaque singletons, so ghosts keep
		# the translucent _mat above.
		shell = MaterialPalette.mat_paint_cream_steel()
		yellow = MaterialPalette.mat_paint_safety_yellow()

	# #99 — hw/hd retained as comments; the legs/braces now use bw/bd half-extents
	# so the support frame catches the widened silo body.
	var frame_top : float = size.y * 0.40    # silo underside / leg top ≈ 2.6 m
	var box_top   : float = size.y * 0.92     # top of the silo box ≈ 5.98 m
	var box_h     : float = box_top - frame_top
	var box_cy    : float = (frame_top + box_top) * 0.5
	# #98 — operator: silo body 50% wider. Followed by #99 — operator: widen the
	# whole silo by ANOTHER 50% (radius * 1.5) WITHOUT changing window dimensions
	# or column positions in world units. Cumulative scale = 1.5 * 1.5 = 2.25,
	# applied RADIALLY (both X and Z) so the cylindrical body bulks out symmetrically
	# around the fixed inspection-port layout. Scale ONLY the shell box + ribs +
	# top deck (via bw/bd), NOT the frame legs / cyclone columns / window column
	# spacing — those keep size.x calibration so windows stay at their absolute
	# width and X position in world units regardless of how fat the body gets.
	var body_scale_x : float = 2.25
	var bw : float = size.x * 0.96 * body_scale_x   # box width (X) — widened (radial)
	var bd : float = size.z * 0.96 * body_scale_x   # box depth (Z) — widened (radial)

	# ── SUPPORT FRAME: 4 vertical corner legs floor→underside, tagged machine_leg ──
	# #99 — leg footprint follows the widened body (bw/bd) so the frame catches the
	# fatter silo at the corners rather than collapsing inside it. Half-extents come
	# from bw/bd not hw/hd.
	var leg_w : float = 0.14
	var lx : float = bw * 0.5 - leg_w * 0.6
	var lz : float = bd * 0.5 - leg_w * 0.6
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var lg := _box(p, Vector3(leg_w, frame_top, leg_w),
				Vector3(sx * lx, frame_top * 0.5, sz * lz), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", frame_top)
	# Horizontal cross-braces at two heights, around the perimeter (X-spans + Z-spans).
	for by in [frame_top * 0.45, frame_top * 0.92]:
		_box(p, Vector3(lx * 2.0, 0.09, 0.09), Vector3(0.0, by,  lz), steel)
		_box(p, Vector3(lx * 2.0, 0.09, 0.09), Vector3(0.0, by, -lz), steel)
		_box(p, Vector3(0.09, 0.09, lz * 2.0), Vector3( lx, by, 0.0), steel)
		_box(p, Vector3(0.09, 0.09, lz * 2.0), Vector3(-lx, by, 0.0), steel)
	# Diagonal X-braces on the two side faces (±X) for a braced-frame read.
	var brace_len : float = sqrt(frame_top * frame_top + (lz * 2.0) * (lz * 2.0))
	for sx in [-1.0, 1.0]:
		for sgn in [1.0, -1.0]:
			var diag := _box(p, Vector3(0.06, 0.06, brace_len),
				Vector3(sx * lx, frame_top * 0.5, 0.0), steel)
			diag.rotation.x = sgn * atan2(lz * 2.0, frame_top)

	# ── SILO BOX: light-grey body occupying the upper portion, full W×D ──────────
	_box(p, Vector3(bw, box_h, bd), Vector3(0.0, box_cy, 0.0), shell)
	# Horizontal stiffener ribs wrapping the box faces (proud of the skin).
	# #99 — rib 2 (i=2, Y≈4.628) is OMITTED because the lifted bottom window
	# (#99 lift +0.37) now spans 4.339..4.947 and would be cut in half by it.
	# Ribs 0, 1, 3 remain; rib 3 (i=3, Y≈5.338, topmost) doubles as the top
	# frame edge of the top window (see WINDOWS block below).
	for i in 4:
		if i == 2:
			continue  # #99: rib 2 crosses the lifted bottom window — omit
		var rib_y : float = frame_top + box_h * (0.18 + 0.21 * float(i))
		_box(p, Vector3(bw + 0.06, 0.07, bd + 0.06), Vector3(0.0, rib_y, 0.0), steel)

	# ── WINDOWS: tall thin recessed dark rectangles on BOTH ±Z faces ─────────────
	# Two columns per face — LEFT pair at -X, RIGHT pair at +X.
	# #98 — was front-face only; mirrored to the -Z face per operator.
	# #98 — operator: window WIDTHS halved. #99 — operator: HALVE THEM AGAIN
	# (cumulative 0.04 = 25% of original 0.16). Window widths are in world-unit
	# size.x terms so they stay constant when the body widens (#99).
	# OPERATOR PASS (post-resize): with the silo footprint shrunk to its
	# correct W=1.80 / D=2.13 m, the prior halvings made the inspection windows
	# unreadably narrow. Restored to the original 0.16 × size.x coefficient so
	# the four ports read as actual sight glasses against the much narrower
	# body. With size.x = 1.80 → win_w ≈ 0.29 m — a real human-scale window.
	# #99 — operator: LIFT bottom windows by +0.37 m (half the gap between
	# top-of-bottom-window and bottom-of-top-window in the prior layout). After
	# the lift, rib 2 at Y=4.628 now CROSSES the bottom window (window spans
	# 4.339..4.947, rib spans 4.593..4.663), so rib 2 is REMOVED in the rib loop
	# above (now 3 ribs not 4).
	# #99 — operator: keep the TOPMOST rib (rib 3, Y=5.338) and use its bottom
	# edge (5.303) as the TOP edge of the top window. The top window is REPOSITIONED
	# below rib 3 (was tucked above it under the box ceiling). Its bottom must
	# clear the lifted bottom window top (4.947) — a 0.05 m steel separator gives
	# bottom-window-top → top-window-bottom = 5.000. Top window height = 0.303
	# (shrunk from 0.608) so it spans 5.000..5.303 cleanly between bottom window
	# and rib 3 used-as-frame-top.
	var win_w_top : float = size.x * 0.16         # operator pass: restored from 0.04
	var win_w_bot : float = size.x * 0.16         # operator pass: restored from 0.04
	# Bottom window keeps its prior height; it just rises by 0.37.
	var win_h_bottom : float = box_h * 0.18        # 0.608 — unchanged
	# Top window shrinks so its TOP aligns with rib 3 bottom and its BOTTOM clears
	# the lifted bottom window top with a 0.05 m frame gap.
	var win_h_top : float = 0.303                  # #99: top window shrunk to fit
	# Bottom window center: prior 4.273 + 0.370 = 4.643.
	var rib_mid_y : float = frame_top + box_h * (0.18 + 0.21 * 1.0)   # 3.918 — still present
	var rib_upper_y : float = frame_top + box_h * (0.18 + 0.21 * 2.0) # 4.628 — REMOVED in rib loop
	var bot_cy : float = (rib_mid_y + rib_upper_y) * 0.5 + 0.37       # 4.273 + 0.37 = 4.643
	# Top window center: top edge = rib_top_y - rib_half (5.338 - 0.035 = 5.303),
	# so center = 5.303 - win_h_top * 0.5 = 5.303 - 0.1515 = 5.1515.
	var rib_top_y : float = frame_top + box_h * (0.18 + 0.21 * 3.0)   # 5.338
	var top_y : float = (rib_top_y - 0.035) - win_h_top * 0.5         # ≈ 5.1515
	for face_sz in [1.0, -1.0]:
		var face_z : float = face_sz * (bd * 0.5 + 0.015)
		# `out_n` is the local +Z direction of the surround/glass meshes so the
		# light frame sits BEHIND the glass relative to the face normal on both
		# sides. Without this the back-face windows render inside-out.
		var surround_offset : float = -0.01 * face_sz
		for col_x in [-size.x * 0.22, size.x * 0.22]:
			# TOP window — narrow, halved width, top edge flush under topmost rib.
			_box(p, Vector3(win_w_top + 0.08, win_h_top + 0.08, 0.02),
				Vector3(col_x, top_y, face_z + surround_offset), steel)
			_box(p, Vector3(win_w_top, win_h_top, 0.03),
				Vector3(col_x, top_y, face_z), glass)
			# BOTTOM window — halved width, shrunk + lifted to sit between
			# the two middle ribs (3.918 and 4.628) with no overlap.
			_box(p, Vector3(win_w_bot + 0.08, win_h_bottom + 0.08, 0.02),
				Vector3(col_x, bot_cy, face_z + surround_offset), steel)
			_box(p, Vector3(win_w_bot, win_h_bottom, 0.03),
				Vector3(col_x, bot_cy, face_z), glass)
	# #98 — operator: the previous arbitrary white-and-black stripe with a red
	# centre line on the +Z face is NOT on the reference photo. Removed.
	var _ignored_red := red
	var _ignored_white := white

	# ── TWO CYCLONES on top, one centred over each window column ─────────────────
	# Reuse the _m_cyclone silhouette (cylindrical body + cone) but mounted so the
	# cone tip points DOWN into the silo box (gravity discharge). Sized + lowered so
	# the highest point (the clean-air outlet) stays at/just under size.y.
	var cyc_r : float = size.x * 0.16
	var cone_tip_y : float = box_top - 0.55             # tip dips ≈0.55 m into the box
	var cone_h : float = 0.62
	var body_h : float = 0.42
	for cx in [-size.x * 0.25, size.x * 0.25]:
		# Downward discharge cone (wide at the top, narrow tip into the silo).
		_cyl(p, cyc_r, 0.06, cone_h, Vector3(cx, cone_tip_y + cone_h * 0.5, 0.0), steel)
		# Cylindrical body sitting on the cone.
		var body_cy : float = cone_tip_y + cone_h + body_h * 0.5
		_cyl(p, cyc_r, cyc_r, body_h, Vector3(cx, body_cy, 0.0), shell)
		# Central clean-air outlet pipe up the middle (only a short stub overshoots).
		_cyl(p, cyc_r * 0.34, cyc_r * 0.34, 0.20,
			Vector3(cx, body_cy + body_h * 0.5 + 0.06, 0.0), steel)
		# Tangential feed inlet box near the top of the body (kept inside the X half-width).
		_box(p, Vector3(cyc_r * 1.1, body_h * 0.45, cyc_r * 0.7),
			Vector3(cx + cyc_r * 0.7, body_cy + body_h * 0.18, 0.0), steel)

	# ── TOP PLATFORM: flat deck at the silo top + safety-yellow guardrails ───────
	_box(p, Vector3(bw + 0.10, 0.05, bd + 0.10), Vector3(0.0, box_top + 0.03, 0.0), steel)
	# #98 — guardrail leaves the -X side OPEN so the ladder lands cleanly on the
	# deck. The push-gate (built below) takes over the fall-protection job there.
	_railing(p, (bw + 0.10) * 0.5, (bd + 0.10) * 0.5, box_top + 0.05, yellow, ["-x"])

	# ── #98 INDUSTRIAL CAGED LADDER + SELF-CLOSING PUSH-GATE ─────────────────────
	# Industrial caged access ladder mounted on the -X face of the (widened) silo
	# body, climbing from floor (Y=0) up to just above the deck. The cage hoops
	# in `_caged_ladder` open toward the climber's chest (+Z by default), so we
	# wrap the ladder in a Node3D rotated -90° about Y → cage now opens toward
	# +X, which is exactly the direction the climber needs to step OFF the
	# ladder and ONTO the deck. The push-gate sits at the deck edge directly
	# above the ladder top, swinging into +X (onto the deck) so the climber
	# pushes through it on the way up, and it auto-closes behind them.
	var ladder_h : float = box_top + 0.10            # floor → just above deck
	var ladder_x : float = -bw * 0.5 - 0.30          # clear of the silo shell
	var ladder_root := Node3D.new()
	ladder_root.name = "SiloAccessLadder"
	ladder_root.rotation.y = -PI * 0.5               # cage now faces +X (toward deck)
	ladder_root.position = Vector3(ladder_x, 0.0, 0.0)
	p.add_child(ladder_root)
	_caged_ladder(ladder_root, Vector3.ZERO, ladder_h, steel, ghost)
	# Push-gate body — built inline so build_node()'s ghost path stays cheap, then
	# attached to a PushGate script at the end. In ghost-mode we skip the script.
	var gate_y : float = box_top + 0.05                     # deck top
	var gate_x_edge : float = -bw * 0.5 - 0.05              # at -X deck edge
	var gate_root : Node3D
	if ghost:
		gate_root = Node3D.new()
	else:
		var pg_script := load("res://src/build/PushGate.gd")
		gate_root = StaticBody3D.new()
		if pg_script != null:
			(gate_root as StaticBody3D).set_script(pg_script)
			# Free side = -X (the ladder side); platform side = +X (requires E).
			gate_root.set("free_side_idx", 1)
	gate_root.name = "SiloPushGate"
	gate_root.position = Vector3(gate_x_edge, gate_y, 0.0)
	p.add_child(gate_root)
	# Two yellow vertical posts at ±Z half-width, one mid-rail + one top-rail.
	_box(gate_root, Vector3(0.05, 1.05, 0.05),
		Vector3(0.0, 0.525,  0.23), yellow)
	_box(gate_root, Vector3(0.05, 1.05, 0.05),
		Vector3(0.0, 0.525, -0.23), yellow)
	_box(gate_root, Vector3(0.04, 0.04, 0.46),
		Vector3(0.0, 1.00, 0.0), yellow)
	_box(gate_root, Vector3(0.04, 0.04, 0.46),
		Vector3(0.0, 0.55, 0.0), yellow)
	# Small spring-hinge cue at the hinge edge (visual only).
	_cyl(gate_root, 0.02, 0.02, 0.10,
		Vector3(0.0, 0.20, 0.23), steel)
	# Collision body for the gate leaf so the player can't walk through it
	# closed (PushGate re-parents this under HingePivot on _ready).
	if not ghost:
		var col := CollisionShape3D.new()
		var col_box := BoxShape3D.new()
		col_box.size = Vector3(0.08, 1.05, 0.46)
		col.shape = col_box
		col.position = Vector3(0.0, 0.525, 0.0)
		gate_root.add_child(col)

	# ── DISCHARGE: previously a downward outlet cone at the box bottom centre.
	# Operator-corrected: the silo has a FLAT bottom — no protruding cone tip.
	# Material drops straight down to the extruder beneath the elevated box.

	# #98 — Lumps belong on a SEPARATE placeable (the wheeled `lump_cart`), parked
	# under the extruder's screen-changer outlet — NOT on the feed silo. Earlier
	# this block modelled a side-mounted catch bin + lump samples on the silo
	# itself, which was operator-corrected. Removed; place a `lump_cart` from the
	# build menu at the extruder filter discharge instead.

	# ── #89 FILM-LEVEL VIEW: sparse off-white flake fill ONLY visible behind the
	# windows (no point rendering bulk fill the user can't see — saves draw calls
	# AND matches reality: the silo body is opaque, you only see flake through the
	# inspection ports). Per operator: in equilibrium the level LEANS toward the
	# compactor-belt side (the silo's discharge), because material settles into
	# the cone above the outlet. We render the BACK-of-box (further from the
	# discharge — i.e. the inside surface visible through the upper windows) with
	# a LOWER flake profile, and the FRONT-of-box surface (right behind the
	# inspection ports) with a HIGHER flake profile, so the eye reads "more
	# material has piled up here near the outlet" through the glass. Tuned to
	# match the four-window layout above (two columns × two rows on +Z).
	var flake_mat := _mat(Color(0.86, 0.84, 0.78), ghost, 0.05, 0.85)
	var win_z : float = bd * 0.5 + 0.015   # restored for the flake-pile block below
	# #98 — windows were resized + repositioned above; references to the old
	# `win_h` / `win_w` are now to the per-row split values.
	var row_data := [
		{"cy": bot_cy, "win_h": win_h_bottom, "win_w": win_w_bot, "factor": 0.70},
		{"cy": top_y,  "win_h": win_h_top,    "win_w": win_w_top, "factor": 0.30},
	]
	for col_x in [-size.x * 0.22, size.x * 0.22]:
		for row in row_data:
			var w_cy : float = float((row as Dictionary)["cy"])
			var row_win_h : float = float((row as Dictionary)["win_h"])
			var row_win_w : float = float((row as Dictionary)["win_w"])
			# Flake pile thicker for the LOWER window row (more accumulation toward
			# the bottom of the silo where the cone narrows) — also closer to the
			# glass surface to read clearly through it.
			var pile_h : float = row_win_h * float((row as Dictionary)["factor"])
			var pile_z_offset : float = -0.05         # 5 cm behind the +Z window plane
			# Small cluster of flake clumps spanning the window width, with a slight
			# downward slope from the back (-Z side, into the box) toward the
			# compactor-belt face (+Z, the discharge side). 4 clumps per window.
			var clump_w : float = row_win_w * 0.22
			var clump_h : float = pile_h * 0.55
			var base_y : float = w_cy - row_win_h * 0.5 + clump_h * 0.5
			for ci in 4:
				var t : float = float(ci) / 3.0   # 0..1 across the window width
				var clump_x : float = col_x - row_win_w * 0.5 * 0.7 + row_win_w * 0.7 * t
				# Slope: the back of the silo (deeper -Z) holds slightly LESS flake
				# (it slid forward toward the discharge) — the front clumps sit
				# slightly higher, riding on top of the settled cone toward outlet.
				var clump_y : float = base_y + (t * 0.10) * pile_h
				_box(p, Vector3(clump_w, clump_h, 0.10),
					Vector3(clump_x, clump_y, win_z + pile_z_offset - 0.06), flake_mat)
				# Second-row clump behind the first to give depth through the glass.
				_box(p, Vector3(clump_w * 0.85, clump_h * 0.7, 0.08),
					Vector3(clump_x, clump_y + clump_h * 0.45, win_z + pile_z_offset - 0.15), flake_mat)

# ── Consolidated extruder UNIT (#92): ONE model = the whole EREMA-style line,
#    reconstructed REAR(-Z)->FRONT(+Z) from the operator's 5 photos. Sim brands:
#    EREMA (barrel), Wave-Cut Systems (pelletizer), Integrated Process Solutions
#    (filter modules), C-2 Process Unit (rotary laser-filter disc). Sections:
#    feed/cutter-compactor TOWER → gearbox + screw motor + main HMI → clad BARREL
#    (stainless rounded hood over navy cabinets) → C-2 rotary LASER-FILTER disc on
#    top → twin white FILTER MODULES A/B → MELTPUMP → WAVE-CUT PELLETIZER cabinet
#    (granulate out the front). Used by Extruders 3A/3B/1/3C + the front half of
#    Line 6. All support legs are machine_leg-tagged so they reach the floor when
#    the unit is raised (#63/#70). ───────────────────────────────────────────────
static func _m_extruder_unit(p: Node3D, size: Vector3, color: Color, ghost: bool, line_tag : String = "") -> void:
	var steel  := _mat(_STEEL, ghost, 0.6, 0.35)                     # brushed stainless
	var navy   := _mat(Color(0.16, 0.22, 0.42), ghost, 0.25, 0.55)  # navy lower cabinets
	var dark   := _mat(_DARK, ghost, 0.5, 0.6)                       # legs / frames / detailing
	var body   := _mat(color, ghost, 0.3, 0.5)                       # per-id accent (gearbox / pump / base block)
	var white  := _mat(Color(0.92, 0.92, 0.90), ghost, 0.1, 0.75)   # filter modules A/B
	var blackm := _mat(Color(0.06, 0.06, 0.07), ghost, 0.3, 0.6)    # hoods / swirl cap / louvers
	var red    := _mat(Color(0.82, 0.14, 0.12), ghost, 0.2, 0.6)    # E-stops / brake lever
	var glass  := _mat(Color(0.10, 0.12, 0.16), ghost, 0.3, 0.4)    # HMI touchscreens
	var flakes := _mat(Color(0.80, 0.80, 0.78), ghost, 0.1, 0.8)    # flakes behind PCU sight-glass
	var _gunk   := _mat(Color(0.10, 0.07, 0.05), ghost, 0.2, 0.6)    # contaminant in filter windows
	var gold   := _mat(Color(0.78, 0.62, 0.22), ghost, 0.5, 0.4)    # Wave-Cut roundel gold
	var teal   := _mat(Color(0.16, 0.55, 0.55), ghost, 0.4, 0.4)    # EREMA / Wave-Cut accent

	var barrel_cy : float = size.y * 0.31                  # barrel centreline ≈ 1.30 m
	var barrel_leg_h : float = barrel_cy * 0.15            # skid leg top, just under the navy cabinet (cabinet underside = barrel_cy*0.56 - barrel_cy*0.41)
	var hood_r : float = size.x * 0.33
	var hood_cy : float = barrel_cy * 0.95
	var hood_top : float = hood_cy + hood_r                # top surface of the clad barrel

	# ═══ BARREL SPINE (centre): skid legs + navy cabinet + stainless rounded hood ═══
	for sz in [-0.30, 0.0, 0.30]:
		for sx in [-1.0, 1.0]:
			var lg := _box(p, Vector3(0.12, barrel_leg_h, 0.12),
				Vector3(sx * size.x * 0.30, barrel_leg_h * 0.5, sz * size.z), dark)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", barrel_leg_h)
	_box(p, Vector3(size.x * 0.66, barrel_cy * 0.82, size.z * 0.62),
		Vector3(0.0, barrel_cy * 0.56, -size.z * 0.02), navy)                                  # navy lower cabinet
	_cyl(p, hood_r, hood_r, size.z * 0.62, Vector3(0.0, hood_cy, -size.z * 0.02), steel, "z")  # clad rounded-top hood
	_cyl(p, size.x * 0.13, size.x * 0.13, size.z * 0.60, Vector3(0.0, barrel_cy, -size.z * 0.02), dark, "z")  # melt barrel within
	# flush pull-handle access hatches on the hood top
	for hzc in [-size.z * 0.18, size.z * 0.02, size.z * 0.20]:
		_box(p, Vector3(size.x * 0.22, 0.03, size.z * 0.05), Vector3(0.0, hood_top + 0.005, hzc), dark)
		_box(p, Vector3(0.12, 0.04, 0.03), Vector3(size.x * 0.07, hood_top + 0.04, hzc), steel)
	# EREMA roundel + wordmark on the +X navy panel
	_cyl(p, size.x * 0.07, size.x * 0.07, 0.03, Vector3(size.x * 0.34, barrel_cy * 0.55, -size.z * 0.18), teal, "x")
	_box(p, Vector3(0.02, size.x * 0.05, size.x * 0.28), Vector3(size.x * 0.335, barrel_cy * 0.55, -size.z * 0.05), steel)
	# #212.3 EREMA brand decal — 0.4 × 0.1 m white-on-navy stencil on the +X
	# face of the navy lower cabinet, with a faint emissive so it reads under
	# work-lighting. The decal sits just below the wordmark bar.
	if not ghost:
		var erema_navy := _mat(Color(0.16, 0.22, 0.42), ghost, 0.25, 0.55)
		erema_navy.emission_enabled = true
		erema_navy.emission = Color(0.16, 0.22, 0.42)
		erema_navy.emission_energy_multiplier = 0.10
		_box(p, Vector3(0.005, 0.10, 0.40),
			Vector3(size.x * 0.34, barrel_cy * 0.35, -size.z * 0.05), erema_navy)
		var erema_lbl := _stencil_label(p, "EREMA",
			Vector3(0.40, 0.10, 0.01), "+X")
		erema_lbl.position = Vector3(size.x * 0.345, barrel_cy * 0.35, -size.z * 0.05)
		if line_tag != "":
			# #223 docs->code: per-line barrel stencil (LINE ONLY, no position number) —
			# docs/plant/swi/TRAIN-laserfilter-p3A__112_CeDo32.md ("ter hoogte van nr 3");
			# operator: the extruder is simply "right after line 3A". Second decal beside EREMA.
			var line_navy := _mat(Color(0.16, 0.22, 0.42), ghost, 0.25, 0.55)
			line_navy.emission_enabled = true
			line_navy.emission = Color(0.16, 0.22, 0.42)
			line_navy.emission_energy_multiplier = 0.10
			_box(p, Vector3(0.005, 0.17, 0.28),
				Vector3(size.x * 0.34, barrel_cy * 0.74, -size.z * 0.05), line_navy)
			var line_lbl := _stencil_label(p, line_tag,
				Vector3(0.26, 0.15, 0.01), "+X")
			line_lbl.position = Vector3(size.x * 0.345, barrel_cy * 0.74, -size.z * 0.05)

	# ═══ BARREL HEATER-ZONE BANDS (distinct heated zones along the clad barrel) ═══
	# #223 docs->code: TRAIN-extruderen-p3__108_CeDo24.md — "de extruderschroef
	# bestaat uit een aantal zones"; the deck lists distinct barrel zone setpoints
	# (~7 heated zones). Shown as proud zone-band collars + a small heater/thermo-
	# couple junction box per zone on the +X shoulder. Zone COUNT and spacing are
	# representational — the docs give temperatures, not band positions.
	var heat_band := _mat(Color(0.50, 0.52, 0.55), ghost, 0.5, 0.45)
	for bz in [-0.24, -0.16, -0.08, 0.0, 0.08, 0.16]:
		var hbz : float = size.z * bz
		_cyl(p, hood_r * 1.02, hood_r * 1.02, size.z * 0.012, Vector3(0.0, hood_cy, hbz), heat_band, "z")   # zone band collar
		_box(p, Vector3(0.10, size.x * 0.12, size.z * 0.02), Vector3(hood_r * 0.75, hood_cy + hood_r * 0.70, hbz), dark)  # zone junction box
	# ═══ SECTION 1: FEED / CUTTER-COMPACTOR (PCU) — SIDE-MOUNTED TANGENTIAL INFEED ═══
	# EREMA Intarema canonical design: The PCU cutter-compactor stands on the SIDE (-X)
	# of the extruder feed zone. The rotating cutter disc at the base prepares the polymer,
	# and feeds it tangentially through a horizontal intake slider (opzetschuif)
	# directly into the side of the extruder screw intake at barrel_cy.
	var tw_z : float = -size.z * 0.20                      # adjacent to the screw infeed zone
	var pcu_x : float = -size.x * 0.58                     # side-mounted on the -X flank
	var drum_r : float = size.x * 0.32
	var drum_h : float = size.y * 0.50
	var pcu_leg_h : float = barrel_cy * 0.45
	var drum_base : float = pcu_leg_h
	var drum_cy : float = drum_base + drum_h * 0.5

	# PCU Floor Support Legs
	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			var tl := _box(p, Vector3(0.12, pcu_leg_h, 0.12),
				Vector3(pcu_x + sx2 * drum_r * 0.68, pcu_leg_h * 0.5, tw_z + sz2 * drum_r * 0.68), dark)
			tl.add_to_group("machine_leg")
			tl.set_meta("leg_h", pcu_leg_h)
		_box(p, Vector3(0.08, 0.08, drum_r * 1.36),
			Vector3(pcu_x + sx2 * drum_r * 0.68, pcu_leg_h * 0.55, tw_z), dark)

	# PCU Base Deck Plate
	_box(p, Vector3(drum_r * 2.1, 0.08, drum_r * 2.1),
		Vector3(pcu_x, drum_base + 0.04, tw_z), steel)

	# Stainless PCU Drum Body
	_cyl(p, drum_r, drum_r, drum_h, Vector3(pcu_x, drum_cy, tw_z), steel)
	for ry in [0.25, 0.55, 0.85]:
		_cyl(p, drum_r * 1.03, drum_r * 1.03, size.y * 0.02, Vector3(pcu_x, drum_base + drum_h * ry, tw_z), steel)
	_cyl(p, drum_r * 1.05, drum_r * 1.05, size.y * 0.035, Vector3(pcu_x, drum_base + drum_h, tw_z), steel)
	_cyl(p, drum_r * 0.42, drum_r * 0.42, size.y * 0.14, Vector3(pcu_x, drum_base + drum_h + size.y * 0.07, tw_z), steel)

	# Steam plume rising above PCU
	_install_steam_plume(p,
		Vector3(pcu_x, drum_base + drum_h + size.y * 0.18, tw_z),
		drum_r * 0.25, 2.0, Color(0.96, 0.94, 0.88), ghost)

	# Round sight-glass on operator-facing (+Z) side
	var glass_y : float = drum_cy + 0.15
	_cyl(p, 0.062, 0.062, 0.03, Vector3(pcu_x, glass_y, tw_z + drum_r * 1.00), dark, "z")
	_cyl(p, 0.050, 0.050, 0.02, Vector3(pcu_x, glass_y, tw_z + drum_r * 1.03), glass, "z")
	_cyl(p, 0.044, 0.044, 0.01, Vector3(pcu_x, glass_y, tw_z + drum_r * 0.99), flakes, "z")

	# Cutter disc rotor + bottom drive motor
	var disc_y : float = drum_base + 0.10
	_cyl(p, drum_r * 0.86, drum_r * 0.86, 0.07, Vector3(pcu_x, disc_y, tw_z), dark)
	var mot_x : float = pcu_x - drum_r * 1.30
	_motor_unit(p, size.x * 0.13, size.z * 0.02, Vector3(mot_x, drum_base + 0.10, tw_z), "y", ghost)

	# PCU Control Box with Dual Gauges on the front (-Z) face at standing height
	var pcu_box_cy : float = 1.40
	_box(p, Vector3(0.12, size.y * 0.16, size.y * 0.18), Vector3(pcu_x, pcu_box_cy, tw_z - drum_r - 0.10), body)
	_cyl(p, 0.045, 0.045, 0.03, Vector3(pcu_x - size.y * 0.04, pcu_box_cy + 0.04, tw_z - drum_r - 0.17), dark, "z")
	_cyl(p, 0.045, 0.045, 0.03, Vector3(pcu_x + size.y * 0.04, pcu_box_cy + 0.04, tw_z - drum_r - 0.17), dark, "z")

	# ═══ TANGENTIAL INTAKE SLIDER (intrek / opzetschuif) ═══
	# Direct horizontal throat from PCU side (+X face) to extruder barrel intake (-X face) at barrel_cy.
	var slider_start_x : float = pcu_x + drum_r * 0.70
	var slider_end_x   : float = -size.x * 0.28
	var slider_len_x   : float = absf(slider_end_x - slider_start_x)
	var slider_mid_x   : float = (slider_start_x + slider_end_x) * 0.5
	var slider_h       : float = barrel_cy * 0.42
	var slider_w_z     : float = drum_r * 0.55

	# Horizontal tangential feed housing connecting PCU into the screw
	_box(p, Vector3(slider_len_x, slider_h, slider_w_z),
		Vector3(slider_mid_x, barrel_cy, tw_z), steel)
	# Sliding gate frame + plate
	_box(p, Vector3(0.06, slider_h * 1.15, slider_w_z * 1.15),
		Vector3(slider_mid_x, barrel_cy, tw_z), dark)
	_box(p, Vector3(0.04, slider_h * 0.85, slider_w_z * 0.95),
		Vector3(slider_mid_x, barrel_cy, tw_z + 0.05), steel)
	# Pneumatic cylinder for the intake slider
	_cyl(p, 0.045, 0.045, 0.35,
		Vector3(slider_mid_x, barrel_cy + slider_h * 0.75, tw_z), dark, "z")
	_cyl(p, 0.020, 0.020, 0.20,
		Vector3(slider_mid_x, barrel_cy + slider_h * 0.75, tw_z + 0.22), steel, "z")

	# ═══ SECTION 2: GEARBOX + SCREW-DRIVE MOTOR + MAIN HMI ═══
	var gb_z : float = -size.z * 0.27
	_box(p, Vector3(size.x * 0.6, barrel_cy * 1.05, size.z * 0.09), Vector3(0.0, barrel_cy * 0.7, gb_z), body)  # gearbox housing
	_motor_unit(p, size.x * 0.18, size.z * 0.10, Vector3(0.0, barrel_cy, -size.z * 0.34), "z", ghost)           # screw-drive motor
	var hmi_x : float = size.x * 0.46
	var sc_y : float = barrel_cy * 1.15
	_box(p, Vector3(0.10, sc_y, 0.10), Vector3(hmi_x, sc_y * 0.5, gb_z + size.z * 0.05), dark)                  # pedestal post
	_box(p, Vector3(0.08, 0.34, 0.30), Vector3(hmi_x, sc_y, gb_z + size.z * 0.05), dark)                        # screen box
	_box(p, Vector3(0.03, 0.26, 0.22), Vector3(hmi_x + 0.06, sc_y, gb_z + size.z * 0.05), glass)                # touchscreen +X
	_cyl(p, 0.03, 0.03, 0.05, Vector3(hmi_x + 0.05, sc_y - 0.24, gb_z + size.z * 0.05), red, "x")               # E-stop
	_cyl(p, 0.02, 0.02, 0.04, Vector3(hmi_x + 0.05, sc_y - 0.30, gb_z + size.z * 0.05 - 0.08), teal, "x")       # button
	_cyl(p, 0.02, 0.02, 0.04, Vector3(hmi_x + 0.05, sc_y - 0.30, gb_z + size.z * 0.05 + 0.08), gold, "x")       # button
	_box(p, Vector3(0.01, 0.10, 0.16), Vector3(hmi_x + 0.07, sc_y - 0.42, gb_z + size.z * 0.05), white)         # warning label

	# ═══ SECTION 4: MELT TAKE-OFF STUB (to the STANDALONE laser filter) ═══
	# #225.3 de-dup: the integrated rotary laser-filter disc (spinning zeefschijf
	# A/B + straight-down afvoerschroef discharge) that used to live here was a
	# SECOND disc — the real filter is the standalone `laser_filter` placeable
	# (_m_laser_filter, bound by ExtruderMachine._closest_in_group('laser_filter')).
	# Mirror of the doubled-compactor cleanup in ExtruderGauntlet.gd:115-118.
	# Only a short melt-inlet stub remains on the barrel top so the pipe run to the
	# external filter still reads continuous.
	var c2_z : float = size.z * 0.02
	var stub_r : float = size.x * 0.09
	_cyl(p, stub_r, stub_r, size.x * 0.26, Vector3(0.0, hood_top + size.x * 0.10, c2_z), dark)   # riser stub off the hood
	_cyl(p, stub_r * 1.25, stub_r * 1.25, size.x * 0.04, Vector3(0.0, hood_top + size.x * 0.02, c2_z), steel)  # flange collar

	# ═══ SECTION 5: KOPFILTER — piston-type screen changer at the die head ═══
	# #223 docs->code: rebuilt as the documented PISTON-TYPE SCREEN CHANGER.
	#   docs/plant/swi/TRAIN-de-kopfilter-p5__119_CeDo35.md — "de kopfilter. De
	#   filters in de piston onder en boven kunnen vervangen worden. De filters
	#   bestaan uit 2 steunzeven en het filter." Source drawing 119_CeDo35.pdf
	#   (melt-path photo) shows a TALL vertical EREMA housing with an UPPER and a
	#   LOWER piston station, each carrying two round screen-pack cavities joined
	#   by an S/hourglass melt channel — the final filtration before pelletizing.
	#   OTHER-training-heetafslag-6__098_CeDo36.md places this screen-changer as
	#   the melt-inlet housing of the die-face pelletizer.
	# Geometry tracks src/sim/HeadFilter.gd: each piston is a hydraulic slide
	# carrier with an ONLINE + OFFLINE cavity (one filters while the other is
	# repacked); every pack = 2 steunzeven (support screens) + 1 filter mesh.
	var kf_z : float = size.z * 0.22                       # barrel front, ahead of hood, behind meltpump
	var kf_house_w : float = size.x * 0.46                 # housing width across the melt path (X)
	var kf_house_d : float = size.z * 0.08                 # housing depth (Z)
	var kf_low_y : float = barrel_cy * 1.04                # LOWER piston station (at the melt centreline)
	var kf_up_y : float = barrel_cy * 1.62                 # UPPER piston station
	var kf_bot : float = barrel_cy * 0.82
	var kf_top : float = kf_up_y + barrel_cy * 0.30
	var kf_h : float = kf_top - kf_bot
	# Screen-pack layer materials (119_CeDo35 close-up: coarse steunzeef mesh +
	# fine filter mesh + coarse steunzeef).
	var steun := _mat(Color(0.62, 0.64, 0.66), ghost, 0.7, 0.35)   # steunzeef (coarse support screen)
	var mesh_f := _mat(Color(0.28, 0.28, 0.30), ghost, 0.4, 0.6)   # fine filter mesh (darker)
	# Housing: navy lower third + stainless upper (matches the EREMA cabinet).
	_box(p, Vector3(kf_house_w, kf_h * 0.30, kf_house_d), Vector3(0.0, kf_bot + kf_h * 0.15, kf_z), navy)
	_box(p, Vector3(kf_house_w, kf_h * 0.70, kf_house_d), Vector3(0.0, kf_bot + kf_h * 0.65, kf_z), steel)
	# Inlet stub from the barrel (-Z) into the UPPER station; external S melt-path
	# pipe upper->lower on the front face (the blue route drawn in 119_CeDo35);
	# outlet stub (+Z) from the LOWER station toward the meltpump / die head.
	_cyl(p, size.x * 0.06, size.x * 0.06, size.z * 0.06, Vector3(0.0, kf_up_y, kf_z - kf_house_d * 0.5 - size.z * 0.03), dark, "z")
	_cyl(p, size.x * 0.045, size.x * 0.045, kf_up_y - kf_low_y, Vector3(size.x * 0.11, (kf_low_y + kf_up_y) * 0.5, kf_z + kf_house_d * 0.5 + size.x * 0.03), steel)
	_cyl(p, size.x * 0.06, size.x * 0.06, size.z * 0.06, Vector3(0.0, kf_low_y, kf_z + kf_house_d * 0.5 + size.z * 0.03), dark, "z")
	# UPPER + LOWER piston stations. Each = a horizontal hydraulic slide bolt
	# crossing the melt path (X), a hydraulic actuator cylinder + rod on the -X
	# end, and TWO round screen-pack cavities on the +Z face (online + offline).
	for st in [kf_low_y, kf_up_y]:
		_box(p, Vector3(kf_house_w * 0.94, size.x * 0.24, kf_house_d * 0.72), Vector3(0.0, st, kf_z), steel)        # horizontal slide bolt
		_box(p, Vector3(kf_house_w * 0.64, size.x * 0.30, 0.02), Vector3(0.0, st, kf_z + kf_house_d * 0.5 + 0.005), blackm)  # window surround
		var act_x : float = -kf_house_w * 0.5 - size.x * 0.11
		_cyl(p, size.x * 0.08, size.x * 0.08, size.x * 0.22, Vector3(act_x, st, kf_z), body, "x")                   # hydraulic cylinder
		_cyl(p, size.x * 0.09, size.x * 0.09, 0.05, Vector3(act_x - size.x * 0.13, st, kf_z), dark, "x")            # end cap / clevis
		_cyl(p, size.x * 0.035, size.x * 0.035, kf_house_w * 0.55, Vector3(-kf_house_w * 0.26, st, kf_z), steel, "x")  # actuator rod
		for cx in [-1.0, 1.0]:
			var pack_x : float = cx * size.x * 0.088
			var pf : float = kf_z + kf_house_d * 0.5 - 0.01
			_cyl(p, size.x * 0.075, size.x * 0.075, 0.03, Vector3(pack_x, st, pf), dark, "z")            # steel retaining ring
			_cyl(p, size.x * 0.062, size.x * 0.062, 0.012, Vector3(pack_x, st, pf + 0.020), steun, "z")  # steunzeef (back)
			_cyl(p, size.x * 0.055, size.x * 0.055, 0.012, Vector3(pack_x, st, pf + 0.033), mesh_f, "z")  # filter mesh
			_cyl(p, size.x * 0.062, size.x * 0.062, 0.010, Vector3(pack_x, st, pf + 0.045), steun, "z")  # steunzeef (front)
	# Local ΔP screen-change gauges on the +X face (sim tracks delta_p_psi).
	for gy in [kf_low_y + barrel_cy * 0.34, kf_up_y + barrel_cy * 0.34]:
		_box(p, Vector3(0.02, 0.02, size.x * 0.14), Vector3(kf_house_w * 0.5, gy, kf_z), steel)
		_cyl(p, 0.06, 0.06, 0.03, Vector3(kf_house_w * 0.5 + 0.01, gy, kf_z + size.x * 0.11), dark, "x")
	# ── HEAD-FILTER CABINET (operator photos 2026-07-20) ──────────────────────
	# docs/plant/photos/extruder_2026-07-20/head_filter_cabinet_closed.jpg and
	# gr-HMI_or-laserfilter_bl-vacuumpots_ye-vacuumcatchresiduebin_pu-headfiltercontrol_
	# pi-headfiltercabinetclosed.jpg (pink polygon).
	#
	# The piston screen-changer above is doc-correct and stays — what was missing
	# is the ENCLOSURE around it. The photos show a large floor-standing brushed
	# stainless cabinet, roughly person-height plus, standing clear of the floor on
	# legs, with a chamfered top corner and two vertical door latches down one
	# edge. The operator sees this cabinet, not the changer, unless a door is open
	# (head_filter_cabinet_open_top-cylinder_out_breaker-plate-in.jpg).
	var hfc_w : float = size.x * 1.02          # wider than the barrel — it stands beside it
	var hfc_d : float = kf_house_d * 2.6
	var hfc_leg : float = barrel_cy * 0.30     # cabinet floats clear of the floor
	var hfc_top : float = size.y * 0.66
	var hfc_h : float = hfc_top - hfc_leg
	var hfc_cy : float = hfc_leg + hfc_h * 0.5
	var hfc_mat := _mat(Color(0.72, 0.73, 0.75), ghost, 0.55, 0.42)   # brushed stainless
	if not ghost:
		for sx8 in [-1.0, 1.0]:
			for sz8 in [-1.0, 1.0]:
				var hl := _box(p, Vector3(0.09, hfc_leg, 0.09),
					Vector3(sx8 * hfc_w * 0.42, hfc_leg * 0.5, kf_z + sz8 * hfc_d * 0.38), dark)
				hl.add_to_group("machine_leg")
				hl.set_meta("leg_h", hfc_leg)
	# Main shell + the chamfered top band (the photo's cut corner, approximated as
	# a narrower box on top rather than a true bevel).
	_box(p, Vector3(hfc_w, hfc_h * 0.88, hfc_d), Vector3(0.0, hfc_cy - hfc_h * 0.06, kf_z), hfc_mat)
	_box(p, Vector3(hfc_w * 0.86, hfc_h * 0.12, hfc_d * 0.86),
		Vector3(0.0, hfc_top - hfc_h * 0.06, kf_z), hfc_mat)
	# Two vertical door latches down the +X edge, and the door seam between them.
	_box(p, Vector3(0.02, hfc_h * 0.92, 0.02), Vector3(hfc_w * 0.5 + 0.012, hfc_cy, kf_z - hfc_d * 0.18), dark)
	for lz in [-0.22, 0.20]:
		_box(p, Vector3(0.05, hfc_h * 0.16, 0.05),
			Vector3(hfc_w * 0.5 + 0.03, hfc_cy + hfc_h * lz, kf_z + hfc_d * 0.30), dark)

	# ── HEAD-FILTER CONTROL (purple polygon, same photo) ──────────────────────
	# Was a hand-sized push-button box bolted to the changer housing — invented,
	# no doc. The photos show a SEPARATE narrow FLOOR-STANDING post beside the
	# cabinet, carrying a green running lamp. Rebuilt at standing height so the
	# SWAP / REPACK E-interaction lands on something the operator can walk up to.
	var hfp_x : float = -hfc_w * 0.5 - 0.28
	var hfp_h : float = barrel_cy * 1.35
	_box(p, Vector3(0.06, hfp_h, 0.06), Vector3(hfp_x, hfp_h * 0.5, kf_z - hfc_d * 0.30), dark)
	_box(p, Vector3(0.16, size.x * 0.26, 0.13),
		Vector3(hfp_x, hfp_h * 0.86, kf_z - hfc_d * 0.30), body)
	_cyl(p, 0.028, 0.028, 0.04,
		Vector3(hfp_x - 0.09, hfp_h * 0.94, kf_z - hfc_d * 0.30), teal, "x")   # green running lamp
	_cyl(p, 0.030, 0.030, 0.05,
		Vector3(hfp_x - 0.09, hfp_h * 0.80, kf_z - hfc_d * 0.30), red, "x")    # E-stop

	# ═══ SECTION 5b: VACUUM DEGAS DOMES on the BARREL itself ═══════════════════
	# Two upward-facing vacuum chambers tap the barrel on top — that's where
	# real screw extruders pull volatiles off the melt. Each is a low dome with
	# a riser pipe to a vacuum line + a sight glass. Positioned DOWNSTREAM of the
	# laser-filter disc and UPSTREAM of the kopfilter — schematic callout 4
	# (degas) sits between the filter (callout 3) and the screen-changer (5):
	# #223 docs->code TRAIN-extruderen-p3__108_CeDo24.md / OTHER-training-extruderen-4__105_CeDo25.md.
	# Kept a clearly-different colour from the head filter so they stay distinguishable.
	var vac_mat := _mat(Color(0.45, 0.48, 0.52), ghost, 0.55, 0.4)
	for vz in [size.z * 0.06, size.z * 0.13]:
		var vac_y : float = hood_top + size.x * 0.04
		# Dome (hemisphere) sitting on the hood — flattened cyl reads as a dome.
		_cyl(p, size.x * 0.10, size.x * 0.06, size.x * 0.10,
			Vector3(0.0, vac_y, vz), vac_mat)
		# Riser pipe up to the vacuum line above.
		_cyl(p, 0.04, 0.04, size.x * 0.30,
			Vector3(0.0, vac_y + size.x * 0.20, vz), dark)
		# Small sight glass on the +X side.
		_cyl(p, 0.025, 0.025, 0.05,
			Vector3(size.x * 0.10, vac_y + size.x * 0.02, vz), glass, "x")

	# ═══ SECTION 6: MELTPUMP (gear-pump block) on the barrel front ═══
	# Lines 3C AND 6 have the smeltpomp (gear pump) fitted; lines 1 / 3A / 3B feed
	# the die head directly. Gated on the per-line tag so the doubled/incorrect
	# pump no longer renders everywhere.
	# (PHOTO-erema-bluport-lijn3C-smeltpomp1-productie__295_CeDo62_3.md is a 3C shot.)
	# CORRECTION 2026-08-31 (operator ruling): the earlier "#225.3 spec: ONLY line
	# 3C" reading excluded line 6. The operator ruled that 3C AND 6 both carry a
	# melt pump and only 1 / 3A / 3B go without — matching the variant map at
	# docs/plant/misc_sources.md:112-114 (V3_BRITAS_PUMP -> line 6 "+ melt pump").
	# See docs/plant/operator_rulings_2026-08-31.md §1.
	if line_tag in ["3C", "6"]:
		var mp_z : float = size.z * 0.30
		_box(p, Vector3(size.x * 0.30, barrel_cy * 0.55, size.z * 0.05), Vector3(0.0, hood_cy, mp_z), body)         # pump block
		for sx4 in [-0.10, 0.10]:
			_cyl(p, size.x * 0.06, size.x * 0.06, size.z * 0.06, Vector3(sx4 * size.x, hood_cy + size.x * 0.18, mp_z), steel, "z")  # gear shafts
		_cyl(p, size.x * 0.08, size.x * 0.08, size.z * 0.06, Vector3(0.0, hood_cy, mp_z + size.z * 0.05), steel, "z")  # melt out to die
		# #223 docs->code: meltpump drive motor on TOP of the gear-pump block
		# (PHOTO-erema-bluport-lijn3C-smeltpomp1-productie__295_CeDo62_3.md: drive motor on top).
		_motor_unit(p, size.x * 0.09, size.x * 0.16, Vector3(0.0, hood_cy + barrel_cy * 0.30, mp_z), "y", ghost)

	# ═══ SECTION 7: WAVE-CUT PELLETIZER CABINET (front, +Z) ═══
	var pz : float = size.z * 0.42
	var cab_w : float = size.x * 0.88
	var cab_base : float = size.y * 0.04
	var cab_h : float = size.y * 0.56
	var cab_cy : float = cab_base + cab_h * 0.5
	var cab_len : float = size.z * 0.16
	var pf_z : float = pz + cab_len * 0.5
	for sx5 in [-1.0, 1.0]:
		var ft := _box(p, Vector3(0.16, cab_base, 0.16), Vector3(sx5 * cab_w * 0.42, cab_base * 0.5, pz + cab_len * 0.3), dark)
		ft.add_to_group("machine_leg")
		ft.set_meta("leg_h", cab_base)
	_box(p, Vector3(cab_w, cab_h * 0.42, cab_len), Vector3(0.0, cab_base + cab_h * 0.21, pz), navy)             # navy lower
	_box(p, Vector3(cab_w, cab_h * 0.58, cab_len), Vector3(0.0, cab_base + cab_h * 0.71, pz), steel)            # stainless upper
	for sx6 in [-0.25, 0.25]:
		_box(p, Vector3(0.02, cab_h * 0.85, 0.02), Vector3(sx6 * cab_w, cab_cy, pf_z + 0.01), dark)             # door seam
	var logo_y : float = cab_base + cab_h * 0.86
	_cyl(p, size.x * 0.11, size.x * 0.11, 0.02, Vector3(-cab_w * 0.30, logo_y, pf_z + 0.01), gold, "z")         # Wave-Cut roundel
	_cyl(p, size.x * 0.06, size.x * 0.06, 0.03, Vector3(-cab_w * 0.30, logo_y, pf_z + 0.02), teal, "z")         # wave inner accent
	_box(p, Vector3(size.x * 0.30, size.x * 0.05, 0.01), Vector3(cab_w * 0.10, logo_y, pf_z + 0.01), gold)      # wordmark bar (clear of roundel)
	for sx7 in [-0.20, 0.20]:
		_box(p, Vector3(size.x * 0.12, cab_h * 0.46, 0.02), Vector3(sx7 * size.x, cab_cy, pf_z + 0.01), blackm) # louvered window
		for k in 6:
			_box(p, Vector3(size.x * 0.12, 0.012, 0.03), Vector3(sx7 * size.x, cab_cy - cab_h * 0.20 + float(k) * cab_h * 0.08, pf_z + 0.02), dark)
	var ph_x : float = -cab_w * 0.5 - 0.12
	var ph_y : float = barrel_cy * 1.2
	_box(p, Vector3(0.08, ph_y, 0.08), Vector3(ph_x, ph_y * 0.5, pf_z - 0.10), dark)                            # pedestal post
	_box(p, Vector3(0.30, 0.06, 0.06), Vector3(ph_x + 0.12, ph_y, pf_z - 0.10), dark)                           # bent arm
	_box(p, Vector3(0.08, 0.26, 0.22), Vector3(ph_x + 0.26, ph_y, pf_z - 0.10), dark)                           # screen box
	_box(p, Vector3(0.03, 0.20, 0.16), Vector3(ph_x + 0.31, ph_y, pf_z - 0.10), glass)                          # touchscreen -X
	_cyl(p, 0.03, 0.03, 0.05, Vector3(ph_x + 0.30, ph_y - 0.18, pf_z - 0.10), red, "x")                         # E-stop
	_cyl(p, 0.02, 0.02, 0.04, Vector3(ph_x + 0.30, ph_y - 0.24, pf_z - 0.16), teal, "x")                        # green button
	_cyl(p, 0.02, 0.02, 0.04, Vector3(ph_x + 0.30, ph_y - 0.24, pf_z - 0.04), red, "x")                         # red button
	# #106 — VISIBLE PELLETIZER HEAD. The cutter used to live HIDDEN inside the
	# cabinet; the operator can't see the spinning blade or the die-face holes
	# from outside, so it read as missing. New layout puts the die head plate
	# proud of the cabinet front and the rotating cutter disc with visible
	# blades right against it, exactly like a real hot-face pelletizer.
	# Die-face plate (steel disc with 8 visible orifice holes).
	var die_z : float = pf_z + 0.04
	var die_r : float = size.x * 0.18
	_cyl(p, die_r, die_r, 0.06, Vector3(0.0, barrel_cy, die_z), steel, "z")
	# 8 visible orifice holes drilled into the die face — black recessed dots.
	for di in 8:
		var ang : float = TAU * float(di) / 8.0
		_cyl(p, 0.025, 0.025, 0.04,
			Vector3(cos(ang) * die_r * 0.65, barrel_cy + sin(ang) * die_r * 0.65, die_z + 0.02),
			blackm, "z")
	# A central pilot hole (where the melt's reference flow exits).
	_cyl(p, 0.04, 0.04, 0.04, Vector3(0.0, barrel_cy, die_z + 0.02), blackm, "z")
	# Hot-face cutter — a thin disc with radial knife blades. Sits 1 cm proud of
	# the die face so the blades sweep across the orifice exits. Rotation at
	# 600 RPM keyed to comp "pelletizer_cutter" so the live RPM system can drive
	# it from HMI. Axis along Z (the melt flow direction).
	var cut_rm := _spinning_cyl(p, die_r * 0.95, die_r * 0.95, 0.025,
		Vector3(0.0, barrel_cy, die_z + 0.06), dark, "z", Vector3.BACK, ghost, 600.0)
	if not ghost:
		cut_rm.set_meta("comp", "pelletizer_cutter")
	# Four radial knife blades sticking off the cutter disc (visible while
	# spinning + when stopped). Built as children of cut_rm so they spin with it.
	# #210c — each blade is wrapped in a StaticBody3D so the operator can E-target
	# it (knife_<i>) and the maintenance interaction can swap the surface override
	# material between new / foutief / beschadigd states. Materials are stashed
	# as meta so a downstream controller (or PlaceableCatalog.set_knife_state)
	# can recolour them without rebuilding the mesh.
	var cy_local : float = 0.0 if not ghost else barrel_cy
	var cz_local : float = 0.0 if not ghost else die_z + 0.06
	var blade_size : Vector3 = Vector3(die_r * 0.20, 0.02, 0.04)
	for kb in 4:
		var kang : float = TAU * float(kb) / 4.0
		var kx : float = cos(kang) * die_r * 0.55
		var ky : float = cy_local + sin(kang) * die_r * 0.55
		# Per-knife StaticBody3D — child of cut_rm so it spins with the disc;
		# the rotation matches the original blade orientation.
		var knife_body := StaticBody3D.new()
		knife_body.name = "knife_%d" % kb
		knife_body.position = Vector3(kx, ky, cz_local)
		knife_body.rotation = Vector3(0.0, 0.0, kang)
		cut_rm.add_child(knife_body)
		# Mesh — same proportions as the legacy _box visual, parented to the
		# knife body so it inherits position+rotation.
		var blade_mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = blade_size
		blade_mi.mesh = bm
		blade_mi.material_override = steel
		knife_body.add_child(blade_mi)
		# Three surface-override materials representing the lifecycle of a knife:
		# new (clean steel), foutief (factory-defective dull grey-brown), and
		# beschadigd (chipped + rust-tinted). All three are cached as meta on
		# the knife_body so set_knife_state() can swap them without re-querying
		# the catalog. NB: only the body carries the meta — keeps the contract
		# tight (one node per knife is the canonical entity).
		# #212.17 — wear materials reworked so the three knife lifecycle states
		# read clearly even at glance:
		#   new       — bright polished steel, low rough, high metallic
		#   foutief   — slightly duller cast-grey with reduced metallic so it
		#               doesn't catch the work-lights as crisply (factory dull)
		#   beschadigd — rust + char tinted, surface roughness LOWERED with a
		#               slight darker shift (chipped/scarred face catches more
		#               speculars on the scratches) + faint emissive so damage
		#               is unmistakable against the new + foutief peers.
		var mat_new        : StandardMaterial3D = _mat(Color(0.78, 0.80, 0.84), ghost, 0.85, 0.20)
		var mat_foutief    : StandardMaterial3D = _mat(Color(0.50, 0.48, 0.44), ghost, 0.15, 0.70)
		var mat_beschadigd : StandardMaterial3D = _mat(Color(0.38, 0.18, 0.12), ghost, 0.45, 0.55)
		if not ghost:
			mat_beschadigd.emission_enabled = true
			mat_beschadigd.emission = Color(0.42, 0.18, 0.10)
			mat_beschadigd.emission_energy_multiplier = 0.05
		knife_body.set_meta("knife_index", kb)
		knife_body.set_meta("placeable_id", "pelletizer_knife")
		knife_body.set_meta("knife_mat_new", mat_new)
		knife_body.set_meta("knife_mat_foutief", mat_foutief)
		knife_body.set_meta("knife_mat_beschadigd", mat_beschadigd)
		knife_body.set_meta("knife_mesh", blade_mi)
		# Collision — small box matching the visible blade. Skipped on ghost
		# placement so the build preview doesn't trip the player's raycast.
		if not ghost:
			var col := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = blade_size
			col.shape = sh
			knife_body.add_child(col)
	# Cutter spindle/coupling behind the disc (back toward the cabinet).
	_cyl(p, size.x * 0.04, size.x * 0.04, 0.20, Vector3(0.0, barrel_cy, die_z + 0.18), steel, "z")
	# ═══ #209b — Die-face strand viz (StrandSwitcher) ═══════════════════════
	# Three groups of 20 strand cylinders in a horizontal row just in front of
	# the die plate. Only ONE group is visible at a time; the active group is
	# chosen by a downstream ExtruderMachine controller via the meta tag
	# "die_face_switcher". Default is GOED GEHARD (lavender, clean) — the
	# state the operator wants to see. The te_heet group also spawns small
	# semi-transparent smoke wisps to read as charred polymer.
	_build_heetafslag_strand_switcher(p, die_r, barrel_cy, die_z, ghost)
	# Pellet collection chute below the die head — angled downward into a
	# catch tray, so the cut pellets visibly fall AWAY from the cutter zone.
	var chute := _box(p, Vector3(die_r * 1.6, 0.04, 0.40),
		Vector3(0.0, barrel_cy - die_r * 0.45, die_z + 0.18), dark)
	chute.rotation = Vector3(deg_to_rad(-25.0), 0.0, 0.0)
	# Granulate-out spout at the BOTTOM (front of pelletizer cabinet, low Y).
	_cyl(p, size.x * 0.10, size.x * 0.10, size.z * 0.08, Vector3(0.0, barrel_cy * 0.5, pf_z + size.z * 0.02), dark, "z")  # granulate out the front

	# ═══ GLOBAL: black overhead extraction hoods ═══
	_box(p, Vector3(cab_w * 1.1, size.y * 0.12, cab_len * 1.2), Vector3(0.0, size.y * 0.92, pz), blackm)        # pelletizer hood
	_cyl(p, size.x * 0.10, size.x * 0.10, size.y * 0.16, Vector3(0.0, size.y * 1.02, pz), blackm)               # hood duct
	_box(p, Vector3(size.x * 0.5, size.y * 0.09, size.z * 0.40), Vector3(0.0, size.y * 0.90, size.z * 0.10), blackm)  # barrel-mid hood

## #209b — Build a "StrandSwitcher" container with three groups of 20 strand
## cylinders each. Only one group is visible at a time; the active one is set
## via show_state(int) (or directly by toggling .visible on the children).
## Layout: strands hang straight DOWN from the die-face plate (the real wave-
## cut die holds the strands in the pinch between die face and cutter rotor
## until the blades sweep). We arrange the 20 strands in a horizontal row
## centred under the die orifice ring so the operator sees the active state
## from outside the cabinet.
static func _build_heetafslag_strand_switcher(p: Node3D, die_r: float,
		barrel_cy: float, die_z: float, ghost: bool) -> void:
	var switcher := Node3D.new()
	switcher.name = "StrandSwitcher"
	# Hang the row right at the die face level, drooping just below the cutter
	# rotor (die_z is the die plate Z; the rotor sits at die_z+0.06).
	switcher.position = Vector3(0.0, barrel_cy - die_r * 0.10, die_z + 0.04)
	p.add_child(switcher)
	switcher.set_meta("die_face_switcher", true)
	# Keep the strand groups OUT of the static-merge bake — otherwise StaticMerge
	# re-shows the group-hidden strands as one baked mesh and the idle die drips
	# melt again despite the LineFlow gate (bughunt 2026-07-17: my earlier
	# "hide grp_good" fix was silently undone by the baker).
	switcher.set_meta("no_merge", true)
	# Strand dimensions per spec — 0.003 m radius (3 mm) × 0.4 m height.
	var strand_r : float = 0.003
	var strand_h : float = 0.40
	var strand_count : int = 20
	# Spread the row across roughly the orifice ring's diameter so each strand
	# reads as "one orifice's flow" even though we draw 20 not 8 (cosmetic).
	var row_w : float = die_r * 1.6
	var dx : float = row_w / float(maxi(strand_count - 1, 1))
	var x0 : float = -row_w * 0.5
	# Per-group materials — duck-typed via _mat so the ghost flag is honoured.
	# Tints match the spec exactly so the in-game read of cold/good/hot is
	# unmistakable from across the floor.
	var mat_cold := _mat(Color(0.50, 0.45, 0.40), ghost, 0.10, 0.85)   # dull grey-brown, lifeless
	var mat_good := _mat(Color(0.55, 0.45, 0.85), ghost, 0.20, 0.50)   # lavender (matches pelletizer.png)
	var mat_hot  := _mat(Color(0.25, 0.10, 0.05), ghost, 0.10, 0.90)   # dark brown / charred
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.albedo_color = Color(0.55, 0.50, 0.48, 0.18)
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED

	var cm := CylinderMesh.new()
	cm.top_radius = strand_r
	cm.bottom_radius = strand_r
	cm.height = strand_h
	cm.radial_segments = 8

	var cm_hot := CylinderMesh.new()
	cm_hot.top_radius = strand_r * 0.85
	cm_hot.bottom_radius = strand_r * 0.85
	cm_hot.height = strand_h
	cm_hot.radial_segments = 8

	var qm := QuadMesh.new()
	qm.size = Vector2(0.04, 0.06)

	var mm_cold := MultiMesh.new()
	mm_cold.transform_format = MultiMesh.TRANSFORM_3D
	mm_cold.instance_count = strand_count
	mm_cold.mesh = cm
	var mmi_cold := MultiMeshInstance3D.new()
	mmi_cold.name = "te_koud_strands"
	mmi_cold.multimesh = mm_cold
	mmi_cold.material_override = mat_cold
	switcher.add_child(mmi_cold)

	var mm_good := MultiMesh.new()
	mm_good.transform_format = MultiMesh.TRANSFORM_3D
	mm_good.instance_count = strand_count
	mm_good.mesh = cm
	var mmi_good := MultiMeshInstance3D.new()
	mmi_good.name = "goed_gehard_strands"
	mmi_good.multimesh = mm_good
	mmi_good.material_override = mat_good
	switcher.add_child(mmi_good)

	var mm_hot := MultiMesh.new()
	mm_hot.transform_format = MultiMesh.TRANSFORM_3D
	mm_hot.instance_count = strand_count
	mm_hot.mesh = cm_hot
	var mmi_hot := MultiMeshInstance3D.new()
	mmi_hot.name = "te_heet_strands"
	mmi_hot.multimesh = mm_hot
	mmi_hot.material_override = mat_hot
	switcher.add_child(mmi_hot)

	var smoke_mm := MultiMesh.new()
	smoke_mm.transform_format = MultiMesh.TRANSFORM_3D
	smoke_mm.instance_count = strand_count
	smoke_mm.mesh = qm
	var mmi_smoke := MultiMeshInstance3D.new()
	mmi_smoke.multimesh = smoke_mm
	mmi_smoke.material_override = smoke_mat
	mmi_hot.add_child(mmi_smoke)

	for i in strand_count:
		var sx : float = x0 + float(i) * dx
		var y_jitter : float = sin(float(i) * 1.31) * 0.005
		var pos := Vector3(sx, -strand_h * 0.5 + y_jitter, 0.0)

		# Slight twist on the cold strands (deformed / not yet hardened).
		var rot_cold := Vector3(deg_to_rad(sin(float(i)) * 6.0), 0.0, deg_to_rad(cos(float(i)) * 6.0))
		mm_cold.set_instance_transform(i, Transform3D(Basis.from_euler(rot_cold), pos))

		# GOED — clean vertical strand (the operator's target state).
		mm_good.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.002, 0.0)))

		# TE HEET — charred, slightly thinner, with a small smoke wisp above.
		var rot_hot := Vector3(deg_to_rad(sin(float(i) * 2.0) * 4.0), 0.0, 0.0)
		mm_hot.set_instance_transform(i, Transform3D(Basis.from_euler(rot_hot), pos))

		# Smoke wisp above the top of the strand. It goes into `smoke_mm`, the
		# MultiMesh built for exactly this a few lines up (instance_count ==
		# strand_count, mesh == qm) — NOT into a per-strand MeshInstance3D.
		#
		# Two reasons this is the only correct form, both learned the hard way:
		#   * the per-strand version referenced `grp_hot`, which is a local of
		#     show_die_face_state() further down the file, so the whole file
		#     failed to parse. PlaceableCatalog is preloaded by BuildMode,
		#     MainWorld and 27 of the test scripts, so ONE undeclared name here
		#     takes the entire project down. Restored from ed9198b after the
		#     7b72ecf merge reverted it; see docs/AUDIT_project_sweep_2026-08-23.md.
		#   * leaving smoke_mm's transforms unset does not merely waste the
		#     MultiMesh — every one of its strand_count instances defaults to
		#     IDENTITY, so all the smoke quads pile up at the switcher origin.
		smoke_mm.set_instance_transform(i, Transform3D(Basis(), pos + Vector3(0.0, strand_h * 0.55, 0.0)))
	# Default visibility — ALL OFF (operator 2026-07-16: no orange melt strands
	# dripping from an idle/unfed extruder = "inventing material from nothing").
	# LineFlow drives show_die_face_state() from live throughput so strands only
	# appear while the extruder is actually pushing melt.
	mmi_cold.visible = false
	mmi_good.visible = false
	mmi_hot.visible = false

## #209b — Flip the StrandSwitcher to a given state. The controller calls this
## with state ∈ {0 = TE KOUD, 1 = GOED GEHARD, 2 = TE HEET}. The lookup is by
## child name so the switcher node can be discovered via the
## "die_face_switcher" meta tag and then handed to this function unchanged.
static func show_die_face_state(switcher: Node3D, state: int) -> void:
	if switcher == null or not is_instance_valid(switcher):
		return
	var grp_cold : MultiMeshInstance3D = switcher.get_node_or_null("te_koud_strands") as MultiMeshInstance3D
	var grp_good : MultiMeshInstance3D = switcher.get_node_or_null("goed_gehard_strands") as MultiMeshInstance3D
	var grp_hot  : MultiMeshInstance3D = switcher.get_node_or_null("te_heet_strands") as MultiMeshInstance3D
	if grp_cold != null:
		grp_cold.visible = (state == 0)
	if grp_good != null:
		grp_good.visible = (state == 1)
	if grp_hot != null:
		grp_hot.visible = (state == 2)

## #210c — Swap a knife's surface override based on its lifecycle state. The
## three materials are stashed as meta on the knife StaticBody3D at build
## time; this method just looks them up and assigns the right one to the
## blade's MeshInstance3D. Callers can pass state ∈ {0 = new, 1 = foutief,
## 2 = beschadigd}. Returns true on success, false if the node isn't a
## valid knife.
## TITECH/TOMRA shaft-wrap visual driver. `wrap_g_normalized` is wrap_g /
## FULL_WRAP_G, clamped 0..1. At 0.0 the cylinder is hidden; at 1.0 it sits at
## the full radius (0.10). Cheap — one CylinderMesh radius write per tick, no
## scene-tree descent (we cached the mesh ref on the placement root in
## _m_nir_sorter via the "shaft_wrap_mesh" meta). Returns true if a placeable
## was actually updated; false (silent) if the node isn't a NIR sorter or the
## meta lookup failed (e.g. mesh was freed mid-tick).
static func set_shaft_wrap_visual(nir_node: Node, wrap_g_normalized: float) -> bool:
	if nir_node == null or not is_instance_valid(nir_node):
		return false
	if not nir_node.has_meta("shaft_wrap_mesh"):
		return false
	var mi := nir_node.get_meta("shaft_wrap_mesh") as MeshInstance3D
	if mi == null or not is_instance_valid(mi):
		return false
	var t : float = clampf(wrap_g_normalized, 0.0, 1.0)
	# Hide entirely when there's no wrap so a clean sorter shows nothing.
	mi.visible = t > 0.001
	if not mi.visible:
		return true
	var cm := mi.mesh as CylinderMesh
	if cm == null:
		return true
	# Grow from 0.04 (a sliver visible just over the drum) to 0.10 at full wrap.
	var r : float = lerpf(0.04, 0.10, t)
	cm.top_radius = r
	cm.bottom_radius = r
	return true

static func set_knife_state(knife_node: Node, state: int) -> bool:
	if knife_node == null or not is_instance_valid(knife_node):
		return false
	if not knife_node.has_meta("knife_mesh"):
		return false
	var mi := knife_node.get_meta("knife_mesh") as MeshInstance3D
	if mi == null or not is_instance_valid(mi):
		return false
	var key : String = "knife_mat_new"
	match state:
		0: key = "knife_mat_new"
		1: key = "knife_mat_foutief"
		2: key = "knife_mat_beschadigd"
		_: return false
	if not knife_node.has_meta(key):
		return false
	var mat := knife_node.get_meta(key) as StandardMaterial3D
	if mat == null:
		return false
	mi.material_override = mat
	knife_node.set_meta("knife_state", state)
	return true

# =============================================================================
# #212 PHASE 3 POLISH — hazard decals + environment placeables
# =============================================================================

# Hazard placard text per id. Keep terse — the Label3D font_size is fixed and
# longer strings would overflow the 0.4 × 0.4 panel.
const HAZARD_LABELS : Dictionary = {
	"hazard_moving":          "DANGER\nMOVING\nMACHINERY",
	"hazard_overhead":        "CAUTION\nOVERHEAD\nLOAD",
	"hazard_hightemp":        "DANGER\nHIGH\nTEMPERATURE",
	"hazard_hardhat":         "HARD HAT\nREQUIRED",
	"hazard_piralchute":      "DANGER\nPIRAL\nCHUTE",
	"hazard_platformmaxload": "PLATFORM\nMAX LOAD",
}

# ── #212.2 hazard decal: yellow panel + black border + Label3D text ──────────
static func _m_hazard_decal(p: Node3D, id: String, size: Vector3,
		color: Color, ghost: bool) -> void:
	var yellow := _mat(color, ghost, 0.0, 0.7)
	var black := _mat(Color(0.04, 0.04, 0.05), ghost, 0.0, 0.8)
	# Backing panel (full size, faces +Z).
	_box(p, Vector3(size.x, size.y, size.z), Vector3(0.0, size.y * 0.5, 0.0), yellow)
	# Black border — 4 thin strips on the front face just proud of the panel.
	var brd : float = 0.022
	var fz : float = size.z * 0.5 + 0.002
	_box(p, Vector3(size.x, brd, 0.002), Vector3(0.0, size.y - brd * 0.5, fz), black)  # top
	_box(p, Vector3(size.x, brd, 0.002), Vector3(0.0, brd * 0.5, fz), black)            # bottom
	_box(p, Vector3(brd, size.y, 0.002), Vector3(-size.x * 0.5 + brd * 0.5, size.y * 0.5, fz), black)
	_box(p, Vector3(brd, size.y, 0.002), Vector3( size.x * 0.5 - brd * 0.5, size.y * 0.5, fz), black)
	# Stencil text — face +Z, centred. Use the file-top helper.
	var text : String = String(HAZARD_LABELS.get(id, "HAZARD"))
	var lbl := _stencil_label(p, text,
		Vector3(size.x - brd * 2.4, size.y - brd * 2.4, 0.01), "+Z")
	lbl.position = Vector3(0.0, size.y * 0.5, fz + 0.003)
	if not ghost:
		_finalize_placeable(p, id)

# ── #212.11 overhead crane: yellow PPE gantry crane (legs + beam + trolley) ──
# ── #212.11 overhead crane: yellow PPE gantry crane with hoist & pendant ──
static func _m_overhead_crane(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var yel := _mat(color, ghost, 0.2, 0.6)
	var beam_steel := _mat(_DARK, ghost, 0.5, 0.5)
	var steel := _mat(_STEEL, ghost, 0.6, 0.35)
	var leg_w : float = 0.30
	var leg_h : float = size.y * 0.94

	for sx in [-1.0, 1.0]:
		var lg := _box(p, Vector3(leg_w, leg_h, leg_w),
			Vector3(float(sx) * (size.x * 0.5 - leg_w * 0.5), leg_h * 0.5, 0.0), yel)
		lg.add_to_group("machine_leg")
		lg.set_meta("leg_h", leg_h)

	# Horizontal gantry beam
	_box(p, Vector3(size.x, size.y * 0.10, leg_w * 0.95),
		Vector3(0.0, leg_h + size.y * 0.05, 0.0), beam_steel)

	# Trolley & motorized cable hoist drum (spinning)
	var trolley_y : float = leg_h - size.y * 0.04
	_box(p, Vector3(size.x * 0.10, size.y * 0.12, size.z * 0.9),
		Vector3(size.x * 0.18, trolley_y, 0.0), yel)
	var _hoist_drum := _spinning_cyl(p, 0.12, 0.12, size.x * 0.08,
		Vector3(size.x * 0.18, trolley_y, 0.0), steel, "z", Vector3.FORWARD, ghost, 60.0)

	# Steel cable & hook
	_cyl(p, 0.015, 0.015, size.y * 0.45,
		Vector3(size.x * 0.18, trolley_y - size.y * 0.30, 0.0), steel)
	_box(p, Vector3(0.14, 0.10, 0.10),
		Vector3(size.x * 0.18, trolley_y - size.y * 0.55, 0.0), beam_steel)

	# Hanging operator push-button pendant control (interactive)
	var _crane_pendant := _interactive_hatch(p, Vector3(0.08, 0.22, 0.06),
		Vector3(size.x * 0.18 + 0.35, trolley_y - size.y * 0.45, 0.0), "Crane Operator Pendant", 45.0, 1.0, yel, ghost)

	if not ghost:
		_finalize_placeable(p, "overhead_crane")

# ── #212.12 fire_riser: tall red pipe with interactive inspector test valve ─────
static func _m_fire_riser(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var red := _mat(color, ghost, 0.3, 0.5)
	var brass := _mat(Color(0.78, 0.62, 0.22), ghost, 0.7, 0.3)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)

	# Main vertical riser pipe
	_cyl(p, size.x * 0.5, size.x * 0.5, size.y,
		Vector3(0.0, size.y * 0.5, 0.0), red, "y")

	# Sprinkler head at top
	_cyl(p, size.x * 0.4, size.x * 0.4, 0.05,
		Vector3(0.0, size.y + 0.02, 0.0), brass, "y")
	_box(p, Vector3(0.10, 0.04, 0.10), Vector3(0.0, size.y + 0.06, 0.0), brass)

	# Horizontal branch pipes
	for sx in [-1.0, 1.0]:
		_cyl(p, size.x * 0.30, size.x * 0.30, 0.8,
			Vector3(float(sx) * 0.4, size.y * 0.7, 0.0), red, "x")

	# Interactive ball valve test lever
	var _test_valve := _interactive_hatch(p, Vector3(0.15, 0.03, 0.04),
		Vector3(size.x * 0.45, size.y * 0.55, 0.0), "Fire Riser Test Valve", 90.0, 1.0, brass, ghost)

	# Water pressure gauge
	_cyl(p, 0.06, 0.06, 0.02, Vector3(0.0, size.y * 0.65, size.x * 0.52), dark, "z")
	_cyl(p, 0.05, 0.05, 0.01, Vector3(0.0, size.y * 0.65, size.x * 0.53), brass, "z")

	if not ghost:
		_finalize_placeable(p, "fire_riser")

# ── #212.12 fire extinguisher with interactive discharge squeeze lever ─────
static func _m_fire_extinguisher(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var red := _mat(color, ghost, 0.3, 0.5)
	var yel := _mat(Color(0.95, 0.85, 0.10), ghost, 0.0, 0.8)
	var dark := _mat(_DARK, ghost, 0.4, 0.6)

	# Cylinder body
	_cyl(p, size.x * 0.45, size.x * 0.45, size.y * 0.8,
		Vector3(0.0, size.y * 0.42, 0.0), red, "y")

	# Top neck
	_cyl(p, size.x * 0.20, size.x * 0.20, size.y * 0.12,
		Vector3(0.0, size.y * 0.88, 0.0), dark, "y")

	# Interactive squeeze handle lever
	var _ext_lever := _interactive_hatch(p, Vector3(size.x * 0.6, size.y * 0.05, size.x * 0.15),
		Vector3(0.0, size.y * 0.96, 0.0), "Extinguisher Squeeze Lever", 30.0, 1.0, dark, ghost)

	# Yellow instructions decal
	var lbl := _stencil_label(p, "INSTRUCTIONS",
		Vector3(size.x * 0.7, size.y * 0.2, 0.01), "+Z")
	lbl.position = Vector3(0.0, size.y * 0.45, size.x * 0.46)
	_box(p, Vector3(size.x * 0.7, size.y * 0.2, 0.002),
		Vector3(0.0, size.y * 0.45, size.x * 0.46 - 0.002), yel)

	if not ghost:
		_finalize_placeable(p, "fire_extinguisher")

# ── #212.13 drainage grating: dark grey with diagonal slots + puddle decal ──
static func _m_drainage_grating(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var dark := _mat(color, ghost, 0.45, 0.7)
	var darker := _mat(Color(0.12, 0.13, 0.15), ghost, 0.4, 0.8)
	var puddle := _mat(Color(0.3, 0.5, 0.8, 0.4), ghost, 0.0, 0.2)

	_box(p, Vector3(size.x, size.y, size.z),
		Vector3(0.0, size.y * 0.5, 0.0), dark)

	for i in 8:
		var t : float = float(i) / 7.0
		var x : float = lerp(-size.x * 0.4, size.x * 0.4, t)
		var slot := _box(p, Vector3(size.x * 0.06, 0.005, size.z * 1.1),
			Vector3(x, size.y + 0.003, 0.0), darker)
		slot.rotation = Vector3(0.0, PI * 0.25, 0.0)

	var pmi := MeshInstance3D.new()
	var pqm := QuadMesh.new()
	pqm.size = Vector2(size.x * 0.5, size.z * 0.5)
	pmi.mesh = pqm
	pmi.material_override = puddle
	pmi.position = Vector3(0.0, size.y + 0.006, 0.0)
	pmi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	p.add_child(pmi)
	if not ghost:
		_finalize_placeable(p, "drainage_grating")

# ── #212.14 scissor lift: yellow base + 4 X-arms + interactive top platform control ──
static func _m_scissor_lift(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var yel := _mat(color, ghost, 0.2, 0.6)
	var dark := _mat(_DARK, ghost, 0.5, 0.5)
	var red := _mat(Color(0.85, 0.15, 0.12), ghost, 0.2, 0.5)

	_box(p, Vector3(size.x, size.y * 0.12, size.z),
		Vector3(0.0, size.y * 0.06, 0.0), yel)

	var arm_w : float = 0.06
	var arm_h : float = size.y * 0.65
	for sx in [-1.0, 1.0]:
		var xside : float = float(sx) * (size.x * 0.5 - 0.05)
		for k in 4:
			var cy : float = size.y * 0.12 + arm_h * 0.5 + float(k) * arm_h * 0.05
			var a1 := _box(p, Vector3(arm_w, arm_h, arm_w),
				Vector3(xside, cy, 0.0), dark)
			a1.rotation = Vector3(0.0, 0.0, PI * 0.25)
			var a2 := _box(p, Vector3(arm_w, arm_h, arm_w),
				Vector3(xside, cy, 0.0), dark)
			a2.rotation = Vector3(0.0, 0.0, -PI * 0.25)

	var top_y : float = size.y * 0.85
	_box(p, Vector3(size.x, size.y * 0.06, size.z),
		Vector3(0.0, top_y, 0.0), yel)

	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			_box(p, Vector3(0.05, size.y * 0.12, 0.05),
				Vector3(float(sx2) * size.x * 0.45,
					top_y + size.y * 0.09,
					float(sz2) * size.z * 0.45), yel)
	_box(p, Vector3(size.x * 0.95, 0.04, 0.04),
		Vector3(0.0, top_y + size.y * 0.14, size.z * 0.45), yel)
	_box(p, Vector3(size.x * 0.95, 0.04, 0.04),
		Vector3(0.0, top_y + size.y * 0.14, -size.z * 0.45), yel)

	# Interactive platform lift controls & E-stop
	var _lift_ctrl := _interactive_hatch(p, Vector3(0.12, 0.18, 0.08),
		Vector3(size.x * 0.40, top_y + size.y * 0.16, size.z * 0.42), "Scissor Lift Controls", 75.0, 1.0, dark, ghost)
	if not ghost:
		_cyl(_lift_ctrl, 0.02, 0.02, 0.02, Vector3(0.0, 0.05, 0.05), red, "z")

	if not ghost:
		_finalize_placeable(p, "scissor_lift")

# ── #212.15 riveted steel arch column: box + rivet bumps in grid ────────────
static func _m_riveted_steel_column(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var steel := _mat(color, ghost, 0.6, 0.4)
	var rivet := _mat(Color(0.45, 0.47, 0.50), ghost, 0.7, 0.3)
	# Main box column.
	_box(p, Vector3(size.x, size.y, size.z),
		Vector3(0.0, size.y * 0.5, 0.0), steel)
	# Rivet bumps in a grid on each of the 4 vertical faces. Plain if-blocks
	# instead of ternary chains so the parser doesn't have to track multi-line
	# operator precedence under -warnings-as-errors.
	var rows : int = 8
	var cols : int = 3
	for face in 4:
		var face_z : float = 0.0
		var face_x : float = 0.0
		if face == 0:
			face_z = size.z * 0.5 + 0.003
		elif face == 1:
			face_z = -size.z * 0.5 - 0.003
		elif face == 2:
			face_x = size.x * 0.5 + 0.003
		else:
			face_x = -size.x * 0.5 - 0.003
		for r in rows:
			for c in cols:
				var y : float = size.y * (0.05 + float(r) / float(rows - 1) * 0.9)
				if face < 2:
					var lx : float = size.x * (-0.4 + float(c) / float(cols - 1) * 0.8)
					_cyl(p, 0.025, 0.025, 0.012,
						Vector3(lx, y, face_z), rivet, "z")
				else:
					var lz : float = size.z * (-0.4 + float(c) / float(cols - 1) * 0.8)
					_cyl(p, 0.025, 0.025, 0.012,
						Vector3(face_x, y, lz), rivet, "x")
	if not ghost:
		_finalize_placeable(p, "riveted_steel_column")

# ── #212.15 concrete V-beam: 2 angled boxes + yellow caution decal at base ──
static func _m_concrete_v_beam(p: Node3D, size: Vector3, color: Color, ghost: bool) -> void:
	var concrete := _mat(color, ghost, 0.1, 0.85)
	var yel := _mat(Color(0.95, 0.75, 0.10), ghost, 0.0, 0.7)
	# Two angled boxes forming an inverted V.
	var leg_len : float = size.y * 1.05
	for sx in [-1.0, 1.0]:
		var beam := _box(p, Vector3(size.x * 0.30, leg_len, size.z),
			Vector3(float(sx) * size.x * 0.18, size.y * 0.5, 0.0), concrete)
		beam.rotation = Vector3(0.0, 0.0, float(sx) * -deg_to_rad(18.0))
	# Yellow caution stripe at the base.
	_box(p, Vector3(size.x, 0.10, size.z * 1.05),
		Vector3(0.0, 0.05, 0.0), yel)
	if not ghost:
		_finalize_placeable(p, "concrete_v_beam")
