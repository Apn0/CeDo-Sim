# PHOTO — EREMA BluPort HMI, LIJN 3C, Smeltpomp 1 (melt pump) screen

- **Source file:** `190_CeDo63 (3).pdf` (1 page, 5.2 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI screen, line **LIJN 3C** (label plate below panel), "Smeltpomp 1 / Productie" screen
- **SWI id:** none (HMI screenshot)
- **Scope:** Melt pump (Smeltpomp 1 = "melt pump 1") monitoring on extruder line 3C — trend + live values + mimic
- **References:** EREMA BluPort; recipe "1-14-25 production program rke"

## Context labels
- Yellow sticker above panel: **"Afzuiging compactor  !!! AAN !!!"** ("Compactor extraction/exhaust — ON!") — reminder that the compactor's extraction/suction must be ON.
- Partial white sticker top-left (mostly cut off): "...IN POSITIE / ...EN NIET VERWIJDEREN OF MISVORMEN / 1 holländisch" ("...in position / and do not remove or deform")
- Blue label plate below screen: **LIJN 3C**
- Bottom-right faint page number: **111**
- Top brand: **BluPort  EREMA** (with BluProcess/BluPort logo)

## Recipe header (verbatim)
- **℞ (Rx) = "1-14-25 production program rke"** (active production program/recipe)
- Right header block: **Smeltpomp 1** / **Productie** ("Production")

## Left-column live values (pictogram : value : unit)
- Clock: **17:15:30**, date **17-2-2025**
- (thermometer/gauge) **107 °C**
- (power) **250,0 kW**
- (speed) **82 rpm**
- (load %) **55 %**
- (hours) **4626 h** (running hours)
- (pressure ◇1) **297 bar**
- (pressure ⊗1 / filter) **22 bar**
- (pressure ◇2) **214 bar**
- (throughput ⤷) **1022 kg/h**

## Trend chart
- Left Y-axis: **0…100** (with cyan **100** and orange markers) — likely °C / % scale for temp/load
- Right Y-axis: **0, 50, 100, 150, 200, 250, 300, 350, 400, 450, 500** (bar) — green/yellow markers
- X-axis timestamps: **16:58:50 / 17:02:59 / 17:07:09 / 17:11:19 / 17:15:29**, all **17-2-2025**
- Trace legend:
  - cyan = **Smeltpomp 1 – toerental** ("melt pump 1 speed") — high flat ~top then dips/oscillates near end
  - green = **Massadruk voor smeltpomp 1** ("mass/melt pressure BEFORE melt pump 1") — low flat near bottom (~20-25)
  - yellow = **Massadruk na smeltpomp 1** ("mass/melt pressure AFTER melt pump 1") — mid ~200, dips near end

## Center tile
- **Smeltpomp 1 / Smeltdichtheid** ("melt density") = **0,748 kg/dm³**

## Right-side mimic + tiles (melt pump unit MPU1)
- **MPU1-toerental** ("MPU1 speed") = **89 rpm**
- **MPU1-belasting** ("MPU1 load") = **57 %**
- **MPU1-doorzet** ("MPU1 throughput") = **2380 kg/h**
- **MPU1-Z1** (zone 1 temp) = **298 °C**
- Bottom melt-filter pressure tiles:
  - **MP < MPU1** = **22 bar** (pressure before MPU1)
  - **ΔMP-MPU1** = **193 bar** (differential)
  - **MP < MF2** = **214 bar** [reading; likely "MP > MF2" or a second melt-filter reference; value 214 bar]
- Mimic shows melt-pump gear-pump render (twin gears) feeding downstream piping

## ANSWERS TO OPEN QUESTIONS
- **Q29 (3C = SCADA host for wash line 6?):** This screen is labelled **LIJN 3C** and is an **EREMA BluPort extruder/melt-pump HMI** (Smeltpomp 1, Productie), NOT a wash-line SCADA. Evidence: panel plate "LIJN 3C" + BluPort branding + melt-pump/extruder mimic. So 3C here = the EREMA extruder line 3C's own HMI. [Does not confirm 3C hosts wash line 6 SCADA; contradicts that reading for this panel.]
- **Q30 (units):** Confirms on this HMI — **Vermogen hoofdmotor = kW** (250,0 kW) alongside a separate **% load** (55 %); **Snelheid = rpm** (82 rpm / 89 rpm); throughput **kg/h**; melt **density kg/dm³**; pressures **bar**; zone temp **°C**. So main-motor power is shown in **kW** and load separately in **%**.

## Notes for sim
- Two throughput figures differ: line/extruder ⤷ **1022 kg/h** vs **MPU1-doorzet 2380 kg/h** — likely instantaneous pump vs averaged line, or different meters. Note discrepancy.
- Smeltdichtheid 0,748 kg/dm³ = melt density used to convert pump volumetric rate to mass throughput.
- Operating point 17-02-2025 17:15: melt temp region ~298 °C at MPU1-Z1, pump ~89 rpm, ΔMP 193 bar.
