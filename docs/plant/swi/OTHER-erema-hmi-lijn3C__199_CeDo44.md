# EREMA BluPort HMI screenshot — LIJN 3C (fourth frame, 02:20:34)

- **Doc id:** OTHER (photo of HMI touchscreen), not a numbered SWI
- **Source file:** `199_CeDo44 (3).pdf`
- **Scope:** Live process values, extruder line 3C, timestamp **21-12-2024 02:20:34** — essentially the same instant as `198_CeDo43` (02:20:32), adjacent duplicate frame.
- **Near-duplicate of** the 196/197/198 LIJN-3C series. Same stickers (`WAARSCHUWING…` / `STAAT Afzuiging compactor AAN`), blue `LIJN 3C` plaque, `BluPort EREMA` branding.

## Recipe header
`Rx  LDPE 800 kg/h  22.04.2024 IBN`.

## Left vertical gauge column (verbatim)
- `2:20:34  21-12-2024`
- `110 °C` / `220,4 kW`
- `105 rpm` / `63 %` / `3553 h`
- `296 bar` (pre-filter, orange)
- `26 bar` (filter Δ)
- `206 bar` (post-filter)
- `1372 kg/h` (output)

## Trend chart
- Time axis `2:03:53` → `2:20:32` (gridlines 2:03:53 / 2:08:03 / 2:12:13 / 2:16:23 / 2:20:32).
- Traces: Toevoer actief (blue), PCU-vermogen (red ~230), PCU-temperatuur 1 (green flat top), AIS-positie (yellow ~150).

## AutoPro control = `Uit` (OFF).

## Right/lower tiles (verbatim)
- `PCU-vulpeil  269 cm`
- `PES-toerental  75 %`
- `TEU-toerental  25 %`
- `BC1-toerental  60 %`
- `EX1-vermogen  224,6 kW`
- `AIS-positie  70 %`
- `PCU-temp. 1  110 °C`
- `PCU-belasting  70 %`
- `EX1-toerental  105 rpm`
- `PCU-vermogen  220,4 kW`
- `EX1-belasting  63 %`
- `EX1-IZ1  94 °C`
- Right-edge tile: `229,2 kW`.

## Answers
- **Q9/Q21:** 3C output **1372 kg/h** (nameplate 800 kg/h). Melt 296/26/206 bar.
- Fully consistent with the 196/198/197 envelope; no new field values. Confirms the four LIJN-3C HMI photos (196,197,198,199) are a burst captured 02:17–02:24 on 21-12-2024, giving redundant steady-state data for the sim's 3C extruder model.
