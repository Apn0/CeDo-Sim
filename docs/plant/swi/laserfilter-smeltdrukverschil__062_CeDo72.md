# Laserfilter smeltdrukverschil ΔMP-MF (melt-filter pressure differential HMI) — 062_CeDo72

- **Source file:** D:/drive-download-20251124T130330Z-1-001/062_CeDo72.pdf
- **Doc id:** OTHER:HMI-manual-page (extruder melt-filter / laserfilter operator screen; no SWI number)
- **Title (NL):** "Smeltdrukverschil ΔMP-MF" (Melt-pressure differential ΔMP-MF)
- **Pages:** 1
- **Scope:** One HMI/SCADA reference page describing the melt-filter (smeltfilter / laserfilter) pressure-differential speed control and safety cutout. Tabbed binder (yellow/orange/red index tabs at right).
- **Line:** general (extruder + melt filter — applies to any extruder line with the rotary disc laserfilter)

## Full transcription (verbatim NL, EN gloss)

**Top info box (ℹ️ info pictogram, small italic grey banner):**
> "Als de smeltdruk stroomopwaarts van de smeltfilter boven een grenswaarde van 320 bar stijgt, worden de Compactor (optie), de extruder en het pelletiseringssysteem onmiddellijk uitgeschakeld."
> *(If the melt pressure upstream of the melt filter rises above a limit of 320 bar, the Compactor (option), the extruder and the pelletising system are immediately shut down.)*

**Heading:** **Smeltdrukverschil ΔMP-MF** (Melt-pressure differential ΔMP-MF)

**Field 1 — display box:**
> `ΔMP-MF1`  →  **0 bar**

Description text:
> "De snelheidsregelaar wordt geregeld door deze waarde. Als het werkelijke drukverschil boven de ingestelde waarde ligt, draait de scraperster sneller, als de druk lager is, draait de scraperster langzamer."
> *(The speed controller is regulated by this value. If the actual pressure differential is above the set value, the scraper star turns faster; if the pressure is lower, the scraper star turns slower.)*
> Underlined: **"Grenswaarden: 0-300 bar"** (Limits: 0–300 bar)

**Field 2 — display box:**
> `MP > MF1`  →  **0 bar**

Description text:
> "toont de huidige smeltdruk stroomafwaarts van de filter"
> *(shows the current melt pressure downstream of the filter)*

## Machine facts extracted (load-bearing for sim)

- **Laserfilter = rotary disc melt filter with a "scraperster" (scraper star)** whose rotation speed is closed-loop controlled by the melt-pressure differential across the filter (ΔMP-MF). Higher differential (dirtier screen) → scraper star spins faster to clear contaminant; lower → slower. This matches the user's "Laser filter (Britas-style melt filter)" memory note: scraper clears contaminant, spins based on ΔP.
- **ΔMP-MF1 setpoint range / limits: 0–300 bar.** Controls scraper star speed.
- **Safety cutout: melt pressure upstream of filter > 320 bar → immediate shutdown of Compactor (option), extruder, and pelletising system.** (Concrete trip value for the sim — a hard fault condition.)
- **MP > MF1** = current melt pressure *downstream* of the filter (post-filter pressure). ΔMP-MF = upstream minus downstream.
- Confirms melt-filter pressure telemetry naming: MP (melt pressure), MF (melt filter). Values shown as **0 bar** (screen at rest / not running).

## Cross-refs to open questions
- **Q15 (extruder zones / laserfilter):** confirms the laserfilter sits mid-stream between extruder and pelletiser; pressure is monitored both upstream (trip at 320 bar) and downstream (MP>MF1). Supports the reading that zones before the filter build pressure/melt and zones after re-melt/stabilise post-filtration.
- No temperature zone data on this page.
