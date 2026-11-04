#!/usr/bin/env bash
# Build one app for the Edge 1030 Plus: scripts/build.sh [fuelzone|music|briefing]
source "$(dirname "$0")/env.sh"
APP="${1:-fuelzone}"
mkdir -p "$ROOT/bin"
# The widgets talk to the proxy and need secrets/edge.xml.
if grep -q '\.\./secrets' "$ROOT/$APP/monkey.jungle"; then
  "$ROOT/scripts/secrets.sh"
fi
"$SDK/bin/monkeyc" -d "$DEVICE" -f "$ROOT/$APP/monkey.jungle" -o "$ROOT/bin/$APP.prg" -y "$KEY" -w
echo "built bin/$APP.prg"
