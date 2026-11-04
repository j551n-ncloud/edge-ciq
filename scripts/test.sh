#!/usr/bin/env bash
# Unit tests ((:test) functions) in the simulator: scripts/test.sh [fuelzone]
source "$(dirname "$0")/env.sh"
APP="${1:-fuelzone}"
mkdir -p "$ROOT/bin"
"$SDK/bin/monkeyc" -d "$DEVICE" -f "$ROOT/$APP/monkey.jungle" -o "$ROOT/bin/$APP-test.prg" -y "$KEY" -w --unit-test
open -a "$SDK/bin/ConnectIQ.app" 2>/dev/null || "$SDK/bin/connectiq" &
sleep 3
"$SDK/bin/monkeydo" "$ROOT/bin/$APP-test.prg" "$DEVICE" -t
