#!/usr/bin/env bash
# SCRIPT ERROR census — fail every log of THIS harness run that carries a
# `SCRIPT ERROR` line.
#
#   bash tools/regression/script_error_census.sh <out_dir> <run_start_marker>
#
# WHY. A GDScript runtime error aborts only the function it hits. A suite that
# awaits its phases (`await _phase_d()`) then carries on as if the phase were
# done, reaches its verdict, and prints PASS without that phase's checks.
# Measured 2026-09-25: with C: full, test_macro_edges_reload's phase-D save
# failed, the typed read that followed was a runtime error, and the suite
# printed `Result: PASS (51 ok, 0 fail)` instead of 60 — and run.sh, which
# reads only each step's verdict line, would have passed it. Every such abort
# prints a `SCRIPT ERROR:` line, so this census catches it in ANY suite, not
# only in the ones that count their own phases.
#
# WHICH LOGS. Every `*.log` in <out_dir> newer than <run_start_marker>, which
# run.sh touches before its first step. The out dir is never cleared, so an
# mtime filter (not a name list) is what keeps stale logs out.
#
# ONE EXCEPTION, by name: parse_sweep.log. The sweep compiles every file of
# the tree in one boot, so a file that needs an autoload reports "Identifier
# not found" there by construction (its header explains the
# ERR_COMPILATION_FAILED noise); it has its own detector (^RESULT: PASS),
# gated earlier in run.sh. Nothing else is excused: a suite whose log carries
# noise is fixed, not listed (test_route_goal_clearance was, 2026-09-25).
#
# Exit 0: every log read is clean. Exit 1: a log carries SCRIPT ERROR lines,
# or no log was newer than the marker (a census that read nothing proves
# nothing). Exit 2: bad arguments.
set -u
out_dir="${1:-}"
marker="${2:-}"
if [ -z "$out_dir" ] || [ -z "$marker" ] || [ ! -d "$out_dir" ] || [ ! -e "$marker" ]; then
	echo "usage: script_error_census.sh <out_dir> <run_start_marker>  (both must exist)" >&2
	exit 2
fi
EXCUSED="parse_sweep.log"

read_n=0
bad=0
excused=0
while IFS= read -r f; do
	name="$(basename "$f")"
	read_n=$((read_n + 1))
	if [ "$name" = "$EXCUSED" ]; then
		excused=$((excused + 1))
		continue
	fi
	# Logs from Windows Godot end lines in \r\n; strip before anchoring.
	n="$(tr -d '\r' < "$f" | grep -ac '^SCRIPT ERROR' || true)"
	if [ "${n:-0}" -gt 0 ]; then
		bad=$((bad + 1))
		first="$(tr -d '\r' < "$f" | grep -a -m1 -A1 '^SCRIPT ERROR' | tr '\n' ' ' | cut -c1-240)"
		echo "FAIL  : $name carries $n SCRIPT ERROR line(s) — a runtime error aborts the function it hits, and a suite can print PASS after it. First: $first"
	fi
done < <(find "$out_dir" -maxdepth 1 -type f -name '*.log' -newer "$marker" | sort)

echo "script error census: $read_n log(s) of this run read, $bad with SCRIPT ERROR lines, $excused excused ($EXCUSED)"
if [ "$read_n" -eq 0 ]; then
	echo "FAIL  : no log is newer than $marker — the census read nothing"
	exit 1
fi
[ "$bad" -eq 0 ] || exit 1
exit 0
