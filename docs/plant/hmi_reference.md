# HMI & instruction photo reference — full transcription

**Sources:** `assets/reference_photos/hmi/` (28 non-.import files) and `assets/reference_photos/instructions/` (2 files).
**Extraction date:** 2026-07-05 (first pass), re-verified 2026-07-05 (second pass).
**Rule applied:** every legible label, value, menu item, temperature, pressure and percentage transcribed; embedded photos described; illegible text marked `[unsure: best reading]`. Dutch kept verbatim, English gloss on first use.

**Second-pass verification note (2026-07-05):** all 32 hmi/ files + 2 instructions/ files were re-opened at full resolution. Every genuine screen's headline values were re-confirmed. Corrections applied this pass: (a) 3C errors row 3246 middle words resolved; (b) BC1 schematic box label is "BC1-verventil"; (c) the feeder SWI page is GENUINE (motion-blur, not AI-editing); (d) the ✦ glyph on several files is an app UI corner icon, not universally an AI watermark — genuine screens (3A laserfilter, 3C main/errors, lijn 6) carry it too, so ✦-presence alone does not demote a file. Files whose *fine print* remains untrustworthy are the AI-GENERATED concept images (LA1_3A.png, sorteerlijn_simplified.jfif, pelletizer drawing) and the heavily-processed washing_3A.png mimic.

## Reliability legend

Several PNGs in this folder were processed with Samsung **Galaxy AI generative edit** (sparkle ✦ watermark bottom-right corner) or are outright AI-generated concept images. AI processing *hallucinates plausible-looking text*, so fine print in those files is **not documentation evidence**. Each section carries one of these flags:

| Flag | Meaning |
|---|---|
| **GENUINE** | Real photo/scan, text is evidence |
| **AI-ENHANCED** | Real plant photo passed through AI upscale/edit — big numbers/layout trustworthy, fine print suspect |
| **AI-GENERATED** | Concept/illustration produced by AI — layout inspiration only, text is NOT plant data |
| **STOCK** | Genuine photo but NOT of the CeDo plant (marketplace/marketing imagery) — machine-type reference only |

---

## 1. `3A_HMI_laserfilter_screen.png` — EREMA laserfilter screen, lijn 3A

**Flag: AI-ENHANCED** (2572x1632, lightly processed; values consistent and legible).

EREMA TOUCH-style laserfilter (melt filter) screen. Clock top-left: **06:05:38 PM 28/01/2025**.

Value boxes (MP = melt pressure, MF = melt filter):
- **MP < MF: 207 bar** (pressure before filter)
- **Δ MP: 182 bar** (differential over filter)
- **MP > MF: 25 bar** (pressure after filter)
- **Motor: On**

Trend panel, 30-minute window **05:35:37 PM → 06:05:37 PM**, left axis 0–350, right axis 0–10. Legend:
- *Melt temperature* (cyan) — flat ≈ **253 °C**
- *Δ MP* (red) — ≈ 175–235 bar, sawtooth spikes
- *Motor 1 speed* (yellow) — square wave alternating 10 ↔ ≈6 (scraper/disc speed cycling)

Right side: 3D render of the laserfilter unit (gear pair, filter disc, blue motor labeled "1").
Bottom menu icons: home, filter diamond, alarm bell (red), Rx (recipes), trend, wrench (service).

**Physics takeaway:** before-filter 207 bar vs after-filter 25 bar → the laserfilter drops ~180 bar; the disc motor cycles between two speeds continuously.

## 2. `3C_errors_screen.png` — BluPort alarm list, LIJN 3C

**Flag: GENUINE** (photo of screen; tape label "LIJN 3C" below panel). Timestamp **29.9.2024 13:37:09**.

EREMA **BluPort** HMI. Recipe line: **Rx LDPE 800 kg/h 22.04.2024 IBN** (IBN = Inbetriebnahme/commissioning recipe).

Left sidebar instrument column (top→bottom):
- 110 °C / 124,2 bar [unsure: kW vs bar for second value]
- 0 rpm / 3 % / 2147 h (extruder stopped)
- 343 bar (before-filter melt pressure, red/alarm)
- 11 bar
- 69 bar
- 57 kg [partial: kg/h output]

**Storingstabel** (fault table — alarm nr, time, text):
| Nr | Tijd | Melding |
|---|---|---|
| 6522 | 13:37:09 | Snelwissel-filter 1 [MPF1] bedrijf niet vrijgegeven (quick-change filter 1 operation not released) |
| 6557 | 15:17:09 | Massadruk voor snelwissel-filter 1 [MPF1] te hoog - uitschakeling (melt pressure before quick-change filter 1 too high — shutdown) |
| 1017 | 13:16:38 | Filter-filter 2 zone 1 [MF2-Z1] verwarmingsstroomalarm (heating-current alarm) |
| 3246 | 15:16:08 | Selectievakje-Snelwissel-filter 1 zone 1 niet in orde (-P0.11) (checkbox — quick-change-filter 1 zone 1 not OK) [re-read 2026-07-05: middle words now legible, was [unsure]] |
| 73 | 15:15:38 | Schakelkast-oververhitting (+K1)) (control-cabinet overtemperature; trailing double-paren is on-screen) |

Sidebar re-read (2026-07-05, sharper): 110 °C / 124,2 bar · 0 rpm / 3 % / 2147 h · 343 bar (red alarm) · 11 bar · 69 bar · 57 kg/h. All eight sidebar units are the same glyph set as §3.

Bottom menu icons: X (close), grid, home, alarm bell (red), heart (diagnostics), wrench, trend, Rx, screen-with-lightning, ecoSAVE, stacked screens, skip-to-end.
Panel hardware: CAUTION sticker; physical buttons ⏻, ⇥, ⌀, heater.

**Takeaway:** 3C carries **two** melt filters in series (MPF1 quick-change + MF2), and over-pressure before the quick-change filter trips the line.

## 3. `3C_extruder_hmi.png` — BluPort main screen, LIJN 3C (02:17)

**Flag: GENUINE.** Timestamp **2:17:25 21-12-2024**. Wide BluPort overview screen, tape label "LIJN 3C".

Left sidebar: PCU (Preconditioning Unit / snijverdichter) **110 °C**, **215,1 kW**; screw **102 rpm**, **60 %**, **3553 h**; before-filter **284 bar** (orange); door-icon **26 bar**; after **203 bar**; output **1294 kg/h**.
Recipe: **Rx LDPE 800 kg/h 22.04.2024 IBN**. AutoPro-control: **Uit** (off). **PCU-vulpeil 265 cm** (fill level).

Schematic value boxes:
| Label | Waarde |
|---|---|
| PES-toerental | 75 % |
| TEU-toerental | 25 % |
| EX1-vermogen | 212,2 kW |
| AIS-positie (intrekschuif) | 70 % |
| PCU-temp. 1 | 110 °C |
| PCU-belasting | 68 % |
| PCU-vermogen | 215,1 kW |
| EX1-toerental | 102 rpm (setpoint field **102** highlighted) |
| EX1-belasting | 60 % |
| EX1-IZ1 | 93 °C |
| BC1-toerental | 60 % (schematic box label reads **"BC1-verventil"** — a fan/valve drive; sidebar/summary uses BC1-toerental) |

Trend (x-axis 2:00:45 → 2:17:24, left axis 0–600, right 0–250): *Toevoer actief* (cyan square wave 0–50, infeed active), *PCU-vermogen* (red ≈215), *PCU-temperatuur 1* (green ≈260 display units), *AIS-positie* (yellow ≈170 display units).

Stickers above screen: white **"GEBRUIK DEZE MACHINE NIET ZONDER VEILIGHEIDSCONTROLE IN POSITIE"** (small print: "…WAARSCHUWINGSBORD NIET VERWIJDEREN OF MISVORMEN. 1 holländisch"), yellow **"STAAT / Afzuiging compactor / !!! AAN !!!"** (compactor extraction must be ON).

## 4. `3C_extruder_hmi.pdf` — duplicate of §3

**Flag: GENUINE. Duplicate of `3C_extruder_hmi.png`** (same capture, 2:17:25 21-12-2024, identical values). PDF renders slightly sharper; confirmed both stickers verbatim as in §3.

## 5. `3C_extruder_hmi_2.png` — BluPort main screen, LIJN 3C (02:34)

**Flag: GENUINE.** Same panel, **2:34:38 21-12-2024** (17 min later).

Sidebar: **110 °C**, **228,3 kW**; **113 rpm**, **68 %**, **3554 h**; **298 bar**; **23 bar**; **202 bar**; output **1444 kg/h**. PCU-vulpeil **265 cm**.
Boxes: PES-toerental **80 %**, TEU-toerental **30 %**, EX1-vermogen **242,2 kW**, AIS-positie **70 %**, PCU-temp. 1 **110 °C**, PCU-belasting **72 %**, PCU-vermogen **228,3 kW**, EX1-toerental **113 rpm**, EX1-belasting **68 %**, EX1-IZ1 **97 °C**, BC1-toerental **60 %**. Trend x-axis 2:17:59 → 2:34:38.

**Takeaway (with §3/§7):** operator pushed screw 102→113 rpm and PES 75→80 % → output rose 1294→1444 kg/h while before-filter pressure rose 284→298 bar. Live operating envelope for the sim.

## 6. `3C_extruder_hmi_2.pdf` — duplicate of §5

**Flag: GENUINE. Duplicate of `3C_extruder_hmi_2.png`** (same capture 2:34:38; PDF confirms EX1-vermogen 242,2 kW, PES 80 %, TEU 30 %).

## 7. `extruder_3c.pdf` — BluPort main screen, LIJN 3C (02:20) — third capture

**Flag: GENUINE.** NOT a duplicate: same night, **2:20:32 21-12-2024** (between §3 and §5).

Sidebar: **110 °C**, **217,9 kW**; **105 rpm**, **63 %**, **3553 h**; **294 bar**; **27 bar**; **206 bar**; output **1368 kg/h**. PCU-vulpeil **268 cm**. AutoPro-control: Uit.
Boxes: PES-toerental **75 %**, TEU-toerental **25 %**, EX1-vermogen **225,5 kW**, AIS-positie **70 %**, PCU-temp. 1 **110 °C**, PCU-belasting **69 %**, PCU-vermogen **217,9 kW** (second field **229,2 kW**), EX1-IZ1 **94 °C**, EX1-toerental **105 rpm**, EX1-belasting **63 %**, BC1-toerental **60 %**. Trend x-axis 2:03:51 → 2:20:30.
Stickers identical to §3 (both confirmed sharp in this PDF).

**Three-point ramp series 3C, 21-12-2024:** (102 rpm → 1294 kg/h @ 284 bar), (105 rpm → 1368 kg/h @ 294 bar), (113 rpm → 1444 kg/h @ 298 bar).

## 8. `3C_extruder_hmi_settings.png` — BluPort system menu, LIJN 3C

**Flag: GENUINE but blurry** (video frame). Timestamp **15:37:36 29-9-2024**. Recipe header same Rx LDPE 800 kg/h 22.04.2024 IBN.

Menu grid of subsystem tiles (icons match sidebar glyphs): *Doseer…* [unsure: Dosing], *Materiaaltoevoer / Material Feeding Unit*, *Extruder 1*, *Smeltfilter 1* (diamond icon), *Smeltpomp 1* [unsure: melt pump], *Smeltfilter 2* (second diamond icon, second row), second *Doseer/infeed* tile (third row), *Granulator/complete system* tile (top right).
Sidebar (line nearly stopped): 110 / **121,0** [unsure: kW]; **0 rpm**, **0 %**, **2047 h**; **276 bar**; **11 bar** [unsure: was read as 82 bar in PNG, 11 bar in PDF render]; **71 bar** [unsure]; output **52 kg/h** [unsure: 48–52].
Bottom menu row: X, grid (active), home, alarm bell, heart, wrench, trend, Rx, screen-lightning, **ecoSAVE** logo, stacked screens, skip-to-end.

**Takeaway:** confirms 3C machine composition tiles: infeed → material feeding unit → Extruder 1 → Filter Unit 1 → Pump Unit 1 → Filter Unit 2 → granulator, plus ecoSAVE energy package.

## 9. `3C_extruder_hmi_settings.pdf` — duplicate of §8

**Flag: GENUINE. Duplicate of `3C_extruder_hmi_settings.png`** (same 15:37:36 29-9-2024 frame, worse legibility; sidebar read 110 / 121,0 · 0 rpm · 0 % · 2047 h · 276 bar · 11 bar · 71 bar · 52 kg/h).

## 10. `6_extruder_HMI.png` — BluPort main screen, LIJN 6

**Flag: GENUINE.** Tape label "LIJN 6". Timestamp **3:42:05 19-2-2025**. Recipe: **Rx EREMA testrun LD[PE] 22.02.24**.

Sidebar: **114 °C**, **230,7 kW**; **80 rpm**, **55 %**, **3251 h**; **234 bar**; **20 bar**; **142 bar**; output **1060 kg/h**. AutoPro-control: Uit. **PCU-vulpijl [sic, screen typo for vulpeil] 69 cm**.
Numeric keypad dialog open over screen (7 8 9 / 4 5 6 / 1 2 3 / 0 . ESC / Del / "Nu") — operator entering PCU-vermogen setpoint: current **226,6 kW**, edit field **236,0 kW** highlighted.
Boxes: PES-toerental **75 %**; EX1-vermogen **157,0 kW**; AIS-positie **35 %**; PCU-temp. 1 **114 °C**; PCU-belasting **73 %**; EX1-hZT-1 **98 °C**; EX1-vermogen (second box) **235,0 kW**; EX1-toerental **80 rpm**; EX1-belasting **55 %**; BC1-toerental **100 %**.

**Takeaway:** lijn 6 runs the same BluPort generation as 3C; ~1060 kg/h at 80 rpm; PCU bunker much emptier (69 cm vs 265 cm on 3C).

## 11. `extruder_hmi_3a_or_3b.jpg` — older EREMA trend screen, lijn 3A or 3B

**Flag: GENUINE** (Samsung SM-G950F EXIF, 2024-02-02 22:22:56; shot rotated 90°). Name tape on panel: "Peter 2…" [partial].

Older-generation EREMA HMI (pre-BluPort, matches lines 3A/3B). Trend screen, timestamps on screen **22:24:07** and **22:07:28, 2/02/2024**.
Trend legend (Dutch, SV = snijverdichter/cutter-compactor):
- *SV-temperatuur (°C)* — green, ≈200 on right axis
- *intrekschuif (%)* (intake slide = AIS) — yellow, ≈175
- *SV-vermogen (kW)* — red
- *toevoer aan* — cyan square wave (infeed on/off)
Right axis 25–225, left axis 100–400.
Right side: line schematic with value boxes all reading 0 (line idle), button *toevoer keuze* [unsure: infeed selection].

**Takeaway:** 3A/3B nomenclature uses SV-* (snijverdichter) and "intrekschuif" where 3C/6 BluPort uses PCU-* and "AIS-positie" — same physical quantities.

## 12. `EREMA_TVEplus_schematic_zone_temps.jpg` — EREMA touch HMI (STOCK photo)

**Flag: STOCK — NOT CeDo.** 640x480 MachinePoint (used-machinery marketplace) photo of a TVEplus at a Slovak plant (POZOR = Slovak "attention" stickers: only trained personnel).

EREMA touch HMI, header **"LLDPE flakes 400kg/h"**, clock 10:07, 27.1.2023. Machine schematic screen with readable values:
- Cutter/compactor: **75 %**, **56.4** [unsure: kW], **106 °C**
- Before filter: **256 °C / 210 bar**; after: **265 °C** [unsure] / **225 °C**
- Melt pump: **27 kW**
- Extruder zone boxes along barrel: ≈ **134 / 185 / 191 / 196 / 190 / 186 / 220 °C** [unsure: small text]
Panel hardware: e-stop, ⏻ key switch, login key, screw-symbol button, heater button.

**Q15 caveat:** this is machine-type reference only; it does NOT document CeDo zone temperatures. It does show the typical EREMA pattern: lower feed-zone temp, rising toward die, hottest at the filter/die end.

## 13. `EREMA_TVEplus_pedestal_with_laserfilter.jpg` — pedestal + laserfilter (STOCK)

**Flag: STOCK — NOT CeDo** (MachinePoint; handwritten "4052 erema" tag). HMI pedestal (numeric keypad dialog open) in front of the large cylindrical **laserfilter housing** with EREMA swirl logo and corrugated discharge hose (the "lump" discharge — matches the sim's laser-filter lump_cart). Slovenian/Slovak stickers VROČE! (hot), POZOR. Machine-shape reference for modelling the laserfilter body.

## 14. `EREMA_ecoSAVE_mini_controller.jpg` — ecoSAVE display (STOCK)

**Flag: STOCK** (EREMA marketing). Small ecoSAVE energy display; rows with checkmarks: **65 kW**, **83 %**, **124 bar**. Reference for the ecoSAVE widget only.

## 15. `EREMA_intarema_cabinet_buttons.webp` — INTAREMA cabinet (STOCK)

**Flag: STOCK** (EREMA marketing; EXIF NIKON D7000, 2023-06-26). INTAREMA HMI cabinet: touchscreen showing cutter-compactor + extruder temp-zone schematic, ecoSAVE logo, physical button row (e-stop, standby, 2 illuminated pushbuttons, heater button), pedestal label "+P1". Button-panel layout reference for 3C/6-generation cabinets.

## 16. `EREMA_regrindpro_dual_screen.webp` — TVEplus RegrindPro (STOCK)

**Flag: STOCK** (marketing). Machine placard "…lus® RegrindPro" (= TVEplus RegrindPro). Main EREMA panel on top + secondary small touchscreen below it; HEISS! (hot) labels. Shows EREMA sometimes fits a second small screen at the filter.

## 17. `erema_extruder_schematic_4zone.svg` — hand-made schematic

**Flag: GENUINE (project asset, hand-authored SVG, no plant data).** 800x300 viewBox. Elements: extruder body rect (150,100→700,200), hopper parallelogram, screw rect + dashed centerline, 4 heating-zone rects `id="zone1"…"zone4"` (x=220/350/480/610), pelletizer circle (cx 725) + die triangle. CSS classes: `.extruder-body .hopper .heating-zone .pelletizer .screw .outline` with fixed hex colors (#CFD8DC, #B0BEC5, #FFB74D, #78909C, #90A4AE, #37474F outlines). Usable directly as a UI texture template.

## 18. `_extruder_HMI.png` — older EREMA panel in front of cyclone

**Flag: AI-ENHANCED (✦ sparkle).** Older EREMA HMI panel (same generation as §11) standing before a cyclone. Screen title readable: **"Extruder Zone 1-8"** with two dialog boxes, an extruder-train schematic, and 6 menu buttons (readable fragments: *Cutter…*, *Set temperatures*, *Process values*, *Errors* — rest illegible even at 4x zoom crop; AI-garbled). Physical: E-STOP, key switch, 3 buttons.
Bottom of frame: floor with spilled pellets and a drain grate under blue cabinets (set-dressing reference).

**Q15 relevance:** the older 3A/3B-generation screens expose **8 extruder zones** ("Extruder Zone 1-8").

## 19. `LA1_3A.png` — cyclone/platform area, lijn 3A

**Flag: AI-GENERATED/heavily edited (✦).** Cyclone + service platform + blue control box, person in cleanroom suit. All signage is hallucinated English ("CAUTION: PLATFORM UNIT 4A HIGH SURFACE TEMP MINIMUM CLOTHING REQUIRED", "MODEL O-FR-100G SER NO…", "TANK-A101") — **not documentation evidence**. Geometry/mood reference only.

## 20. `washing_3A.png` — wash-line HMI, lijn 3A

**Flag: AI-ENHANCED (✦), most screen text garbled** (hallucinations: "C.O.A.D.", "Ventsibility dogemein", "Colm-Recycling", "Dosing voirvest 38.5%", "Powter MOL 15.0%", "I/O Leivo 12 ubpm", "Power 10.0%", "Temp avalon LET.0%", "Fageritges 1.8.70 n%", "Compzsrtor", "12 oals", "Oprenor Settings").

**GENUINE element:** crisp printed note taped left of the screen: **"Tijdens starten hoort de doseerschroef M1A op 0% te staan."** (during startup the dosing screw M1A must be at 0 %), with an arrow to the *M1A Dosing Screw* box showing **0%**.
Semi-legible real-ish labels on the mimic: M1A Dosing Screw, P11B screws, MQ fans, P12A 0%, P12B 0%, AME tank "31", 85 %, M12B, P11P, P1B, 157 °C [unsure], L30 °C [garbled], Tank Level 0.0 %, PE/PEZ/PV/P1A/P12, 5 %, AUTO. Menu: Process Overview, Trends, Alarms, Stop Settings.

**Q3 relevance:** the physical note names the dosing screw **M1A** (not M11a).

## 21. `sorting_line_3A_3B_center_of_HMI.png` — printed SOP page (Tomra/TITECH switching)

**Flag: GENUINE content, lightly AI-processed** (photo of a printed SOP table; body text readable).

| Handeling | Instructie |
|---|---|
| Terug switchen Tomra's naar titech en Tomra's | "Schakel met de knop 2040/2035 terug op knop 2040 door daarop te drukken zodat de folie weer naar beide sorteerlijnen gaat." |
| Reiniging Tomra 1 of Tomra 2 | "Voor de Tomra reiniging moet je de sorteerlijn eerst op leegdraaien zetten. Zet de knop 'empty' van '0' naar '1'." |
| (vervolg, met rood kruis = veiligheid) | "Nadat er geen folie meer over de sorteerbanden ko[mt] … de reiniging van Tomra 1 of 2 starten, op exact deze[lfde manier] als de titech's vanaf punt 3 tot en met punt 5." |
| Opstarten | "Zet de dosering/bunker weer aan op het beeldscherm. Zet de knop 'empty' van '1' naar '0'." |

Screenshot mimic embedded in the page shows conveyor band numbers: **3717, 37:0[cut], 2040, 2025 (yellow), 2031, 2035, 2020**, plus container symbols. The **2040/2035** button routes folie to both sorting lines vs one.

## 22. `HMI_sorteerlijn_bunker.jpg` — bunker/dosing HMI, sorteerlijn

**Flag: GENUINE** (software tag "Google", plausible real screen). German/Dutch mixed UI, DE/NL flag buttons.

Left table **"speed autom."** — 10 rows setpoint/limit: *setpoint 1 empty* … *setpoint 10 full*, all showing 0 / 0. Below: *Bereken Snelheid* (calculate speed) on/off toggle — **off**; **"bunkersnelheid berekend: 875"**.

Right column **"bunkersnelheid setpoint"** (bunker speed setpoints per feed mode):
| Modus | Setpoint |
|---|---|
| Beide (both 3A+3B) | **875** |
| Zonder 3A | **875** |
| Zonder 3B | **875** |
| Vertraging (delay) | 30 sec / 0 sec |
| Pers alleen (baler only) | **200** |
| Vert omschak. (switchover delay) | 75 sec / 0 sec |
| Vert terug (return delay) | 30 sec / 30 sec |

"filling setpoint / actual value **258**". Belt readouts: actual **86** / setpoint **125**; actual **108** / setpoint **70**.
Bottom button row: Auto / Hand / horn / I / 0 / *Nummer richtlijnen 0* [unsure] / *Enkeling-Stop* / reset / *Overzicht* / *Start scherm*.

**Q16:** bunker speed 200–875 shown **unitless** on screen (no unit label anywhere on the panel).

## 23. `sorteerlijn_partial.png` — sorting-line overview mimic

**Flag: AI-ENHANCED (✦), band numbers plausible, fine text partly garbled.**

Process mimic with conveyor band numbers: **3006, 3002 (multiple), 3008, 3010 ×2, 3107 ×3, 3108, 3103, 3104, 3004 ×2**. Boxes labelled "Sorteer", "Sorteer-order", **"Zwanenhals"** (gooseneck, light-blue box). *Herstart* dialog: "Programma: 1 / Product type: Standard / Bestemming: Lane 4 / Aantal: 100". Status list: "5170 Transportband in w[erking] / 4003 Sorteercriteria OK / 4003 Sorteed aanwezig [unsure] / 1251 Product aanwezig / Status: 1-1-1". Winder graphic with STOP/DAMP [unsure]. Menu: red STOP, *Nummer richtingen* [unsure], C, Enkeling-Stop, reset, Overzicht, Start scherm.

Note: this mimic's menu row matches `HMI_sorteerlijn_bunker.jpg` (§22) — same SCADA family.

## 24. `sorteerlijn_simplified.jfif` — AI concept image

**Flag: AI-GENERATED.** Generic green process-HMI concept; garbled text ("TAN (78%)", "FILTER 1 AP (1.2 NAR)", "POMP-1 ACTIVE", "PRUSOM GORWUM"). Physical button row: POWER / RUN / FAULT / ALARM1 / ALARM2 / [garbled] / MUTE / RESET / TEST + EMERGENCY e-stop. Layout inspiration only — **no plant data**.

## 25. `sorteerlijn_overzicht.pdf` — Cedo-PROD-SWI-049 "Opstarten sorteerlijn", page 2 of 2

**Flag: GENUINE (official SWI scan).**
Header: **Cedo-PROD-SWI-049 — Opstarten sorteerlijn** (starting up the sorting line), PROD Department, SWI, **Issue No. 01, Issue Date 4-8-2022, Author PROD Dept, Approved By Peter Scheffer, Page 2 of 2**. (Page 1 not present in this file.)

| Nr | Titel handeling | Pictogram | Omschrijving |
|---|---|---|---|
| 5 | Controleren hekwerken | zicht (eye) | "Controleer of de hekwerken dicht zijn en geen werknemers achter de hekwerken." (check fences closed, nobody behind them) |
| 6 | Sorteerlijn opstarten | geluid (ear) + zicht | "Start de sorteerlijn op: **1: druk de automaatknop in (deze licht op) 2: druk op de voorverwarmknop. 3: Als de knop op het scherm groen wordt, druk dan de groene drukknop in.** en blijf er even bijstaan voor te kijken of er iets fout loopt. Als er een storing is is dit te zien op het bedieningspaneel. Los deze eerst op voordat de sorteerlijn opgestart word." |

Supporting photo (step 6): the bunker HMI cabinet — screen showing the green process mimic (same screen family as §22/§23), a row of ~9 small pushbuttons below it, and a yellow-collared e-stop at the bottom.
Footer pictogram legend: *Functie* (hand), *Geluid* (ear), *Zicht* (eye), *LET OP: Veiligheid* (red cross), *LET OP: Kwaliteit* (green diamond), *TIP* (blue dot).

## 26. `kufferaths_line1.png` — Kufferath DRD 1 / DRD 2 dryer HMIs, lijn 1

**Flag: GENUINE** (two German screens side by side). Date on screens: **Samstag 29. Juni 2024, 13:41:38**.

| Parameter | DRD 1 | DRD 2 |
|---|---|---|
| Motorlast DRD (motor load) | **65 %** | **88 %** |
| Schritt (step) | **6: Entleeren** (emptying) | **3: Befüllen** (filling) |
| Schrittlaufzeit (step runtime) | 43 s | 48 s |
| Trockenzeit (drying time) | 30 s | 30 s |
| Befüllstop DRD (fill stop at) | 90 % | 90 % |
| Entleerstop DRD (empty stop at) | 60 % | 60 % |
| Temperatur Sollwert DRD | 40 °C | 40 °C |
| Trocknungs-Automatik | EIN / [AUS active] | EIN / [AUS active] |
| Heizregister (heater bank) | [EIN active] / AUS | [EIN active] / AUS |
| Taktzeit/Pausezeit Entleerschieber | 2 s / 4 s | 2 s / 4 s |
| Laufzeit Beschickungsschieber (feed slide travel, Offen/Geschlossen) | 12 / 120 | 12 / 120 |
| Laufzeit Entleerschieber | 12 / 12 | 12 / 12 |
| Korrekturwert Temperatur DRD | +13 °C | +15 °C |
| Korrekturwert Temperatur Entstaubung (dedusting) | +83 °C | +98 °C |
| Silo voll (silo full) | 3 s | 3 s |
| Standby | 3 s | 3 s |

Menus: MAIN / PARAMETER / HANDBETRIEB and ZYKLUSDATEN / SYSTEM / ALARME.

**Takeaway:** lijn 1 dryers run a numbered step cycle (…3 Befüllen → 6 Entleeren…), batch-style: fill to 90 %, dry 30 s at 40 °C setpoint, empty to 60 %.

## 27. `shredder_2_HMI.png` — shredder 2 pushbutton panel

**Flag: AI-ENHANCED, selector fine print partly garbled.**

Panel controls (top→bottom):
- Key switch **"BESTURING"** (control) — position UIT (off)
- Selector **"I = Auto / II = Hand / III = Onderhoud"** (maintenance)
- Green illuminated button **"Automaat start"**
- **"WERKSTROOM: 0 UIT / I AAN"** (work current off/on)
- Garbled selectors: "[Z]INDE i=schleruit il=verout" [unsure], "STKE I=naar binnen III=naar buiten" [unsure: something = inward/outward]
- **"NOODSTOP: 1. INDRUKKEN 2. VERGRENDEL"** (e-stop: press, then lock) — red mushroom button, green indicator lamps
Bottom of frame: wooden post with white sensor and yellow lever near the shredder infeed; white/blue film shreds over a red edge (AI-artifacted).

## 28. `_e_kast.png` — MCC cabinet in production hall

**Flag: AI-ENHANCED (✦), all label text garbled.** Hall with silo/cyclone and catwalks; cream MCC (motor control center) cabinet: small HMI screen (unreadable), 4 rows of illuminated buttons, e-stop, 2 gauges + 2 dials, black main-switch lever, garbled CAUTION sticker. Foreground: green LPG forklift (brand garbled "GESFEVC"), pallets, yellow floor lines. Set-dressing/geometry reference only.

## 29. `e-kast_line_1.png` — MCC panel row, lijn 1

**Flag: AI-ENHANCED (✦).** Row of light-grey MCC panels on a steel plinth with louvered vents; labels "…L 1-A", "PANEL 1 B" [garbled]; small Siemens-style HMI (green table + bar chart, unreadable); button rows; e-stop with yellow tag; red interlock lever; overhead cable loom and dust pipe; floor debris. Geometry reference for lijn 1 electrical row.

## 30. `instructions/line_3ABC_6_feeder_operator_instructions.png` — SWI page: balen opzetten (bale feeding)

**Flag: GENUINE (re-read 2026-07-05).** Correction to prior note: the ✦ bottom-right is the app UI glyph, not proof of AI editing; rows 5–6 body text is **motion-blur/ghosting from the handheld photo**, not AI hallucination — the photos are real plant photos, lightly blurred, not "AI-smeared." Inner page of an SWI-format table (no header block on this page), header row + rows 3–6. Columns (header now fully legible): **nr / Titel handeling / Let op / Omschrijving handeling / Ondersteunende foto / schets**.

| Nr | Titel | Pictogrammen | Omschrijving | Foto |
|---|---|---|---|---|
| 3 | Zet de baal m.b.v. heftruck op de transportband | zicht, veiligheid | "Zet de baal met beleid op de band, niet laten vallen. Rij met heftruck rustig naar voren en niet tegen band aan rijden." | Green forklift placing a film bale onto the wide flat infeed conveyor (blue side walls, yellow guard post, red fire-extinguisher pictogram on wall) |
| 4 | Baal loslaten | zicht, veiligheid | "Maak de klem van de heftruck los en rij naar achter, de baal valt nu uit elkaar aan beide kanten. En wel in lengte richting van de band." Sketch: blue rectangle (baal) with green arrows to both sides. | Bale fallen apart lengthwise on the conveyor |
| 5 | Baal verkeerd op gezet | zicht | "Als een baal verkeerd is opgezet dan zal deze zich gaan [klemmen tegen de schuine wand van de band … niet laten/extra verlies op]" [unsure: heavily ghosted]. Ends: "Op de foto staat de baal correct." | Strapped bale sitting at the foot of the inclined conveyor section against blue wall |
| 6 | Aantal balen op de transportband | zicht, kwaliteit (groene ruit), 2× TIP (blauwe stip) | "Om de kwaliteit van opzetten te waarborgen mag de band niet geheel vol staan met balen, anders: • Valt band thermisch uit (belt trips on thermal overload) • Brugvorming in shredder (bridging in the shredder). **Afstand tussen de balen 0,5 meter.**" | Long inclined feeder conveyor climbing toward the shredder with spaced bales; hall with blue partition walls |

**Sim-relevant rules:** bales must be released so they break apart lengthwise; keep **0,5 m spacing**; overfilling the band causes thermal trip of the conveyor or bridging in the shredder — two ready-made failure modes.

## 31. `instructions/pelletizer_instructions.png` — "Messen slijpen doe je ook met plezier" (pelletizer knives)

**Flag: AI-GENERATED infographic from operator input** (Galaxy-AI/LLM-produced; literally contains "[cite: user input]"). The *facts* were supplied by the operator; the drawing is synthetic.

Title: **"Messen slijpen doe je ook met plezier"** (knife sharpening is also done with pleasure — wordplay).
Diagrams: new knife (flat blade, straight edge, mounting hole) ×4; used knife (wavy/toothed edge); bottom row edge profiles labelled *edge*, *Alignment*, "Nieuw / Nauwkeurig" (new/accurate) vs "Gebruikt / **Foutief / Beschadigd**" (used/faulty/damaged); hatched **matrijsplaat** (die plate) with scratch marks labelled "Krassen achter / beschadigingen".

**Onderhoudsspecificaties** box:
- een nieuw mes is plat (a new knife is flat)
- de snijkant is recht (cutting edge straight)
- een gebruikt blad is **gegolfd/getand** (used blade is wavy/toothed)
- de snijkant is **niet meer** recht
- Onderhoudsinterval: **4 stuks** (knives per set/interval) [unsure: phrasing ambiguous — likely 4 knives replaced per maintenance]
- Resultaat: "Het mes laat krassen achter beschadigingen op de matrijsplaat" (worn knife scratches/damages the die plate)
- **Vereist gereedschap voor mesvervanging: Maat 7 dopsleutel** (size-7 socket wrench) [cite: user input]

**Sim-relevant:** pelletizer knife wear (flat→wavy) degrades pellets and damages the die plate; replacement = 4 knives, size-7 socket.

---

## Cross-file syntheses

- **3C operating envelope (21-12-2024, Rx LDPE 800 kg/h):** 102→105→113 rpm gives 1294→1368→1444 kg/h at 284→294→298 bar before-filter; PCU steady 110 °C; PCU-vulpeil 265–268 cm; AIS 70 %; BC1 60 %. The "800 kg/h" in the recipe name is the commissioning rating — the line actually ran 1.3–1.4 t/h.
- **Lijn 6 (19-2-2025, testrun recipe):** 80 rpm → 1060 kg/h at 234 bar; BC1 100 %; PCU-vulpeil only 69 cm.
- **Terminology map:** older 3A/3B HMIs: SV-temperatuur/SV-vermogen/intrekschuif; BluPort 3C/6: PCU-temp/PCU-vermogen/AIS-positie. Same quantities.
- **Units (Q30):** vermogen = kW; toerental = rpm (extruder screw) or % (PES/TEU/BC1 drives); belasting = %; melt pressures = bar; PCU-vulpeil = cm; output = kg/h.
- **Filters:** 3C shows a two-filter train (Smeltfilter 1 quick-change "snelwissel" + Smeltfilter 2) plus melt pump; 3A shows an EREMA laserfilter screen with ~180 bar differential and cycling scraper motor.
- **AI contamination warning:** LA1_3A.png, sorteerlijn_simplified.jfif and pelletizer_instructions.png are AI-generated imagery; washing_3A.png, _extruder_HMI.png, shredder_2_HMI.png, _e_kast.png, e-kast_line_1.png, sorteerlijn_partial.png, 3A_HMI_laserfilter_screen.png, sorting_line_3A_3B_center_of_HMI.png and the feeder SWI page carry the Galaxy-AI edit mark — treat their fine print with suspicion; only values cross-confirmed by genuine files were used in the syntheses above.
