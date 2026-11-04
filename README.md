# edge-ciq

Connect IQ apps for the Garmin Edge 1030 Plus. Design (screens, layout spec):
the "Edge 1030 Plus Interface" canvas on claude.ai.

![The four screens: Fuel + Zone ride page, gel alert, Ride Brief and Music widgets](docs/overview.png)

_Renders of the design canvas (282 x 470, the Edge 1030 Plus screen), with sample data. Single screens in [`docs/`](docs/)._

| App | Type | Status |
|---|---|---|
| `fuelzone/` | data field, full screen | ride screen, gel alert, bell; on the Edge |
| `briefing/` | widget "Ride Brief" | on the Edge (enable it in the widget loop) |
| `music/` | widget "Music" | on the Edge (enable it in the widget loop) |
| `shared/` | code | `bell/` for the ride screen, `widget/` (proxy calls, drawing) for the widgets |

## fuelzone

One full-screen data field (put it on a 1-field data page):

- **Heart rate** with zone pill and 5-part zone bar. Zones come from the
  `hrZones` setting (default: the Strava zones 127/158/174/189), empty falls
  back to the device's cycling HR zones.
- **Ascent (or 3 s power), speed, cadence, ride time.** The first slot shows
  total ascent until a power meter sends data, then switches to 3 s power.
- **Fuel:** countdown to the next gel, carbs eaten vs target so far, dots per
  gel. One gel every `gelIntervalMin` (25) of timer time, counted from the
  last gel. No alerts when `plannedMinutes` is set and under 60.
- **Gel alert:** full-screen takeover plus a tone when a gel is due. Nothing
  to press: it counts down 3 s (the ride screen shows the seconds) and then
  logs the gel by itself, with a short confirmation tone.
- **Bell:** press Lap twice within 2.5 s. Plays a ding-ding through the
  speaker. Lap does nothing else in this field. Both
  presses still create laps in the FIT file (data fields get no touch input,
  Lap is the only key they see). A "BELL" banner shows when it
  triggers. Not a legal replacement for a mechanical bell (StVZO §64a), and silent if device tones are off.
- **FIT fields** `carbs` (g) and `gels` on the session, so they show on the
  ride in Garmin Connect.
- **Live ride:** every 30 s the field saves a snapshot (position, distance,
  ride time, HR and zone, gels, carbs, ascent, speed); a background sender
  (`LiveService`, 5 min minimum interval) posts the latest one through the phone
  to glance `/garmin-api/live`. glance alerts started / stopped 15+ min /
  finished in Telegram, claude-telegram reads it via `get_live_ride`. About
  60 KB per hour. Setting `liveTracking`.
- Gel state survives an app restart mid-ride (`Application.Storage`), and is
  cleared when the ride is saved or discarded.

Settings (Garmin Connect app → device → Connect IQ apps → Fuel + Zone; sideloaded
apps may not show them, then change the defaults in `resources/settings/properties.xml`):
`gelIntervalMin`, `gelGrams`, `carbsPerHour`, `plannedGels`,
`plannedMinutes`, `hrZones`, `bellOnDoubleLap`, `liveTracking`.

## Widgets

Swipe down on the Edge to reach them. Sideloaded widgets start switched off:
enable them under Menu > Settings > System > Widgets. They call the glance proxy through
the phone (Garmin Connect app over Bluetooth, the phone's mobile data), so no
WiFi on the bike; without the phone the brief shows the last saved copy.

- **Ride Brief:** readiness ring and reasons, weather and dark-from, packing
  list, gel plan, bike status (`GET /garmin-api/edge-brief`). Tap refreshes.
- **Music:** Spotify previous / play-pause / next and like
  (`/music-api/now`, `POST /music-api/cmd`), polls every 5 s while shown. No
  volume (the iPhone has no remote volume), no shuffle/repeat (Spotify
  disallows toggling them for this account).

Both send the narrow `EDGE_API_TOKEN` (only valid for those routes), baked in
at build time: `scripts/secrets.sh` writes it from `../glance/.env` (or
`$EDGE_API_TOKEN`) to the gitignored `secrets/edge.xml`. `scripts/build.sh`
runs it for the widgets automatically.

## Setup

1. Install the SDK Manager: `brew install --cask connectiq-sdk-manager`.
2. Open `SdkManager.app`, sign in with the Garmin account, install the latest
   SDK, click "Use this SDK", and under Devices install **Edge 1030 Plus**.
3. Signing key (once, kept out of git):

   ```bash
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
   ```

Optional: the "Monkey C" VS Code extension for editing and debugging.

## Build, simulate, test

```bash
scripts/build.sh fuelzone   # bin/fuelzone.prg (also: music, briefing)
scripts/sim.sh fuelzone     # build + run in the simulator
scripts/test.sh fuelzone    # (:test) unit tests in the simulator
```

In the simulator: Simulation → Activity Data to feed HR/power/speed, and
Simulation → Data Fields → Layout 1 field for the full-screen layout.

## Install on the Edge

Plug the Edge in over USB and copy `bin/<app>.prg` to `GARMIN/Apps/` with
`cp -X` (macOS `._` files make the Edge log signature errors).
Unplug, then add the field to a data page of the ride profile.

Climbs: none here on purpose, Garmin's ClimbPro covers them on routes.
