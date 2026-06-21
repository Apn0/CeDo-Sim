extends RefCounted
class_name EremaFaultRegistry

## Canonical EREMA-style fault labels + codes derived from a real operator HMI
## emulator (Micro-Extruder/erema_hmi.py). The 7 EREMA "POTENTIAL_ALARMS" are
## the textbook fault names every EREMA extruder panel shows; mapping them to
## existing CeDo model state lets the Storingstabel display canonical wording
## instead of internal sim flags.
##
## Code ranges loosely follow what's visible in 3C_errors_screen.png:
##   1xxx — filter zone faults     4xxx — process/material faults
##   5xxx — pressure faults        6xxx — snelwissel-filter faults

const F_MELT_TEMP_HIGH      := { "nr": 4001, "msg": "Smelt-temperatuur te hoog" }
const F_MOTOR_E1_OVERLOAD   := { "nr": 4002, "msg": "Motor E1 overbelasting" }
const F_HOPPER_LEVEL_LOW    := { "nr": 4003, "msg": "Vultrechter (PCU) niveau laag" }
const F_FILTER_PRESSURE_HI  := { "nr": 5503, "msg": "Filter-massadruk te hoog (ΔMP)" }
const F_COOLING_FLOW_LOW    := { "nr": 4101, "msg": "Koelwater-debiet te laag" }
const F_VACUUM_PUMP_FAIL    := { "nr": 4201, "msg": "Vacuümpomp storing" }
const F_PELLET_KNIFE_WEAR   := { "nr": 4301, "msg": "Pelletizer-messen versleten" }

## Tunable thresholds for the auto-detection helpers below.
const MELT_TEMP_HIGH_OFFSET_C   := 25.0    # over setpoint
const HOPPER_LEVEL_LOW_PCT      := 8.0
const FILTER_DP_HIGH_BAR        := 318.0   # operator-chosen trip; ΔMP at 182 bar in the LIJN 3A photo had no alarm
const KNIFE_WEAR_TRIP_COUNT     := 2       # of 4 knives

## Detects active EREMA-style faults from live model state. Each detector is a
## pure function: returns the canonical fault dict (with .nr + .msg) when its
## trip condition is met, or null otherwise. The HmiOverlay can merge these
## into its existing Storingstabel without changing the sim layer.
##
## Each `extruder_model` is duck-typed — only the fields we read have to exist.
static func detect_active(extruder_model : Object) -> Array:
	var out : Array = []
	if extruder_model == null:
		return out

	# Filter pressure high — laser filter ΔMP (psi) above a comfortable bar
	if "primary_lf" in extruder_model and extruder_model.primary_lf != null:
		var lf : Object = extruder_model.primary_lf
		if "delta_p_psi" in lf:
			var bar : float = float(lf.delta_p_psi) * 0.0689
			if bar > FILTER_DP_HIGH_BAR:
				out.append(F_FILTER_PRESSURE_HI)

	# Motor overload — reuses any existing trip flag on the model
	if "motor_overload_tripped" in extruder_model and extruder_model.motor_overload_tripped:
		out.append(F_MOTOR_E1_OVERLOAD)
	elif extruder_model.has_method("is_motor_overloaded") and extruder_model.is_motor_overloaded():
		out.append(F_MOTOR_E1_OVERLOAD)

	# Vacuum pump failure — VACUUM_ALARM state on the model (field is `state`)
	if "state" in extruder_model:
		var st : int = int(extruder_model.state)
		# State.VACUUM_ALARM is index 5 after STARTING/STOPPING were added; we
		# don't hard-code that — match the enum by name via the State dictionary.
		var enum_dict : Dictionary = extruder_model.get("State", {}) if extruder_model.has_method("get") else {}
		# `State` is exposed as an enum constant on the script, not as a Dictionary,
		# so the runtime lookup above will fail silently — fall back to comparing
		# the `get_state_name()` accessor which is part of ExtruderModel's API.
		if extruder_model.has_method("get_state_name"):
			if String(extruder_model.get_state_name()) == "VACUUM_ALARM":
				out.append(F_VACUUM_PUMP_FAIL)

	# Melt-temp high
	var setpt : float = 230.0
	if "config" in extruder_model and extruder_model.config != null and "melt_temp_setpoint_c" in extruder_model.config:
		setpt = float(extruder_model.config.melt_temp_setpoint_c)
	if "melt_temp_c" in extruder_model:
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
		"tijd": "%02d:%02d:%02d" % [int(tijd_s) / 3600 % 24, int(tijd_s) / 60 % 60, int(tijd_s) % 60],
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
