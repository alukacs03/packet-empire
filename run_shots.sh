#!/usr/bin/env bash
# Render every screen to a directory. Silent: PACKET_SHOT mutes Sfx and the
# dummy driver keeps the run off the speakers entirely.
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DIR="${1:?usage: run_shots.sh <outdir>}"
rm -rf "$DIR" && mkdir -p "$DIR"
PACKET_SHOT="$DIR" "$GODOT" --path "$(dirname "$0")" --audio-driver Dummy \
  --quit-after 2000 >/dev/null 2>&1 || true
ls "$DIR"
