# PHOTO — EREMA Bluport HMI trend, LIJN 6, LDPE testrun (smeltpomp toerental + druk)

- **Source PDF:** `368_CeDo31 (3).pdf`
- **Type:** Photograph of EREMA Bluport HMI touchscreen + control panel, NL
- **Line:** **LIJN 6** (labeled on white plate below screen)
- **Screen title (top-right, Rx icon):** "EREMA testrun LDPE 22.02.24" [unsure: "ERE_A" partly glared → EREMA]
- **Timestamp (top-left):** 6:59:52 · 1-11-2024
- **SWI id:** none (live HMI capture)
- **Scope:** Trend graph of melt-pump (smeltpomp) speed and pressures during an LDPE test run

## Sticky-note above screen (NL, partly cut off)
> "8 rpm maximum"
> "...chten er settings gewijzigd worden[,]"
> "[commu]niceer dit met shiftleader en mail naar CI"
(≈ "8 rpm maximum. Should settings be changed, communicate this with the shift leader and mail to CI.")
[unsure: first word "…chten" = "Mochten" (should); "CI" = Continuous Improvement / CI team]

## Left-column live values (top→bottom, value + unit)
| Value | Unit | Likely meaning |
|---|---|---|
| 114 | °C | temperature |
| 197,5 | kW [unsure: "kW" glared] | power |
| 108 | rpm | (screw or pump) speed |
| 60 | % | (load / valve %) |
| 1329 | h | running hours |
| 293 | bar | pressure (⌀ icon — melt pressure point 1) |
| 31 | bar | pressure (2nd point) |
| 114 | bar | pressure (⌀ icon — 3rd point) |
| 923 | kg/h | **throughput / output** |

## Right-side axis
Dual Y-axis (0–100 left scale for blue curve; 0–~300 right scale, marked 250/200/150/100/50 for pressure/temperature).

## Trend curves (legend under X-axis)
- **Blue (flat, top ~ full scale):** unlabeled top trace (temperature or a setpoint), steady across the window.
- **Green:** "Smeltpomp 1 - toerental" (melt pump 1 — speed/rpm) — low band, ~steady.
- **Yellow:** two yellow labels — "Massadruk voor smeltpomp 1" (mass pressure **before** melt pump 1) and "Massadruk na smeltpomp 1" (mass pressure **after** melt pump 1). Yellow curve sits mid-band, fairly steady with minor ripple.

X-axis time stamps: 6:43:12 · 6:47:21 · 6:51:31 · 6:55:41 · 6:59:51 (all 1-11-2024), i.e. ~a 17-minute window.

Small white pop-up box mid-screen: "Smeltpomp 1" / "Smeltdichtheid" [unsure: melt density] with a (blank/white) value field.

Bottom-left: red hamburger/menu (3 red bars) and a red alarm indicator.

## Panel hardware (below screen)
Physical buttons left→right: yellow E-stop/mushroom, power (○) button, an "enter/login" arrow-into-box icon (lit), a settings/gear (S) illuminated pushbutton. White "LIJN 6" label plate.

## Q&A hits
- **Q9 (line throughput kg/h):** **LIJN 6 ≈ 923 kg/h** during this LDPE test run (1-11-2024). Green curve = Smeltpomp 1 toerental.
- **Q16 / Q30 units:** confirms melt-pump readouts in **rpm** (toerental) and **bar** (massadruk voor/na smeltpomp), throughput in **kg/h**, temp °C, power kW, load %, running time h.
- **Q29 (3C SCADA host for wash line 6):** N/A — this is an EREMA extrusion HMI for LIJN 6, not the wash SCADA.
- Sticky note gives an operational limit: **"8 rpm maximum"** (context: the note warns not to exceed 8 rpm on some element; escalate setting changes to shiftleader + CI). [unsure: which element the 8 rpm cap applies to — not stated on note]
