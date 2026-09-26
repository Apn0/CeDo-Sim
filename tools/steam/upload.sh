#!/usr/bin/env bash
# Upload the Steam build (the output of tools/steam/build_windows.sh) with
# SteamPipe. See docs/steam/README.md.
#
#   STEAM_APPID=… STEAM_DEPOTID=… STEAM_USER=… PREVIEW=1 bash tools/steam/upload.sh
#
# Needs a Steamworks app with one Windows depot, steamcmd (from the Steamworks
# SDK: tools/ContentBuilder/builder/steamcmd.exe), and a Steam account that has
# logged in to steamcmd once BY HAND (password + Steam Guard code), so that
# steamcmd holds its cached credentials. This script never takes a password.
#
# PREVIEW=1 (the default) scans and reports what would upload and uploads
# nothing. PREVIEW=0 uploads. BRANCH sets the build live on that beta branch;
# empty sets nothing live (Valve: the default branch can only be set live in
# App Admin).
set -euo pipefail

: "${STEAM_APPID:?set STEAM_APPID (App Admin)}"
: "${STEAM_DEPOTID:?set STEAM_DEPOTID (SteamPipe > Depots)}"
: "${STEAM_USER:?set STEAM_USER (the build account; log in to steamcmd by hand once first)}"
STEAMCMD="${STEAMCMD:-/d/cedo_archive/steam/steamcmd/steamcmd.exe}"
CONTENT="${CONTENT:-/d/cedo_archive/steam/build/windows}"
WORK="${WORK:-/d/cedo_archive/steam}"
BRANCH="${BRANCH:-}"
PREVIEW="${PREVIEW:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DESC="${DESC:-CeDo Simulator $(git -C "$HERE" rev-parse --short HEAD) $(date +%Y-%m-%d)}"

[ -x "$STEAMCMD" ] || { echo "steamcmd not found at $STEAMCMD (set STEAMCMD)"; exit 1; }
for f in CeDoSimulator.exe CeDoSimulator.pck; do
	[ -s "$CONTENT/$f" ] || { echo "no build in $CONTENT ($f missing): run tools/steam/build_windows.sh"; exit 1; }
done

mkdir -p "$WORK/scripts" "$WORK/output"
VDF="$WORK/scripts/app_build_${STEAM_APPID}.vdf"
win() { cygpath -w "$1"; }
sed -e "s|@APPID@|$STEAM_APPID|" -e "s|@DEPOTID@|$STEAM_DEPOTID|" \
	-e "s|@DESC@|$DESC|" -e "s|@BRANCH@|$BRANCH|" -e "s|@PREVIEW@|$PREVIEW|" \
	-e "s|@CONTENT@|$(win "$CONTENT" | sed 's|\\|\\\\|g')\\\\|" \
	-e "s|@OUTPUT@|$(win "$WORK/output" | sed 's|\\|\\\\|g')\\\\|" \
	"$HERE/app_build.vdf.template" > "$VDF"
echo "== $VDF"
cat "$VDF"
echo "== steamcmd (preview=$PREVIEW, setlive='${BRANCH}')"
"$STEAMCMD" +login "$STEAM_USER" +run_app_build "$(win "$VDF")" +quit
