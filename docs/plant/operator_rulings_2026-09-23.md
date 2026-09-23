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
