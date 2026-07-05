# EREMA Compactor — Vaste messen: demonteren/monteren/afstellen + naslijpen (fixed knives)

- **Source file:** `305_CeDo64.pdf` (single page, EREMA compactor manual excerpt, scanned; Fig. 90 & Fig. 91)
- **SWI id:** none (EREMA manual — Compactor knife maintenance; "Process combinatie")
- **Title:** Demonteren, monteren en afstellen van vaste messen / Naslijpen van de vaste messen / Scherpe-stompe messen in de Compactor
- **Scope:** Compactor (EREMA pre-conditioning unit) fixed-knife (*vaste messen*) removal, fitting, adjustment, and regrinding; sharp vs blunt knife effects.
- **References:** Fig. 90 (knife/rotor cross-section), Fig. 91 (knife grind geometry), DIN ISO 1302 (surface quality). Part of EREMA compactor knife family (see messen-matrijsplaat, EREMA-compactor-PCU docs).

## Header / Safety (let op pictogram = triangle warning)
- "Process combinatie" (process combination — section header).
- **let op (warning triangle pictogram):** "zorg tijdens werkzaamheden aan de Compactor voor voldoende ventilatie, schakel de hoofdschakelaar uit en beveilig deze tegen opnieuw inschakelen."
  - EN: *During work on the Compactor ensure sufficient ventilation, switch off the main switch and secure it against being switched on again (LOTO).*

## Demonteren, monteren en afstellen van vaste messen (full text)
"Merk op dat de uitstekende lengte van de vaste messen (4) kan worden aangepast. Zorg ervoor dat de afstand tussen de roterende messen (5) en de vaste messen (4) minstens **10 mm (1)** bedraagt. Kleinere afstanden kunnen leiden tot vastlopen van de rotorschijf en breuk van de messen. Bovendien mag de voorste hoek (2) (zie ook fig. 90) van het vaste mes niet in de tank uitsteken, omdat dan folie, stroken enz. dan vast kunnen komen te zitten, wat er ook toe kan leiden dat de messen Compactor vastloopt. Verwijder de bevestigingsschroef (3) en duw het vaste mes (4) aan de buitenkant uit de geleiding."

EN gloss: *The protruding length of the fixed knives (4) can be adjusted. Ensure the gap between the rotating knives (5) and the fixed knives (4) is at least **10 mm (1)**. Smaller gaps can cause the rotor disc to jam and knives to break. The front corner (2) (see fig. 90) of the fixed knife must not protrude into the tank, otherwise film/strips etc. can get stuck, which can also jam the Compactor knives. Remove fixing screw (3) and push the fixed knife (4) out of the guide from the outside.*

### Fig. 90 (description)
Cross-section of rotor disc / knife assembly. Callouts: (1) gap = min 10 mm between rotating & fixed knife; (2) front corner (*voorste hoek*) of fixed knife; (3) fixing screw (*bevestigingsschroef*); (4) fixed knife (*vast mes*); (5) rotating knives (*roterende messen*). Curved rotor housing shown.

## Naslijpen van de vaste messen (regrinding fixed knives)
"HSS vaste messen worden vooral gebruikt voor het verwerken van strips, afsnijdsels, spoelen, touwen, enz. Hun levensduur is aanzienlijk hoger dan die van de rotormessen."
- EN: *HSS fixed knives are mainly used for processing strips, cut-offs, spools, ropes etc. Their service life is considerably higher than that of the rotor knives.*
- "Oppervlakte kwaliteit die nodig is voor naslijpen: **N5 volgens DIN ISO 1302**" = *Surface quality required for regrinding: N5 per DIN ISO 1302.*

### Fig. 91 (description)
Knife blade profile drawing. Grind angle **50°** at the cutting edge; blade length dimension **L_min ≈ 45 mm (1.77")**.

## Scherpe/stompe messen in de Compactor (sharp/blunt knives)
**Stompe messen (blunt knives):**
- Hebben minder snijkracht — *have less cutting force*
- Creëren alleen warmte door wrijving — *only create heat by friction*
- Verlagen de verwerkingscapaciteit — *reduce processing capacity*
- Hebben veel waterinjectie nodig — *need a lot of water injection*
- Hebben een instabiele werking van de lijn — *cause unstable operation of the line*

**(red bold callout):** "Alleen scherpe messen mogen gebruikt worden om de Compactor ten volle te benutten!"
- EN: *Only sharp knives may be used to fully utilise the Compactor!*

### Photos (2, right side)
- Top: close-up of worn/blunt compactor knife edge (metallic, dirty, rounded edge).
- Bottom: view of compactor rotor/tank interior showing knife holders / two round bosses.

## Key values (verbatim)
- Min gap rotating↔fixed knife: **10 mm**
- Grind angle: **50°**
- Min blade length after grind: **L_min ≈ 45 mm (1.77")**
- Regrind surface quality: **N5 (DIN ISO 1302)**
- Fixed knives material: **HSS**

## Q&A hits
- **Q24 (densities / compactor):** indirect — blunt knives reduce throughput & raise water injection, i.e. affect bulk-density behaviour; no numeric densities here.
- Reinforces EREMA Compactor knife-maintenance model (sharp knives mandatory; 10 mm gap). No direct numbered-question answer, but supports compactor mechanics for the sim.
