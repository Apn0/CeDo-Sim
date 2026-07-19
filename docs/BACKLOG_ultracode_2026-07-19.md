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
- **npc-05 Container-emptying chain**: overflow generator scans unregistered groups;
  CrewManager only "stands by". Needs outdoor-skip designation on WasteContainer +
  CrewManager rework. Only testable now that npc-01/npc-02 landed. First candidate
  for the next NPC session.

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
