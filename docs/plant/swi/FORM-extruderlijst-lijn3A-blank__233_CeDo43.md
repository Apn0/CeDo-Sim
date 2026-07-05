# FORM — Lijn 3A Extruder lijst (blank production log)

- **Source file:** `233_CeDo43.pdf`
- **Doc id:** none printed (CeDo internal production log form, "cedo" logo top-right)
- **Type:** single-page blank fill-in form (per-shift extruder operating log for lijn 3A)
- **Scope:** Lijn 3A extruder — hourly operator log (uur 1..uur 8)

## Header fields (blank to fill)
- **Title:** "Lijn 3A : Extruder lijst"
- Datum: ........ 2024
- Dienst ("shift"): **OD / MD / ND** (Ochtenddienst / Middagdienst / Nachtdienst = morning / afternoon / night)
- Ploeg ("team/crew"): **A / B / C / D / E**  ← note 5 crews (A–E), consistent with 5-ploegen
- Naam invuller ("name of person filling in"): ........
- Order nummer: ........
- **order wisselen bij:** ___ KG  ("change order at ___ kg")
- **kilo's vorige order:** ___ KG  ("kilos of previous order")

## Section 1 — "Werkelijke controle tijd invullen" ("fill in actual check time"), columns uur 1..uur 8
Rows (measured values, one per hour):
| Row | Label (verbatim) | Gloss |
|---|---|---|
| 1 | Cummulatieve output kg | cumulative output kg |
| 2 | Actuele snelheid kg/uur | actual speed kg/hour |
| 3 | stort gewicht meting | bulk/pour weight measurement (stortgewicht) |
| 4 | aantal korrels met gasvorming | number of pellets with gas formation (bubbles) |
| 5 | aantal korrels met aluminium | number of pellets with aluminium |

## Section 2 — "Slow running reden" ("reason for slow running"), columns uur 1..uur 8
Tick per hour which cause applies:
| Label (verbatim) | Gloss |
|---|---|
| Sorteerlijn (grondstof/shredder 1/2) | sorting line (feedstock / shredder 1 or 2) |
| Overblazen naar was 3a | over-blowing to wash 3a |
| Laserfilter druk | laserfilter pressure |
| Kwaliteit eind product | quality of end product |
| anders: | other |

## Legend block (stilstand codes)
- **M: Messen wissel** — knife/blade change
- **O: Onderhoud** — maintenance
- **P: process storing** — process fault
- **T: Technische storing** — technical fault

## Summary fields
- **stortgewicht gemiddelde =** ___  ("bulk weight average")
- **Vochtmeting =** ___ %  ("moisture measurement in %")

## Section 3 — "Reden stilstand" ("reason for downtime"), columns uur 1..uur 8
- Large blank grid, ~8 rows, to log downtime reasons per hour using M/O/P/T codes above.
- Bottom row: **Genomen actie:** ("action taken") — free text.

## Answers to open questions
- **Q17 (FORM row ending in vocht):** This form's summary ends with **"Vochtmeting = ___ %"** (moisture measurement, percent) as the final metric line — matches the "ends in vocht" pattern. Value blank on this master form.
- **Q19 (stortgewicht unit + value):** "stort gewicht meting" logged per hour and a **"stortgewicht gemiddelde"** (average) summarised; on this blank form no unit is printed next to the value cell (operators fill raw number — from context g/L bulk density). Value blank (master form).
- **Q20 (slow-running remedies per cause):** The form enumerates the **5 slow-running causes** operators must attribute each hour: (1) Sorteerlijn/grondstof/shredder 1/2, (2) Overblazen naar was 3a, (3) Laserfilter druk, (4) Kwaliteit eind product, (5) anders. Remedy actions are logged free-text under "Genomen actie". (Cause list confirmed; explicit remedy-per-cause table not on this form.)
- **Q33 (filled-in Extruderlijst exists?):** This is the **BLANK master** of the Extruderlijst for lijn 3A — confirms the form exists and its exact layout, but this copy is unfilled. Header confirms year 2024, shifts OD/MD/ND, crews A–E.
- **Bonus (calendar/crew):** Ploeg A/B/C/D/E = 5 crews; supports the 5-ploegen structure. Order-change trigger "order wisselen bij ___ KG" — orders are switched at a kilo threshold, useful game mechanic.
- **Q1 (ZSS):** not present here.
