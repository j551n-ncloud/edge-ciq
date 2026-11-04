# Sourced by the other scripts. Finds the SDK the Connect IQ SDK Manager
# marked as current.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-edge1030plus}"
CIQ_HOME="$HOME/Library/Application Support/Garmin/ConnectIQ"

if [[ ! -f "$CIQ_HOME/current-sdk.cfg" ]]; then
  echo "No Connect IQ SDK selected. Open SdkManager.app, sign in, install the latest SDK and the Edge 1030 Plus device, then 'Use this SDK'." >&2
  exit 1
fi
SDK="$(tr -d '\n' < "$CIQ_HOME/current-sdk.cfg")"
SDK="${SDK%/}"
KEY="$ROOT/developer_key.der"
if [[ ! -f "$KEY" ]]; then
  echo "Missing $KEY, see README (Signing key)." >&2
  exit 1
fi
