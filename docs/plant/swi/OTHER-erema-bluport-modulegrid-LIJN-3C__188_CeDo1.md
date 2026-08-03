# EREMA BluPort HMI — module/menu grid, panel labeled "LIJN 3C"

- **Source file:** 188_CeDo1.pdf (1 page, photo of EREMA BluPort HMI, module-grid/menu page)
- **Doc id / slug:** OTHER-erema-bluport-modulegrid-LIJN-3C
- **Doc type:** Photograph of EREMA BluPort touchscreen module-selection grid (each tile = a machine module screen); same panel as 187_CeDo87(3)
- **Timestamp:** 15:37:3x, 29-9-2024 (~30 s after 187's alarm shot)
- **Recipe/header:** **"℞ LDPE 600 kg/h  22.04.2024 IBN"** (same recipe as 187). Branding **BluPort EREMA**. Physical plate below screen: **"LIJN 3C"**.

## Left column live values (VERBATIM, low-res)
110 °C · 124,0 kW · (rpm blank) · 0 % · 2147 h · 276 bar · 11 bar · 71 bar · 52 kg/h. (Line still tripped/idling from the 187 alarm — 0 %, 52 kg/h.)

## Module grid tiles (VERBATIM icon labels, left→right, top→bottom)
Row 1: 
- **[⇥ Doseren]** (Dosing / infeed) 
- **[◷ Wateronthardung / Wateront...heid?]** — label reads "Wateronthard/…Losd" [unsure: "Wateronthardheid" = water hardness/softener] 
- **[≋ Extruder 1]** (Extruder 1) 
- **[◆ Smeltfilter 1]** (Melt filter 1) 
- **[⊡ Smeltpomp 1]** (Melt pump 1) 
- **[⇤ Granulier-/Granulaat systeem]** (Granulating / pellet system) 

Row 2: 
- **[◆ Smeltfilter 2]** (Melt filter 2) — under the Smeltfilter 1 tile 

Row 3: 
- **[⇥ Doseren / Dosier...]** (second dosing/infeed module tile, left side) 

Remaining grid cells empty. So the 3C line's module chain = **Doseren → Wateronthardheid → Extruder 1 → Smeltfilter 1 (+ Smeltfilter 2) → Smeltpomp 1 → Granulaatsysteem**, with a second Doseren module.

## Answers to open questions
- **Q29 (Is 3C the SCADA node hosting wash line 6?) — CLARIFIES.** The LIJN 3C BluPort exposes **extruder + melt filters + melt pump + granulate** modules (a full EREMA extrusion train), NOT a wash line. So "3C" = the panel/SCADA node for an **EREMA extruder line running LDPE 600 kg/h**. No wash-line-6 modules appear on this panel → 3C is an extruder node, weakening the "3C hosts wash line 6" hypothesis (it hosts an extruder). (Cross-check Q26 line naming.)
- **Q15 (melt filters) — CONFIRMS TWO FILTERS.** Distinct **Smeltfilter 1** and **Smeltfilter 2** module tiles + **Smeltpomp 1** (melt pump). Matches 187's MF1/MF2 faults. The 3C extruder has two melt filters in series plus a melt pump feeding the granulate system.
- **Q3 (dosing screws) — RELATED.** TWO "Doseren" (dosing) module tiles on 3C — consistent with the sim's shared/dual dosing-screw question (Q3). Two independent dosing modules exist on this line.
- **Q9 — DATA (confirms 187).** 3C recipe LDPE 600 kg/h.
- **Q30 — CONFIRMS.** Same channel/unit set (°C, kW, rpm, %, h, bar, kg/h).
- Water treatment tile ("Wateronthard…") on an extruder panel = the granulate/pelletizer water softener loop (relates to Q5 granuleerwater loop / Q11 water abbreviations, but no direct expansion of LA1/LA2/ZSS here).
