# Cedo-PROD-SWI-010 — Wisselen Halogeen lampen NIRs (page 4 of 4, steps 9-12)

- **Source file:** `341_CeDo128 (2).pdf`
- **SWI id:** Cedo-PROD-SWI-010
- **Title (NL):** Wisselen Halogeen lampen NIRs
- **Department:** PROD Department / SWI
- **Rev No.:** 03
- **Issue Date:** 19-9-2023
- **Author:** PROD Dept
- **Approved By:** Peter Scheffer
- **Page:** 4 of 4

## Instructie (step table, continued)

| nr | Titel handeling | Let op (pictogram) | Omschrijving handeling | Ondersteunende foto / schets |
|----|-----------------|--------------------|------------------------|------------------------------|
| 9 | Stappen plan *(step plan)* | — | *(exploded assembly diagram of the halogen lamp module, with 5 numbered callouts)* | Diagram caption: **"Afb. 20: Vervangen van de halogeenlampmodule"** *(Fig. 20: Replacing the halogen lamp module)*. Numbered legend: **1 Glasfilaring nr. 1** [unsure: "Glasflaring/Glasvezel nr 1"]; **2 Lamphouder** (lamp holder); **3 Halogeenlampmodule** (halogen lamp module); **4 Glasfilaring nr** [number cut off]; **5 Houdschroef (2x)** (retaining screw, 2×). Sub-steps printed in diagram: 6. Maak de twee houdschroeven los *(loosen the two retaining screws)*. 7. Vervang de kapotte halogeenlampeenheid door een nieuwe *(replace the broken halogen lamp unit with a new one)*. 8. Monteer de onderdelen door bovenstaande volgorde omgekeerd uit te voeren *(reassemble by performing the above steps in reverse order)*. |
| 10 | Stappen plan | Functie (hand); Zicht (eye); TIP (blue dot); Kwaliteit (green diamond) | Zie foto hierboven: **5:** Maak de 2 houdschroeven los, nr. 5 in de foto. **6:** Vervang de kapotte halogeenlamp voor een nieuwe. **Raak de halogeenlamp zelf niet aan met je handen**, houd de halogeen lamp altijd vast aan de houder. **7:** Monteer alle onderdelen door bovenstaande volgorde omgekeerd uit te voeren. — **Kwaliteit:** Zet de warmtewisselaar goed vast weer terug, zodat deze stofdicht is, en er dus geen stof in de lamp unit komt. Dit vermindert namelijk de werking van de sorteerder. *(Refit the heat exchanger tightly so it is dust-tight; dust in the lamp unit reduces sorter performance.)* | *(refers to diagram in step 9)* |
| 11 | Lamp uren reset *(lamp-hours reset)* | Functie (hand); Zicht (eye); Kwaliteit (green diamond) | Na het wisselen van een lamp altijd de lampuren-teller op reset zetten. Door op het dialoogvenster 'lamp vervangen' te klikken, en dan op reset te klikken, wordt de teller op '0' uren gezet, en de storingdetectie van de lamp wordt opnieuw gekalibreerd. *(After swapping a lamp, always reset the lamp-hours counter. In the 'lamp vervangen' dialog click reset → counter goes to 0 h and the lamp fault detection recalibrates.)* | Photo: **TOMRA** HMI screen; two lamp panels labelled "Lampuren" with **Status OK**, "Zet terug" (reset) buttons, warning triangle. Bottom nav bar: **Home, Sortering, Statuszien, Configureren, Onderhoud, Lampen**. Clock **09:30**. |
| 12 | Detector kaliberen *(calibrate detector)* — highlighted | Functie (hand); Zicht (eye) | Na lampwissel en kalibratie, doe je ook altijd een kalibratie van de detector zelf volgens **Cedo-Prod-SWI-009-R03** met de kalibratieplaat, veeg het glas vantevoren ook altijd schoon volgens **Cedo-Prod-SWI-011-R02**. *(After lamp swap + calibration, always also calibrate the detector itself per SWI-009-R03 with the calibration plate; first always wipe the glass clean per SWI-011-R02.)* | — |

## Legend (footer)
- hand = **Functie**; ear = **Geluid**; eye = **Zicht**; red cross = **LET OP: Veiligheid**; green diamond = **LET OP: Kwaliteit**; blue dot = **TIP**.

## Answers to open questions
- **Q28 (TITECH/Tomra):** HMI is **TOMRA**-branded with nav tabs Home / Sortering / Statuszien / Configureren / Onderhoud / Lampen. Lamp fault detection is tied to a **lamp-hours counter** that must be reset on swap. Cross-refs: **SWI-009-R03** = detector calibration with calibration plate; **SWI-011-R02** = cleaning the glass. Rule: never touch halogen bulb with bare hands (hold by holder); keep heat-exchanger dust-tight or sorter performance drops.

## Notes for sim
- Full lamp-swap chain: LOTOTO → 10-min cooldown → loosen 2 screws → swap module (by holder only) → reassemble reverse → refit heat exchanger dust-tight → HMI lamp-hours reset → detector calibration (plate) → glass wipe. Multi-step maintenance minigame.
