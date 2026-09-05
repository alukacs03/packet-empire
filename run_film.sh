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
# the soundtrack is composed offline and mixed under the game's own interface
# sounds (the room's hum is muted while filming: on tape it is only a drone)
python3 "$HERE/tools/film/music.py" "$WORK/music.wav" 80
ffmpeg -y -v error -i "$WORK/film.avi" -i "$WORK/music.wav" \
  -filter_complex "[1:a]volume=0.55,afade=t=out:st=52:d=4.5[m];[0:a][m]amix=inputs=2:duration=first:dropout_transition=0,alimiter=limit=0.95[a]" \
  -map 0:v -map "[a]" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$OUT"
ls -la "$OUT"
