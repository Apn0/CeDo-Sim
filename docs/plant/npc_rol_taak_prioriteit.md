# NPC gedrag: rol → verantwoordelijkheid → taak → prioriteit

Design-spec voor de autonome ploeg (#173 / #198 vervolg). Afgeleid uit
operator-input, niet uit fantasie. **Bouw pas tegen dit document nadat Arno het
heeft nagekeken.**

---

## 0. Grondbeginsel

> **De productie draaiende houden heeft altijd voorrang.**

Het echte noorden is **de output halen** ("projected output need"). De praktische
proxy daarvoor: **de silo vóór de extruder vol houden** — of hij mag leeg zijn,
zolang er constant materiaal blijft komen. Zodra dát in gevaar komt is er een
probleem.

Alles wat de doorvoer stopt of bedreigt is het belangrijkste. Al het andere
(schoonmaken, onderhoud, containers legen) is ondergeschikt en wordt in de
**slack** gepropt — de momenten dat de lijn genoeg gevoed is en er niks stuk is.
Prioriteit is **dynamisch en situationeel** ("gewoon logisch nadenken"), geen
vast rooster.

---

## 1. De twee lagen (bestaan al in code)

| Laag | Wat het is | Persistent? | Waar in code |
|------|-----------|-------------|--------------|
| **Rol** | Identiteit + gebied + verantwoordelijkheid (extruder-operator, feeder, ploegleider…). Geeft een **zone** (welke machines) en maakt je de persoon die een storing in díe zone oplost. | **Ja** — verandert niet. Blijft je rol terwijl je een taak doet. | `CrewManager.gd` (ROLE_POSTS, ZONES) + `npc_role` |
| **Taak** | Alles wat je fysiek dóet. Wordt automatisch toegewezen op basis van rol + wereldtoestand. Tijdelijk. | Nee | `NpcAutonomyBoard.gd` (task board), `accept_roles` |

**Belangrijk:** in het ploegpaneel (Numpad `.`) wijs je een **post** toe (rol /
sectie / machine / HIER), **niet** een taak. "Blad blazen" kies je nooit zelf —
dat deelt het bord automatisch uit aan een NPC die niks urgenters heeft.

---

## 2. De prioriteitsladder (dynamisch, elke tick herberekend)

Hoger tier verdringt altijd lager tier. Binnen een tier: dichtste/meest logische
NPC pakt het.

### Tier 0 — Veiligheid / nood (gereserveerd, hoogste van alles)
Brand, iemand bekneld/geblokkeerd, medisch. Verdringt óók de productie. **Nog geen
generators** — die events bestaan nog niet in de sim. De prioriteitsband is
gereserveerd; zodra we brand/nood toevoegen krijgen die tasks automatisch deze
band en dus voorrang. Nu alleen een lege haak.

### Tier 1 — Eigen lijn draaiend houden
De ploeg is opgedeeld in **lijn-teams**: één operator per **1-2 lijnen**, met de
feeder(s) die bij díe lijn(en) horen. Er is **géén vaste volgorde tussen lijnen**
— elk team is zelf verantwoordelijk voor de output van zijn eigen lijn(en).

**Regels binnen een team:**
- **Eigen lijn heeft een storing → eerst díe fixen.** Alles daarvoor wijkt. De
  operator wiens zone de storing bezit lost het op (via de storings-loop hieronder).
- **Feeder van een stilstaande lijn helpt de operator meteen.** Ligt de
  (sorteer)lijn stil, dan is er niks om op de band te leggen — dus de feeder gaat
  **direct** mee de storing verhelpen. Bals stapelen / balenpers / schoonmaken
  kán dan wel, maar is lagere prioriteit dan de storing, dus dat wacht.
- **Eigen lijn draait goed + tijd over → mag een ander team helpen.** Zodra je
  eigen lijn een probleem heeft komt die eerst; hulp van buiten is mooi
  meegenomen, geen verplichting.

**De storings-loop (per verantwoordelijke rol):**
```
alarm in mijn zone
  → loop naar de HMI die die zone bezit
  → lees af wélke unit stuk is (bv. granulator)
  → loop naar die unit
  → verhelp / maak vrij
  → sluit weer dicht
  → loop terug naar de HMI
  → herstart / kwiteer
  → hervat post
```

### Tier 2 — De lijn gevoed houden (feeder-kernlus)
Interne ladder (feeder beslist "gewoon logisch"):
1. **Bals gestapeld in werkgebied < minimum** én band niet kritiek leeg →
   **bijhalen wint van voeren** (je kunt niet voeren wat er niet is; en
   halverwege de shift zonder bals = lijn stopt).
2. Anders, **band vraagt materiaal** én bals aanwezig → **band voeren**.
3. **Band vol** (kan er niks meer bij) én stapel op peil → feeder is **vrij**
   voor lagere tiers.
4. **Nul bals gestapeld** → kan **alleen** bijhalen (niks om op de band te leggen).

### Tier 3 — Vaste onderhoudsklus, ~1× per shift, met slack-venster
- **Balenpers leegmaken:** ~1× per 8u-shift, klusje van ~5-10 min.
- **Geen vast tijdstip** — vuur hem af wanneer er échte slack is (band vol
  genoeg, genoeg bals gestapeld, geen actieve storing).
- **Zachte deadline:** "moet ergens in die 8 uur". **Overslaanbaar** op een
  rotdag (storing-na-storing, te weinig mensen) — het is niet stuk, ándere
  dingen wel. Niet-afgemaakt is dan acceptabel. Zeldzaam geval, maar toegestaan.

### Tier 4 — Achtergrond-huishouding (laagste, bestaat al)
Blad blazen, spuiten, hopen scheppen, overloop-containers legen, afgekoelde
lumpskarren legen. Vult stilstand op; wordt door álles hierboven verdrongen. Al
gated op shift-fase (opstart/overdracht-boost) in `NpcAutonomyBoard.gd`.

---

## 3. Wat er NU is vs. wat mist

| Onderdeel | Status |
|-----------|--------|
| Rol + zone + basale jam-respons | ✅ bestaat (`CrewManager`) |
| Taakbord + rol-gated auto-taken | ✅ bestaat (`NpcAutonomyBoard`) — **maar alleen Tier 4** |
| Post gaat vóór schoonmaak | ✅ **gebouwd (#223)** — `CrewManager.needs_worker()` + `NPC._production_needs_me()`: productie (jam/dispatch/pauze) verdringt nu strikt de huishouding; een geposte operator laat de bladblazer vallen zodra er een storing in zijn zone is en pakt er geen op zolang productie hem claimt |
| Tier 1 storings-rangschikking op doorvoer-impact | ❌ mist — alleen grove `JAM_KG`-posting |
| Storings-loop (HMI → unit → fix → dicht → HMI → herstart) | ❌ mist |
| Feeder-ladder (Tier 2) | ❌ mist |
| Tier 3 balenpers als slack-gated 1×/shift taak | ❌ mist — bestaat als taak helemaal niet |

---

## 4. Beslist / open

**Beslist:**
- Géén harde volgorde tussen lijnen — per **lijn-team**, eigen lijn eerst (§Tier 1).
- Feeder van een stilstaande lijn **helpt de operator direct** bij de storing.
- Output-doel = extruder-voedingssilo vol / constant materiaal (§0).

**Open (Arno):**
- **Veiligheid** — komt er boven Tier 1 nog een noodstop/veiligheid-tier
  (iemand geblokkeerd, brand), of laten we dat voorlopig buiten scope?
