# "Werking Titech tomra" — Pagina 2 van 3 (AUTOSORT working principle + EM sensor)

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/173_CeDo49.pdf` (1 page = **page 2 of 3** of "Werking Titech tomra")
**Doc type:** Not a SWI. TITECH/TOMRA sorter working-principle reference. Companion to page 3 (`172_CeDo50`).

## Header
> "Werking Titech tomra" — "Pagina 2 van 3"

## Embedded diagram — "Afb. 2: Werkingsprincipe" (Fig. 2: Working principle)
Schematic of the sorter: material fed onto a conveyor belt from the left; an orange box (spectrometer scanner, item 2) mounted above the belt scanning downward; at the belt end, objects split into two bins via air jets. Numbered callouts:
1. **Voeding van niet-gesorteerd materiaal** *(feed of unsorted material)*
2. **Spectrometerscanner** *(spectrometer scanner)*
3. **Afscheidingsruimte** *(separation chamber/space)* — two collection bins with a splitter, ejected material blown into one, remainder falls into the other.

## Body (verbatim transcription)
> "Aanvoermateriaal wordt gelijkmatig op een transportband (1) gestort, waar dit door de **AUTOSORT-scannereenheid** en een **optionele EM-sensor** wordt gescand. Tijdens het scannen wordt de complete breedte van de riem lineair gescand. Als een sensor materiaal detecteert dat dient te worden gesorteerd, verzendt de schakelkast de opdracht om de betreffende kleppen van het **kleppenblok** aan het einde van de transportband te blazen. Het materiaal dat wordt gesorteerd, wordt door lucht over de **splitterrol** in de **afscheidingsruimte (3)** opgeheven. De rest valt op een lagere transportband of in de **bunker**."

**Gloss:** Incoming material is spread evenly onto conveyor (1) where it is scanned by the **AUTOSORT scanner unit** and an **optional EM sensor**. During scanning the full belt width is scanned linearly. When a sensor detects material to be sorted, the control cabinet commands the relevant valves of the **valve block (kleppenblok)** at the belt end to blow. The sorted material is lifted by air over the **splitter roll (splitterrol)** into the **separation chamber (3)**. The rest falls onto a lower conveyor or into the **bunker**.

## Notes / open-question hits (Q28 — MAJOR HITS)
- **Q28 — EM sensor fitted?** DIRECT ANSWER: the scanner is an **AUTOSORT scanner unit** with an **"optionele EM-sensor"** *(optional EM sensor)*. So an EM (electromagnetic / metal) sensor is an **option** on the TITECH AUTOSORT — the spec/report treats it as optional, not standard. (Page 3 described NIR only; page 2 confirms EM is an add-on option.) Whether CeDo's specific units had the EM option fitted is not stated on this page — [unsure], but the machine platform supports it.
- **Q28 — machine model:** confirms the TITECH sorter platform is **TOMRA/TITECH AUTOSORT** (the modern name; "PolySort UHR" on p.3 is the sorter product family). Scanner = spectrometer (NIR).
- **Q28 — sorting mechanism:** full belt width **linearly scanned**; ejection via a **kleppenblok (valve block)** of air valves at the belt end; ejected material lifted over a **splitterrol (splitter roll)** into the **afscheidingsruimte**; reject/remainder falls to a lower conveyor or into the **bunker**. This ties the sorter reject stream directly to the plant **bunker** (the cutter-compactor infeed bunker — FORM-008 rows 3-4 "Bunker speed / height").
- **Q28 — page content map:** p.2 = working principle diagram + AUTOSORT/EM/valve-block/splitter-roll text (this doc); p.3 = PolySort UHR NIR detail, belt speed 2.5-3.0 m/s, polymer types (`172_CeDo50`). Page 1 still undigested.
- **Q2 / bunker linkage:** the "rest valt ... in de bunker" confirms the sorter's main (accepted PE) stream continues to the bunker → cutter-compactor. Useful for the sim's material-flow graph (sorter → bunker → compactor → extruder).
