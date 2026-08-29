# SWI-009 — Kalibreren Titech, Tomra NIR (p6 of 8)

- **SWI ID:** Cedo-PROD-SWI-009
- **Title (NL):** Kalibreren Titech, Tomra NIR [partly obscured header, reads "Kalibreren Titech, Tom[ra ...]"]
- **Title (EN):** Calibrating the Titech / Tomra NIR sorter
- **Department:** PROD Department / SWI
- **Rev No.:** 04
- **Issue Date:** 19-9-2023
- **Author:** PROD Dept
- **Approved By:** Peter Scheffer
- **Page:** 6 of 8
- **Source file:** `357_CeDo135 (2).pdf` (D:/drive-download-20251124T130330Z-1-001)
- **Scope:** TITECH/TOMRA NIR sorter — this page covers steps **16–19**: verify glasses/belt clean & start with Tomra, log in as operator, enable lamps (checkbox via Onderhoud→Licht menu), and check **lamp light intensity (must be >90%, else replace lamp)**.
- **Related pages:** `SWI-009__021_CeDo129_2.md`, `SWI-009-p2__014_CeDo130.md`, `SWI-009-p3__154_CeDo132_2.md`, `SWI-009-p4__029_CeDo133_2.md`, `SWI-009-p5__162_CeDo134_2.md`, `SWI-009-p8__091_CeDo137_2.md`. (This p6 fills the gap between p5 and p8.)

## Step table (nr / titel handeling / let-op / omschrijving / foto) — VERBATIM

| nr | Titel handeling | Let op (pictograms) | Omschrijving handeling (verbatim NL → EN gloss) | Ondersteunende foto / schets |
|----|-----------------|---------------------|--------------------------------------------------|------------------------------|
| 16 | *(blank title)* | Veiligheid (red lock/padlock icon); Functie (hand); Zicht (eye) | "Glaasjes en transportband zijn schoon en starten met de Tomra." (The **glasses/windows** and **conveyor belt** are clean, and start with the Tomra.) | Orange **TOMRA** logo tile (indicates the TOMRA/Titech HMI). |
| 17 | Lampen aanzetten / inloggen (Switch lamps on / log in) | Functie (hand); Zicht (eye); TIP/info (blue i) | "Log in het menu in als 'operator' met wachtwoord '[REDACTED]'." (Log into the menu as **'operator'** with password **'[REDACTED]'**.) | Photo of HMI login screen: tabs "…ortering / Statistieken", prompt "Raak aan om in te loggen" (Touch to log in). |
| 18 | Lampen aanzetten (Switch lamps on) | *(none)* | "Zet vinkje in vak zoals te zien op foto. In dit menu komt door eerst te gaan naar: – Onderhoud – Licht." (Tick the checkbox as shown in the photo. Reach this menu by first going to **Onderhoud** [Maintenance] → **Licht** [Light].) | Photo: finger pointing at a checkbox on the HMI maintenance/light screen. |
| 19 | Lichtsterkte lamp (Lamp light intensity) | *(none)* | "Controleer de lichtsterkte van de lamp; **moet meer dan 90% zijn anders eerst lamp vervangen.** Controleer dit in het bovenstaande menu door op het symbool: – symbool lamp – en controleer de waarde. Is de waarde meer dan 90% dan is het goed, anders eerst lamp vervangen. – **Reset daarna de waarde.**" (Check the lamp light intensity; **must be more than 90%, otherwise replace the lamp first.** Check via the lamp symbol in the above menu and read the value. If >90% it's OK, otherwise replace the lamp first. Then **reset the value**.) | Photo of HMI status screen showing two lamp panels with "Status 90(100)%" [unsure exact], "Lamp uren / Lamp hours", "Reset lamp Calibratie" buttons and a live NIR image thumbnail. |

## Pictogram legend (footer, verbatim)
Functie (hand) · Geluid (ear, "Geluid") · Zicht (eye) · LET OP: Veiligheid (red cross) · LET OP: Kwaliteit (green diamond) · TIP (blue circle).

## Open-question hits — Q28 (TITECH / TOMRA) — STRONG
- **Q14 (FORM-008 row 16 full text):** NOT this doc (this is SWI-009 step 16, unrelated to FORM-008). No help for Q14.
- **TITECH = TOMRA** confirmed (orange TOMRA logo on the HMI; "Titech" and "Tomra" used interchangeably — Titech is the legacy brand now TOMRA).
- **HMI login:** user **'operator'**, password **'[REDACTED]'**.
- **Menu path to lamp control:** Onderhoud (Maintenance) → Licht (Light) → tick checkbox to enable lamps.
- **Lamp health threshold:** NIR lamp **light intensity must be >90%**; below that → **replace the lamp**, then **reset the value** (lamp-hours / calibration reset). This is a concrete maintenance rule usable as a sim degradation mechanic (lamp wears, <90% forces a lamp swap).
- HMI has **"Lamp uren" (lamp hours)** counter and **"Reset lamp Calibratie"** buttons; **Statistieken** and **sortering** tabs.
- Cross-refs the halogen-lamp replacement SWI (`SWI-010-p1-wisselen-halogeenlampen-NIR__340_CeDo123_2.md`) — this SWI-009 p6 is the *check* step, SWI-010 is the *replace* procedure.

## Notes
- Step 16 title cell is blank in the source (only pictograms + description).
- Lamp status values partly illegible in the photo; the >90% rule is clearly stated in the omschrijving text.
- No throughput/temp/water values (this is a sorter-calibration SWI).
