# PHOTO — EREMA BluPort HMI: "Smeltpomp 1 / Productie" (melt pump MPU1 mimic)

- **Source file:** 329_CeDo33 (3).pdf
- **Type:** Photograph of EREMA **BluPort** HMI screen (dark, off-axis)
- **SWI id:** none (HMI screenshot)
- **Header logo:** "BluPort  EREMA" (EREMA BluPort SCADA/HMI)
- **Screen title banner:** **"Smeltpomp 1"** (Melt pump 1) / sub-banner **"Productie"** (Production)
- **Line context:** EREMA extruder line 3C (BluPort is the lijn-3C/lijn-6 EREMA HMI family per prior docs). Melt pump = MPU1 (Melt Pump Unit 1 / smeltpomp = gear pump downstream of laserfilter).

## Central graphic
- Gear-pump mimic: two intermeshing gears (twin-gear melt/discharge pump) in a housing, with melt inflow pipe from top (from extruder/laserfilter) and horizontal in/out melt pipes (left = inlet, right = outlet, both drawn as torn/broken-pipe ends indicating continuation off-screen).

## Live values (verbatim)
| Tag (verbatim) | Value | Unit | Gloss |
|----------------|-------|------|-------|
| **MPU1-toerental** | 89 | rpm | melt pump 1 speed (toerental = revolutions) |
| **MPU1-belasting** | 39 | % | melt pump 1 load |
| **MPU1-dobrzet** [sic — "doorzet"] | 2632 | kg/h | melt pump 1 throughput |
| **MPU1-Z1** | 270 | °C | melt pump 1 zone 1 temperature |
| **MP < MPU1** | 33 | bar | melt pressure before/at MPU1 (inlet-side pressure) [unsure: "MP vóór MPU1"] |
| **ΔMP-MPU1** | 84 | bar | melt pressure differential across MPU1 |
| **MP < MF2** | 115 | bar | melt pressure before MF2 (melt filter 2 / after-pump) [unsure last digit; reads 115 bar] |

Notes on legibility: image dim; "dobrzet" is OCR/scan artefact for **doorzet**; "MP < MPU1" and "MP < MF2" — the "<" likely denotes "voor/before" the named component. Values above read cleanly except MF2 pressure (115 bar, [unsure]).

## Answers to open questions
- **Q30 (units):** Confirms melt-pump HMI tag units — toerental in **rpm**, belasting in **%**, doorzet in **kg/h**, zone temp in **°C**, all pressures in **bar**. Melt pump throughput here **2632 kg/h** (higher than extruder-panel 1679 kg/h in 328_CeDo17 — different run/line).
- **Q7 (tankje tussen extruders):** no direct answer, but confirms melt-train order component naming: extruder → MPU1 (smeltpomp/gear pump) → MF2 (melt filter 2). "MP < MF2" = pressure before MF2.
- **Q15 (laserfilter temp zones):** MPU1-Z1 melt zone = **270 °C** (melt-pump body zone), consistent with post-laserfilter melt in the 240-270 °C band.
- No answers to Q1-Q6, Q8-Q14, Q16-Q29, Q31-Q33.
