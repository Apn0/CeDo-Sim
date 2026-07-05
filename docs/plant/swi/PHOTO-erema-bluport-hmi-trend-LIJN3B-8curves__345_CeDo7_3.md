# Photo — EREMA Bluport HMI trend, LIJN 3B, 8 curves, 13-05-2024

- **Source file:** `345_CeDo7 (3).pdf`
- **Type:** Plant-floor photograph of an EREMA-branded Bluport HMI trend ("Kromme") screen. Scan rotated ~90° CW, glare/scratches.
- **Line identified:** blue sticker on the panel bezel reads **"LIJN 3B"**; below it a white label **"UIT / AUTO / HAND"** (off / auto / manual selector). So this HMI drives **lijn 3B**.
- **No SWI id.**

## On-screen date/time
- Trend time axis (bottom): **18:39:33 → 19:09:33 → 19:39:33 → 20:09:33, 13/05/2024**.
- Value-column timestamps: **13/05/2024 19:29:35.140** (snapshot cursor time) [unsure on exact ms].

## Y-axis scale
Top axis ticks: **0, 50, 100, 150, 200, 250**.

## Variabelenaanbinding legend + Waarde (value) column
The 8 curves ("Kromme") with their snapshot "Waarde" values at 19:29:35 (verbatim labels; values best-read under glare):

| # | Variable (NL) | EN gloss | Waarde |
|---|---------------|----------|--------|
| 1 | doorzet (kg/h) | throughput | **488** [unsure] |
| 2 | vermogen verdichter (kW) | compactor power | **216** |
| 3 | temperatuur verdichter (°C) | compactor temp | **114** |
| 4 | toerental extruder (rpm) | extruder speed | **100** |
| 5 | belasting extruder (%) | extruder load | **75** |
| 6 | toevoer aan [unsure: "toevoer aan"] | infeed on (state) | **[unsure]** |
| 7 | massadruk voor smeltfilter 2 (bar) | melt pressure before melt-filter 2 | **176** [unsure] |
| 8 | massatemperatuur voor smeltfilter [unsure] (°C) | melt temp before melt-filter | **201** [unsure] |

*(Value column right of the legend lists Waarde | Datum/Tijd; readings above are the left "Waarde" numbers, all stamped 13/05/2024 ~19:29:35.140.)*

## Right-edge nav icons
EREMA Bluport glyphs: play/skip-to-start triangle, wave/antenna "verbinding" icon, login door, diamond/home, up-arrows, screen-return.

## Answers to open questions
- **Q9 / Q21 (line throughput):** **Lijn 3B** running at **doorzet ≈ 488 kg/h** at this snapshot (13-05-2024, 19:29). Lower than the 1082 kg/h seen on the other line photo (CeDo4) — so different lines / operating points vary widely (~500 vs ~1080 kg/h). Extruder at **100 rpm, 75 % load, compactor 216 kW / 114 °C**, pre-filter melt pressure ~176 bar, melt temp ~201 °C.
- **Q30 (units):** Same EREMA unit set confirmed for lijn 3B: doorzet kg/h, vermogen verdichter kW, temperatuur verdichter °C, toerental extruder rpm, belasting extruder %, massadruk bar, massatemperatuur °C. **belasting = %**, **toerental = rpm** (settles Q30 ambiguity: Vermogen hoofdmotor here is "vermogen verdichter" in kW; extruder Snelheid = rpm; load = %).
- **Q15 (melt zones):** melt pressure/temp measured "voor smeltfilter 2" (before melt/laser filter 2) — sensor placement upstream of the filter, consistent with laserfilter monitoring.

## Notes for sim
- Second real operating snapshot, this one explicitly tagged **LIJN 3B**: 488 kg/h, extruder 100 rpm / 75 %, compactor 216 kW / 114 °C, melt ~201 °C / 176 bar. Pair with the CeDo4 photo (~1082 kg/h) to bracket the sim's throughput range per line.
- The **UIT/AUTO/HAND** selector label confirms each EREMA line panel has a 3-position mode switch (off/auto/manual) — usable as a sim control.
