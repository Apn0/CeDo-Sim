# EREMA reference — Compactor temperatuur & materiaalcirculatie (afb. 87)

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/176_CeDo56.pdf` (1 page)
**Doc type:** Not a SWI. EREMA manual/training page on correct Compactor temperature and material circulation. Extracted exhaustively.

## Body (verbatim transcription)

> "De juiste temperatuur in de Compactor hangt af van het materiaal en moet zo worden gekozen dat een goede voorverdichting wordt bereikt (verwekingspunt van de te verwerken polymeer) voor een goede extrudervulling (hoge output), maar met een veiligheidsmarge zodat de kunststof nog niet smelt in de Compactor (dit is gewoonlijk ongeveer **10-15 °C onder het smeltpunt** van de te verwerken kunststof)."

**Gloss:** The correct Compactor temperature depends on the material and must be chosen so good pre-compaction is achieved (softening point of the polymer) for good extruder filling (high output), but with a safety margin so the plastic does not yet melt in the Compactor — this is usually **about 10-15 °C below the melting point** of the plastic being processed.

**Embedded diagrams (two, side by side):**
- **LEFT (correct, no cross):** compactor bowl with material partly filled and two circular arrows showing **good material circulation** (toroidal flow) around the rotating knife plate at the bottom.
- **RIGHT (crossed out with a big X):** compactor bowl **overfilled** to the top — bad; no circulation.

> "Vooral bij het opstarten van de 'koude' Compactor moet ervoor worden gezorgd dat deze niet wordt overladen met materiaal voordat de gewenste motorbelasting is bereikt, omdat het materiaal nog niet is samengeperst (zie afb. 87 optimale materiaalcirculatie (links) en overvolle compator (rechts))."

**Gloss:** Especially when starting the "cold" Compactor, take care not to overload it with material before the desired motor load is reached, because the material is not yet compacted (see fig. 87: optimal material circulation (left) vs. overfilled compactor (right)).

## Notes / open-question hits
- **Q15 / Q33 (extruder & compactor temperatures):** Explains WHY the compactor runs at 123 °C (FORM-008 rows 19-20): the compactor temperature is deliberately set to the polymer **softening point (verwekingspunt), ~10-15 °C BELOW the melt point**, to pre-densify without melting. For LDPE (melt ~110-120 °C for LDPE; but recycled mixed PE softening higher), the 123 °C setpoint fits "soften, don't melt." "Hoger=plastificeren" on FORM-008 = going above this margin starts melting the flake in the compactor (bad). This is the authoritative rationale for the compactor setpoint.
- **Q20 (slow-running causes → REMEDIES):** DIRECT operational remedy. **Cause: overfilling the compactor (especially on cold start) before motor load is reached → material not yet compacted → poor circulation → poor extruder filling / low output.** **Remedy: on cold start, do NOT overload the compactor; feed gradually until desired motor load is reached, maintaining good toroidal material circulation (afb. 87 left).** Also: compactor temperature too low → poor voorverdichting → poor extruder filling (low output); temperature too high → melts in compactor (plastifies). Keep 10-15 °C under melt point. These are actionable start-up/slow-running remedies for the sim.
- **Q30 (Vermogen hoofdmotor / compactor motor load):** confirms **"motorbelasting" (motor load)** is the key control variable on compactor start-up — the operator feeds material until a **desired motor load** is reached. Supports interpreting the sim's "power_CC" (compactor power) and "Vermogen hoofdmotor" as the load-control signal. (Load target reached = compactor properly filled and circulating.)
- Companion to `171_CeDo52` (PCU = compactor) and `175_CeDo58` (air flush / sauna effect). Together they fully characterise the EREMA cutter-compactor stage for the sim.
