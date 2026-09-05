#!/usr/bin/env bash
# The same scripts, through the game's CLI, headless. Writes out/<node>.game.txt.
set -u
cd "$(dirname "$0")"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
for f in scripts/*.txt; do
  node=$(basename "$f" .txt)
  PACKET_TEST=replay PACKET_REPLAY="$(pwd)/$f" "$GODOT" --headless --path ../.. --quit-after 300 2>/dev/null \
    | sed -n '/^--- replay start/,/^--- replay end/p' | sed '1d;$d' > "out/$node.game.txt"
  echo "$node: $(wc -l < "out/$node.game.txt") lines"
done
