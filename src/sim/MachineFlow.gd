extends RefCounted
class_name MachineFlow
## Per-machine flow profile for the auto-linking line simulation.
##
## Ports are given as FRACTIONS of the machine's footprint:
##   x,z ∈ [-0.5, 0.5] (offset from centre),  y ∈ [0, 1] (height above the base).
## LineFlow turns these into world positions via the machine's transform, links
## each output to the nearest downstream input, and draws a physical connector.
##
##   role  : "process" | "conveyor" | "sink" | "none" (none = not in the flow)
##   in    : input port  (where material arrives)
##   out   : output port (where material leaves)
##   waste : fraction of throughput shed as waste here (→ nearest waste container)
##   rate  : throughput limit (kg/s)
##
## WET/DIRTY PROCESS SEMANTICS (layered on by _apply_process, consumed by LineFlow
## via the MaterialBatch transforms). Each machine declares what it does to the
## two enemies — water and contamination:
##   process       : tag string (shred/wash/dry/float/screen/dewater/compact/
##                   meltfilter/airsep/sort/ballistic/optical/buffer/convey) —
##                   drives HMI + connector look
##   water_add     : frac of polymer mass taken on as water here (washing wets film)
##   water_remove  : frac of CURRENT water driven off here (drying)
##   contam_remove : frac of CURRENT dirt stripped to the nearest scraper bin
##   reject_other  : frac of off-spec "other" polymer rejected (optical/ballistic sort)
##   reject_hdpe   : frac of HDPE rejected (optical sort)

static func profile(id: String) -> Dictionary:
	var pr := {
		"role": "process",
		"in":   Vector3(0.0, 0.85, -0.45),
		"out":  Vector3(0.0, 0.35, 0.45),
		"waste": 0.0,
		"rate": 6.0,
		# Process semantics — defaults make a machine an inert pass-through.
		"process":       "convey",
		"water_add":     0.0,
		"water_remove":  0.0,
		"contam_remove": 0.0,
		"reject_other":  0.0,
		"reject_hdpe":   0.0,
	}
	match id:
		# ── sinks: the extruders turn melt into granulaat (line end) ──────────
		"extruder_3a", "extruder_3b", "extruder_1", "extruder_3c", "extruder_6":
			pr["role"] = "sink"
			pr["in"]   = Vector3(0.0, 0.9, 0.45)
			pr["rate"] = 8.0
		# ── size reduction ───────────────────────────────────────────────────
		"shredder_3a3b", "shredder_1_3c6", "shredder_1", "shredder_2", "mill":
			pr["in"]  = Vector3(0.0, 0.85, 0.0)
			pr["out"] = Vector3(0.0, 0.15, 0.0)
			pr["waste"] = 0.01
		"vuilsnippersilo":
			pr["in"]  = Vector3(0.0, 0.85, 0.0)
			pr["out"] = Vector3(0.35, 0.25, 0.0)
		# sorting line (front end: open bales, pull metal/heavies/film)
		"sga_drum":
			pr["in"]    = Vector3(0.0, 0.85, -0.45)
			pr["out"]   = Vector3(0.0, 0.30, 0.45)
			pr["waste"] = 0.02
			pr["rate"]  = 8.0
		"metal_belt":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.78, -0.45)
			pr["out"]  = Vector3(0.0, 0.78, 0.45)
			pr["rate"] = 8.0
		"ballistic_sep":
			pr["in"]    = Vector3(0.0, 0.85, -0.45)
			pr["out"]   = Vector3(0.0, 0.45, 0.45)
			pr["waste"] = 0.02
			pr["rate"]  = 7.0
		"wind_sifter":
			pr["in"]   = Vector3(0.0, 0.55, -0.45)
			pr["out"]  = Vector3(0.0, 0.80, 0.45)
			pr["rate"] = 7.0
		"titech_sort":
			pr["in"]   = Vector3(0.0, 0.80, -0.45)
			pr["out"]  = Vector3(0.0, 0.70, 0.45)
			pr["rate"] = 7.0
		"prewash_drum":
			pr["in"]    = Vector3(0.0, 0.80, -0.45)
			pr["out"]   = Vector3(0.0, 0.40, 0.45)
			pr["waste"] = 0.03
		"kufferath_sieve":
			pr["in"]  = Vector3(0.0, 0.75, -0.4)
			pr["out"] = Vector3(0.0, 0.35, 0.45)
		"mengsilo":
			pr["in"]   = Vector3(0.0, 0.95, 0.0)
			pr["out"]  = Vector3(0.0, 0.12, 0.0)
			pr["rate"] = 12.0
		# ── separation (these shed real waste) ───────────────────────────────
		"flotation_tank":
			pr["in"]   = Vector3(0.0, 0.72, -0.45)
			pr["out"]  = Vector3(0.0, 0.74, 0.45)
			pr["waste"] = 0.12                       # sinkers + skimmed reject
		"rotation_tank":
			pr["in"]   = Vector3(0.0, 0.72, -0.45)
			pr["out"]  = Vector3(0.0, 0.72, 0.45)
			pr["waste"] = 0.06
		"rafter":
			pr["in"]   = Vector3(0.0, 0.7, 0.4)
			pr["out"]  = Vector3(0.0, 0.4, -0.4)
			pr["waste"] = 0.03
		"friction_sep", "friction_washer", "intensive_washer":
			pr["waste"] = 0.04
		"sink_float":
			pr["in"]   = Vector3(0.0, 0.72, -0.45)
			pr["out"]  = Vector3(0.0, 0.72, 0.45)
			pr["waste"] = 0.10
		# ── dewatering / conveyance ──────────────────────────────────────────
		"dewater_screw":
			pr["in"]  = Vector3(0.0, 0.4, -0.45)
			pr["out"] = Vector3(0.0, 0.95, 0.45)
		"transport_screw":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.4, -0.45)
			pr["out"]  = Vector3(0.0, 0.95, 0.45)
		"transport_belt":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.85, -0.45)
			pr["out"]  = Vector3(0.0, 0.85, 0.45)
		"inclined_belt_8m":
			# Climbs (Y+Z) diagonal: input at the base (-Z is the low end), output
			# at the top corner of the bounding box. y/z fractions match the 8.5 m
			# bounding so LineFlow's port-to-port lookup hits the actual roller ends.
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.03, -0.45)
			pr["out"]  = Vector3(0.0, 0.94, 0.45)
		"feed_hopper":
			# Tiny chute — material falls in the top, dribbles out the +Z flange end.
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.95, 0.0)
			pr["out"]  = Vector3(0.0, 0.12, 0.45)
		"bunker":
			# Receives bales/loose film from the top (where the forklift dumps it)
			# and meters them out the +Z discharge mouth onto the next belt.
			pr["in"]    = Vector3(0.0, 0.95, 0.0)
			pr["out"]   = Vector3(0.0, 0.15, 0.45)
			pr["waste"] = 0.0
			pr["rate"]  = 10.0    # bunkers buffer + meter — high throughput
		"blower":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.5, 0.0)
			pr["out"]  = Vector3(0.0, 0.85, 0.0)
		"cyclone":
			pr["in"]  = Vector3(0.4, 0.8, 0.0)
			pr["out"] = Vector3(0.0, 0.08, 0.0)
		# ── drying / prep / storage ──────────────────────────────────────────
		"mech_dryer":
			pr["in"]  = Vector3(0.0, 0.85, -0.3)
			pr["out"] = Vector3(0.0, 0.5, 0.45)
		"mas_bak":
			pr["in"]  = Vector3(0.0, 0.9, -0.3)
			pr["out"] = Vector3(0.0, 0.5, 0.45)
		"compactor":
			pr["in"]  = Vector3(0.0, 0.82, -0.3)
			pr["out"] = Vector3(0.0, 0.4, 0.45)
		"extruder_screw":
			pr["in"]   = Vector3(0.0, 0.85, -0.45)
			pr["out"]  = Vector3(0.0, 0.5, 0.45)
			pr["rate"] = 8.0
		"vacuum_degas":
			pr["in"]   = Vector3(0.0, 0.6, -0.45)
			pr["out"]  = Vector3(0.0, 0.6, 0.45)
		# Line 3C extruder back-end (#175): Compactorband lifts dosed flake from the
		# Extruder Silo up into the compactor (low/-Z in, high/+Z out); the pelletizer
		# train runs head-to-tail; the Voorraad silo is the granulate product SINK.
		"compactorband":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.25, -0.45)
			pr["out"]  = Vector3(0.0, 0.85, 0.45)
			pr["rate"] = 8.0
		"centrifuge":
			pr["in"]   = Vector3(0.0, 0.55, -0.45)
			pr["out"]  = Vector3(0.0, 0.6, 0.45)
		"kopfilter":
			pr["in"]   = Vector3(0.0, 0.62, -0.45)
			pr["out"]  = Vector3(0.0, 0.62, 0.45)
		"heetafslag":
			pr["in"]   = Vector3(0.0, 0.58, -0.45)
			pr["out"]  = Vector3(0.0, 0.2, 0.45)
		"ontwaterzeef":
			pr["in"]   = Vector3(0.0, 0.7, -0.45)
			pr["out"]  = Vector3(0.0, 0.72, 0.45)
		"weegschaal":
			pr["in"]   = Vector3(0.0, 0.85, 0.0)
			pr["out"]  = Vector3(0.0, 0.12, 0.45)
		"voorraad_silo":
			pr["role"] = "sink"
			pr["in"]   = Vector3(0.0, 0.9, 0.0)
			pr["rate"] = 12.0
		"silo", "doseersilo":
			pr["in"]  = Vector3(0.0, 0.9, 0.0)
			pr["out"] = Vector3(0.0, 0.12, 0.0)
		# ── not part of the material flow ────────────────────────────────────
		"door", "pcu_cabinet", "hmi_panel", "surface", "waste_container", "water_pump", "pump_large", "wash_line", "zss_water":
			pr["role"] = "none"   # info screens / fixtures — NOT material-flow machines
		_:
			# Bales and anything unrecognised are not flow nodes (bales feed the
			# head node's composition instead — see LineFlow).
			if BaleDefs.get_origin(id.trim_suffix("_stack5")).size() > 0:
				pr["role"] = "none"
	_apply_process(pr, id)
	return pr

## Layer the wet/dirty process behaviour onto a profile. Kept separate from the
## port/rate match above so the geometry and the physics read independently. Values
## are per-PASS (each kg goes through a machine once), tuned against the real plant:
## a clean LDPE stream is wet at the washers and bone-dry by the time it pellets.
static func _apply_process(pr: Dictionary, id: String) -> void:
	match id:
		# ── line end: the extruder melt-filters dirt and degasses moisture ────
		"extruder_3a", "extruder_3b", "extruder_1", "extruder_3c", "extruder_6":
			pr["process"] = "meltfilter"
			pr["contam_remove"] = 0.85   # screen-pack catches gels / black specks
			pr["water_remove"]  = 0.95   # vacuum degassing vents off residual moisture
		# ── size reduction: no cleaning, just smaller flake ───────────────────
		"shredder_3a3b", "shredder_1_3c6", "shredder_1", "shredder_2", "mill":
			pr["process"] = "shred"
		# ── buffers / silos: hold + meter, material unchanged ─────────────────
		"vuilsnippersilo", "silo", "mas_bak", "bunker":
			pr["process"] = "buffer"
		# ── friction wash: mechanical scrub, wets the film, strips a lot of dirt
		"friction_washer", "friction_sep":
			pr["process"] = "wash"
			pr["water_add"]     = 0.45
			pr["contam_remove"] = 0.45
		# ── intensive (hot caustic) wash: highest dirt removal ────────────────
		"intensive_washer":
			pr["process"] = "wash"
			pr["water_add"]     = 0.30
			pr["contam_remove"] = 0.55
		# ── rotation tank: gentler wash + tumble ──────────────────────────────
		"rotation_tank":
			pr["process"] = "wash"
			pr["water_add"]     = 0.20
			pr["contam_remove"] = 0.35
		# ── sink/float: heavies (PET/PVC/sand) drop out; film floats off clean ─
		"flotation_tank", "sink_float":
			pr["process"] = "float"
			pr["water_add"]     = 0.40
			pr["contam_remove"] = 0.50
			pr["reject_other"]  = 0.30
		# ── sieve deck: drains water, screens fines ───────────────────────────
		"rafter":
			pr["process"] = "screen"
			pr["water_remove"]  = 0.30
			pr["contam_remove"] = 0.15
		# ── dewatering: mechanical water removal ──────────────────────────────
		"dewater_screw":
			pr["process"] = "dewater"
			pr["water_remove"] = 0.50
		# ── dryers: drive off the bulk of the moisture ────────────────────────
		"mech_dryer":
			pr["process"] = "dry"
			pr["water_remove"] = 0.70
		"centrifuge":
			pr["process"] = "dry"
			pr["water_remove"] = 0.80   # spin dryer — very effective
		# ── compactor: friction heat densifies + drives off moisture ──────────
		"compactor":
			pr["process"] = "compact"
			pr["water_remove"] = 0.60
		"extruder_screw":
			pr["process"] = "meltfilter"
			pr["water_remove"] = 0.85
			pr["contam_remove"] = 0.25
		"vacuum_degas":
			pr["process"] = "degas"
			pr["water_remove"] = 0.85
			pr["contam_remove"] = 0.20
		# ── Line 3C extruder back-end (#175) ──────────────────────────────────
		"compactorband":
			pr["process"] = "convey"
		"kopfilter":
			pr["process"] = "diehead"
		"heetafslag":
			pr["process"] = "pelletize"
			pr["water_add"] = 0.05
		"ontwaterzeef":
			pr["process"] = "dewater"
			pr["water_remove"] = 0.80
		"weegschaal", "voorraad_silo":
			pr["process"] = "buffer"
		# ── cyclone / air sep: pulls light fines + some moisture into the air ─
		"cyclone":
			pr["process"] = "airsep"
			pr["water_remove"]  = 0.20
			pr["contam_remove"] = 0.10
		# ── conveyance: inert ─────────────────────────────────────────────────
		"transport_belt", "transport_screw", "inclined_belt_8m", "feed_hopper", "blower":
			pr["process"] = "convey"
		# front-end sorting: open bales, screen fines, pull metal/heavies/off-spec
		"sga_drum":
			pr["process"] = "screen"
			pr["contam_remove"] = 0.20
		"metal_belt":
			pr["process"] = "sort"            # overband magnet pulls ferrous fines
			pr["contam_remove"] = 0.06
		"ballistic_sep":
			pr["process"] = "ballistic"
			pr["contam_remove"] = 0.18
			pr["reject_other"]  = 0.20
		"wind_sifter":
			pr["process"] = "airsep"
			pr["contam_remove"] = 0.25
		"titech_sort":
			pr["process"] = "optical"
			pr["reject_other"] = 0.60
			pr["reject_hdpe"]  = 0.20
		"prewash_drum":
			pr["process"] = "wash"
			pr["water_add"]     = 0.35
			pr["contam_remove"] = 0.40
		"kufferath_sieve":
			pr["process"] = "screen"
			pr["water_remove"]  = 0.35
			pr["contam_remove"] = 0.20
		"mengsilo":
			pr["process"] = "buffer"
