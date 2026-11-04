#!/usr/bin/env bash
# Writes secrets/edge.xml (gitignored): the proxy base URL and the narrow
# EDGE_API_TOKEN the widgets send. Token from $EDGE_API_TOKEN, else from
# glance's .env next to this repo (override the path with $GLANCE_ENV).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVF="${GLANCE_ENV:-$ROOT/../glance/.env}"
TOKEN="${EDGE_API_TOKEN:-}"
if [[ -z "$TOKEN" && -f "$ENVF" ]]; then
  TOKEN="$(grep '^EDGE_API_TOKEN=' "$ENVF" | cut -d= -f2- | tr -d "\"'")"
fi
BASE="${EDGE_BASE_URL:-https://dash.j551n.com}"
if [[ -z "$TOKEN" ]]; then
  echo "No EDGE_API_TOKEN (set it, or add it to $ENVF)." >&2
  exit 1
fi
mkdir -p "$ROOT/secrets"
umask 077
cat > "$ROOT/secrets/edge.xml" <<EOF
<resources>
    <properties>
        <property id="baseUrl" type="string">$BASE</property>
        <property id="apiToken" type="string">$TOKEN</property>
    </properties>
</resources>
EOF
