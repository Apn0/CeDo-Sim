# EREMA BROCHURE — INTAREMA® "Built to perform" (image brochure)

- **Source file:** `353_intarema_image_08_2022_en.pdf` (D:/drive-download-20251124T130330Z-1-001)
- **Type:** EREMA general/image brochure, English, 7 scanned pages. Doc code **08/22** (Aug 2022). Download: erema.com/en/download_center/
- **SWI id:** none (vendor brochure)
- **Scope:** Marketing overview of the INTAREMA® platform (the extruder family CeDo runs). No throughput table in this one (that's in the TVEplus brochure `352`). Value here = the **standard control-system feature list** and the **standby/automation behaviour** relevant to modelling line auto-behaviour in the sim.
- **Publisher:** EREMA, Ansfelden, Austria (same as `352`).

## Three pillars (same trio as TVEplus brochure)
1. **Counter Current®** (patented) — reverses PCU rotation vs extruder screw; relative intake speed rises so the extruder edge "slices up" the plastic → more material in shorter time, consistently high output over a much broader PCU temperature range. Bullets (verbatim):
   - Highest process stability through improved material intake → constantly high output over broader temperature range.
   - Higher flexibility and operational stability with a variety of materials.
   - Increased throughputs with the same plant size for more productivity.
   - PCU is "multitalented": **Cutting, homogenising, heating, drying, compacting, buffering and dosing – in a single stage.**
2. **Smart Start®** — three sub-areas:
   - **automation:** stable processes, top pellet quality, reduced labour & energy via high-performance control tech.
   - **recipe management:** saved processing parameters loaded at push of a button → reproducibility/constant processes; upgradeable via **re360 MES**.
   - **operation & data management:** few buttons, ergonomic touchscreen operator panel; upgrades = **smart portal, CSV data storage, OPC interface with customer's MES, re360 MES**.
3. **ecoSAVE®** — **up to 12% less energy**, reduced CO₂, lower cost; new highly efficient **direct drive** of the extruder screw; **energy display on operating panel** (constant energy-consumption overview). Standard feature, no extra cost.

## Standard control systems (VERBATIM — useful for sim line automation)
> "Standard control system examples: **Start / stop control, automatic load detector, automatic feeding supervision of the preconditioning unit, automatic pelletiser speed control**"

## Automation use-cases (verbatim behaviour — good for sim state machine)
- **Inhouse recycling (film production):** recycling machine keeps pace with main line frequency; **recognises when no more edge trim is supplied and switches automatically to energy-saving standby mode**; restarts when edge trim resumes.
- **Post-consumer recycling (sorting + washing plant integration):** compensates for moisture differences from the washing plant; **recognises when washing plant stops supplying material → auto standby → auto restart** when material returns. (Directly models the CeDo wash-line → extruder coupling.)
- **Special applications (foams & regrind):** ultramodern sensor tech keeps quality constant with varying bulk densities; inputs incl. EPP, EPS, XPS foams + regrind.

## Data-management standard vs upgrade matrix (page 10-11)
Three quality axes: **Convenient operation · Transparency (data overview/analysis) · Data traceability/protection.** Rows (bar-fill capability): Smart Start touchscreen panel (standard) → Smart portal (1:1) → CSV → OPC + customer's own MES → **re360** (highest fill on all three).
- **Smart portal (optional):** remote control + services (remote maintenance / process-engineering support / software updates).
- **CSV (optional):** data storage in CSV format.
- **OPC + customer's MES (optional):** OPC interface integrates a customer-provided MES.

## Open-question hits
- **Q30 (units — Vermogen/Snelheid etc.):** No hard units here, but confirms the extruder uses a **direct drive** (screw) and the panel shows an **energy display** (kWh-type). Supports interpreting HMI "elektrische energie" screens (cross-ref `PHOTO-erema-hmi-elektrische-energie-kWh-per-kg__328`).
- **Q9/Q21 (throughput):** no table in this brochure — see `352_intarema_tveplus` MD for the kg/h tables.
- No CeDo plant-label answers (Q1/Q11/Q12 etc.) — pure vendor image brochure.

## Notes
- Back cover identical to `352` (EREMA HQ + QR), doc code 08/22.
- Confirms the "washing plant no longer supplying → auto standby" logic is a genuine INTAREMA standard behaviour, worth replicating in the sim's line coupling.
