# Operator rulings — 2026-08-30

Statements made by the operator about the reference video `VID-20250912-WA0010.mp4`. These SUPERSEDE
earlier notes where they conflict. Recorded because project rule 1 requires an operator statement in
`docs/plant/` before code may contradict an earlier reading — and because the first write-up of this
video went into `assets/reference_photos/MAPPING.md`, which is **gitignored** (`CLAUDE.md:238`) and
therefore not durable. Everything below is the committed copy.

Source video: `assets/reference_photos/machines/VID-20250912-WA0010.mp4` (11.2 s, 472×850, with
audio; shot 2025-09-12, moved into the repo 2026-08-30). Sibling of `VID-20250912-WA0011.mp4`, the
walkthrough that fed `assets/audio/clips/`.

---

## 1. The video is EXTRUDER LINE 6 during a wet-PCU start — NOT a laserfilter purge — RECORDED, not built

> "it is extruder line 6. also it is during severe failure, full reject pellets, slow running
> situation, gassy pellets due to compromised vacuum units. Cause in this instance: Line Engineer
> started the extruder with high water contents in the PCU mixed with the film, instead of waiting
> for it to be evaporated; the extruder was started and lots of water entered the extruder screw
> where it moved along the screw; causing the issues"

**The failure chain, as ruled:**

`wet film left in the PCU` → `engineer starts the extruder anyway instead of waiting for evaporation`
→ `water carried down the extruder screw` → `vacuum units compromised` → `gassy pellets` +
`slow running` → `full reject`.

**CORRECTION 2026-08-30 of the first reading.** This video was initially written up as a routine
laserfilter / melt-filter purge, with the observation that the discharge was missing its lump cart.
That reading is wrong and must not be reused: the event is a severe failure on line 6, and the
material on the floor is a symptom, not a maintenance operation. The earlier reading is left on the
record here rather than deleted, per the `operator_issues_2026-07-20.md` convention.

**Measured from the footage** (frame extraction at 2 fps):

- Laserfilter disc mounted on top of the extruder barrel, face heavily fouled, one dark strand
  hanging down over the barrel cladding.
- **Two** angled discharge chutes side by side, both ejecting thick **ropey** grey-olive material
  simultaneously — ropes, not pellets, not discrete lumps.
- The material runs down the side of a beige floor-standing cabinet and piles on the concrete. The
  blue wheeled cart sits well to the **left**, under the disc, **not** under the chutes. Solidified
  crumbs cover several metres of floor.
- Continuous white plume for the full 11 s.
- Above the extruder: two cone-bottom vessels on a steel platform, the left one carrying the **EREMA
  wave logo** (the cutter-compactor / PCU), stainless risers to the roof.
- The operator stands calmly at the HMI throughout. Degraded running, not an evacuation.

**Measured from colour and audio, supporting "water" over "burning polymer":**

- Sampled across the clip, in the frames where the plume fills the sample window it measures
  near-neutral white at **1.4–4 % saturation** (e.g. RGB 147,149,146). Degrading polymer fumes skew
  blue-grey or yellow-brown; colourless white at that saturation is water vapour.
- Audio is broadband hiss with **no tonal or rotational harmonics** — a continuous gas/steam escape,
  not machinery. A human voice appears at ~8.5–11 s.

*(Method note: the colour and audio figures are measured from the file; the identification of the
machines in frame is inferred from the footage and settled by the operator ruling above.)*

---

## 2. EREMA already documents this exact chain as the "sauna effect" — the SWI corpus was not consulted when the video was first read

The operator's account is not new information to this repo. It is EREMA's own documented failure
mode, already transcribed into `docs/plant/swi/`, and it was missed because the first search covered
only `docs/plant/*.md` and not the SWI corpus beneath it.

- `docs/plant/swi/EREMA-air-flush-module__175_CeDo58.md:10` — *"Repeated evaporation and condensation
  results in negative **sauna effect**"*.
- Same file `:20` — without the Air Flush Module: **"excess compactor motor load, extra energy cost,
  steam entering the extruder, pellet-quality problems, more maintenance."** That is the operator's
  symptom list, written by the machine builder.
- Same file `:21` — already carries the sim linkage in prose:
  **"infeed moisture ↑ ⇒ compactor motor load ↑ ⇒ throughput ↓ / pellet quality ↓"**, and names it a
  *"concrete cause of poor running / high motor load / pellet-quality drop"*.
- `docs/plant/swi/EREMA-geforceerde-voeding__180_CeDo57.md:32` — the quantitative basis: **~0.72 kWh
  per litre to evaporate water (~1 kWh/l including condensation losses), and 1 litre of water flashes
  to 1673 litres of steam.** This is the number that explains the plume.
- `docs/plant/swi/EREMA-compactor-waterinjectie__177_CeDo60.md:23` — compactor water injection is a
  *noodvoorziening* only; over-injecting **worsens** the sauna effect.

**What the operator's ruling adds that the SWIs do not have:** the human decision. No EREMA document
says "the engineer started before the water had evaporated". The SWIs describe the physics; this
ruling supplies the operator error that triggers it, which is what makes it a *game* mechanic rather
than a datasheet.

---

## 3. The sim has BOTH ENDS of this chain built and the MIDDLE LINK missing — two dead setters — RECORDED, not built

This is the actionable finding. Verified by direct grep of `src/` on 2026-08-30.

**The PCU end exists.** `src/sim/CutterCompactor.gd:179` —
`var feed_moisture_pct : float = 4.0  # % water by mass in incoming flake (4 % typical, 12 % wet)`;
`:180` `MOISTURE_KW_PER_PCT = 2.5`; `:181` `MOISTURE_DRY_BASELINE = 4.0`; consumed at `:483` to add
motor kW. The header comment claims it is *"Set by the upstream dewatering screw each tick."*

**The extruder end exists, and it is a full degassing physics model.**
`src/sim/ExtruderModel.gd:240` `volatile_load_g_per_kg : float = 4.0`; `:745` converts it to a
per-tick gas mass; per-stage `PRIMARY_DEGAS` / `SECONDARY_DEGAS` extraction against
`primary_suction_pct` / `secondary_suction_pct`; `:184`
`VACUUM_FLOOD_CHOKED_CAPACITY_SCALE = 0.30` chokes every degas stage to 30 % once
`flooded_dismantle_required` trips (`:804`, cleared at `:881`); residual gas surviving to the die
becomes `residual_volatile_g_per_kg`, which drives `pellet_defect_rate` between
`:131 DEFECT_RESIDUAL_OK_G_PER_KG = 1.5` and `:132 DEFECT_RESIDUAL_SCRAP_G_PER_KG = 12.0`, where the
code's own comment for the top of the range reads *"the pellet stream is unusable"*. There is even a
dedicated `VACUUM_ALARM` state (`:95`).

So **"gassy pellets due to compromised vacuum units" and "full reject" are already implemented.**

**The middle link is missing. Both setters are defined and called by nothing:**

| Setter | Defined | Callers in `src/` |
|---|---|---|
| `set_feed_moisture_pct()` | `src/sim/CutterCompactor.gd:319` | **0** |
| `set_volatile_load()` | `src/sim/ExtruderModel.gd:700` | **0** |

`feed_moisture_pct` therefore sits at its default `4.0`, which is exactly `MOISTURE_DRY_BASELINE`, so
the moisture penalty is **structurally always zero**. `volatile_load_g_per_kg` sits at `4.0`
("clean LDPE feed") forever, so residual gas never approaches the 12.0 scrap threshold and
`pellet_defect_rate` can never rise on its own. Moisture never leaves the PCU and never becomes gas
in the barrel.

**`pellet_defect_rate` is a gauge, not a material path.** Its only consumer outside the model is
`src/scenes/machines/ExtruderMachine.gd:396-399`, which pushes it to SCADA as a percentage with an
alarm band (`0..2 %` OK). No material is diverted to a reject stream anywhere.

**Recommendation (needs operator approval before building):** wire the two setters — dewatering /
drying stage → `set_feed_moisture_pct()` → PCU evaporation over residence time → carry-over →
`set_volatile_load()` at start. That single link turns this video into a playable failure, and it is
the smallest change with the largest reach in the extruder model.

---

## 4. "Slow running" is documented in full and modelled nowhere — RECORDED, not built

- `docs/plant/slow_running.md:7` carries the plant's own footer: **"Budget snelheid is 1200 kg/hr"**,
  with the stilstand-vs-slow-running decision rule and five printed causes. A machine-readable twin
  exists at `src/data/plant/troubleshooting_slow_running.json`. Neither file is loaded by any `.gd`.
- Executable references to slow running in `src/`: **zero.** The only hit for
  `slow_running|slowrunning|langzaam` in any `.gd` is a comment at `src/sim/TagMap.gd:71`.
- `ExtruderModel.State` (`:95`) has nine members and none is degraded or rate-limited:
  `OFF, IDLE, STARTING, RUNNING, STOPPING, VACUUM_ALARM, FAULT, EMERGENCY_STOP, PREHEAT`.
- Throughput cannot fall. `src/sim/ExtruderModel.gd:465-467` is a pure ramp of `runtime_s` toward
  `config.nominal_kg_per_h`; once the 180 s ramp completes it is pinned. Nothing upstream, no feed
  shortage, no filter pressure and no material property can lower it. The only continuous derate is
  pelletizer knife wear, which needs 80 real running-hours and is unreachable in a shift.
- The sim's nominal is `src/sim/ExtruderConfig.gd:16` **950 kg/h** against the documented **1200
  kg/h** budget, so a perfectly healthy sim extruder is permanently ~21 % under budget — and nothing
  measures it, because no budget value exists in the runtime to compare against.

**Smallest useful change:** add a budget figure to `ExtruderConfig` and a running comparison, so the
shortfall becomes observable at all. Without it "slow running" cannot be raised, cleared, timed or
scored.

---

## 5. Line 6 does not exist in the sim — BLOCKED ON DOCS

The docs know line 6 well (≈15 SWI/photo digests transcribe the LIJN 6 EREMA BluPort panel, with a
throughput band of 923–1186 kg/h), and `docs/plant/README.md:124-127` settles that **3C and 6 are two
separate EREMA regranulation lines.** The code knows almost nothing:

- No `line_6` macro. `src/autoload/LineMacroStore.gd:70-74` lists seven ids and none is line 6; the
  shared `LINE_3C6_SEQ` front-end is four machines that stop at the trilzeef.
- `extruder_6` exists in the catalog (`src/build/PlaceableCatalog.gd:156`) but is placed by **zero**
  macros — `grep -c extruder_6 src/build/BuildMode.gd` returns `0`. It is a build-menu prop.
- No per-line calibration. `src/data/machines/` contains exactly one file, `Extruder3B.tres`, so
  line 6 silently runs 3B's numbers (`nominal_kg_per_h = 950`), not its documented 923–1186 band.
- **There is no `lijn_6_flow.md`.** Per rule 1 (docs are primary, photos illustrate) a line-6 tail
  must not be built until that doc exists. This video is currently the only line-6 extruder-tail
  evidence in the tree.

**CORRECTION 2026-08-31 — the "Britas vs disc" contradiction was misstated above and in the
`photo_audit.md` rows.** The first version of this ruling claimed the doc and the video contradict
each other and that "one of the two is wrong". That is not so, and the claim must not be acted on:

- `extruder_line_layout.md:34` is a table whose column is **"Final filter (step 7)"** — the
  head-filter position at the die. It says line 6 has a Britas *instead of head filters*. It makes no
  claim about the laserfilter, which is a separate earlier step in the same doc (`:36-40`). A rotary
  disc upstream and a Britas at the die are **not** mutually exclusive.

**The real contradiction is internal to the repo**, between two docs describing the same machine:

| Source | Says line 6's Britas is |
|---|---|
| `docs/plant/extruder_line_layout.md:127` | "Britas/**ABMF band filter**" |
| `docs/plant/misc_sources.md:114` | "Britas **rotary** melt filter + melt pump" |

**It is already settled by photo evidence neither line cites.**
`docs/plant/hmi_screen_inventory_2026-07-28.md:149` transcribes the real BRITAS panel from
`assets/reference_photos/hmi/PXL_20250220_020309380.jpg`: **"BRITAS ABMF (Automatischer Bandfilter /
automatic screen-belt melt filter)"**, with the fields `Zeefband - toevoer`, `Uitgevoerde
zeefwissels 14760` and `Verbruikte zeefband 9645,000 m`. A filter medium consumed in **metres** is a
belt. **`misc_sources.md:114`'s "rotary" is the error and should be corrected there.**

**Root cause of the confusion.** `misc_sources.md:140-141` describes the line-**3B** photo
`laser_filter_3B.jpg` as a "Britas-style rotary disc melt filter" and reasons that "3B's device here
is visually the same disc-filter family" as line 6's Britas. That collapsed two genuinely different
machines into one name. The warning was already on the record and unacted:
`hmi_screen_inventory_2026-07-28.md:151` — *"check whether it models BRITAS or the EREMA laserfilter,
they are DIFFERENT machines."*

---

## 6. Open questions for the operator

1. **ANSWERED 2026-08-31 — YES, both. See `operator_rulings_2026-08-31.md` §1.** ~~Does line 6 run BOTH?~~ The evidence is consistent with an EREMA **laserfilter** (the rotary
   disc in the video, with its twin afvoerschroeven) sitting upstream of a **BRITAS ABMF band
   filter** at the die in place of a head filter. Is that the real line-6 layout — laserfilter *and*
   Britas — or only one of the two? (Superseded the earlier, wrongly-framed "Britas vs disc"
   question; see the CORRECTION in §5.)
2. **What the two chutes are.** Is that the laserfilter discharging its contaminant, or the line
   dumping melt to reject because nothing is worth pelletizing?
3. **Where the plume comes from.** Off the discharging melt as it hits air, or venting back out of
   the vacuum / degassing section because the vacuum is compromised?
4. **Whether line 6 has an Air Flush Module.** `175_CeDo58` presents it as the EREMA remedy for
   exactly this. If line 6 has none, that is a standing vulnerability worth modelling.
