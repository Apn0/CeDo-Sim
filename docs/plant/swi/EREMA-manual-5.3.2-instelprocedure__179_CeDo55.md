# EREMA Operating Manual §5.3.2 — Instelprocedure (Compactor kW vs output chart, Fig. 88)

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/179_CeDo55.pdf` (1 page)
**Doc type:** Not a SWI. Page from the **EREMA operating manual**, section **5.3.2 Instelprocedure** (setting procedure) — Compactor motor-load-vs-output diagram. HIGH-VALUE: carries throughput (kg/h) numbers. Extracted exhaustively.

## §5.3.2 Instelprocedure (verbatim + gloss)
> - "Gebruik het onderstaande diagram om ruwweg de benodigde motorbelasting van de Compactor vooraf te bepalen als functie van de uitgang en het plasmatype [plastic-type]."
> - "Pas de ingestelde kW-waarde aan op de aan/uit-knop van de PCU om het gewenste vermogen te bereiken."
> - "Tijdens het gebruik, moet de instelling worden geoptimaliseerd, zodat de empirisch bepaalde optimale Compactor temperatuur wordt bereikt."

**Gloss:** Use the diagram below to roughly pre-determine the required Compactor motor load as a function of output and plastic type. Adjust the set kW value on the PCU on/off button to reach the desired power. During operation, optimise the setting so the empirically determined optimal Compactor temperature is reached.

## Fig. 88 — chart transcription
**Caption (verbatim):** "Fig. 88: Belasting van de Compactor (kW) (1) als functie van de outputsnelheid (kg/u) (2) en het te verwerken materiaal (polymeer)"
*(Compactor load (kW) (1) as a function of the output rate (kg/h) (2) and the processed material (polymer).)*

- **Y-axis (1):** Belasting van de Compactor = **Compactor load in kW**, scale 0 → 300 kW (gridlines every 20).
- **X-axis (2):** Outputsnelheid = **output rate in kg/u (kg/h)**, scale **1000 → 2000 kg/h** (gridlines every 100).
- **Plotted line labelled "LD/LLDPE"** (the CeDo material): a rising straight line from approx **(1000 kg/h, ~100 kW)** up to approx **(2000 kg/h, ~185 kW)**. Reading intermediate points (best reading off the grid):
  - 1000 kg/h → ~100 kW
  - **1200 kg/h → ~110-115 kW**
  - 1400 kg/h → ~130 kW
  - 1500 kg/h → ~140 kW (label sits here)
  - 1600 kg/h → ~150 kW
  - 1800 kg/h → ~170 kW
  - 2000 kg/h → ~185 kW
  (Approx slope ~0.085 kW per kg/h; [values read from gridlines, ±5 kW].)

**Info box (verbatim):**
> "De waarden in het diagram moeten worden gezien als referentiewaarden voor droge grondstoffen. Om het exacte vermogen te bereiken, moet de kW-instelling worden aangepast aan de grondstof en de plaatselijke omstandigheden. Extra doseereenheden verhogen het vermogen."
> *(The values in the diagram are reference values for DRY raw material. To reach the exact power, the kW setting must be adapted to the raw material and local conditions. Extra dosing units increase the power.)*

## Notes / open-question hits (Q9 / Q21 / Q30 — MAJOR HITS)
- **Q9 (line capacities / throughput kg/h):** STRONG hit. The EREMA Compactor for **LD/LLDPE** is characterised over an **output range of 1000-2000 kg/h**. This is the design throughput envelope for the extrusion line's front end — i.e. a single EREMA extrusion train processes on the order of **1-2 tonne/h of LDPE/LLDPE**. (Reference values for DRY feed; wet feed reduces effective output.)
- **Q21 (the 1200 kg/hr budget speed — which line?):** LIKELY hit. **1200 kg/h sits squarely on this LD/LLDPE Compactor curve (≈110-115 kW)** — i.e. 1200 kg/h is a normal operating point on an EREMA LDPE extrusion line. So the "1200 kg/hr budget speed" is the **target output of an EREMA LDPE extruder line** (the line-3 extruder trains 3a/3b, and/or line 1), read against this exact chart. It's not a wash-line figure — it's the **extruder/compactor output budget**. [Line identity: this is the EREMA extruder output; on the CeDo layout that's the 3a/3b extrusion trains — [likely] the intended "budget speed" line.]
- **Q30 (power_CC units / Vermogen hoofdmotor):** CONFIRMED the **Compactor (PCU) load is measured in kW** (0-300 kW range on this chart). So the sim's **"power_CC" = Compactor motor load in kW**, and the compactor is set via a **kW target on the PCU on/off knob**. This directly answers whether power_CC is kW vs A → **kW**. (Compactor operating band for LDPE ≈ 100-185 kW across 1000-2000 kg/h.)
- **Q20 (slow-running → remedies) reinforcement:** setting procedure = pick target kW from Fig. 88 for desired kg/h, set on PCU, then trim to hit the empirical optimal Compactor temperature. **Wet feed lowers output vs the dry-reference curve** → to restore output either dry the feed better or add dosing units ("Extra doseereenheden verhogen het vermogen"). Actionable for sim: output(kg/h) is a function of compactor kW AND feed dryness.
- **Q24 (feed density/dryness):** chart values are explicitly for **DRY grondstoffen (dry raw material)** — wet feed shifts the curve; reinforces moisture as the key output-limiting variable (consistent with sauna-effect page `175_CeDo58`).
- Companion EREMA pages: 171 (PCU), 176 (temp/circulation), 177 (water injection), this 179 (kW vs output). Together they fully specify the EREMA compactor control model for the sim.
