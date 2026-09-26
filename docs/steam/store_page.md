# Steam store page: draft

**DRAFT, for the operator to edit before pasting into Steamworks.** Every
feature line below is something the repository contains on 2026-09-26; nothing
is promised that is not built. Valve's rules are cited in
[README.md](README.md).

## Name

CeDo Simulator

## Short description

(Valve: plain text, "a few hundred characters". This one is 235.)

> Work a shift in a real plastic-film recycling plant. CeDo Simulator rebuilds
> the LDPE recycling plant in Geleen, Netherlands: shredders, wash lines,
> dryers and extruders, with the plant's own control screens, alarms and
> start-up rules.

## About this game

> **A real plant, not a generic factory.** CeDo Simulator is modelled on the
> LDPE film recycling plant in Geleen where its developer worked. Machines,
> layouts and procedures come from the operator's own photos, the plant's work
> instructions and its control-room screens, and the plant's recorded process
> data sets the numbers.
>
> **Follow the film from bale to granulate.** Bales are shredded, washed,
> separated, dried and melted into granulate on lines 1, 3A, 3B and 3C. The
> simulation moves real kilograms through every machine: a full silo stops the
> screw that feeds it, a tripped motor stops conveying, and a line that backs
> up comes to an e-stop.
>
> **Run it from the panels the plant uses.** Twelve HMI panels, laid out after
> the real screens: alarms you acknowledge one by one, an extruder that checks
> its natraject before it starts, a barrel that needs its warm-up, and melt
> pressures that trip the line when you push too hard.
>
> **Drive the yard.** Forklift, bale clamp, Merlo telehandler and mast lift,
> with a crew working the lines around you.
>
> **Sounds from the floor.** The machines that have a sound use the
> operator's own recordings, made on the plant floor.
>
> This is a development build. The plant speaks the operators' Dutch:
> trilzeef, maalmolen, flotatietank, waslijn, doseersilo.

Operator to check before posting: every sentence above against how the build
plays today, and the Dutch/English mix against what the page declares under
languages. In particular: a New Game starts with an EMPTY factory (the building
and your gate are there, no lines) and the lines are placed from the build menu
(Tab). "Follow the film" only holds once they are placed.

## Tags (suggestions)

Simulation, Industrial, Management, Realistic, First-Person, Singleplayer,
Automation, Education.

## Content survey (Valve's three parts)

- General content: no violence, no sexual content.
- Mature content: none.
- AI content: the operator declares this; parts of the code and the HMI
  mock-ups were written with AI tools (the `.dc.html` screens are "Claude-Design
  exports", per `src/scenes/hud/HmiWebOverlay.gd`). Nothing is generated live
  in the shipped build.

## Images still to make

Sizes from https://partner.steamgames.com/doc/store/assets (checked
2026-09-26). None exist yet. Capsules may carry only the art, the game name and
an official subtitle.

| asset | size |
|---|---|
| Header capsule | 920×430 |
| Small capsule | 462×174 (the logo must nearly fill it) |
| Main capsule | 1232×706 |
| Vertical capsule | 748×896 |
| Page background (optional) | 1438×810 |
| Screenshots, at least 5 | 1920×1080 minimum, 16:9, gameplay only |
| Library capsule | 600×900 |
| Library header | 920×430 |
| Library hero | 3840×1240, no text, keep 860×380 safe area, .png |
| Library logo | 1280 wide and/or 720 tall, transparent .png |
| Shortcut icon | 256×256 or 512×512, .ico or .png |
| Community icon | 184×184, .jpg |
| Trailer | required at release: up to 1920×1080, .mp4/.mov/.wmv, H.264/AAC |

The screenshots should be taken in the build, with the game in a window on a
GPU; the headless probes cannot produce them.

## System requirements

Unknown; see README "Open". Nothing has measured the game on a low-end PC.
