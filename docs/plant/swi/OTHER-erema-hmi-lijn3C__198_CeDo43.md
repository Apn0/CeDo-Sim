# EREMA BluPort HMI screenshot — LIJN 3C (third frame, 02:20)

- **Doc id:** OTHER (photo of HMI touchscreen), not a numbered SWI
- **Source file:** `198_CeDo43 (3).pdf`
- **Scope:** Live process values, extruder line 3C, timestamp **21-12-2024 02:20:32** (chronologically between 196 @02:17 and 197 @02:23).
- **Near-duplicate of** `OTHER-erema-hmi-lijn3C__196_CeDo37.md` / `__197_CeDo48.md`.
- Same stickers/plaque/branding as 196 & 197. PCU hopper icon rendered as **blue water-drop cluster** this frame (vs grey dots in 196/197) — indicates PCU fill/level graphic state.

## Recipe header
`Rx  LDPE 800 kg/h  22.04.2024 IBN`.

## Left vertical gauge column (verbatim)
- `2:20:32  21-12-2024`
- `110 °C` / `217,9 kW`
- `105 rpm` / `63 %` / `3553 h`
- `294 bar` (pre-filter)
- `27 bar` (filter Δ)
- `206 bar` (post-filter)
- `1368 kg/h` (output)

## Trend chart
- Time axis `2:03:51` → `2:20:30` (gridlines 2:03:51 / 2:08:01 / 2:12:11 / 2:16:21 / 2:20:30).
- Traces: Toevoer actief (blue square-wave), PCU-vermogen (red ~230), PCU-temperatuur 1 (green flat ~top), AIS-positie (yellow ~150).

## AutoPro control = `Uit` (OFF).

## Right/lower tiles (verbatim)
- `PCU-vulpeil  268 cm`
- `PES-toerental  75 %`
- `TEU-toerental  25 %`
- `BC1-toerental  60 %`
- `EX1-vermogen  225,5 kW`
- `AIS-positie  70 %`
- `PCU-temp. 1  110 °C`
- `PCU-belasting  69 %`
- `EX1-toerental  105 rpm`
- `PCU-vermogen  217,9 kW`
- `EX1-belasting  63 %`
- `EX1-IZ1  94 °C`
- Extra tile visible right edge: `229,2 kW` (labelled near PCU-vermogen tile — likely a second power readout / EX1-vermogen instantaneous).

## Answers
- **Q9/Q21:** 3C output **1368 kg/h** at 800 kg/h nameplate (matches 196/197 trend of ~1.3–1.4 t/h). Melt pressures 294/27/206 bar.
- **Q30:** consistent units — kW / % / rpm / bar / cm / kg/h.
- **Three-frame series (196/198/197) gives a real steady-state operating envelope for the sim's line-3C extruder model:** screw 102–105 rpm, EX1 load 60–63 %, PCU load 68–72 %, melt temp 110–111 °C, EX1-IZ1 93–95 °C, pre-filter 284–294 bar, filter Δ 26–27 bar, post-filter 203–206 bar, output 1294–1376 kg/h, PCU fill 258–268 cm, PES 75–80 %, TEU 25–30 %, operating hours 3553 h.
