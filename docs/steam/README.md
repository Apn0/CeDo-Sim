# CeDo Simulator on Steam

**State on 2026-09-26: the Windows 64-bit build is ready and measured. Nothing
is on Steam yet.** The operator has no Steamworks partner account. Creating one,
the identity/tax/bank steps and the $100 app fee are his to do; the steps are
below. Everything after that (build, upload) is scripted.

Operator rulings for this build, 2026-09-26:
- Ship the CeDo name, logo and plant data as they are ("Ship as is"); getting
  CeDo's OK is his.
- Windows 64-bit only.
- Bundle his world layout as a new player's starting world.

The store-page draft and the image list are in [store_page.md](store_page.md).

## What was measured

Build `c1dabb7` + this change, exported with Godot 4.6.3 release templates
into `D:\cedo_archive\steam\build\windows\`: `CeDoSimulator.exe` 104.6 MB,
`CeDoSimulator.pck` 743.5 MB, `godot_wry.dll`,
`libgodot_rapier.windows.x86_64-pc-windows-msvc.dll`. Every run used a scratch
`APPDATA` under `D:\cedo_archive\steam\scratch\` or a copy of the operator's
userdata under `D:\cedo_archive\userdata\steam_probe\`. His real
`world_layout.json` kept md5 `e046af7d…` throughout.

| check | result | log (`D:\cedo_archive\steam\logs\`) |
|---|---|---|
| the 101 cache-only assets (building shell, Merlo P40, cars, textures), `MainWorld`, `MainMenu`, `audio_layout.json` load from the `.pck` | 104 of 104 | `probe_pck_seeded.log` |
| web HMI: `hmi_shell.html`, React vendor script, the 34 `.dc.html` screens readable | ok | same |
| machine-sound specs found in the export (`.tres.remap`) | 12 | same |
| shipped `.exe`, empty `APPDATA`, first launch: writes the bundled layout to `user://` | `seeded` printed, md5 = the operator's | `scratch\player_run1.log` |
| second launch after the player's file changed: no re-seed, player's file kept | ok | `scratch\player_run2.log` |
| a player's New Game in the export: world configured, building frame fitted, his 3A/3B gate placed | 9 ok, 0 fail, 0 `SCRIPT ERROR` | `probe_pck_seeded.log` |
| the same WITHOUT the bundled layout (first build) | no building frame, 0 placed, 0 LineFlow nodes | `probe_pck_fresh.log` |
| the project source (not the export), empty `APPDATA` | identical to the line above, so the export is faithful | `probe_src_fresh.log` |
| `test_api_keys` (new check [5]: a build without the `editor` feature takes no key from a Desktop `.env`) | 18 ok; the gate removed gives 3 red | scratchpad |
| parse sweep / `test_new_world_wipe` | 482 ok, 0 fail / 11 ok, 0 fail | `parse_sweep2.log`, `test_new_world_wipe.log` |

A New Game has 0 LineFlow nodes in the export and in the editor alike: the
factory starts empty and lines are placed from the build menu. That is the
current development state, not an export defect.

Not measured: a windowed run on a GPU. Every run above is headless, so frame
rate, the renderer and the web HMI's WebView2 window have not been seen in the
export. Play it once before uploading.

## Why the build needs its own export setup

- **101 assets have no source file since the 2026-09-21 wipe**
  (`docs/audit/assets_loss_and_restore_2026-09-21.md`). Among them are
  `CeDo_factory_solid.obj`, `CeDo_building.obj`, the Merlo P40 and the traffic
  cars. Godot's "Export all resources" only sees files on disk, so it would have
  shipped a game without its building. `tools/steam/gen_export_preset.py` lists
  every resource explicitly ("selected resources" mode), and a listed path is
  exported through its `.import` file, source or not. It is re-run on every build.
- **Left out** (never loaded by the game): `src/tests/`, `tools/`, `docs/`
  except the web HMI pages, `assets/reference_photos/` (451 MB of plant photos,
  cited in comments only), `assets/building_3d_raw/` (519 MB, only the
  `BuildingAlign` dev scene), the `line_connection_audit` CSV.
- **The web HMI pages are plain files**, added by the preset's include filter.
  The line-3C mimic PNG is an imported texture, so the WebView cannot read it in
  the export; the 3C overview then renders without its machine drawing (its
  shell handles a missing mimic by design).
- **API keys.** `ApiKeys` used to read `.env` from the Desktop of whoever runs
  the game. An exported build no longer does (`OS.has_feature("editor")`).
  Without keys, the voice features use their local fallback.
- **The starting world.** `WorldLayout._seed_from_build` (exported builds
  only): when `user://world_layout.json` does not exist, it writes
  `res://steam_seed/world_layout.json`, copied from the operator's file by the
  build script, and says so in the log. `steam_seed/` is gitignored.
- **One `user://` for both.** The exported game and the editor share
  `%APPDATA%\Godot\app_userdata\CeDo Simulator`. On this machine the Steam
  build plays the operator's own world and saves into it; the harness writes
  there too. Never run a test build without a scratch `APPDATA`.
- **The exported release `.exe` ignores `--script`** (measured: it opened the
  main menu instead). To look inside a `.pck`, run it with a copy of the editor
  binary: see "Checking a build".

## Building

```bash
bash tools/steam/build_windows.sh
```

Copies the seed, regenerates `export_presets.cfg`, exports into
`D:\cedo_archive\steam\build\windows\` (a previous build is moved to
`windows.prev-<stamp>`, never deleted) and writes `build_info-<stamp>.txt`
beside it. About 90 s.

## Checking a build

Seeding, with the shipped `.exe` (it runs the main menu for 300 frames):

```bash
A=/d/cedo_archive/steam/scratch/appdata_player; rm -rf $A; mkdir -p $A
APPDATA="$(cygpath -w $A)" timeout 90 /d/cedo_archive/steam/build/windows/CeDoSimulator.exe --headless --quit-after 300 > $A.log 2>&1; grep seeded $A.log
```

Contents and a New Game, with the probe: copy the Godot 4.6.3 editor binaries
(both `.exe`) and the two DLLs from the build into
`D:\cedo_archive\steam\scratch\runner\`, then:

```bash
APPDATA="$(cygpath -w /d/cedo_archive/steam/scratch/appdata_player)" timeout 330 /d/cedo_archive/steam/scratch/runner/Godot_v4.6.3-stable_win64_console.exe --headless --main-pack D:/cedo_archive/steam/build/windows/CeDoSimulator.pck --script <repo>/tools/steam/probe_export.gd -- --paths=<file with res:// paths>
```

Read `Result:` together with the `^SCRIPT ERROR` count. Exit 139 after the
verdict is the known headless teardown segfault.

## Getting it onto Steam

Checked against Valve's pages on 2026-09-26. Where two Valve pages disagree,
both are given.

1. **Steamworks account** at https://partner.steamgames.com. Sign the NDA and
   the Steam Distribution Agreement, give your legal name for identity
   verification, bank details (the account holder must match) and a tax
   questionnaire. Tax review "may take 2-7 business days"
   (https://partner.steamgames.com/doc/gettingstarted/onboarding).
2. **Pay the Steam Direct fee**: $100 per app, not refundable, paid back after
   the app earns $1,000 adjusted gross revenue
   (https://partner.steamgames.com/steamdirect). This creates the AppID.
   Before release: a 30-day wait after paying (that page) or 21 days (the
   onboarding page), and the store page must be public as "Coming Soon" for at
   least two weeks (https://partner.steamgames.com/doc/store/coming_soon).
3. **Note the AppID and the depot ID** (App Admin; SteamPipe > Depots).
   Valve recommends a separate build account that has only "Edit App
   Metadata" and "Publish App Changes To Steam"
   (https://partner.steamgames.com/doc/sdk/uploading).
4. **Get steamcmd** from the Steamworks SDK (partner site;
   `tools/ContentBuilder/builder/steamcmd.exe`) and put it in
   `D:\cedo_archive\steam\steamcmd\` (or set `STEAMCMD`).
5. **Log in once by hand**: run `steamcmd +login <build account>`, enter the
   password and the Steam Guard code, then `quit`. steamcmd keeps the login;
   the upload script never asks for a password.
6. **Preview, then upload**:
   ```bash
   STEAM_APPID=<appid> STEAM_DEPOTID=<depot> STEAM_USER=<build account> bash tools/steam/upload.sh
   STEAM_APPID=<appid> STEAM_DEPOTID=<depot> STEAM_USER=<build account> PREVIEW=0 bash tools/steam/upload.sh
   ```
   The first command is a preview: it reports and uploads nothing. The second
   uploads. `BRANCH=<beta branch>` sets the build live on that branch; the
   default branch is set live in App Admin. For an unreleased app only the
   Steam accounts in your partner account own it, so this is private
   (https://partner.steamgames.com/doc/store/application/builds).
7. **Store page**: text, images and the content survey (it includes the AI
   content disclosure), from [store_page.md](store_page.md). It is not public
   until Valve approves it and you click "Post as Coming Soon". Submit at least
   7 business days before you want it live; review "typically takes 3-5
   business days" (https://partner.steamgames.com/doc/store/review_process).
8. **Testers**: a first-time developer can request keys three weeks after the
   AppID was created (https://partner.steamgames.com/doc/features/keys).
   Steam Playtest can hand out access before the store page is live
   (https://partner.steamgames.com/doc/features/playtest).

## Open

- **Rights.** Valve's agreement has you warrant that you hold "all necessary
  rights" to what you distribute. The build carries CeDo's name and logo and
  plant data from CeDo documents. The operator ruled "ship as is" and will
  handle CeDo's OK himself. No Valve page addresses a real company's name or
  logo specifically.
- **WebView2.** The web HMI panels need Microsoft's WebView2 runtime, which
  Windows 10/11 usually has. Whether Steam should install it as a
  redistributable: I don't know. It is settled by running the build on a PC
  without WebView2, or by checking Steamworks' redistributables list.
- **System requirements** for the store page: I don't know. Nothing here
  measures performance on a GPU. It is settled by playing the build on a known
  low-end PC.
- **Supported languages**: the UI mixes English and Dutch plant vocabulary.
  The operator decides what to declare.
- Found in passing, not export problems: `src/data/plant/qa_spec_ldpe.json`
  (`QaSpec.DEFAULT_SPEC_PATH`) is not in the repository; the `waterbox` addon
  references files it does not have (the export log's only real errors).
