# PHOTO — EREMA BluPort HMI, LIJN 6, testrun LDPE (live-values screen)

- **Source PDF:** `316_CeDo21.pdf` (1 page, photo of HMI touchscreen)
- **Type:** Photograph of EREMA BluPort control-panel screen, line labeled **LIJN 6** (label plate at bottom of monitor bezel). EREMA logo top-right and center of screen.
- **Scope:** Live-values + trend-graph overview screen during an "EREMA testrun LDPE 22.02.24" recipe.

## Sticky note (taped above the screen, top-left) — verbatim NL
> [ont/aan?]trekschroeven setting  [first word partly cut off; reads "...trekschroeven setting" — likely "Aantrekschroeven" or "Uittrekschroeven setting"]
> 3 rpm minimum
> 8 rpm maximum
> Mochten er settings gewijzigd worden communiceer dit met shiftleader en mail naar CI

EN: "[pull-]screws setting — 3 rpm minimum, 8 rpm maximum. Should settings be changed, communicate this with the shift leader and mail to CI."
- [unsure: first word "Aantrekschroeven" (tightening screws) vs a feed/draw screw; the 3-8 rpm range is very low, consistent with a slow draw/pull screw or dosing screw.]

## Header / recipe line
- Clock: **22:11:31**, date **1-10-2024**
- Recipe (Rx): **"EREMA testrun LDPE 22.02.24"**
- Branding: **BluPort · EREMA**

## Left column live values (icon : value : unit) — verbatim
| Icon (meaning) | Value | Unit |
|---|---|---|
| Temperature (°C symbol) | **105** | °C |
| (power, same group) | **177,9** | kW [unsure: "kW" glyph faint] |
| Screw speed (rpm) | **111** | rpm |
| Load/percentage | **54** | % |
| Hours counter | **862** | h |
| Pressure gauge | **273** | bar |
| Pressure gauge (2nd) | **22** | bar |
| Pressure gauge (3rd) | **124** | bar |
| Output (throughput) | **1045** | kg/h |

Interpretation for sim: this is an extruder/laserfilter live panel — melt temp 105 °C shown at top [unsure: low for melt, may be a specific zone/water temp], main-drive 111 rpm at 54% load, 862 running hours, three pressures (273 / 22 / 124 bar — likely pre-filter melt pressure, a differential, and post-filter/pump pressure), throughput **1045 kg/h** (answers throughput magnitude for LIJN 6 — see Q9).

## Trend graph (center)
- Time axis: **21:54:50 → 22:11:29**, date 1-10-2024 (≈16 min window), x-tick labels 21:54:50 / 21:59:00 / 22:03:10 / 22:07:20 / 22:11:29.
- Left Y-axis scale: 0 … 600 (ticks 50,100,150,200,250,300,350,400,450,500,550,600).
- Right Y-axis scale: 0 … 250 (ticks 25,50,75,100,125,150,175,200,225,250).
- Legend / traces:
  - **Toevoer actief** (blue, square-wave, toggling 0/1) — "feed active" digital signal, pulsing on/off.
  - **PCU - vermogen** (orange, noisy, ~150–200 band) — PCU (pre-conditioning unit / compactor) power.
  - **PCU - temperatuur 1** (green, steady ~250 on left scale) — PCU temperature 1.
  - **AIS - positie** (yellow, flat ~90–100) — AIS position (Automatic Injection/feed Slide position, i.e. the ingangsschuif/PCU feed-slide position).

## Right-side control buttons (state panel)
- **AutoPro-control** (header)
- **Aan** (On) — greyed/active state box
- **Productie** (Production) — green bar under it (active/running)
- **Legen** (Empty/Purge)
- A blank/white button lower-right [illegible label].

## Bottom-of-bezel
- Plate: **LIJN 6**
- Partially visible large "**111**" repeated at very bottom (mirrors the 111 rpm value on a secondary readout) and a triangle warning icon bottom-right.

## Question hunt
- **Q9 (throughput kg/h):** LIJN 6 shows **1045 kg/h** output on this testrun. Supports ~1000+ kg/h per line magnitude.
- **Q16 (Bunker speed 200-800 unit):** not this screen; sticky note gives a *screw* setting 3–8 rpm (different device).
- **Q30 (units):** confirms Snelheid in **rpm** (111 rpm) with separate **%** load (54 %); power in **kW** (177,9); pressures in **bar**; output in **kg/h**. AIS-positie trended as a numeric (likely %).
- **Q31 (washer6 vals 0-6):** N/A here.
- Note: "PCU" = EREMA's Pre-Conditioning Unit (the compactor/geforceerde voeding zone); "AIS" position = feed-slide/ingangsschuif position (cross-ref EREMA-manual-5.3.3 ingangsschuifregelaar PCU).
