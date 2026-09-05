#!/usr/bin/env bash
# Run every scripts/<node>.txt on the live containerlab node of that name and
# keep the transcript in out/<node>.real.txt. Needs sshpass.
set -u
cd "$(dirname "$0")"
LAB=packet-lab
for f in scripts/*.txt; do
  node=$(basename "$f" .txt)
  host="clab-$LAB-$node"
  out="out/$node.real.txt"
  : > "$out"
  case "$node" in
    e1) user=admin; pass=admin ;;
    *)  user=admin; pass="" ;;
  esac
  grep -v '^#' "$f" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "> $line" >> "$out"
    case "$node" in
      h*) docker exec "$host" sh -c "$line" >> "$out" 2>&1 ;;  # plain linux nodes have no sshd
      *)  sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$user@$host" "$line" >> "$out" 2>&1 ;;
    esac
  done
  echo "$node: $(wc -l < "$out") lines"
done
