# CeDo-Sim

LDPE Recycling Simulator — a Godot 4.6 model of a real plastic-film recycling
plant (CeDo, Geleen NL) that the operator actually worked at. The plant is a
real place; the sim is judged against it, not against what seems plausible.

- **`CLAUDE.md`** — deep project knowledge, engine paths, harness facts, and the
  traps that have already cost this project weeks. Read it before searching.
- **`docs/`** — the plant record. `docs/plant/` is primary; photos illustrate.
- **`bash tools/regression/run.sh`** — the one command that proves things.

---

# THE CONTRACT FOR CHANGING ANYTHING

> Written 2026-08-30 after an assistant reported "the Tab key is not
> implemented" about a feature that had worked for months. It searched `src/`
> for the literal string `KEY_TAB`. This project binds keys through **named
> InputMap actions**, so `KEY_TAB` appears in no source file *by design* — the
> search could not have succeeded. The binding was in `project.godot`, the
> handler at `BuildMode.gd:1296`, the intent documented at `BuildMode.gd:15`,
> and the rebind entry at `SettingsManager.gd:165`. The keycode `4194306` was
> visible in the search output and was read past.
>
> **A feature is not absent because your grep missed it.** Before reporting that
> something does not exist, find out how this project *expresses* that kind of
> thing, then search for that. "Not found" is a statement about your search.

A feature is not "added" when the code runs. It is added when it is reachable,
rebindable, discoverable, wired to real simulation state, tested, and written
down. Work the list below **before** writing code and **again** before saying
done.

## 1. Reachability — can the operator actually get to it?

- [ ] **Main menu** — `src/scenes/menus/main_menu/MainMenu.tscn` / `.gd`.
      Does this need an entry, and does the existing layout still fit?
- [ ] **Pause / in-game menu** — the `ui_cancel` path ("Pause / cancel",
      `SettingsManager.gd:190`). Reachable while paused? Should it be?
- [ ] **Settings menu** — `src/scenes/menus/SettingsMenu.tscn` / `.gd`.
- [ ] **HUD** — `src/scenes/hud/`. Is there a prompt, or is the feature
      invisible until you already know it exists?

## 2. Input — never invent a key

- [ ] **Read `project.godot`'s `[input]` block first.** Every binding is a named
      action there. Keycodes are decimal Godot constants, not letters —
      `4194306` is Tab, `4194305` is Escape. Decode before concluding.
- [ ] **Check the key is free.** Two actions on one key is a silent conflict.
- [ ] **Register it for rebinding** — `SettingsManager.gd` `KEYBIND_GROUPS`
      (~`:130-170`): put the action in the right group, or it cannot be rebound
      and does not appear in the settings UI at all.
- [ ] **Add its human label** (~`:180-250`). House style embeds the key:
      `"Rotate placement CCW (Q · scroll down)"`. *Known gap:*
      `"build_mode_toggle": "Toggle build mode"` carries no `(Tab)` — every
      sibling does. Fix labels like this when you touch them.
- [ ] **Handle it through the action**, never a raw keycode:
      `event.is_action_pressed("my_action")`.

Search by mechanism, not by literal:

```bash
grep -n "my_action" project.godot src/autoload/SettingsManager.gd
grep -rn "is_action_pressed" src/ | grep my_action
```

## 3. Is it real, or only present?

The repo's own Rule 3: **a bench green proves the mock, not the feature.**
`npc-05` passed 31/31 while moving 0.00 kg.

- [ ] **Wired into the simulation**, not just instantiated — does it appear in
      `LineFlow` / `WorldLayout` / `BuildMode`'s `PlacedObjects`, does it get a
      `placeable_id`, does it survive save→reload?
- [ ] **Dependencies OF the feature** — what must exist first? Does it degrade
      honestly when that is missing, or silently do nothing?
- [ ] **Dependencies ON the feature** — what already calls this? Check every
      call site before changing a signature or a contract.
- [ ] **Catalog / registry entries** — a new placeable that is not in
      `PlaceableCatalog.gd` and not in the build menu does not exist to the
      operator, however good the model is.

## 4. Detail and provenance

- [ ] **Rule 1: no build without docs.** Plant components come from operator
      photos, specs, or explicit approval — never from imagination.
- [ ] **Meets `docs/DETAIL_STANDARD_audit_2026-08-18.md`.**
- [ ] **Grime by default** (`PlaceableCatalog._mat`); motors CeDo blue `#191E6C`
      unless the operator says otherwise, and record the exception if so.

## 5. Proof

- [ ] **A test that fails when the feature breaks.** Wire it into
      `tools/regression/run.sh` — a test the harness never runs buys nothing.
- [ ] **Mutation-test it.** Break the behaviour on purpose; watch the test go
      red **and exit**. A test you have never seen fail is unproven.
- [ ] **Counted checks, not bare `assert()`.** A failing `assert()` aborts before
      `quit()` and *hangs* the harness instead of failing it — measured, 90 s
      without exiting. It is also compiled out of release builds.
- [ ] **Full harness before and after.** Compare the FAIL lists; new red is
      yours until proven pre-existing by a baseline run.

## 6. Write it down

- [ ] `CLAUDE.md` for anything a future session would otherwise rediscover.
- [ ] `docs/audit/` for anything measured.
- [ ] **Correct stale numbers when you find them.** `CLAUDE.md`'s own harness
      section once claimed 23 suites and blamed a test that had started passing.

## 7. When you do not know — ask the operator

Do not guess at plant behaviour, layout, naming, or what a request meant. Ask a
direct question in chat (an `AskUserQuestion` popup) with the specific options.
One question at a time. A wrong assumption modelled in detail costs more than
the question would have.

---

**Failure modes this list exists to prevent** — every one has happened here:

| symptom | root cause |
|---|---|
| "X is not implemented" | grepped for an implementation detail instead of the binding mechanism |
| feature works, nobody can find it | no menu entry, no HUD prompt, no rebind entry |
| green tests, dead feature | asserted on a mock instead of a real world boot |
| harness hangs instead of failing | bare `assert()` with no counted fallback |
| merge parses on both branches, breaks combined | GDScript has no block scoping; two `var x` in one function |
| doc says 23 suites, reality is 41 | numbers written once and never re-measured |
