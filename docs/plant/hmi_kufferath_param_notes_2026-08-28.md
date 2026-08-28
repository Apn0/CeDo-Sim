# Kufferath PARAMETER screen — operator behaviour notes (PARKED, 2026-08-28)

**Source photo:** `assets/reference_photos/hmi/kufferaths_line1.png` (real
plant HMI, German; twin panel DRD 1 / DRD 2; timestamp Samstag 29. Juni 2024,
13:41:38). Operator gave these notes by voice during the doc walk and
explicitly said: **"for the HMIs … we need to continue on that later because
we are just doing a good flow on the line layouts."** So: RECORDED, not yet
built. The mockups' values were deliberately zeroed by the operator earlier
("I specifically set all values to zero") — he now wants them set correctly
from this photo when the HMI pass resumes.

## Interaction spec (operator, voice → mapped to the photo's labels)

| Photo element | Operator's behaviour spec |
|---|---|
| **Trocknungs-Automatik** EIN/AUS, **Heizregister** EIN/AUS | Clickable button pairs. Click EIN → it turns GREEN and the AUS button (red when active) turns GRAY — and vice versa. (Photo confirms: active state carries the colour, inactive is gray.) |
| **Trockenzeit** 30 s | Settable number (tap → enter value). |
| **Befüllstop DRD** 90 %, **Entleerstop DRD** 60 %, **Temperatur Sollwert DRD** 40 °C | Settable numbers ("the ninety and sixty and forty"). |
| **Entleerschieber** Taktzeit 2 s / Pausezeit 4 s; **Laufzeit Beschickungsschieber** 12 / 120 [o]; **Laufzeit Entleerschieber** 12 / 12 [o] | Settable ("the two seconds, four seconds, twelve and hundred twenty, twelve and twelve"). |
| **Silo voll** 3 s, **Standby** 3 s | Settable ("the three and three at the bottom"). |
| **Motorlast DRD** 65 % / 88 % | **Definitely sensor values** (live readings). |
| **Schrittlaufzeit** 43 s / 48 s (with Schritt 6: Entleeren / Schritt 3: Befüllen) | Derived sensors — "derived from the time and which point of the cycle they are"; counts through the step until the cycle completes. |
| **Korrekturwert Temperatur DRD** +13 / +15 °C, **Korrekturwert Temperatur Entstaubung** +83 / +98 °C | Operator UNSURE — "might be sensor readings, but I'm not one hundred percent sure." (Label reads "Korrekturwert" = correction value; do NOT decide without him.) |
| Bottom nav MAIN · PARAMETER · HANDBETRIEB · ZYKLUSDATEN · SYSTEM · ALARME | "Certain screens are also not present yet" — the missing pages need building in the HMI pass. |

## Open items for the HMI pass (when resumed)

1. Make the listed numbers tappable/settable ("I cannot tap certain numbers")
   and wire the EIN/AUS colour toggles.
2. Build the missing sibling screens (HANDBETRIEB, ZYKLUSDATEN, SYSTEM, …).
3. Port the photo's real values in place of the zeroed mockup values.
4. Resolve the Korrekturwert sensor-vs-setpoint question WITH the operator.
