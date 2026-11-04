#!/usr/bin/env bash
# Build and run in the simulator: scripts/sim.sh [fuelzone]
source "$(dirname "$0")/env.sh"
APP="${1:-fuelzone}"
"$ROOT/scripts/build.sh" "$APP"
open -a "$SDK/bin/ConnectIQ.app" 2>/dev/null || "$SDK/bin/connectiq" &
sleep 3
OUT="$APP"; [[ "$DEVICE" != edge1030plus ]] && OUT="$APP-$DEVICE"
"$SDK/bin/monkeydo" "$ROOT/bin/$OUT.prg" "$DEVICE"
