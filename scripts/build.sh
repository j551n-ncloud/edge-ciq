#!/usr/bin/env bash
# Build one app for the Edge 1030 Plus: scripts/build.sh [fuelzone|music|briefing]
# Other device: DEVICE=edge840 scripts/build.sh fuelzone -> bin/fuelzone-edge840.prg
source "$(dirname "$0")/env.sh"
APP="${1:-fuelzone}"
OUT="$APP"
[[ "$DEVICE" != edge1030plus ]] && OUT="$APP-$DEVICE"
mkdir -p "$ROOT/bin"
# The widgets talk to the proxy and need secrets/edge.xml.
if grep -q '\.\./secrets;\|\.\./secrets$' "$ROOT/$APP/monkey.jungle"; then
  "$ROOT/scripts/secrets.sh"
fi
# The music widget's own Spotify login.
if grep -q 'secrets-spotify' "$ROOT/$APP/monkey.jungle" && [[ ! -f "$ROOT/secrets-spotify/spotify.xml" ]]; then
  echo "No Spotify login yet: run python3 scripts/spotify-login.py (README, Widgets)." >&2
  exit 1
fi
"$SDK/bin/monkeyc" -d "$DEVICE" -f "$ROOT/$APP/monkey.jungle" -o "$ROOT/bin/$OUT.prg" -y "$KEY" -w
echo "built bin/$OUT.prg"
