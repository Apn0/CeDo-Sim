# GUIDE — Messen en messenhouders + Schoksensor eenheid (Compactor knives/holders + shock-sensor unit)

- **Source file:** `356_CeDo61.pdf` (D:/drive-download-20251124T130330Z-1-001)
- **Type:** Single-page training/reference sheet (scanned, ring binder), 2 photos of compactor rotor/knives + a shock-sensor block with photos.
- **SWI id:** none (EREMA training reference, Dutch)
- **Scope:** (1) Messen en messenhouders (knives and knife holders in the Compactor); (2) Schoksensor eenheid (shock-sensor unit, type PCK) — detects metal parts stuck/flying in the Compactor and auto-stops the cutter + screw motors.
- **Related:** `EREMA-compactor-vaste-messen-demonteren-naslijpen__305_CeDo64.md`, `REF-roterende-messen-HSS-HM-compactor__300_CeDo63.md`, `EREMA-compactor-PCU__171_CeDo52.md`.

---

## Block 1 — Messen en messenhouders (Knives and knife holders)
Heading only + 2 photos (no body text):
- **Photo left:** the compactor rotor disc viewed from above — a large circular plate with radial knife slots and multiple fixed knife blades arranged around the rim; blue/teal alignment tools or spacers standing on the disc.
- **Photo right:** close-up of the compactor tub wall showing the **messenhouder** (knife holder) bracket and a mounted knife blade (dark rectangular blade clamped in a holder against the bowl wall).

(No numeric values or step table in this block — purely a labelled photo reference of the rotor/knife layout.)

---

## Block 2 — Schoksensor eenheid (Shock-sensor unit)

### "Bestaat uit:" (Consists of:)
- **Schoksensor op de PCU-wand** — shock sensor on the PCU wall.
- **Evolutie-eenheid is in de kast (verschillende modellen gebruikt in de loop der jaren!)** — evaluation unit is in the cabinet (different models used over the years!).
- Photos: black shock sensor (piezo-type puck with cable) + a yellow/black indicator module in the switch cabinet labelled **"PCK"** (the indicator type).

### Algemene functie: (General function — verbatim, glossed)
- **Metalen onderdelen die vast komen te zitten in de Compactor kunnen aanzienlijke schade aan de hele machine veroorzaken.** — Metal parts that get stuck in the Compactor can cause considerable damage to the whole machine.
- **Alle EREMA (behalve VACUREMA) zijn standaard uitgerust met deze schoksensor** om grote metalen onderdelen te detecteren en te scheiden. — All EREMA machines (except VACUREMA) are standard-equipped with this shock sensor to detect and separate large metal parts.
- Working principle: metal parts penetrating the Compactor generate specific **structuurgeluidstrillingen** (structure-borne sound vibrations). The shock sensor "hears" these vibrations on the Compactor and converts them into voltage signals, analysed by the **indicator in de schakelkast** (indicator in the switch cabinet). The indicator is designed to distinguish between normal/usual vibrations and vibrations caused by flying metal parts (of a certain size). When metal parts are detected, the indicator **stops the cutter motor (snijmotor) and the screw motor (schroefmotor)** to prevent further damage. Sensitivity of the indicator **(type PCK)** can be set on the **draaiknop** (rotary knob / potentiometer).
- **Gevoeligheid (sensitivity) adjustment:** can be adjusted on the rotary potentiometer during production, BUT the adjustment is only accepted once the supply voltage has been switched off and on again! To test the setting, use a hammer and tap lightly near the sensor at the cutter connection. If the setting is correct, the indicator activates and the cutter (snijder) and extruder motors are automatically switched off.

---

## Open-question hits
- **Q30 / control interpretation:** confirms a hardware safety interlock — shock sensor (PCK indicator) auto-stops **snijmotor + schroefmotor** on metal-impact detection. Good sim event: "metal detected → cutter + screw motors trip." Sensitivity is a tunable potentiometer setting (latched only after power cycle).
- **Q28 (TITECH / metal detection):** distinct system — this is the EREMA in-Compactor shock sensor (structure-borne), not the TITECH NIR sorter. Complements the plant's metal-rejection story (TITECH ejects upstream; shock sensor is the last-ditch in-machine protection).
- No throughput/temperature/water-routing values here (Q9/Q15/Q5 etc. not addressed).
- Machine-family note: **VACUREMA does NOT have this shock sensor**; all other EREMA lines do.

## Notes
- Indicator type explicitly **"PCK"** — worth using as the in-game component name for the compactor metal-shock safety unit.
- No revision/date/SWI number on the sheet.
