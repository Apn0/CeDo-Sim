extends Node

class_name ShiftClock

## Real-time 1:1 shift clock, 07:00 – 15:00 (8 hours).
##
## MainWorld is the single authority for calling start_shift() or
## load_shift_state() + resume_shift().  ShiftClock._ready() intentionally
## does NOT touch GameState to avoid the sibling-ordering race condition
## (ShiftClock is child[0], GameState is child[1] — GameState._ready() hasn't
## run yet when ShiftClock._ready() fires).

const SHIFT_START_HOUR  : int = 7
const SHIFT_START_MINUTE: int = 0
const SHIFT_END_HOUR    : int = 15
const SHIFT_END_MINUTE  : int = 0

var shift_elapsed_seconds: float = 0.0
var shift_total_seconds  : float = (SHIFT_END_HOUR - SHIFT_START_HOUR) * 3600.0
var shift_active         : bool  = false

# ── #166 Pre-shift window ────────────────────────────────────────────────────
# When start_pre_shift(window_s) is called, shift_elapsed_seconds is seeded to
# `-window_s` and ticks UP through zero. The bell rings (shift_started emitted
# a second time) when elapsed crosses 0. During the negative window the clock
# advances with the same time_scale; get_time_string() shows e.g. "06:30" when
# the dienst is Vroege and elapsed is -1800. PreShiftSequence in MainWorld
# reads is_pre_shift() and dispatches NPC arrival actions off this clock.
var _pre_shift_bell_pending : bool = false   # emit shift_started when elapsed crosses 0

# Time COMPRESSION. The clock used to run 1:1 with real time — an 8-hour shift
# took 8 REAL hours, so the display barely crept off 07:00 (and a save left at
# the end reloaded frozen at 15:00, which is the bug the operator hit). With a
# scale of 24, the 8 h window plays out in ~20 real minutes. Tunable per taste.
@export var time_scale   : float = 24.0
# When the shift reaches 15:00, auto-advance to the next WORKING day's shift
# instead of freezing. The operator asked for "proceed to the next shift / day"
# to be worked out — this is it. Set false to hold at the end (e.g. for a
# between-shift summary screen later).
@export var auto_advance : bool = false

# ── 2-2-2-4 calendar context ─────────────────────────────────────────────────
# The clock above still runs the single playable 07:00–15:00 window; these two
# fields place that window in the wider rota so the HUD/CrewManager know which
# dienst it is, which ploeg is on, and who is resting. day_index 0 / team_index 0
# (Ploeg A) lands on a Vroege dienst — coherent with the 07:00 start.
var day_index : int = 0      # absolute calendar day, 0-based
var team_index: int = 0      # the player's ploeg (0 = A … 4 = E)

# GameState reference — resolved lazily when needed for save/load.
var _game_state: GameState

signal shift_started
signal shift_ended
signal shift_rolled_over(new_day_index: int)   # auto-advanced to a new working day
signal time_updated(time_string: String)
## Emitted when seek_to_wall_time() / set_day_index() jumps the clock.
## MainWorld + PreShiftSequence listen so they can re-evaluate NPC / car state
## at the new instant instead of being stuck in whatever the last forward tick
## produced. payload: new elapsed_seconds.
signal time_jumped(new_elapsed_seconds: float)

# =============================================================================
func _ready() -> void:
	# MainWorld._start_or_resume_shift() drives the shift itself; here we only wire
	# the operator-set time-compression preference (#166) and seed the display.
	_apply_time_scale_setting()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_signal("settings_applied"):
		sm.settings_applied.connect(_apply_time_scale_setting)
		# Live-apply starting time/date when the operator clicks Apply in the
		# Settings menu. _last_applied_* gate prevents the in-shift "save +
		# reload was fine, my real shift moved on and I just bumped Render
		# scale" case from yanking the clock backwards — only a CHANGED
		# starting_time / starting_date triggers a re-seek.
		sm.settings_applied.connect(_on_settings_applied)
	emit_signal("time_updated", get_time_string())

# Last-applied starting_time / starting_date. apply_starting_settings() and
# _on_settings_applied() update these; the latter only re-seeks when they
# CHANGE, so the operator can edit graphics/audio without their shift jumping.
var _last_applied_start_time : String = ""
var _last_applied_start_date : String = ""

func _on_settings_applied() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null or not sm.has_method("gameplay"):
		return
	var gp : Dictionary = sm.gameplay()
	var t : String = String(gp.get("starting_time", ""))
	var d : String = String(gp.get("starting_date", ""))
	if t == _last_applied_start_time and d == _last_applied_start_date:
		return
	_last_applied_start_time = t
	_last_applied_start_date = d
	apply_starting_settings()

## Pull the time-compression rate from the gameplay settings (#166), so the
## operator picks the shift pace. Falls back to the @export default when the
## SettingsManager autoload isn't present (e.g. a bare headless harness).
func _apply_time_scale_setting() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("gameplay"):
		time_scale = clampf(float(sm.gameplay().get("shift_time_scale", time_scale)), 1.0, 240.0)

func _physics_process(delta: float) -> void:
	if not shift_active:
		return

	# Compressed time — `time_scale` game-seconds per real second.
	var prev := shift_elapsed_seconds
	shift_elapsed_seconds += delta * time_scale

	# #166 — pre-shift bell: when elapsed crosses 0 from below, fire shift_started
	# once and clear the pending flag. CrewManager/PreShiftSequence both listen.
	if _pre_shift_bell_pending and prev < 0.0 and shift_elapsed_seconds >= 0.0:
		_pre_shift_bell_pending = false
		emit_signal("shift_started")

	if shift_elapsed_seconds >= shift_total_seconds:
		shift_elapsed_seconds = shift_total_seconds
		emit_signal("shift_ended")
		if auto_advance:
			roll_to_next_shift()       # → next working day, fresh 07:00 window
		else:
			shift_active = false       # hold at 15:00 (for a summary screen, etc.)

	emit_signal("time_updated", get_time_string())

## End of shift → advance the 2-2-2-4 calendar to the player ploeg's next
## WORKING day (skipping the 4-day rest block) and begin a fresh 07:00 window.
## Keeps the clock progressing day after day instead of freezing at 15:00.
func roll_to_next_shift() -> void:
	advance_day(1)
	var guard := 0
	while is_resting_today() and guard < 14:
		advance_day(1)
		guard += 1
	shift_elapsed_seconds = 0.0
	shift_active = true
	emit_signal("shift_rolled_over", day_index)
	emit_signal("shift_started")

# =============================================================================
# CONTROL
# =============================================================================
func start_shift() -> void:
	shift_active          = true
	shift_elapsed_seconds = 0.0
	_pre_shift_bell_pending = false
	emit_signal("shift_started")

## #166 — Begin a pre-shift window of `window_seconds` game-seconds. The clock
## seeds to -window_seconds, ticks forward, and emits shift_started a second
## time when it crosses 0. Callers that care about "the shift bell" should
## subscribe to shift_started; callers that want the wider on-site window (i.e.
## NPC dispatch loops) should poll is_pre_shift() / is_active().
func start_pre_shift(window_seconds: float) -> void:
	shift_active          = true
	shift_elapsed_seconds = -absf(window_seconds)
	_pre_shift_bell_pending = true

func pause_shift() -> void:
	shift_active = false

func resume_shift() -> void:
	shift_active = true

## Seek the clock so its wall-clock readout shows HH:MM. Solves "operator set
## a starting time — make NPCs / cars match that instant" without bolting on
## a separate save/load round-trip. The math is the inverse of get_time_string():
##   target_minutes - shift_start_minutes → elapsed seconds (can be negative
##   for pre-shift, e.g. 06:30 on a Vroege day is -1800).
## If allow_day_rollover is true and the target is BEHIND the current elapsed,
## advance the day so we land on the NEXT instance of HH:MM (skipping the
## team's rest block). emit time_jumped so MainWorld / PreShiftSequence can
## reposition cars + NPC state machines.
func seek_to_wall_time(hour: int, minute: int, allow_day_rollover: bool = true) -> void:
	var target_min : int = hour * 60 + minute
	var start_min  : int = shift_start_hour() * 60 + SHIFT_START_MINUTE
	# Offset in minutes from this dienst's start. Wrap into the symmetric
	# [-12h .. +12h] window so 03:00 on a Vroege day reads as 4 h INTO last
	# night's shift, not 20 h ago.
	var delta_min : int = target_min - start_min
	while delta_min < -12 * 60: delta_min += 24 * 60
	while delta_min >  12 * 60: delta_min -= 24 * 60
	var new_elapsed : float = float(delta_min) * 60.0
	if allow_day_rollover and new_elapsed < shift_elapsed_seconds:
		advance_day(1)
		var guard := 0
		while is_resting_today() and guard < 14:
			advance_day(1)
			guard += 1
	shift_elapsed_seconds = new_elapsed
	_pre_shift_bell_pending = (new_elapsed < 0.0)
	shift_active = true
	emit_signal("time_updated", get_time_string())
	emit_signal("time_jumped", shift_elapsed_seconds)

## Move directly to a specific calendar day_index (cannot go BACK — the rota
## models a forward-only timeline; pass d <= day_index for a no-op).
func set_day_index(d: int) -> void:
	if d > day_index:
		advance_day(d - day_index)
		emit_signal("time_jumped", shift_elapsed_seconds)

## Apply the operator's "Starting time" / "Starting date" settings (gameplay).
## Called once at MainWorld bootstrap AFTER load_shift_state(): if the operator
## set a time/date in the Settings UI, this overrides the saved/default state.
## A blank "starting_time" leaves the loaded state untouched; a blank
## "starting_date" treats the offset as 0 days from today.
##
## Date handling: starting_date is YYYY-MM-DD. We treat it as a number-of-days
## delta from today's system date, then convert that delta to day_index by
## advancing the rota that many days. This keeps the existing 2-2-2-4 rota
## semantics (day_index = absolute working-day count) intact.
func apply_starting_settings() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null or not sm.has_method("gameplay"):
		return
	var gp : Dictionary = sm.gameplay()
	var time_s : String = String(gp.get("starting_time", "")).strip_edges()
	var date_s : String = String(gp.get("starting_date", "")).strip_edges()
	# Date first — sets the calendar day before we seek to the time within it.
	if date_s != "":
		var parts : PackedStringArray = date_s.split("-")
		if parts.size() == 3:
			var y := int(parts[0]); var mo := int(parts[1]); var d := int(parts[2])
			var picked : Dictionary = {"year": y, "month": mo, "day": d}
			var today_d : Dictionary = Time.get_date_dict_from_system()
			var delta_days : int = _days_between(today_d, picked)
			if delta_days > 0:
				set_day_index(day_index + delta_days)
	# Time second — apply HH:MM as wall-clock, with day-rollover semantics so
	# "set 07:00 at 13:00 on a Vroege day" lands on tomorrow's 07:00 not
	# yesterday's. With no day set explicitly the rollover handles overnight
	# correctly for the player.
	if time_s != "":
		var hm : PackedStringArray = time_s.split(":")
		if hm.size() == 2:
			var h := int(hm[0]); var m := int(hm[1])
			h = clampi(h, 0, 23)
			m = clampi(m, 0, 59)
			# When the operator also picked a date, don't roll over again —
			# the date already locked the day_index.
			var allow_rollover : bool = (date_s == "")
			seek_to_wall_time(h, m, allow_rollover)

## Days between two date dicts (today → target). Negative means target is in
## the past (we clamp to 0 above). Uses the proleptic Gregorian calendar via
## a serial-day count — cheap and accurate enough for the rota window.
func _days_between(a: Dictionary, b: Dictionary) -> int:
	return _serial_day(b) - _serial_day(a)

func _serial_day(d: Dictionary) -> int:
	var y : int = int(d.get("year", 1970))
	var m : int = int(d.get("month", 1))
	var dd : int = int(d.get("day", 1))
	# Shift Jan/Feb into the previous year so leap-day math lines up.
	if m <= 2:
		y -= 1
		m += 12
	# Howard Hinnant's days_from_civil — handles all proleptic Gregorian dates.
	var era : int = (y if y >= 0 else y - 399) / 400
	var yoe : int = y - era * 400                # [0, 399]
	var doy : int = (153 * (m - 3) + 2) / 5 + dd - 1     # [0, 365]
	var doe : int = yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468           # offset so 1970-01-01 → 0

# =============================================================================
# QUERIES
# =============================================================================
func get_time_string() -> String:
	# #166 — handle negative (pre-shift) time. Offset hour/minute backwards from
	# the dienst start, wrapping into the previous day if necessary (so -30 min
	# before 07:00 reads as 06:30, and -60 min before 23:00 reads as 22:00).
	var total_s : int = int(shift_elapsed_seconds)
	var base_minutes : int = shift_start_hour() * 60 + int(total_s / 60.0)
	# Modulo into [0, 1440) so negative totals wrap to "yesterday evening".
	base_minutes = ((base_minutes % 1440) + 1440) % 1440
	var hours   : int = base_minutes / 60
	var minutes : int = base_minutes % 60
	return "%02d:%02d" % [hours, minutes]

## The clock start hour for the dienst this playable window represents.
func shift_start_hour() -> int:
	match current_shift():
		ShiftRota.Shift.EARLY: return 7
		ShiftRota.Shift.LATE:  return 15
		ShiftRota.Shift.NIGHT: return 23
		_:                     return 7   # rest days are skipped by the rollover

func get_elapsed_seconds() -> float:
	return shift_elapsed_seconds

func get_remaining_seconds() -> float:
	return maxf(0.0, shift_total_seconds - shift_elapsed_seconds)

func get_progress_percent() -> float:
	# Pre-shift reads 0%; only the productive 07–15 window fills the bar.
	return clampf(shift_elapsed_seconds / shift_total_seconds, 0.0, 1.0)

func is_in_shift() -> bool:
	# Active and past the bell. Excludes the pre-shift window.
	return shift_active and shift_elapsed_seconds >= 0.0 and shift_elapsed_seconds < shift_total_seconds

## #166 — True while the clock is ticking but the bell hasn't rung yet.
func is_pre_shift() -> bool:
	return shift_active and shift_elapsed_seconds < 0.0

## Seconds remaining until the bell. Returns 0 once the shift has started.
func get_pre_shift_remaining_seconds() -> float:
	return maxf(0.0, -shift_elapsed_seconds)

# =============================================================================
# CALENDAR (2-2-2-4 rota context for the played shift)
# =============================================================================
## The dienst this playable window represents, per the rota.
func current_shift() -> int:
	return ShiftRota.team_shift(team_index, day_index)

func current_shift_label() -> String:
	return ShiftRota.shift_label(current_shift())

func current_team_label() -> String:
	return ShiftRota.team_label(team_index)

## True when the player's own ploeg is on its 4-day rest block.
func is_resting_today() -> bool:
	return ShiftRota.is_resting(team_index, day_index)

## Advance the calendar (e.g. on shift_ended → next working day).
func advance_day(n: int = 1) -> void:
	day_index += maxi(0, n)

## "Dag 3 · Vroege dienst · Ploeg A" — one line for the HUD.
func calendar_string() -> String:
	return "Dag %d · %s · %s" % [day_index + 1, current_shift_label(), current_team_label()]

# =============================================================================
# SAVE / LOAD  (called by MainWorld, which already holds the GameState ref)
# =============================================================================
func save_shift_state() -> void:
	var gs := _get_game_state()
	if gs:
		gs.save_shift_state({
			"elapsed_seconds": shift_elapsed_seconds,
			"is_active":       shift_active,
			"day_index":       day_index,
			"team_index":      team_index,
		})

func load_shift_state() -> void:
	var gs := _get_game_state()
	if not gs:
		return
	var state := gs.load_shift_state()
	if state.is_empty():
		return
	shift_elapsed_seconds = state.get("elapsed_seconds", 0.0)
	day_index  = int(state.get("day_index", day_index))
	team_index = int(state.get("team_index", team_index))
	# If the saved shift had already run out, DON'T resume frozen at 15:00 (the
	# reported bug) — advance to the next working day and start fresh at 07:00.
	if shift_elapsed_seconds >= shift_total_seconds:
		advance_day(1)
		var guard := 0
		while is_resting_today() and guard < 14:
			advance_day(1)
			guard += 1
		shift_elapsed_seconds = 0.0
	# Don't restore shift_active from save — MainWorld calls resume_shift() after.

func _get_game_state() -> GameState:
	if not _game_state:
		# GameState is a sibling under MainWorld. Sibling path is timing-independent
		# (current_scene may still be null during MainWorld._ready(), when this runs).
		_game_state = get_node_or_null("../GameState") as GameState
	return _game_state
