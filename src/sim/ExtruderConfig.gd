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
## NOT READ since 2026-09-25. It was RUNNING's own idle -> nominal ramp, timed
## off the model's LIFETIME runtime_s, so only a model's first start ever used
## it; a later start ran straight to nominal flow on a still-cold melt and
## tripped 318 bar. A start now ramps to the operator's rpm setpoint (see
## screw_rpm_min). Kept only so the .tres files still load clean.
@export var startup_ramp_s      : float = 180.0
@export var idle_kg_per_h       : float = 50.0    # screw turning, no feed
@export var screw_rpm_idle      : float = 35.0
@export var screw_rpm_nominal   : float = 110.0
@export var screw_rpm_max       : float = 145.0
## The lowest screw speed the operator can set. A start ramps the screw from
## standstill to the operator's setpoint, which a stop leaves where it was, at
## this many rpm per ExtruderModel.START_RAMP_S (60 rpm in 3 s). Operator
## 2026-09-25 (recollection): "the minimum value possible to set 60 rpm"; a
## start "will ramp up to that 80 ... not 80 instantly"; and after a 318-bar
## trip "it is not possible to leave the extruder at 100 RPM ... as it ramps up,
## it reaches the 318 plus bar again ... So you can put it at 60 RPM. And then
## hope that it is able to start." The EREMA WinCC archive agrees on the floor:
## 3A/3B speed_extruder has no reading between 0 and 60 rpm (6-min medians,
## 2023-06-19..28, and the raw ~5 s export), and the raw starts land on 60
## after long stops, back on the old rpm after short ones
## (docs/plant/operator_rulings_2026-09-25.md §E1). Applies to every extruder.
@export var screw_rpm_min       : float = 60.0

@export_group("Thermals")
@export var melt_temp_setpoint  : float = 215.0   # °C
@export var melt_temp_min_alarm : float = 195.0
@export var melt_temp_max_alarm : float = 240.0
@export var melt_temp_drift_per_s : float = 0.3   # passive drift toward setpoint
@export var melt_temp_runaway_per_s : float = 0.8 # rate in FAULT state (legacy; FAULT no longer runs away — see ExtruderModel.gd)

## Per-zone melt-temp setpoints (size 7). Operator can drop a zone (e.g. to
## avoid burning paper/cellulose contamination) which makes the local
## viscosity climb and loads the screw motor. ExtruderModel.gd applies
## `melt_temp_setpoint` to all zones at construction if this array is empty
## or wrong-length; otherwise this overrides per-zone.
@export var zone_temp_setpoints : Array[float] = []

@export_group("Motor & torque")
## Design-max motor torque is 100 %. Trip at TORQUE_TRIP_PCT (110 %) — sustained
## > 2 s sends ExtruderModel to FAULT with fault_reason = "motor_torque_trip".
@export var motor_torque_base_pct      : float = 60.0   # nominal-run baseline
@export var motor_torque_per_10c_below : float = 20.0   # added per 10 °C below avg zone setpoint

@export_group("Filter")
@export var laser_filter_grams_between_swap : float = 8_000_000.0
@export var backflush_threshold_grams       : float = 4_000_000.0
@export var backflush_lump_mass_kg          : float = 35.0   # avg lump produced

@export_group("Melt pressures (bar)")
## All in BAR — every plant HMI, SWI and trend is (2026-09-24; the model used to
## carry one "280 psi" die pressure that had no source). Two points, per the
## operator's ruling (docs/plant/operator_rulings_2026-09-24.md). The line runs
## screw -> laserfilter (MF1) -> degassing -> melt pump -> kopfilter (MF2) ->
## heetafslag.
##
## Pressure AFTER the laserfilter at nominal throughput and melt, MP > MF. The
## melt sets it; the pressure BEFORE the laserfilter is this plus the screen's
## own dMP (LaserFilter). 25 bar = the 3A laserfilter screen, MP<MF 207 /
## dMP 182 / MP>MF 25 (docs/plant/hmi_reference.md sec 1). Line 6 reads 18-22,
## 3C 24-26 (PHOTO-erema-bluport-lijn6__226, -lijn3C-trend-8curves-2__293).
@export var mp_after_laserfilter_nominal_bar : float = 25.0
## Kopdruk (pressure INTO the kopfilter, PLC tag MD_vor_SF2) with a CLEAN pack at
## nominal throughput and melt: the melt pump's work against the die plate.
## A loading pack adds its dP on top. DERIVED, not documented: the bottom of
## this line's FORM-008 window, so one shift of pack loading (FORM-008 row 27,
## "1x per dienst minimaal wisselen") stays inside it. 3B = 140 (window 140-155).
@export var die_plate_nominal_bar : float = 140.0
## FORM-008 kopdruk window, bar (docs/plant/checklist_3a_3b.md rows 25/26):
## 3A 120-150, 3B 140-155. The SCADA gauge alarms outside it.
@export var kopdruk_window_bar : Vector2 = Vector2(140.0, 155.0)

@export_group("Startup — barrel warm-up")
## Minimum seconds from a cold barrel (ambient) to melt setpoint.
##
## Operator-confirmed, Cedo-PROD-SWI-042 p4 step 19 ("Extruder compactor 3a en
## 3b opstart"): "start je de compactors van 3a en 3b extruder op. Dit ALTIJD
## minimaal 30 minuten, in deze opwarm tijd, kunnen de silo's verder vullen."
## — start-up always takes at least 30 minutes of warm-up, during which the
## silos keep filling. That same step notes "Nog SWI maken opstarten
## extruders": there is no dedicated extruder start-up SWI yet, so step 19 is
## the authority.
##
## NB this is NOT the 15 s "voorverwarmen" button from SWI-048/049 — those are
## the SORTING LINE ("Opstarten sorteerlijn"), a different machine. See the
## note in ExtruderModel._tick_preheat().
@export var preheat_min_s : float = 1800.0

@export_group("Vacuum cascade — the signature 120-second mechanic")
@export var vacuum_alarm_grace_s     : float = 120.0
## The real plant timing: vacuum unit error → 120s grace → if missed, cascade.
## During grace period operator can fix the vacuum and clear the alarm.

@export_group("Compactor")
@export var compactor_fill_low_pct       : float = 0.20
@export var compactor_fill_high_pct      : float = 0.85
@export var compactor_silo_min_fill_pct  : float = 0.05    # below this → starvation
