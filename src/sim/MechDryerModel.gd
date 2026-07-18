extends RefCounted
class_name MechDryerModel

## Single drum thermal/level state. Drives the antiphase cycle controller.

var fill_pct       : float = 0.0
var temp_c         : float = 20.0
var residual_moisture_pct : float = 100.0
var throughput_kg_s : float = 0.0
var heater_on      : bool  = false
var setpoint_c     : float = 40.0

const HEAT_RATE_C_PER_S := 0.30   # heater on, no flake load
const COOL_RATE_C_PER_S := 0.05
const MOISTURE_REMOVE_RATE_PCT_PER_S := 0.4  # when temp ≥ setpoint and fill > 0

func tick(delta_s : float, inflow_kg_s : float, outflow_kg_s : float) -> void:
	var drum_capacity_kg := 250.0
	fill_pct = clamp(fill_pct + (inflow_kg_s - outflow_kg_s) * delta_s * 100.0 / drum_capacity_kg, 0.0, 100.0)
	if heater_on:
		temp_c += HEAT_RATE_C_PER_S * delta_s
	else:
		temp_c -= COOL_RATE_C_PER_S * delta_s
	temp_c = clamp(temp_c, 20.0, 80.0)
	if temp_c >= setpoint_c and fill_pct > 1.0:
		residual_moisture_pct = max(0.0, residual_moisture_pct - MOISTURE_REMOVE_RATE_PCT_PER_S * delta_s)
	throughput_kg_s = outflow_kg_s
