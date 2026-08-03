# World / Save regression harness

Automated proof that **world creation** and **save creation** are correct — the
answer to "how do I *know* the machines aren't landing outside the building
again?"

## Run it

```bash
bash tools/regression/run.sh
```

Exit code `0` = all green. Output: `tools/regression/out/topdown.png` (visual)
and `out/last_run.log` (assertions).

## What it checks

Boots the **real** `MainWorld` headless against the real `world_layout.json`.

**World creation**
- `Plant` initialised; operating-floor grade at ~−9.0 (the site datum, not a
  wing roof);
- building shell mesh present with a real footprint;
- every door/gate in `WorldLayout.structure_items` sits **on a wall line**
  (checked by mapping each door back into the building frame).

**Macro sanity**
- every operator line macro (`user://macros/*.json`) is validated: accumulated
  `dx/dy/dz` drift must stay within sane bounds. This is the guard that catches
  a **corrupt macro** (the original `line_3a.json` had an 82.5 m lateral and a
  27 km vertical delta — which is exactly what threw built lines into the yard).

**Save creation**
- every `LINE_3A_SEQ` id resolves in the catalog (no silently-dropped machines);
- a line built from the **clean const seed** places the expected machine count;
- **every** machine lands **inside** the true building footprint — tested by
  converting each machine's scene position back to the building frame and
  checking the real wall rectangles (NOT the rotated AABB, which is the trap
  that hid the bug);
- `save → clear → reload` reproduces every machine position to **< 1 cm**.

## How correctness is proven (not assumed)

`Plant.scene_to_pc` + the building-frame affine are exact inverses, verified in
the run itself: all four operator-placed doors map back to their known building
frame coordinates to the centimetre. The machine inside/outside test rides on
that same, validated transform.

## Files

- `src/tests/regression_world_save.gd` / `.tscn` — the in-engine harness.
- `tools/regression/topdown_render.py` — data-driven top-down PNG (matplotlib).
- `tools/regression/run.sh` — one-command runner.
- `out/` — generated: `topdown.png`, `positions.json`, `last_run.log`.
