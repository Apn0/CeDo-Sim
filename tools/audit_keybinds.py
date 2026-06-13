#!/usr/bin/env python3
"""Keybind audit: cross-reference project.godot InputMap, runtime-registered
actions (InputMap.add_action calls), and consumers (is_action_pressed /
is_action_just_pressed / get_action_strength). Emits a markdown table.

Run from the repo root: python3 tools/audit_keybinds.py
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Godot 4 keycodes used in the project — only the ones we actually have.
GODOT_KEYS = {
	# Letters
	65:"A", 66:"B", 67:"C", 68:"D", 69:"E", 70:"F", 71:"G", 72:"H",
	73:"I", 74:"J", 75:"K", 76:"L", 77:"M", 78:"N", 79:"O", 80:"P",
	81:"Q", 82:"R", 83:"S", 84:"T", 85:"U", 86:"V", 87:"W", 88:"X",
	89:"Y", 90:"Z",
	# Digits
	48:"0", 49:"1", 50:"2", 51:"3", 52:"4", 53:"5", 54:"6", 55:"7",
	56:"8", 57:"9",
	# Specials
	4194305:"Esc", 4194306:"Tab", 4194308:"Backspace", 4194309:"Return",
	4194310:"KP_Enter", 4194321:"Insert", 4194312:"Delete", 4194313:"Pause",
	4194314:"Home", 4194315:"End", 4194316:"Left", 4194317:"Up",
	4194318:"Right", 4194319:"Down", 4194320:"PageUp", 4194324:"PageDown",
	4194325:"Shift", 4194326:"Ctrl", 4194327:"Meta", 4194328:"Alt",
	4194329:"CapsLock",
	# Function keys
	4194332:"F1", 4194333:"F2", 4194334:"F3", 4194335:"F4", 4194336:"F5",
	4194337:"F6", 4194338:"F7", 4194339:"F8", 4194340:"F9", 4194341:"F10",
	4194342:"F11", 4194343:"F12",
	# Punctuation / symbols
	32:" ", 44:",", 46:".", 47:"/", 59:";", 60:"<", 96:"`",
	4194418:"Numpad_Decimal",  # KP_Period in Godot 4
	# Keypad numbers (KP_0..KP_9 — 4194416..4194425 in Godot 4)
	4194416:"KP_0", 4194417:"KP_1", 4194419:"KP_2",
}

GODOT_MOUSE = {1: "MouseLeft", 2: "MouseRight", 3: "MouseMiddle",
	4: "MouseWheelUp", 5: "MouseWheelDown"}


# ── 1. Parse project.godot ────────────────────────────────────────────────────
def parse_project_godot():
	path = os.path.join(ROOT, "project.godot")
	text = open(path, encoding="utf-8").read()
	# Slice the [input] section only.
	m = re.search(r"\[input\]\s*\n(.*?)(?=\n\[|\Z)", text, re.S)
	if not m:
		return {}
	section = m.group(1)
	# Each action block: "action_name={ ... events:[...] ... }"
	out = {}
	for am in re.finditer(r"^([a-z_][a-z0-9_]*)=\{(.*?)\n\}", section, re.M | re.S):
		action = am.group(1)
		body = am.group(2)
		events = []
		# Each event object in the events list.
		for ev in re.finditer(r"Object\((InputEventKey|InputEventMouseButton),(.*?)\)", body):
			kind = ev.group(1)
			fields = ev.group(2)
			if kind == "InputEventKey":
				kc_m = re.search(r'"keycode":(\d+)', fields)
				phys_m = re.search(r'"physical_keycode":(\d+)', fields)
				kc = int(kc_m.group(1)) if kc_m else 0
				phys = int(phys_m.group(1)) if phys_m else 0
				use = kc if kc else phys
				label = GODOT_KEYS.get(use, f"KEY_{use}")
				events.append(label)
			elif kind == "InputEventMouseButton":
				bi_m = re.search(r'"button_index":(\d+)', fields)
				bi = int(bi_m.group(1)) if bi_m else 0
				events.append(GODOT_MOUSE.get(bi, f"MB_{bi}"))
		out[action] = events
	return out


# ── 2. Scan for runtime-registered actions (InputMap.add_action) ─────────────
def scan_runtime_registrations():
	"""Find runtime registrations. TWO patterns:
	  (a) literal: InputMap.add_action("name")
	  (b) dict-driven: var binds := { "name": KEY_X, ... } / for n in binds: add_action(n)
	      — we approximate by matching any `"action_id": KEY_<SOMETHING>` line that
	      appears in a file that also calls InputMap.add_action somewhere.
	"""
	hits = []
	for dp, _, files in os.walk(os.path.join(ROOT, "src")):
		for f in files:
			if not f.endswith(".gd"):
				continue
			p = os.path.join(dp, f)
			try:
				text = open(p, encoding="utf-8").read()
			except Exception:
				continue
			rel = os.path.relpath(p, ROOT)
			# (a) literal-string calls
			for m in re.finditer(r'InputMap\.add_action\(\s*"([^"]+)"', text):
				hits.append((m.group(1), rel))
			# (b) dict-driven: only count if the file also calls InputMap.add_action
			if "InputMap.add_action" in text:
				for m in re.finditer(r'"([a-z_][a-z0-9_]*)"\s*:\s*(KEY_|MOUSE_|JOY_)', text):
					hits.append((m.group(1), rel))
	# Dedup (some actions appear in both patterns within the same file).
	seen = set(); out = []
	for action, rel in hits:
		key = (action, rel)
		if key in seen: continue
		seen.add(key); out.append((action, rel))
	return out


# ── 3. Scan for consumers ─────────────────────────────────────────────────────
CONSUMER_PATTERNS = [
	r'is_action_pressed\(\s*"([^"]+)"',
	r'is_action_just_pressed\(\s*"([^"]+)"',
	r'is_action_just_released\(\s*"([^"]+)"',
	r'get_action_strength\(\s*"([^"]+)"',
	r'get_action_raw_strength\(\s*"([^"]+)"',
	r'event\.is_action_pressed\(\s*"([^"]+)"',
	r'event\.is_action_released\(\s*"([^"]+)"',
]

def scan_consumers():
	out = {}    # action -> [file, ...]
	for dp, _, files in os.walk(os.path.join(ROOT, "src")):
		for f in files:
			if not f.endswith(".gd"):
				continue
			p = os.path.join(dp, f)
			try:
				text = open(p, encoding="utf-8").read()
			except Exception:
				continue
			for pat in CONSUMER_PATTERNS:
				for m in re.finditer(pat, text):
					a = m.group(1)
					rel = os.path.relpath(p, ROOT)
					out.setdefault(a, set()).add(rel)
	return {k: sorted(v) for k, v in out.items()}


# ── 4. Settings menu — what's listed in Controls? ─────────────────────────────
def scan_settings_menu():
	"""Look for ControlsMenu/Settings scripts and return the action ids that
	appear in their button/label text or as a key remap target."""
	candidates = []
	for dp, _, files in os.walk(os.path.join(ROOT, "src")):
		for f in files:
			if "settings" in f.lower() or "controls" in f.lower() or "options" in f.lower():
				candidates.append(os.path.join(dp, f))
	mentioned = set()
	for p in candidates:
		try:
			text = open(p, encoding="utf-8").read()
		except Exception:
			continue
		for m in re.finditer(r'"([a-z_][a-z0-9_]+)"', text):
			a = m.group(1)
			if "_" in a and len(a) > 3:
				mentioned.add(a)
	return candidates, mentioned


# ── Report ───────────────────────────────────────────────────────────────────
def main():
	static = parse_project_godot()
	runtime = scan_runtime_registrations()
	consumers = scan_consumers()
	settings_files, settings_actions = scan_settings_menu()

	all_actions = set(static.keys()) | {r[0] for r in runtime} | set(consumers.keys())

	print(f"## Keybind audit")
	print(f"\n- {len(static)} actions registered in `project.godot` [input]")
	print(f"- {len(runtime)} runtime InputMap.add_action calls (at {len({r[1] for r in runtime})} sites)")
	print(f"- {len(consumers)} action names referenced in `is_action_*` / `get_action_strength`")
	print(f"- Settings/controls files scanned: {len(settings_files)}")
	print()

	# Issue buckets.
	orphan_action  = []   # action exists but no consumer
	orphan_consumer= []   # consumer for an action that's nowhere registered
	dup_runtime    = {}   # action registered both statically AND at runtime
	by_action = {}
	for a in sorted(all_actions):
		keys = static.get(a, [])
		runtime_sites = [r[1] for r in runtime if r[0] == a]
		consumer_sites = consumers.get(a, [])
		if a in static and a in runtime:
			dup_runtime[a] = runtime_sites
		if (a in static or a in runtime) and not consumer_sites:
			orphan_action.append(a)
		if (a not in static) and not runtime_sites:
			orphan_consumer.append(a)
		by_action[a] = (keys, runtime_sites, consumer_sites)

	print("### Issues\n")
	print(f"**Actions registered but never consumed** ({len(orphan_action)}):")
	for a in sorted(orphan_action):
		if a.startswith("ui_"):
			continue  # ui_* are Godot's built-ins
		print(f"  - `{a}`")
	print()
	print(f"**Action names referenced in code but never registered** ({len(orphan_consumer)}):")
	for a in sorted(orphan_consumer):
		print(f"  - `{a}`  ← consumers: {by_action[a][2]}")
	print()
	print(f"**Double-registered (project.godot + runtime)** ({len(dup_runtime)}):")
	for a, sites in sorted(dup_runtime.items()):
		print(f"  - `{a}`  ← runtime sites: {sites}")
	print()

	# Full table.
	print("### Full table\n")
	print("| action | keys | runtime add | consumers (#) | functional? |")
	print("|---|---|---|---|---|")
	for a in sorted(all_actions):
		if a.startswith("ui_"):
			continue
		keys, runtime_sites, consumer_sites = by_action[a]
		kstr = ", ".join(keys) if keys else ""
		rstr = "yes" if runtime_sites else ""
		cstr = str(len(consumer_sites))
		# Functional = registered in some way AND has at least one consumer.
		functional = "yes" if (keys or runtime_sites) and consumer_sites else "no"
		print(f"| `{a}` | {kstr} | {rstr} | {cstr} | {functional} |")

if __name__ == "__main__":
	main()
