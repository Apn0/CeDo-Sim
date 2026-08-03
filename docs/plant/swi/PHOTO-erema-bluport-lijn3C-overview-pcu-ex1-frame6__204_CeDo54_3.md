# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Process overview (PCU / EX1) — frame 6

- **Source file:** `204_CeDo54 (3).pdf` (1 page, 5.4 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — process-overview / intake+extruder mimic. **Sixth frame** of the 194/195/201/202/203 sequence, 21-12-2024, clock **2:38:10** — ~18 min after the 201/202/203 cluster (2:19-2:20). Highest throughput reading of the whole 3C series.
- **SWI id:** none (HMI screenshot)
- **Scope:** LIJN 3C intake/compactor (PCU) + extruder EX1 + AIS + trend
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Same fixed content as 194/195/201/202/203
- White WAARSCHUWING sticker; yellow **"STAAT — Afzuiging compactor !!! AAN !!!"**; **LIJN 3C** plate; **BluPort EREMA** brand; recipe **"LDPE 800 kg/h 22.04.2024 IBN"**; **AutoPro-control = Uit**; trend axes left 0-600 / right 0-250.

## Left-column live values (this frame)
- Clock: **2:38:10**, date **21-12-2024**
- (gauge) **110 °C**
- (power) **229,9 kW**
- (speed) **115 rpm**  (up from 105 — operator raised EX1 speed again)
- (load %) **70 %**
- (hours) **3554 h**
- (pressure ◇1) **302 bar**  — **rendered RED** (over-alarm; was orange 289-297 earlier, now red at 302)
- (pressure ⊗1) **26 bar**
- (pressure ◇2) **206 bar**
- (throughput ⤷) **1513 kg/h**  — highest 3C reading captured

## Trend chart (this frame)
- X-axis: **2:21:29 / 2:25:39 / 2:29:49 / 2:33:59 / 2:38:08**, all **21-12-2024**
- cyan **Toevoer actief** feed pulses (dense, near-continuous first half then a gap ~2:34); orange **PCU-vermogen** ~220-250; green **PCU-temperatuur 1** flat ~250; yellow **AIS-positie** flat.

## Right mimic tiles (this frame)
- **PCU-vulpeil** = **273 cm**  (still climbing: 266→267→269→270→271→273)
- **PES-toerental** = **80 %**  (raised from 75 back to 80)
- **TEU-toerental** = **30 %**  (raised from 25 to 30)
- **PCU-temp. 1** = **110 °C**
- **PCU-belasting** = **73 %**  (up from 70-71)
- **PCU-vermogen** = **229,9 kW**
- **AIS-positie** = **70 %**
- **EX1-vermogen** = **245,8 kW**  (up from ~223-225)
- **EX1-toerental** = **115 rpm**  (up from 105)
- **EX1-belasting** = **70 %**  (up from 63)
- **EX1-IZ1** = **98 °C**  (up from 94 — feed-throat warming as rate rises)
- new blue-highlighted field next to EX1-IZ1: **236,3 kW** (editable/focused; appears to be an EX1-vermogen setpoint or a second power readout in focus) [unsure: exact tag — field is blue = editable focus]
- **BC1-toerental** = **0 %**  (infeed belt STOPPED — belt off while PCU buffer is full at 273 cm and line pulls from buffer)

## ANSWERS TO OPEN QUESTIONS
- **Q21:** LIJN 3C peaks at **1513 kg/h** here at 115 rpm — well above the "LDPE 800 kg/h" recipe nameplate (~1.9×). Confirms 3C is the plant's high-throughput LDPE line; live band across all captures ≈ **1022-1513 kg/h**. [confidence: likely]
- **Q15:** feed-end temps still cool but rising with rate: PCU 110 °C, EX1-IZ1 **98 °C** (was 93-94 at 90-105 rpm) — shows intake-zone temp tracks throughput slightly.
- **Q30:** reconfirmed (rpm for EX1, % for PES/TEU/BC1/loads, kW power, cm level, bar pressure, kg/h throughput).

## Notes for sim
- **Second ramp step**: after settling at 105 rpm (201/202/203, ~1350 kg/h) the operator pushed EX1 to **115 rpm** → EX1 power 224→245,8 kW, load 63→70 %, throughput ~1350→**1513 kg/h**, EX1-IZ1 94→98 °C, and ◇1 pressure crossed into the **RED alarm band at 302 bar**. Good "push past the sweet spot → pressure alarm" dynamic for the sim: raising extruder speed lifts melt pressure ◇1 toward/over the alarm threshold (~300 bar).
- **BC1 = 0 %** with PCU-vulpeil 273 cm shows the control logic stops the infeed belt when the compactor buffer is full — a nice interlock behaviour to model (belt gates on buffer level).
- ◇1 alarm colour ladder now confirmed: green (normal) → orange (~289-297, elevated) → **red (302, alarm)**. Use ~300 bar as the ◇1 alarm setpoint in the sim.
- Full 21-12-2024 LIJN 3C timeline (six frames):
  | time | EX1 rpm | EX1 kW | ⤷ kg/h | PCU-vulpeil cm | ◇1 bar | note |
  |------|---------|--------|--------|----------------|--------|------|
  | 1:16:44 (194) | 90  | 189,8 | 1216 | 266 | 297 orange | pre-ramp |
  | 2:18:42 (195) | 105 | 222,0 | 1321 | 267 | 290 orange | ramp to 105 |
  | 2:19:04 (202) | 105 | 224,6 | 1344 | 270 | 289 orange | settle |
  | 2:19:08 (203) | 105 | 222,6 | 1347 | 271 | 290 orange | settle |
  | 2:20:24 (201) | 105 | 224,9 | 1367 | 269 | 295 orange | settle |
  | 2:38:10 (204) | 115 | 245,8 | 1513 | 273 | **302 RED** | 2nd ramp, alarm |
- Keep 194 as canonical topology; 204 is the high-rate / alarm-threshold data point.
