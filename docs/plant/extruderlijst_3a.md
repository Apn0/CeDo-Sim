# Lijn 3A : Extruder lijst (extruder shift log form)

**Sources:**
- `C:/Users/arnod/Documents/CeDo_Simulator_data/Extruderlijst_3A.pdf` (1 page, photo of the paper form in a ring binder)
- `C:/Users/arnod/Documents/CeDo_Simulator_data/Extruderlijst_3A_clean_A4.pdf` (1 page, straightened/cropped re-photograph of the same form)

**Extraction date:** 2026-07-04

**Nature of the document:** This is NOT a filled-in setpoint sheet — it is the **blank hourly log form** the Lijn 3A extruder operator fills in every shift (8 hourly columns = one 8-hour dienst). No numeric values are pre-printed except unit hints ("KG", "%"). The columns to be filled are per-hour observations of the EREMA extruder output.

---

## Form header (top-left block)

| Field (verbatim NL) | English gloss | Pre-printed content |
|---|---|---|
| Lijn 3A : Extruder lijst | Line 3A: Extruder list | form title |
| Datum: ................2024 | Date | dotted fill-in line, pre-printed year "2024" |
| Dienst: OD / MD / ND | Shift: OD / MD / ND (ochtenddienst = morning, middagdienst = afternoon, nachtdienst = night — circle one) | three options |
| Ploeg : A / B / C / D / E | Crew: A/B/C/D/E (circle one; 5-crew rotation) | five options |
| Naam invuller: ............... | Name of person filling in | dotted fill-in line |
| Order nummer: ............... | Order number | dotted fill-in line |

Top-right: **cedo** company logo.

## Order-change box (right of header)

| Field (verbatim NL) | English gloss | Unit |
|---|---|---|
| order wisselen bij: | change order at: (cumulative kg at which to switch to the next order) | KG |
| kilo's vorige order: | kilos of previous order | KG |

## Row above the hourly grid

Verbatim: **"Werkelijke controle tijd invullen"** (fill in the actual control/check time) — a row of 8 blank cells above the "uur" headers where the operator writes the real clock time of each hourly check.

## Hourly grid — section 1 (measurements)

Column headers: **uur 1 | uur 2 | uur 3 | uur 4 | uur 5 | uur 6 | uur 7 | uur 8** (uur = hour)

| Row label (verbatim NL) | English gloss |
|---|---|
| Cummulatieve output kg | Cumulative output in kg (sic: "Cummulatieve") |
| Actuele snelheid kg/uur | Current speed in kg/hour |
| stort gewicht meting | Bulk density measurement (of the granulate) |
| aantal korrels met gasvorming | Number of pellets with gas formation (voids/bubbles) |
| aantal korrels met aluminium | Number of pellets with aluminium (contamination) — first letters obscured by binder ring in the raw photo; fully legible in the clean_A4 variant |

All 5 rows × 8 hour-columns are blank fill-in cells.

## Hourly grid — section 2 (slow running)

Section header row: **"Slow running reden"** (slow running reason) with its own repeated column headers **uur 1 … uur 8**.

| Row label (verbatim NL) | English gloss |
|---|---|
| Sorteerlijn (grondstof/shredder 1/2) | Sorting line (raw material / shredder 1/2) — i.e. slow because of upstream sorting-line feed |
| Overblazen naar was 3a | Blowing over (pneumatic transfer) to wash 3a |
| Laserfilter druk | Laser filter pressure |
| Kwaliteit eind product | Quality of end product |
| anders: | other: |

All 5 rows × 8 hour-columns are blank tick/fill-in cells.

## Legend block (bottom-left of the middle section)

Verbatim, one per line (codes the operator writes into the stilstand grid):

- **M:Messen wissel** — M: knife/blade change (pelletizer knives)
- **O:Onderhoud** — O: maintenance
- **P:process storing** — P: process fault
- **T:Technische storing** — T: technical fault/breakdown

## Averages block (right of the legend)

| Field (verbatim NL) | English gloss |
|---|---|
| stortgewicht gemiddelde = | bulk density average = (blank fill-in) |
| Vochtmeting =        % | Moisture measurement = ___ % (blank fill-in) |

## Section 3 — downtime grid

Header row: **"Reden stilstand"** (reason for standstill/downtime) with column headers **uur 1 … uur 8**.

Below it: approximately **10 blank rows**. The left area of each row is split into **two fill-in columns** (a narrow first column — for the M/O/P/T code — and a wider second column for the description), followed by the 8 hour cells.

## Bottom section

Verbatim label: **"Genomen actie:"** (action taken) — large blank free-text area spanning the bottom of the page, with the hour-column grid extending alongside/above it.

---

## Differences between the two PDF variants

Both PDFs show the **same form, identical fields, identical layout** — no content differences found.

| Aspect | Extruderlijst_3A.pdf | Extruderlijst_3A_clean_A4.pdf |
|---|---|---|
| Capture | Photo at slight angle, form sits in a ring binder with coloured tab dividers visible | Straightened, tighter A4 crop of the same physical sheet |
| Legibility | Row "aantal korrels met aluminium": first letters hidden behind a binder ring | Same row still partially behind the ring but clearly readable as "aantal" |
| Content | identical | identical |

## Notes / open questions for the operator

1. The form contains **no pre-printed setpoints** — the actual EREMA 3A setpoint values (temperatures, pressures, screw speeds) are not on this sheet. Target values that exist on paper are on Checklist FORM-008 (see `checklist_3a_3b.md`). Is there a separate filled-in Extruderlijst or an EREMA parameter sheet with real hourly numbers?
2. What are typical/target values for "Actuele snelheid kg/uur" and "stortgewicht" on 3A, and the acceptance threshold for "aantal korrels met gasvorming/aluminium" (per what sample size — pellets per scoop?)?
3. "order wisselen bij: ___ KG" — confirm this means the cumulative-output kg mark at which the operator switches to the next order.
