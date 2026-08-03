# EREMA HMI screenshot — LIJN 6 testrun LDPE (photo)

- **Source file:** `224_CeDo65 (3).pdf`
- **Doc id:** none (photo of EREMA BluPort/AutoPro HMI, wall-mounted, physical label plate "LIJN 6" below screen)
- **Type:** single-page photograph of live HMI, not a work instruction
- **Scope:** Lijn 6 (extrusieregeling / EREMA extruder + PCU compactor)
- **Screen title (Rx line):** "EREMA testrun LDPE 22.02.24"
- **Clock overlay top-left:** 3:42:05 / 19-2-2025 (note: title says testrun dated 22.02.24 but trend timestamps read 19-2-2025 — screenshot taken during a re-run/review)

## Left-hand vertical parameter column (pictogram + value + unit)
Verbatim, top to bottom, each with an icon glyph:
| Pictogram (gloss) | Value | Unit |
|---|---|---|
| clock | 3:42:05 / 19-2-2025 | (time/date) |
| gauge (temp) | 114 | °C |
| (power) | 230,7 | kW |
| screw / auger | 80 | rpm |
| % | 55 | % |
| hourglass/hours | 3251 | h |
| pressure ◇ | 234 | bar |
| pressure (boxed) | 20 | bar |
| pressure ◇ | 142 | bar |
| output arrow ⤷ | 1060 | kg/h |

## Trend graph (center)
- X-axis timestamps: 3:25:25, 3:29:34, 3:33:44, 3:37:54, 3:42:04 — all dated 19-2-2025
- Left Y-axis scale: 50..600 (steps of 50) — for red/green traces
- Right Y-axis scale: 0..250 (steps of 25) — highlighted markers green at ~250, yellow at ~200
- Legend (verbatim):
  - **Toevoer actief** (cyan) — "feed active" (on/off band at bottom, square-wave)
  - **PCU – vermogen** (red/orange) — "PCU power" (noisy ~250 trending)
  - **PCU – temperatuur 1** (green) — "PCU temperature 1" (~300 rising to ~330)
  - **AIS – positie** (yellow) — "AIS position" (flat line ~100)

## Top-right controls
- Numeric keypad 7 8 9 ← / 4 5 6 / 1 2 3 / 0 - . ESC ←
- Buttons partially cut off at right edge: "De…", "Num…"
- **AutoPro – control** button, **Uit** ("Off") button

## Right-hand live value tiles (verbatim)
| Label | Value |
|---|---|
| PCU-vulpeil ("PCU fill level") | 69 cm |
| PES-toerental ("PES speed") | 75 % |
| T… (cut off) | — |
| BC1-toerental | 100 % |
| EX1-vermogen | 157,0 kW [unsure: 157,0] |
| AIS-positie | 35 % |
| PCU-temp. 1 | 114 °C |
| EX1-toerental | 80 rpm |
| PCU-belasting ("PCU load") | 73 % |
| PCU-vermogen | 226,6 kW [unsure: 226,6] |
| EX1-JZ1 | 98 °C |
| EX1-belasting ("EX1 load") | 55 % |
| (selected/highlighted field, blue) | 235,0 kW |

## Machine mimic (bottom-right)
- Inclined conveyor/feed schematic drawn in light blue, "EREMA®" logo on the extruder body.
- Hopper with pellet-dots pictogram at top-right of mimic.

## Notes / partial text
- Top edge: yellow sticky-note fragment "...municeer dit met shiftleader en mail naar…" ("…communicate this with shiftleader and mail to…") — operator instruction annotation.
- Red hamburger menu icon bottom-left (3 red bars).

## Answers to open questions
- **Q9 (throughput kg/h):** Lijn 6 running at **1060 kg/h** (left column output) during LDPE testrun; EX1 80 rpm, PCU load 73%. Confirms lijn 6 ~1 t/h class.
- **Q30 (units):** EREMA HMI uses Vermogen in **kW** (EX1-vermogen 157 kW, PCU-vermogen 226,6 kW; left column 230,7 kW), Snelheid/toerental in **rpm** (80 rpm) AND **%** (BC1 100%, PES 75%), belasting/load in **%** (PCU 73%, EX1 55%), temp in °C, druk in bar, PCU-vulpeil in cm. So "%" and "rpm" coexist depending on the drive: main extruder EX1 shown as rpm; auxiliary drives (BC1 conveyor, PES) as %.
- **Q32 (softstarter power exports):** not a softstarter screen — this is EREMA AutoPro; power reported directly in kW.
