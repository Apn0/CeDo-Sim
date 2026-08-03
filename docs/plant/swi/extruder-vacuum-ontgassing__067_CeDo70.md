# Extruder — Vacuüm ontgassingsunit & Vacuümontgassing (EREMA vacuum degassing + pump types) — 067_CeDo70

- **Source file:** D:/drive-download-20251124T130330Z-1-001/067_CeDo70.pdf
- **Doc id:** OTHER:EREMA-manual-page (machine spec; no SWI number) — mentions "Onze TE- en TVE-machines" = EREMA TE / TVE extruder series
- **Title (NL):** "Extruder – Vacuüm ontgassingsunit" + "Vacuümontgassing"
- **Title (EN):** "Extruder — Vacuum degassing unit" + "Vacuum degassing"
- **Pages:** 1
- **Scope:** One machine-spec page describing the EREMA extruder vacuum degassing unit and the water-ring vacuum pump types used. Multiple photos + a pump cutaway. Tabbed binder (yellow/orange/red tabs at right).
- **Line:** general (EREMA TE/TVE extruders — applies to 3a/3b and any EREMA line)

## Full transcription (verbatim NL, EN gloss)

### Heading: **"Extruder – Vacuüm ontgassingsunit"** (Extruder — Vacuum degassing unit)

> "Onze TE- en TVE-machines zijn uitgerust met een vacuüm ontgassingsunit op het achterste gedeelte van de extruder. Het vacuüm ontgassingssysteem moet de gassen verwijderen die tijdens het proces ontstaan."
> *(Our TE and TVE machines are equipped with a vacuum degassing unit on the rear part of the extruder. The vacuum degassing system must remove the gases that arise during the process.)*

Gases to remove (bullets):
- verdampt water (vocht) *(evaporated water / moisture)*
- gassen van verbrand papier/cellulose *(gases from burnt paper/cellulose)*
- gassen van verbrande inkt/printkleuren *(gases from burnt ink/print colours)*
- … *(etc.)*

> "De ontgasser heeft de volgende onderdelen:" *(The degasser has the following parts:)*
- vacuümpomp (vloeistof/waterringpomp) *(vacuum pump — liquid/water-ring pump)*
- opslagtank voor vloeibare gassen *(storage tank for liquefied gases)*
- Ontgassingsdoppen op de extruderbuis *(degassing caps/ports on the extruder barrel)*
- slangen, leidingen, drukmeters en vacuümsensor *(hoses, pipes, pressure gauges and vacuum sensor)*
- vacuümbooster (extra) *(vacuum booster — optional)*

**Photos (2):**
1. The actual degassing unit cabinet on the plant floor — twin stainless housings with gauges, valves, a blue control box, mounted at the rear of the extruder.
2. A pair of tall glass/transparent separator columns (the vapour/liquid separator sight tubes of the degasser).

### Heading: **"Vacuümontgassing"** (Vacuum degassing)

> "In principe zijn onze machines uitgerust met vloeistof/waterringpompen die gevoed moeten worden door water om een vacuüm op te bouwen."
> *(In principle our machines are equipped with liquid/water-ring pumps that must be fed with water to build up a vacuum.)*

> "Afhankelijk van het type worden de pompen gevoed door water onder druk (bijv. stadswater) of door water dat door de vacuümpomp zelf uit een tank wordt gezogen (bijv. BWB)."
> *(Depending on the type, the pumps are fed by pressurised water (e.g. mains/city water) or by water that the vacuum pump itself draws from a tank (e.g. BWB).)*
- "Het werkingsprincipe is vergelijkbaar" *(The working principle is comparable.)*

> "Gebruikte types:" *(Types used:)*
- **Eentrapspompen: V55, V155, V330, …** *(single-stage pumps: V55, V155, V330, …)*
- **Tweetrapspompen: VH180, VH300, VH600, …** *(two-stage pumps: VH180, VH300, VH600, …)*

**Photos (3):**
1. A single-stage water-ring vacuum pump on a base (electric motor + pump body).
2. A two-stage water-ring vacuum pump (red-valved, twin-stage body).
3. Cutaway illustration of a water-ring pump impeller — off-centre rotor (orange) in a housing with the blue water ring, showing the eccentric water-ring operating principle.

## Machine facts extracted (load-bearing for sim)

- **Extruders are EREMA TE and TVE series** ("Onze TE- en TVE-machines"). The degassing unit sits at the **rear of the extruder barrel**.
- **Vacuum degassing removes:** moisture (verdampt water), burnt paper/cellulose gases, burnt ink/print-colour gases — i.e. the smoke/steam from contaminated film. This is why FORM-018 stresses "vocht afzuiging" (moisture extraction) on the compactor.
- **Degasser components:** water-ring vacuum pump + liquid-gas storage tank + degassing ports on barrel + hoses/pipes/pressure gauges/vacuum sensor + optional vacuum booster.
- **Vacuum pump models (real specs):**
  - Single-stage (eentrapspompen): **V55, V155, V330** (number ≈ capacity in m³/h)
  - Two-stage (tweetrapspompen): **VH180, VH300, VH600**
- **Pumps are liquid/water-ring type**, fed either by pressurised mains water (stadswater) or by water self-drawn from a tank (labelled **BWB**).

## Cross-refs to open questions
- **Q5 (water routing — vacuum pump water):** the water-ring vacuum pumps consume water fed from mains or a tank ("BWB"). "BWB" appears here as a water-supply tank reference for the vacuum pumps — a new water-loop node. (Not a full routing map.)
- **Q15 (extruder zones):** confirms degassing is at the **rear of the extruder barrel** (downstream of feed, part of the melt path before the laserfilter) — consistent with mid-barrel/rear vacuum ports.
- **Machine make (general):** extruders are **EREMA TE/TVE**; vacuum pumps are water-ring V-series (single-stage V55/V155/V330) and VH-series (two-stage VH180/VH300/VH600).
