# EREMA reference — "Invloed van waterinjectie" & "Onderdelen voor de waterinjectie" (Compactor)

**Source scan:** `D:/drive-download-20251124T130330Z-1-001/177_CeDo60.pdf` (1 page)
**Doc type:** Not a SWI. EREMA manual/training page on Compactor water injection (temperature control) and its components. Extracted exhaustively incl. photo captions.

## Section 1 — "Invloed van waterinjectie" (Influence of water injection)
**Bullets (verbatim):**
> - "Alleen in gebruik als noodvoorziening." *(Only used as an emergency/backup provision.)*
> - "Injecteer water wanneer het instelpunt van de temperatuur wordt bereikt." *(Inject water when the temperature setpoint is reached.)*
> - "Zet overtollige energie om in stoom." *(Convert excess energy into steam.)*
> - "Er gaat een alarm af als er te veel water wordt geïnjecteerd." *(An alarm sounds if too much water is injected.)*
> - "Automatische belasting detector zoekt permanent naar optimaal instelpunt." *(An automatic load detector continuously searches for the optimal setpoint.)*

## Section 2 — "Onderdelen voor de waterinjectie" (Components for the water injection)
Three labelled photos (captions verbatim + one-line photo description):
1. **"Zwaardsonde die het thermokoppel in de Compactor beschermt"** *(Sword/blade probe that protects the thermocouple in the Compactor)* — Photo: a flat stainless steel blade-shaped guard/sheath mounted at an angle inside a metal housing, with two round bolt heads. This is the protective sword-sheath around the temperature probe.
2. **"Thermokoppel, haaks 65mm om de Materiaal temperatuur [te meten]"** *(Thermocouple, right-angled, 65 mm, for the material temperature)* — Photo: an L-shaped (right-angle bent) thermocouple probe with a long straight shaft and a short bent tip; **65 mm** bend length. Measures the material temperature.
3. **"Waterinjectiestuk in de Compactor"** *(Water injection nozzle/piece in the Compactor)* — Photo: a brass/bronze circular injection nozzle fitting set into the compactor wall (threaded boss with a central bore).

## Notes / open-question hits
- **Q15 / Q33 (compactor temperature control & sensors):** Documents the **compactor water-injection system** used to hold the compactor temperature at setpoint. Mechanism: when the temperature **setpoint** (the 123 °C from FORM-008) is reached, **water is injected** and the **excess energy is turned to steam** (flash cooling) — but this is an **emergency/backup** method ("Alleen in gebruik als noodvoorziening"), with an **over-injection alarm**. Primary control is the **automatic load detector** continuously seeking the optimal setpoint.
- **Sensor spec (Q30/Q33):** the compactor **material temperature** is measured by a **right-angle 65 mm thermocouple** protected by a **zwaardsonde (sword-probe guard)**. This is the sensor behind the "Compactor temperatuur" reading (FORM-008 rows 19-20) and the EREMA HMI "PCU" temperature — useful for sim sensor realism.
- **Q20 (slow-running causes → remedies):** water injection is the **remedy for an over-hot compactor** (excess energy → steam) — but only as a last resort; the real control is feeding to a target motor load (see `176_CeDo56`). Over-injecting water triggers an alarm and worsens the sauna effect (`175_CeDo58`), so it's a noodvoorziening only.
- **Q5 (water routing) minor:** confirms a **water-injection feed into the compactor** exists as a small dosed water input (temperature-control water), distinct from the wash/flotation/granulate water loops.
- Completes the EREMA compactor set: 171 (PCU=compactor), 175 (air flush/sauna), 176 (temp & circulation), 177 (water injection & sensors).
