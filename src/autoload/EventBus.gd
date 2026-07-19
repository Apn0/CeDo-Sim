extends Node

## Global signal hub. Register as autoload "EventBus" in Project Settings.
##
## Rationale: when a vacuum alarm fires, dozens of unrelated systems care
## (HUD blink, alarm siren, machine state change, ShiftClock tagging,
## TelemetryRecorder). Wiring those peer-to-peer creates a tangle and breaks
## when nodes are added/removed. EventBus centralises the broadcast.
##
## Naming convention: <subject>_<past_tense_event>(args). Always past tense —
## signals describe things that have *happened*, not things to do.

# ── Machine lifecycle ─────────────────────────────────────────────────────────
signal machine_state_changed(machine_id: String, old_state: int, new_state: int)
signal machine_alarm_raised(machine_id: String, alarm_id: String, severity: int)
signal machine_alarm_cleared(machine_id: String, alarm_id: String)
signal machine_lump_produced(machine_id: String, mass_kg: float, temp_c: float)
## Emitted every sim-tick while a machine is in VACUUM_ALARM state.
## remaining_s counts down from vacuum_alarm_grace_s → 0 (cascade failure).
signal machine_vacuum_alarm_tick(machine_id: String, remaining_s: float)

## Generic SCADA event channel — for higher-level operational events that don't
## fit the per-machine alarm/state/lump signals above. Used for things like:
##   * "cascade_stop_all_except_pcu" — emitted by ExtruderMachine on the edge
##     into the extruder's FAULT state. The PCU/CutterCompactor keeps running
##     (operator anecdote: stopping the PCU mid-charge lets the pot solidify
##     at 125 °C, which is a multi-day teardown); everything else downstream
##     of the extruder halts.
##   * "cascade_resume" — emitted when the operator clears the upstream FAULT.
##   * Future: "leegdraaien_started", "shift_handover", "td_blade_work_scheduled",
##     etc. — anything the SCADA panel + ledger + audio mixer want to react to
##     but isn't a simple per-machine state change.
## `line_id` identifies which extruder line emitted it (e.g. "3A", "3B", "1");
## `event_name` is a stable string key; `data` carries event-specific payload
## (free-form Dictionary so we don't have to add a new signal for every
## variation).
signal scada_event(line_id: String, event_name: String, data: Dictionary)

# ── Player actions ────────────────────────────────────────────────────────────
signal player_interacted(target: Node, interaction: String)
signal player_picked_up(item_id: String)
signal player_dropped(item_id: String)

# ── Operator embodiment (mode switching) ──────────────────────────────────────
signal operator_mode_changed(old_mode: String, new_mode: String)
signal operator_entered_vehicle(vehicle: Node)
signal operator_exited_vehicle(vehicle: Node)

# ── Interaction prompts (HUD bottom-centre [E] hint) ──────────────────────────
## Pattern: any interactable (VehicleEnterArea, ExtruderMachine, etc.) emits
## `_show` when the player enters its range, `_hide` when they leave. HUD
## tracks the most recent source — if the active source emits `_hide`, the
## prompt clears; if a different source emits `_show`, it replaces.
signal interaction_prompt_show(source: Node, prompt: String)
signal interaction_prompt_hide(source: Node)

# ── Barcode scanner ───────────────────────────────────────────────────────────
## Fired when the scanner returns a hit. HUD shows `text` in a banner
## under the centre crosshair for ~3 s before fading. `text` is multi-line
## ("[scan] <name>\n  key : value\n  ...").
signal scanner_banner(text: String, is_error: bool)

## #3 — a bale was physically scanned (barcode gun read its label). `entry` is a
## structured row for the shift-leader scan log: batch / item / origin / weight_kg /
## line / by / time / elapsed. ScanLog records it; the office terminal displays it.
signal bale_scanned(entry: Dictionary)
## Emitted by ScanLog after it appends a row, so an open terminal refreshes live.
signal scanlog_changed

# ── Vehicle events (used by both player + NPC drivers) ────────────────────────
signal vehicle_fuel_low(vehicle_id: String, fuel_fraction: float)
signal vehicle_fuel_empty(vehicle_id: String)
signal vehicle_refueled(vehicle_id: String)
signal vehicle_collided(vehicle_a: String, vehicle_b: String, impulse: float)

# ── Shift lifecycle ───────────────────────────────────────────────────────────
signal shift_started
signal shift_ended
## Emitted by SaveCoordinator.save_game() after every flush — the 60 s autosave
## tick, the pause-card Save button, and Save & Quit. HUD listens and pops a
## short "✓ Saved" toast so the operator can see progress reached disk.
signal autosave_completed

# ── Social / mutual aid ───────────────────────────────────────────────────────
signal npc_called_for_help(caller_id: String, target_id: String, task: String)
signal npc_started_helping(helper_id: String, helped_id: String, task: String)
signal npc_finished_helping(helper_id: String, helped_id: String, task: String, success: bool)
