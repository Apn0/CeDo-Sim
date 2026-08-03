# OTHER: EREMA BluPort HMI screenshot — LIJN 3C (2nd frame, +6 min)

- **source_file:** 212_CeDo53 (3).pdf
- **doc type:** Photo of EREMA BluPort SCADA/HMI main screen (not a SWI)
- **line:** 3C ("LIJN 3C" plate)
- **duplicate_of (same screen, different timestamp):** 211_CeDo49 (3).pdf
- **pages:** 1
- **timestamp on screen:** 2:35:46  21-12-2024 (≈6 min after the 211 frame)

## Photo description
Same EREMA BluPort HMI as 211, photographed ~6 min later. Left warning sticker now
readable: "…AARSCHUWING / …UIK DEZE MACHINE NIET / …ER VEILIGHEIDSCONTROLE / IN POSITIE
/ …GBORD NIET VERWIJDEREN OF MISVORMEN. 1 hollandisch" (= WAARSCHUWING / GEBRUIK DEZE
MACHINE NIET … VEILIGHEIDSCONTROLE IN POSITIE / … BORD NIET VERWIJDEREN OF MISVORMEN —
warning: do not use this machine without safety guard in position, do not remove/deform
the sign). Centre-top yellow sticker: **"STAAT / Afzuiging compactor !!! AAN !!!"**.
Recipe bar same: **"Rx LDPE 800 kg/h 22.04.2024 IBN"**. Plate: **LIJN 3C**.

## Left vertical gauge column (live)
| Pictogram | Value | Unit |
|---|---|---|
| temp | 110 | °C |
| power | 223,1 | kW |
| rpm | 115 | rpm |
| % | 70 | % |
| hours | 3554 | h |
| pressure ◇ | **299** | bar (highlighted) |
| pressure ⊟ | 24 | bar |
| pressure ◇ | 204 | bar |
| output ⟿ | **1474** | kg/h |

Trend window X-axis: 2:19:07 → 2:35:46, 21-12-2024. Same trace legend
(Toevoer actief cyan / PCU-temperatuur 1 green / PCU-vermogen orange / AIS-positie yellow).
AutoPro-control: **Uit** (OFF).

## Right data tiles
| Tile | Value |
|---|---|
| PCU-vulpeil | 268 cm |
| PES-toerental | 80 % |
| TEU-toerental | 30 % |
| PCU-belasting | 71 % |
| PCU-vermogen | 223,1 kW |

## Extruder mimic tiles
| Tile | Value |
|---|---|
| BC1-toerental | 70 % |
| EX1-vermogen | 248,4 kW |
| EX1-toerental | 115 rpm |
| EX1-belasting | 70 % |
| AIS-positie | 70 % |
| PCU-temp. 1 | 110 °C |
| EX1-IZ1 | 97 °C |

## Notes / answers
- Reinforces **Q29**: LIJN 3C = EREMA BluPort extruder/regranulate line (not wash line 6).
- **Q30**: EX1-vermogen kW, EX1-toerental rpm, belasting/toerental of PCU/PES/TEU/BC1 in %.
- **Q9/Q21**: recipe 800 kg/h nameplate; live doorzet 1474 kg/h; screw 115 rpm at 70 % load,
  melt pressure pre-filter ~299 bar — a slightly harder-running frame than 211 (287 bar / 107 rpm).
- Melt pressure differential across filter readable as ~24 bar (2nd pressure tile) — supports
  laserfilter Δp monitoring (cf. laserfilter-smeltdrukverschil doc).
