# Erema extruder HMI control-panel photo (line 3) — NOT a SWI page

- **SWI ID:** OTHER:photo (no SWI header, no step table)
- **Title (NL):** — (operator photo of Erema extruder control screen)
- **Title (EN):** Erema extruder HMI trend/overview screen + hard-key panel
- **Source file:** 165_CeDo66 (3).pdf
- **Pages:** 1
- **Scope:** Line 3 Erema extruder operator HMI. A single photograph of the Erema control-panel touchscreen (blue bezel) showing a live trend graph, process readouts, and the bottom row of physical hard-keys. No instructional text, no step table, no pictogram footer — this is a reference photo, not an SWI procedure page.

## Screen transcription (verbatim readouts)

**Timestamp / date on screen:** `17:27:57  27/02/2025` (current); trend window left edge `17:11:18  27/02/2025` → right edge `17:27:57 27/02/2025` (~16.5 min window).

**Left trend graph — Y axis 0…400 (left scale):** three plotted traces with legend:
- `SV-vermogen (kW)` — red trace (SV power draw in kW), rising ~100 → ~230 across the window.
- `toevoer aan` (feed on) — cyan trace, low/near-zero stepped square-wave (on/off feed indicator) along the bottom.
- `SV-temperatuur (°C)` — green trace, rising alongside the red, tracking near it.
- `intrekschuif (%)` — yellow trace (**intake/retract slide %**), flat low along the bottom (~near 0–5%).

**Right-hand Y axis (second scale) 0…225** with two setpoint/limit markers: green band ≈ **200**, yellow band ≈ **175** (temperature scale in °C for the green SV-temperatuur trace).

**Process readouts (right side data boxes):**
- `ex - belasting` (extruder load) = **42 %**
- `extr. rpm` (extruder rpm) = **65 rpm**
- Partial label `E…` (Erema logo/extruder graphic, right edge, cut off).

**Mimic / navigation icons across bottom of screen (left→right):**
- `toevoer keuze` (feed selection) — button, top-left of icon row.
- `toevoer` (feed/infeed) — icon: arrow-into-box.
- `extruder` — icon: three screw/coil loops (extruder screw symbol).
- `smeltfilter` (melt filter = **Laserfilter**) — icon: arrows → diamond → arrows (filter-flow symbol).
- `navolging` (post-processing / downstream / "follow-up") — icon: arrow looping out of a box (outfeed to downstream, i.e. heetafslag/pelletiser).

**Physical hard-keys (bottom bezel, below screen, left→right):**
- Yellow mushroom button (partial, far left) — likely feed/jog or E-stop-adjacent yellow.
- Power/standby key (circle-with-line power symbol).
- Feed key (arrow-into-box symbol, matches `toevoer`).
- Rotary selector knob (0 / 1 / 2 positions visible).
- Function key (circular icon, "s"-like glyph — possibly screw/start).

## Notes / answers

- **Confirms Erema is the line-3 extruder OEM** and names the on-screen process signal set the sim can mirror for an extruder gauge cluster:
  - **ex-belasting (extruder load) %** — here 42 %
  - **extr. rpm** — here 65 rpm
  - **SV-vermogen (kW)** — screw/drive power (SV = "Schnecke"/screw drive), live ~230 kW
  - **SV-temperatuur (°C)** — melt/screw temperature, setpoint band ~200 °C (green), ~175 °C secondary (yellow)
  - **intrekschuif (%)** — intake retract-slide position (Erema's cutter-compactor "intake slide" feeding the screw)
  - **toevoer aan** — binary feed-on signal
- **Relevant to Q4 (extruder gauges/setpoints):** real Erema HMI shows load %, rpm, drive power kW, melt-temp °C with 200 °C target band — directly usable numbers for the sim's extruder panel. At this moment the machine is **warming/starting up** (temp still climbing toward the 200 °C band, feed pulsing on/off, load only 42 %).
- **Relevant to Q4/Q15 (Laserfilter):** the melt filter is labelled **"smeltfilter"** on the Erema mimic (the Erema term for the Laserfilter); downstream node is **"navolging"** (post-processing → heetafslag/pelletiser). Screen flow left→right: **toevoer → extruder → smeltfilter → navolging** — the Erema line-3 process chain in the OEM's own words.
- **Date stamp 27/02/2025** — a recent operator capture (photo taken during a real start-up).
- No SWI number, no procedure steps; indexed as OTHER:photo. No data lost — full screen readout transcribed above.
