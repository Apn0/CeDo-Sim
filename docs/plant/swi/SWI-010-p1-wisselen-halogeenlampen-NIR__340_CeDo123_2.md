# Cedo-PROD-SWI-010 — Wisselen Halogeen lampen NIRs (page 1 of 4)

- **Source file:** `340_CeDo123 (2).pdf`
- **SWI id:** Cedo-PROD-SWI-010
- **Title (NL):** Wisselen Halogeen lampen NIRs *(replacing the halogen lamps of the NIR sorters)*
- **Department:** PROD Department / SWI
- **Rev No.:** 03
- **Issue Date:** 19-9-2023
- **Author:** PROD Dept
- **Approved By:** Peter Scheffer
- **Page:** 1 of 4 (scan contains only page 1)

## 1. Doel Document (Purpose) — highlighted
Het correct en veilig wisselen van een lamp van de sorteermachine/NIR wanneer er een lamp defect is, en daarna altijd de lamp zelf kalibreren EN daarna altijd de betreffende detector ook kalibreren met de kalibratie plaat (**Cedo-Prod-SWI-009-R03**), in deze volgorde.

*(Correctly and safely replacing a lamp of the sorting machine/NIR when a lamp is defective, then always calibrating the lamp itself AND then always calibrating the relevant detector too using the calibration plate (ref SWI-009-R03), in this order.)*

Op de onderhoudsdag controleer je voordat je de kalibratie doet, ook de lampen visueel, zie punt 1 in de SWI onder. *(On the maintenance day, before doing the calibration, also check the lamps visually — see step 1 below.)*

## 2. Veiligheid (Safety) — highlighted header
- Denk bij het betreden van de sorteerband bij het wisselen van een lamp altijd aan het volgen van de **lototo** procedure, stel de band veilig waar je op staat! *(When stepping onto the sorting belt to change a lamp, always follow the LOTOTO procedure; make the belt safe where you stand.)*
- Denk aan het uitschakelen en veilig stellen van de **Tomra** unit voor het wisselen van de lamp volgens de lototo procedure. *(Remember to switch off and safely isolate the Tomra unit before changing the lamp per LOTOTO.)*
- Laat de lamp **10 minuten** afkoelen voor wissel. Risico op brandwonden. *(Let the lamp cool 10 minutes before swapping. Burn risk.)*

## 3. Bereik Document (Scope)
Shiftleaders, assistent shiftleaders, lijn 3 extruder operators, ETD engineers.

## 4. Referentie naar (References)
Hoofdstuk 7.7.2 Tomra instructie klapper *(Chapter 7.7.2 Tomra instruction binder)*

## 5. Definities
*(header present, no content)*

## 6. Instructie (step table)

| nr | Titel handeling | Let op (pictogram) | Omschrijving handeling | Ondersteunende foto / schets |
|----|-----------------|--------------------|------------------------|------------------------------|
| 1 | Visuele controle alle 8 de scanners (4x2) op de onderhoudsdag *(visual check of all 8 scanners (4×2) on maintenance day)* | Zicht (eye) icon; Functie (hand) icon | Zet de lampen in 'hand' modus 'aan', en bekijk op de transportband of er een zwarte streep in het midden zit. Zo ja, wissel dan de 2 lampen van de betreffende scanner(s) volgens onderstaande procedure, ook al geeft de NIR geen foutmelding op de lamp. *(Put the lamps in 'hand' mode 'on', and look on the conveyor belt whether there is a black stripe in the middle. If so, replace the 2 lamps of the relevant scanner(s) per the procedure below, even if the NIR gives no fault message on the lamp.)* | Photo: conveyor belt surface with lamp illumination; caption: "Zie foto voorbeeld zwarte streep in het midden waarbij je moet wisselen." *(See photo example of the black stripe in the middle where you must replace.)* |

## Legend (footer)
- hand icon = **Functie** (function)
- ear/sound icon = **Geluid** (sound)
- eye icon = **Zicht** (sight/vision)
- red cross = **LET OP: Veiligheid**
- green diamond = **LET OP: Kwaliteit**
- blue dot = **TIP**

## Answers to open questions
- **Q28 (TITECH programs/sensors):** Confirms the NIR sorters are **Tomra/TITECH** units with **8 scanners arranged 4×2** (4 pairs of 2 lamps each). "Hand" mode exists to force lamps on for visual inspection. A dead lamp shows as a **black stripe in the middle of the belt**. Calibration workflow: replace lamp → calibrate lamp → calibrate detector with calibration plate (SWI-009-R03). Halogen lamps used for NIR illumination.

## Notes for sim
- Maintenance-day ritual: force lamps to hand-on, scan for black stripe, LOTOTO the belt and Tomra unit, 10-min cooldown, swap paired lamps, then double calibration. Good micro-task loop for the sim's "onderhoudsdag."
