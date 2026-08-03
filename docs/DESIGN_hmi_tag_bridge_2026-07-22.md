# DESIGN — HMI tag bridge: audit + recommendation (2026-07-22)

Status: **RECOMMENDATION — do NOT build the WebSocket/HTML bridge.** Blocked on
ONE operator answer (provenance of the 34 HTML screens, §7.2). Static analysis
only; the operator had the game open, so nothing here is runtime-measured except
where noted.

A proposal (from a session that had not seen this repo) suggested: Godot as the
PLC, a separate 34-screen HTML/React HMI as a dumb terminal, bridged by
WebSocket, with an invented dot-named tag database and a `TagDB` autoload
publishing from `_physics_process`.

## 1. Why not: the dumb-terminal layer it wants to create already exists

~26 rendered HMI surfaces, in-engine, today:

| Layer | What | Where |
|---|---|---|
| HmiOverlay (CanvasLayer 45) | 5 screens + 4 STORINGEN sub-tabs, modal, look-at + E on an `Hmi` placeable, PULL at 4 Hz | `HmiOverlay.gd:32,567-570`; `Hmi.gd:84-89` |
| Sub-scopes | 6 sub-scope screens from 5 scripts (542-890 lines each) | `src/scenes/hud/scopes/` |
| Extra panels | ShredderRelayPanel (own CanvasLayer 50), ExtruderZonePanel | `Hmi.gd:98-104` |
| ScadaDashboard (CanvasLayer 20) | ISA-101, always-on, PUSH-based, never talks to HmiOverlay | `ScadaDashboard.gd` |

14 HMI placeables (`PlaceableCatalog.gd:483-498`) across 12 operator-scoped
panels (`HmiScopes.gd:106-237`). A WS-bridged HTML HMI would be the **third**
display layer, and the project already has **two that never talk to each other**
— so the open question is how to reach ONE owner and FEWER surfaces, not where to
put a third.

## 2. The TagDB it wants to invent already exists, with nearly the same signature

`ScadaDashboard.set_param(key, value, nominal_low, nominal_high, label)`
(`ScadaDashboard.gd:125-137`), plus `set_text_param` (`:143`) and
`is_param_alarming` (`:161`) — a name-keyed tag store **with alarm bands**,
already called from the sim tick by a single centralised publisher:
`LineFlow._push_scada` (`LineFlow.gd:2314-2377`, throttled 0.16 s) and
`ExtruderMachine._push_extruder_params_to_scada` (0.2 s).

## 3. The real tag namespace is already on disk — and unused

`src/data/plant/line3c_scada_tags.json`: **1056 unique tags**, from the
operator's own `3c_tags.xlsx` export (extracted 2026-07-04). SLASH-hierarchical
with Dutch leaves; roots `scada/3c` (1029: info 519 / setpoints 479 /
meeting 31), `lines/3c`, `historicaldata/3c`.

**Zero code consumers** (6 doc references only). The proposal's invented
dot-names (`L3C_4L.current`, `BC1.setpoint`) would be a **fourth** private
taxonomy alongside this, HmiOverlay's internal names, and ScadaDashboard's keys —
a no-build-without-docs violation with the real answer sitting in the repo.

## 4. Two defects that make ANY bridge premature

### 4a. There is no write path (confirmed first-hand, not inherited)

```gdscript
func _on_toggle_auto() -> void:            # HmiOverlay.gd:1111-1113
    _automaat = not _automaat
    _refresh()                              # local var + redraw. That is all.

func _on_manual_toggle(section: String) -> void:   # :1115-1119
    if _automaat: return
    _manual_run[section] = not bool(_manual_run.get(section, false))
    _refresh()                              # local dict + redraw. That is all.
```

`_automaat` (6 hits) and `_manual_run` (4 hits) exist **only** inside
HmiOverlay, only for button text and lamp colour. Eleven lines above, the same
file writes `_line_flow.feed_enabled = false` — so it knows how; these controls
just do not. A WS terminal whose numpad "writes over the socket instead of
localStorage" writes into the same void. (The in-engine numpad is literally
`pass` — `ExtruderBluPortScope.gd:877-881`.)

Four of five control classes have **no endpoint at all**: per-section start/stop
(`SECTIONS` is a 6-string constant inside HmiOverlay `:155-162`; no section
concept exists in `src/sim/`), per-line addressing (one global LineFlow, one
global `feed_enabled`), non-RPM setpoints, alarm acknowledge (`KWITTEREN` mutates
a local dict, `:1121-1128`).

### 4b. Equipment is not addressable — so a tag has nothing to bind to

Every public LineFlow entry point resolves through `_find_node_by_id()`
(`LineFlow.gd:1483-1487`), which returns the **first match on a non-unique
placeable id**. `LINE_3A_SEQ` places 42 machines from 28 distinct ids
(`BuildMode.gd:85`) — blower x5, cyclone x4, transport_screw x4 — so
**instances 2..n of any repeated id are unreachable by construction: 14 of 42
machines on Line 3A cannot be commanded by ANY front end.**

Until a machine has a stable unique key, both the wire format and the screen
technology are undecidable.

### 4c. Some existing screens are fake too

`WashingScope.bind()` (`WashingScope.gd:146-151`) and `SorteerlijnScope.bind()`
(`:162-168`) have **zero callers repo-wide** — so 7 process values
(`WashingScope.gd:90-98`: 19.4 %, 32.2 RPM, -17.3 %) and 6 stage lamps are photo
literals by construction. HOOFDMENU's lamp refresh iterates `_section_tiles`,
which is never appended to — dead code; `_section_tile()` has zero callers.
Bridging this layer would hide these behind a nicer front-end.

## 5. Smaller but real defects in the proposed code

- **`TagDB.set(name, value)` shadows `Object.set(property, value)`** — arity
  matches exactly (2 args), so the collision is *silent* rather than a parse
  error; Godot 4.6 emits NATIVE_METHOD_OVERRIDE. This project runs
  warnings-as-errors and calls `.set()` on nodes dynamically throughout.
- **60 Hz unconditional broadcast from `_physics_process`** contradicts the
  project's own documented convention: `src/autoload/SimTick.gd:6-10` states
  process realism must NOT live in `_physics_process`; the sim tick is a **10 Hz**
  fixed accumulator (`:19-22,43-60`). Both existing SCADA publishers are
  deliberately throttled and say so.
- **A new `TagDB` autoload repeats a live unfixed bug class**: it would be
  autoload #21, booting before LineFlow/ScadaDashboard/HmiOverlay exist (they
  live under MainWorld). Exactly the shape of `Walkie.gd:57` reaching for
  VoiceService with no retry — which is why crew TTS is silently dead every
  launch (FULL_LOGIC_AUDIT #12).
- **No reconnect / backpressure / auth / teardown story**, and no precedent to
  copy: **zero** hits repo-wide for WebSocketPeer, TCPServer, HTTPServer,
  StreamPeerTCP, PacketPeerUDP, ENetMultiplayerPeer, MultiplayerAPI, rpc. This
  would be the project's first listening socket.
- **The "34 screens of manual work" comparison is rigged** — it prices the
  native option in full and the bridge at zero, when ~26 surfaces already exist
  in exactly the native idiom and the bridge buys zero fidelity.

## 6. What the proposal gets RIGHT (not a strawman)

- **PLC owns state, HMI is a view with no authority** — correct, matches real
  plants, and already partly true: LineFlow owns state, ScadaDashboard is a pure
  push-only sink with no Buttons at all.
- **A named tag surface is the right abstraction**, and better than what the
  current screens do (HmiOverlay walks `_line_flow._nodes` internals directly,
  `:1401-1488`).
- **The setpoint-write critique is the single most valuable idea in it.** A
  numpad that writes to localStorage — or in-engine, to `pass` — is a prop.
  Operator input must land in the process model.
- **One publish point per value, many views** is right, and the codebase agrees
  (`_push_scada` is already exactly that). The error is *per-equipment*
  publishers.
- **Separating "who computes" from "who draws" fixes a real defect it could not
  have known about**: `_automaat`, `_manual_run`, `_acked_faults`,
  `_shielded_faults`, `_leegdraaien` are all view-local process state that
  belongs to the sim.

## 7. The real deciding question

NOT "panel PC standalone vs workstation beside the sim" — that is a deployment
detail, downstream of:

1. **Is any equipment addressable?** No (§4b). There is nothing on the other end
   of a tag.
2. **What ARE the 34 HTML screens, provenance-wise?** If they came from operator
   photos/exports/specs, their **content is documentation** and should be ported
   into the `scopes/` pattern — bridge the data, never the runtime. If a session
   generated them from imagination, adopting them at all violates
   no-build-without-docs and they should be discarded, not wired.

Absent an answer to (2): **go native-port.** If a browser surface is later
genuinely wanted (a real second monitor beside the sim), the acceptable shape is
a **read-only**, snapshot-schema, on-change, rate-limited feed serialised from
the ONE existing publish point (`LineFlow.gd:2314`) — never a write channel,
never a per-equipment publisher.

Cost of this call, plainly: if the 34 screens contain real content the sim lacks,
porting it is genuinely expensive — the 5 existing scopes are 542-890 line
self-contained procedural Controls, so 34 screens is plausibly 15-25k lines of
layout work versus a bridge demo that "works" in a day. That cost is accepted
because the bridge's cheapness is entirely front-loaded: it buys **zero
fidelity** (both sides' numpads write nothing) and permanently doubles the
ownership surface.

## 8. First slice — survives either branch

**A read-only `TagMap` + a measured tag snapshot.** Pure addition: no writer, no
socket, no autoload, nothing deleted, safe while the game is open.

1. `src/sim/TagMap.gd` — the FIRST code consumer of `line3c_scada_tags.json`.
   Hand-authored, doc-cited map from a **subset** (~40-90 tags that have a real
   simulated quantity, not all 1056) to `(machine key, get_machine_info field)`,
   seeded from the spine that already agrees in code: `Line3CDef.gd:53-90`
   `L3C.<n>` == `scada/3c/info/<n>` == the `6_<n>_<dutchname>` meeting tags.
   Candidate seeds: `em/status` <- powered, `em/snelheid` <- spin x rpm_pct,
   `em/hand` <- hand_mode, `niveau/niveau` <- SiloLevelSensor.current_level_pct,
   `lines/3c/data/throughputactual` <- thru, `lines/3c/performance/targetspeed`
   <- `Line3CDef.LINE_SPEED_KG_H` (1687.0). Every entry carries its doc cite;
   anything not derivable is **absent, not guessed**.
2. A one-shot snapshot dump following the repo's existing external-tool
   convention (engine writes JSON to `user://`, external script reads the
   globalized path — as `regression_world_save.gd` -> `run.sh` ->
   `topdown_render.py` already do).

**Non-vacuous pass criteria, stated up front:** `resolved_tags > 0` AND every
resolved tag has a non-null value AND the dump reports (a)
`duplicate_id_collisions` — expected **non-zero, ~14 on Line 3A**, which
*measures* the §4b addressing defect instead of asserting it — and (b)
`live_line_amps`, which per the code path reads **0.0** and thereby proves the
`l3c_code` -> `amps_nominal=0` chain (`LineFlow.gd:467-482`, `ProcessModel.gd:38-40`,
`LineFlow.gd:1731-1734`) that the "~488 A" comment at `LineFlow.gd:1729-1730`
currently hides. **A run reporting 0 resolved tags, or 0 collisions, is a failed
run, not a pass.**

Why it survives both branches: if native wins, TagMap is how the existing screens
finally carry the operator's real tag names instead of a private taxonomy, and
the snapshot becomes a harness artifact that asserts real values (today the
harness proves geometry only). If the bridge ever wins, TagMap IS the wire format
and the snapshot IS the payload schema — the only throwaway is the file write.

Why not start with the unique-machine-key fix (more important): it touches the
live HMI write path, so measure first and give that fix a before/after number,
which is what measure-don't-assert requires.

## 9. What cannot be settled without the operator

- **Provenance of the 34 screens** — the load-bearing unknown (§7.2).
- Whether "34" is even a comparable unit: the repo has 12 scoped physical panels
  rendering ~26 surfaces, so 34 could be sub-pages, distinct panels, or a mix.
- Whether the HTML screens cover equipment the sim has **no** screen for —
  specifically the 5 empty-string stub tiles (doseren, doseren_2,
  wateronthardheid, smeltpomp_1, granulaatsysteem, `HmiOverlay.gd:354-358`) and
  the 12 reconstructed extruder back-end stages (`Line3CDef.gd:78-89`).
- **What tag names the HTML screens use.** Real slash names -> mapping work
  shrinks and they are far more valuable than the proposal implies. Invented
  dot-names -> adopting them propagates the invented namespace.
- Whether a browser surface is wanted **at all**, or whether the goal was always
  in-game panels the player walks up to (the current deliberate design:
  look-at + E, mouse released to VISIBLE at `Hmi.gd:122`). A browser HMI changes
  the game's core interaction model.
- The open 3c-vs-6 line-identity question (`line3c_scada_tags.md:8-11`) and the
  3A/3B/1 equipment-number table only the operator + the flow-diagram PDFs can
  supply.

## 10. First slice — BUILT AND MEASURED (2026-07-22)

`src/sim/TagMap.gd` (77 rows) + `src/tests/test_tag_snapshot.gd`. Wired into
`tools/regression/run.sh`. Verdict **24 ok / 0 fail / 1 skip — PASS**, confirmed
by an independent run.

### What it proves

| | Result |
|---|---|
| Export loaded | 1056 tags, first code consumer since 2026-07-04 |
| Rows mapped | 77 (**7.3 % coverage** — honest, not padded) |
| Invented tag names | **0** — every string verbatim in the export, re-verified outside Godot |
| Uncited rows | 0 — every row cites tag source AND sim source |
| Resolved | 77/77, 0 unresolved, 0 null |
| Liveness | 19/40 bools true, 31/36 numerics non-zero, 12 distinct values, 10/10 `em/snelheid` > 0 |
| Material moved | 5/8 flow rows > 0 after 1280 kg injected |

### The two defects it MEASURES rather than asserts

- **(b) `duplicate_id_collisions = 14`** (47 nodes / 33 distinct ids).
  Triangulated three ways — live world, `line_3a` subset, and a standalone
  static parse of `LINE_3A_SEQ` — all 14. Breakdown: `blower:5, cyclone:4,
  transport_screw:4, friction_sep:2, verdeelwals:2, lump_cart:2,
  lump_cart_spot:2`. **SCADA-aligned 3C units unreachable: 10 of 20.**
  NOTE: this criterion **inverts on a genuine fix** — unique machine keys make
  it 0 and the check must be REWRITTEN, not silenced. Flagged in-line.
- **(c) the calibrated amps path is dead.** `l3c_code` stamped on **0 of 47**
  nodes; `sum(amps_nominal) = 0.00 A`; `ProcessModel.line_nominal_amps()` =
  488.49 A. The only writer to `nd["amps"]` is `MotorOverload.current_amps`,
  seeded from its **placeholder 90.0 A default precisely because
  `amps_nominal` was 0**. So the "~488 A" comment at `LineFlow.gd:1729-1730`
  does not describe what the sim reports. `live_line_amps` is deliberately NOT
  fixtured: it reads 126.0 A idle but 217-259 A fed, **not run-stable**. The
  stable invariants are `stamped == 0` and `sum_amps_nominal == 0.0`.

### The vacuous-green hunt failed the first build — and that is the point

The adversarial pass broke 2 of 3 original criteria:

- `null_valued == 0` was a **tautology** — `_emit` sets `resolved := value != null`,
  so a null can never be counted resolved. It printed "0 null" with an *empty map*.
- `resolved_tags > 0` **survived `get_machine_info` being stubbed out**: 73 of 77
  rows went unresolved and the run still printed PASS.
- **No liveness criterion existed at all** — an all-zero/all-false accessor scored
  an identical PASS.
- The **flow half of the map was dead**: `linestatus` read "Running", 47 machines
  powered and spinning, **zero kg moved**. The npc-05 shape exactly.

Hardened and mutation-proven: empty map → **7 fail**, stubbed `get_machine_info`
→ **6 fail**, all-default values → **3 fail**, feed disabled → **2 fail**.

### New defects found in passing

1. **`MachineFlow.gd:381-385` misses the `_wide` id.** `flotation_tank` gets
   `water_add 0.40`; `flotation_tank_wide` — which is L3C.11's actual id
   (`Line3CDef.gd:65`) — gets **0.00** and runs the generic `convey` profile.
   The Flotatietank is not modelled as a water stage at all.
2. **`scada/3c/info/4l/em/alarm` reads FALSE during a genuine `friction_sep`
   MotorOverload trip.** The row's "PARTIAL" note is now proven, not asserted.
3. Coverage gaps documented rather than silently absent: unit 3 `intrekwals` is
   mappable and unmapped; unit 11 has **three** peddelwals groups, not one;
   unit 1 implies an unmodelled agitator (`loopbewaking roerwerk`).

### Residual risk

- `live_line_amps` not run-stable once fed — never fixture 217.73.
- `flotation_tank_wide` and `silo` receive no material even when fed (probe-row
  topology), so their rows are type-checked but not value-exercised — hence
  5 of 8, not 8 of 8.
- The 2 `em/alarm` rows and several bools read false in a healthy run; a
  constant-false stub would satisfy them. Only the trip case is covered.
- `WATERFLOW` rows read `MachineFlow.profile()` directly, not the live node —
  would diverge if `l3c_code` ever gets stamped.

### Next, in dependency order

1. **Unique machine keys** — the real blocker (§4b). 14 machines unreachable
   today; this test now gives that fix a before/after number.
2. **Stamp `l3c_code`** so the calibrated amps path goes live (it is currently
   set only in `tests/FlakeCouplingTest.gd:64`, nowhere in production).
3. **Port the 34 screens' content** into `src/scenes/hud/scopes/` — pending the
   operator supplying them (§9).
