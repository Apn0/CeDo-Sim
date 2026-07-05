# EREMA HMI — SV / extruder live values (frame 2, Dutch, screen photo)

- **Source file:** `258_CeDo6 (3).pdf`
- **Type:** Single photo of the SAME EREMA HMI mimic as `257_CeDo5 (3).pdf` (`PHOTO-erema-hmi-SV-extruder-livevalues__257_CeDo5_3.md`), shot seconds apart. Same layout, same screen; only a few live process values drifted. Dutch labels, EREMA diamond logo top-right, "extruder" screw pictogram + up-arrow back button bottom-right.

## Live values transcribed verbatim (label — value — unit) — DELTAS vs frame 1 marked

- **afzuiging** — **0** — (*extraction, unchanged*)
- **afzuiging 1** — **55** — **%** — (*unchanged*)
- **SV-belasting** — **63** — **%** — (*was 61% in frame 1 → +2*)
- **SV-vermogen** — **199** — **kW** — (*was 193 kW → +6*)
- **SV-vulpeil** — **45** — **cm** — (*unchanged*)
- **SV-temperatuur** — **108** — **°C** — (*unchanged*)
- **schuif** — **100** — **%** — (*unchanged, gate fully open*)
- **ex - belasting** — **101** — **%** — (*was 102% → -1*)
- **extr rpm** — **120** — **rpm** — (*unchanged*)
- **[blue-highlighted] 120** — **rpm** — (*extruder rpm actual/selected, unchanged*)

Extruder barrel temperature zones (unchanged from frame 1):
- **EZ-1** — **113** — **°C**
- **ZZ-1** — **157** — **°C**
- **ZZ-2** — **184** — **°C**
- **ZZ-3** — **213** — **°C**

Top-right partial label: **"smelt..."** (melt).

## Notes
- Effectively a duplicate of 257; retained for completeness / to show live-value jitter (SV-belasting and SV-vermogen fluctuate a few percent / few kW while running steadily). Same open-question relevance as 257 — see `PHOTO-erema-hmi-SV-extruder-livevalues__257_CeDo5_3.md` (Q30 units confirmed: kW / % / rpm / cm / °C; Q15 EREMA barrel zones EZ/ZZ rising 113→157→184→213 °C).
