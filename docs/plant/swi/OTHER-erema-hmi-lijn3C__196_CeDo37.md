# EREMA BluPort HMI screenshot — LIJN 3C (extruder line 3C)

- **Doc id:** OTHER (photo of HMI touchscreen), not a numbered SWI
- **Source file:** `196_CeDo37 (3).pdf`
- **Type:** Single photo of the EREMA BluPort operator screen on line 3C
- **Scope:** Live process values for extruder line 3C, timestamp 21-12-2024 02:17:25
- **Machine make:** EREMA — "BluPort" branded (EREMA BluPort recycling extruder). Logo "EREMA" top-right and centre; "BluPort EREMA" top-right of screen.
- **Line label:** Blue plaque under the screen reads **"LIJN 3C"**.
- **Yellow warning sticker above screen:** `STAAT / Afzuiging compactor / !!! AAN !!!` — "STATE / Compactor extraction / ON" (compactor dust extraction status indicator).
- **White safety sticker (top-left, partly cut):** `... GEBRUIK DEZE MACHINE NIET / ...ONDER VEILIGHEIDSCONTROLE / IN POSITIE / ...ARSCHUWINGSBORD NIET VERWIJDEREN OF MISVORMEN` — do not use machine without safety guard in position; do not remove/deform warning sign. "1 holländisch" small label.

## Recipe / batch header (Rx line)
`Rx  LDPE 800 kg/h  22.04.2024 IBN` — recipe = **LDPE at 800 kg/h**, dated 22-04-2024, "IBN" (Inbetriebnahme / commissioning reference).

## Left-hand vertical gauge column (with pictogram icons)
Verbatim values top→bottom:
- Clock/date: `2:17:25  21-12-2024`
- (speed/temp icon) `110 °C` and `215,1 kW`
- (screw icon) `102 rpm`, `60 %`, `3553 h` (operating hours)
- (pressure-diamond icon) `284 bar` (shown in orange/amber — elevated)
- (filter icon ⊟) `26 bar`
- (pressure-diamond icon) `203 bar`
- (output icon ⤷) `1294 kg/h`

## Central trend chart
- Time axis: `2:00:45` → `2:17:24` on 21-12-2024 (5 gridlines: 2:00:45 / 2:04:55 / 2:09:05 / 2:13:15 / 2:17:24).
- Left Y-axis 0–600 (scale 50..600). Right Y-axis 0–250 (25..250).
- Trace legend:
  - **Toevoer actief** (blue, square-wave, "feed active") — bottom band, on/off pulses ~50 level.
  - **PCU – vermogen** (red/orange, "PCU power") — ~200 level, fluctuating.
  - **PCU – temperatuur 1** (green, "PCU temperature 1") — flat ~250 (left axis) / steady near top.
  - **AIS – positie** (yellow, "AIS position") — flat ~150.

## AutoPro control box (upper right)
- `AutoPro-control` with toggle showing **`Uit`** (OFF).

## Right-side & lower data tiles (verbatim)
- `PCU-vulpeil  265 cm` — PCU fill level 265 cm.
- `PES-toerental  75 %` — PES speed 75 %.
- `TEU-toerental  25 %` — TEU speed 25 %.
- `BC1-toerental  60 %` — belt conveyor 1 speed 60 %.
- `EX1-vermogen  212,2 kW` — extruder 1 power.
- `AIS-positie  70 %` — AIS position 70 %.
- `PCU-temp. 1  110 °C`.
- `PCU-belasting  68 %` — PCU load 68 %.
- `EX1-toerental  102 rpm` (a second highlighted `102 rpm` box).
- `PCU-vermogen  215,1 kW`.
- `EX1-belasting  60 %` — extruder 1 load.
- `EX1-IZ1  93 °C` — extruder 1 intake zone 1 temp.

## Schematic (lower right)
Isometric EREMA machine graphic: inclined **BC1 conveyor belt** feeding a **PCU** (Preconditioning Unit — the cutter/compactor pre-feed hopper, shown with the triangular hopper and dot-cloud fill icon) into the **EX1 extruder** (labelled EREMA on the barrel).

## Answers to open questions found here
- **Q29 (Is "3C" the SCADA node hosting wash line 6?):** This screen is labelled "LIJN 3C" but shows an **extruder/pelletising line** (EREMA BluPort, PCU + EX1), NOT a wash line. So 3C here = an EREMA extrusion line, contradicting the guess that 3C hosts wash line 6. [partial — this is the extruder-side 3C HMI]
- **Q30 (units):**
  - `Vermogen hoofdmotor` — here EX1/PCU power is in **kW** (215,1 kW / 212,2 kW), not %/A. The 0-119 range value is likely % of a load metric; here `PCU-belasting 68 %` and `EX1-belasting 60 %` are the load-% values.
  - `Snelheid hoofdmotor` — extruder screw speed shown in **rpm** (102 rpm) AND as a separate **%** figure (60 %). So the 0-130 field is rpm; a parallel 0-100 field is %.
  - `power_CC` — compactor/PCU power in **kW** (PCU-vermogen 215,1 kW).
- **Throughput (Q9/Q21):** Recipe target **LDPE 800 kg/h**; live output **1294 kg/h** on the output line (⤷ 1294 kg/h). So line 3C ran well above the 800 kg/h recipe nameplate at this moment. Melt pressures: 284 bar (pre-filter), 26 bar (Δ filter), 203 bar (post-filter).
- **Q15 (laserfilter zones):** melt temp "PCU-temp 1 = 110 °C" is the PCU (pre-extruder) temp; extruder zone EX1-IZ1 = 93 °C (intake zone). Melt/screw temp 110 °C top gauge. (Extruder barrel zone profile not shown on this screen.)

## Notes
- "PCU" = EREMA Preconditioning Unit (the plasticising/compacting pre-feed with cutter-compactor). "EX1" = extruder 1. "AIS" = Automatic Intelligent Screen-changer / feed-slide position. "PES"/"TEU" = EREMA sub-units (feed/discharge screws). "BC1" = belt conveyor 1.
- Melt filter here is the EREMA laser-type (26 bar differential across it: 284 bar in, 203 bar out — Δ ≈ 81 bar total, filter reads 26 bar).
