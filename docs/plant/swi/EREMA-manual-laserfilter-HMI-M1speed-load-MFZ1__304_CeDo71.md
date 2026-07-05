# EREMA manual — Laserfilter HMI (Fig. 54 smeltfilter behuizing, M1-speed / M1-load / MF1-Z1)

- **Source file:** `304_CeDo71.pdf` (single page, EREMA operator-manual excerpt, scanned)
- **SWI id:** none (EREMA manual page — laser-filter / melt-filter HMI reference)
- **Title:** Laserfilter motor speed / motor load / temperatuur zone MF-Z1 (HMI field descriptions)
- **Scope:** EREMA touchscreen fields for the laser filter (*Laserfilter* = melt filter with rotating scraper disc, *schraperschijf*). Operator-level HMI.
- **References:** EREMA laserfilter family (SWI-074, LF2-406); MF1-Z1/MF1-Z2 temperature zones.

## Header
- "Operator niveau =" [pictogram, level 3.0 or similar — unsure: small box reads approx "3.0"] — indicates HMI shown is at **Operator niveau** (operator level).
- Brand: **EREMA** (logo top right).

## Fig. 54 (photo/screenshot description)
- Caption: "**Fig. 54: touchscreen smeltfilter behuizing**" (touchscreen melt-filter housing).
- Screenshot of EREMA HMI dark screen. Left panel: timestamp "10:56:20 08/09/2021" [unsure: date reading], event/log list at bottom with rows of timestamps and text "Motor 1 - Speed", "Motor 1 - Pump" [unsure], header bar right "Melt filter 1 - Reiniging 1" [unsure]. Right side: schematic of the melt-filter housing (white geometric block diagram) with several temperature readout boxes reading "0 °C" (labels MF1-Z1/Z2/Z3/Z4 area — small), and top-right small boxes with values (%, rpm) reading approx "0 rpm" / "0 %". Nav arrows bottom (back/forward), hamburger menu bottom-left. A large "Rx" / prescription-like glyph overlays center-left [unsure: OCR artifact].

## HMI field descriptions (verbatim NL + EN gloss)

### Laserfilter motor speed
- Field label: **M1-speed** — value shown **0 rpm**
- Description: "Weergave van de schraperschijfsnelheid" = *Display of the scraper-disc speed* (*schraperschijf* = scraper disc of the laser filter).

### Laserfilter motor load
- Field label: **M1-load** — value shown **0 %**
- Description: "toont de belasting op de aandrijfmotor van de schraperschijf" = *shows the load on the drive motor of the scraper disc.*

### Laserfilter temperatuur zone MF-Z1
- Field label: **MF1-Z1** — value shown **30 °C**
- Description: "Bij het aanpassen van de waarde van de MF1-Z1 zone (mastertemperatuur), wordt de MF1-Z2 temperatuurzone op de laserfilter ook geregeld met dezelfde ingestelde waarde (master - slave - werking)."
  - EN: *When adjusting the value of the MF1-Z1 zone (master temperature), the MF1-Z2 temperature zone on the laser filter is also controlled to the same set value (master–slave operation).*

## Key values (verbatim)
- M1-speed: **0 rpm** (scraper-disc speed)
- M1-load: **0 %** (scraper-disc drive-motor load)
- MF1-Z1: **30 °C** (master temp; MF1-Z2 follows as slave)

## Q&A hits
- **Q15 (temp zones around laserfilter):** partial — confirms laser filter has its own temperature zones **MF1-Z1** (master) and **MF1-Z2** (slave), governed together. Does not give the 200/235/175/240/245/250/255 extruder-zone sequence. Doc quote: "MF1-Z1 zone (mastertemperatuur) ... MF1-Z2 temperatuurzone op de laserfilter ook geregeld ... (master - slave - werking)."
- **Q30 (units):** M1-speed unit = **rpm** (scraper disc); M1-load unit = **%** (motor load). Laser-filter temp unit = **°C**.
- Naming: laser-filter scraper disc drive motor = **M1** (M1-speed / M1-load). Consistent with laser-filter M1/M2/M3 references elsewhere.
