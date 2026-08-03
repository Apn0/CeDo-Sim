# EREMA BluPort HMI screenshot — trend/history graph screen (rotated 90°)

- **Source file:** `217_CeDo10 (3).pdf` (single page, 5.3 MB photo)
- **Doc type:** Photograph of an EREMA BluPort HMI **trend graph / history** page. Image is rotated ~90° (portrait phone photo of a landscape screen); text reads sideways.
- **SWI id:** none (HMI photo)
- **Line:** not labelled in frame, but same EREMA BluPort HMI family as 206-210 (bottom bezel shows the same "Rx" recipe button, an "eco SAVE" button, and folder/camera icons). Almost certainly LIJN 3C (same panel).

## Screen contents
- Full-screen **trend graph** (multiple colored traces on a black background) with a legend table on the right.
- Y-axis (top edge in rotated image) numeric scale runs ~0 … 275/300 (tick labels 25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275 visible).
- Two vertical **cursor lines** with timestamps:
  - **17:43:41  11-8-2024** (left cursor)
  - **18:16:59  11-8-2024** (right cursor / current)

## Legend / value table (right side) — "Datum/Tijd" = Date/Time
Each row: a value, then the sample timestamp **11-8-2024 17:41:23:292** (all rows share the same date/time stamp — cursor readout column), colour-coded to match the traces:

| Value | Colour | Timestamp | Likely tag (by colour vs 206-210 overview) |
|---|---|---|---|
| 25 | cyan | 11-8-2024 17:41:23:292 | Toevoer actief / BC1 (cyan = feed) |
| 119 | blue/indigo | 11-8-2024 17:41:23:292 | — |
| 112 | green | 11-8-2024 17:41:23:292 | PCU-temperatuur 1 (green in overview) |
| 59 | yellow | 11-8-2024 17:41:23:292 | AIS-positie (yellow in overview) |
| 13 | orange | 11-8-2024 17:41:23:292 | — |
| 70 | white | 11-8-2024 17:41:23:292 | — |
| 262 | red | 11-8-2024 17:41:23:292 | PCU-vermogen (red in overview) [unsure: 262] |
| 11 | (white/last row) | 11-8-2024 17:41:23:292 | — |

- Header cells over the table: **"Datum/Tijd"** (Date/Time) and **"Waarde"** (Value).
- Traces visible on the plot: red (steps down then up), white (two segments), green (rising S-curve), purple/violet (rising curve), yellow+orange short segments near the cursor, cyan square-wave pulses near the bottom.

## Bottom bezel (rotated, reads sideways)
- **Rx** recipe button (same as 206-210), **eco SAVE** button, folder icon, camera icon. Confirms same BluPort HMI.

## Q&A hits
- **Q29/Q30:** Same EREMA BluPort HMI as the LIJN 3C overview screens — this is its **trend-history page**. Values (temp ~112, power ~262, AIS ~59) are consistent with the 3C process ranges seen in 206-210, reinforcing that "3C" = EREMA extruder/compactor line HMI (not a wash SCADA host). Units per trace not labelled on this page.
- Date **11-8-2024** (11 Aug 2024) — a different/earlier session than the 21-23 Dec 2024 overview captures; shows the same HMI was in service months earlier.
- No SWI step data. No answers to Q1-Q28, Q31-Q33.
