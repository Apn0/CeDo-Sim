class_name HeadFilter
extends StaticBody3D

# =============================================================================
# Kopfilter (head filter) — slide-plate screen-changer at the die head.
#
# Different beast from the laser filter:
#   * Sits POST-vacuum-degassing and PRE-die. Final polish filtration before
#     the melt hits the heated die plate of the pelletizer.
#   * Single melt-adapter block carries TWO screen-pack cavities side-by-side
#     on a hydraulic slide carrier. One cavity is ONLINE (in the melt path);
#     the other is OFFLINE and can be opened for repacking while production
#     continues. The slide is a kinematic horizontal motion driven by the
#     operator from the local control panel.
#   * NOT self-cleaning. ΔP rises monotonically as the online pack catches
#     gels, charred fines, ink residue, and grit that escaped the laser
#     filter. The operator runs the pack until ΔP nears the line limit, then
#     SWAPS to the freshly-repacked offline cavity (brief line dip during
#     the slide), then REPACKS the now-offline old cavity.
#
# Two procedures, both E-interactions:
#
#   SWAP (cavity A ↔ cavity B, ~5 s line dip):
#       SWAP_DEPRESSURIZE → SWAP_SLIDE → SWAP_REPRESSURIZE
#     Refused if the offline cavity is not FRESH (would just bring more
#     pressure online than you started with).
#
#   REPACK (offline cavity, no line dip):
#       REPACK_OPEN → REPACK_REMOVE_OLD → REPACK_CLEAN_BREAKER →
#       REPACK_INSPECT → REPACK_INSERT_NEW → REPACK_CLOSE
#     Mesh-marking on the new pack is visible at REPACK_INSPECT, picked at
#     random from the stockroom mix (60 / 80 / 100 / 120 mesh).
#
# What changes are NOT modelled (parity with the operator's earlier laser-
# filter decision — no off-screen vacuum oven, no consumables ledger):
#   * No "consumable inventory" of fresh screen packs — the stockroom is
#     assumed full. Just like the laser filter, a fresh pack is always
#     available when REPACK_INSERT_NEW fires.
#   * Breaker-plate wear is not tracked (negligible on a properly-handled
#     die-head block — wear shows up on the pack, not the breaker).
# =============================================================================

# ── Tunables ─────────────────────────────────────────────────────────────────
# A head-filter pack hits the line ΔP limit (~420 psi) after roughly the
# same dirty-melt hours as the laser filter would — they run in series.
const PACK_LIMIT_PSI            : float = 420.0   # operator should swap before this
const PACK_HARD_LIMIT_PSI       : float = 500.0   # filter_change_needed() = true above this
const LOADING_PER_KG_THROUGHPUT : float = 0.10    # g loading per kg melt — half the laser-filter rate
const DELTA_P_PER_LOADING_G     : float = 0.22    # psi per g loading
const PSI_PER_BAR               : float = 14.5038 # the operator reads the pack dP in bar
# Mesh stock: real stockroom mix of pack sizes. Higher mesh # = finer.
const MESH_OPTIONS              : Array[int] = [60, 80, 100, 120]

# Procedure timings (sim seconds)
const T_SWAP_DEPRESSURIZE_S  : float = 1.5
const T_SWAP_SLIDE_S         : float = 2.5
const T_SWAP_REPRESSURIZE_S  : float = 1.5

enum Proc {
	IDLE,
	# Swap procedure — brief line dip
	SWAP_DEPRESSURIZE, SWAP_SLIDE, SWAP_REPRESSURIZE,
	# Repack procedure on the OFFLINE cavity — no line dip
	REPACK_OPEN, REPACK_REMOVE_OLD, REPACK_CLEAN_BREAKER, REPACK_INSPECT,
	REPACK_INSERT_NEW, REPACK_CLOSE,
}

# One screen-pack cavity (A or B). Held in a 2-element array indexed by
# `_active_idx` for the online cavity and `1 - _active_idx` for the offline.
class Cavity:
	var mesh                 : int   = 80     # mesh marking on the current pack
	var loading_g            : float = 0.0
	var delta_p_psi          : float = 0.0
	var fresh                : bool  = true   # set true on REPACK_INSERT_NEW
	var pack_present         : bool  = true   # false while operator is mid-repack

# ── Live state ───────────────────────────────────────────────────────────────
var cavities             : Array = []     # [Cavity, Cavity]
var _active_idx          : int   = 0      # which cavity is online
var feed_throughput_kg_h : float = 0.0    # set by ExtruderModel each tick
var _proc                : int   = Proc.IDLE
var _proc_t              : float = 0.0
# Cascade-halt flag — set by ExtruderMachine when the extruder enters its
# FAULT cascade ("everything-except-PCU stops" per the vacuum-lid-pushed-open
# anecdote). While halted, the online cavity stops accumulating loading and
# the operator can't start a swap/repack procedure (the line isn't moving
# melt, so there's no swap to do). Cleared when the operator clears the
# upstream FAULT and the line resumes.
var is_halted            : bool  = false
# Repack "intent" — pressing E on IDLE picks REPACK if the offline cavity
# is dirty, SWAP if the offline cavity is fresh and the online is loaded.
# This keeps the single E button contextual.

# =============================================================================
func _ready() -> void:
	add_to_group("head_filter")
	add_to_group("kopfilter")
	cavities = [Cavity.new(), Cavity.new()]
	# Both cavities start with a fresh, random-mesh pack from stock.
	for c in cavities:
		c.mesh  = MESH_OPTIONS[randi() % MESH_OPTIONS.size()]
		c.fresh = true
		c.pack_present = true

# =============================================================================
func _physics_process(delta: float) -> void:
	# Cascade halt: extruder is in FAULT, nothing is moving through the line,
	# so no loading accrues and no swap/repack procedure can advance. The
	# online cavity's loading_g + delta_p_psi freeze where they were — when
	# the line resumes (cascade_resume) the operator picks up exactly where
	# they left off.
	if is_halted:
		return
	if _proc != Proc.IDLE:
		_advance_proc(delta)
		return
	# Online cavity accumulates loading. The offline cavity is static — its
	# pack just sits idle until it's swapped online or repacked.
	var on : Cavity = cavities[_active_idx]
	if on.pack_present:
		var add_g_s : float = feed_throughput_kg_h / 3600.0 * LOADING_PER_KG_THROUGHPUT
		on.loading_g += add_g_s * delta
		# No ceiling: a pack nobody swaps keeps clogging until the 160-bar MP<PEL
		# interlock stops the line (the dP across THIS filter, operator ruling
		# 2026-09-24; ExtruderMachine._check_pressure_trips). The old 600 psi
		# (41 bar) clamp had no source and made that interlock unreachable.
		on.delta_p_psi = maxf(0.0, on.loading_g * DELTA_P_PER_LOADING_G)
		# Once the pack has carried real melt for a while it's no longer "fresh".
		if on.loading_g > 5.0:
			on.fresh = false

# =============================================================================
# PUBLIC API
# =============================================================================
func set_feed_throughput(kg_h: float) -> void:
	feed_throughput_kg_h = maxf(0.0, kg_h)

## True during the slide swap (line dips while the carrier moves) OR while a
## cascade halt is active (the upstream extruder is in FAULT — vacuum-lid
## alarm cascaded everything except the PCU). REPACK does NOT take the line
## down because it's on the offline cavity.
func is_line_down() -> bool:
	return is_halted \
		or _proc == Proc.SWAP_DEPRESSURIZE \
		or _proc == Proc.SWAP_SLIDE \
		or _proc == Proc.SWAP_REPRESSURIZE

# =============================================================================
# CASCADE HALT — wired by ExtruderMachine on FAULT entry / exit
# =============================================================================
## ExtruderMachine calls this on the edge into the extruder's FAULT state.
## The head filter freezes: online cavity stops accumulating, the slide
## carrier can't move (no melt flowing means depressurization is moot, and
## a swap mid-cascade would just dump cold melt), and the operator can't
## start a new procedure. Any procedure already in flight is left where it
## is so the operator can resume it after the cascade is cleared.
func cascade_stop() -> void:
	is_halted = true

## ExtruderMachine calls this when the extruder transitions OUT of FAULT
## (operator cleared it). The online cavity resumes accumulating loading;
## any procedure that was mid-way picks up from where it paused.
func cascade_resume() -> void:
	is_halted = false

## Total ΔP across the head-filter block — currently just the online cavity's
## contribution. ExtruderModel can sum this with laser_filter.delta_p_psi to
## report a true line-melt pressure differential.
func delta_p_psi() -> float:
	var on : Cavity = cavities[_active_idx]
	return on.delta_p_psi

## The same dP in bar — what ExtruderMachine mirrors into the model, where it
## is MP<PEL (the 160-bar pelletiser interlock) and the rise of kopdruk.
func delta_p_bar() -> float:
	return delta_p_psi() / PSI_PER_BAR

func filter_change_needed() -> bool:
	var on : Cavity = cavities[_active_idx]
	return on.delta_p_psi >= PACK_HARD_LIMIT_PSI \
		or (on.delta_p_psi >= PACK_LIMIT_PSI and not cavities[1 - _active_idx].fresh == false)

# Active / offline accessors (the rest of the code reads these to avoid
# spelling out _active_idx / 1 - _active_idx everywhere).
func _online() -> Cavity:
	return cavities[_active_idx]
func _offline() -> Cavity:
	return cavities[1 - _active_idx]

# =============================================================================
# CROSSHAIR INTERACTION (E)
# =============================================================================
func crosshair_prompt(_p: Node3D) -> String:
	if is_halted:
		return "Kopfilter — cascade-stop actief (lijn in FAULT)"
	match _proc:
		Proc.IDLE:
			var on  : Cavity = _online()
			var off : Cavity = _offline()
			if off.fresh and on.delta_p_psi >= PACK_LIMIT_PSI:
				return "Schuif schermwissel — start [E]   (ΔP %.1f bar)" % (on.delta_p_psi / PSI_PER_BAR)
			if not off.pack_present or not off.fresh:
				return "Offline cavity hervullen [E]   (online ΔP %.1f bar)" % (on.delta_p_psi / PSI_PER_BAR)
			return "Kopfilter ΔP: %.1f bar   (offline gereed)" % (on.delta_p_psi / PSI_PER_BAR)
		Proc.SWAP_DEPRESSURIZE: return "Drukverlaging vóór slide…"
		Proc.SWAP_SLIDE:        return "Schuif beweegt…"
		Proc.SWAP_REPRESSURIZE: return "Druk opbouwen…"
		Proc.REPACK_OPEN:           return "Offline cavity openen [E]"
		Proc.REPACK_REMOVE_OLD:     return "Oude pack verwijderen [E]"
		Proc.REPACK_CLEAN_BREAKER:  return "Breaker plate schoonmaken [E]"
		Proc.REPACK_INSPECT:
			var n : Cavity = _offline()
			return "Nieuwe pack: %d mesh [E]" % n.mesh
		Proc.REPACK_INSERT_NEW: return "Pack plaatsen [E]"
		Proc.REPACK_CLOSE:      return "Cavity sluiten [E]"
	return ""

func crosshair_interact(_p: Node3D) -> void:
	if is_halted:
		# Refuse to start anything — the line isn't moving melt, so neither
		# SWAP nor REPACK would do what the operator expects. They need to
		# clear the upstream cascade first.
		return
	match _proc:
		Proc.IDLE:
			# Context-sensitive: if offline cavity is fresh AND online needs
			# swapping, run SWAP. Otherwise, run REPACK on the offline cavity.
			var on  : Cavity = _online()
			var off : Cavity = _offline()
			if off.fresh and off.pack_present and on.delta_p_psi >= PACK_LIMIT_PSI:
				_proc = Proc.SWAP_DEPRESSURIZE
			else:
				_proc = Proc.REPACK_OPEN
			_proc_t = 0.0
		# E-driven steps just advance to the next state.
		Proc.REPACK_OPEN, Proc.REPACK_REMOVE_OLD, Proc.REPACK_CLEAN_BREAKER, \
		Proc.REPACK_INSPECT, Proc.REPACK_INSERT_NEW, Proc.REPACK_CLOSE:
			_advance_repack_step()

# =============================================================================
# PROCEDURE STATE MACHINES
# =============================================================================
func _advance_proc(delta: float) -> void:
	_proc_t += delta
	match _proc:
		Proc.SWAP_DEPRESSURIZE:
			if _proc_t >= T_SWAP_DEPRESSURIZE_S:
				_proc = Proc.SWAP_SLIDE
				_proc_t = 0.0
		Proc.SWAP_SLIDE:
			if _proc_t >= T_SWAP_SLIDE_S:
				# Cavities swap roles. Previously-offline (fresh) cavity is
				# now online; previously-online (loaded) cavity is now
				# offline awaiting repack.
				_active_idx = 1 - _active_idx
				_proc = Proc.SWAP_REPRESSURIZE
				_proc_t = 0.0
		Proc.SWAP_REPRESSURIZE:
			if _proc_t >= T_SWAP_REPRESSURIZE_S:
				_proc = Proc.IDLE
				_proc_t = 0.0

func _advance_repack_step() -> void:
	_proc_t = 0.0
	var off : Cavity = _offline()
	match _proc:
		Proc.REPACK_OPEN:
			_proc = Proc.REPACK_REMOVE_OLD
		Proc.REPACK_REMOVE_OLD:
			off.pack_present = false
			off.loading_g = 0.0
			off.delta_p_psi = 0.0
			_proc = Proc.REPACK_CLEAN_BREAKER
		Proc.REPACK_CLEAN_BREAKER:
			_proc = Proc.REPACK_INSPECT
		Proc.REPACK_INSPECT:
			# Pick the new pack's mesh marking from stock — the operator only
			# sees this here, holding the pack before insertion.
			off.mesh = MESH_OPTIONS[randi() % MESH_OPTIONS.size()]
			_proc = Proc.REPACK_INSERT_NEW
		Proc.REPACK_INSERT_NEW:
			off.pack_present = true
			off.fresh = true
			_proc = Proc.REPACK_CLOSE
		Proc.REPACK_CLOSE:
			_proc = Proc.IDLE
