#!/usr/bin/env bash
# Record the demo film with sound: Godot's movie writer captures every frame
# and the audio mix, ffmpeg turns the AVI into an MP4. Silent: the window is
# placed offscreen and never takes focus.
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:?usage: run_film.sh <out.mp4>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
printf '[display]\nwindow/size/no_focus=true\nwindow/size/initial_position_type=0\nwindow/size/initial_position=Vector2i(3000,3000)\n' > "$HERE/override.cfg"
trap 'rm -f "$HERE/override.cfg"; rm -rf "$WORK"' EXIT
PACKET_FILM="$WORK/frames" "$GODOT" --path "$HERE" --write-movie "$WORK/film.avi" --fixed-fps 30 >/dev/null 2>&1 || true
ffmpeg -y -v error -i "$WORK/film.avi" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart "$OUT"
ls -la "$OUT"
