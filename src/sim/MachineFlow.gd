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
		# #223 docs->code (docs/plant/swi/pelletiseer-waterbassin-trilnaald__063_CeDo86.md)
		# Pellet-dewatering (ontwaterzeef) HMI tunables. Present on every profile
		# (0.0 = off) so the HMI can read/set them uniformly; only ontwaterzeef
		# acts on them today. trilnaald_followup_s = seconds the trilmotoren keep
		# running after the pelletiser stops; basin_flush_interval_min = minutes
		# between fixed-duration water-basin flushes (0 = flushing off).
		"trilnaald_followup_s":     0.0,
		"basin_flush_interval_min": 0.0,
	}
	match id:
		# ── sinks: the extruders turn melt into granulaat (line end) ──────────
		"extruder_3a", "extruder_1", "extruder_3c", "extruder_6":
			pr["role"] = "sink"
			pr["in"]   = Vector3(0.0, 0.9, 0.45)
			pr["rate"] = 8.0
		# extruder_3b (operator 2026-07-16 "line 3B functional start to finish"):
		# demoted from sink → process so it EMITS its granulaat downstream instead
		# of banking + swallowing it. The 3B macro's pelletising back-end
		# (laser_filter → heetafslag → ontwaterzeef → centrifuge → weegschaal →
		# voorraad_silo) was placed + linked but starved because the sink emitted
		# nothing; now material flows to voorraad_silo (already a sink, line ~292),
		# which banks the granulaat at the true line end — mirroring how 3C runs
		# its extruder_screw as a process into a voorraad_silo sink. 3A / Line 1
		# extruders stay sinks (unchanged), so there is no double-count anywhere.
		"extruder_3b":
			pr["role"] = "process"
			pr["process"] = "convey"
			pr["in"]   = Vector3(0.0, 0.9, 0.45)
			pr["out"]  = Vector3(0.0, 0.35, 0.45)
			pr["rate"] = 8.0
		# ── size reduction ───────────────────────────────────────────────────
		# Dedupe: shredder_3a3b + shredder_1_3c6 removed — they were legacy ids
		# for the old generic _m_shredder model. shredder_1 (#50 bespoke) and
		# shredder_2 cover lines 3A/3B and the fine pass.
		"shredder_1", "shredder_2":
			pr["in"]  = Vector3(0.0, 0.85, 0.0)
			pr["out"] = Vector3(0.0, 0.15, 0.0)
			pr["waste"] = 0.01
			# 2026-08-29 — this used to fall through to the file's generic
			# default (6.0 kg/s = 21,600 kg/h) while ShredderMachine.gd's OWN
			# rated capacity for the exact same node — 4500/2200 kg/h,
			# doc-grounded (whole-plant film feed + 3C mass-balance figures,
			# see ShredderMachine.gd's header) — sat right next to it, unread.
			# Already flagged and left open by audit findings H6/H16
			# (docs/plant/DOCS_VS_SIM_GAP_AUDIT_2026-08-28.md and the earlier
			# DETAIL_STANDARD audit): two independent, disagreeing capacity
			# models on one node. Reading ShredderMachine's constant directly
			# (not duplicating the number) means the two can never diverge
			# again silently — test_shredder_rate_reconciliation guards it.
			# Measured consequence of the old 4.8x-looser default: a single
			# bale dumped on line 1's infeed sailed straight through
			# shredder_1 and tripped the UNRELATED downstream 'mill' node
			# instead — the coarse shredder should be the natural bottleneck
			# for a bulk dump, not a machine four stages later.
			pr["rate"] = (ShredderMachine.RATED_COARSE if id == "shredder_1"
				else ShredderMachine.RATED_FINE) / 3600.0
		"mill":
			pr["in"]  = Vector3(0.0, 0.85, 0.0)
			pr["out"] = Vector3(0.0, 0.15, 0.0)
			pr["waste"] = 0.01
			# UNLIKE shredder_1/2 above, "mill" (maalmolen_1, line 1's
			# DOWNSTREAM dry granulator — see BuildMode.gd LINE_1_SEQ, well
			# after the friction separators/dryers) has NO ShredderMachine.gd
			# brain (PlaceableCatalog only attaches one to shredder_1/2) and
			# NO real capacity figure for LINE 1 specifically. Two amp
			# readings exist in docs/plant/ that look tempting but are NOT
			# this machine: hmi_screen_inventory_2026-07-28.md's "Maalmolen
			# 240 A" is LINE 3C's mill (L3C.6), and checklist_lijn1.md row 10
			# "Lijn 5 maalmolen 130-270 Amp" is explicitly LINE 5's, per that
			# same file's own header ("this form covers both lijn 1 and lijn
			# 5"). Neither transfers. Stays on the generic default rate until
			# a real line-1 figure exists — do not borrow the 3C or Lijn-5
			# numbers here, that is the exact misattribution CLAUDE.md's
			# citation-accuracy history warns about.
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
		# vw_trommel — line 1's ONE wet drum. Operator ruling 2026-08-28 (layout
		# sketch): the voorwastrommel IS the HPS (SGA) zware-delen scheider —
		# one machine does both jobs. So this arm MERGES the two stages'
		# existing constants rather than sharing prewash_drum's:
		#   waste 0.05        = prewash 0.03 + sga heavies-reject 0.02
		#   rate  8.0         = the sga_drum arm's rate (one big drum replaces
		#                       what the sim modelled as two stages in series)
		# in/out kept from the prewash arm (funnel high at -Z in, low +Z out —
		# matches _m_vw_trommel's real geometry). Composition arithmetic on
		# constants the sim already carried — no new invented physics.
		"vw_trommel":
			pr["in"]    = Vector3(0.0, 0.80, -0.45)
			pr["out"]   = Vector3(0.0, 0.40, 0.45)
			pr["waste"] = 0.05
			pr["rate"]  = 8.0
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
		"rafter":
			# Port fractions recomputed 2026-07-06 for the raised-platform +
			# water-tank model (bbox 1.8 × 4.8 × 3.6): inlet hopper mouth at
			# ~4.57 m / +Z, discharge chute lip at ~2.7 m / -Z end.
			# waste/screen/water_remove values unchanged — no new data.
			pr["in"]   = Vector3(0.0, 0.95, 0.35)
			pr["out"]  = Vector3(0.0, 0.55, -0.5)
			pr["waste"] = 0.03
		# #91 — trilzeef: top-fed at the +Z high end (a belt drops material in
		# through the rubber flap), discharges OVERS out the -Z low end into the
		# open-top chute. The THROUGHS (small fines) drop into a collection bin
		# below — modelled as `waste` so they leave the line.
		"trilzeef":
			pr["in"]   = Vector3(0.0, 0.95, 0.40)
			pr["out"]  = Vector3(0.0, 0.10, -0.45)
			pr["waste"] = 0.08      # fines that drop through the holes
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
		# #54 — 3A/3B intake conveyor network. Twelve numbered belts ferry flake
		# between the shredder-2 climb and the switch belt. All identical from a
		# flow standpoint (conveyor, no waste); they're distinct only visually
		# (length/height/incline/colour) in PlaceableCatalog.build_intake_belt().
		"transportband_1", "transportband_2", "transportband_3", "transportband_4", \
		"transportband_5", "transportband_6", "transportband_7", \
		"transportband_9", "transportband_10", "transportband_11", "transportband_12":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.85, -0.45)
			pr["out"]  = Vector3(0.0, 0.85, 0.45)
			pr["rate"] = 8.0
		# #138 — C8 is bidirectional. Default forward to C9; when both VSSs report
		# FULL, the Conveyor8 controller ramps the belt direction to reverse over
		# 2 s, then ramps up to full reverse (another 2 s), feeding C8.5 → U-bay.
		# Modelled as a splitter so the linker emits TWO outgoing edges: wout
		# forward (to C9, nearest +Z input), wout2 reverse (to C8.5, nearest -Z).
		"transportband_8":
			pr["role"] = "splitter"
			pr["in"]   = Vector3(0.0, 0.85, -0.45)
			pr["out"]  = Vector3(0.0, 0.85,  0.45)   # forward end, feeds C9
			pr["out2"] = Vector3(0.0, 0.85, -0.45)   # reverse end, feeds C8.5
			pr["rate"] = 8.0
		# C8.5 is the slightly-lower overflow belt that C8 discharges to when
		# reversed. Plain conveyor — material flows in one direction toward the
		# U-bay (which the LineFlow linker reaches by geometry).
		"transportband_8_5":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.75, -0.45)
			pr["out"]  = Vector3(0.0, 0.75,  0.45)
			pr["rate"] = 6.0
		"switch_belt":
			# Y-junction diverter — accepts one upstream input, has TWO outputs
			# (the chute that feeds VSS and the alternate chute that feeds U-bay).
			# LineFlow._link treats role="splitter" specially: it emits TWO outgoing
			# edges, one to each output port's nearest input. Buffer-level routing
			# (split fraction biased toward the less-full downstream) is handled in
			# LineFlow._convey on a per-tick basis.
			pr["role"] = "splitter"
			pr["in"]   = Vector3(0.0, 0.85, -0.45)
			pr["out"]  = Vector3(0.0, 0.55, 0.45)    # primary output (toward VSS)
			pr["out2"] = Vector3(0.45, 0.55, 0.30)   # secondary output (toward U-bay)
			pr["rate"] = 10.0
		"vss_silo":
			# Intake metering silo — primary destination from the switch belt. When
			# its buffer fills past VSS_FULL_FRAC the switch sends the overflow to
			# u_bay. Discharges to the wash-line head (vuilsnippersilo of the line).
			pr["in"]   = Vector3(0.0, 0.9, 0.0)
			pr["out"]  = Vector3(0.0, 0.12, 0.0)
			pr["rate"] = 10.0
			pr["process"] = "buffer"
		"u_bay":
			# Concrete overflow surge bay — the U-shaped poured concrete pit the
			# Merlo scoops out of when VSS is full. Larger buffer, manual discharge
			# (the front loader carries flake back to opzetband). For now LineFlow
			# models it as a slow-discharging buffer feeding the wash-line head too.
			pr["in"]   = Vector3(0.0, 0.85, 0.0)
			pr["out"]  = Vector3(0.0, 0.15, 0.45)
			pr["rate"] = 5.0
			pr["process"] = "buffer"
		"variable_belt":
			# Variable-length conveyor — endpoints come from the placed instance's
			# vb_start / vb_end meta; the in/out fractions here are placeholders
			# that LineFlow._discover ignores for this id.
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.5, -0.5)
			pr["out"]  = Vector3(0.0, 0.5, 0.5)
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
			# Rebuilt 2026-07-06 (bunker.md §5): NOT an intake pit — a ~10 m
			# buffer CONVEYOR downstream of shredder 1 (operator interview:
			# shredder 1 bottom → belt → bunker → belt 1040). Material drops in
			# over the -Z infeed-end wall top; the travelling deck discharges at
			# the +Z end over the bunkerrol onto the next belt.
			pr["role"]  = "conveyor"
			pr["in"]    = Vector3(0.0, 0.95, -0.45)
			pr["out"]   = Vector3(0.0, 0.27, 0.45)   # deck at 1.25/5.0 ≈ 0.25 bbox height
			pr["waste"] = 0.0
			pr["rate"]  = 10.0    # kept — inside the derived 4.6-18.4 kg/s band (bunker.md §3)
		"blower":
			pr["role"] = "conveyor"
			pr["in"]   = Vector3(0.0, 0.5, 0.0)
			pr["out"]  = Vector3(0.0, 0.85, 0.0)
		"cyclone":
			pr["in"]  = Vector3(0.4, 0.8, 0.0)
			pr["out"] = Vector3(0.0, 0.08, 0.0)
		# #79 — same airsep process semantics as a chain cyclone, but the inlet
		# sits HIGH (near the top of the 8 m tower) and the discharge spout drops
		# DOWN to floor level so it can land on the top of a silo placed under
		# the tower. Y fractions tuned to size = (2.4, 8.0, 2.4).
		"cyclone_tower":
			pr["in"]  = Vector3(0.4, 0.85, 0.0)
			pr["out"] = Vector3(0.0, 0.02, 0.0)
		# ── drying / prep / storage ──────────────────────────────────────────
		"mech_dryer":
			pr["in"]  = Vector3(0.0, 0.85, -0.3)
			pr["out"] = Vector3(0.0, 0.15, 0.45)
		"mas_bak":
			pr["in"]  = Vector3(0.0, 0.9, -0.3)
			pr["out"] = Vector3(0.0, 0.5, 0.45)
		"compactor", "cutter_compactor":
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
		# Outdoor MS/LS pellet silos (silopark zuidwest, 2 rows of 5 — operator
		# 2026-07-06 ruling B8 / floor plan 240_CeDo127): same passive sink
		# treatment as voorraad_silo. They stand beyond MAX_LINK_DIST so in
		# practice they are edge-less scenery until a pneumatic blower bridge is
		# modelled (silos_ms_ls.md §7). rate copied from voorraad_silo —
		# real pneumatic transfer rate UNDOCUMENTED (silos_ms_ls.md flag 14).
		"voorraad_silo", "ms_silo_buiten", "ls_silo_buiten":
			pr["role"] = "sink"
			pr["in"]   = Vector3(0.0, 0.9, 0.0)   # pneumatic line lands on the silo TOP (125_CeDo40)
			pr["rate"] = 12.0
		# Bigbag station (gap 2.2, 3A only): granulate falls in through the
		# top cyclone/fill head; the bag BANKS it (sink) — a filled bag leaves
		# by forklift, not by line flow. Doc edge 36: Weegschaal → bigbag.
		"bigbag_station":
			pr["role"] = "sink"
			pr["in"]   = Vector3(0.0, 0.95, 0.0)
			pr["rate"] = 4.0
		"silo":
			pr["in"]  = Vector3(0.0, 0.9, 0.0)
			pr["out"] = Vector3(0.0, 0.12, 0.0)
		"doseersilo":
			# 2026-09-23 (rulings §17): a trough tilted up along +Z — "the bottom
			# is the input side, the top is the output side". Fractions of the
			# catalog box (3.4 × 5.2 × 6.2): the low-end rim sits ~2.6 m up, the
			# high-end rim ~4.9 m.
			pr["in"]  = Vector3(0.0, 0.50, -0.42)
			pr["out"] = Vector3(0.0, 0.95, 0.42)
		# ── gravity connectors (funnel / transfer chute): passive pass-throughs, NOT
		# throttles or operator machines. High rate so they never bottleneck; LineFlow's
		# flow graph already routes machine→connector→machine by geometry. (#48) ──
		"funnel", "transfer_chute":
			pr["role"] = "conveyor"
			pr["process"] = "convey"
			pr["rate"] = 60.0
			pr["in"]  = Vector3(0.0, 0.85, 0.0)
			pr["out"] = Vector3(0.0, 0.12, 0.0)
		# ── not part of the material flow ────────────────────────────────────
		# Dedupe: pump_large + wash_line removed from the catalog. water_pump
		# is the canonical pump id and stays as a role-none fixture (it doesn't
		# carry material — it pushes water through the wash loop).
		# 2026-07-06 batch: the four small water fixtures (water_small.md) are
		# role-none like water_pump/zss_water — they push WATER around the wash
		# loops, not film. eop_endpoint is an external-entity endpoint (Indaver
		# water treatment, eop_rafter.md Part A) — never a material-flow node.
		# 2026-08-15: the retired `hmi_panel` / `hmi_wall` ids left this list;
		# the `hmi_` prefix branch below covers every HMI that still exists.
		"door", "pcu_cabinet", "surface", "waste_container", "water_pump", "zss_water", \
		"kleine_la", "tankje_tussen_extruders", "pomp_c1", "pomp_zeefbocht", "eop_endpoint", \
		"heater_cabinet", "thermal_dryer_decommissioned":
			pr["role"] = "none"   # info screens / fixtures — NOT material-flow machines
		_:
			# #165 — every scoped HMI id (`hmi_shredder_l1`, etc.) is a control
			# fixture, NOT a material-flow node. Catch them all by prefix so we
			# don't have to enumerate the 12 ids here AND in HmiScopes.gd.
			if id.begins_with("hmi_"):
				pr["role"] = "none"
			# Hand tools (leaf blower / jerrycan / shovel / scanner / wrench) are
			# HELD items, not material-flow machines. Without this they defaulted to
			# role "process" and leaked into LineFlow → the crew "post" dropdown as
			# phantom stations (operator 2026-07-16: posting Mohammed to the leaf
			# blower did nothing — a dead AT_POST at a non-machine).
			elif id.begins_with("tool_") or id == "socket_wrench_7":
				pr["role"] = "none"
			# Bales and anything unrecognised are not flow nodes (bales feed the
			# head node's composition instead — see LineFlow).
			elif BaleDefs.get_origin(id.trim_suffix("_stack5")).size() > 0:
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
		"shredder_1", "shredder_2", "mill":
			pr["process"] = "shred"
		# ── buffers / silos: hold + meter, material unchanged ─────────────────
		"vuilsnippersilo", "silo", "mas_bak", "bunker", "vss_silo", "u_bay":
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
		# Trilzeef: dry sieve, no water involved; strips a chunk of fine dirt
		# (it falls through the holes with the small fraction).
		"trilzeef":
			pr["process"] = "screen"
			pr["contam_remove"] = 0.20
		# ── dewatering: mechanical water removal ──────────────────────────────
		"dewater_screw":
			pr["process"] = "dewater"
			pr["water_remove"] = 0.50
		# ── dryers: drive off the bulk of the moisture ────────────────────────
		"mech_dryer":
			pr["process"] = "dry"
			pr["water_remove"] = _mech_dryer_water_remove()
		"centrifuge":
			pr["process"] = "dry"
			pr["water_remove"] = 0.80   # spin dryer — very effective
		# ── compactor: friction heat densifies + drives off moisture ──────────
		"compactor", "cutter_compactor":
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
			# #223 docs->code (docs/plant/swi/pelletiseer-waterbassin-trilnaald__063_CeDo86.md)
			# HMI-settable tunables (default 0.0 = off). Set explicitly so the
			# ontwaterzeef node always advertises them; the flush DURATION is
			# fixed, only the interval + follow-up seconds are operator values.
			pr["trilnaald_followup_s"]     = 0.0
			pr["basin_flush_interval_min"] = 0.0
		# #223 docs->code (docs/plant/swi/TRAIN-de-weegschaal-p6c__117_CeDo39.md)
		# Weegschaal is NOT an inert buffer: it meters production in fixed 25 kg
		# weigh-and-dump batches (inlet klep closes at 25 kg, discharge klep
		# dumps to the voorraad silo, valves switch back at 0 kg). Tag "weigh"
		# so LineFlow routes it through the attached WeighHopper (see the
		# _weigh_hoppers registry below) instead of free-flowing.
		"weegschaal":
			pr["process"] = "weigh"
		"voorraad_silo", "ms_silo_buiten", "ls_silo_buiten":
			pr["process"] = "buffer"
		"bigbag_station":
			pr["process"] = "buffer"
		# ── cyclone / air sep: pulls light fines + some moisture into the air ─
		"cyclone", "cyclone_tower":
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
			pr["water_add"]     = 0.30
			pr["contam_remove"] = 0.40
		# vw_trommel = voorwas + HPS/SGA in one drum (operator ruling
		# 2026-08-28, see the arm above). contam_remove is the COMPOSITION of
		# the two merged stages' existing constants — material passing both a
		# 0.40 wash and a 0.20 screen keeps (1−0.40)·(1−0.20) of its dirt:
		#   1 − 0.60 × 0.80 = 0.52
		"vw_trommel":
			pr["process"] = "wash"
			pr["water_add"]     = 0.30
			pr["contam_remove"] = 0.52
		"kufferath_sieve":
			pr["process"] = "screen"
			pr["water_remove"]  = 0.35
			pr["contam_remove"] = 0.20
		"mengsilo":
			pr["process"] = "buffer"

# ── mech_dryer model registry (#99) ──────────────────────────────────────
# Plug a MechDryerModel in via attach_mech_dryer_model(id, model). When the
# id is "mech_dryer" we look up the FIRST attached model and let its
# (temp_c vs setpoint_c) gap drive the water_remove fraction. Without an
# attached model we fall back to the historical constant 0.70.
static var _mech_dryer_models : Dictionary = {}

static func attach_mech_dryer_model(key: String, model) -> void:
	_mech_dryer_models[key] = model

static func detach_mech_dryer_model(key: String) -> void:
	_mech_dryer_models.erase(key)

static func _mech_dryer_water_remove() -> float:
	if _mech_dryer_models.is_empty():
		return 0.70
	for key in _mech_dryer_models.keys():
		var m = _mech_dryer_models[key]
		if m == null:
			continue
		var gap : float = m.temp_c - m.setpoint_c
		var eff : float = clampf(0.70 + gap * 0.01, 0.10, 0.95)
		var residual_factor : float = clampf(m.residual_moisture_pct / 100.0, 0.0, 1.0)
		return eff * residual_factor
	return 0.70

# -- weigh-hopper registry (#223 item 16) ----------------------------
# #223 docs->code (docs/plant/swi/TRAIN-de-weegschaal-p6c__117_CeDo39.md)
# Mirror of the mech_dryer model registry above: LineFlow attaches a
# WeighHopper to a weegschaal node key, feeds it kg per tick, and pulls the
# released 25 kg dumps back out. produced_kg / dump_count are then readable
# straight off the attached hopper for the HMI. No scene deps here.
static var _weigh_hoppers : Dictionary = {}

static func attach_weigh_hopper(key: String, hopper: WeighHopper) -> void:
	_weigh_hoppers[key] = hopper

static func detach_weigh_hopper(key: String) -> void:
	_weigh_hoppers.erase(key)

## Attached WeighHopper for this node key, or null if none is registered.
static func weigh_hopper_for(key: String) -> WeighHopper:
	return _weigh_hoppers.get(key, null)
