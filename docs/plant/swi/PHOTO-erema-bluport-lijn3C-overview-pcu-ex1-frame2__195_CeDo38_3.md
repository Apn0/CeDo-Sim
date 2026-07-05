# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Process overview (PCU / EX1) — frame 2

- **Source file:** `195_CeDo38 (3).pdf` (1 page, 5.1 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — process-overview / intake+extruder mimic. **Near-twin of `194_CeDo36`**, same day (21-12-2024), ~1 h later (2:18:42 vs 1:16:44). All layout/labels identical; only live values differ.
- **SWI id:** none (HMI screenshot)
- **Scope:** LIJN 3C intake/compactor (PCU) + extruder EX1 + AIS + trend; LDPE production
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Same fixed content as 194_CeDo36
- Yellow sticker "STAAT — Afzuiging compactor !!! AAN !!!"; white WAARSCHUWING sticker; **LIJN 3C** plate; **BluPort EREMA** brand.
- Recipe **℞ = "LDPE 800 kg/h 22.04.2024 IBN"**.
- Control box **AutoPro-control = Uit** (OFF).
- Trend legend identical: cyan **Toevoer actief**, orange **PCU-vermogen**, green **PCU-temperatuur 1**, yellow **AIS-positie**. Left axis 0-600, right axis 0-250.

## Left-column live values (this frame)
- Clock: **2:18:42**, date **21-12-2024**
- (gauge) **110 °C**  (194 was 108)
- (power) **223,8 kW**  (194 was 205,5)
- (speed) **105 rpm**  (194 was 90)
- (load %) **62 %**  (194 was 59)
- (hours) **3553 h**  (194 was 3552)
- (pressure ◇1) **290 bar** (orange)  (194 was 297)
- (pressure ⊗1) **26 bar**  (194 was 25)
- (pressure ◇2) **202 bar**  (194 was 187)
- (throughput ⤷) **1321 kg/h**  (194 was 1216)

## Trend chart (this frame)
- X-axis: **2:02:01 / 2:06:11 / 2:10:21 / 2:14:31 / 2:18:40**, all **21-12-2024**
- cyan **Toevoer actief** = denser on/off pulses (feed cycling faster); green **PCU-temperatuur 1** flat ~250; orange **PCU-vermogen** ~250 band; yellow **AIS-positie** flat (no step this hour).

## Right mimic tiles (this frame)
- **PCU-vulpeil** = **267 cm**  (194: 266)
- **PES-toerental** = **75 %**  (194: 80)
- **TEU-toerental** = **25 %**  (194: 30)
- **PCU-temp. 1** = **110 °C**  (194: 108)
- **PCU-belasting** = **71 %**  (194: 65)
- **PCU-vermogen** = **223,8 kW**  (194: 205,5)
- **AIS-positie** = **70 %**  (194: 60)
- **EX1-vermogen** = **222,0 kW**  (194: 189,8)
- **EX1-toerental** = **105 rpm** (shown twice; second field highlighted blue **105 rpm** = editable setpoint focus)  (194: 90)
- **EX1-belasting** = **62 %**  (194: 59)
- **EX1-IZ1** = **94 °C**  (194: 93)
- **BC1-toerental** = **60 %**  (194: 12)

## ANSWERS TO OPEN QUESTIONS
- **Q21 (which line ~1200 kg/h):** LIJN 3C live throughput **1321 kg/h** here (was 1216 an hour earlier). 3C runs 1200-1375 kg/h band across all captures → strengthens "3C ≈ 1200+ kg/h line". [confidence: hint]
- **Q15 (zone gradient):** intake temps again cool: EX1-IZ1 94 °C, PCU 110 °C — consistent with 194.
- **Q30:** aux drives in **%**, extruder in **rpm** — reconfirmed; EX1 setpoint field editable (blue-highlighted 105 rpm) shows operator can trim extruder speed directly.

## Notes for sim
- Operator ramped the line UP between 194 (1:16, 90 rpm / 1216 kg/h) and this frame (2:18, 105 rpm / 1321 kg/h): raised EX1 speed → EX1 power 189,8→222,0 kW, PCU load 65→71 %, throughput 1216→1321 kg/h, BC1 belt 12→60 %. Good real dynamic response curve for the sim (speed↑ → power↑, load↑, throughput↑; ◇1 pressure actually dropped 297→290 bar as feed evened out).
- Confirms EX1-toerental is a directly-adjustable setpoint (editable field) — the sim's primary throughput lever on 3C.
- Duplicate of 194's topology; no new labels. Treat 194 as the canonical topology digest, this as the "line ramp-up" dynamics data point.
