#!/usr/bin/env python3
"""
symbol_flow.py — catch the `_live_pieces` bug class repo-wide.

MOTIVE (operator, 2026-08-17): BaleBurst.gd wrote `_live_pieces.append(seg)` at a
line where `_live_pieces` was never declared. The identifier occurred EXACTLY ONCE
in the whole codebase. That single fact was enough to prove the symbol was broken,
and it had blocked every test in the repo for three weeks.

So: count how often each symbol occurs, and where it sits in the read/write flow.
Every variable in a pipeline should be WRITTEN somewhere and READ somewhere. A
symbol that is only one of those is either dead or broken.

Verdicts
  UNDECLARED  used but never declared in its file  -> hard parse error (the _live_pieces case)
  WRITE_ONLY  assigned/appended, never read back   -> dead state; the write is a lie
  READ_ONLY   read, never assigned after its decl  -> always its default value
  DEAD        declared, never mentioned again      -> harmless clutter

Scope: private members/locals (leading `_`) plus plain locals, analysed PER FILE.
GDScript private convention makes this sound: a `_name` must resolve inside its own
file, so an in-file miss is a real miss. Names reached through `.` (obj.field) are
attributed to the object, never to this file, which keeps false positives near zero.

Usage:  python tools/audit/symbol_flow.py [--root src] [--project DIR] [--json out.json] [--all]
        res:// resolves against --project, by default the project.godot directory
        at or above --root, so the result does not depend on the current directory.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict

# --- GDScript lexical helpers ------------------------------------------------

_IDENT_RE = re.compile(r'\b[A-Za-z_][A-Za-z0-9_]*\b')
# An identifier reached through a dot belongs to the other object, not this file.
_DOTTED_RE = re.compile(r'\.\s*([A-Za-z_][A-Za-z0-9_]*)')

_DECL_PATTERNS = [
    # `(?:@\w+…)*` covers @export/@onready/@export_range/… in any combination.
    re.compile(r'^\s*(?:@\w+\s*(?:\([^)]*\))?\s*)*(?:static\s+)?var\s+([A-Za-z_]\w*)'),
    re.compile(r'^\s*const\s+([A-Za-z_]\w*)'),
    re.compile(r'^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)'),
    re.compile(r'^\s*signal\s+([A-Za-z_]\w*)'),
    re.compile(r'^\s*class\s+([A-Za-z_]\w*)'),
    re.compile(r'^\s*class_name\s+([A-Za-z_]\w*)'),
    re.compile(r'^\s*enum\s+([A-Za-z_]\w*)'),
    re.compile(r'^\s*for\s+([A-Za-z_]\w*)\s+in\b'),
]
_FUNC_OPEN_RE = re.compile(r'^\s*(?:static\s+)?func\s+\w*\s*\(')
_LAMBDA_OPEN_RE = re.compile(r'func\s*\(')
_PARAM_RE = re.compile(r'([A-Za-z_]\w*)\s*(?::[^,=]+)?(?:=[^,]+)?')
_EXTENDS_RE = re.compile(r'^\s*extends\s+(?:"([^"]+)"|([A-Za-z_]\w*))')
_CLASSNAME_RE = re.compile(r'^\s*class_name\s+([A-Za-z_]\w*)')

# `x = `, `x += `, `x[i] = ` ... but never `==`, `<=`, `>=`, `!=`
_ASSIGN_RE = re.compile(r'^\s*([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*(?:\+|-|\*|/|%|\|\||&&)?=(?!=)')
# Mutating a container counts as a write, not a read. The `(?<![.\w])` guard keeps
# `cm._handling.clear()` attributed to `cm`, not to a phantom local `_handling`.
_MUTATE_RE = re.compile(
    r'(?<![.\w])([A-Za-z_]\w*)\s*\.\s*(?:append|append_array|push_back|push_front|insert|erase|'
    r'remove_at|clear|resize|sort|sort_custom|reverse|merge|assign|fill|set|pop_back|pop_front)\s*\('
)

# Declared-and-never-read is intentional for these.
_IGNORE_UNREAD = re.compile(r'^(_|__)?(ready|init|process|physics_process|input|'
                            r'unhandled_input|notification|draw|enter_tree|exit_tree)$')

GD_BUILTINS = {
    'self', 'true', 'false', 'null', 'int', 'float', 'bool', 'String', 'Array',
    'Dictionary', 'Vector2', 'Vector3', 'Vector4', 'Color', 'Transform2D', 'Transform3D',
    'Basis', 'Quaternion', 'AABB', 'Plane', 'Rect2', 'Rect2i', 'Vector2i', 'Vector3i',
    'Vector4i', 'NodePath', 'RID', 'Callable', 'Signal', 'StringName', 'PackedByteArray',
    'PackedInt32Array', 'PackedInt64Array', 'PackedFloat32Array', 'PackedFloat64Array',
    'PackedStringArray', 'PackedVector2Array', 'PackedVector3Array', 'PackedColorArray',
    'if', 'elif', 'else', 'for', 'while', 'match', 'break', 'continue', 'return',
    'pass', 'func', 'var', 'const', 'enum', 'class', 'class_name', 'extends', 'static',
    'signal', 'await', 'yield', 'assert', 'breakpoint', 'preload', 'load', 'is', 'in',
    'as', 'not', 'and', 'or', 'super', 'range', 'print', 'printerr', 'push_error',
    'push_warning', 'str', 'len', 'abs', 'absf', 'absi', 'min', 'max', 'minf', 'maxf',
    'mini', 'maxi', 'clamp', 'clampf', 'clampi', 'round', 'roundf', 'floor', 'floorf',
    'ceil', 'ceilf', 'sqrt', 'pow', 'sin', 'cos', 'tan', 'atan', 'atan2', 'lerp',
    'lerpf', 'inverse_lerp', 'remap', 'sign', 'signf', 'signi', 'snapped', 'fmod',
    'fposmod', 'posmod', 'deg_to_rad', 'rad_to_deg', 'is_nan', 'is_inf', 'is_equal_approx',
    'is_zero_approx', 'is_instance_valid', 'weakref', 'typeof', 'type_string', 'randf',
    'randi', 'randf_range', 'randi_range', 'randomize', 'seed', 'hash', 'instance_from_id',
    'get_tree', 'get_node', 'get_node_or_null', 'find_child', 'add_child', 'queue_free',
    'set_process', 'set_physics_process', 'emit_signal', 'connect', 'disconnect',
    'has_method', 'has_signal', 'call', 'call_deferred', 'callv', 'bind', 'unbind',
    'duplicate', 'new', 'free', 'notification', 'to_string', 'Time', 'OS', 'Engine',
    'Input', 'ProjectSettings', 'ResourceLoader', 'ResourceSaver', 'FileAccess',
    'DirAccess', 'JSON', 'Geometry3D', 'Geometry2D', 'PhysicsServer3D', 'RenderingServer',
    'INF', 'NAN', 'PI', 'TAU', 'void',
}


def strip_noise(text: str) -> str:
    """Blank out strings and comments, preserving line count and column offsets.

    Scans char-by-char PER LINE and resets quote state at every newline. A regex
    cannot do this safely: `[^"\\]` and `[^'\\]` both match newline, so an
    apostrophe in a prose comment ("the bale's OWN meshes") opens a match that
    runs to the next apostrophe many lines later and eats the newlines between —
    which silently shifted every reported line number by ~56. Measured, not guessed.
    """
    out_lines = []
    for line in text.split('\n'):
        buf = []
        quote = ''          # '' | '"' | "'"
        escaped = False
        for ch in line:
            if quote:
                buf.append(' ')
                if escaped:
                    escaped = False
                elif ch == '\\':
                    escaped = True
                elif ch == quote:
                    quote = ''
            elif ch in '"\'':
                quote = ch
                buf.append(' ')
            elif ch == '#':
                buf.append(' ' * (len(line) - len(buf)))
                break
            else:
                buf.append(ch)
        out_lines.append(''.join(buf))
    return '\n'.join(out_lines)


def scan_file(path: str) -> dict:
    """Own declarations + extends target for one file. No cross-file resolution yet."""
    try:
        raw = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return {}
    src = strip_noise(raw)
    lines = src.split('\n')

    declared: dict[str, int] = {}
    class_name = None
    extends = None

    # `extends`/`class_name` are read from the RAW text: strip_noise() blanks string
    # literals, which would erase the quoted path in `extends "res://…/Base.gd"`
    # and silently break every inheritance lookup.
    for line in raw.split('\n'):
        if extends is None:
            e = _EXTENDS_RE.match(line)
            if e:
                extends = e.group(1) or e.group(2)
        c = _CLASSNAME_RE.match(line)
        if c:
            class_name = c.group(1)
        if extends and class_name:
            break

    for i, line in enumerate(lines, 1):
        # `var W := size.x; var H := size.y; var _D := size.z` packs three
        # declarations onto one line — match each `;`-separated statement, not
        # just the one anchored at the start of the line.
        indent = line[:len(line) - len(line.lstrip())]
        for stmt in ([line] if ';' not in line
                     else [line] + [indent + s.strip() for s in line.split(';')]):
            for pat in _DECL_PATTERNS:
                m = pat.match(stmt)
                if m:
                    declared.setdefault(m.group(1), i)

    # Function/lambda parameters — signatures may WRAP across lines, so accumulate
    # until the parens balance. The repo's own lint skips these ("86 multi-line
    # signature(s) not checked"), which is exactly where `_result`/`_headers` hide.
    i = 0
    while i < len(lines):
        line = lines[i]
        if _FUNC_OPEN_RE.match(line) or _LAMBDA_OPEN_RE.search(line):
            start = i
            buf = line[line.find('(', line.find('func')):]
            depth = buf.count('(') - buf.count(')')
            while depth > 0 and i + 1 < len(lines):
                i += 1
                buf += ' ' + lines[i]
                depth = buf.count('(') - buf.count(')')
            inner = buf[1:buf.rfind(')')] if ')' in buf else buf[1:]
            for pm in _PARAM_RE.finditer(inner):
                declared.setdefault(pm.group(1), start + 1)
        i += 1

    return dict(path=path, lines=lines, declared=declared,
                class_name=class_name, extends=extends,
                spec_anchors='audit: spec-anchors' in raw)


def analyse(scan: dict, inherited: set) -> list[dict]:
    path, lines = scan['path'], scan['lines']
    declared = scan['declared']

    writes: dict[str, list[int]] = defaultdict(list)
    reads: dict[str, list[int]] = defaultdict(list)

    for i, line in enumerate(lines, 1):
        if not line.strip():
            continue
        write_here = set()
        a = _ASSIGN_RE.match(line)
        if a:
            write_here.add(a.group(1))
        for m in _MUTATE_RE.finditer(line):
            write_here.add(m.group(1))

        # Names reached via `.` belong to another object — never to this file.
        dotted = {m.group(1) for m in _DOTTED_RE.finditer(line)}
        # ...except the receiver of a mutating call, which we just credited as a write.
        for name in write_here:
            dotted.discard(name)

        for m in _IDENT_RE.finditer(line):
            name = m.group(0)
            if name in GD_BUILTINS or name in dotted:
                continue
            # Skip the declaration keyword's own target on its declaring line.
            if name in write_here:
                writes[name].append(i)
            else:
                reads[name].append(i)

    findings = []
    for name in sorted(set(list(writes) + list(reads) + list(declared))):
        if not name.startswith('_') or name == '_':
            continue  # private convention keeps this sound; publics resolve cross-file
                      # bare `_` is GDScript's discard identifier, never a real symbol
        decl = declared.get(name)
        w, r = writes.get(name, []), reads.get(name, [])
        total = len(w) + len(r)

        if decl is None:
            if name in inherited:
                continue  # declared by a base class up the `extends` chain
            # Used but never declared here or in any base -> GDScript parse error.
            findings.append(dict(file=path, name=name, verdict='UNDECLARED',
                                 line=sorted(w + r)[0], occurrences=total,
                                 detail='used but never declared in this file or any base'))
        elif _IGNORE_UNREAD.match(name):
            continue
        elif not r and w:
            findings.append(dict(file=path, name=name, verdict='WRITE_ONLY',
                                 line=decl, occurrences=total,
                                 detail=f'written at {w} but never read'))
        elif total == 0 or (decl and not w and not r):
            findings.append(dict(file=path, name=name, verdict='DEAD',
                                 line=decl, occurrences=total,
                                 detail='declared, never mentioned again'))
    return findings


def find_project(root: str) -> str:
    """The directory holding project.godot, at or above `root`: what res:// means.

    This used to default to '.', the CURRENT directory, which is right only when the
    tool is started from inside the tree it scans. Measured 2026-09-25: run.sh
    started from another worktree with PROJ=<tree> resolved every
    `extends "res://…/HmiScreenBase.gd"` into the wrong tree, lost the inherited
    members and reported 38 parse-breaking symbols in L3CUnitScreen.gd /
    WashingScope.gd (0 from inside the tree). Started from another drive it
    crashed in os.path.relpath. No project.godot is an error, not a silent
    fall-back to the cwd, since that fall-back is what hid this.
    """
    d = os.path.abspath(root)
    while True:
        if os.path.isfile(os.path.join(d, 'project.godot')):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            sys.exit(f'[symbol_flow] no project.godot at or above --root {root!r}; '
                     f'pass --project <the directory res:// means>')
        d = parent


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='src')
    ap.add_argument('--project', default=None,
                    help='project root that res:// resolves to (default: the nearest '
                         'directory at or above --root that holds project.godot)')
    ap.add_argument('--json')
    ap.add_argument('--all', action='store_true',
                    help='include WRITE_ONLY/DEAD (default: only parse-breaking UNDECLARED)')
    args = ap.parse_args()
    args.project = os.path.abspath(args.project) if args.project else find_project(args.root)

    files = []
    for dirpath, _, names in os.walk(args.root):
        files += [os.path.join(dirpath, n) for n in names if n.endswith('.gd')]

    # Pass 1 — scan every file for its own declarations and its `extends` target.
    scans = {}
    for f in sorted(files):
        s = scan_file(f)
        if s:
            scans[os.path.abspath(f)] = s

    by_class = {s['class_name']: p for p, s in scans.items() if s['class_name']}

    def resolve(path: str, seen: frozenset = frozenset()) -> set:
        """Every symbol visible from base classes, walking the extends chain."""
        s = scans.get(path)
        if not s or not s['extends'] or path in seen:
            return set()
        tgt = s['extends']
        base = None
        if tgt.startswith('res://'):
            base = os.path.abspath(os.path.join(args.project, tgt[len('res://'):]))
        elif tgt in by_class:
            base = by_class[tgt]
        if base is None or base not in scans:
            return set()   # engine class (Node3D, Control, …) — members unknown
        return set(scans[base]['declared']) | resolve(base, seen | {path})

    # Pass 2 — judge each file with its inherited surface in hand.
    all_findings = []
    for p in sorted(scans):
        all_findings += analyse(scans[p], resolve(p))

    # Pass 3 — repo-wide dead constants. A `const` is referenced either bare
    # in-file or as `ClassName.CONST` elsewhere, so a whole-repo count of 1 means
    # nothing but the declaration mentions it. This is how OUTPUT_KG_PER_FILL was
    # found: the constant behind a fixed mass-MINTING bug, left behind unused.
    corpus = defaultdict(int)
    for s in scans.values():
        for line in s['lines']:
            for m in _IDENT_RE.finditer(line):
                corpus[m.group(0)] += 1

    for p, s in sorted(scans.items()):
        # Opt-out for files that deliberately record operator/plant figures which
        # nothing consumes YET (ProcessModel's training-binder anchors). Those are
        # captured knowledge, not dead code — flagging them buries real findings.
        if s.get('spec_anchors'):
            continue
        for i, line in enumerate(s['lines'], 1):
            m = re.match(r'^\s*const\s+([A-Z][A-Z0-9_]*)', line)
            if m and corpus[m.group(1)] == 1:
                all_findings.append(dict(
                    file=os.path.relpath(p, args.project), name=m.group(1),
                    verdict='DEAD_CONST', line=i, occurrences=1,
                    detail='declared once, referenced nowhere in the repo'))

    hard = [f for f in all_findings if f['verdict'] == 'UNDECLARED']
    soft = [f for f in all_findings if f['verdict'] != 'UNDECLARED']
    shown = all_findings if args.all else hard

    by_verdict = defaultdict(list)
    for f in shown:
        by_verdict[f['verdict']].append(f)

    for verdict in ('UNDECLARED', 'WRITE_ONLY', 'DEAD', 'DEAD_CONST'):
        group = by_verdict.get(verdict, [])
        if not group:
            continue
        print(f'\n=== {verdict} ({len(group)}) ===')
        for f in group:
            rel = f['file'].replace('\\', '/')
            print(f"  {rel}:{f['line']}  {f['name']}  "
                  f"(occurs {f['occurrences']}x) — {f['detail']}")

    print(f'\n[symbol_flow] {len(files)} files scanned; '
          f'{len(hard)} parse-breaking, {len(soft)} dead/write-only')

    if args.json:
        json.dump(all_findings, open(args.json, 'w'), indent=2)
        print(f'[symbol_flow] wrote {args.json}')

    return 1 if hard else 0


if __name__ == '__main__':
    sys.exit(main())
