extends RefCounted
class_name WeighHopper
## #223 docs->code (docs/plant/swi/TRAIN-de-weegschaal-p6c__117_CeDo39.md)
##
## Granulate weigh-and-dump hopper on the extruder output, between the
## pelletiser train and the voorraad silo. Meters PRODUCTION in fixed 25 kg
## batches, exactly as the training slide describes:
##
##   "Bij 25 kg gaat bovenste klep dicht en onderste klep open.
##    Bij 0 kg wisselen de stand van de kleppen weer."
##   (At 25 kg the upper/inlet valve closes and the lower/discharge valve
##    opens; at 0 kg the valves switch back.)
##
## So each dump = exactly 25 kg produced, and counting dumps counts production.
##
## Deterministic + headless-friendly (RefCounted, no scene deps): LineFlow feeds
## it kg per tick via feed() and pulls the released kg via tick(). The attached
## instance is reachable through MachineFlow's _weigh_hoppers registry so the HMI
## can read produced_kg / dump_count off the weegschaal node.

const BATCH_KG := 25.0        # trip point: inlet klep closes, discharge klep opens
const EPS := 1.0e-6

var hopper_kg   : float = 0.0   # live measured weight ("Meetcont. gewicht")
var produced_kg : float = 0.0   # running total dumped to the silo (= 25 * dump_count)
var dump_count  : int   = 0     # number of completed 25 kg weigh-dumps
var inlet_open  : bool  = true  # upper klep: true = accepting granulate, false = full/dumping

## Accept incoming granulate. Returns the kg ACTUALLY accepted this call:
##   * 0.0 when the inlet klep is closed (hopper full, mid-dump) or kg <= 0,
##   * clamped to the remaining headroom up to BATCH_KG, so the hopper never
##     overfills past 25 kg — the caller sees accepted < offered and knows to
##     tick (dump + reopen) before re-offering the remainder. No kg is lost.
## Reaching 25 kg closes the inlet (upper klep dicht).
func feed(kg: float) -> float:
	if not inlet_open or kg <= 0.0:
		return 0.0
	var capacity : float = BATCH_KG - hopper_kg
	if capacity <= 0.0:
		inlet_open = false
		return 0.0
	var accepted : float = minf(kg, capacity)
	hopper_kg += accepted
	if hopper_kg >= BATCH_KG - EPS:
		hopper_kg = BATCH_KG
		inlet_open = false   # bovenste klep dicht
	return accepted

## Advance the batch cycle. Returns the kg released DOWNSTREAM (to the voorraad
## silo) this tick. The discharge klep is open only while the inlet is closed
## (i.e. a full 25 kg batch is waiting): when so, dump the whole 25 kg in one
## shot, bump the production counter, and reopen the inlet at 0 kg
## ("Bij 0 kg wisselen de stand van de kleppen weer"). Returns 0.0 while still
## filling. delta is accepted for signature symmetry with the rest of the sim;
## the dump itself is instantaneous (fixed, near-zero discharge time).
func tick(delta: float) -> float:
	if delta < 0.0:
		return 0.0
	if inlet_open:
		return 0.0   # still filling — discharge klep closed, nothing released
	if hopper_kg >= BATCH_KG - EPS:
		var released : float = BATCH_KG
		hopper_kg -= BATCH_KG
		if hopper_kg < EPS:
			hopper_kg = 0.0
		produced_kg += released
		dump_count  += 1
		inlet_open   = true   # reopen bovenste klep at 0 kg
		return released
	# Inlet closed but under a full batch (shouldn't normally happen) — reopen.
	inlet_open = true
	return 0.0

## Clear all state (fresh run / world reset).
func reset() -> void:
	hopper_kg   = 0.0
	produced_kg = 0.0
	dump_count  = 0
	inlet_open  = true
