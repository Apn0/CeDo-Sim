# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Process overview (PCU / EX1) — frame 4 + nav bar

- **Source file:** `202_CeDo39 (3).pdf` (1 page, 5.5 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — process-overview / intake+extruder mimic. **Fourth frame** of the 194/195/201 sequence, 21-12-2024, clock **2:19:04** (between 195=2:18:42 and 201=2:20:24). Notable extra: the **bottom navigation icon row** of the panel is visible in this shot.
- **SWI id:** none (HMI screenshot)
- **Scope:** LIJN 3C intake/compactor (PCU) + extruder EX1 + AIS + trend + panel nav bar
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Same fixed content as 194/195/201
- Stickers, **LIJN 3C** plate, **BluPort EREMA** brand, recipe **"LDPE 800 kg/h 22.04.2024 IBN"**, **AutoPro-control = Uit**, same trend legend & axes (0-600 left, 0-250 right).

## Left-column live values (this frame)
- Clock: **2:19:04**, date **21-12-2024**
- (gauge) **110 °C**
- (power) **223,4 kW**
- (speed) **105 rpm**
- (load %) **63 %**
- (hours) **3553 h**
- (pressure ◇1) **289 bar**
- (pressure ⊗1) **26 bar**
- (pressure ◇2) **206 bar**
- (throughput ⤷) **1344 kg/h**

## Trend chart (this frame)
- X-axis: **2:02:23 / 2:06:33 / 2:10:43 / 2:14:53 / 2:19:02**, all **21-12-2024**

## Right mimic tiles (this frame)
- **PCU-vulpeil** = **270 cm**  (level still climbing: 266→267→269→270)
- **PES-toerental** = **75 %**
- **TEU-toerental** = **25 %**
- **PCU-temp. 1** = **110 °C**
- **PCU-belasting** = **71 %**
- **PCU-vermogen** = **223,4 kW**
- **AIS-positie** = **70 %**
- **EX1-vermogen** = **224,6 kW**
- **EX1-toerental** = **105 rpm** (with editable setpoint field highlighted blue **105 rpm** below)
- **EX1-belasting** = **63 %**
- **EX1-IZ1** = **94 °C**
- **BC1-toerental** = **60 %**

## Bottom navigation icon row (NEW — visible in this frame)
Six outline pictograms along the panel's physical bottom bezel, left→right:
1. **Power / standby** (circle with vertical line)  — [outline button]
2. **Login / enter** (arrow-into-door)  — user login
3. **(unclear)** faint icon
4. **Process / measure** (gauge/speedometer dial)
5. **Heating / zones** (three vertical wavy heat lines ≋)  — temperature-zone screen
6. (row continues off-frame right)
- Also a yellow icon far bottom-left corner (partly cut).
- On-screen red 3-bar hamburger menu icon still at bottom-left of the display.

## ANSWERS TO OPEN QUESTIONS
- **Q21:** 3C throughput **1344 kg/h** here — fits the 1216→1367 kg/h ramp band. Reconfirms 3C as the high-rate LDPE line.
- **Q15:** PCU 110 °C / EX1-IZ1 94 °C stable; the **≋ heat-zone nav icon** confirms the panel has a dedicated temperature-zones screen (not captured in these photos) — the source for the full extruder zone list the sim wants.
- **Q30:** reconfirmed.

## Notes for sim
- Adds a 4th point to the 21-12-2024 ramp (2:19:04, 1344 kg/h) between 195 and 201 — line hunting slightly (1321→1344→1367) around 105 rpm.
- The **hardware nav bar** (power, login, gauge/process, ≋ heat-zones) is useful for replicating the physical EREMA panel chrome in the sim UI. A dedicated temperature-zone screen exists behind the ≋ icon — flag as a doc still to obtain (would answer Q15 fully).
- Redundant readings vs 194/201; keep 194 as canonical topology, this frame contributes only the nav-bar pictograms + one more ramp data point.
