# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Smeltpomp 1 / Productie (clear frame)

- **Source file:** `193_CeDo59 (3).pdf` (1 page, 5.3 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — "Smeltpomp 1 / Productie". Clearer/complete twin of `190_CeDo63`; the mimic tiles are legible here.
- **SWI id:** none (HMI screenshot)
- **Scope:** Melt pump 1, extruder line 3C, LDPE production
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Context labels
- White safety sticker top-left: "...VEILIGHEIDSCONTROLE / IN POSITIE / ...GAAND NIET VERWIJDEREN OF MISVORMEN / 1 holländisch"
- Yellow sticker top-center: **"START — Afzuiging compactor !!! AAN !!!"** ("compactor extraction ON")
- Brand: **BluPort  EREMA**; blue plate below: **LIJN 3C**; red hamburger icon bottom-left

## Recipe header (verbatim)
- **℞ = "LDPE 800 kg/h 22.04.2024 IBN"**  (note: 800 kg/h here vs 600 kg/h on the 3C frames dated 2024-10)
- Right block: **Smeltpomp 1 / Productie**

## Left-column live values
- Clock: **2:10:10**, date **3-1-2025**
- (gauge) **115 °C**
- (power) **220,1 kW**
- (speed) **107 rpm**
- (load) **59 %**
- (hours) **3804 h**
- (pressure ◇1) **275 bar**
- (pressure ⊗1/filter) **24 bar**
- (pressure ◇2) **191 bar**
- (throughput ⤷) **1375 kg/h**

## Trend chart
- Left Y-axis **0-100** (cyan 100 / orange), right Y-axis **0-500 bar** in 50s (green/yellow)
- X-axis: **1:53:30 / 1:57:39 / 2:01:49 / 2:05:59 / 2:10:09**, all **3-1-2025**
- Legend:
  - cyan = **Smeltpomp 1 – toerental** (steady ~330 on right-axis scale = speed trace, gently rising)
  - green = **Massadruk voor smeltpomp 1** (low ~25 bar)
  - yellow = **Massadruk na smeltpomp 1** (~190 bar, steady)

## Center tile
- **Smeltpomp 1 / Smeltdichtheid = 0,748 kg/dm³** (same density as 190_CeDo63)

## Right mimic + tiles (all legible here)
- **MPU1-toerental** = **66 rpm**
- **MPU1-belasting** = **43 %**
- **MPU1-doorzet** = **1814 kg/h**
- **MPU1-Z1** = **261 °C** (zone 1)
- second temp below MPU1-Z1 = **230 °C** (likely MPU1-Z2 / a second zone or melt temp)
- **MP < MPU1** = **24 bar** (before melt pump)
- **ΔMP-MPU1** = **166 bar** (differential)
- **MP < MF2** = **191 bar** [reading "MP < MF2"; value 191 bar — matches ◇2 = 191 bar]
- Mimic: melt-pump gear body (twin gears shown) + diverter/valve piping

## ANSWERS TO OPEN QUESTIONS
- **Q15 (temp zones / why zone3=175):** Adds live 3C melt-pump zone temps: **MPU1-Z1 = 261 °C**, second = **230 °C**, melt/gauge 115 °C. (These are melt-pump/discharge zones, not the extruder-barrel zone list in FORM-008; still useful cross-check that post-filter melt runs ~230-261 °C on 3C.)
- **Q29 / Q30:** Reconfirms LIJN 3C = EREMA extruder melt-pump BluPort; power kW, speed rpm, load %, throughput kg/h, density kg/dm³, pressures bar.

## Notes for sim
- Same physical line as 190/191/192 (LIJN 3C) at different times/recipes:
  - 2024-10-09: recipe "LDPE **600** kg/h", ~1322-1326 kg/h actual
  - 2025-01-03 (this): recipe "LDPE **800** kg/h", **1375 kg/h** actual, MPU1-doorzet 1814 kg/h
  - 2025-02-17 (190_CeDo63): recipe "1-14-25 production program rke", 1022 kg/h line / 2380 kg/h MPU1
- Again two throughput numbers (line ⤷ 1375 vs MPU1-doorzet 1814 kg/h) — confirm the discrepancy pattern; MPU1-doorzet consistently reads higher than the line ⤷ figure.
- Melt density **0,748 kg/dm³** stable across frames — good constant for sim melt-mass conversion.
