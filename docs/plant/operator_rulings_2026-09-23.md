# Operator rulings — 2026-09-23 (interactive session, from memory of Geleen)

Source: Arno, answering AskUserQuestion prompts in the Claude session of
2026-09-23. These are **recollections, not documents or photos** — label them
as such when citing (CLAUDE.md Rule 1 accepts "explicit approval"; this is
that). Where an answer set a number in code, the code cites this file.

## 1. Film on the belts (design item P1)

| question | answer (verbatim where quoted) | where it landed |
|---|---|---|
| Dry side (shredder outfeed, before washing): what does the film look like on the belts? | **Mixed sizes** — "all of the above together, from small flake to long strips" (offered: strips 10-30 cm, palm-sized flake, fist-sized crumpled chunks) | `FilmFlakeField._build`: length multiplier 0.50-3.20, size multiplier 0.55-1.60 (was 0.55-2.65 / 0.60-1.45) |
| Colour of the film stream | "Mix of colors, although more white/translucent, then blue (variety of shades), then all other colors, least black" | `FilmFlakeField.COLOUR_SHARE_*`: white 68 %, blue 16 % (4 shades), other 13 %, black 3 % — the ORDER is his, the shares are a reading of it |
| Bed depth on a running belt | "Varies per belt" | bed depth is DERIVED per belt: kg/m = throughput ÷ deck speed, depth = kg/m ÷ (bulk density × width) — `FilmFlakeField.set_belt_state` |
| Transportbanden after the shredder (3A/3B intake network, line 1 past shredder 1) | "3a 3b about twice the material, but those transportation belts also run 50% faster then the other conveyors" | falls out of the sim's own numbers (3A/3B belts carry `_INTAKE_BELT_SPEED_MPS` = 0.5 vs 0.4 generic; the material rate is LineFlow's). No constant was typed for it. NOTE: 0.5/0.4 is +25 %, he says +50 % — flagged for the speed question below |
| Compactorband (extruder silo → compactor) | **Heaped, 20 cm or more** | `FilmFlakeField.BED_FULL_M` = 0.20 is "a full belt": every flake visible. The compactorband's bed at the sim's 0.4 m/s deck speed and ~0.5 kg/s comes out at ~1 cm — a heaped bed at that rate needs a deck creeping at ~2 cm/s. **Open: the real compactorband speed** (next question round) |
| After washing, where the flake is visible | **"Same flake, wet and darker"** | existing moisture tint (`_apply_tint`: darker grey, glossy) now also on the bed heap and the flake shader |
| Wet side: where can you SEE the flake? | **Kufferath sieve / scheidingsgoot; dewatering screw trough; "Open top tanks, transitions cyclones to blowers"** | NOT built yet — listed under open items below |
| Transport screws (transportschroef): open trough or closed? | **"Differs per screw"** (no notes on which) | nothing built on screws; needs the per-screw list |

### Second round (after the first renders)

| question | answer (verbatim) | where it landed |
|---|---|---|
| Compactorband deck speed? (a heaped bed at ~0.5 kg/s needs a creeping deck; the sim ran 0.4 m/s) | "More like 4 centimeters per second" | `PlaceableCatalog.COMPACTORBAND_SPEED_MPS` = 0.04: carry meta, BeltSurface, roller rpm, the bed's drift. With it, "heaped 20 cm+" at 3A/3B's 0.61 kg/s gives the dried-flake bulk density: `BeltBuilder.FLAKE_BULK_KGM3` = 90 (derived, see its comment) |
| Is the bed (white slab with flakes on top) a fair start? | "It should be flakes only. But is that too heavy? Then use similar method that for instance Gold Mining simulator uses for the soil, instead of sand the texture is film" | belt mode v2: a rounded, lumpy HEAP mesh wearing a procedural film texture (normal-mapped, scrolling), plus a dense flake layer the GPU scrolls and lifts in a vertex shader — no per-flake CPU cost, ~120 flakes per m² |
| Which belt speeds are closer to Geleen: the sim's 0.5 (intake) vs 0.4 m/s (other conveyors)? | "Actually closer to 1.5m/s" (for the 3A/3B transportbanden; with the earlier "50 % faster than the other conveyors" that puts the others near 1.0 m/s) | **NOT applied.** `PlaceableCatalog._INTAKE_BELT_SPEED_MPS` carries the note "Real CeDo intake belts run roughly 0.4–0.6 m/s; 0.5 m/s is the operator-confirmed middle" — two operator statements conflict by 3×. Belt speed drives the player carry, every rigid body on a deck, the roller rpm and the belt-to-belt discharge arcs, so it gets its own confirmed change. Question for the next round |
| Which wet-side place gets a visible flake bed next? | Scheidingsgoot, Kufferath sieve, dewatering screw trough — "Use the textured soil simulation for this I mentioned in earlier answer too" | queued as task 1c: the same textured heap + flake layer, wet-tinted, on those three |

### Stated assumptions the code carries (not operator numbers)

- Bulk density of loose material on a deck, `BeltBuilder.SNIPPER_BULK_KGM3` =
  60 kg/m³ (freshly shredded film) and `FLAKE_BULK_KGM3` = 90 kg/m³ (washed,
  dried flake on the compactorband — derived from his 4 cm/s and "heaped
  20 cm+" at the 3A/3B design rate; it was 180, `ShredderFeedBelt.OUTPUT_DENSITY`'s
  settled-pile figure, which gave 10 cm).
- A bed slews at one belt-full per transit time and is uniform along the deck
  (no leading edge).
- A stopped deck holds its bed (physical: material on a stopped belt stays).

### Open, to ask or look at

1. ~~Compactorband deck speed~~ — answered: 4 cm/s (second round).
2. **Which transport screws are open-trough** (his "differs per screw").
3. **Wet-side visibility** — Kufferath sieve, scheidingsgoot, dewatering screw
   trough are the three to build (second round); "open top tanks" and the
   cyclone→blower transitions still need naming (which tanks? what is seen?).
4. **Intake belt speed — CONFLICT.** Second round: "closer to 1.5 m/s" for the
   3A/3B transportbanden (others then ~1.0 m/s); the catalog's note says
   0.4–0.6 m/s was operator-confirmed earlier. Needs one explicit answer
   before any speed changes (blast radius: player carry, deck physics,
   roller rpm, discharge arcs).
5. `drum_feed_belt`, `westa_band_1`, `opzetband_*` (ShredderFeedBelt scenes)
   carry no film bed yet — the opzetbanden carry bales, the drum feed belt
   carries snippers and should get one.
6. `metal_belt`, `scraper_conveyor`, `compactor_belt` (bespoke decks, deck_kind
   'none') carry no bed yet.

## 2. Crew posts (task 2 — the `test_nav_connectivity` red)

| question | answer (verbatim) | where it lands |
|---|---|---|
| Where does the permanent feeder (Abdellilah, Mohammed) actually stand on 3A/3B? The sim posted them at the windzifter, the only machine of their zone on a 3A-only world | "line 1, he drives the Merlo and check containers etc. for washing line one" | the permanent feeder is a LINE 1 role: Merlo bale feeding + container checks for wash line 1. No fixed post on 3A/3B |
| Does anyone have a fixed post at a windzifter (3A/3B wash line or the sorting line)? | "No, nobody" | `CrewManager.ZONES["permanent_feeder"]` loses `wind_sifter` (jams there fall to the floaters, as "crew only come when it blocks") |
| May a blocked post slide along the aisle to the nearest clear spot (≤ 3 m)? | "depends on height (use of mast lift needed) or other accessibility option like the fixed stair/walkway (flotation tanks) (or ladder, but that is not added yet and low prio)" | not a slide: a post belongs at the machine's ACCESS point — a mast lift where it is high, the fixed stair/walkway on the flotation tanks, a ladder later. Recorded as a design item (crew posts at access points), not built today |

## 3. Silo level windows (task 3 — P5's silo half)

| silo | answer (verbatim) |
|---|---|
| which silos show a level from OUTSIDE | Doseersilo, Mengsilo, Extruder silo (NOT the VSS / vuilsnippersilo) |
| doseersilo | "dosing silo 2 square windows approx 30x30 cm horizontal distance 90cm between them centered along the tank, on both sides" |
| mengsilo | "mixing silo 1 small 15x15cm window 1/3 the way up on 1 side" |
| extruder silo | "extruder silo 4 vertical windows on each side" |

## 4. Choked reject pile (task 4 — P6's `_dump_waste` half)

| question | answer (verbatim) |
|---|---|
| when the reject pile under a chute is not cleared and keeps growing | "The machine chokes and stops" |
| how it comes back | "Shovel, then reset on the HMI" — an alarm shows, someone clears the pile, the machine is restarted by hand |

## 5. Smoke on a packed-up drive (task 6 — P2's second half)

| question | answer (verbatim) |
|---|---|
| does the real one smoke | "Visible smoke sometimes" |
| what it looks like | "Heavy smoke, people react" |

## 6. Doorway fixture (task 5)

"Suite builds its own gate (Recommended)" — `test_jam_baseline` is to place
its own 3A/3B gate fixture; the operator's world stays without a door.

## 7. Extruder lump carts, the laser filter, line 6 (task 7 — voice answers, transcribed as given)

**3C carts / smeltfilter 1 and 2.** Smeltfilter 1 is the LASER FILTER, the
first filter seen from the PCU (input) side: a cylinder standing with its
flat sides along the barrel, the bottom of its round part 10-20 cm above the
barrel's highest point; on each flat side a smaller cylinder ~8-9 cm in
diameter sticks out 25-30 cm, with a hole at its end and a short pipe
(~6 cm long, ~75 mm wide) pointing down — that pushes the scraped-off
material out and down into the lump cart, one cart on either side. Inside:
two filters (one per side), three knives each, scraping the bad product off
and expelling it through the side nozzles. Smeltfilter 2 is the HEAD FILTERS
(kopfilter): they capture the dirt, are changed as filter changes, and have
NO lump carts — they have the cabinets with the two expanding filter-head
changer units, one top and one bottom. Look up EREMA (the extruder's maker)
for diagrams of the laser filter, head filters, vacuum units, barrel/screw,
and probably the pelletizer.

**Layout along the barrel (material direction):** PCU intake slider →
extruder screw start → (past the HMI on its stand, at the FRONT, between the
PCU and the laser filter) → laser filter + vacuum pots (one unit with two
pots) → head filters → melt pump on 3C and 6 only → die and pelletizer head.
The platform is at the REAR of the extruder, the PCU side.

**Carts:** "there is no carts for an extruder. They are optionally bought
extra." Geleen had FOUR carts per extruder at least: two on standby (empty),
two under the laser filter (one either side) once the extruder runs. A full
cart is swapped for an empty one and parked in the yellow-marked area; after
cooling it is emptied with the forklift and parked back empty on the yellow
line, ready for the next swap. So 3C = 2 carts in use + 2 standby, not 4 in
use. (Corrects the "2 or 4?" question in `docs/plant/extruder_line_layout.md`.)

**Line 6 — Britas.** "There is a misunderstanding": the Britas unit
(extruder 6 only, a different maker) is an ABMF, automatic band melt filter:
a long filter band, one side new mesh; during a change the melt pressure is
lowered and the band is pulled ~30 cm across the barrel head so clean mesh
faces the extruder; the dirty material sticks to the sieve. NO discharge
screw, NO lump carts. (Corrects the "uittrekschroeven" reading.)

## 8. Conveyor speeds, and how wrong speeds should play (conflict 1)

"Every conveyor can be running at a different speed" from its HMI settings.
If today's estimates are wrong, that is gameplay: one conveyor too fast into
one too slow → too much material on the second → a heap → a blockage in the
transition chute → material builds up, pressure on conveyor two, the motor
gets hot, draws more amps and TRIPS → all conveyors in that section stop →
the operator goes there, shovels, finds the cause and fixes the speed. "If we
just have good estimates, or at least good enough, then the rest of it is
basically my gameplay." → today's numbers stand: intake transportbanden
~1.5 m/s, the other conveyors ~50 % slower (~1.0 m/s). The mismatch → chute
blockage → overload trip chain is a DESIGN ITEM (belt capacity from speed ×
bed, chute overload) — not yet modelled.

## 9. Extruder silo windows (conflict 2)

"It's four windows per side" — on the LONG sides, not the short sides where
the ladder is. Think of a long face in four quadrants; each window sits in
the inner sub-quadrant of its quadrant — "the most centre of the centre, but
not actually in the centre overlapping", not touching. Vertical (taller than
wide). This supersedes the #98/#99 layout (two windows per short face).

## 10. Standby lump carts (task 7, round 4)

"It is not per se within the six meter mark … for extruder six, I think at
least 10 meters. But it is different per extruder." The operator will place
the yellow areas himself with the build menu (Tab) and mark them with F10 if
needed. Spaces are NOT line-owned: when 3A produced lumps fast ("two cards
every 25 minutes") and 3B slowly ("two cards in two hours"), 3A used 3B's
carts and spaces. → Nothing to build: standby areas are operator-placed
`lump_cart_spot`s, shared between lines.

## 11. Line 1 — what it processes, and its metal-detecting first conveyor (round 4)

- **LINE 1 (normally) ONLY PROCESSES AGRICULTURAL (BLACK) FILM** — the
  "stretch film" farmers use (asparagus etc.), NOT the Rotterdam / Alba /
  Zwolle bales the other four lines run.
- Line 1 bales are bigger: ~1.70 m high, ~2 m wide, ~1.5 m thick, plus a
  ~30 % smaller version. They can hold extreme metal: car wheels, plough
  parts, "very sometimes even an anvil" (put in on purpose for weight),
  large nails, balls of wire, farm scrap. Such a part in any shredder
  "causes a crash of the shredder" — knives break off and slam around.
- Only line 1 has metal detection. The very first conveyor, before the
  Westa conveyor, has a sensor at about three quarters of its length: on
  detection it slows to a stop, reverses about one full conveyor length to
  clear the debris, slows to a stop, and runs forward again until an
  operator stops it or the next detection. The 3A/3B shredder and the 3C/6
  shredders have no magnet or metal sensor before the bale — those parts
  are "basically never" in those bales.

## 12. Where flake is seen on the wet side (round 4, completing §1)

- Chutes are mainly closed. The VW drum's exit chute on line 1 is open-top
  (already modelled). The prewash drum / voorwastrommel of line 1 holds "a
  slurry of water and film, quite turbulent" driven by the inside flight.
- **Cyclone → blower:** the cyclone tapers to a bottom mouth; the blower's
  suction box sits 10-15 cm BELOW it with a round hole. The film falls that
  gap through open air (air goes up the cyclone's centre, so the blower
  must draw from a gap, not a sealed pipe) — "at that point you can see the
  film physically".
- **Open-top vessels:** the dosing silo (doseersilo), the bunker, the
  bezinkafscheider (settling separator), the ontwaterschroef ONLY after the
  flotation tank (after e.g. the rafter it is closed), VSS 3A and VSS 3B, the
  prewash drum. (The "none besides the flotation tank" box was ticked too;
  his text is the ruling.)

## 13. Vacuum pots (task 9) and the in-game look (task 8)

Vacuum pots: "Use the EREMA diagrams" — look them up, show what was found
before building (Rule 1). In-game look: "After the full harness".

### EREMA / BritAS findings for task 9 (looked up 2026-09-23 evening; shown before building)

Sources: EREMA INTAREMA TVEplus product page
(https://www.erema.com/en/intarema_tveplus/) and brochure
(https://www.erema.com/assets/media_center/folder/intarema_tveplus_2024_11_en.pdf),
EREMA Laserfilter article, Kunststoffe 2014
(https://www.erema.com/assets/press/bilder/2014_04_kunststoffe_Laserfilter_EN.pdf),
BritAS ABMF product page (https://www.britas.de/en/product/abmf/).

- **TVEplus sequence** (brochure callouts): Preconditioning Unit (cut, mix,
  heat, dry, compact, buffer) → extruder screw with REVERSE degassing (3) →
  at the end of the plasticising zone the melt is directed OUT of the
  extruder, cleaned in the fully automatic self-cleaning filter (4) and
  returned → final homogenisation (5) → the degassing zone (6) → melt pump →
  the tool (8, e.g. the pelletiser) "at extremely low pressure". "Optimised
  triple degassing": preconditioning unit, reverse degassing in the screw,
  the extruder degassing zone. Filtration is upstream of degassing.
- **Laserfilter**: the contaminated melt is pressed through TWO laser-bored
  screen discs in parallel; a scraper disc ("scraper star") rotates BETWEEN
  the static screen discs, lifts the contaminants off immediately and conveys
  them to the discharge system (discharge screws); contamination such as
  wood, paper, aluminium, copper; fineness 90-130 µm; up to 3,500 kg/h. This
  is the operator's §7 picture: one filter per side, knives, side nozzles.
- **BritAS ABMF** (line 6): "automatic belt melt filter" — fresh screen mesh
  is fed at every filter change without stopping production; the melt is
  stored temporarily while the belt advances. No discharge screw, as §7 says.
- **Vacuum pots**: neither source gives their geometry. The sim's two vacuum
  domes on the barrel already come from the operator's own 2026-07-20
  photos (`gr-HMI_or-laserfilter_bl-vacuumpots_ye-vacuumcatchresiduebin…`),
  and `ExtruderModel` already tracks two pots at 18 kg each with the lid-open
  → VACUUM_ALARM cascade and `vacuum_line_gunk_kg` → `clean_vacuum_lines()`.
  So P3 needs no new geometry source: a level behind each pot's sight glass
  (the same proud witness port as the silos), the lid lifting on the alarm, a
  gunk deposit on the riser, and the hold-E clean. Proposed to the operator.

## 14. Vacuum pots — the cleaning is an OPERATOR MINI-GAME, not a hold-E (task 9, round 5; voice, transcribed)

"This is a simulator, this is operator simulation stuff … I have never held
any E's inside the factory." The end game is simulating operator tasks; first
a working factory. What happens at a flooded vacuum pot:

1. The lid has popped open. Pull it off — the plastic sticks to it more and
   more, harder the longer the pot has been out of vacuum.
2. With a **plamuurmes** (putty knife; "Emrah, who is Turkish, would say
   müürmes") clear the melt off every inner plane of the pot: the TOP
   section (top-left → top-right → bottom-right → bottom-left of that
   plane), the BOTTOM flat plane the same way, then the side walls (for the
   left: left-front, left-rear, left-bottom, left-front plane; the right
   likewise). The tool is narrower than a plane, so it has to be pushed in
   several times; sometimes it only goes halfway — pull it out, move it
   aside when it is not touching the melt, push again; a spot that took
   only half may take three quarters or all of it the next time, "depending
   on how stiff the melt is".
3. For testing: a plane counts as cleared at ≥ 90 %. When all four planes
   are ≥ 90 % the melt block visibly moves — "drops down and forwards,
   towards the player by like a centimetre" — and can be taken out BY HAND
   (no tool) and placed or thrown anywhere: the ground, a container, the
   lump pile under a filling cart, into the lump cart if there is room.
4. Which pot: laser-filter trouble clogs the FIRST pot; head-filter (second
   melt filter) trouble clogs the RIGHT pot; sometimes both.
5. Put the lid back; if the seal is good, start the extruder again; the
   vacuum pump reaches vacuum and the alarm clears.
6. **The two-minute rule.** If you are at the pots when the alarm sounds and
   you get the lid off, the pot clean and the lid back within about two
   minutes, the extruder sees the vacuum restored, silences the alarm and
   keeps running. Past two minutes it shuts down INSTANTLY — the extruder
   screw motor, the vacuum pump, the laser-filter knife motor, water pumps,
   the pelletiser head, everything on the extruder; the vacuum alarm stops
   (no vacuum needed when off) and a different HMI alarm sounds saying it
   shut down because of the laser-filter error.

(`ExtruderModel`'s VACUUM_ALARM → FAULT cascade already runs 120 s; the
mini-game and the by-hand block removal are new. Staged: A = the visible
state — pot level behind the sight glass, lid lifting, gunk; B = the lid,
the plamuurmes planes, the block, the re-lid and the seal.)

## 15. Line 1 — queued (round 5)

"Yes, both": the black agricultural-film bale type (≈1.7 × 2.0 × 1.5 m and
a ~30 % smaller one, sometimes with scrap metal inside) and the first
conveyor's metal detection with the reverse-one-length cycle (§11).

## 16. Doseersilo top (round 5)

Undecided until he sees it: "show top down image of it/them as well as
top-front-right and top-front-left view" — rendered
(`docs/plant/renders/shot_doseersilo_topdown.png`, `_topfrontright.png`,
`_topfrontleft.png`) and sent. Build order after the look: "not decided
yet, not relevant. ALL need to be done for alpha build anyways."

## 17. Doseersilo — open top and a corrected shape (round 6)

"Open, no grating." And, from the three renders: "The thing is basically
more like a flotation tank. With the three screws going on like the bottom
flat of it. And then the thing as a whole, without the support construction
legs, is tilted up slightly. I would say about 20 degrees or 25 degrees. So
the bottom is the input side, the top is the output side. And then the legs
are added so that the very bottom point sits at a height of about 1.7
meters. There is no semicircular shapes on top of it at all. And looking at
the images that you sent me, it would be maybe 10% less wide and 10% longer,
looking at the top-down view." → an open, flat-bottomed trough tilted
20-25° (low end = inlet, high end = outlet), three augers along the flat
bottom, no half-disc end plates, lowest point 1.7 m above the floor, 0.9×
width and 1.1× length of the rendered model; the two 30 × 30 cm windows per
long side (§3) stay.

## 18. Line 1 bales: LINE_1_FOLIE, and weight variance for every bale (round 6)

Bale type name: **LINE_1_FOLIE**. Large bales ~1000 kg, ±15 % (one standard
deviation). "Apply this variance/ratio whatever to all bale types that are
present in the sim thus far (since I noticed while testing that e.g. all
Rotterdam bales are the exact same weight → which is not realistic)."

## 19. Round seven (2026-09-24, ~01:30): doseersilo accepted, the cyclone gap, the sieve split, what next

Asked through AskUserQuestion after the wet-side beds and the metal-detect
conveyor were built and committed:

- **Doseersilo v2** (open tilted trough, 22.5°, lowest point 1.70 m,
  2.98 × 5.57 m, three augers driven from the high end, two windows per
  side): **"Yes, move on."**
- **Cyclone → blower:** the blower is **"Beside it, ducted"** — the cyclone's
  mouth drops into a short chute/duct that runs sideways into the blower;
  the open-air gap where "you can see the film physically" (§12) is at the
  chute mouth, NOT under the cyclone. The sim's beside-on-the-floor blowers
  are therefore right; the gap stream belongs at the cyclone's mouth into a
  short lateral chute. (Queued: build that chute + stream.)
- **Line 1 tail:** after the dewatering screw there is ONE friction
  separator and it **feeds BOTH Kufferath sieves** ("One separator feeds
  both sieves (split)"). The SEQ's second sieve had no feed edge until this
  ruling; fixed with L/R stream tags on the tail pairs.
- **Next build:** **the vacuum-pot cleaning mini-game** (P3 stage B,
  `docs/DESIGN_vacuum_pot_minigame_2026-09-23.md`), ahead of the belt-speed
  mismatch gameplay and the in-game look.
