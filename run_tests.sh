#!/usr/bin/env bash
# Run the headless suite. Exit 0 only if every check passed and nothing errored.
set -uo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT=$(PACKET_TEST=1 "$GODOT" --headless --path "$(dirname "$0")" --quit-after 1500 2>&1)
RC=$?
echo "$OUT" | grep -E "^(FAIL|SCRIPT ERROR|ERROR)" | head -20
PASSES=$(echo "$OUT" | grep -c "^PASS")
# grep -q exits on the first match, which SIGPIPEs the echo and, under
# pipefail, made this check fail at random. Match on the string instead.
if [[ "$OUT" != *"---- 0 failures"* ]]; then
  echo "SUITE FAILED (or did not run to completion)"; exit 1
fi
# the UI smoke pass runs after the summary line above and reports separately;
# without this a failing smoke check printed FAIL and the run still said green
if [[ "$OUT" != *"---- 0 smoke failures"* ]]; then
  echo "UI SMOKE FAILED (or did not run to completion)"; exit 1
fi
if [ "$RC" -ne 0 ]; then
  echo "GODOT EXITED $RC"; exit 1
fi
if [[ "$OUT" == *"SCRIPT ERROR"* ]]; then
  echo "SCRIPT ERRORS present"; exit 1
fi
echo "all green: $PASSES checks"
