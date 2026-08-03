# PHOTO — EREMA BluPort HMI, LIJN 6, testrun LDPE (2-10-2024 01:04, live values)

- **Source PDF:** `317_CeDo23 (3).pdf` (1 page, photo of HMI touchscreen)
- **Type:** Photograph of EREMA BluPort control-panel screen, **LIJN 6** (bezel plate). Same panel/recipe as `316_CeDo21` but a later timestamp; the sticky note is fully legible here.
- **Scope:** Live-values + trend-graph overview during "EREMA testrun LDPE 22.02.24" recipe.

## Sticky note (taped above screen) — VERBATIM, now fully legible
> **Laserfilter uittrekschroeven setting**
> 3 rpm minimum
> 8 rpm maximum
> Mochten er settings gewijzigd worden communiceer dit met shiftleader en mail naar CI

EN: "**Laserfilter pull-out screws (discharge/extraction screws) setting** — 3 rpm minimum, 8 rpm maximum. Should settings be changed, communicate with the shift leader and mail to CI."
- RESOLVES the ambiguous first word from `316_CeDo21`: it is **"Laserfilter uittrekschroeven"** = the laserfilter's contaminant-discharge (uittrek/extraction) screws that convey rejected melt/dirt out of the rotary laserfilter. Operating band **3–8 rpm**.

## Header / recipe
- Clock: **1:04:32**, date **2-10-2024**
- Recipe (Rx): **"EREMA testrun LDPE 22.02.24"**
- Branding: **BluPort · EREMA**

## Left column live values — verbatim
| Icon (meaning) | Value | Unit |
|---|---|---|
| Temperature | **10[6]** | °C [reads 106; unsure last digit] |
| (power) | **21[3],7** | kW [unsure: "213,7" — first digits faint] |
| Screw speed | **97** | rpm |
| Load | **46** | % |
| Hours | **865** | h |
| Pressure 1 | **245** | bar |
| Pressure 2 | **20** | bar |
| Pressure 3 | **107** | bar |
| Output | **1112** | kg/h |

Cross-check vs `316_CeDo21` (22:11 on 1-10-2024): rpm 111→97, load 54→46 %, hours 862→865, P1 273→245, P2 22→20, P3 124→107, output 1045→1112 kg/h. Consistent same-line trend a few hours apart.

## Trend graph (center)
- Time axis: **0:47:53 → 1:04:32**, date 2-10-2024 (x-ticks 0:47:53 / 0:52:03 / 0:56:13 / 1:00:22 / 1:04:32).
- Left Y-axis: 0…600 (steps of 50). Right Y-axis: 0…250 (steps of 25).
- Traces (same legend as 316):
  - **Toevoer actief** (blue square-wave, 0/1) — feed active, pulsing.
  - **PCU - vermogen** (orange, ~180–220 band) — PCU power.
  - **PCU - temperatuur 1** (green, flat ~250) — PCU temperature 1.
  - **AIS - positie** (yellow, flat ~95) — AIS/feed-slide position.

## Right-side control buttons
- **AutoPro-control** (header)
- **Uit** (Off) — box below (note: `316` showed "Aan"/"Productie"; here only "Uit" visible, production panel not lit — line idling/between states).
- Blank white button lower-right [illegible].

## Bottom
- Bezel plate: **LIJN 6**.

## Question hunt
- **Q9 (throughput):** LIJN 6 output **1112 kg/h** here (vs 1045 kg/h in 316). Confirms line 6 runs ~1000–1100 kg/h on LDPE testruns.
- **Laserfilter uittrekschroeven:** operating band **3–8 rpm** (from sticky note) — useful sim parameter for the laserfilter discharge auger. Cross-ref laserfilter docs (PROD-SWI-074, TRAIN-de-laserfilter-3A-typen, GUIDE-laserfilter-zeefplaten).
- **Q30 (units):** rpm / % / kW / bar / kg/h confirmed as in 316; AIS-positie numeric.
