# EREMA BluPort HMI — alarm/fault list, panel labeled "LIJN 3C"

- **Source file:** 187_CeDo87 (3).pdf (1 page, photo of EREMA BluPort HMI, fault-list page)
- **Doc id / slug:** OTHER-erema-bluport-alarmlist-LIJN-3C
- **Doc type:** Photograph of EREMA BluPort touchscreen showing the "Storingstabel" (fault/alarm table); physical label plate below the screen reads **"LIJN 3C"**
- **Timestamp:** 15:37:09, 29-9-2024 (29 Sep 2024)
- **Recipe/header:** **"℞ LDPE 600 kg/h  22.04.2024 IBN"** — active recipe = LDPE at 600 kg/h, recipe dated 22-04-2024, "IBN" = Inbetriebnahme (commissioning) recipe. Top-right branding: **"BluPort  EREMA"**.

## Left column live values (VERBATIM, low-res)
| Pictogram | Value | Unit |
|---|---|---|
| Circle S-swirl (screw) | 110 | °C |
| (same) | 124,2 | kW |
| Coils | (blank) | rpm |
| (same) | 3 | % |
| (same) | 2147 | h |
| Diamond ◆₁ | 343 | bar (shown in red = alarm) |
| Boxed ⊡ | 11 | bar |
| Diamond ◆₂ | 60 | bar |
| Output ⤶ | 57 | kg/h |

(Note: throughput 57 kg/h and speed 3 % = line nearly stopped / tripped, consistent with the melt-filter pressure alarm at 343 bar.)

## Storingstabel — fault list (VERBATIM best-reading, red=active alarms)
| Nr. | Tijd | Storingstekst (fault text) |
|---|---|---|
| 6522 | 15:37:09 | **Smeltfilter 1 [MF1] bedrijf/net vrijgeven** (Melt filter 1 operation/release) — highlighted blue (selected) |
| (----) | 15:37:09 | **Smeltdruk voor smeltfilter 1 [MP < MF1] te hoog – uitschakeling** (Melt pressure before melt filter 1 too high – shutdown) — red |
| 5407 | 15:26:38 | **Smeltfilter 2 zone 1 [MF2-Z1] verwarmingsstroomalarm** (Melt filter 2 zone 1 heating-current alarm) — red |
| 6240 | 15:48:00 | **Selectiviteitsmodule 1 niet in orde (-F0.11)** (Selectivity module 1 not OK / fault -F0.11) — red |
| 73 | 14:42:06 | **Schakelkast oververhitting (+K1)** (Control cabinet overheating +K1) — red |

Bottom of table has three tab buttons: clock/history, ⚠ warning, and a gauge/current icon. Bottom nav bar pictograms: ✕, grid(menu), home, **🔔(red, alarm active)**, heart(diagnostics), wrench(maintenance), trend-graph, ℞(recipe), monitor(ecoSAVE), PC, ▶| (next).

## Answers to open questions
- **Q29 (Is "3C" the SCADA node hosting wash line 6?) — PARTIAL / IMPORTANT.** The physical panel plate says **"LIJN 3C"** and this is an **EREMA EXTRUDER** BluPort HMI (melt filters MF1/MF2, melt pressure, extruder screw). So on the SCADA/panel naming, **"3C" is (also) the label on an EREMA extruder line's HMI**, not only a wash-line node. This suggests 3C is a line/panel identifier that can front an extruder. Does NOT confirm it hosts wash line 6; it confirms 3C = an EREMA extruder BluPort panel. (Reconcile with Q26 floor-plan naming.)
- **Q9 (line capacity / throughput) — DIRECT DATA.** LIJN 3C recipe = **LDPE 600 kg/h** (design/recipe rate). This is a real per-line throughput figure (600 kg/h for the 3C LDPE recipe), distinct from the ~1685 kg/h extruder in 182–184 (different/larger line).
- **Q15 (laserfilter / melt filter) — SUPPORTS.** Faults name **Smeltfilter 1 [MF1]** and **Smeltfilter 2 [MF2]** with **melt pressure before MF1** monitored ("Smeltdruk voor smeltfilter 1 [MP < MF1] te hoog – uitschakeling"). Confirms melt-pressure trip is measured BEFORE the melt filter, and there are TWO melt filters (MF1, MF2) with zoned heating (MF2-Z1). Live ◆₁=343 bar (red) = the pre-filter pressure that tripped. Strongly supports the pressure-straddles-filter model.
- **Q20 (slow-running causes → remedies) — DATA.** Real trip cause captured: melt pressure before filter too high → automatic shutdown (screen dropped to 3 %/57 kg/h). Remedy = screen/filter change (schermwissel) when Δp/pre-pressure too high. Also cabinet overheating (+K1) and heating-current alarms as stoppage causes.
- **Q30 (units) — CONFIRMS.** kW (124,2), %, rpm, bar, kg/h, h — same channel set as 182–185. Power=kW, speed=% here (rpm blank because screw nearly stopped).
- **Q33 — YES.** Real filled-in extruder data with active fault log, dated 29-9-2024.
