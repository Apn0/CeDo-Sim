extends RefCounted
class_name EremaFaultRegistry

## Fault labels + codes for the EREMA BluPort Storingstabel. Two tiers:
##   1. DOCUMENTED — verbatim nr + Dutch text photographed on the LIJN 3C alarm
##      screen (3C_errors_screen.png / hmi_reference.md:59-65). These are ground
##      truth. 6522/6557 have live detectors (see detect_active); the remaining
##      three (1017, 3246, 73) are catalogued for the Storingstabel but have no
##      plant signal in the sim yet.
##   2. EMULATOR (F_* 4xxx/5xxx/6xxx below) — derived from an old operator HMI
##      emulator (Micro-Extruder/erema_hmi.py); kept as fallbacks that map onto
##      existing CeDo model state where the documented codes lack a live signal.
##
## Code ranges (emulator tier) loosely follow what's visible in the photo:
##   1xxx — filter zone faults     4xxx — process/material faults
##   5xxx — pressure faults        6xxx — snelwissel-filter faults

const F_MELT_TEMP_HIGH      := { "nr": 4001, "msg": "Smelt-temperatuur te hoog" }
const F_MOTOR_E1_OVERLOAD   := { "nr": 4002, "msg": "Motor E1 overbelasting" }
const F_HOPPER_LEVEL_LOW    := { "nr": 4003, "msg": "Vultrechter (PCU) niveau laag" }
const F_FILTER_PRESSURE_HI  := { "nr": 5503, "msg": "Filter-massadruk te hoog (ΔMP)" }
const F_COOLING_FLOW_LOW    := { "nr": 4101, "msg": "Koelwater-debiet te laag" }
const F_VACUUM_PUMP_FAIL    := { "nr": 4201, "msg": "Vacuümpomp storing" }
const F_PELLET_KNIFE_WEAR   := { "nr": 4301, "msg": "Pelletizer-messen versleten" }
## The start button's latched alarm: a start refused by a failed check, a start
## aborted, or a natraject machine that stopped under a running screw
## (operator rulings 2026-09-25, rulings file §I1/§I5/§I6). A SIM code in the
## emulator tier: no photo shows the plant's number or text for it. The live
## text (which machine, why) replaces "msg" when it is raised.
const F_NATRAJECT_START     := { "nr": 4401, "msg": "Startblokkering natraject" }

## Documented BluPort alarms — VERBATIM from the LIJN 3C Storingstabel photo
## (hmi_reference.md:59-65, file 3C_errors_screen.png, GENUINE). These are the
## real alarm nrs + Dutch texts photographed at CeDo; the codes above come from
## an old emulator and are kept only as fallbacks. The two filter-pressure
## alarms (6522/6557) are wired to live LaserFilter state in detect_active().
const F_MPF1_NOT_RELEASED   := { "nr": 6522, "msg": "Snelwissel-filter 1 [MPF1] bedrijf niet vrijgegeven" }
const F_MPF1_PRESSURE_HI    := { "nr": 6557, "msg": "Massadruk voor snelwissel-filter 1 [MPF1] te hoog - uitschakeling" }
const F_MF2_Z1_HEATCURRENT  := { "nr": 1017, "msg": "Filter-filter 2 zone 1 [MF2-Z1] verwarmingsstroomalarm" }
const F_MPF1_Z1_CHECKBOX    := { "nr": 3246, "msg": "Selectievakje-Snelwissel-filter 1 zone 1 niet in orde (-P0.11)" }
const F_CABINET_OVERTEMP    := { "nr": 73,   "msg": "Schakelkast-oververhitting (+K1)" }

## Trip threshold (bar) for the documented 6557 "massadruk voor snelwissel-filter
## te hoog" shutdown. The 3C photo shows 343 bar in red-alarm at the before-filter
## sensor while 284-298 bar ran clean, so the trip sits just under 343.
const MPF1_PRESSURE_TRIP_BAR : float = 335.0

## #223 docs->code — laserfilter 318-bar UPSTREAM over-pressure trip (item 14).
## docs/plant/swi/laserfilter-smeltdrukverschil__062_CeDo72.md: "Als de smeltdruk
## stroomopwaarts van de smeltfilter boven een grenswaarde ... stijgt, worden de
## Compactor (optie), de extruder en het pelletiseringssysteem onmiddellijk
## uitgeschakeld." Plant is set to 318 bar (manual lists 320) — matches
## LaserFilter.UPSTREAM_TRIP_BAR. This is SEPARATE from the 6557/335-bar MPF1
## quick-change-filter alarm above (that one is the 3C before-filter sensor).
const F_LF_UPSTREAM_OVERPRESSURE := { "nr": 5518, "msg": "Smeltdruk stroomopwaarts laserfilter te hoog (318 bar) - uitschakeling Compactor+extruder+pelletiser" }

## #223 docs->code — pelletiser 160-bar MP<PEL melt-pressure interlock (item 17).
## docs/plant/swi/EREMA-manual-4.3.7-pelletiseersysteem__169_CeDo84.md: "Als de
## smeltdruk boven een grenswaarde (160 bar) stijgt, worden de Compactor
## (configureerbaar), de extruder en het pelletiseersysteem onmiddellijk
## uitgeschakeld." MP<PEL = smeltdruk stroomopwaarts van de pelletiseermachine
## Operator ruling 2026-09-24: on 3A/3B that is the dP across the kopfilter
## (ExtruderModel.mp_pel_bar).
const F_PEL_MELT_PRESSURE_HI := { "nr": 5516, "msg": "Massadruk voor pelletiseermachine [MP<PEL] te hoog (160 bar) - uitschakeling" }

## Pelletiser melt-pressure interlock trip (bar) — EREMA §4.3.7 (169_CeDo84).
## "grenswaarde (160 bar) ... configureerbaar" — kept at the manual's 160 bar.
## MP<PEL above this trips Compactor + extruder + pelletiser simultaneously.
const PEL_MELT_PRESSURE_TRIP_BAR : float = 160.0

## The 5 verbatim documented alarms, in the order photographed on the 3C screen.
## Order matches the reference so a Storingstabel dump reads like the panel.
const DOCUMENTED_ALARMS : Array = [
	F_MPF1_NOT_RELEASED,   # 6522
	F_MPF1_PRESSURE_HI,    # 6557
	F_MF2_Z1_HEATCURRENT,  # 1017
	F_MPF1_Z1_CHECKBOX,    # 3246
	F_CABINET_OVERTEMP,    # 73
]

## Tunable thresholds for the auto-detection helpers below.
const MELT_TEMP_HIGH_OFFSET_C   := 25.0    # over setpoint
const HOPPER_LEVEL_LOW_PCT      := 8.0
const FILTER_DP_HIGH_BAR        := 318.0   # #223 operator override: CeDo trip is 318 bar (manual lists 320); ΔMP 182 bar in the 3A photo had no alarm
const KNIFE_WEAR_TRIP_COUNT     := 2       # of 4 knives

## Detects active EREMA-style faults from live model state. Each detector is a
## pure function: returns the canonical fault dict (with .nr + .msg) when its
## trip condition is met, or null otherwise. The HmiOverlay can merge these
## into its existing Storingstabel without changing the sim layer.
##
## Each `extruder_model` is duck-typed — only the fields we read have to exist.
## `laser_filter` (optional) is the live LaserFilter serving this extruder; when
## supplied, the two documented filter-pressure alarms (6522/6557) are detected
## from its real state. HmiOverlay resolves and passes it.
static func detect_active(extruder_model : Object, laser_filter : Object = null) -> Array:
	var out : Array = []

	# Documented BluPort filter-pressure alarms, wired to live LaserFilter
	# state (hmi_reference.md:59-65). Detected independently of extruder_model
	# so a bound filter still trips even if the model is null.
	if laser_filter != null and is_instance_valid(laser_filter):
		# 6557 - massadruk VOOR snelwissel-filter te hoog, uitschakeling. The
		# before-filter pressure = the melt-set pressure after it + its own dMP
		# (LaserFilter.mp_before_filter_bar, bar).
		if laser_filter.has_method("mp_before_filter_bar"):
			var up_bar : float = float(laser_filter.call("mp_before_filter_bar"))
			if up_bar > MPF1_PRESSURE_TRIP_BAR:
				out.append(F_MPF1_PRESSURE_HI)
		# 6522 - snelwissel-filter bedrijf niet vrijgegeven: the quick-change
		# filter is halted / mid-change so operation isn't released.
		if laser_filter.has_method("is_line_down") and bool(laser_filter.call("is_line_down")):
			out.append(F_MPF1_NOT_RELEASED)
		# #223 docs->code (item 14) — laserfilter 318-bar UPSTREAM over-pressure
		# trip. is_tripped latches at LaserFilter.UPSTREAM_TRIP_BAR (318). Surface
		# the documented shutdown row so the Storingstabel shows why the line died
		# (ExtruderMachine performs the actual latching trio shutdown).
		if "is_tripped" in laser_filter and bool(laser_filter.is_tripped):
			out.append(F_LF_UPSTREAM_OVERPRESSURE)

	if extruder_model == null:
		return out

	# #223 docs->code (item 17) — pelletiser 160-bar MP<PEL melt-pressure
	# interlock. MP<PEL (smeltdruk stroomopwaarts van de pelletiseermachine) is,
	# per the operator's ruling of 2026-09-24, the dP across the kopfilter; the
	# model carries it in bar as mp_pel_bar. Surface the documented row while
	# the condition holds; ExtruderMachine latches + trips.
	if "mp_pel_bar" in extruder_model:
		var pel_bar : float = float(extruder_model.mp_pel_bar)
		if pel_bar > PEL_MELT_PRESSURE_TRIP_BAR:
			out.append(F_PEL_MELT_PRESSURE_HI)

	# #223 docs->code (items 14/17) — persist the over-pressure trip rows via the
	# latched fault_reason. Once ExtruderMachine hard-stops the line, die pressure
	# drops to 0 (so the live-pressure branch above only catches the trip instant)
	# and the laser filter may not be passed in; fault_reason keeps the row up on
	# the Storingstabel until the operator resets the emergency stop.
	if "fault_reason" in extruder_model:
		var fr : String = String(extruder_model.fault_reason)
		if fr == "laserfilter_upstream_overpressure_318bar" and not out.has(F_LF_UPSTREAM_OVERPRESSURE):
			out.append(F_LF_UPSTREAM_OVERPRESSURE)
		elif fr == "pelletiser_meltdruk_160bar" and not out.has(F_PEL_MELT_PRESSURE_HI):
			out.append(F_PEL_MELT_PRESSURE_HI)

	# The start button's latched alarm (4401), up until it is reset on the HMI.
	if "start_seq" in extruder_model and extruder_model.start_seq != null:
		var sa : String = String(extruder_model.start_seq.alarm)
		if sa != "":
			out.append({"nr": int(F_NATRAJECT_START["nr"]), "msg": sa})

	# Filter pressure high — laser filter ΔMP (psi) above a comfortable bar
	if "primary_lf" in extruder_model and extruder_model.primary_lf != null:
		var lf : Object = extruder_model.primary_lf
		if "delta_p_psi" in lf:
			var bar : float = float(lf.delta_p_psi) / LaserFilter.PSI_PER_BAR
			if bar > FILTER_DP_HIGH_BAR:
				out.append(F_FILTER_PRESSURE_HI)

	# Motor overload — reuses any existing trip flag on the model
	if "motor_overload_tripped" in extruder_model and extruder_model.motor_overload_tripped:
		out.append(F_MOTOR_E1_OVERLOAD)
	elif extruder_model.has_method("is_motor_overloaded") and extruder_model.is_motor_overloaded():
		out.append(F_MOTOR_E1_OVERLOAD)

	# Vacuum pump failure — VACUUM_ALARM state on the model. The State enum's
	# integer index shifted when STARTING/STOPPING were inserted, so we never
	# hard-code it — match by NAME via the public get_state_name() accessor
	# (part of ExtruderModel's API, returns State.keys()[state]).
	if extruder_model.has_method("get_state_name"):
		if String(extruder_model.get_state_name()) == "VACUUM_ALARM":
			out.append(F_VACUUM_PUMP_FAIL)

	# Melt-temp high
	var setpt : float = 230.0
	if "config" in extruder_model and extruder_model.config != null and "melt_temp_setpoint_c" in extruder_model.config:
		setpt = float(extruder_model.config.melt_temp_setpoint_c)
	elif "config" in extruder_model and extruder_model.config != null and "melt_temp_setpoint" in extruder_model.config:
		setpt = float(extruder_model.config.melt_temp_setpoint)
	# #audit-H11 — ExtruderModel.gd:191 names the field `melt_temp`, not
	# `melt_temp_c`. The old guard `"melt_temp_c" in extruder_model` was
	# always false → F_MELT_TEMP_HIGH could never fire. Probe both names so
	# legacy ExtruderModel subclasses that renamed the field still work.
	if "melt_temp" in extruder_model:
		if float(extruder_model.melt_temp) > setpt + MELT_TEMP_HIGH_OFFSET_C:
			out.append(F_MELT_TEMP_HIGH)
	elif "melt_temp_c" in extruder_model:
		if float(extruder_model.melt_temp_c) > setpt + MELT_TEMP_HIGH_OFFSET_C:
			out.append(F_MELT_TEMP_HIGH)

	# Hopper / PCU-vulpeil low — try both names
	var hopper_pct : float = -1.0
	if "pcu_vulpeil_pct" in extruder_model:
		hopper_pct = float(extruder_model.pcu_vulpeil_pct)
	elif "hopper_level_pct" in extruder_model:
		hopper_pct = float(extruder_model.hopper_level_pct)
	if hopper_pct >= 0.0 and hopper_pct < HOPPER_LEVEL_LOW_PCT:
		out.append(F_HOPPER_LEVEL_LOW)

	# Pelletizer knife wear — reuses PelletizerModel.count_worn_knives()
	if "pelletizer" in extruder_model and extruder_model.pelletizer != null:
		var pm : Object = extruder_model.pelletizer
		if pm.has_method("count_worn_knives"):
			if int(pm.count_worn_knives()) >= KNIFE_WEAR_TRIP_COUNT:
				out.append(F_PELLET_KNIFE_WEAR)

	# Cooling water flow low — not yet wired (no plant signal exists).
	# Detector left here so the HmiOverlay can show the label as soon as a
	# water-flow signal is added; today the condition is always false.
	if "cooling_flow_l_per_min" in extruder_model:
		if float(extruder_model.cooling_flow_l_per_min) < 1.0:
			out.append(F_COOLING_FLOW_LOW)

	return out

## Used by HmiOverlay.STORINGSTABEL to render a row from the canonical map.
## Returns "0000 — fallback" when the entry doesn't carry a code.
static func format_row(fault : Dictionary, tijd_s : float = 0.0) -> Dictionary:
	return {
		"nr":   int(fault.get("nr", 0)),
		# floori, not `/`: whole hours/minutes are the intent but a bare integer
		# divide trips INTEGER_DIVISION and warnings are errors in this project.
		"tijd": "%02d:%02d:%02d" % [floori(tijd_s / 3600.0) % 24, floori(tijd_s / 60.0) % 60, int(tijd_s) % 60],
		"msg":  String(fault.get("msg", "")),
	}

## The 4-state ramp pattern from the operator's HMI emulator. Pure helper so
## the BluPort scope can show a smooth STARTING/STOPPING transition without
## any model change.
##
## Returns one of: "STOPPED", "STARTING", "RUNNING", "STOPPING", "FAULT".
static func derive_status_label(extruder_model : Object) -> String:
	if extruder_model == null:
		return "STOPPED"
	# Prefer the canonical state name — ExtruderModel now has real STARTING /
	# STOPPING states, so the label reads straight off the model. Only fall
	# back to rpm-derived heuristics when the state name is unrecognised.
	if extruder_model.has_method("get_state_name"):
		var sn : String = String(extruder_model.get_state_name())
		match sn:
			"OFF":              return "STOPPED"
			"IDLE":             return "STOPPED"
			"STARTING":         return "STARTING"
			"RUNNING":          return "RUNNING"
			"STOPPING":         return "STOPPING"
			"VACUUM_ALARM":     return "RUNNING"   # production continues during alarm
			"FAULT":            return "FAULT"
			"EMERGENCY_STOP":   return "FAULT"
	# Heuristic fallback for models that don't expose get_state_name()
	var rpm : float = 0.0
	var sp  : float = 0.0
	if "screw_rpm" in extruder_model: rpm = float(extruder_model.screw_rpm)
	if "config" in extruder_model and extruder_model.config != null and "screw_rpm_nominal" in extruder_model.config:
		sp = float(extruder_model.config.screw_rpm_nominal)
	if rpm < 0.5: return "STOPPED"
	if sp > 0.0 and rpm < sp * 0.92: return "STARTING"
	return "RUNNING"
