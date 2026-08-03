# EREMA HMI — SV / extruder live values (Dutch, screen photo)

- **Source file:** `257_CeDo5 (3).pdf`
- **Type:** Single photo of an EREMA HMI touchscreen (dirty/scratched glass, glare bottom-left). Dutch labels. NOT a Cedo-PROD-SWI.
- **Mimic shown:** The **SV** (smeltvergaarbak / screw-compactor pre-conditioning vessel feeding the extruder) hopper + **extruder** barrel with temperature zones. Right edge shows an auger/extruder screw pictogram labeled "extruder" and a "smelt..." (melt) label top-right, plus an up-arrow "terug"/back navigation button (bottom-right rounded square with up-arrow).
- **EREMA diamond logo** visible top-right corner.

## Live values transcribed verbatim (label — value — unit)

Left / lower cluster:
- **afzuiging** — **0** — (no unit shown) — (*extraction/suction*)  [top-left, partially "afzuig..."]
- **afzuiging 1** — **55** — **%** — (*extraction 1 / suction 1*)
- **SV-belasting** — **61** — **%** — (*SV load / compactor load*)
- **SV-vermogen** — **193** — **kW** — (*SV power*)
- **SV-vulpeil** — **45** — **cm** — (*SV fill level*)
- **SV-temperatuur** — **108** — **°C** — (*SV temperature*)
- **schuif** — **100** — **%** — (*slide/gate valve, between SV and extruder — 100% = fully open*)
- **ex - belasting** — **102** — **%** — (*extruder load*) [reads "ex - belasting"]
- **extr rpm** — **120** — **rpm** — (*extruder rpm, setpoint*)
- **[blue-highlighted] 120** — **rpm** — (*extruder rpm, actual/selected — value 120 in blue box*)

Right cluster — extruder barrel temperature zones (bottom→top along the screw, verbatim tag + value):
- **EZ-1** — **113** — **°C** — (*Einzugszone / infeed zone 1*)
- **ZZ-1** — **157** — **°C** — (*Zylinderzone / cylinder zone 1*)
- **ZZ-2** — **184** — **°C** — (*cylinder zone 2*)
- **ZZ-3** — **213** — **°C** — (*cylinder zone 3, topmost/nearest melt outlet*)

Top-right partial label: **"smelt..."** (melt / smeltdruk or smelttemperatuur — cut off).

## Interpretation for sim
- Confirms EREMA HMI reports the compactor as **"SV"** with these live channels: SV-belasting (%), SV-vermogen (kW), SV-vulpeil (cm), SV-temperatuur (°C). The **schuif** (slide gate) between SV and extruder is a controllable 0–100% element (here 100%).
- Extruder temperature profile rises along the screw: EZ-1 113 → ZZ-1 157 → ZZ-2 184 → ZZ-3 213 °C (infeed cooler, climbing toward the melt end).
- Extruder rpm 120 (both setpoint and actual), ex-belasting 102% (running slightly over nominal load).

## Open-question relevance
- **Q30 (units):** Direct evidence — Vermogen hoofdmotor reported in **kW** (SV-vermogen 193 kW); belasting/load in **%** (SV-belasting 61%, ex-belasting 102%); Snelheid in **rpm** (extr rpm 120); vulpeil in **cm** (SV-vulpeil 45 cm); afzuiging in **%** (55%).
- **Q15 (temp zones):** This is the *EREMA extruder barrel* zone profile (EZ-1/ZZ-1/ZZ-2/ZZ-3 = 113/157/184/213 °C), a different zone scheme than the 200-235-175-240-245-250-255 °C list in the open question — this EREMA HMI names zones EZ (Einzug) + ZZ (Zylinder), rising monotonically, no 175 dip here.
- No line number (3A/3B/3C/6) explicitly on screen, but the EREMA + Dutch labels + SV-vergaarbak terminology match the EREMA lines (3C / 6).
