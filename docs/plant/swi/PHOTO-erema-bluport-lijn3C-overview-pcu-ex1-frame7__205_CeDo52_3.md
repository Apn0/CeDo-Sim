# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Process overview (PCU / EX1) — frame 7

- **Source file:** `205_CeDo52 (3).pdf` (1 page, 5.6 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — process-overview / intake+extruder mimic. **Seventh (final) frame** of the 194/195/201/202/203/204 sequence, 21-12-2024, clock **2:34:45** — chronologically between the 105-rpm settle cluster (2:19-2:20) and the 115-rpm peak (204 @ 2:38:10). Bottom hardware nav bezel pictograms clearly visible.
- **SWI id:** none (HMI screenshot)
- **Scope:** LIJN 3C intake/compactor (PCU) + extruder EX1 + AIS + trend + panel nav bar
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Same fixed content as the rest of the sequence
- White WAARSCHUWING sticker (full text legible: "WAARSCHUWING / GEBRUIK DEZE MACHINE NIET / ZONDER VEILIGHEIDSCONTROLE / IN POSITIE / WAARSCHUWINGSBORD NIET VERWIJDEREN OF MISVORMEN / 1 holländisch"); yellow **"STAAT — Afzuiging compactor !!! AAN !!!"**; **LIJN 3C** plate; **BluPort EREMA** brand; recipe **"LDPE 800 kg/h 22.04.2024 IBN"**; **AutoPro-control = Uit**; trend axes left 0-600 / right 0-250.

## Left-column live values (this frame)
- Clock: **2:34:45**, date **21-12-2024**
- (gauge) **110 °C**
- (power) **221,9 kW**
- (speed) **113 rpm**  (mid-ramp between 105 and 115)
- (load %) **68 %**
- (hours) **3554 h**
- (pressure ◇1) **298 bar**  — rendered **orange** (elevated, just under the 302 red seen at 204)
- (pressure ⊗1) **25 bar**
- (pressure ◇2) **202 bar**
- (throughput ⤷) **1452 kg/h**

## Trend chart (this frame)
- X-axis: **2:18:05 / 2:22:15 / 2:26:25 / 2:30:35 / 2:34:44**, all **21-12-2024**
- cyan **Toevoer actief** feed pulses (very dense/near-continuous — feed running hard to match the higher rate); orange **PCU-vermogen** ~220-250; green **PCU-temperatuur 1** flat ~250; yellow **AIS-positie** flat.

## Right mimic tiles (this frame)
- **PCU-vulpeil** = **265 cm**  (dipped from 273 — buffer drawn down as extruder pulls faster than belt refills; note BC1 back to 60% here)
- **PES-toerental** = **80 %**
- **TEU-toerental** = **30 %**
- **PCU-temp. 1** = **110 °C**
- **PCU-belasting** = **70 %**
- **PCU-vermogen** = **221,9 kW**
- **AIS-positie** = **70 %**
- **EX1-vermogen** = **242,1 kW**
- **EX1-toerental** = **113 rpm**
- **EX1-belasting** = **68 %**
- **EX1-IZ1** = **97 °C**
- **BC1-toerental** = **60 %**  (belt running again — refilling the buffer)

## Bottom navigation icon row (visible, matches 202)
Outline pictograms along the panel's physical bottom bezel, left→right:
1. **Power / standby** (circle with vertical line)
2. **Login / enter** (arrow-into-door)
3. **Process / measure** (gauge/speedometer dial)
4. **Heating / zones** (three vertical wavy heat lines ≋) — dedicated temperature-zone screen
- Confirms the same hardware nav bar as documented on 202.

## ANSWERS TO OPEN QUESTIONS
- **Q21:** LIJN 3C **1452 kg/h** at 113 rpm — mid-point of the ramp toward the 1513 kg/h peak (204). Reconfirms 3C as the high-throughput LDPE line; full live band ≈ **1022-1513 kg/h**. [confidence: likely]
- **Q15:** feed-end temps stable-rising: PCU 110 °C, EX1-IZ1 **97 °C** (94 @ 105 rpm → 97 @ 113 rpm → 98 @ 115 rpm) — clean monotonic intake-zone-temp-vs-throughput relationship for the sim.
- **Q30:** reconfirmed unit conventions.

## Notes for sim
- Fills in the ramp between 105 rpm (~1350 kg/h) and 115 rpm (1513 kg/h): at **113 rpm → 1452 kg/h**, ◇1 = 298 bar orange (just below the 302 red alarm at 204). Gives the sim a smooth ◇1-pressure-vs-EX1-speed curve: 90 rpm→297, 105 rpm→289-295, 113 rpm→298, 115 rpm→302(red). Pressure rises steeply in the last few rpm before the alarm — a good "diminishing headroom near the limit" feel.
- **PCU-vulpeil dynamics**: buffer climbed 266→273 while at 90-105 rpm, then drew DOWN to 265 here at 113 rpm as the extruder out-pulls the belt — confirms the compactor is a real buffer whose level is set by the (infeed rate − extruder draw) balance. Excellent for a buffer-level sim mechanic.
- Consolidated 21-12-2024 LIJN 3C timeline (all seven frames, chronological):
  | time | EX1 rpm | EX1 kW | ⤷ kg/h | PCU-vulpeil cm | ◇1 bar | BC1 % |
  |------|---------|--------|--------|----------------|--------|-------|
  | 1:16:44 (194) | 90  | 189,8 | 1216 | 266 | 297 orange | 12 |
  | 2:18:42 (195) | 105 | 222,0 | 1321 | 267 | 290 orange | 60 |
  | 2:19:04 (202) | 105 | 224,6 | 1344 | 270 | 289 orange | 60 |
  | 2:19:08 (203) | 105 | 222,6 | 1347 | 271 | 290 orange | 60 |
  | 2:20:24 (201) | 105 | 224,9 | 1367 | 269 | 295 orange | 60 |
  | 2:34:45 (205) | 113 | 242,1 | 1452 | 265 | 298 orange | 60 |
  | 2:38:10 (204) | 115 | 245,8 | 1513 | 273 | **302 RED** | 0 |
- Keep 194 as canonical topology; 205 is the mid-ramp / near-alarm data point + a second nav-bar confirmation.
