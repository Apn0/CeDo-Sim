# EREMA BluPort SCADA screen — LIJN 6 (photo)

- **Source file:** `226_CeDo68 (3).pdf`
- **Doc type:** OTHER — operator photo of HMI/SCADA panel (not a SWI)
- **swi_id:** OTHER:PHOTO-scada
- **Line:** 6 (labelled "LIJN 6" on plate beneath screen)
- **Machine make/type:** EREMA — **BluPort** system, screen header "BluPort ERE[MA]"
- **Screen / node:** "Smeltfilter 1 - laserfilter" (melt filter 1 — laser filter)
- **Timestamp on screen:** 2:40:19, 12-3-2025
- **Pages:** 1

## Photo description
Close-up photo of the EREMA BluPort touchscreen HMI on wash/extrusion **Lijn 6**. Above the screen are two taped-on notices; the top-right yellow label reads "Afzuiging compactor !!! AAN !!!" (compactor extraction MUST be ON). A partial white notice top-left reads "3 rpm minimum / 8 rpm maximum / Mochten er settings gewijzigd worden communiceer dit met shiftleader en mail naar CI" (should settings be changed, communicate with shiftleader and mail CI). Screen shows a live trend chart plus extruder/laserfilter values. A large machine icon labelled "1" on the right represents the laser melt filter.

## Header / program
- **Rx label:** "1-14-25 production program rke" (recipe/program identifier)
- **System:** BluPort (EREMA)
- **Sub-view:** "Smeltfilter 1 - laserfilter"

## Left-column live gauges (top to bottom, with pictograms)
| Pictogram | Value | Unit | Meaning (gloss) |
|---|---|---|---|
| clock (temp) | 111 | °C | temperature |
| speed/power | 225,8 | kW | main motor power (Vermogen) |
| bars (rpm) | 110 | rpm | main motor speed |
| — | 55 | % | (main motor load / speed %) |
| — | 3554 | h | running hours |
| ◇ (pressure) | 279 | bar | pressure (MP < MF1, matches "279 bar" tile) |
| ⊟ (pressure) | 18 | bar | pressure (matches ΔMP-MF1 differential region) |
| ◇ (pressure) | 172 | bar | pressure |
| ⤷ (output) | **1186** | **kg/h** | **throughput / output rate (answers Q9 for Lijn 6)** |

## Trend chart (2:23:38 → 2:40:17, 12-3-2025)
Four plotted signals (legend):
- **Extruder 1 - belasting** (extruder 1 load) — green trace, rising ~250→290 region (right axis 0–15 scale)
- **Extruder 1 - toerental** (extruder 1 speed) — orange/red trace, flat ~110
- **Massadrukverschil smeltfilter 1** (mass pressure differential melt filter 1) — green legend
- **Motor 1 - toerental** (motor 1 speed) — yellow trace, flat near top (~10 on right axis)
- Left axis 0–350; right axis 0–15.

## Bottom control tiles
- **Motor** — "Aan" (ON)
- **Zeefvoorwaarde Gaten vrij [%]** (sieve condition / holes free %): **47 %**
- **Zeefwissel** (screen change) — button
- **MP < MF1:** 279 bar
- **ΔMP-MF1:** 257 bar
- **MP > MF[1]:** 22 bar
- **ΔMP-MF1-LPE:** 1,0

## Answers to open questions
- **Q9 (throughput):** Lijn 6 running at **1186 kg/h** output on 12-3-2025 (see ⤷ gauge). Extruder load trending 250–290.
- **Q15 (laserfilter zones / MP):** This screen is the "Smeltfilter 1 - laserfilter" node; melt-pressure architecture confirmed as **MP < MF1 (before filter) = 279 bar**, **MP > MF1 (after filter) = 22 bar**, **ΔMP-MF1 = 257 bar** differential across the laser filter. Confirms laserfilter measures upstream (high) vs downstream (low) melt pressure.
- **Q29 / Q30 (units):** On Lijn 6 EREMA BluPort — **Vermogen (power) = kW** (225,8 kW); **Snelheid hoofdmotor = rpm** (110 rpm) with a separate **% load** field (55 %); temperature °C; pressures in **bar**; output in **kg/h**. This gives concrete unit answers for the EREMA/Lijn-6 exports.
- **Q28-adjacent / recipe:** production program "1-14-25 production program rke" active.
- Operator note (taped): main-motor / screw range **3 rpm min – 8 rpm max**, and **compactor afzuiging (extraction) must be AAN** — reinforces the "Afzuiging compactor AAN" checklist item seen in FORM-008.
