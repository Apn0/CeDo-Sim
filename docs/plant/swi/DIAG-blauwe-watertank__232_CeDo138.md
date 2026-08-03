# Diagram — Blauwe watertank (blue water tank) connections (photo)

- **Source file:** `232_CeDo138.pdf`
- **Doc type:** OTHER — engineering sketch / connection diagram
- **swi_id:** OTHER:DIAG-blauwe-watertank
- **Author (caption bottom-right):** HULTINK Sander — "Blauwe tank water" — dated **2023-09-27**
- **Line:** general (central water buffer serving lines 1, 5, and extruders 3a/3b)
- **Pages:** 1

## Photo description
A single sheet in a ring binder (orange divider tabs at right). Centered is a grey rectangle labelled **"Blauwe watertank"** (blue water tank) drawn with several **port holes / nozzles** on its top, left, and right edges. Leader lines label each connection port. Caption bottom-right: "HULTINK Sander / Blauwe tank water / 2023-09-27".

## Connection ports (transcribed, by side)

**Top edge (ports, left→right):**
- **Loze leiding** (blind/dead line — capped/unused connection) — appears TWICE on top (two "Loze leiding" labels)
- **Centrale waterbak extruder 3a en 3b** (central water basin, extruders 3a and 3b) — top-right port

**Left edge (ports, top→bottom):**
- **Lijn 1 centrale waterbak achter controle tafel** (line 1 central water basin behind the control table)
- **Loze leiding** (dead line)
- **Lijn 5 waterbak vacuum** (line 5 water basin, vacuum)
- **Vers kanaalwater** (fresh canal water — make-up water supply)
- **Centrale waterbak extruder 3a en 3b** (central water basin extruders 3a and 3b) — left-lower port
- **Procespomp 1 EOP** (process pump 1, EOP)

**Right edge:**
- **Centrale waterbak extruder 3a en 3b** (right port)

## Answers to open questions (HIGH VALUE)
- **Q10 (Blauwe tank — role/connections):** The **Blauwe watertank is the CENTRAL water buffer** of the plant. It interconnects:
  - **Lijn 1** central water basin (behind the control table)
  - **Lijn 5** water basin (vacuum)
  - **Central water basin for extruders 3a and 3b** (multiple ports — top-right, left-lower, right — so the 3a/3b extruder water basin ties into the blue tank at several points)
  - **Vers kanaalwater** = fresh canal water make-up feed
  - **Procespomp 1 EOP** = process pump 1 to/from EOP
  - Several **Loze leidingen** (capped spare connections)
  - [No volume or pump specs given on this sheet — Q10 volume still open; but the connection topology is now fully mapped.]
- **Q12 (EOP):** **EOP** appears as **"Procespomp 1 EOP"** — a process pump feeding/serving the EOP. EOP is the plant's water treatment/effluent destination ("Riool naar EOP" in FORM checklists). EOP = the (end-of-pipe) effluent/water-treatment plant. [unsure: EOP likely "Effluent/Eind-Ontgeleiding Purificatie" or a proprietary CeDo/Geleen site name — best reading: EOP = the site water-treatment / effluent facility; "riool naar EOP" = sewer to EOP.] Confirms **Procespomp 1** links the blue tank to the EOP.
- **Q5 (water routing — blue tank / fresh water / EOP):**
  - **Vers kanaalwater (fresh canal water)** feeds INTO the blue tank (make-up).
  - Blue tank connects to **Lijn 1, Lijn 5 vacuum, and extruder 3a/3b central water basins** — it is the shared cooling/process water reservoir across lines.
  - **Procespomp 1 EOP** links blue tank ↔ EOP (water treatment). This is the "ZSS ↔ blauwe tank" style routing the Q5 question asks about — here the treatment node is named EOP (via Procespomp 1).
- **Q1 (ZSS / water zuivering):** Not named "ZSS" here, but this diagram identifies the water-treatment endpoint as **EOP** reached via **Procespomp 1**. Possible ZSS and EOP refer to the same treatment system, or ZSS is a sub-unit; cross-check with other water docs. (This sheet uses EOP, not ZSS.)
- **Naming for sim:** Central water reservoir = **"Blauwe watertank"** (literally the blue tank). It buffers water for lines 1, 5, and extruders 3a/3b; topped up with fresh canal water; drained/circulated to EOP via Procespomp 1.
