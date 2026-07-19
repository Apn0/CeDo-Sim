#!/usr/bin/env python3
"""Flag GDScript function parameters that are never used in the body.

WHY THIS EXISTS
---------------
This project treats warnings as errors, and UNUSED_PARAMETER is the one that
keeps shipping: three separate instances slipped through a "verified" batch on
2026-07-19/20 (RefuelBlowerTask._tick_refuel, BeltBuilder.build_internal,
OverflowDumpTask._tick_scoop_bulk).

They slip through because there is NO headless way to see GDScript warnings.
Verified on Godot 4.6.3: `--check-only --script`, a runtime `load()` of the
script, and `--headless --editor --quit` ALL print nothing for a deliberately
planted unused parameter. Warnings are produced by the editor's script-reload
path only, i.e. they reach the operator and not CI. Hence this static check.

SCOPE (deliberately narrow — it only claims what it can prove)
--------------------------------------------------------------
* Single-line `func` signatures only. Multi-line signatures are skipped and
  counted in the summary so the blind spot is visible, never silent.
* A parameter counts as USED if its name appears as a whole word anywhere in
  the function body, including inside strings — a false negative is much
  cheaper here than a false positive that trains people to ignore the tool.
* Parameters already prefixed with `_` are the project's "intentionally unused"
  convention and are skipped, same as the engine does.

Usage:  python3 tools/regression/lint_unused_params.py [root=src]
Exit:   0 clean, 1 if any unused parameter was found.
"""

import re
import sys
from pathlib import Path

FUNC_RE = re.compile(r"^(\s*)(?:static\s+)?func\s+\w+\s*\((.*)\)\s*(?:->\s*[\w\.\[\], ]+\s*)?:\s*(#.*)?$")
FUNC_START_RE = re.compile(r"^\s*(?:static\s+)?func\s+\w+\s*\(")


def split_params(param_src: str):
    """Split a parameter list on top-level commas (types can contain commas)."""
    params, depth, cur = [], 0, ""
    for ch in param_src:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            params.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        params.append(cur)
    return params


def param_name(param: str):
    name = param.strip()
    for sep in ("=", ":"):          # strip default value, then type hint
        if sep in name:
            name = name.split(sep, 1)[0]
    name = name.strip()
    return name if re.fullmatch(r"[A-Za-z_]\w*", name or "") else None


def body_lines(lines, start_idx, indent):
    """Lines belonging to the function that starts at start_idx."""
    out = []
    for line in lines[start_idx + 1:]:
        if not line.strip():
            out.append(line)
            continue
        cur_indent = len(line) - len(line.lstrip())
        if cur_indent <= len(indent):
            break
        out.append(line)
    return out


def check_file(path: Path):
    findings, skipped = [], 0
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for i, line in enumerate(lines):
        m = FUNC_RE.match(line)
        if not m:
            if FUNC_START_RE.match(line):
                skipped += 1          # multi-line signature: out of scope
            continue
        indent, param_src = m.group(1), m.group(2)
        body = "\n".join(body_lines(lines, i, indent))
        for p in split_params(param_src):
            name = param_name(p)
            if not name or name.startswith("_"):
                continue
            if not re.search(rf"\b{re.escape(name)}\b", body):
                findings.append((i + 1, name, line.strip()))
    return findings, skipped


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "src")
    files = sorted(root.rglob("*.gd"))
    total, skipped_total = 0, 0
    for f in files:
        findings, skipped = check_file(f)
        skipped_total += skipped
        for lineno, name, sig in findings:
            total += 1
            print(f"{f}:{lineno}: parameter '{name}' is never used -> rename to '_{name}'")
            print(f"    {sig}")
    print(f"[lint_unused_params] {len(files)} files, {total} unused parameter(s), "
          f"{skipped_total} multi-line signature(s) not checked")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
