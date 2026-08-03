# Cedo-QESH-PLD-007 — Instructie Boek, p.28/32 (Gouden Regels 7 LOTOTO + 8 Drugs/Alcohol)

- **Source file:** `301_CeDo115.pdf` (1 page scan — page 28 of 32 of the QESH instruction book)
- **Doc id:** `Cedo-QESH-PLD-007`
- **Doc title:** `Instructie Boek`, QESH Department / PLD
- **Rev No:** 01
- **Issue Date:** 17-5-2022
- **Author:** QESH Dept.
- **Approved By:** Omar Atif
- **Page:** 28 of 32
- **Sibling of** `299_CeDo117.pdf` (p.30 of the same book).

## Top (carry-over from previous rule) — VERBATIM
- `Overtreding van deze regels wordt onderworpen aan de normale disciplinaire procedures.` (Violation of these rules is subject to the normal disciplinary procedures.)

## Gouden Regels 7 — LOTOTO — "Taggen en isoleren" (Golden Rule 7 — Lock Out / Tag Out / Try Out — Tagging and isolating)
**De regel** (the rule) — VERBATIM bullets:
- `Ik zal niets bedienen dat een buiten gebruiksklaar label heeft` (I will not operate anything that has an out-of-service label.)
- `Ik zal een tag die buiten gebruik is niet verwijderen, tenzij ik daartoe geautoriseerd ben.` (I will not remove an out-of-service tag unless I am authorised to do so.)
- `Ik identificeer alle potentiële energiebronnen voordat ik aan mijn taak begin` (I identify all potential energy sources before I begin my task.)
- `Ik zal nooit aan apparatuur beginnen te werken zonder de juiste isolatie- en uitsluitingsprocedures te gebruiken om alle energiebronnen te isoleren` (I will never start working on equipment without using the proper isolation and lock-out procedures to isolate all energy sources.)
- `Ik zal controleren en testen of de juiste energiebronnen goed zijn geïsoleerd bij de bron met behulp van persoonlijke sloten en tags` (I will check and test that the correct energy sources are properly isolated at the source using personal locks and tags.)
- `Ik zal ervoor zorgen dat alle opgeslagen energie wordt afgevoerd` (I will ensure all stored energy is discharged.)
- `Ik zal de persoonlijke gevarentag van iemand anders niet verwijderen` (I will not remove someone else's personal danger tag.)
- Photo: LOTO **lock-out hasp** (multi-hole scissor hasp) + **padlock**.

## Gouden Regels 8 — Drugs- en alcoholbeleid (Golden Rule 8 — Drug & alcohol policy)
**De regel** — VERBATIM:
- `Ik zal geen alcohol of drugs gebruiken op de werkplek of tijdens werktijd` (I will not use alcohol or drugs at the workplace or during working hours.)

## Answers to open questions
- **Q (safety/isolation mechanics — LOTOTO):** Full LOTOTO golden rule. In-sim maintenance events (e.g. the laserfilter wissel SWI-074, screw/heater work) should be gated behind a **lock-out/tag-out** step: identify energy sources → isolate → apply personal lock+tag → verify zero-energy → discharge stored energy. Never remove another person's tag. This is the safety layer wrapping the maintenance mini-games.
- **"Gouden Regels" (Golden Rules) numbering:** Rule 7 = LOTOTO, Rule 8 = Drugs/Alcohol → CeDo has a numbered set of Golden Rules (at least 8). Good flavor for an onboarding/safety module.
- Corroborates the fatigue/alcohol policy on p.30 (299): zero alcohol/drugs.

## Notes for sim
- LOTOTO as a prerequisite interlock for any maintenance action: lock + tag before working; the "buiten gebruik" (out-of-service) label blocks operation. Ties to the barrier-tape access model on p.30.
- Numbered Golden Rules set = a ready-made safety-training checklist for an intro tutorial.
