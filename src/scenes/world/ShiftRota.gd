extends RefCounted
class_name ShiftRota

## The 2-2-2-4 continental shift calendar — pure data, no scene dependencies.
##
## A team works a repeating 10-day cycle: 2 early (vroege), 2 late, 2 night, then
## 4 rest days.  Five teams (ploegen A-E) are phased two days apart so that on
## EVERY calendar day exactly one team covers each of the three shifts and two
## teams are resting:
##
##   cycle day:   0  1  2  3  4  5  6  7  8  9
##   pattern  :   V  V  L  L  N  N  R  R  R  R     (V=vroeg L=laat N=nacht R=rust)
##
##   team A reads the pattern at (day-0), team B at (day-2), … team E at (day-8),
##   so the five teams tile the pattern with no gap and no double-cover.
##
## This is the calendar the user actually lives at CeDo: "je kunt niet onder je
## dienst uit" — the rota decides who is on the floor, who is resting, and (with
## CrewManager) which posts go unmanned when someone is on break.

enum Shift { EARLY, LATE, NIGHT, REST }

const TEAM_COUNT : int = 5      # ploegen A..E
const CYCLE_DAYS : int = 10     # length of one 2-2-2-4 cycle
const TEAM_PHASE : int = 2      # each team starts 2 days into the previous one

## One team's 10-day pattern. Index = day within the cycle.
const PATTERN : Array[int] = [
	Shift.EARLY, Shift.EARLY,
	Shift.LATE,  Shift.LATE,
	Shift.NIGHT, Shift.NIGHT,
	Shift.REST,  Shift.REST, Shift.REST, Shift.REST,
]

# =============================================================================
# QUERIES
# =============================================================================
## Which shift team `team` (0..4) works on absolute calendar `day` (0-based).
static func team_shift(team: int, day: int) -> int:
	var local := posmod(day - TEAM_PHASE * team, CYCLE_DAYS)
	return PATTERN[local]

## Every team working `shift` on `day` (normally exactly one for E/L/N, two for REST).
static func teams_on(day: int, shift: int) -> Array[int]:
	var out: Array[int] = []
	for t in TEAM_COUNT:
		if team_shift(t, day) == shift:
			out.append(t)
	return out

## Teams resting on `day` (the 2-2-2-4 always rests two of five).
static func resting_teams(day: int) -> Array[int]:
	return teams_on(day, Shift.REST)

## True if `team` is on its rest block on `day`.
static func is_resting(team: int, day: int) -> bool:
	return team_shift(team, day) == Shift.REST

## The single team covering a working shift on `day`, or -1 if none/rest.
static func team_for_shift(day: int, shift: int) -> int:
	if shift == Shift.REST:
		return -1
	var on := teams_on(day, shift)
	return on[0] if on.size() > 0 else -1

# =============================================================================
# LABELS  (Dutch, to match the PLC/HMI theme)
# =============================================================================
static func shift_label(shift: int) -> String:
	match shift:
		Shift.EARLY: return "Ochtenddienst"
		Shift.LATE:  return "Middagdienst"
		Shift.NIGHT: return "Nachtdienst"
		_:           return "Weekend"

static func shift_short(shift: int) -> String:
	match shift:
		Shift.EARLY: return "V"
		Shift.LATE:  return "L"
		Shift.NIGHT: return "N"
		_:           return "R"

static func team_label(team: int) -> String:
	# Ploeg A..E
	return "Ploeg %s" % char(65 + posmod(team, TEAM_COUNT))

## Clock window [start_hour, end_hour) for a shift; nights wrap past midnight.
static func shift_hours(shift: int) -> Vector2i:
	match shift:
		Shift.EARLY: return Vector2i(6, 14)
		Shift.LATE:  return Vector2i(14, 22)
		Shift.NIGHT: return Vector2i(22, 6)
		_:           return Vector2i(0, 0)
