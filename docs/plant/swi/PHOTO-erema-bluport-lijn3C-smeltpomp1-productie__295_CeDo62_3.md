# PHOTO — EREMA BluPort HMI, LIJN 3C, "Smeltpomp 1" (melt pump) production screen

- **Source file:** `295_CeDo62 (3).pdf` (1 page, photo of physical HMI touchscreen)
- **Type:** Photograph of EREMA BluPort melt-pump (Smeltpomp 1 / MPU1) production screen with trend + mimic
- **Line:** LIJN 3C (blue engraved plate below screen)
- **Recipe banner (top center):** `℞ 1-14-25 production program rke` — recipe "1-14-25 production program rke" (rke = initials/operator tag)
- **Screen timestamp:** `20:28:30  7-2-2025`
- **Brand:** BluPort / EREMA (top-right)

## Left-hand live value column (pictogram → value → unit)
| Pictogram | Value | Unit | Gloss |
|---|---|---|---|
| thermometer | **116** | °C | melt/temperature |
| power ◎ | **255,6** | kW | hoofdmotor power |
| screw ~~~ | **140** | rpm | extruder screw speed |
| % | **67** | % | screw load/speed % |
| clock | **4437** | h | running hours |
| ◇ | **252** | bar | pressure (pre-filter melt) |
| ▣ | **26** | bar | pressure |
| ◇ | **184** | bar | pressure |
| output ⤒ | **1261** | kg/h | throughput/output |

## Trend graph (bottom-left)
- Left Y-axis: 0 … 100 (marks 50, 100). Right Y-axis: 0 … 500 (marks 50 … 500).
- X-axis (time): `20:11:50 7-2-2025` → `20:16:00` → `20:20:10` → `20:24:19` → `20:28:29 7-2-2025`.
- Three trend lines with legend below:
  - **cyan** = `Smeltpomp 1 - toerental` (melt pump 1 speed/rpm) — upper noisy band ~250-320 on right scale
  - **yellow** = `Massadruk na smeltpomp 1` (melt pressure AFTER melt pump 1) — mid band ~150-200
  - **green** = `Massadruk voor smeltpomp 1` (melt pressure BEFORE melt pump 1) — low band near 0-50

## Right-hand mimic (Smeltpomp 1 / Productie)
- Header boxes: `Smeltpomp 1` / `Productie` (production).
- Gear-pump graphic (two intermeshing gears) with drive motor on top.
- **`MPU1-toerental`** (melt pump unit 1 speed): **56 rpm**
- **`MPU1-belasting`** (MPU1 load): **43 %**
- **`MPU1-doorzet`** (MPU1 throughput): **1329 kg/h**
- **`MPU1-Z1`** (MPU1 zone 1 temp): **251 °C**
- Bottom mimic pressure boxes:
  - **`MP - MPU1`** (melt pressure at MPU1 inlet): **26 bar**
  - **`ΔMP-MPU1`** (differential melt pressure across MPU1): **159 bar**
  - **`MP - MF2`** (melt pressure at melt filter 2 / MF2): **184 bar**

## Center-bottom box (Smeltpomp 1)
- **`Smeltdichtheid`** (melt density): **0,700 kg/dm³**

## Physical panel labels
- **Top-center yellow placard:** `STAAT / Afzuiging compactor / !!! AAN !!!` (State: compactor extraction ON).
- **Top-left placard (partly cut):** `...ER VEILIGHEIDSCONTROLE IN POSITIE / ...INGSBORD NIET VERWIJDEREN OF MISVORMEN — 1 holländisch`.
- **Blue engraved plate:** `LIJN 3C`.
- **Bottom pushbutton row (icons):** ⏻ power · ⤵ infeed · ◎ screw/rotation · ♨~~~ heating.

## Answers to open questions
- **Q15 (laserfilter / melt filter):** This screen exposes the **melt-pump + melt-filter train** on 3C: melt pump MPU1 sits between the extruder and **MF2** (melt filter 2). Pressures: **MP-MPU1 = 26 bar** (inlet), **ΔMP-MPU1 = 159 bar** (pump builds ~159 bar across itself), **MP-MF2 = 184 bar** (pressure at melt filter 2). MPU1-Z1 melt temp **251 °C**. So the laserfilter/melt-filter runs downstream of a gear melt pump; pump discharge feeds the filter at ~184 bar. Trend distinguishes **Massadruk voor** vs **na smeltpomp 1** (before/after the pump) — a discrete pressure jump across the pump. Good sim model: extruder → melt pump (builds pressure) → melt filter.
- **Q30 (units):** Melt pump toerental in **rpm** (56); belasting in **%** (43); doorzet in **kg/h** (1329); pressures in **bar**; melt density **Smeltdichtheid in kg/dm³** (0,700). Extruder side: 255,6 kW / 67 % / 140 rpm / output 1261 kg/h.
- **Q9/Q21 (throughput):** Live extruder output **1261 kg/h**, melt-pump doorzet **1329 kg/h** (pump slightly ahead of extruder readout). Consistent with 3C running ~1200-1400 kg/h.
- **Note:** `Smeltdichtheid 0,700 kg/dm³` is a concrete melt-density constant usable to convert volumetric pump throughput ↔ mass flow in a sim.

## Notes for sim
- Melt-pump object model: toerental (rpm), belasting (%), doorzet (kg/h), zone temp Z1 (°C), inlet pressure (MP-MPU1), differential (ΔMP), outlet-to-filter pressure (MP-MF2). Melt density 0,700 kg/dm³.
- Confirms a **second melt filter "MF2"** exists on 3C (numbering implies MF1 upstream), plus the gear melt pump between extruder and filter.
