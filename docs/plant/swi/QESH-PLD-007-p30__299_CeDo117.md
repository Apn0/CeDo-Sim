# Cedo-QESH-PLD-007 — Instructie Boek, p.30/32 (Fitness voor werk + Barrièretaping)

- **Source file:** `299_CeDo117.pdf` (1 page scan — page 30 of 32 of the QESH instruction book)
- **Doc id:** `Cedo-QESH-PLD-007`
- **Doc title:** `Instructie Boek` (Instruction Book), QESH Department / PLD
- **Rev No:** 01
- **Issue Date:** 17-5-2022
- **Author:** QESH Dept.
- **Approved By:** Omar Atif
- **Page:** 30 of 32

## Section: Fitness voor werk — Vermoeidheidsbeheer (Fitness for work — Fatigue management) — VERBATIM
- `U heeft minimaal 7 tot 8 uur ononderbroken slaap van goede kwaliteit nodig voordat u aan de volgende dienst begint.` (You need at least 7 to 8 hours of good-quality uninterrupted sleep before starting the next shift.)
- `Na de werkuren moeten de afdelingsmanagers de vermoeidheid van de werknemer op individuele basis beoordelen en beheren.` (After working hours, department managers must assess and manage employee fatigue on an individual basis.)
- `Elke gemiste slaap telt op en moet uiteindelijk worden terugbetaald.` (Every bit of missed sleep accumulates and must ultimately be paid back.)
- `Slaapschuld heeft hetzelfde effect als 24 uur achter het stuur dronken zijn zonder slaap, gelijk aan 0,1% alcoholgehalte in het bloed` (Sleep debt has the same effect as being drunk behind the wheel for 24 hours without sleep, equal to 0.1% blood alcohol content.)

## Section: Fitness voor werk (alcohol/drugs) — VERBATIM
- `Cedo tolereert geen alcohol en drugs.` (Cedo tolerates no alcohol or drugs.)
- `Alle werknemers moeten uitgerust en vrij van alcohol of drugs die hun vermogen om veilig te werken zouden kunnen beïnvloeden, op hun werk te verschijnen` (All employees must show up to work rested and free of alcohol or drugs that could affect their ability to work safely.)

## Section: Barrièretaping (barrier taping) — table VERBATIM
Columns: `Type | Steekproef | Kleur: | Toegangsvoorwaarden | Toegepast/verwijderd door`
(Type | sample/spot-check (photo) | Colour | Access conditions | Applied/removed by)

| Type | Kleur | Toegangsvoorwaarden | Toegepast / verwijderd door |
|---|---|---|---|
| `Let op tape` (Caution tape) | `Geel en zwart` (Yellow and black) | `Toegang toegestaan met autorisatie van gebiedstoezichthouder en na briefing over de potentiële of feitelijke gevaren` (Access allowed with authorisation of the area supervisor and after briefing on the potential or actual hazards) | `Toegepast: Persoon die verantwoordelijk is voor het identificeren van het gevaar` (Applied: person responsible for identifying the hazard). `Verwijdering: Area / Job shift leider` (Removal: Area / Job shift leader) |

- Steekproef photo: a roll of **yellow-and-black diagonally striped** hazard barrier tape.
- **[note]** Only the "Let op tape" (yellow/black caution) row is present on this page; a red barrier-tape row (Verboden toegang / no entry) presumably continues on the next page (this table appears truncated at page bottom).

## Answers to open questions
- **Q (shift / fatigue rules) — supports the "can't escape your shift" pillar:** DIRECT policy text. CeDo's own rule: **minimum 7-8 h uninterrupted good sleep before a shift**; fatigue assessed per-worker by dept managers after hours; sleep debt likened to 0.1 % BAC. This is real employer policy that can flavor the sim's fatigue/shift mechanics (a "sleep debt" stat, manager fatigue checks).
- **Barrier-tape convention for sim:** **Yellow-and-black = "Let op" (caution)**: entry allowed only with area-supervisor authorisation + hazard briefing; applied by the hazard-identifier, removed by the Area/Job shift leader. Good for modeling in-plant hazard-zone gating / a shift-leader permission mechanic.
- No process/throughput/laserfilter data on this QESH page.

## Notes for sim
- Fatigue/sleep-debt policy (7-8 h rule; sleep debt = impairment) → a plausible in-sim "rested/fatigued" state gate tied to the 2-2-2-4 calendar.
- Access-control model: hazard zones taped off; shift leader controls removal → maps to a permission/interlock mechanic.
