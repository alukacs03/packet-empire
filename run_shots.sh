#!/usr/bin/env bash
# Render every screen to a directory. Silent: PACKET_SHOT mutes Sfx and the
# dummy driver keeps the run off the speakers entirely.
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DIR="${1:?usage: run_shots.sh <outdir>}"
# each run is ~35MB of PNGs; keeping every one of them fills a disk quietly
find "$(dirname "$DIR")" -maxdepth 1 -name 'shots*' -type d -mmin +120 -exec rm -rf {} + 2>/dev/null || true
rm -rf "$DIR" && mkdir -p "$DIR"
# Keep the window off the user's screen and out of their focus: a no_focus
# window placed offscreen still renders, so the capture works and nothing
# steals the keyboard. override.cfg is read by Godot on top of project.godot.
HERE="$(cd "$(dirname "$0")" && pwd)"
printf '[display]\nwindow/size/no_focus=true\nwindow/size/initial_position_type=0\nwindow/size/initial_position=Vector2i(3000,3000)\n' > "$HERE/override.cfg"
trap 'rm -f "$HERE/override.cfg"' EXIT
PACKET_SHOT="$DIR" "$GODOT" --path "$(dirname "$0")" --audio-driver Dummy \
  --quit-after 2000 >/dev/null 2>&1 || true
ls "$DIR"
