#!/usr/bin/env bash
# Record a showcase video of the game running. Godot writes one JPEG per
# rendered frame with a caption strip; ffmpeg turns them into an mp4. Silent:
# the film harness mutes Sfx and the dummy driver keeps it off the speakers.
#
#   ./run_film.sh /tmp/film out.mp4
set -euo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DIR="${1:?usage: run_film.sh <frame-dir> [out.mp4]}"
OUT="${2:-packet-empire.mp4}"
rm -rf "$DIR" && mkdir -p "$DIR"
# Keep the window off the user's screen and out of their focus: a no_focus
# window placed offscreen still renders, so the capture works and nothing
# steals the keyboard. override.cfg is read by Godot on top of project.godot.
HERE="$(cd "$(dirname "$0")" && pwd)"
printf '[display]\nwindow/size/no_focus=true\nwindow/size/initial_position_type=0\nwindow/size/initial_position=Vector2i(3000,3000)\n' > "$HERE/override.cfg"
trap 'rm -f "$HERE/override.cfg"' EXIT
# ~1700 frames at 720p is about 250MB of stills; the frame directory is
# temporary and is removed at the end.
PACKET_FILM="$DIR" "$GODOT" --path "$(dirname "$0")" --audio-driver Dummy
ffmpeg -y -loglevel error -framerate 30 -i "$DIR/f%05d.jpg" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart "$OUT"
rm -rf "$DIR"
echo "wrote $OUT"
