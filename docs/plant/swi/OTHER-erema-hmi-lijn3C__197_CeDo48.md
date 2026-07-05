# EREMA BluPort HMI screenshot — LIJN 3C (second frame, +6 min)

- **Doc id:** OTHER (photo of HMI touchscreen), not a numbered SWI
- **Source file:** `197_CeDo48 (3).pdf`
- **Type:** Single photo of the EREMA BluPort operator screen on line 3C
- **Scope:** Live process values for extruder line 3C, timestamp **21-12-2024 02:23:52** (~6 min after `196_CeDo37`)
- **Near-duplicate of** `OTHER-erema-hmi-lijn3C__196_CeDo37.md` — same machine/screen, later timestamp, different live values.
- Same stickers as 196: yellow `STAAT / Afzuiging compactor / !!! AAN !!!`; white safety sticker top-left; blue `LIJN 3C` plaque; `BluPort EREMA` branding.

## Recipe header
`Rx  LDPE 800 kg/h  22.04.2024 IBN` (identical to 196).

## Left vertical gauge column (verbatim)
- Clock: `2:23:52  21-12-2024`
- `111 °C` / `225,5 kW`
- `105 rpm` / `62 %` / `3553 h`
- `287 bar` (orange/amber — pre-filter melt pressure)
- `27 bar` (filter Δ)
- `205 bar` (post-filter)
- `1376 kg/h` (output)

## Central trend chart
- Time axis `2:07:11` → `2:23:50` (gridlines 2:07:11 / 2:11:21 / 2:15:31 / 2:19:41 / 2:23:50), 21-12-2024.
- Same 4 traces: **Toevoer actief** (blue square-wave), **PCU – vermogen** (red ~200), **PCU – temperatuur 1** (green flat top), **AIS – positie** (yellow ~150).

## AutoPro control
- `AutoPro-control` = **`Uit`** (OFF).

## Right/lower data tiles (verbatim)
- `PCU-vulpeil  258 cm`
- `PES-toerental  80 %`
- `TEU-toerental  30 %`
- `BC1-toerental  0 %` (belt conveyor stopped this frame)
- `EX1-vermogen  222,1 kW`
- `AIS-positie  70 %`
- `PCU-temp. 1  111 °C`
- `PCU-belasting  72 %`
- `EX1-toerental  105 rpm`
- `PCU-vermogen  225,5 kW`
- `EX1-belasting  62 %`
- `EX1-IZ1  95 °C`

## Comparison 196 vs 197 (drift over ~6 min)
| Field | 196 (02:17) | 197 (02:23) |
|---|---|---|
| Melt temp (top) | 110 °C | 111 °C |
| PCU-vermogen | 215,1 kW | 225,5 kW |
| EX1-toerental | 102 rpm | 105 rpm |
| EX1-belasting | 60 % | 62 % |
| Pre-filter bar | 284 | 287 |
| Filter Δ bar | 26 | 27 |
| Post-filter bar | 203 | 205 |
| Output kg/h | 1294 | 1376 |
| PCU-vulpeil | 265 cm | 258 cm |
| PES / TEU | 75/25 % | 80/30 % |
| PCU-belasting | 68 % | 72 % |
| BC1-toerental | 60 % | 0 % |

## Answers to open questions
- **Q9/Q21 throughput:** line 3C recipe nameplate **LDPE 800 kg/h**; live output here **1376 kg/h** (196 showed 1294). Real running rate ~1.3–1.4 t/h on 3C.
- **Q30 units confirmed** (see 196): power in **kW**, load in **%**, screw speed in **rpm** with a parallel **%**, output in **kg/h**, PCU fill in **cm**, melt pressure in **bar**.
- **Q29:** reconfirms LIJN 3C = EREMA extruder/pelletiser line, not a wash line.
