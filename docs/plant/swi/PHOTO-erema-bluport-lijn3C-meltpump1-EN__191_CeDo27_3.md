# PHOTO — EREMA BluPort HMI (English), LIJN 3C, Melt pump 1 / Production

- **Source file:** `191_CeDo27 (3).pdf` (1 page, 3.0 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, **English** UI language, line **LIJN 3C** (label plate below panel) — "Melt pump 1 / Production" screen (English twin of 190_CeDo63)
- **SWI id:** none (HMI screenshot)
- **Scope:** Melt pump 1 monitoring on extruder line 3C
- **References:** EREMA BluPort; recipe "LDPE 600 kg/h 22.04.2024 …"

## Context labels
- White sticker top-left (partly cut): "...VEILIGHEIDSCONTROLE / IN POSITIE / ..." ("...safety check / in position...")
- Top brand: **ERE[MA]** (large) and screen brand **BluPort  EREMA**
- Blue label plate below screen: **LIJN 3C**
- Alarm pictogram top-center lit yellow (wifi/alarm broadcast icon) — warning active
- Red 3-bar menu icon bottom-left (hamburger/alarm list)

## Recipe header (verbatim, English UI)
- **℞ (Rx) = "LDPE 600 kg/h 22.04.2024 …BN"** [last token unsure: "BN" or "IBN"]
- Right header block: **Melt pump 1** / **Production**

## Left-column live values
- Clock: **21:34:53**, date **09/10/2024**  [reading: 09-10-2024]
- (gauge) **114 °C**
- (power) **210,5 kW**  [unsure last digit: 210.5]
- (speed) **105 rpm**  [unsure: 105]
- (load) **61 %**
- (hours) **2276 h**
- (pressure ◇1) **272 bar**
- (pressure ⊗1/filter) **39 bar**
- (pressure ◇2) **172 bar**
- (throughput ⤷) **1326 kg/h**  [unsure: 1326]

## Trend chart (English legend)
- Left Y-axis: **0…100** (cyan 100 / orange markers)
- Right Y-axis: **0…500** in 50s (green/yellow markers) — bar
- X-axis timestamps around **21:xx:xx  09/10/2024** (illegible minutes)
- Trace legend:
  - cyan = **Melt pump 1 - speed** (rises sharply mid-chart then flat high — startup ramp captured)
  - green = **Melt pressure upstream of melt pump 1** (low, ~near bottom)
  - yellow = **Melt pressure downstream melt pump 1** (mid, steps up)

## Center tile
- **Melt pump 1 / melt density** (value area too dark to read — [unsure: not legible])

## Right mimic
- Melt-pump / diverter valve mimic (twin-gear pump body, several status boxes blank/white — screen mostly dark). Tiles unreadable.

## ANSWERS TO OPEN QUESTIONS
- **Q29:** Reconfirms **LIJN 3C** panel = **EREMA BluPort extruder melt-pump HMI** (Melt pump 1 / Production), English UI. Not a wash-line SCADA screen. Same conclusion as 190_CeDo63.
- **Q30:** Confirms English unit labels: power **kW**, speed **rpm**, load **%**, throughput **kg/h**, pressures **bar**, density in a "melt density" tile. Matches Dutch twin.
- **Q21 (1200 kg/hr budget which line?):** Not stated, but this **3C** recipe is **"LDPE 600 kg/h"** and live throughput reads ~**1326 kg/h**; line 3C runs LDPE. [Data point only, does not pin the 1200 budget.]

## Notes for sim
- Direct English↔Dutch label mapping for BluPort (useful for bilingual sim UI):
  - Smeltpomp = Melt pump; toerental = speed; Massadruk voor = Melt pressure upstream; Massadruk na = Melt pressure downstream; Smeltdichtheid = melt density; Productie = Production; doorzet = throughput; belasting = load.
- Chart captures a **startup ramp** (pump speed climbing from low to steady) — good reference for sim start-of-shift extruder spin-up behaviour.
