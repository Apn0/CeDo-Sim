# EREMA BluPort HMI screenshot — LIJN 3C (fifth frame, 02:42:33)

- **Doc id:** OTHER (photo of HMI touchscreen), not a numbered SWI
- **Source file:** `200_CeDo55 (3).pdf`
- **Scope:** Live process values, extruder line 3C, timestamp **21-12-2024 02:42:33** — ~18 min after the 196–199 burst, latest frame in the LIJN-3C series.
- **Near-duplicate of** the 196/197/198/199 LIJN-3C series. Same white safety sticker top-left (`...VEILIGHEIDSCONTROLE / IN POSITIE`, `1 hollandisch`), yellow `STAAT / Afzuiging compactor / !!! AAN !!!` plaque, blue `LIJN 3C` plaque, `BluPort EREMA` branding.

## Recipe header
`Rx  LDPE 800 kg/h  22.04.2024 IBN` (identical to 196–199).

## Left vertical gauge column (verbatim, top→bottom)
- Clock/date: `2:42:33  21-12-2024`
- `110 °C` / `234,4 kW`
- `115 rpm` / `69 %` / `3554 h` (operating hours ticked up from 3553 → 3554)
- `298 bar` (pre-filter, orange/amber)
- `26 bar` (filter Δ)
- `209 bar` (post-filter)
- `1505 kg/h` (output)

## Central trend chart
- Time axis `2:25:53` → `2:42:32` on 21-12-2024 (gridlines 2:25:53 / 2:30:03 / 2:34:13 / 2:38:23 / 2:42:32).
- Left Y-axis 0–600, right Y-axis 0–250.
- Traces: **Toevoer actief** (blue square-wave, "feed active") ~50 band; **PCU – vermogen** (red ~250, higher than earlier frames); **PCU – temperatuur 1** (green flat ~top); **AIS – positie** (yellow ~150).

## AutoPro control box
- `AutoPro-control` = **`Uit`** (OFF).

## Right/lower data tiles (verbatim)
- `PCU-vulpeil  272 cm`
- `PES-toerental  80 %`
- `TEU-toerental  30 %`
- `BC1-toerental  70 %`
- `EX1-vermogen  246,9 kW`
- `AIS-positie  70 %`
- `PCU-temp. 1  110 °C`
- `PCU-belasting  74 %`
- `EX1-toerental  115 rpm`
- `PCU-vermogen  234,4 kW`
- `EX1-belasting  69 %`
- `EX1-IZ1  99 °C`
- Right-edge second power tile near PCU-vermogen: `234,5 kW`.

## Schematic (lower right)
Isometric EREMA machine graphic: inclined **BC1 conveyor belt** → **PCU** (hopper with blue water-drop fill cluster this frame) → **EX1 extruder** (EREMA-branded barrel).

## Comparison — this frame (200 @02:42) vs earlier burst (196 @02:17)
| Field | 196 (02:17) | 200 (02:42) |
|---|---|---|
| Melt temp (top) | 110 °C | 110 °C |
| PCU-vermogen | 215,1 kW | 234,4 kW |
| EX1-toerental | 102 rpm | 115 rpm |
| EX1-belasting | 60 % | 69 % |
| EX1-vermogen | 212,2 kW | 246,9 kW |
| Pre-filter bar | 284 | 298 |
| Filter Δ bar | 26 | 26 |
| Post-filter bar | 203 | 209 |
| Output kg/h | 1294 | 1505 |
| PCU-vulpeil | 265 cm | 272 cm |
| PCU-belasting | 68 % | 74 % |
| EX1-IZ1 | 93 °C | 99 °C |
| Operating hours | 3553 h | 3554 h |

## Answers
- **Q9/Q21:** 3C output **1505 kg/h** here — the highest of the series; the line ramped from ~1.3 t/h (02:17) to ~1.5 t/h (02:42) by pushing screw 102→115 rpm and EX1 load 60→69 %. Nameplate recipe still 800 kg/h. This **extends the sim's 3C extruder envelope upper bound to ~1505 kg/h at 115 rpm / 69 % load / 246,9 kW EX1 power**.
- **Q30:** units reconfirmed — kW / % / rpm / bar / cm / kg/h.
- **Q15:** PCU-temp 1 = 110 °C (pre-extruder), EX1-IZ1 = 99 °C (extruder intake zone), both track with load; melt pressure rose with throughput (298/26/209 bar).
- **Consolidated LIJN-3C envelope (196–200, five frames, 02:17–02:42, 21-12-2024):** screw **102–115 rpm**, EX1 load **60–69 %**, EX1 power **212–247 kW**, PCU load **68–74 %**, PCU power **215–234 kW**, melt temp **110–111 °C**, EX1-IZ1 **93–99 °C**, pre-filter **284–298 bar**, filter Δ **26–27 bar**, post-filter **203–209 bar**, output **1294–1505 kg/h**, PCU fill **258–272 cm**, PES **75–80 %**, TEU **25–30 %**, BC1 **0–70 %**, operating hours **3553–3554 h**.
