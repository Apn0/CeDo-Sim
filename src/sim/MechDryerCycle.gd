extends RefCounted
class_name MechDryerCycle

## DRD batch cycle: IDLE → BEFÜLLEN → TROCKNEN (30s) → ENTLEEREN → IDLE.
## DRD1 and DRD2 must run 180° out of phase.

enum Step { IDLE, BEFULLEN, TROCKNEN, ENTLEEREN }

var trockenzeit_s : float = 30.0
var befuelstop_pct : float = 90.0
var entleerstop_pct : float = 60.0
var temp_sollwert_c : float = 40.0
# #218 — Sandbox/mid-shift default: the cycle comes up ARMED because the real-
# plant shift-lead routine has already flipped Trocknungs-Automatik EIN by the
# time a sandbox or warm-boot world spawns. KufferathsDryerScope's EIN/AUS pills
# (and the enable_cycle / disable_cycle hooks below) still drive it at runtime.
# RefCounted doesn't accept @export, so this matches the plain-var pattern of
# the tunables above. Cold-commission (fresh world boot) will gate this back to
# false via the EventBus shift_started signal in a follow-up.
var cycle_enabled : bool = true

# Pulse generator settings (per Kufferath HMI photo)
const ENTLEER_OPEN_S  := 2.0
const ENTLEER_CLOSE_S := 4.0
const BESCH_OPEN_S    := 12.0
const BESCH_CLOSE_S   := 120.0

var step           : int   = Step.IDLE
var step_elapsed_s : float = 0.0
var dryer          : MechDryerModel = null

# Gate states
var entleer_open : bool = false
var besch_open   : bool = false
var _gate_t      : float = 0.0

func _init(d : MechDryerModel = null) -> void:
	dryer = d if d != null else MechDryerModel.new()

func tick(delta_s : float) -> void:
	step_elapsed_s += delta_s
	_gate_t += delta_s
	match step:
		Step.IDLE:
			entleer_open = false
			besch_open = false
			dryer.heater_on = true
			# #218 — hold at IDLE until the HMI flips Trocknungs-Automatik EIN.
			# Without this gate the cycle silently auto-starts the moment the
			# pair is registered, defeating cold commissioning.
			if cycle_enabled and dryer.fill_pct < befuelstop_pct - 1.0:
				_transition(Step.BEFULLEN)
		Step.BEFULLEN:
			# Beschickungsschieber pulse 12s open / 120s closed
			besch_open = (fmod(_gate_t, BESCH_OPEN_S + BESCH_CLOSE_S) < BESCH_OPEN_S)
			entleer_open = false
			dryer.heater_on = true
			if dryer.fill_pct >= befuelstop_pct:
				_transition(Step.TROCKNEN)
		Step.TROCKNEN:
			besch_open = false
			entleer_open = false
			dryer.heater_on = true
			if step_elapsed_s >= trockenzeit_s:
				_transition(Step.ENTLEEREN)
		Step.ENTLEEREN:
			# Entleerschieber pulse 2s open / 4s closed
			entleer_open = (fmod(_gate_t, ENTLEER_OPEN_S + ENTLEER_CLOSE_S) < ENTLEER_OPEN_S)
			besch_open = false
			dryer.heater_on = false
			if dryer.fill_pct <= entleerstop_pct:
				_transition(Step.IDLE)

func _transition(new_step : int) -> void:
	step = new_step
	step_elapsed_s = 0.0
	_gate_t = 0.0

# Antiphase helper: shift this cycle by half its nominal length so a pair runs out of phase.
func force_antiphase_start() -> void:
	step = Step.TROCKNEN
	step_elapsed_s = trockenzeit_s * 0.5

# #218 — HMI hooks. KufferathsDryerScope toggles Trocknungs-Automatik EIN/AUS
# through these. While enabled, tick() will leave IDLE on its own once the drum
# has headroom; while disabled, the cycle parks at IDLE the next time it lands
# there (an in-flight TROCKNEN/ENTLEEREN finishes normally, then holds).
func enable_cycle() -> void:
	cycle_enabled = true

func disable_cycle() -> void:
	cycle_enabled = false
