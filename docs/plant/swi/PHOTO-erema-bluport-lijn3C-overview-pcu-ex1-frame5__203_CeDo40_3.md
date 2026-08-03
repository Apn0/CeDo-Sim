# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Process overview (PCU / EX1) — frame 5

- **Source file:** `203_CeDo40 (3).pdf` (1 page, 5.6 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — process-overview / intake+extruder mimic. **Fifth frame** of the 194/195/201/202 sequence, 21-12-2024, clock **2:19:08** — essentially co-temporal with 202 (2:19:04) and just before 201 (2:20:24). Sharp full-screen shot; the bottom hardware nav bezel is again partly visible.
- **SWI id:** none (HMI screenshot)
- **Scope:** LIJN 3C intake/compactor (PCU) + extruder EX1 + AIS + trend
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Same fixed content as 194/195/201/202
- White WAARSCHUWING sticker top-left; **LIJN 3C** plate; **BluPort EREMA** brand; recipe **"LDPE 800 kg/h 22.04.2024 IBN"**; **AutoPro-control = Uit**; trend legend/axes identical (left 0-600, right 0-250).
- Yellow sticker top-center: **"STAAT — Afzuiging compactor !!! AAN !!!"** ("compactor extraction is ON") — same wording as 194/195.

## Left-column live values (this frame)
- Clock: **2:19:08**, date **21-12-2024**
- (gauge) **109 °C**
- (power) **223,3 kW**
- (speed) **105 rpm**
- (load %) **63 %**
- (hours) **3553 h**
- (pressure ◇1) **290 bar**
- (pressure ⊗1) **24 bar**
- (pressure ◇2) **205 bar**
- (throughput ⤷) **1347 kg/h**

## Trend chart (this frame)
- X-axis: **2:02:27 / 2:06:37 / 2:10:47 / 2:14:57 / 2:19:06**, all **21-12-2024**
- Legend: cyan **Toevoer actief** (bottom square-wave feed pulses), orange **PCU-vermogen**, green **PCU-temperatuur 1** (~250 flat), yellow **AIS-positie** (flat).

## Right mimic tiles (this frame)
- **PCU-vulpeil** = **271 cm**  (level still creeping up: 266→267→269→270→271)
- **PES-toerental** = **75 %**
- **TEU-toerental** = **25 %**
- **PCU-temp. 1** = **109 °C**
- **PCU-belasting** = **71 %**
- **PCU-vermogen** = **223,3 kW**
- **AIS-positie** = **70 %**
- **EX1-vermogen** = **222,6 kW**
- **EX1-toerental** = **105 rpm** (editable setpoint field below highlighted blue **105 rpm**)
- **EX1-belasting** = **63 %**
- **EX1-IZ1** = **94 °C**
- **BC1-toerental** = **60 %**

## ANSWERS TO OPEN QUESTIONS
- **Q21:** 3C live **1347 kg/h** here — squarely in the 1321-1367 kg/h settling band around 105 rpm; reconfirms 3C as the high-rate LDPE line.
- **Q15:** PCU 109 °C / EX1-IZ1 94 °C stable — feed end cool, unchanged.
- **Q30:** reconfirmed unit conventions.

## Notes for sim
- Fifth data point on the 21-12-2024 ramp/settle: at 105 rpm the throughput hunts 1321→1344→1347→1367 kg/h while PCU-vulpeil climbs 266→271 cm — the compactor buffer keeps filling faster than the extruder pulls, a clean lag/buffer dynamic for the sim.
- Fully redundant topology vs 194 (canonical); this frame adds only one more settle data point + confirms PCU-vulpeil monotonic climb to 271 cm.
- Keep 194 as canonical topology digest; 195/201/202/203 are the dynamics dataset.
