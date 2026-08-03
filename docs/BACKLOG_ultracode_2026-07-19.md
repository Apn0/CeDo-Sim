# Ultracode session backlog — 2026-07-19

16 of 40 audited findings were implemented and verified this session (harness 14/0/2,
test_cart_push 10/10, npc bench PASS). The rest were deliberately deferred; this file
is the queue for the next rounds, with the reason each item waited.

## Deferred — needs its own session (L effort)
- **npc-06 Navigation**: MainWorld navmesh has no machine/wall obstacles, no stuck
  detection, avoidance off. Only provable with in-game measured runs (bench bakes an
  obstacle-free navmesh — structurally can't catch it).
- **npc-07 Vehicle autopilot**: dead-reckoning, no path plan / obstacle handling /
  reverse-out. Depends on npc-06's obstacle-carved navmesh. Schedule as ONE
  navigation session together.
- **phys-02 Fork-pocket collision** doesn't match visible pocket mouths: needs the
  freeze-on-spawn cart redesign + collision relayout + fork_spread retune, with
  harness iteration. phys-03 (CoM pin, DONE this session) was its precondition.
- **phys-05 Frozen-kinematic vehicles** bulldoze props with infinite mass
  (squeeze-eject risk). Real fix = AnimatableBody chassis re-architecture, high blast
  radius across every vehicle. Interim MAX_SPEED clamp possible in LumpCart.gd.
- **tex-05 `_pmat(role)` pipeline**: migrate `_mat()` builders machine-by-machine
  riding the photo_audit loop, one operator render approval per machine.

## Deferred — needs the operator watching (eyeball verification)
- **tex-02 Building shell walls** flat cream; `beige_wall_001` cached with zero
  consumers. Textured walls previously rendered black faces — only visible in-game.
- **tex-07 EREMA extruder**: verify calibrated cabinet blue against
  `_extruder_start_and_PCU.png` before palette-swap.
- **npc-10 Cleaning-circuit waypoints** are hardcoded plant-local constants; verify
  against live wet-side/dry-side layouts in-game.

## Deferred — design decision first
- **npc-05 Container-emptying chain**: ⚠️ **CORRECTED 2026-07-21 — was marked DONE
  on a VACUOUS GREEN.** The code (D1-D4, O1) is real and committed, and its bench
  printed 31/31 PASS — but that bench never moved material. A real-MainWorld run
  proved the chain was **completely dead in a live session**: three independent
  stages all measured `bin 275.00 -> 275.00 kg (removed 0.00), skip 0.00 ->
  0.00 kg`. Nothing ever moved. Root causes, all runtime-measured:
  - **Boarding deadlock**: `OperatorContext` called `npc.set_physics_process(false)`
    on board, but `OverflowDumpTask.tick()` is only reachable from
    `NPC._physics_process` — so the task froze the instant it boarded, forever,
    with `_phase_t` stuck at 0.0 so even the 90 s timeout could never fire. The
    forklift stayed `occupied` for the rest of the session, jamming the idle gate
    for every future dump.
  - **No vehicle could carry bulk**: `load_bulk`/`unload_bulk` existed ONLY in the
    task's `has_method` guards and in the bench's own stub. In a real session the
    source bin emptied and the skip received `add(0.0)` — **mass was destroyed**,
    the mirror of the mass-creation bug in §C of the operator-issues doc.
  - **Prune deleted in-flight tasks**: the generator returned before marking bins
    `seen`, so the moment any forklift became occupied the live task was erased
    (observed as `open=0 active=2`).
  - Board result was discarded (`NPC.gd` dropped the bool), so a REFUSED boarding
    still advanced the phase.
  Fixed + re-verified 2026-07-21: bench **81 ok / 0 fail and mutation-tested**
  (reverting each fix turns specific greens red), real world moves **275.00 kg
  removed == 275.00 kg received**, twice (autonomous + operator `force_task`).
  **Still failing, honestly:** the shipped layout parks forklifts 205 m away and
  the autopilot jams against the perimeter fence at a repeatable coordinate —
  that is npc-06/npc-07 below, not papered over. The outdoor skip is also
  measurably INDOORS (roof 7.9 m above it); moved-outdoors was A/B tested and the
  chain then cannot complete until navigation lands, so it stays indoors as a
  labelled assumption — one constant flips it back.
  Design + evidence: `docs/DESIGN_npc05_container_chain_2026-07-20.md`,
  `src/tests/test_npc05_container_chain.gd`, `src/tests/test_npc05_realworld.gd`.

## Deferred — cheap follow-ups (bundle into next QoL round)
- **qol-06** E-to-exit a moving vehicle is silently ignored — add "stop first" prompt
  (touches OperatorContext.gd; bundle with qol-08).
- **qol-07** Hotbar slot 5 missing from Controls tab / not rebindable.
- **qol-08** Hardcoded "[E]" prefix on every prompt including refusal messages
  (4 files, 3 lanes — do as its own pass).
- **phys-07** Lump chunks can tunnel through the 2.5 cm cart-floor plate (no CCD) —
  fold into phys-02's collision relayout.
- **phys-09** Orphaned `Player.tscn` (wrong capsule radius + collision-node name,
  referenced nowhere) — deletion candidate.
- **keybinds comment**: BaleClamp.gd ~206-209 comments still say "H" for the LPG
  valve; key is now I (code correct, comment stale).

## Where the full audit lives
Raw findings (40, with file:line evidence) + the lane plan were produced by the
2026-07-19 ultracode audit workflow. The implemented set: qol-01..05, npc-01/02/03/
04/08/09/11/12, phys-01/03/04/06/08, tex-01/03/04.
