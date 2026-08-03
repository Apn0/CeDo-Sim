# PHOTO — EREMA SIMATIC HMI, Laserfilter trend screen

- **Source file:** `189_CeDo89 (3).pdf` (1 page, 4.6 MB photo scan)
- **Type:** Photograph of a Siemens SIMATIC HMI TOUCH panel running EREMA laserfilter software
- **SWI id:** none (screenshot/photo, not a numbered work instruction)
- **Scope:** Laserfilter (melt filter) monitoring screen — one filter unit ("1")
- **References:** EREMA laserfilter; SIMATIC HMI

## Panel hardware
- Brand top-left: **SIEMENS**; top-right: **SIMATIC HMI**; right vertical bezel: **TOUCH**
- Software brand top-right of screen: **EREMA** (with EREMA infinity/motor logo)

## On-screen values (verbatim)
- Clock (top-left): **06:05:38 PM**, date **28/01/2025**
- Top-right three tiles (melt-pressure differential across filter):
  - **MP < MF** = **207 bar**  (MP = pressure before filter / Melt Pressure before screen)
  - **Δ MP** = **182 bar**  (differential melt pressure across filter)
  - **MP > MF** = **25 bar**  (pressure after filter)
  - [interpretation: MF = melt filter; "MP < MF" reads as melt pressure on the upstream side, "MP > MF" downstream side; Δ MP = 207 − 25 = 182 bar, consistent]

## Trend chart (left)
- Left Y-axis (temperature) scale: **0, 50, 100, 150, 200, 250, 300, 350** (°C)
- Right Y-axis (speed) scale: **0, 2, 4, 6, 8, 10**
- Colored scale markers left: cyan **350**, orange **300** (legend swatches)
- Right swatch: yellow **10**
- X-axis timestamps: **05:35:37 PM / 05:45:37 PM / 05:55:37 PM / 06:05:37 PM**, all **28/01/2025**
- Legend under chart:
  - cyan = **Melt temperature** (flat trace ~250 °C)
  - yellow = **Motor 1 speed** (square-wave, cycling between ~0 and full — the periodic screen-change/back-flush cycle of the laserfilter)
  - orange = **Δ MP** (sawtooth ~180-210, rising then dropping on each screen advance)

## Controls
- Center-bottom control box: label **Motor**, state button **On**
- 3D render (right): single laserfilter/melt-filter head labelled **1** (blue EREMA motor icon) with feed and discharge piping

## Bottom navigation icons (pictograms, left→right)
1. **Home** (house)
2. **Process/flow** (→◇→ diamond flow icon)
3. **Alarm** (bell, lit RED = active alarm/acknowledge)
4. **Rx** (recipe / prescription "℞" — recipe management)
5. **Trend** (rising line-chart with arrow)
6. **Settings/maintenance** (wrench)

## Notes for sim
- Confirms laserfilter is driven by a **Motor 1 speed** that advances the screen in periodic pulses; Δ MP builds as the screen loads with contaminant then drops on each advance/back-flush. Melt temperature is held ~250 °C.
- Bears on **Q15** (temp zones) only indirectly: melt temp at the filter here is ~250 °C.
- Δ MP of 182 bar with 207 in / 25 out is a live operating point captured 28-01-2025 18:05.
