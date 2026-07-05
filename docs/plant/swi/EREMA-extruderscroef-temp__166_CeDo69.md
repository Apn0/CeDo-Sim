# EREMA Extruderschroef & Temperatuurprofiel — reference sheet (INTAREMA / TVEplus)

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/166_CeDo69.pdf` (1 page)
**Doc type:** Not a SWI. An EREMA reference/instruction page (screw-speed recommendation chart + extruder temperature-profile example). Carries machine specs — extracted exhaustively. Watermarked "VSU" / "Voor" (draft/internal).

> NOTE ON FILENAME COLLISION: an earlier batch digested `013_CeDo69` as `SWI-040-p3__013_CeDo69.md` (Lindner shredder page). This `166_CeDo69.pdf` is a **completely different document** (EREMA extruder reference) that happens to share the "CeDo69" plant scan number. Not a duplicate.

## Section 1 — "Extruderschroef (aanbevolen snelheidsinstelling)"
> *Extruder screw (recommended speed setting)*

Dutch caption verbatim:
> "Aanbevolen snelheidsbereik van de extruderschroef afhankelijk van de grootte van de extruder en het polymeer."
> *(Recommended speed range of the extruder screw depending on the size of the extruder and the polymer.)*

**Embedded chart** — titled **"Screw Speed INTAREMA 906 to 2021"**:
- X-axis: extruder model/size index, ticks visible ~40, 60, 80, 100, 120, 140, 160, 180, 200, 220 (corresponds to INTAREMA sizes 906 → 2021 across the range).
- Y-axis: **Screw speed [rpm]**, log-like scale ~40 up to ~500+ (top tick ~"100" label partially legible; curves descend from ~500 rpm at small sizes down toward ~40-60 rpm at largest).
- Multiple descending curves, one per polymer family. Legend swatches on the left edge (verbatim, [unsure] where noted):
  - **"PP, PS"** [unsure] — top curve (highest allowable rpm)
  - **"LD, LLDPE, PA, PC"** [unsure]
  - **"HDPE, ABS, PET"** [unsure] — lower curves
- Annotation boxes on the chart (verbatim / best reading):
  - **"75 Hz Maximum Speed"** (upper region)
  - **"50 Hz maximum Torque"** (mid-left)
  - **"50 Hz Maximum Screw Speed (without booster)"** (lower-left) [unsure wording]
  - Right-side note box [unsure, best reading]: "For medium extruders a 'reduced' operation with higher speed can be used for [soft?] PE — to increase the extruder output the screw speed should be adjusted according to this chart."
- **Takeaway:** screw rpm is inversely related to extruder size; small INTAREMA runs high rpm, large runs low rpm. PE grades (LDPE/LLDPE — the CeDo feed) sit in the middle band. Frequency ceilings: **75 Hz = max speed**, **50 Hz = max torque / max screw speed without booster**.

## Section 2 — "Extruder – temperatuurprofiel"
> *Extruder – temperature profile*

Verbatim text:
> "Nuttige info in de Bluport onder polymeer assistent"
> *(Useful info in the Bluport under polymer assistant.)*
> URL: **https://bluport.erema.at/home**  (EREMA Bluport / "polymeer assistent" = polymer assistant tool)
> "Voorbeeld – LDPE bedrukte folie op een TVEplus:"
> *(Example – LDPE printed film on a TVEplus:)*

**Embedded screenshot** of the Bluport "Temperature query" tool. Left query panel:
- Process: **MFI > t** [unsure]
- **Print:** option **"printed"** selected (vs "blank") — i.e. this profile is for **bedrukte/printed** LDPE film.
- **Plant Types:** T / TF / **TVEplus** (TVEplus selected) — confirms CeDo example machine class = **TVEplus** extruder.

Right **TEMPERATURE** result column — profile zones (top → bottom) with the temperature values shown along the curled right edge of the scan (partially cut off, best reading):
| Zone (EREMA nomenclature) | Temperature [°C] (best reading) |
|---|---|
| **PCU** (feed/intake power control unit) | [unsure — top value ~"100–1.. °C"] |
| **Intake section** | [unsure ~"8.. °C" / low] |
| **TVEplus Extruder — Before melt filter** | **230 °C to 250 °C** [best reading of "230 °C to 250 °C"] |
| **TVEplus Extruder — After melt filter** | **180 °C to 220 °C** [best reading "180 °C to 220 °C"] |
| **Melt filter and pelletising** | **230 °C to 250 °C** [best reading] |

(The right-edge temperature stack reads, top-to-bottom, approx: "100 … °C", "8.. °C", "230 °C to 250 °C", "180 °C to 220 °C", "230 °C to 250 °C" — several partially obscured by page curl; marked [unsure].)

## Notes / open-question hits
- **Q15 (extruder temperature zones, before vs after laserfilter, why a low zone):** STRONG hit. EREMA's own TVEplus reference divides the profile into **"Before melt filter"** and **"After melt filter"** stages. The **After-melt-filter zone runs COOLER (180–220 °C) than Before-melt-filter (230–250 °C)** — this is the canonical explanation for the sim's low middle zone (the ~175 °C zone 3 the question asks about): melt is deliberately cooled after filtration before/around pelletising to control viscosity and avoid degradation. "Melt filter" here = the laserfilter/melt-filter position; pelletising zone climbs back to 230–250 °C. So zone ordering: hot to build melt → filter → cool → (re-heat at die/pelletiser).
- **Q33 / extruder specifics:** the CeDo machine class is confirmed as EREMA **TVEplus** (Two-stage Venting Extruder plus / TVEplus counter-current melt filter design), fed by an **INTAREMA** front end (cutter-compactor + single screw). Screw-speed governed by the "INTAREMA 906 to 2021" size chart.
- **Machine spec / Q15 tooling:** melt-filter position confirmed as a discrete stage between two temperature regimes — consistent with the plant's **laserfilter** (rotary-disc melt filter) sitting mid-extruder.
- **Frequency limits (machine spec):** 75 Hz max speed; 50 Hz max torque / max screw speed without booster — useful for sim main-motor speed/vermogen modelling (relates to Q30 Vermogen/Snelheid hoofdmotor units — EREMA governs these in Hz/rpm).
- Bluport polymer-assistant URL recorded for provenance: https://bluport.erema.at/home
