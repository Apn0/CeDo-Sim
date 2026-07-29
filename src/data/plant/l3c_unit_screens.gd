extends RefCounted
class_name L3CUnitScreenSpecs

## VERBATIM TRANSCRIPTION of the operator's per-unit HMI screens for wash line
## 3C.  Data only — the layout engine is src/scenes/hud/scopes/L3CUnitScreen.gd.
##
## SOURCE
## ------
## docs/plant/hmi_screens_2026-07-26/*.dc.html, the operator's own export.  Every
## string below was extracted from the HTML mechanically and is cited by its
## line number in the file it came from.  Nothing here is typed from memory and
## nothing is translated.
##
## THE RULE THAT MATTERS MOST
## --------------------------
## DO NOT NORMALISE THESE STRINGS.  The real screens disagree with each other,
## and the disagreements are the plant, not typos to be cleaned up:
##
##     L3C.1   "Safety zone was"       L3C.4  "Safety zone wash"
##     L3C.1   "Safety zone voorwas"   L3C.4  "Safety zone prewash"
##     L3C.3   "Peddelwalzen"          L3C.11 "Peddelwals 1,2,3,4"
##     L3C.1   "Uittrekschroef midden" (lower-case m, beside two capitalised)
##     L3C.14  "Doseersluis Links"     L3C.14 "Doseersluis Rechts"
##
## An operator reads these to find a specific device on a specific screen.
## src/tests/test_l3c_unit_screens.gd fails if a "tidy-up" collapses them.
##
## STRUCTURE IS NOT UNIFORM EITHER
## -------------------------------
## The motor cards do not all carry the same rows.  On L3C.14:
##     Mechanische Droger   Gewenst: Loopbewaking                     Reëel: Stroom
##     Reinigingsschraper   Gewenst: Aanlooptijd, Uitlooptijd         Reëel: Aanlooptijd, Uitlooptijd, Stroom
##     Doseersluis *        Gewenst: Aanlooptijd, Uitlooptijd, Loopbewaking
##                                                                    Reëel: Aanlooptijd, Uitlooptijd, Stroom
## so each card carries its own row lists rather than inheriting a template.
##
## WHICH CARD SHOWS THE MACHINE CURRENT
## -------------------------------------
## `stroom_from_machine` names the ONE card that renders the unit's machine-level
## `amps`.  This is not a fresh judgement: TagMap already maps
## `<unit>/softstarterdroger1/stroom` to MACHINE_FIELD `amps` (TagMap.gd:723), and
## `stroom_tag_motor` records the motor segment so the screen reports the same
## verbatim tag TagMap does.  Every other card renders "--", because the sim has
## no per-motor state at all (TagMap.gd:722).

## The three header chips, verbatim.  Identical on both L3C.14 screens; the CITE
## differs between them (:19 vs :21), which is why the cite lives per screen.
const HEADER_CHIPS : Array = [
	{"label": "Status Lijn 3C"},
	{"label": "Status was"},
	{"label": "Status Silo"},
]

const SCREENS : Dictionary = {
	# ---------------------------------------------------------------------
	# L3C.14 Mechanische Droger LINKS
	# docs/plant/hmi_screens_2026-07-26/Waslijn 3C L3C.14 Mech Droger Links.dc.html
	#
	# Chosen as the first ported unit screen because it is the sharpest proof
	# that machines are addressed individually now: this unit and its Rechts
	# sibling are the same machine TYPE (mech_dryer) and BOTH read 0.00 A until
	# 2026-07-29. They now read their own calibrated currents, 70.80 A and
	# 63.51 A (Line3CDef.gd:77-78, measured by test_line3c_identity).
	# ---------------------------------------------------------------------
	"L3C.14L": {
		"code": "L3C.14L",
		"tag_unit": "14l",
		"title": "L3C.14 Mechanische Droger Links",       # mockup :28
		"amps_fmt": "int",                                 # photo: L3C.14 prints a bare integer
		"stroom_from_machine": "Mechanische Droger",       # TagMap.gd:723
		"stroom_tag_motor": "softstarterdroger1",
		"cite_status": "mockup :29-30",
		"cite_timers": "mockup :32",
		"cite_cards": "mockup :37-39",
		"cite_lamps": "mockup :49",
		"cite_alarm": "mockup :24",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd",
			"Bewaking StartTijd", "Bewaking StopTijd"],    # mockup :32
		"cards": [                                          # mockup :37-39
			{"title": "Mechanische Droger",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Stroom"]},
			{"title": "Reinigingsschraper",
				"gewenst": ["Aanlooptijd", "Uitlooptijd"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
			{"title": "Doseersluis Links",
				"gewenst": ["Aanlooptijd", "Uitlooptijd", "Loopbewaking"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
		],
		"cards_bottom": [],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Deur Droger"],  # mockup :49
	},

	# ---------------------------------------------------------------------
	# L3C.14 Mechanische Droger RECHTS
	# docs/plant/hmi_screens_2026-07-26/Waslijn 3C L3C.14 Mech Droger Rechts.dc.html
	#
	# This file is HAND-AUTHORED where its Links sibling is templated: per-card
	# HTML comments, a machine SVG the other screens do not have, and different
	# line numbers throughout. Its LOGICAL content is identical apart from
	# "Doseersluis Rechts". Ported as the second screen precisely because a
	# layout engine that only works on templated input is not a layout engine.
	# ---------------------------------------------------------------------
	"L3C.14R": {
		"code": "L3C.14R",
		"tag_unit": "14r",
		"title": "L3C.14 Mechanische Droger Rechts",      # mockup :33
		"amps_fmt": "int",
		# NOT the family grey. This screen's panel face is a DARK SLATE, used 5
		# times in its file (:32 and the three motor cards), on a 1024x768 canvas
		# rather than the 1280x800 every sibling uses. Recorded in
		# docs/plant/hmi_screen_inventory_2026-07-28.md:235 — "THIS FILE IS
		# STRUCTURALLY DIFFERENT FROM ITS FIVE SIBLINGS and a porter must not
		# assume one template". Rendering it in the sibling grey would be an
		# infidelity nothing else would catch.
		"panel_bg": "#5a6070",
		"stroom_from_machine": "Mechanische Droger",       # TagMap.gd:537 (14r mirrors the approved 14l row)
		"stroom_tag_motor": "softstarterdroger1",
		"cite_status": "mockup :35-36",
		"cite_timers": "mockup :38-42",
		"cite_cards": "mockup :48-85",
		"cite_lamps": "mockup :111-113",
		"cite_alarm": "mockup :28",
		"timers": ["StartTijd", "StopTijd", "LeegdraaiTijd",
			"Bewaking StartTijd", "Bewaking StopTijd"],    # mockup :38-42
		"cards": [                                          # mockup :50, :61, :75
			{"title": "Mechanische Droger",
				"gewenst": ["Loopbewaking"],
				"reeel": ["Stroom"]},
			{"title": "Reinigingsschraper",
				"gewenst": ["Aanlooptijd", "Uitlooptijd"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
			{"title": "Doseersluis Rechts",
				"gewenst": ["Aanlooptijd", "Uitlooptijd", "Loopbewaking"],
				"reeel": ["Aanlooptijd", "Uitlooptijd", "Stroom"]},
		],
		"cards_bottom": [],
		"lamps": ["Werkschakelaar", "Safety zone wash", "Deur Droger"],  # mockup :111-113
	},
}
