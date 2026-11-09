#!/bin/bash
# Checks YouTube's answers for the iPhone's own YouTube route (owner, 2026-11-09: the server's copy first, else the
# iPhone gets it from YouTube itself, like Android/NewPipe). Runs one probe from scripts/yt/ on ribs02 (same home
# internet as the phones), with python3 and nothing else. The only command the owner's permission rule allows for
# this work: Bash(scripts/yt-check.sh:*).
#   scripts/yt-check.sh NAME [ARGS…]     runs scripts/yt/NAME.py on ribs02
set -euo pipefail
cd "$(dirname "$0")/.."
name=${1:?usage: scripts/yt-check.sh NAME [ARGS…]}; shift
[[ "$name" =~ ^[a-z0-9-]+$ ]] || { echo "bad probe name"; exit 2; }
f=scripts/yt/$name.py
[ -f "$f" ] || { echo "no $f"; exit 2; }
scp -q "$f" "ribs:/srv/build/ios/yt-$name.py" 2>/dev/null
ssh ribs "python3 /srv/build/ios/yt-$name.py $(printf '%q ' "$@"); rm -f /srv/build/ios/yt-$name.py" 2>&1 \
    | grep -v -e '^---' -e 'Radiance Innovation' -e AUTHORIZED -e 'Personal data' -e 'Questions:' || true
