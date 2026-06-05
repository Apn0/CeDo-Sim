extends Resource
class_name ExtruderConfig

## Tunable constants for one extruder. Create `.tres` instances per line
## (Extruder3A.tres, Extruder3B.tres, ExtruderLine1.tres, etc.).
## Values are editor-visible so they can be tuned without touching code.
##
## Defaults below are reasonable for EREMA-class extruders on LDPE film
## reclaim; override per-line based on operator-known real numbers.

@export_group("Identity")
@export var line_id      : String = "3B"
@export var display_name : String = "Extruder 3B"

@export_group("Throughput")
@export var nominal_kg_per_h    : float = 950.0   # design throughput
@export var startup_ramp_s      : float = 180.0   # 0 → nominal over this time
@export var idle_kg_per_h       : float = 50.0    # screw turning, no feed
@export var screw_rpm_idle      : float = 35.0
@export var screw_rpm_nominal   : float = 110.0
@export var screw_rpm_max       : float = 145.0

@export_group("Thermals")
@export var melt_temp_setpoint  : float = 215.0   # °C
@export var melt_temp_min_alarm : float = 195.0
@export var melt_temp_max_alarm : float = 240.0
@export var melt_temp_drift_per_s : float = 0.3   # passive drift toward setpoint
@export var melt_temp_runaway_per_s : float = 0.8 # rate in FAULT state

@export_group("Filter")
@export var laser_filter_grams_between_swap : float = 8_000_000.0
@export var backflush_threshold_grams       : float = 4_000_000.0
@export var backflush_lump_mass_kg          : float = 35.0   # avg lump produced

@export_group("Vacuum cascade — the signature 120-second mechanic")
@export var vacuum_alarm_grace_s     : float = 120.0
## The real plant timing: vacuum unit error → 120s grace → if missed, cascade.
## During grace period operator can fix the vacuum and clear the alarm.

@export_group("Compactor")
@export var compactor_fill_low_pct       : float = 0.20
@export var compactor_fill_high_pct      : float = 0.85
@export var compactor_silo_min_fill_pct  : float = 0.05    # below this → starvation
