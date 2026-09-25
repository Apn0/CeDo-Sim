# In-world HMI screens and hold-F interact mode — survey (2026-09-25)

**Status: SURVEY ONLY. Nothing is built.** The operator's request is recorded
as CLAIMED in `docs/plant/operator_rulings_2026-09-25.md` §H1. His answers to
the design questions go into §H2 of that file. This document records what the
code does today and what the request would cost. Every file:line was read at
`4c1fb12` and re-checked the same day against `main` `256f828`, 131 commits
later. The line numbers are main's; the facts had not changed, and what main
ADDED is in §1 and §5. Items marked INFERRED were not measured. The pixel figures in §3 are
arithmetic from constants in the code; nothing was rendered.

## 1. How an HMI opens today

`Hmi.gd` (on each placed panel) → `crosshair_interact` → `_open_overlay`
(`src/build/Hmi.gd:110-112, 124-139`). From there it takes one of three
routes, chosen by fields of `HmiScopes.SCOPES`:

| route | panels | what opens |
|---|---|---|
| `web_screen` set | **7**: shredder L1, shredder 1 3A/3B, shredder 3C/6, sorteerlijn 3A/3B, waslijn (all), extruder (all), water 3C/6 | `HmiWebOverlay` (layer 46). A **native WebView2 child window** (godot_wry) is laid over the game and loads a `.dc.html` design (1280×800) from `docs/plant/hmi_screens_2026-07-26/`. |
| `panel_type: "relay"` | **1**: shredder 2 3A/3B | `ShredderRelayPanel` (a 720×460 Control) on its own CanvasLayer at layer 50 |
| neither | **4**: transport 3A/3B, transport 3C/6, water extruder 1/3A/3B, indaver | `HmiOverlay.tscn`: a CanvasLayer at layer 45 with a 900×624 bezel, built in code |

Facts that constrain the design:

- **One shared overlay for all panels** (static `_overlay`, `Hmi.gd:37-41`).
  Mode state such as `_automaat`, `_manual_run` and `_acked_faults` lives on
  that one instance (`HmiOverlay.gd:206-209`).
- **The page resets to HOOFDMENU on every open** (`HmiOverlay.gd:397`). Each
  page switch frees and rebuilds its children (`:839-872`).
- **Refresh is 4 Hz.** A 0.25 s timer in `_process` drives the refresh, which
  reads LineFlow through the `line_flow` group (`HmiOverlay.gd:680-706`; web:
  `HmiWebOverlay.gd:33, 190-196`).
- **Panels beep until someone acknowledges (new on main, 2026-09-25).**
  `Hmi._setup_alarm_sound` (`Hmi.gd:263-351`) counts a panel's unacknowledged
  alarms from two places:
  - its own `EventBus` alarm list;
  - the shared overlay's fault list (`_overlay.unacked_count_for_tokens`).

  KWITTEREN on the overlay acknowledges both. The overlay keeps watching
  while it is closed (`00646e6`). Today only `hmi_washing_all` has a sound
  bank. **This is a second reason the single shared overlay matters.** Per-panel
  in-world screens have to keep one fault/ack model that every panel reads,
  not twelve copies.
- **The game is not paused.** The player stops only because the mouse is no
  longer captured (`PlayerController.gd:343-356`).
- **The sub-screens are plain `extends Control`**: `HmiScreenBase`,
  `L3CUnitScreen`, `WashingScope`, `ExtruderBluPortScope`,
  `KufferathsDryerScope`, `LaserFilterScope`, `SorteerlijnScope` and
  `ShredderRelayPanel`. None of them reads the root viewport size.
  `L3CUnitScreen` already runs standalone under a 1280×800 Control root in
  `src/tests/shot_l3c_unit_screen.gd:19-45`. INFERRED: they can be reparented
  into a SubViewport.

## 2. The hard constraint: a WebView cannot go on a mesh

godot_wry's `WebView` is a native OS window, not a Godot texture:

- `HmiWebOverlay.gd:7-11` says it "can never be a texture on a 3D machine
  screen".
- `src/tests/proof_hmi_web.gd:12-13` records that Godot's own viewport capture
  cannot see it.
- The WebView class exposes no texture or offscreen member (see the survey of
  the DLL's class members).

So the **7 web panels cannot show their current design in the world** as
things stand. There are three ways out, and choosing between them is the
operator's call:

1. **In the world, show the Godot-built page.** It carries the same data and
   has an older look. `ExtruderBluPortScope`, `WashingScope`, `SorteerlijnScope`
   and `L3CUnitScreen` already exist.
2. **Redraw the web designs as Godot Controls**, one screen at a time: 33
   `.dc.html` files. This is the look he approved, and it is the largest
   effort.
3. **Swap the browser addon** for one that renders offscreen to a texture
   (a CEF/Chromium build). That means downloading a large third-party
   binary, and nobody has tried it on 4.6.3. It is not recommended.

## 3. Reading from 3–5 m: the pixel budget

These figures are computed, not rendered. They take:

- the screen face size, 0.49 × 0.315 m (`PlaceableCatalog.gd:6414`);
- the default vertical FOV of 75° (`SettingsManager.gd:42`, `Camera3D` keeps
  height);
- a window 1080 px tall.

| distance | screen on the monitor |
|---|---|
| 0.8 m | 431 × 277 px |
| 1.0 m | 345 × 222 px |
| 3.0 m | **115 × 74 px** |
| 5.0 m | **69 × 44 px** |

At 1440 px tall, multiply by 1.33 (3 m → 153 × 99 px).

At 3 m a 1280-px-wide design is shown about 11× smaller. That makes 14-px
design text about 1 px tall. Status colours and big blocks can be told apart;
numbers cannot be read. The real eye resolves far more than a monitor pixel at
3 m. **"Readable from 3–5 m" in the sim therefore needs one of these:**

- a zoom (a held key narrows the FOV);
- a far-view layout with large figures;
- accepting that you walk up to read it.

I don't know the real panel's physical size. `hmi_screen_inventory` lists
canvases from 1024×600 to 1920×1080, which is the resolution, not the size.
A photo with something of known size beside the panel, or the SIMATIC model
number, would settle it.

## 4. Keys today (VERIFIED)

| key | on foot | elsewhere |
|---|---|---|
| E | `interact`: the crosshair ray, 3.75 m (`PlayerController.gd:49, 997-1001`). If the ray has **no target**, each held tool's own `_unhandled_input` **drops** the tool (10 tools, e.g. `ShovelTool.gd:85`, `WireCutter.gd:111`). | `build_rotate_cw`. Door, Gate and PushGate also read `KEY_E` directly. |
| Q | `hotbar_drop`, **already** (`project.godot:402`, `PlayerController.gd:1067-1071`) | `build_rotate_ccw` |
| F | `flashlight` (`project.godot:140`). It is not marked handled, so with the hose nozzle held, F also fires `hose_advance_back` (INFERRED). | `forklift_lift_down` in a cab; `build_lower` in build mode |
| F8 | `inspect_mode` (`SettingsManager.gd:788`, not `:660` as CLAUDE.md says). It is the editor's Stop key when the game runs embedded. | — |
| LMB | `tool_use` | `build_place` |

Two keys **re-add themselves**: `PlayerController._ensure_hotbar_actions`
(`:1141-1170`) puts Q back on `hotbar_drop` even after a user rebind. Saved
bindings in `user://settings.cfg` replace defaults per action
(`SettingsManager.gd:728-737`). So a changed default does not reach an
existing settings file without a migration like `_migrate_legacy_keybinds`
(`:293-352`).

What the request means for the keys:

- **"Drop → Q"** is only half a change. Q already drops. The work is removing
  E-drop from ten tool scripts.
- **Hold-F** collides with the flashlight tap and the hose's F. Hold-F must be
  on-foot only; F in a cab and in build mode keep their meanings.
- **Clicking a button in the world** needs the hit point, not just the
  collider. The panel's box collider face sits about 8 cm in front of the
  screen face (collider z = 0.25, screen z ≈ 0.17, `PlaceableCatalog.gd:1621-1634`).
  So the click has to be projected onto the screen plane, turned into UV,
  and pushed into the SubViewport as a mouse event (INFERRED design, not built).
- The F1 key sheet (`KeybindSheet.gd:87-109`) and `test_keybind_sheet` read
  `ACTION_GROUPS` / `ACTION_LABELS`. Label text names keys literally at
  `SettingsManager.gd:189, 210, 242-245`.

## 5. Tests that assume a pop-up

All of these run headless and are wired into `run.sh`:

- **`test_hmi_overlay_open_close`** (28 checks, `run.sh:996`): a fresh
  overlay is hidden (`:53`), and `close_overlay` hides the CanvasLayer
  (`:116`).
- **`test_hmi_web`** (`run.sh:799`): `webview_available()` is false headless;
  `open_for` makes it visible (`:195-201`); `close()` hides it (`:207-209`).
- **`test_hmi_retired`** (70 checks): the crosshair prompt starts with "Open "
  (`:190`), and the script is `Hmi.gd` (`:134`).
- **Four suites added on main on 2026-09-25 drive the real overlay or its
  static slot.** `test_hmi_fault_rearm` and `test_hmi_fault_per_line` call
  `open_for` on `HmiOverlay.tscn` with the `hmi_extruder_all` scope.
  `test_hmi_ack_rearm` news up `HmiOverlay.gd`. `test_machine_sounds` sets
  `Hmi._overlay` directly. All four are in the main loop (`run.sh:650`).
  They test the fault/ack model rather than the pop-up, so they should
  survive if that model stays in one shared place (§1).
- **`test_hmi_web_gather_vals`** and **`test_hmi_universal_interactive`** test
  only the data path, so they survive any rendering change.

Headless facts that matter for new tests:

- Under the dummy renderer a ViewportTexture comes back **empty**
  (`shot_l3c_unit_screen.gd:9-10`, `tool_render_3c_mimic.gd:17`), and
  CanvasItem draw callbacks never fire (`test_laserscope_pressure_box.gd:15`).
- As with MultiMesh, a headless suite can assert the node graph (the
  SubViewport, its Control, the page persisting, a pushed click reaching a
  button) but **never the pixels**.
- A readability claim needs a windowed render, per Rule 2.

## 6. Cost — MEASURED 2026-09-25 (`src/tests/probe_inworld_hmi_cost.tscn`)

**Setup.** The probe ran windowed on the operator's PC (NVIDIA GTX 1070,
1280×720 window, vsync off), with `APPDATA` pointed at an empty folder on D: so
`user://` was not his.

- Twelve quads are built at the screen face size, all in view.
- N of them are textured by a SubViewport that hosts the **real**
  `HmiOverlay.tscn`, opened on `hmi_extruder_all` with the ExtruderBluPort
  page.
- The 2D is laid out at 1280×800 and stretched onto the texture.
- 2 s warm-up, then 4 s measured per configuration.
- Another session's headless suites were running at the same time and shared
  the CPU. The baseline repeated at the end of each run within 0.2 ms.
- Two runs: the full grid, then an attribution pass (`-- --attrib`).

**Full grid** (mean frame-time delta against the baseline of 2.11 ms; GPU = the
SubViewports' measured GPU time):

| screens | texture | redraw every frame | redraw on the 4 Hz tick |
|---|---|---|---|
| 1 | 640×400 | +4.2 ms | +3.7 ms |
| 1 | 1280×800 | +4.6 ms | +3.9 ms |
| 4 | 640×400 | +11.7 ms | +10.0 ms |
| 4 | 1280×800 | +12.3 ms | +10.4 ms |
| 12 | 640×400 | +32.5 ms (GPU 0.59 ms) | +22.5 ms |
| 12 | 1280×800 | +28.7 ms (GPU 0.88 ms) | +26.7 ms |

**Attribution** (12 screens, 640×400; baseline 1.67 ms):

| what changed | delta |
|---|---|
| BluPort page, redrawn on the 4 Hz tick | +22.7 ms |
| BluPort page, SubViewport **never draws** (`UPDATE_DISABLED`) | +21.9 ms |
| BluPort page with its own `_process` switched off | **+1.6 ms** |
| HOOFDMENU page, redrawn on the 4 Hz tick | **+0.8 ms** |
| HOOFDMENU page, never draws | +0.6 ms |

**What this says:**

- **Drawing is cheap.** Twelve screens cost 0.6–0.9 ms of GPU time when they
  redraw every frame. Redrawing a HOOFDMENU page at 4 Hz adds about 0.25 ms
  over never drawing it. Texture size (640×400 vs 1280×800) made no difference
  to frame time that stands above the noise.
- **The cost is the ExtruderBluPort page's own `_process`, about 1.8 ms per
  screen per frame.** `ExtruderBluPortScope._process`
  (`src/scenes/hud/scopes/ExtruderBluPortScope.gd:184`) updates its rail,
  right panel, schematic overlays and clock, and redraws its chart, on
  **every frame**. That work does not depend on whether the texture is drawn.
  It already costs that much today, in the pop-up, but only while one pop-up
  is open.
- **Consequences for the build:**
  - Before any page lives in the world, its per-frame updates move onto the
    overlay's 4 Hz tick, and only for screens the player can see.
  - Every page that goes in-world gets measured the same way.
  - With that done, the HOOFDMENU figure (0.8 ms for twelve) is the order of
    cost to expect.

**Not measured, and why:**

- No LineFlow and no extruder model were bound, so pages drew defaults, and a
  running plant makes the 4 Hz refresh do more work.
- Distance and off-screen culling were not tried, because every screen was in
  view.

## 7. Placement

Panels are placed from the build menu, not by the line macros. `BuildMode`
treats `hmi_*` as flow-irrelevant (`BuildMode.gd:1111`). **0 of 12**
panels have an operator-specified mount (`HmiScopes.MOUNTS`, all
`MOUNT_UNSET`). An in-world screen shows only where he has placed a panel.

## 8. Decided 2026-09-25 — the spec is in the rulings file

The operator answered four rounds of questions. The consolidated spec is
`docs/plant/operator_rulings_2026-09-25.md` §H5 and is not repeated here. In
short:

- Screens are in the world with a page per panel, saved with the game.
- There is no pop-up. E on an HMI does nothing, and the web designs are
  redrawn later.
- The extruder/PCU panel comes first.
- Hold F (longer than ~0.2 s) enters F-mode: first person, zoom, a gold aim
  dot and a ~1.5 m click reach. Tap F does single actions.
- E becomes pick-up. L becomes the flashlight. In a cab, E is lift down. R is
  hose reel-in.

## 9. Build order, when it is started (proposal, not started)

Each step lands with its own measurement.

1. **Cost probe first** (§6). **DONE 2026-09-25.** It runs windowed, because
   the dummy renderer cannot measure GPU cost. The result:
   - use 640×400 textures, redrawn on the 4 Hz tick;
   - drawing is not the problem; the ExtruderBluPort page's per-frame
     `_process` is, at ~1.8 ms per screen per frame.
2. **Move the ExtruderBluPort page's per-frame updates onto the 4 Hz tick**
   (and only for screens in view). Re-run the probe, which should read near
   the HOOFDMENU figure.
3. **Extruder panel in the world:**
   - Move `HmiOverlay`'s chrome and pages out of the CanvasLayer into a
     Control that one SubViewport per panel hosts.
   - Put the ViewportTexture on a **named** screen MeshInstance.
     INFERRED from `StaticMerge.gd:110-134`: today the screen box is probably
     merged into `Model/StaticMerged`, so it has to be excluded from the
     merge.
   - Headless proofs, which check the node graph and never pixels:
     - the page persists across walking away;
     - a synthetic click pushed into the SubViewport reaches the right button;
     - the page round-trips through save and load.
   - Readability needs a windowed render at 1, 3 and 5 m.
4. **F-mode:**
   - hold/tap detection;
   - the camera state save/restore in `CameraRig`, with the FOV;
   - zoom and look-sensitivity scaling;
   - the gold dot;
   - the ray through the gold dot → the screen plane → UV →
     `SubViewport.push_input`.
5. **Key migration** (E/F/Q/R/L in both contexts):
   - the Door/Gate/PushGate raw `KEY_E` reads;
   - the 10 tool E-drop branches;
   - a `settings.cfg` migration;
   - the F1 sheet labels;
   - `test_keybind_sheet`.
6. **Retire the pop-up paths.** Update `test_hmi_overlay_open_close`,
   `test_hmi_web` and `test_hmi_retired` (§5) to assert the in-world screen
   instead. Never delete the old suites; `.bak` them (Rule 5).
