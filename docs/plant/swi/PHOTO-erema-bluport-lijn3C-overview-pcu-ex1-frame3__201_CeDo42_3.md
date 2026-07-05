# PHOTO — EREMA BluPort HMI (Dutch), LIJN 3C, Process overview (PCU / EX1) — frame 3 (clear)

- **Source file:** `201_CeDo42 (3).pdf` (1 page, 5.3 MB photo scan)
- **Type:** Photograph of EREMA **BluPort** HMI, Dutch UI, **LIJN 3C** — process-overview / intake+extruder mimic. **Third frame** of the 194/195 sequence, same day 21-12-2024, ~2 min after 195 (2:20:24 vs 2:18:42). Clearest/sharpest image of the three — full mimic legible, page number **111** visible bottom-right.
- **SWI id:** none (HMI screenshot)
- **Scope:** LIJN 3C intake/compactor (PCU) + extruder EX1 + AIS + trend; LDPE production
- **References:** EREMA BluPort; recipe "LDPE 800 kg/h 22.04.2024 IBN"

## Same fixed content as 194/195
- Stickers, **LIJN 3C** plate, **BluPort EREMA** brand, recipe **"LDPE 800 kg/h 22.04.2024 IBN"**, **AutoPro-control = Uit**, same trend legend & axes. Bottom-right faint **111** page marker.

## Left-column live values (this frame)
- Clock: **2:20:24**, date **21-12-2024**
- (gauge) **109 °C**
- (power) **219,3 kW**
- (speed) **105 rpm**
- (load %) **63 %**
- (hours) **3553 h**
- (pressure ◇1) **295 bar** (orange)
- (pressure ⊗1) **26 bar**
- (pressure ◇2) **203 bar**
- (throughput ⤷) **1367 kg/h**

## Trend chart (this frame)
- X-axis: **2:03:45 / 2:07:55 / 2:12:05 / 2:16:15 / 2:20:24**, all **21-12-2024**
- cyan **Toevoer actief** feed pulses (denser first half, sparser tail); green **PCU-temperatuur 1** ~250 flat rising slightly; orange **PCU-vermogen** ~200-250 noisy; yellow **AIS-positie** flat.

## Right mimic tiles (this frame)
- **PCU-vulpeil** = **269 cm**  (195: 267, 194: 266 — level slowly climbing)
- **PES-toerental** = **75 %**
- **TEU-toerental** = **25 %**
- **PCU-temp. 1** = **109 °C**
- **PCU-belasting** = **70 %**
- **PCU-vermogen** = **219,3 kW**
- **AIS-positie** = **70 %**
- **EX1-vermogen** = **224,9 kW**
- **EX1-toerental** = **105 rpm**
- **EX1-belasting** = **63 %**
- **EX1-IZ1** = **94 °C**
- **BC1-toerental** = **60 %**

## ANSWERS TO OPEN QUESTIONS
- **Q21 (which line ~1200 kg/h):** LIJN 3C now **1367 kg/h** live (climbing: 194=1216 → 195=1321 → 201=1367 over ~1 h). Confirms 3C is the high-throughput LDPE line operating in the **~1200-1375 kg/h** band; the recipe nameplate is "LDPE 800 kg/h" but actual line output is ~1.4× that. [confidence: hint→likely that 3C is "the ~1200 kg/h line"]
- **Q15:** intake temps stable (PCU 109 °C, EX1-IZ1 94 °C).
- **Q30:** reconfirmed unit conventions.

## Notes for sim
- Completes the **21-12-2024 ramp timeline** on LIJN 3C (three frames 194→195→201):
  | time | EX1 rpm | EX1 kW | PCU load % | ⤷ kg/h | PCU-vulpeil cm | ◇1 bar |
  |------|---------|--------|-----------|--------|----------------|--------|
  | 1:16:44 (194) | 90 | 189,8 | 65 | 1216 | 266 | 297 |
  | 2:18:42 (195) | 105 | 222,0 | 71 | 1321 | 267 | 290 |
  | 2:20:24 (201) | 105 | 224,9 | 70 | 1367 | 269 | 295 |
- Shows the line settling at 105 rpm after the ramp, throughput still creeping up (1321→1367) as the compactor buffer (PCU-vulpeil 267→269) and thermal state stabilise — nice lag behaviour for the sim.
- Treat 194 as canonical topology; 195+201 as the dynamics/ramp dataset.
