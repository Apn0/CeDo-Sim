extends RefCounted

## The extruder's start button (the RIGHT white LED ring) and its "natraject",
## the machines after the extruder that its PLC starts and stops: blower +
## weegschaal, centrifuge, ontwaterzeef, heetafslag, laserfilter.
##
## Operator rulings 2026-09-25, fourth session
## (docs/plant/operator_rulings_2026-09-25.md §I1-§I9). Recollections, not a
## document: no SWI lists the extruder's start conditions, and the plant's raw
## WinCC archive logs none of these machines.
##   * The button first runs the safety checks. If one fails, NOTHING starts:
##     the alarm rings and shows the problem, and the button does nothing
##     until the alarm is reset on the HMI (not at the machine) (§I1, §I6).
##   * Checks passed: blower -> centrifuge -> sieve -> heetafslag water ->
##     knives -> laserfilter scraper -> screw, each once the one before is up
##     (§I2). The ring blinks 0.5 s off / 0.5 s on meanwhile and goes solid as
##     the screw starts to ramp (§I3).
##   * A stop or a trip stops the screw first; the ring blinks while the rest
##     runs down, "not exactly in reverse", and goes off once everything
##     stands (§I3). Built in reverse: the order of that run-down is his
##     "about the same", not a documented sequence.
##   * A natraject machine that stops while the extruder runs trips the
##     extruder (§I5, a sim ruling: he did not know the plant's PLC here).
##   * natraject_enabled is the hidden deep setting ("natraject", on by
##     default). Off: no checks on those machines and it does not start them,
##     only the screw (§I7).
##
## Pure logic, no scene access. ExtruderMachine feeds it, every tick, the state
## of the natraject machines it found in LineFlow and applies what comes back:
## run commands per machine, a one-shot "start the screw", or a trip.

## Start order (§I2). The sim has no node for the blower that carries the
## granulate from the centrifuge up to the scale; the weegschaal step stands
## for "the path up to the scale". The heetafslag is ONE node in the sim, so
## "water, then knives" is one step. The vacuum pump has no run state in the
## sim and is not a step.
const STEP_IDS : Array[String] = ["weegschaal", "centrifuge", "ontwaterzeef", "heetafslag", "laser_filter"]
const STEP_NAMES : Dictionary = {
	"weegschaal":   "Blower + weegschaal",
	"centrifuge":   "Centrifuge",
	"ontwaterzeef": "Ontwaterzeef",
	"heetafslag":   "Heetafslag",
	"laser_filter": "Laserfilter",
}

## The ring: 0.5 s off, 0.5 s on, looped (operator: "for now we can do 0.5
## seconds off, 0.5 seconds on" — he has the exact ratio somewhere).
const BLINK_HALF_S : float = 0.5
## A step is up once its machine's spin reaches this (LineFlow ramps spin over
## SPIN_UP_S = 2.5 s), and down once it falls to SPUN_DOWN.
const SPUN_UP : float = 0.99
const SPUN_DOWN : float = 0.01
## A machine commanded on that is not up within this aborts the start. No
## plant number: 4x LineFlow's 2.5 s spin-up, so only a machine that cannot
## come up at all (held off by the line's e-stop, say) reaches it.
const STEP_TIMEOUT_S : float = 10.0
## The screw start is handed to the model once the natraject is up; if the
## model has not started the screw within this, the start is given up.
const SCREW_WAIT_S : float = 1.0

enum Phase { IDLE, NATRAJECT_UP, SCREW, RUN_DOWN }
enum Led { OFF, BLINK, SOLID }

var phase : int = Phase.IDLE
## NATRAJECT_UP: index of the machine coming up. RUN_DOWN: index of the machine
## going down (counts down from the last).
var step : int = 0
var step_t : float = 0.0
## The latched alarm. Non-empty = the button does nothing until reset_alarm().
var alarm : String = ""
var natraject_enabled : bool = true
## What each natraject machine is commanded to (id -> bool). ExtruderMachine
## writes it into LineFlow every tick.
var run_cmd : Dictionary = {}
## Every machine this sequence switched, in order: [[id, on], ...]. For tests
## and the audit trail; cleared on each press.
var switch_log : Array = []

var _blink_t : float = 0.0
## The run commands as they stood when the run-down began: only a machine that
## was switched on is waited for on the way down.
var _was_on : Dictionary = {}
var _screw_pending : bool = false
var _screw_seen : bool = false
var _screw_wait_t : float = 0.0


func _init() -> void:
	for id in STEP_IDS:
		run_cmd[id] = false


## The button. `status` is id -> {found, available, why, powered, spin} for
## each STEP_IDS machine. Returns "" when the start sequence begins, otherwise
## why nothing happened (the button is dead while an alarm is latched, and a
## failed check latches one).
func press(status: Dictionary) -> String:
	if alarm != "":
		return "alarm: " + alarm
	if phase == Phase.NATRAJECT_UP or phase == Phase.SCREW:
		return "busy"
	if not natraject_enabled:
		# The hidden setting off: no checks and nothing started. The caller
		# hands the press straight to the screw (ExtruderMachine does), and
		# tick() follows the screw from there.
		return ""
	for id in STEP_IDS:
		var s : Dictionary = status.get(id, {})
		if not bool(s.get("found", false)):
			alarm = "Start geweigerd — %s niet gevonden" % STEP_NAMES[id]
			return alarm
		if not bool(s.get("available", false)):
			alarm = "Start geweigerd — %s: %s" % [STEP_NAMES[id], String(s.get("why", "niet gereed"))]
			return alarm
	switch_log.clear()
	_enter(Phase.NATRAJECT_UP)
	step = 0
	return ""


## Clears the latched alarm (the HMI's reset). The machine that caused it must
## be put right first, or the next press latches it again.
func reset_alarm() -> void:
	alarm = ""


## One tick. `screw_driven` = the model is driving the screw (STARTING,
## RUNNING, VACUUM_ALARM); `screw_turning` = the screw still turns (rpm > 0.5,
## a coast included). Returns {"start_screw": bool, "trip": String}.
func tick(delta: float, status: Dictionary, screw_driven: bool, screw_turning: bool) -> Dictionary:
	var out := {"start_screw": false, "trip": ""}
	_blink_t += delta
	step_t += delta
	# A screw that runs without this sequence having started it (natraject
	# off, or a model put in RUNNING directly): follow it, so the ring is solid
	# and a stop still runs down. Nothing is checked on machines never started.
	if phase == Phase.IDLE and screw_driven:
		_enter(Phase.SCREW)
		_screw_seen = true
		_screw_pending = false
	match phase:
		Phase.NATRAJECT_UP:
			if not natraject_enabled:
				_to_screw(out)
				return out
			# A machine switched on (or coming up) that drops out aborts the start.
			for i in range(0, step + 1):
				var sid : String = STEP_IDS[i]
				var ss : Dictionary = status.get(sid, {})
				if not bool(ss.get("available", false)):
					alarm = "Start afgebroken — %s: %s" % [STEP_NAMES[sid], String(ss.get("why", "gestopt"))]
					_enter(Phase.RUN_DOWN)
					step = STEP_IDS.size() - 1
					return out
			var id : String = STEP_IDS[step]
			_command(id, true)
			if float(status.get(id, {}).get("spin", 0.0)) >= SPUN_UP:
				step += 1
				step_t = 0.0
				if step >= STEP_IDS.size():
					_to_screw(out)
			elif step_t > STEP_TIMEOUT_S:
				alarm = "Start afgebroken — %s komt niet op toeren" % STEP_NAMES[id]
				_enter(Phase.RUN_DOWN)
				step = STEP_IDS.size() - 1
		Phase.SCREW:
			if screw_driven:
				_screw_seen = true
				_screw_pending = false
			elif _screw_pending:
				_screw_wait_t += delta
				if _screw_wait_t > SCREW_WAIT_S:
					_screw_pending = false
					alarm = "Start afgebroken — de schroef startte niet"
					_enter(Phase.RUN_DOWN)
					step = STEP_IDS.size() - 1
					return out
			if _screw_seen and not screw_driven:
				# Stopped or tripped elsewhere (318 bar, torque, a stop): the
				# screw is already stopping; the natraject follows once it stands.
				_enter(Phase.RUN_DOWN)
				step = STEP_IDS.size() - 1
				return out
			if natraject_enabled and _screw_seen:
				for sid2 in STEP_IDS:
					var st : Dictionary = status.get(sid2, {})
					if bool(run_cmd.get(sid2, false)) and not bool(st.get("powered", false)):
						alarm = "Natraject gestopt — %s: %s" % [STEP_NAMES[sid2], String(st.get("why", "gestopt"))]
						out["trip"] = alarm
						_enter(Phase.RUN_DOWN)
						step = STEP_IDS.size() - 1
						return out
		Phase.RUN_DOWN:
			# The screw stops first; the rest only once it stands.
			if screw_turning:
				return out
			while step >= 0:
				var did : String = STEP_IDS[step]
				if bool(_was_on.get(did, false)):
					_command(did, false)
					var sd : Dictionary = status.get(did, {})
					if bool(sd.get("found", false)) and float(sd.get("spin", 0.0)) > SPUN_DOWN:
						return out
				step -= 1
			_enter(Phase.IDLE)
	return out


func led() -> int:
	match phase:
		Phase.NATRAJECT_UP, Phase.RUN_DOWN:
			return Led.BLINK
		Phase.SCREW:
			return Led.SOLID
	return Led.OFF


## Whether the ring is lit right now: a blink starts with its 0.5 s off half.
func led_lit() -> bool:
	match led():
		Led.SOLID:
			return true
		Led.BLINK:
			return fmod(_blink_t, 2.0 * BLINK_HALF_S) >= BLINK_HALF_S
	return false


## One line for the HMI and the machine's prompt.
func status_text() -> String:
	if alarm != "":
		return alarm + " (reset op de extruder-HMI)"
	match phase:
		Phase.NATRAJECT_UP:
			return "Startvolgorde: %s start" % STEP_NAMES[STEP_IDS[mini(step, STEP_IDS.size() - 1)]]
		Phase.SCREW:
			return "Schroef draait"
		Phase.RUN_DOWN:
			return "Natraject stopt"
	return "Gereed" if natraject_enabled else "Gereed (natraject UIT)"


func _to_screw(out: Dictionary) -> void:
	_enter(Phase.SCREW)
	_screw_pending = true
	_screw_seen = false
	_screw_wait_t = 0.0
	out["start_screw"] = true


func _command(id: String, on: bool) -> void:
	if bool(run_cmd.get(id, false)) != on:
		run_cmd[id] = on
		switch_log.append([id, on])


func _enter(p: int) -> void:
	if p == Phase.RUN_DOWN:
		_was_on = run_cmd.duplicate()
	if (p == Phase.NATRAJECT_UP or p == Phase.RUN_DOWN) and phase != Phase.NATRAJECT_UP and phase != Phase.RUN_DOWN:
		_blink_t = 0.0
	phase = p
	step_t = 0.0


## Resume on load (rulings file §R1-§R3): where the sequence is, its latched
## alarm, the hidden natraject setting, and each natraject machine's run command.
## The switch log is an audit trail of one press and is not saved.
const RESUME_FIELDS : Array[String] = [
	"phase", "step", "step_t", "alarm", "natraject_enabled", "run_cmd",
	"_blink_t", "_was_on", "_screw_pending", "_screw_seen", "_screw_wait_t",
]
const _Resume := preload("res://src/sim/PlantResume.gd")

func save_run_state() -> Dictionary:
	return _Resume.pack(self, RESUME_FIELDS)

func restore_run_state(d: Dictionary) -> void:
	_Resume.unpack(self, d)
