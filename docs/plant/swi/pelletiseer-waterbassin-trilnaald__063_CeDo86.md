# Pelletiseersysteem — waterbassin spoelinterval & trilnaald follow-up tijd (HMI) — 063_CeDo86

- **Source file:** D:/drive-download-20251124T130330Z-1-001/063_CeDo86.pdf
- **Doc id:** OTHER:HMI-manual-page (pelletising system operator screen; no SWI number)
- **Title (NL):** two settings on one page — "Pelletiseersysteem - intervaltijd voor het spoelen van het waterbassin" and "Pelletiseersysteem - trilnaald follow-up tijd"
- **Title (EN):** "Pelletising system — interval time for flushing the water basin" / "Pelletising system — vibrating-needle follow-up time"
- **Pages:** 1
- **Scope:** One HMI reference page (same EREMA-style manual as 062_CeDo72). Tabbed binder (yellow/orange/red tabs at right).
- **Line:** general (pelletiser / pellet dewatering — applies to any pelletising line)

## Full transcription (verbatim NL, EN gloss)

### Setting 1
Heading: **"Pelletiseersysteem - intervaltijd voor het spoelen van het waterbassin"**
*(Pelletising system — interval time for flushing the water basin)*

HMI box (labelled **"Pelletising system - vibrator"**):
> `Follow-up time`  →  **0 s**

Note: the box is *labelled* "Pelletising system - vibrator / Follow-up time" but the heading text describes the water-basin flush interval — the two blocks appear swapped on the scan (see Setting 2, whose box is labelled "water basin / Flush interval time"). Transcribed exactly as printed.

Description text:
> "Stel het interval in waarmee het spoelen plaatsvindt op het pelletontwateringsscherm. De duur van het spoelen ligt vast."
> *(Set the interval at which flushing takes place, on the pellet-dewatering screen. The duration of the flush is fixed.)*

### Setting 2
Heading: **"Pelletiseersysteem - trilnaald follow-up tijd"**
*(Pelletising system — vibrating-needle [trilnaald] follow-up time)*

HMI box (labelled **"Pelletising system - water basin"**):
> `Flush interval time`  →  **0 min**  (the "0" is highlighted/editable)

Description text:
> "Stel de follow-up tijd in gedurende welke de trilmotoren blijven draaien nadat het pelletiseersysteem is uitgeschakeld."
> *(Set the follow-up time during which the vibration motors keep running after the pelletising system has been switched off.)*

## Machine facts extracted

- **Pellet dewatering ("pelletontwatering") screen** on the HMI controls water-basin flushing. Flush **interval** is operator-settable (minutes); flush **duration is fixed**.
- **Trilnaald / trilmotoren (vibrating needle / vibration motors)** on the pellet dewatering vibrator have a **follow-up time (seconds)** — they keep running after the pelletiser is switched off to clear residual pellets/water.
- Values shown at rest: 0 s / 0 min.
- Confirms sim water-loop machinery: pelletiser has a **water basin + dewatering screen + vibratory dewatering** stage (relevant to Q5 granuleerwater loop / Ontwaterzeef water routing — the pellet water basin is periodically flushed).

## Cross-refs to open questions
- **Q5 (water routing / granuleerwater loop):** confirms a pellet water basin that is periodically flushed and a vibratory **Ontwaterzeef**-style dewatering screen ("pelletontwateringsscherm") in the pellet/granulate water loop. Does not give routing directions.
- No throughput, temperature, or line-ID data on this page.
