# DESIGN npc-05 — Container-leeg-keten (overflow → forklift → outdoor skip)

Status: **GOEDGEKEURD (Arno, 2026-07-20) → GEBOUWD.** O1 = één nieuwe buiten-skip
via ContainerGuide (positie = gelabelde aanname, vrij te verplaatsen); O2 =
Optie A; O3 = HUD-warning + 30 m³, vrachtwagen-wissel buiten scope. Bewijs:
`src/tests/test_npc05_container_chain.gd` — draai `tests\run_tests.bat`
(stage 10) op de operator-machine.
Backlog-bron: `docs/BACKLOG_ultracode_2026-07-19.md` § "Deferred — design decision
first". Vereiste npc-01/npc-02 (claim/release-machinerie) is geland.

---

## 1. Bewijs — waarom de keten nu dood is

| # | Vondst | Bewijs (file:line) |
|---|--------|--------------------|
| E1 | Generator scant **niet-bestaande groepen**. `_scan_overflow_containers()` zoekt `lumps_container_indoor` (r539) en `shipping_container_outdoor` (r556); geen enkele node zit in die groepen — de enige andere treffer in het repo is de comment die dat zelf toegeeft. `WasteContainer` meldt zich alléén bij `waste_container`. Gevolg: return op r543 → **`OverflowDumpTask` spawnt nooit in-game.** | `NpcAutonomyBoard.gd:537-585`, comment `:311-313`; `WasteContainer.gd:101` |
| E2 | CrewManager **staat er alleen maar bij**. `_dispatch_for_full_bin()` stuurt een vrije worker naar de volste bak > safe_fill; die staat daar `SERVICE_SECS` = 4,0 s en er wordt **niets geleegd** — de comment zegt het letterlijk ("later the forklift step would do the actual empty()"). | `CrewManager.gd:354-386`, `:27` |
| E3 | **Key-mismatch maakt E2 bovendien one-shot.** Dispatch slaat de claim op als `_handling["bin_<iid>"]` (r383-384) maar de worker krijgt sid `"waste_bin"` mee (r382); `step_brain()` geeft die sid terug (`NPC.gd:625`, return `service_station_id`) en de tick wist `_handling.erase("waste_bin")` (r292) — **de sleutel `bin_<iid>` wordt nooit gewist**. Elke bak wordt dus max. 1× per sessie "behandeld" en staat daarna eeuwig als in-behandeling. Bonus-rommel: `_relieve(_node_by_id("waste_bin"))` + vals `machine_alarm_cleared`-event met "BUF-300" (r290-294). | `CrewManager.gd:288-294, 379-384`; `NPC.gd:868-875` |
| E4 | Beleid **#198 (indoor laag houden, outdoor als fallback) is dood beleid**: `_choose_lumps_destination()` kiest alleen nog op fill uit de generieke groep `waste_container` en kent geen indoor/outdoor meer; `INDOOR_HANDOVER_TARGET`/`INDOOR_HARD_CAP` (r306-307) sturen niets outdoor. | `NpcAutonomyBoard.gd:295-348` |

Het taak-skelet zelf is gezond: `OverflowDumpTask` (5 fases, timeouts, npc-04
destination-guard, ledger via `empty()`/`add()`) hoeft **niet** op de schop
(`OverflowDumpTask.gd:17-120`).

---

## 2. Ontwerp

### D1 — Outdoor-skip-designatie op WasteContainer
- Nieuw `@export var outdoor_skip : bool = false` op `WasteContainer.gd` —
  "dit is de buiten-afvoerbak: open-top eindbestemming; forklift dumpt hier;
  de ploeg leegt hem zelf nooit."
- In `_ready()` (r100-106): bij `outdoor_skip` óók
  `add_to_group("waste_container_outdoor")`. Groep i.p.v. alleen property, zodat
  generators goedkoop kunnen scannen (bestaande stijl).
- Gedragsregels als `outdoor_skip`:
  - telt **niet** mee als indoor-kandidaat in generator én
    `_choose_lumps_destination()` (anders lus: outdoor vol → dump outdoor→outdoor);
  - triggert **geen** crew-aandacht bij `needs_emptying()` — alleen
    HUD/gauge-warning (wissel door vrachtwagen = buiten scope, zie O3);
  - `accepted_streams` leeg laten (accepteert alles), ruime `capacity_m3`
    (voorstel 30 m³).

### D2 — Generator-fix `_scan_overflow_containers()` (board r537-585)
- **Indoor-selectie:** alle `waste_container` **niet** in
  `waste_container_outdoor` met `is_full()` → één task **per volle bak**
  (nu: alleen de eerste). Dedup per bin-iid zoals nu (r572-575).
- **Outdoor-selectie:** laagste `fill_fraction()` uit `waste_container_outdoor`;
  geen outdoor in de wereld → niets emitten (zoals nu, maar met werkende groep).
- Indoor ≠ outdoor is door de groepsscheiding gegarandeerd (npc-04-regel blijft).
- Priority blijft Tier 4-band (50 + cleaning-modifier, r583-584) — conform
  `npc_rol_taak_prioriteit.md` §Tier 4, waar "overloop-containers legen"
  letterlijk staat; #223-verdringing door productie blijft dus vanzelf gelden.

### D3 — CrewManager-rework: één eigenaar per bak
- **Optie A (voorstel):** `_dispatch_for_full_bin()` + aanroep (r322-324)
  **verwijderen**. Het bord wordt de enige eigenaar van container-legen (Tier 4);
  CrewManager houdt productie/storingen (Tier 1) + pauzes. De 4-seconden-standby
  levert niets, is door E3 de facto one-shot, en twee systemen op dezelfde bak =
  dubbel-claim-arbitrage die we anders moeten bouwen én testen.
- **Optie B:** dispatch behouden als "eerste hulp" (worker markeert de bak tot de
  bord-task hem overneemt). Vereist `_handling` ↔ `_open_tasks`-arbitrage +
  E3-fix + extra regressietests. **Niet aangeraden** — complexiteit zonder
  gameplay-winst.
- E3 verdwijnt bij Optie A vanzelf (code weg); bij Optie B is de fix verplicht.

### D4 — #198-beleid weer levend (board r295-348)
`_choose_lumps_destination()`:
- outdoor-skips uitsluiten van de normale "best_open"-selectie;
- outdoor wél teruggeven als (a) alle indoor vol, of (b) handover én beste
  indoor-fill ≥ 0,5 (bestaande handover-regel r341-342 blijft de maat — de oude
  lumps-count-constants r306-307 vervallen of worden comment-historie).
Zo is outdoor weer "ultimate fallback" (regel 4 van het #198-comment) zonder de
werkende fill-logica te verbouwen.

### D5 — Test-/benchplan (headless, geen operator nodig)
1. Vul indoor `WasteContainer` tot `is_full()`, board-tick → assert: task
   geëmit, geclaimd, 5 fases doorlopen met mock-forklift
   (`benchmark_mock_container.gd`/npc-task-bench herbruiken), `empty()`-kg ==
   outdoor `add()`-kg (ledger sluitend).
2. Assert: **geen** task geëmit voor de outdoor-skip zelf; outdoor nooit als
   indoor-bron gekozen.
3. Twee volle bakken → twee tasks (E1-regressie op "alleen de eerste").
4. Optie A: CrewManager-tick + board-tick samen → exact één NPC beweegt naar de
   bak. (Optie B: extra E3-regressietest op `_handling`-lifecycle.)
5. Handover-fase: destination flipt naar outdoor conform D4.

---

## 3. Open — beslissing Arno vóór bouw

- **O1:** Welke fysieke bak(ken) in de huidige layout zijn de outdoor skip(s)?
  (`ContainerGuide.gd` spawnt per `container_id` — aanwijzen welke entries de
  vlag krijgen, of één nieuwe buiten-skip toevoegen.)
- **O2:** D3 Optie **A** of **B**?
- **O3:** Volle outdoor skip: voorlopig alleen HUD-warning + grote capacity
  (voorstel), of meteen nieuw backlog-item "vrachtwagen-wissel outdoor skip"?
