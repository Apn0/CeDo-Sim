# PHOTO — EREMA BluPort HMI, LIJN 3C, "Elektrische energie +N1" trend

- **Source file:** `291_CeDo71 (3).pdf` (1 page, photo of physical HMI panel)
- **Type:** Photograph of EREMA BluPort touchscreen control panel + surrounding pushbuttons/labels
- **Line:** LIJN 3C (blue engraved plate below screen)
- **Screen title:** `Elektrische energie +N1` (Electrical energy; "+N1" = extruder/module tag)
- **Timestamp on screen:** `4:02:35  31-3-2025`
- **Brand:** EREMA (logo top-right) / BluPort HMI (logo top-right of screen)

## Left-hand live value column (icons + values, top → bottom)
| Pictogram | Value | Unit | Gloss |
|---|---|---|---|
| thermometer | **111** | °C | melt/temperature |
| (same block) | **102,7** | kW | current power (hoofdmotor) |
| screw ~~~ | **59** | rpm | extruder screw speed |
| % | **36** | % | screw load / speed % |
| clock (h) | **5455** | h | running hours |
| ◇ (diamond) | **221** | bar | pressure (melt, pre-filter) |
| ▣h | **17** | bar | pressure (2nd point) |
| ◇ | **66** | bar | pressure (3rd point) |
| �copen | **-466** | kg/h | throughput/output (negative reading shown) |

## Center info boxes
- **`Actueel benodigde elektrische energie`** (currently required electrical energy): **0,496 kWh/kg** — specific energy consumption per kg
- **`Elektrisch energieverbruik`** (electrical energy consumption / cumulative): **856733 kWh**
- **`Reset`** button below it.

## Trend graph
- Y-axis left: 0 … 2500 (scale marks 125, 250, 375 … up to 2500) — kW/A total scale
- Y-axis right: 0 … 1000 (125-step marks) — secondary scale
- X-axis (time): `3:45:56 31-3-2025` → `3:50:06` → `3:54:15` → `3:58:25` → `4:02:35 31-3-2025` (≈ rolling window ending at current time)
- Two trend lines: white (upper, ~noisy band around 500-625) and green (lower band, steadier ~375-500).

## Bottom data table (verbatim)
| Label | Value | | Label | Value |
|---|---|---|---|---|
| Stroom L1 | 454,8 A | | Totaal actief vermogen L1L2L3 | 237,3 kW |
| Stroom L2 | 462,3 A | | Vermogensfactor L1L2L3 | 0,7 |
| Stroom L3 | 459,0 A | | Frequentie | 50,0 Hz |

(Stroom = current per phase; Totaal actief vermogen = total active power; Vermogensfactor = power factor; Frequentie = mains frequency.)

## Navigation bar icons (bottom of screen, left→right)
✕ (close) · ▦ (module grid) · ⌂ (home) · 🔔 (alarms) · ♡/heartbeat (status/health) · 🔧 (maintenance) · 📈 (trends) · ℞ (Rx / recipes) · ⚡ screen icon (energy) · eco·SAVE (EREMA ecoSAVE energy mode) · monitor+ (remote) · ▶| (next).

## Physical panel — labels & controls
- **Top-left placard (warning, red triangle):** `GEBRUIK DEZE MACHINE NIET ZONDER VEILIGHEIDSCONTROLE IN POSITIE` / `WAARSCHUWINGSBORD NIET VERWIJDEREN IN MIDDEWEN` [unsure: last line partly cut]. (Do not use this machine without safety guard in position; do not remove warning sign.)
- **Top-center yellow placard:** `STAAT` / `Afzuiging compactor` / `!!! AAN !!!` — "State: compactor extraction is ON". (Confirms compactor de-dusting/extraction interlock.)
- **Blue engraved plate under screen:** `LIJN 3C`.
- **Bottom pushbutton row (icons):** ⏻ power (on/off) · ⤵ infeed (material in) · ◎ screw/rotation (illuminated white) · ♨ ~~~ heating (illuminated white).
- **Bottom-left:** red mushroom EMERGENCY STOP / NOODSTOP (with red cap).
- **Bottom-right blue button:** `Mute Vacuüm alarm`.
- **Bottom-right placard (warning):** `WAARSCHUWING — MACHINE NIET BEDIENEN ZONDER VOORAFGAANDE OPLEIDING EN AUTORISATIE` (Do not operate machine without prior training and authorisation).

## Answers to open questions
- **Q29 (3C = SCADA host for wash line 6?):** No direct evidence here. This screen is the EREMA extruder line 3C's own energy HMI (BluPort), a per-extruder panel. Does not tie 3C to wash line 6. No support either way from this photo.
- **Q30 (units):** Confirms on live HMI: **Vermogen hoofdmotor in kW** (102,7 kW) AND **%** (36 %) shown as separate readouts; **Snelheid in rpm** (59 rpm); **Stroom in A per phase**; **Totaal actief vermogen in kW**; **Frequentie in Hz**; specific energy in **kWh/kg**. So Vermogen is reported in both kW and %, Snelheid in rpm (with a parallel % load).
- **Q15 (temp zones):** Only a single melt temperature 111 °C shown here (not the zone profile); no zone-by-zone data on this screen.

## Notes for sim
- ecoSAVE branding + "Actueel benodigde elektrische energie 0,496 kWh/kg" gives a concrete specific-energy figure usable for a power/cost model on an EREMA extruder line.
- "Afzuiging compactor AAN" placard reinforces the compactor-extraction interlock modeled elsewhere.
