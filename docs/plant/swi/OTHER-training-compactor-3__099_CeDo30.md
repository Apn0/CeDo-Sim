# Training flipbook slide -3- — De Compactor (the compactor / agglomerator)

- **Doc type:** OTHER — training presentation slide (flipbook), NOT a SWI
- **swi_id:** OTHER:training-slide
- **Title (NL):** De Compactor
- **Title (EN):** The compactor (film agglomerator/densifier)
- **Slide number:** -3-
- **Series:** Cedo Kunstofrecycling training deck, Lean Practitioner
- **Year:** 2024
- **Source file:** 099_CeDo30.pdf
- **Scope:** Explains the RPM/Temperature/Power (KW) balance triangle inside the compactor

## Content (verbatim NL + EN gloss)

**Body text -3-:**
> "Bij het verhogen van rpm zal T omlaag gaan en"
> "Bij verhogen van kw compactor zal de T hierbinnen omhoog gaan"

EN: "When increasing rpm, T (temperature) will go down, and — when increasing the kW of the compactor, the T inside it will go up."

**Diagram — a triangle (process balance):**
- **Apex (top) = Temperatuur / T** (temperature).
- **Bottom-left corner = RPM / Toerental** (rotational speed).
- **Bottom-right corner = KW / Vermogen** (power).
- Left edge annotation: **"Toevoeging materiaal"** (adding material) with an arrow pointing inward toward the apex.
- Right edge annotation: **"Toevoeging van water"** (adding water) with an arrow pointing inward toward the apex.
- Inside, near center: label **"Compactor"**.
- Left-inner ladder of material states from bottom to mid: **plastisch → smelt → koud** (plastic → melt → cold) reading up the left leg — i.e., a gradient of material condition.
- Right-inner label: **"Schuif"** (slide/plunger — the compactor discharge screw/ram).
- (Faint ghost text bleeding through: "Pagir"/"...roef" from adjacent pages — not part of this slide.)

**Footer:** "2024 — Cedo Kunstofrecycling" + LEAN PRACTITIONER badge.

## Notes / answers to open questions
- **Q30 (power_CC units):** This slide labels the compactor power axis as **KW / Vermogen** — supports that compactor "power" (power_CC) is expressed in **kW**. The compactor is controlled by a balance of **RPM (toerental), Temperatuur (T), and KW (vermogen/power)**.
- **Compactor operating principle (for sim modeling):**
  - Increasing **RPM** → lowers internal **temperature T**.
  - Increasing **KW (power draw)** → raises internal **temperature T**.
  - **Adding material** and **adding water** both push toward the temperature apex (they are the two operator inputs that shift the balance).
  - Material passes through states **cold → melt → plastic** as it is worked; when correctly plasticised it is pushed out by the **schuif (discharge slide/screw)**.
- Confirms the compactor is a **thermo-kinetic film densifier/agglomerator** where operators trim RPM, power and water/material feed to hold the plasticising temperature — directly usable as the compactor control model in the simulator.
