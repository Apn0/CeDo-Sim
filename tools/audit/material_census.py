#!/usr/bin/env python3
"""
material_census.py — follow the material, not the code.

OPERATOR'S FRAMING (2026-08-17): a bale is scanned, wired, cut, clamped, belted,
shredded, magnet-sorted, floated, friction-washed, dried, extruded, filtered,
pelletised. Every stage is input -> modification -> output. Iron wire, aluminium,
LDPE/HDPE/PP all ride along and separate at different stages. So:

    EVERY INPUT HAS AN OUTPUT.

A stage that CONSUMES material but never EMITS is a mass sink — film vanishes.
A stage that EMITS but never CONSUMES is a mass source — film is minted. Both are
invisible in a screenshot and both survive a green test suite, because nothing
downstream knows what it should have received.

This censuses the conserved quantities across every file that touches
MaterialBatch, counts how often each occurs, and flags the asymmetries.

Verdicts
  MINTS     builds a non-empty batch without debiting an upstream reservoir
  SINKS     consumes (split_*) but never emits (add/merge) — material dead-ends
  DROPS_SUB moves mass_kg but ignores water_kg/contaminant_kg — sub-masses lost
  OK        balanced, or a documented boundary (plant intake / reject stream)

Usage:  python tools/audit/material_census.py [--root src] [--json out.json]
"""

from __future__ import annotations

import argparse
import json
import os
import re
from collections import defaultdict

CONSERVED = ['mass_kg', 'volume_m3', 'composition', 'water_kg', 'contaminant_kg']

# How material legitimately moves. Consuming and emitting must both appear in any
# stage that is not a plant boundary.
CONSUME_RE = re.compile(r'\.\s*(split_mass|split_fraction)\s*\(')
EMIT_RE = re.compile(r'\.\s*(add|merge)\s*\(|MaterialBatch\s*\.\s*merge\s*\(')
SIDE_RE = re.compile(r'\.\s*(remove_water|remove_contaminant|add_water|reject_polymer)\s*\(')
# A construction with a literal 0/empty first arg is an empty accumulator, not mass.
CONSTRUCT_RE = re.compile(r'MaterialBatch\s*\.\s*new\s*\(\s*([^,)]*)')
# Debiting an upstream reservoir: `remaining -= draw`, `_throat_kg -= kg_out`, …
DEBIT_RE = re.compile(r'\b\w+\s*-=\s*|\bminf\s*\(|\.\s*split_(?:mass|fraction)\s*\(')

# Documented plant boundaries — material legitimately enters/leaves the world here.
BOUNDARY = {
    'BaleDefs.gd': 'plant intake — bales arrive from outside the fence',
    'MaterialBatch.gd': 'the accounting primitive itself',
    # QaLab.gd:33-40 — non-destructive by default: submit_sample() grades a
    # duplicate_batch(), not the live one, so the plant ledger never sees the
    # sample. A lab bench consuming its own sample is a boundary, not a sink.
    'QaLab.gd': 'QA bench sample — grades a duplicate, never debited from the plant ledger',
}
# Test fixtures construct batches as literal input (BaleDefs.gd's boundary,
# applied per-file) rather than moving real plant mass — same as the plant
# intake case above, just under src/tests/ instead of a single autoload.
TEST_DIR_MARKER = os.sep + 'tests' + os.sep


def strip_comments(text: str) -> list[str]:
    out = []
    for line in text.split('\n'):
        q, esc, buf = '', False, []
        for ch in line:
            if q:
                buf.append(' ')
                if esc:
                    esc = False
                elif ch == '\\':
                    esc = True
                elif ch == q:
                    q = ''
            elif ch in '"\'':
                q = ch
                buf.append(' ')
            elif ch == '#':
                break
            else:
                buf.append(ch)
        out.append(''.join(buf))
    return out


def census(path: str) -> dict | None:
    try:
        raw = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return None
    if 'MaterialBatch' not in raw:
        return None

    lines = strip_comments(raw)
    body = '\n'.join(lines)

    counts = {q: len(re.findall(r'\b%s\b' % q, body)) for q in CONSERVED}
    consumes = len(CONSUME_RE.findall(body))
    emits = len(EMIT_RE.findall(body))
    sides = len(SIDE_RE.findall(body))

    # Constructions carrying real mass (first arg is not a literal 0).
    mass_constructs = []
    for i, line in enumerate(lines, 1):
        for m in CONSTRUCT_RE.finditer(line):
            arg = m.group(1).strip()
            if arg in ('', '0', '0.0'):
                continue          # empty accumulator — no mass claimed
            mass_constructs.append((i, arg))

    return dict(path=path, counts=counts, consumes=consumes, emits=emits,
                sides=sides, mass_constructs=mass_constructs, lines=lines)


def judge(c: dict) -> list[dict]:
    base = os.path.basename(c['path'])
    findings = []
    if base in BOUNDARY or TEST_DIR_MARKER in c['path']:
        return findings

    # MINTS — a batch is built with mass, but nothing in the file debits a source.
    if c['mass_constructs']:
        body = '\n'.join(c['lines'])
        if not DEBIT_RE.search(body):
            for ln, arg in c['mass_constructs']:
                findings.append(dict(
                    file=c['path'], line=ln, verdict='MINTS',
                    detail=f'MaterialBatch.new({arg}…) with no debit anywhere in file'))

    # SINKS — consumes material but never hands any onward.
    if c['consumes'] and not c['emits'] and not c['sides']:
        findings.append(dict(
            file=c['path'], line=0, verdict='SINKS',
            detail=f"{c['consumes']} split_*() call(s), 0 add/merge and 0 side-stream — "
                   'material is consumed and never re-emitted'))

    # DROPS_SUB — moves total mass but never touches the sub-masses riding inside it.
    if c['counts']['mass_kg'] and (c['consumes'] or c['emits']):
        if not c['counts']['water_kg'] and not c['counts']['contaminant_kg'] and not c['sides']:
            findings.append(dict(
                file=c['path'], line=0, verdict='DROPS_SUB',
                detail=f"mass_kg x{c['counts']['mass_kg']} but water_kg x0 / contaminant_kg x0 — "
                       'wet+dirty sub-masses are not carried through this stage'))
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='src')
    ap.add_argument('--json')
    args = ap.parse_args()

    files = []
    for dirpath, _, names in os.walk(args.root):
        files += [os.path.join(dirpath, n) for n in names if n.endswith('.gd')]

    stages, findings = [], []
    for f in sorted(files):
        c = census(f)
        if c:
            stages.append(c)
            findings += judge(c)

    print(f'{"stage":<44}{"mass":>5}{"vol":>5}{"comp":>5}{"H2O":>5}{"dirt":>5}'
          f'{"cons":>6}{"emit":>6}{"side":>6}')
    print('-' * 92)
    for c in sorted(stages, key=lambda s: -sum(s['counts'].values())):
        n = os.path.basename(c['path'])[:43]
        k = c['counts']
        print(f"{n:<44}{k['mass_kg']:>5}{k['volume_m3']:>5}{k['composition']:>5}"
              f"{k['water_kg']:>5}{k['contaminant_kg']:>5}"
              f"{c['consumes']:>6}{c['emits']:>6}{c['sides']:>6}")

    by_v = defaultdict(list)
    for f in findings:
        by_v[f['verdict']].append(f)
    for v in ('MINTS', 'SINKS', 'DROPS_SUB'):
        for f in by_v.get(v, []):
            loc = f"{f['file'].replace(os.sep, '/')}" + (f":{f['line']}" if f['line'] else '')
            print(f"\n  [{v}] {loc}\n         {f['detail']}")

    print(f'\n[material_census] {len(stages)} material-touching files; {len(findings)} flagged')
    if args.json:
        json.dump(findings, open(args.json, 'w'), indent=2)
    return 1 if findings else 0


if __name__ == '__main__':
    raise SystemExit(main())
