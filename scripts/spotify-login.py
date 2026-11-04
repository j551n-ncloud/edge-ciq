#!/usr/bin/env python3
"""One-time Spotify login for the Music widget, separate from glance's.

The widget talks to the Spotify Web API itself (through the phone), so it
needs its own refresh token. This runs the authorization code flow against
a local callback and writes secrets-spotify/spotify.xml (gitignored): the
app's id and secret (also as a Basic auth string) and the refresh token,
baked into the music build.

Before the first run, add this redirect URI to the Spotify app
(developer.spotify.com > your app > Settings > Redirect URIs):
    http://127.0.0.1:8888/callback

Client id and secret: $SPOTIFY_CLIENT_ID / $SPOTIFY_CLIENT_SECRET, else
glance's .env next to this repo ($GLANCE_ENV overrides the path).

Run: python3 scripts/spotify-login.py   (opens the browser, waits 5 min)
Revoke later: spotify.com > Account > Apps.
"""
import base64
import json
import os
import secrets
import subprocess
import sys
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = " ".join([
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-library-read",
    "user-library-modify",
])
OUT = ROOT / "secrets-spotify" / "spotify.xml"


def env_value(key: str) -> str:
    if os.environ.get(key):
        return os.environ[key]
    envf = Path(os.environ.get("GLANCE_ENV", ROOT.parent / "glance" / ".env"))
    if envf.exists():
        for line in envf.read_text().splitlines():
            if line.startswith(key + "="):
                return line.split("=", 1)[1].strip().strip("\"'")
    sys.exit(f"No {key} (set it, or add it to {envf}).")


def main() -> None:
    cid = env_value("SPOTIFY_CLIENT_ID")
    secret = env_value("SPOTIFY_CLIENT_SECRET")
    state = secrets.token_urlsafe(16)
    result: dict = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            ok = q.get("state", [""])[0] == state and "code" in q
            if ok:
                result["code"] = q["code"][0]
            else:
                result["error"] = q.get("error", ["state mismatch"])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(("Done, back to the terminal." if ok else "Login failed: " + result["error"]).encode())

        def log_message(self, *args):
            pass

    url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
        "client_id": cid, "response_type": "code", "redirect_uri": REDIRECT,
        "scope": SCOPES, "state": state, "show_dialog": "true",
    })
    srv = HTTPServer(("127.0.0.1", 8888), Handler)
    srv.timeout = 300
    print("Opening the Spotify login in the browser. If it doesn't open:\n" + url)
    subprocess.run(["open", url], check=False)
    srv.handle_request()
    if "code" not in result:
        sys.exit("Login failed: " + result.get("error", "timed out after 5 min"))

    basic = base64.b64encode(f"{cid}:{secret}".encode()).decode()
    req = urllib.request.Request(
        "https://accounts.spotify.com/api/token",
        data=urllib.parse.urlencode({
            "grant_type": "authorization_code", "code": result["code"], "redirect_uri": REDIRECT,
        }).encode(),
        headers={"Authorization": "Basic " + basic,
                 "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req) as r:
        tok = json.load(r)
    if "refresh_token" not in tok:
        sys.exit("No refresh token in Spotify's answer.")

    OUT.parent.mkdir(exist_ok=True)
    os.umask(0o077)
    OUT.write_text(f"""<!-- Written by scripts/spotify-login.py, never commit. -->
<resources>
    <properties>
        <property id="spotifyBasic" type="string">{escape(basic)}</property>
        <property id="spotifyRefresh" type="string">{escape(tok["refresh_token"])}</property>
        <property id="spotifyId" type="string">{escape(cid)}</property>
        <property id="spotifySecret" type="string">{escape(secret)}</property>
    </properties>
</resources>
""")
    print(f"Saved {OUT.relative_to(ROOT)} (scopes: {tok.get('scope', '?')}).")


if __name__ == "__main__":
    main()
