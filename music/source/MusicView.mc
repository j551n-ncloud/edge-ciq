import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Spotify remote through the glance proxy (/music-api/now and /cmd), laid out
// like the design canvas at 282x470:
//   header 34 | now playing 150 | prev / play-pause / next 120 |
//   like 84 | footer (hint or status)
// No shuffle/repeat: Spotify disallows toggling them for this account
// (actions.disallows), so the buttons could only ever fail.
// Polls now-playing every 5 s while the widget is on screen.
class MusicView extends WatchUi.View {
    const POLL_MS = 5000;
    const BELL_MS = 1500;
    const GAP = 8;

    hidden var _now as Dictionary? = null;
    hidden var _status as String? = "Loading...";
    hidden var _busy as Boolean = false;
    // A request is out over Bluetooth; don't stack another one on it (a slow
    // phone link plus the 5 s poll would otherwise queue requests until the
    // Edge rejects them).
    hidden var _inFlight as Boolean = false;
    hidden var _bellUntil as Number = 0;
    hidden var _poll as Timer.Timer = new Timer.Timer();
    hidden var _bellTimer as Timer.Timer = new Timer.Timer();
    // [x, y, w, h, cmd] per button, rebuilt on every draw.
    hidden var _buttons as Array<Array> = [] as Array<Array>;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        refresh();
        _poll.start(method(:refresh), POLL_MS, true);
    }

    function onHide() as Void {
        _poll.stop();
    }

    // --- Proxy ------------------------------------------------------------------

    function refresh() as Void {
        if (!_busy && !_inFlight) {
            _inFlight = true;
            Api.get("/music-api/now", method(:onNow));
        }
    }

    function onNow(code as Number, data as Dictionary or String or Null) as Void {
        _busy = false;
        _inFlight = false;
        if (code == 200 && data instanceof Dictionary) {
            _now = data;
            _status = null;
        } else {
            _status = Api.errorText(code, data);
            System.println("music error " + code + ": " + _status);
        }
        WatchUi.requestUpdate();
    }

    function command(cmd as String) as Void {
        if (_inFlight) {
            _status = "Busy, try again";
            WatchUi.requestUpdate();
            return;
        }
        _busy = true;
        _inFlight = true;
        _status = "...";
        WatchUi.requestUpdate();
        Api.post("/music-api/cmd", {"cmd" => cmd}, method(:onNow));
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

    function ringBell() as Void {
        System.println("bell: " + Bell.ring());
        _bellUntil = System.getTimer() + BELL_MS;
        _bellTimer.start(method(:redraw), BELL_MS + 50, false);
        WatchUi.requestUpdate();
    }

    function redraw() as Void {
        WatchUi.requestUpdate();
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

        // Header
        var hH = (34 * s).toNumber();
        dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, hH / 2, Graphics.FONT_XTINY, "MUSIC", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var dev = (now != null && now["device"] instanceof String) ? "Spotify - " + now["device"] : "Spotify";
        dc.drawText(w - pad, hH / 2, Graphics.FONT_XTINY, Ui.fit(dc, dev, Graphics.FONT_XTINY, w / 2),
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
        var rh = hR - 12;
        var liked = active && now["liked"] == true;
        textButton(dc, pad, y, w - 2 * pad, rh, liked, Ui.FUEL, liked ? "unlike" : "like", liked ? "LIKED" : "LIKE");

        // Footer: status or the double-tap hint
        y += hR;
        Ui.hline(dc, y, w);
        var st = _status;
        dc.setColor(st != null ? Ui.WARN : Ui.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y + (h - y) / 2, Graphics.FONT_XTINY,
            Ui.fit(dc, st != null ? st : "Double-tap: bell", Graphics.FONT_XTINY, w - 2 * pad),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (System.getTimer() < _bellUntil) {
            Ui.bellBanner(dc);
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
