import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Spotify remote, straight to the Spotify Web API through the phone
// (Spotify.mc), laid out like the design canvas at 282x470:
//   header 34 | now playing 150 | prev / play-pause / next 120 |
//   like 84 | up next (the rest); status in the header
// No shuffle/repeat: Spotify disallows toggling them for this account
// (actions.disallows), so the buttons could only ever fail.
// Polls now-playing every 5 s while the widget is on screen.
class MusicView extends WatchUi.View {
    const POLL_MS = 5000;
    // Spotify applies commands asynchronously; read back after this.
    const SETTLE_MS = 1000;
    const GAP = 8;
    // market=from_token drops the per-track country lists, by far the
    // largest part of the answer.
    const PLAYER = "/me/player?market=from_token&additional_types=track";

    // Only what the screen shows, copied out of Spotify's answer:
    // active, playing, title, artist, posMs, lenMs, device, id.
    hidden var _now as Dictionary? = null;
    hidden var _status as String? = "Loading...";
    hidden var _busy as Boolean = false;
    // The play/pause path just sent, to flip it if Spotify says it's
    // already in that state (403); null for other commands.
    hidden var _lastToggle as String? = null;
    // A request is out over Bluetooth; don't stack another one on it (a slow
    // phone link plus the 5 s poll would otherwise queue requests until the
    // Edge rejects them).
    hidden var _inFlight as Boolean = false;
    // When the request in flight went out. A request the phone never
    // answers (Bluetooth link disturbed) would otherwise block every tap
    // with "Busy" until the widget is reopened.
    const STUCK_MS = 15000;
    hidden var _sentAt as Number = 0;
    hidden var _poll as Timer.Timer = new Timer.Timer();
    hidden var _settle as Timer.Timer = new Timer.Timer();
    hidden var _sp as Spotify = new Spotify();
    // Second connection for the liked check and the queue, so the large
    // queue answer never blocks the buttons or the poll.
    hidden var _bg as Spotify = new Spotify();
    hidden var _bgBusy as Boolean = false;
    // Liked state per track id, so it's only asked once per song.
    hidden var _likedId as String? = null;
    hidden var _liked as Boolean? = null;
    // "Title - Artist" of the next track in the queue, asked once per song.
    hidden var _next as String? = null;
    hidden var _queueFor as String? = null;
    // [x, y, w, h, cmd] per button, rebuilt on every draw.
    hidden var _buttons as Array<Array> = [] as Array<Array>;

    function initialize() {
        View.initialize();
        // Last known state, shown at once while the first answer is on its way.
        var c = Application.Storage.getValue("music");
        if (c instanceof Array && c.size() == 4) {
            _now = c[0] instanceof Dictionary ? c[0] as Dictionary : null;
            _likedId = c[1] instanceof String ? c[1] as String : null;
            _queueFor = _likedId;
            _liked = c[2] instanceof Boolean ? c[2] as Boolean : null;
            _next = c[3] instanceof String ? c[3] as String : null;
        }
    }

    hidden function saveCache() as Void {
        Application.Storage.setValue("music", [_now, _likedId, _liked, _next]);
    }

    function onShow() as Void {
        refresh();
        _poll.start(method(:refresh), POLL_MS, true);
    }

    function onHide() as Void {
        _poll.stop();
        _settle.stop();
    }

    // --- Spotify -------------------------------------------------------------

    function refresh() as Void {
        unstick();
        if (!_busy && !_inFlight) {
            _inFlight = true;
            _sentAt = System.getTimer();
            _sp.call(Communications.HTTP_REQUEST_METHOD_GET, PLAYER, null, method(:onPlayer));
        }
    }

    function onPlayer(code as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        _inFlight = false;
        if (code == 200 && data instanceof Dictionary && data["item"] instanceof Dictionary) {
            var was = _now;
            _now = compact(data);
            data = null;
            _status = null;
            var id = (_now as Dictionary)["id"];
            if (id instanceof String && !id.equals(_likedId) && !_bgBusy) {
                // New song: liked state, then up next, on the second line.
                _likedId = id;
                _liked = null;
                _next = null;
                _bgBusy = true;
                _bg.call(Communications.HTTP_REQUEST_METHOD_GET,
                    "/me/library/contains?uris=spotify%3Atrack%3A" + id, null, method(:onLiked));
            }
            if (was == null || was["playing"] != (_now as Dictionary)["playing"]) {
                saveCache();
            }
        } else if (code == 200 || code == 204 || code == 0) {
            // Nothing playing on any device: Spotify answers 204 with an
            // empty body, which arrives as 0 through the iPhone (204 in the
            // simulator). Link problems have their own negative codes.
            _now = {"active" => false};
            _status = null;
        } else {
            _status = Spotify.errorText(code, data);
            System.println("music error " + code + ": " + _status);
        }
        WatchUi.requestUpdate();
    }

    hidden function compact(st as Dictionary) as Dictionary {
        var it = st["item"] as Dictionary;
        var artists = "";
        if (it["artists"] instanceof Array) {
            var a = it["artists"] as Array;
            for (var i = 0; i < a.size(); i++) {
                if (a[i] instanceof Dictionary && (a[i] as Dictionary)["name"] instanceof String) {
                    artists += (artists.length() > 0 ? ", " : "") + (a[i] as Dictionary)["name"];
                }
            }
        }
        var dev = st["device"];
        return {
            "active" => true,
            "playing" => st["is_playing"] == true,
            "title" => it["name"] instanceof String ? it["name"] : "",
            "artist" => artists,
            "posMs" => st["progress_ms"] instanceof Number ? st["progress_ms"] : 0,
            "lenMs" => it["duration_ms"] instanceof Number ? it["duration_ms"] : 0,
            "device" => (dev instanceof Dictionary && dev["name"] instanceof String) ? dev["name"] : null,
            "id" => it["id"]
        };
    }

    // /me/library/contains answers a JSON array: [true] or [false].
    function onLiked(code as Number, data) as Void {
        _bgBusy = false;
        if (code == 200 && data instanceof Array && (data as Array).size() > 0) {
            _liked = (data as Array)[0] == true;
        } else {
            System.println("liked check " + code + ": " + data);
        }
        // Then the next track, once per song (the queue answer is large).
        var id = _likedId;
        if (id != null && !id.equals(_queueFor)) {
            _queueFor = id;
            _bgBusy = true;
            _bg.call(Communications.HTTP_REQUEST_METHOD_GET, "/me/player/queue", null, method(:onQueue));
        }
        saveCache();
        WatchUi.requestUpdate();
    }

    function onQueue(code as Number, data as Dictionary or String or Null) as Void {
        _bgBusy = false;
        _next = null;
        if (code == 200 && data instanceof Dictionary && data["queue"] instanceof Array
                && (data["queue"] as Array).size() > 0 && (data["queue"] as Array)[0] instanceof Dictionary) {
            var t = (data["queue"] as Array)[0] as Dictionary;
            var name = t["name"] instanceof String ? t["name"] as String : "";
            var by = "";
            if (t["artists"] instanceof Array && (t["artists"] as Array).size() > 0
                    && (t["artists"] as Array)[0] instanceof Dictionary) {
                var a = ((t["artists"] as Array)[0] as Dictionary)["name"];
                by = a instanceof String ? " - " + a : "";
            }
            _next = name + by;
        } else {
            System.println("queue " + code);
        }
        data = null;
        saveCache();
        WatchUi.requestUpdate();
    }

    function command(cmd as String) as Void {
        unstick();
        if (_inFlight) {
            _status = "Busy, try again";
            WatchUi.requestUpdate();
            return;
        }
        var now = _now;
        var id = now != null ? now["id"] : null;
        var m = Communications.HTTP_REQUEST_METHOD_PUT;
        var path;
        if (cmd.equals("next") || cmd.equals("previous")) {
            m = Communications.HTTP_REQUEST_METHOD_POST;
            path = "/me/player/" + cmd;
        } else if (cmd.equals("like") || cmd.equals("unlike")) {
            if (!(id instanceof String)) {
                return;
            }
            if (cmd.equals("unlike")) {
                m = Communications.HTTP_REQUEST_METHOD_DELETE;
            }
            path = "/me/library?uris=spotify%3Atrack%3A" + id;
            _liked = cmd.equals("like");
        } else {
            var playing = now != null && now["playing"] == true;
            path = (cmd.equals("toggle") && playing) ? "/me/player/pause" : "/me/player/play";
            if (now != null && now["active"] == true) {
                now["playing"] = !playing;
            }
        }
        _busy = true;
        _inFlight = true;
        _sentAt = System.getTimer();
        _status = "...";
        WatchUi.requestUpdate();
        _lastToggle = path.equals("/me/player/pause") || path.equals("/me/player/play") ? path : null;
        _sp.call(m, path, m == Communications.HTTP_REQUEST_METHOD_DELETE ? null : {}, method(:onCmd));
    }

    function onCmd(code as Number, data as Dictionary or String or Null) as Void {
        _inFlight = false;
        // Pause on a paused player (or play on a playing one) is refused
        // with 403 when the shown state was behind: send the other one.
        var t = _lastToggle;
        if (code == 403 && t != null) {
            _lastToggle = null;
            var other = t.equals("/me/player/pause") ? "/me/player/play" : "/me/player/pause";
            var now = _now;
            if (now != null && now["active"] == true) {
                now["playing"] = other.equals("/me/player/play");
            }
            _inFlight = true;
            _sentAt = System.getTimer();
            _sp.call(Communications.HTTP_REQUEST_METHOD_PUT, other, {}, method(:onCmd));
            return;
        }
        _lastToggle = null;
        // Spotify confirms commands with an empty body, which the Edge
        // reports as -400 (body not JSON); its errors always carry JSON.
        if ((code >= 200 && code < 300) || code == -400) {
            _status = null;
            _settle.start(method(:afterCmd), SETTLE_MS, false);
        } else {
            _busy = false;
            _status = Spotify.errorText(code, data);
            System.println("music cmd " + code + ": " + _status);
            // The optimistic flip was wrong; read the real state.
            _likedId = null;
        }
        WatchUi.requestUpdate();
    }

    // Gives up on a request that's been out longer than STUCK_MS.
    hidden function unstick() as Void {
        if (_inFlight && System.getTimer() - _sentAt > STUCK_MS) {
            System.println("music: no answer after " + STUCK_MS + " ms");
            _inFlight = false;
            _busy = false;
            _status = "No answer from phone";
        }
    }

    function afterCmd() as Void {
        _busy = false;
        refresh();
    }

    // --- Input (from MusicDelegate) ----------------------------------------------

    function tapAt(x as Number, y as Number) as Void {
        for (var i = 0; i < _buttons.size(); i++) {
            var b = _buttons[i];
            if (x >= b[0] && x < b[0] + b[2] && y >= b[1] && y < b[1] + b[3]) {
                command(b[4] as String);
                return;
            }
        }
    }


    // --- Drawing -----------------------------------------------------------------

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var s = h / 470.0;
        var pad = Ui.PAD;
        dc.setColor(Ui.INK, Ui.PAPER);
        dc.clear();
        _buttons = [] as Array<Array>;

        var now = _now;
        var active = now != null && now["active"] == true;

        // Header; a status (error, "...") takes the device's place.
        var hH = (34 * s).toNumber();
        dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, hH / 2, Graphics.FONT_XTINY, "MUSIC", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var st = _status;
        var right = st != null ? st
            : ((now != null && now["device"] instanceof String) ? "Spotify - " + now["device"] : "Spotify");
        dc.setColor(st != null ? Ui.WARN : Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - pad, hH / 2, Graphics.FONT_XTINY, Ui.fit(dc, right, Graphics.FONT_XTINY, w * 2 / 3),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        Ui.hline(dc, hH - 1, w);

        // Now playing
        var y = hH;
        var hN = (150 * s).toNumber();
        var playing = active && now["playing"] == true;
        Ui.label(dc, pad, y + 10, !active ? "NOTHING PLAYING" : (playing ? "PLAYING" : "PAUSED"));
        if (active) {
            var title = now["title"] instanceof String ? now["title"] as String : "";
            var artist = now["artist"] instanceof String ? now["artist"] as String : "";
            var ty = y + 10 + dc.getFontHeight(Graphics.FONT_XTINY) + 4;
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, ty, Graphics.FONT_MEDIUM, Ui.fit(dc, title, Graphics.FONT_MEDIUM, w - 2 * pad), Graphics.TEXT_JUSTIFY_LEFT);
            ty += dc.getFontHeight(Graphics.FONT_MEDIUM);
            dc.drawText(pad, ty, Graphics.FONT_SMALL, Ui.fit(dc, artist, Graphics.FONT_SMALL, w - 2 * pad), Graphics.TEXT_JUSTIFY_LEFT);

            var pos = now["posMs"] instanceof Number ? now["posMs"] as Number : 0;
            var len = now["lenMs"] instanceof Number ? now["lenMs"] as Number : 0;
            var barY = y + hN - 32;
            var barW = w - 2 * pad;
            dc.setColor(Ui.LINE, Ui.LINE);
            dc.fillRectangle(pad, barY, barW, 6);
            if (len > 0) {
                dc.setColor(Ui.INK, Ui.INK);
                dc.fillRectangle(pad, barY, (barW * pos.toFloat() / len).toNumber(), 6);
            }
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, barY + 9, Graphics.FONT_XTINY, Ui.mmss(pos), Graphics.TEXT_JUSTIFY_LEFT);
            dc.drawText(w - pad, barY + 9, Graphics.FONT_XTINY, Ui.mmss(len), Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, y + hN / 2, Graphics.FONT_SMALL, "Start Spotify on the phone", Graphics.TEXT_JUSTIFY_LEFT);
        }
        Ui.hline(dc, y + hN - 1, w);

        // Previous / play-pause / next
        y += hN;
        var hC = (120 * s).toNumber();
        var bw = (w - 2 * pad - 2 * GAP) / 3;
        var bh = hC - 24;
        var by = y + 12;
        button(dc, pad, by, bw, bh, false, Ui.INK, "previous");
        iconSkip(dc, pad + bw / 2, by + bh / 2, false, Ui.INK);
        button(dc, pad + bw + GAP, by, bw, bh, true, Ui.INK, active ? "toggle" : "play");
        if (playing) {
            iconPause(dc, pad + bw + GAP + bw / 2, by + bh / 2, Ui.PAPER);
        } else {
            iconPlay(dc, pad + bw + GAP + bw / 2, by + bh / 2, Ui.PAPER);
        }
        button(dc, pad + 2 * (bw + GAP), by, bw, bh, false, Ui.INK, "next");
        iconSkip(dc, pad + 2 * (bw + GAP) + bw / 2, by + bh / 2, true, Ui.INK);

        // Like, full width
        y += hC;
        var hR = (84 * s).toNumber();
        var liked = active && _liked == true;
        textButton(dc, pad, y, w - 2 * pad, hR - 12, liked, Ui.FUEL, liked ? "unlike" : "like", liked ? "LIKED" : "LIKE");

        // Up next, in the space below
        y += hR;
        Ui.hline(dc, y, w);
        var nx = _next;
        if (active && nx != null) {
            var fh = dc.getFontHeight(Graphics.FONT_XTINY) + 2 + dc.getFontHeight(Graphics.FONT_SMALL);
            var ny = y + (h - y - fh) / 2;
            Ui.label(dc, pad, ny, "UP NEXT");
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, ny + dc.getFontHeight(Graphics.FONT_XTINY) + 2, Graphics.FONT_SMALL,
                Ui.fit(dc, nx, Graphics.FONT_SMALL, w - 2 * pad), Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    hidden function button(dc as Dc, x as Number, y as Number, bw as Number, bh as Number,
                           filled as Boolean, color as Number, cmd as String) as Void {
        if (filled) {
            dc.setColor(color, color);
            dc.fillRectangle(x, y, bw, bh);
        } else {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawRectangle(x + 1, y + 1, bw - 2, bh - 2);
            dc.setPenWidth(1);
        }
        _buttons.add([x, y, bw, bh, cmd]);
    }

    hidden function textButton(dc as Dc, x as Number, y as Number, bw as Number, bh as Number,
                               on as Boolean, onColor as Number, cmd as String, text as String) as Void {
        button(dc, x, y, bw, bh, on, on ? onColor : Ui.LINE, cmd);
        dc.setColor(on ? (onColor == Ui.INK ? Ui.PAPER : Ui.INK) : Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + bw / 2, y + bh / 2, Graphics.FONT_SMALL, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Skip icon: triangle + bar, pointing right for next, left for previous.
    hidden function iconSkip(dc as Dc, cx as Number, cy as Number, forward as Boolean, color as Number) as Void {
        dc.setColor(color, color);
        if (forward) {
            dc.fillPolygon([[cx - 12, cy - 13], [cx - 12, cy + 13], [cx + 7, cy]]);
            dc.fillRectangle(cx + 8, cy - 13, 5, 26);
        } else {
            dc.fillPolygon([[cx + 12, cy - 13], [cx + 12, cy + 13], [cx - 7, cy]]);
            dc.fillRectangle(cx - 13, cy - 13, 5, 26);
        }
    }

    hidden function iconPlay(dc as Dc, cx as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, color);
        dc.fillPolygon([[cx - 10, cy - 16], [cx - 10, cy + 16], [cx + 16, cy]]);
    }

    hidden function iconPause(dc as Dc, cx as Number, cy as Number, color as Number) as Void {
        dc.setColor(color, color);
        dc.fillRectangle(cx - 13, cy - 15, 9, 30);
        dc.fillRectangle(cx + 4, cy - 15, 9, 30);
    }
}
