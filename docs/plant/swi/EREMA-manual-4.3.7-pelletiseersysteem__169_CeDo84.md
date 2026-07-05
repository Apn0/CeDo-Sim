# EREMA Operating Manual §4.3.7 — Pelletiseersysteem (HMI screen)

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/169_CeDo84.pdf` (1 page)
**Doc type:** Not a SWI. Page from the **EREMA operating manual** (Dutch translation), section **4.3.7 Pelletiseersysteem** (pelletising system HMI). Machine/SCADA spec — extracted exhaustively.

## §4.3.7 Pelletiseersysteem (verbatim + gloss)

> "Door op de knop 'Pelletiseersysteem' [icon] te drukken in het aanraakscherm 'Componenten selecteren' (zie 4.3 Componentenbediening op pagina 88) wordt het volgende aanraakscherm geopend."
> *(Pressing the 'Pelletising system' button on the 'Select components' touchscreen (see 4.3 Component operation, p.88) opens the following touchscreen.)*

> "Bedieningsniveau = [icon: 1→9]" *(Operating/authorisation level.)*

**Fig. 56: Pelletiseersysteem aanraakscherm** — embedded photo of the EREMA HMI touchscreen (black background, EREMA logo top-right). Shows a 3D render of the **pelletiser machine (die-face cutter + drive motor, labelled "EREMA")** with live value tiles overlaid:
- Header timestamp "10:56:29 09/05/2023", "Rx" mode indicator.
- Left-column status readouts (0 values, machine idle): rpm "0", red alarm tile "2N4" [unsure], "0", "0 %".
- Value tiles near the machine (verbatim labels, best reading):
  - **"MT < PEL — 0 °C"** (melt temperature upstream of pelletiser)
  - **"MP < PEL — 0 bar"** (melt pressure upstream of pelletiser)
  - **"MP<P.. — 0 °C"** [unsure]
  - **"[Mes-]snelheid — 0 rpm"** *(knife speed)*
  - **"[Init.] flow — 0 %"** [unsure]
  - **"0 °C"** die/water temp tile
- Right-side buttons: **"Pellet diverter positive"** [unsure label] and **"Prüfen 1 / Proefdr..1"** [unsure].

### Readout definitions (verbatim):
> **"Smelttemperatuur stroomopwaarts van de pelletiseermachine — MT < PEL"** — tile "MT < PEL — 0 °C"
> "toont de huidige smelttemperatuur stroomopwaarts van de pelletiseermachine"
> *(Melt temperature upstream of the pelletiser — shows the current melt temperature upstream of the pelletiser machine.)*

> **"Smeltdruk stroomopwaarts van pellitizer — MP < PEL"** — tile "MP < PEL — 0 bar"
> "toont de huidige smeltdruk stroomopwaarts van de pelletiseermachine"
> *(Melt pressure upstream of the pelletiser — shows the current melt pressure upstream of the pelletiser machine.)*

### Info/warning box (verbatim):
> "Als de smeltdruk boven een grenswaarde (**160 bar**) stijgt, worden de Compactor (configureerbaar; zie 4.3.4.1 Instellingen op pagina 101), de extruder en het pelletiseersysteem onmiddellijk uitgeschakeld."
> *(If the melt pressure rises above a limit value (**160 bar**), the Compactor (configurable; see 4.3.4.1 Settings, p.101), the extruder and the pelletising system are immediately switched off.)*

## Notes / open-question hits
- **Q15/Q33 (extruder/pelletiser interlocks & sensors):** Documents two live HMI signals — **MT<PEL** (melt temperature upstream of pelletiser, °C) and **MP<PEL** (melt pressure upstream of pelletiser, bar). Critical interlock: **melt pressure > 160 bar (configurable) instantly trips Compactor + extruder + pelletiser.** This is the hard safety limit sitting just above the FORM-008 kopfilter operating pressures (3a 120-150 bar, 3b 140-155 bar) — i.e. the operating window is deliberately kept under the 160-bar trip. Directly usable for sim over-pressure trip modelling.
- **Q30 (units):** confirms melt pressure in **bar**, melt temperature in **°C**, knife/roll speed in **rpm** on the EREMA HMI. Supports plant convention: pelletiser/extruder pressures in bar, drive speeds in rpm.
- **Q33 (real power/HMI exports):** This is the actual EREMA HMI the operator uses — "Bedieningsniveau" (operating levels 1-9), Fig. 56 pelletising screen. Confirms SCADA source is the EREMA touch panel; no raw power export on this page.
- Machine family reconfirmed as **EREMA** (companion to 166/167 EREMA sheets). Screen dated 09/05/2023.
