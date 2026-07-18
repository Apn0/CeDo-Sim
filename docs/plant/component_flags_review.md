# New-component spec flags — review (2026-07-06)

61 flags raised by the six component spec sheets (scratchpad `component_specs/`, spec
phase of the new-components build). Every flag = a spot where documentation ran out and
the spec chose a marked placeholder instead of inventing. Grouped here by KIND, because
the kinds have very different consequences.

## A. Confirmed code bug — fix FIRST, independent of any new component (1)

**I1 — side-lane utilities poison `lf_explicit_outs`** (BuildMode.gd ~:1300, confirmed by
code reading). Branch entries for flow-irrelevant utilities (role-none, e.g. water pumps)
write `lf_explicit_outs` onto the previous main machine; LineFlow treats any node with a
non-empty `lf_explicit_outs` as `explicit_src` and skips its geometry fallback → on a
fresh `line_3a` macro build, `transfer_chute` ends up with **no outgoing edge** — a
material-flow break that exists TODAY. Fix: `_is_flow_relevant(mid)` guard (predicate
already exists, BM:367-393) before the branch bookkeeping. **Prerequisite** for adding
`kleine_la` or the pump entries — they are exactly the kind of side-lane utility that
triggers it.
*Consequence if ignored: line 3A macro flow silently broken; every new utility makes it worse.*

## B. Document conflicts — need an operator ruling, else wrong-by-construction (8)

| # | Conflict | The two sources |
|---|---|---|
| B1 | Bunker doors: plexiglass vs barred/grated | Interview (plexiglass) vs SWI-049 photo (barred) |
| B2 | Bunker belts: which is infeed, which outfeed | Interview: 1012 in / 1040 out; SWI-042-p1 puts band 1040 UNDER shredder 1 |
| B3 | Bunker max speed | FORM-008 range 200–800 vs HMI photo showing setpoint 875 |
| B4 | Bunker fill scale | Three scales seen: 100–130 cm, "2.0 = full", HMI "filling actual 258" |
| B5 | Afzuiging count | Brief: 2 hoods per compactor (unit 2 dead) vs Q13 answer reading: 1 per compactor, row 22 = the 3B unit |
| B6 | MS→LS transfer topology | 125_CeDo40: voorraad→meng→transport chain vs interview: blowers silo-to-silo |
| B7 | Rafter platform height | "at 3B flotation-tank height": tank BOTTOM on the 3.5 m stand top, or RIM aligned at 4.1 m? |
| B8 | Outdoor silo count | Floor plan circles: 10 (2×5) vs digest read: ~9 vs interview: ~10 |

*Consequence: these are the only flags where a placeholder could be actively WRONG rather
than merely plain. Eight one-line answers from the operator settle all of them.*

## C. Missing dimensions/appearance — cosmetic placeholders, safe to build now (24)

Bunker: wall height (3.5 vs 4.0 → midpoint), deck elevation (1.0–1.5 → midpoint), wall
thickness, bunkerrol diameter/position/driven-or-idler, deck drive motor location,
exterior colour. Silos: height (18.0 m from shell-mesh measurement), diameter (3.5/4.0 m
derived), body proportions (copied from `_m_silo`), truck-lane clearance 4.5 m, discharge
mechanism type (neutral tube+valve+spout), blower pipe diameter/routing, grey tint,
ladder-vs-stair access, catwalks. Water: kleine_la 1.5×1.2×1.5 m (pending LA1's real
size), tankje dims/top style, pump appearance (generic Wilo stand-in ×2). Afzuiging: hood
shape ("kitchen-hood-like" only), duct routing/destination, SAS unit size. EOP: whole
appearance (6×3×4 m grey block + placard placeholder), site location, pipe-stub layout.
Rafter: tank dims/water level (cylinder envelope + margin).

*Consequence: visual fidelity only. Each is cited in a code comment; when a photo
surfaces, geometry is updated without touching behaviour or saves. This is the normal,
healthy state under the no-build-without-docs rule.*

## D. Unknown mechanisms — behaviour approximated conservatively (17)

- Bunker: the fixed time interval behind "mm per interval" (~36 s DERIVED from the
  600≈10-min calibration — the one number that anchors everything), default production
  speed (only the 300 pre-start fill setting is documented), auto-speed 10-setpoint table
  + Beide/Zonder-3A/Zonder-3B mode logic (display-only until documented), sensor
  type/mount.
- Afzuiging: %→drying-effect curve (linear placeholder, 55 % = nominal), the "EN
  reiniging" cleaning half of the checklist row (no separate mechanic yet), unit-2
  repairability (default: never repairable — matches reality), control location.
- Water: kleine_la modeled dead-end (no outlet documented), tankje flow direction
  (`unsure` in the flow graph), **zeefbocht screen not modeled at all** (zero
  documentation — pump only).
- Silos: per-silo tonnage/pellet bulk density (ties to open Q19 stortgewicht ≥470),
  pneumatic transfer rate (copied from voorraad_silo).

*Consequence: gameplay numbers will need a tuning pass when real values arrive; nothing
blocks building. The zeefbocht screen and the auto-speed table are the two real
functionality holes.*

## E. Integration & save-compat — handled during implementation (11)

- Bunker keeps its existing `placeable_id` (saves survive); legacy `uittrekrol` comp key
  must keep working or be migrated; LegacyPropsSpawner's bale-dump test flow retargets;
  CrewManager's phantom `bunker_3a/_3b/_1/_3c/_6` zone ids reconciled.
- I3 (macro index shift on kleine_la insertion): **moot** — no `line_3b.json` macro
  exists in the user profile (verified 2026-07-06).
- I4 (stale bunker size override): **moot** — `placeable_size_overrides.json` holds only
  `tool_scanner` + `vss_silo` (verified 2026-07-06).
- Pump id policy: distinct `pomp_c1` / `pomp_zeefbocht` ids (per the flotation_tank/_wide
  precedent) vs reusing one pump id — implementer default: distinct ids.
- Bunkers on other lines (1/3C/6) undocumented — only line 3's is being rebuilt.

*Consequence: checklist for the implementer; nothing user-facing.*

## Operator photo wishlist (would clear most of category C)

bunker exterior + doors • PCU afzuiging hood • zeefbocht screen • LA1 tank (with
something for scale) • EOP installation • outdoor silo park (truck lane + discharge +
blower piping) • tankje tussen extruders. The operator's phone-photo archive
(`F:/Citizen/Downloads/Phone Files (1)`, webp files) has not been searched for these yet.


## Rulings — operator interview 2026-07-06 (all 8 category-B conflicts RESOLVED)

- **B1 doors:** COMBINATION — barred/grated doors, each with a blurry plexiglass window
  and its own frame. Both sources were right.
- **B2 belts:** **1040 = shredder 1 → bunker** (SWI-042 correct). The long belt's number
  is still unconfirmed (operator will find documentation). CRITICAL layout fact — the
  line is a "SNAIL", not straight: feeder belt → 90° side-feed into shredder-1 funnel →
  belt 1040 at 90° → feeds the bunker TOP (bunker runs at 180° vs the initial feeder) →
  roll at bunker end → next belt at another 90° (clockwise from above) → the LONG belt at
  another 90°, running parallel to and between the initial feeder and the bunker.
  Operator explicitly requests floor plans for sorting/washing areas before line layout
  work — nothing is a straight line.
- **B3 speed:** normal band 200–800; **hard cap 1000** in the sim (real cap unknown,
  ≥1000). Below 200 is settable but causes relay trips / motor stalls (~every 15 min,
  worse the lower). Overspeed use case: bunker ran empty (feeder gap or shredder-1
  malfunction) → set 1000 to rush material to the outfeed so sorting/washing don't
  starve. NOTE an internal inconsistency to keep visible: 600 ≈ 10 min traversal
  (calibration kept) vs operator's "at 200 it takes ~15 min" (linear would give ~30 min)
  — memory approximation; calibration anchor stays 600≈10 min.
- **B4 fill:** the 100–130 cm figures are the LEVEL SETTING (default **115**), read by a
  sensor ~3 m up — and it was MISCALIBRATED: setting 100 → actual bed ~130–140 cm;
  setting 130 → actual ~170–180 cm (≈ +35–50 cm offset). Sim should reproduce the
  miscalibration (authentic operator knowledge!). "2.0 = full" and HMI "258" remain
  separate scales, unexplained.
- **B5 afzuiging:** **NOT A HOOD.** A ~30 cm diameter vent hole in the compactor's top
  centre with a fan inside behind a mesh — ONE per PCU. The % controls that fan (100% =
  too much moisture removed the wrong way, 0% = moisture stays; 55% the working point).
  The vent shaft above it is a separate building system — out of scope for now. This
  OVERRIDES afzuiging.md's hood geometry entirely.
- **B6 silo mixing:** per-line dedicated silos (only 3A pellets in a 3A silo, etc.);
  operators never interact. Mixing = a recirculation LOOP: pellets pumped BACKWARD in the
  chain (laadsilo → mengsilo) and forward again, looping continuously per pellet type.
  Model as background system: fixed chain + meng⇄laad recirculation, no player controls.
- **B7 rafter:** ~~the WATER LEVELS equalize — rafter tank water level = flotation-tank
  water level (connected vessels).~~ **CORRECTED 2026-07-17: the operator rejected the
  "connected vessels" claim — the rafter and flotation tank are SEPARATE tanks; nothing
  ties their water levels.** Rafter mesh cylinder ~75 cm diameter, encapsulated in a tank
  ~1 m wide × 1 m high; everything below the tank is support platform. Platform top
  lowered 3.1 → 1.9 m (operator: it was 1.2 m too high).
- **B8 silos:** **10**, in 2 rows of 5, per the floor plan.
