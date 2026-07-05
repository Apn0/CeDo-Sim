# FLOW — Lijn 1 flow diagram inclusief waterloops

- **Source file:** 244_CeDo126.pdf
- **Type:** Flow diagram (block chart) with water-loop overlay (purple/blue connector lines + red line)
- **Title (as printed):** "Lijn 1 flow diagram inclusief waterloops" ("Line 1 flow diagram including water loops")
- **Date:** 18-04-2023
- **Branding:** cedo logo bottom-right
- **Scope:** Full line 1 — infeed/metal detection → shredder → prewash → flotation → drying (Kufferath/MAS) → extrusion/compactor → pelletizing → weighing → MS/LS outdoor silo, PLUS the four water-treatment/supply subsystems and their routing.
- **Companion:** 239_CeDo125 (lijn1 material-only). This is the water-inclusive master.

## Material flow — Row 1 (top, left→right): infeed / metal / shred / prewash
1. **Metaal detectie band** ("metal detection belt") →
2. **Opzetband (Westa)** ("feed/loading belt, make Westa") →
3. **Shredder & band 1 onder shredder** ("shredder & belt 1 under shredder") →
4. **Magneetband (boven band 1)** ("magnet belt, above belt 1") →
5. **Band 2 (naar voorwas trommel)** ("belt 2, to prewash drum") →
6. **Band 2 (naar HPS/SGA)** ("belt 2, to HPS/SGA") →
7. **HPS (SGA) zware delen scheider** ("HPS (SGA) heavy-parts separator") → [routes down to Frictiescheider 6a/6b]

## Material flow — Row 2 (right→left): friction / mechanical dry / grind → flotation
- **Frictiescheider 6a** ("friction separator 6a") → **Mechanische droger 7a** ("mechanical dryer 7a") → **Ventilator 8a** ("fan 8a") →
- **Frictiescheider 6b** → **Mechanische droger 7b** → **Ventilator 8b** →
- both 8a/8b → **Maalmolen 1** ("grinding mill 1") →
- → **Ventilator 10a** → **Intrekschroef 11a** ("draw-in screw 11a") → **Flotatie tank**
- → **Ventilator 10b** → **Intrekschroef 11b** ("draw-in screw 11b") → **Flotatie tank**

## Material flow — Row 3 (left→right): flotation exit → Kufferath → MAS dry → transport
- **Uittrekschroef flotatie tank** ("draw-out screw flotation tank") → **Frictiescheider links rechts** ("friction separator left-right") → branches to:
  - **Kufferath 1** → **MAS buffer 1** → **MAS droger 1** ("MAS dryer 1") → **Transport ventilator 1 (Deltoid)** →
  - **Kufferath 2** → **MAS buffer 2** → **MAS droger 2** → **Transport ventilator 2 (Deltoid)** →
  - both → **Extruder silo**

## Material flow — Row 4 (right→left then to outdoor silo)
- **Compactor band** → **Compactor** → **Extruder incl laserfilter, vacuum en matrijs** ("extruder incl. laser filter, vacuum and die") → **Ontwaterzeef** ("dewatering sieve") → **Centrifuge** → **Weegschaal** ("weighing scale") → **Voorraad silo buiten (MS/LS)** ("outdoor storage silo MS/LS")

## Water subsystems (bottom row, purple/blue blocks) — Q1, Q5, Q10, Q12 answers
Four dark-purple/blue water blocks + connectors:
1. **Waterput & pomp was 1 naar ZSS** ("water well/pit & pump, wash 1, to ZSS") — mid-left dark-blue block. Collects wash-1 water, pumps it to ZSS.
2. **ZSS water zuivering systeem** ("ZSS water purification system") — bottom-left. **==> ZSS = a water purification/treatment system (waterzuivering)==** [Q1 ANSWER].
3. **Blauwe tank water voor was 1, 3a en 3b** ("blue tank, water for wash 1, 3a and 3b") — bottom, between ZSS and EOP. **==> Blauwe tank supplies wash water to washes 1, 3a AND 3b (shared across three lines)==** [Q10 partial: shared clean-water buffer tank; no volume/pump spec printed here].
4. **EOP water zuivering system** ("EOP water purification system") — bottom-center. **==> EOP = a water purification system==** [Q12 ANSWER: EOP is a waterzuivering (purification) system/plant; drains route to it].
5. **Koeltoren circuit inclusief voorbehandeld kanaalwater** ("cooling-tower circuit including pretreated canal water") — bottom-center dark-blue. Red line up to Extruder (hot side) + blue line — granulation/cooling water loop for extruder/pelletizer.
6. **Vers kanaalwater toevoer** ("fresh canal-water supply") — bottom-right dark-blue. Feeds fresh make-up water into the circuits.

## Water routing (connector lines) — Q5 answers
- **Waterput & pomp was 1 → ZSS** (labeled arrow "naar ZSS"): wash-1 dirty water pumped to ZSS purification.
- **ZSS water zuivering ↔ upstream:** ZSS returns clarified water up-line (purple lines run from ZSS up the left edge to Flotatie tank / Intrekschroef area) and connects to Blauwe tank.
- **Blauwe tank ← EOP / ZSS:** Blauwe tank is fed by the purification systems (ZSS + EOP arrows point into Blauwe tank), then distributes clean water to was 1 / 3a / 3b.
- **EOP water zuivering ↔ ZSS:** bidirectional purple arrows between EOP and ZSS blocks (water shared/cascaded between the two treatment systems); EOP also feeds Blauwe tank.
- **Koeltoren circuit → Extruder:** red line (hot) up into "Extruder incl laserfilter, vacuum en matrijs"; blue return line — closed cooling/granulation loop with pretreated canal water.
- **Vers kanaalwater toevoer:** fresh canal water enters the koeltoren circuit and the treatment chain as make-up.
- Purple lines from **Ontwaterzeef / Centrifuge** area run back down to ZSS/EOP (process water from dewatering returns to purification).

## Answers hunted
- **Q1 (ZSS meaning/location):** ZSS = "ZSS water zuivering systeem" = a **water purification system** for line 1 (bottom-left of diagram). Fed by "Waterput & pomp was 1 naar ZSS." Doc 244_CeDo126, block labels "Waterput & pomp was 1 naar ZSS" and "ZSS water zuivering systeem." [CERTAIN it is a waterzuivering system; the literal expansion of the initialism ZSS not spelled out.]
- **Q5 (water routing):** See "Water routing" section above — ZSS↔blauwe tank (ZSS/EOP feed blauwe tank), blauwe tank→was 1/3a/3b, koeltoren circuit→compactor/extruder (granulation/cooling), fresh canal water make-up, dewatering process water→ZSS/EOP. Confirmed directions from arrow overlay. Doc 244_CeDo126.
- **Q10 (blauwe tank):** "Blauwe tank water voor was 1, 3a en 3b" — clean-water buffer **shared across was 1, 3a, 3b**. No volume or pump specs printed on this diagram. Doc 244_CeDo126.
- **Q12 (EOP meaning):** "EOP water zuivering system" — EOP is a **water purification system/plant**; process drains route to it. (Earlier docs mention "Riool naar EOP" = sewer to EOP.) Doc 244_CeDo126. [Literal expansion of EOP initialism still not spelled out on-scan.]
- **LA1/LA2 (Q11):** Not labeled on this line-1 diagram (LA appears on 3A water-circuit docs). No new info here.
- **Note:** Two parallel prewash/dry trains (a/b) on line 1: Frictiescheider 6a/6b, Mechanische droger 7a/7b, Ventilator 8a/8b, Ventilator 10a/10b, Intrekschroef 11a/11b, Kufferath 1/2, MAS buffer 1/2, MAS droger 1/2, Transport ventilator 1/2 (Deltoid).
