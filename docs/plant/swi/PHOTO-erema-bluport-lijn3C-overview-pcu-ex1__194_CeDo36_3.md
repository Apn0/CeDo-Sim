# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Process overview (PCU / EX1 / trend)

- **Source file:** `194_CeDo36 (3).pdf` (1 page, 5.5 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — process-overview / mimic screen (NOT the melt-pump screen; this one shows the compactor-PCU + extruder EX1 feed section with mimic tiles). Same physical line as 190/191/192/193.
- **SWI id:** none (HMI screenshot)
- **Scope:** LIJN 3C intake/compactor (PCU) + extruder EX1 + AIS slide-in + trend; LDPE production
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Context labels
- White safety sticker top-left: "WAARSCHUWING / GEBRUIK DEZE MACHINE NIET / ...ONDER VEILIGHEIDSCONTROLE / IN POSITIE / ...WAARSCHUWINGSBORD NIET VERWIJDEREN OF MISVORMEN / 1 holländisch"
- Yellow sticker top-center: **"STAAT — Afzuiging compactor !!! AAN !!!"** ("compactor extraction is ON")
- Brand top-right: **ERE[MA]** (large); screen brand **BluPort  EREMA**
- Blue label plate below screen: **LIJN 3C**
- Bottom-left: three-bar hamburger/menu icon (grey)

## Recipe header (verbatim)
- **℞ = "LDPE 800 kg/h 22.04.2024 IBN"** (same recipe as 193_CeDo59)
- Top-right control box: **"AutoPro-control"** with state button **"Uit"** (OFF) — the AutoPro auto-control is switched off, i.e. running manual/fixed.

## Left-column live values (pictogram : value : unit)
- Clock: **1:16:44**, date **21-12-2024**
- (thermometer/gauge) **108 °C**
- (power) **205,5 kW**
- (speed) **90 rpm**
- (load %) **59 %**
- (hours) **3552 h** (running hours)
- (pressure ◇1) **297 bar**  (shown in orange/amber = elevated/alarm colour)
- (pressure ⊗1 / filter) **25 bar**
- (pressure ◇2) **187 bar**
- (throughput ⤷) **1216 kg/h**

## Trend chart (Dutch legend)
- Left Y-axis: **0…600** in 50s (0,50,100,…,600) — left scale for kW/power & temperature traces
- Right Y-axis: **0…250** in 25s (0,25,…,250) — right scale, cyan **250** / yellow **200** swatches at top; also `<25` cyan bottom swatch
- X-axis timestamps: **1:00:04 / 1:04:14 / 1:08:23 / 1:12:33 / 1:16:43**, all **21-12-2024**
- Trace legend (three series):
  - cyan (top) = **Toevoer actief** ("feed active") — square-wave toggling 0/full (on-off feed pulses at bottom of chart)
  - orange/red = **PCU-vermogen** ("PCU power") — flat ~200-250 band
  - green = **PCU-temperatuur 1** ("PCU temperature 1") — flat top trace ~250
  - yellow = **AIS-positie** ("AIS position") — steps DOWN partway through chart (slide/knife position change ~1:10)

## Right-side mimic + tiles (intake/compactor + extruder)
Mimic shows an inclined feed conveyor/chute (BC1) dropping material into the compactor bowl (PCU) which feeds the EREMA extruder (EX1). Water-drop icon cluster on the PCU cover.

- **PCU-vulpeil** ("PCU fill level") = **266 cm**
- **PES-toerental** ("PES speed" — pre-conditioning/pusher screw?) = **80 %**
- **TEU-toerental** ("TEU speed") = **30 %**
- **PCU-temp. 1** = **108 °C**
- **PCU-belasting** ("PCU load") = **65 %**
- **PCU-vermogen** ("PCU power") = **205,5 kW**
- **AIS-positie** ("AIS position" — Automatic Infeed Slide / doseerschuif) = **60 %**
- **EX1-vermogen** ("extruder 1 power") = **189,8 kW**
- **EX1-toerental** ("extruder 1 speed") = **90 rpm**
- **EX1-belasting** ("extruder 1 load") = **59 %**
- **EX1-IZ1** ("extruder 1 intake zone 1 temp") = **93 °C**
- **BC1-toerental** ("belt conveyor 1 speed") = **12 %**

## Abbreviation key (inferred from EREMA Intarema/BluPort convention)
- **PCU** = Preconditioning Unit (the compactor bowl that heats/densifies the LDPE flakes before the extruder)
- **PES** = ? (pusher/pre-feed screw speed, %)  [unsure: exact expansion]
- **TEU** = ? (take-off/degassing unit speed, %)  [unsure: exact expansion]
- **AIS** = Automatic Infeed / slide feeding material from PCU into EX1 (position %)
- **EX1** = Extruder 1
- **BC1** = Belt Conveyor 1 (infeed conveyor, speed %)
- **IZ1** = Intake Zone 1 (extruder feed-throat zone temp)

## ANSWERS TO OPEN QUESTIONS
- **Q29 / Q30:** Reconfirms LIJN 3C = EREMA BluPort. This frame proves the SAME HMI drives BOTH the melt-pump screen (190/193) AND the intake/compactor+extruder overview (this one) — it is one integrated EREMA Intarema line, not separate systems. Units: power **kW**, speed **rpm** (extruder) and **%** (aux drives PES/TEU/BC1), temps **°C**, level **cm**, throughput **kg/h**, pressure **bar**, load **%**.
- **Q15 (temp zones):** New live intake-side temps for 3C: **PCU-temp 1 = 108 °C** (compactor bowl), **EX1-IZ1 = 93 °C** (extruder intake/feed-throat zone). Confirms the feed end runs cool (~90-110 °C) vs the melt/filter end ~250-298 °C — a plausible full zone gradient for the sim (feed ~90 → compactor ~108 → melt ~250 → MPU zone ~298 °C).
- **Q21 (which line carries the 1200 kg/h budget?):** Live 3C throughput here = **1216 kg/h** at recipe "LDPE 800 kg/h". This is the closest live match yet to a "1200 kg/hr" figure — supports (but does not prove) that **LIJN 3C** is the ~1200 kg/h line. [confidence: hint]

## Notes for sim
- This is the best single reference for the LIJN 3C **process topology**: infeed belt (BC1) → compactor/preconditioning (PCU, with fill level & bowl temp) → AIS slide → extruder (EX1) → [melt filter / melt pump, on the 190/193 screen]. Good for building the 3C node graph.
- **PCU-vulpeil 266 cm** = compactor fill level; a controllable/observable buffer for the sim.
- **AutoPro-control = Uit (OFF)** captured here — operator running the line on manual setpoints.
- ◇1 = 297 bar rendered in orange = near/over an alarm threshold (alarm pictogram context) — same 297 bar seen on 190_CeDo63; likely the pre-filter melt pressure alarm band.
- Aux-drive speeds are in **% not rpm** (PES 80%, TEU 30%, BC1 12%) whereas the main extruder EX1 is in **rpm** (90) — mixed unit convention for the sim UI.
