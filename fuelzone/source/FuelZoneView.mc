import Toybox.Activity;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Background;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Full-screen ride layout (use it in a 1-field data page). Bands follow the
// design spec at 282x470, scaled to the actual field height:
//   A heart rate 112 | B 2x2 grid 176 | C fuel 140 | D route 42
// Smaller fields fall back to a compact gel countdown.
class FuelZoneView extends WatchUi.DataField {
    const PAD = 12;
    const FUEL = 0xFF5500;
    // How often the ride screen refreshes the live-ride snapshot in Storage
    // (the background sender posts the latest one every 5 min).
    const SNAP_MS = 30000;

    hidden var _fuel as FuelState;
    hidden var _zones as Zones;
    hidden var _demo as Boolean = false;
    hidden var _liveOn as Boolean = true;
    hidden var _lastSnapAt as Number = -SNAP_MS;
    // Starts above any demo timer so the first sample sets up the demo ride.
    hidden var _demoTimer as Number = 0x7FFFFFFF;

    hidden var _hr as Number? = null;
    hidden var _pow as Array<Number> = [] as Array<Number>;
    // The power slot shows climbing until a power meter has sent data once.
    hidden var _hasPower as Boolean = false;
    hidden var _ascent as Number? = null;
    hidden var _speed as Float? = null;
    hidden var _cad as Number? = null;
    hidden var _timer as Number = 0;
    hidden var _dist as Float? = null;
    hidden var _toDest as Float? = null;
    hidden var _avgSpeed as Float? = null;


    hidden var _carbsField as FitContributor.Field?;
    hidden var _gelsField as FitContributor.Field?;

    hidden var _fg as Number = Graphics.COLOR_BLACK;
    hidden var _bg as Number = Graphics.COLOR_WHITE;
    hidden var _muted as Number = 0x555555;
    hidden var _line as Number = 0xAAAAAA;

    function initialize() {
        DataField.initialize();
        _fuel = new FuelState();
        _zones = new Zones();
        loadSettings();

        var saved = Application.Storage.getValue("fuel");
        if (saved instanceof Array) {
            _fuel.restore(saved);
        }

        // Session totals land on the ride in Garmin Connect.
        _carbsField = createField("carbs", 0, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "g"});
        _gelsField = createField("gels", 1, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "gels"});
        writeFit();
    }

    function loadSettings() as Void {
        _fuel.configure(numProp("gelGrams", 30), numProp("maxCarbsPerHour", 90),
            numProp("plannedGels", 0), numProp("plannedMinutes", 0), numProp("noRouteStartMin", 60));
        _zones.load(strProp("hrZones", ""));
        _liveOn = boolProp("liveTracking", true);
        _demo = boolProp("demoMode", false);
        // The simulator has no HR zones: sample ones, so the demo shows the
        // zone raising the carb rate.
        if (_demo && _zones.limits == null) {
            _zones.load("120,140,160,175");
        }
    }

    // --- Activity callbacks ---------------------------------------------------

    function compute(info as Activity.Info) as Void {
        _hr = info.currentHeartRate;
        var p = info.currentPower;
        if (p != null) {
            _hasPower = true;
            _pow.add(p);
            if (_pow.size() > 3) {
                _pow = _pow.slice(1, null);
            }
        }
        _ascent = info.totalAscent;
        _speed = info.currentSpeed;
        _cad = info.currentCadence;
        var t = info.timerTime;
        _timer = (t == null) ? 0 : t;
        _dist = info.elapsedDistance;
        _toDest = info.distanceToDestination;
        _avgSpeed = info.averageSpeed;

        var running = info.timerState == Activity.TIMER_STATE_ON;
        if (_demo) {
            var f = DemoFeed.sample(System.getTimer());
            // Loop restart (and first sample): 3 gels so far, the next one
            // nearly due, 5 planned. Compared against the demo's own last
            // timer, not _timer, which compute() already overwrote above.
            if ((f[3] as Number) < _demoTimer) {
                _fuel.reset();
                _fuel.gelsTaken = 3;
                // 1.5 g short: due ~12 s in at 45 g/h (the simulator's
                // zones put the flat in Z2) and 10x speed.
                _fuel.needG = _fuel.gelGrams - 1.5;
                _fuel.plannedGels = 5;
                // 5 s of real time at the demo's 10x.
                _fuel.confirmMs = 5000 * DemoFeed.SPEEDUP;
            }
            _hr = f[0] as Number;
            _speed = (f[1] as Numeric).toFloat();
            _cad = f[2] as Number;
            _timer = f[3] as Number;
            _demoTimer = _timer;
            _dist = (f[4] as Numeric).toFloat();
            _ascent = ((f[5] as Numeric).toFloat() - 120.0).toNumber();
            running = true;
        }

        _fuel.update(_timer, estTotalMs(), _hr == null ? 0 : _zones.zoneFor(_hr as Number));
        if (running && _fuel.shouldAlert(_timer)) {
            raiseGelAlert();
            save();
        }
        // Live ride: refresh the snapshot the background sender posts.
        if (!_demo && _liveOn && Application.Storage.getValue("liveId") != null
                && System.getTimer() - _lastSnapAt >= SNAP_MS) {
            saveSnapshot(info, running ? "ride" : "paused");
        }

        // The alert's 5 s countdown ran out: log the gel.
        if (running && _fuel.tick(_timer)) {
            save();
            writeFit();
            if (!_demo && Attention has :playTone) {
                Attention.playTone(Attention.TONE_SUCCESS);
            }
        }
    }

    function onTimerStart() as Void {
        startLive();
    }

    function onTimerResume() as Void {
        startLive();
    }

    // Called when the ride is saved or discarded.
    function onTimerReset() as Void {
        rememberSpeed();
        stopLive();
        _fuel.reset();
        _pow = [] as Array<Number>;
        _hasPower = false;
        save();
    }

    // Expected ride length from the route: timer so far plus distance left
    // at this ride's average speed. In the first 10 min (warm-up, traffic
    // lights) the average of past rides instead, 25 km/h before the first
    // one. -1 without a route.
    hidden function estTotalMs() as Number {
        var rest = _toDest;
        if (rest == null || rest <= 0) {
            return -1;
        }
        var v = _avgSpeed;
        if (v == null || v < 2.0 || _timer < 600000) {
            var past = Application.Storage.getValue("pastSpeed");
            v = past instanceof Float ? past : 6.94;
        }
        return _timer + (rest / v * 1000).toNumber();
    }

    // Average speed of a finished ride of 30 min or more, half-weighted
    // into the past rides' value (m/s).
    hidden function rememberSpeed() as Void {
        var v = _avgSpeed;
        if (_demo || v == null || v < 2.0 || _timer < 1800000) {
            return;
        }
        var past = Application.Storage.getValue("pastSpeed");
        Application.Storage.setValue("pastSpeed", past instanceof Float ? (past + v) / 2.0 : v);
    }

    // --- Live ride --------------------------------------------------------------

    // New ride id on the first start, and the 5 min background sender.
    hidden function startLive() as Void {
        if (!_liveOn || !(Toybox has :Background)) {
            return;
        }
        if (Application.Storage.getValue("liveId") == null) {
            Application.Storage.setValue("liveId", Time.now().value());
        }
        if (Background.getTemporalEventRegisteredTime() == null) {
            Background.registerForTemporalEvent(new Time.Duration(300));
        }
    }

    // Last snapshot marked done, sender off. The proxy also ends a ride after
    // 20 min of silence, since a background post after the ride is not certain.
    hidden function stopLive() as Void {
        if (Application.Storage.getValue("liveId") != null) {
            saveSnapshot(null, "done");
        }
        if (Toybox has :Background) {
            Background.deleteTemporalEvent();
        }
        Application.Storage.deleteValue("liveId");
    }

    hidden function saveSnapshot(info as Activity.Info?, st as String) as Void {
        var snap = {
            "id" => Application.Storage.getValue("liveId"),
            "t" => _timer,
            "st" => st,
            "d" => _dist == null ? 0 : (_dist as Float).toNumber(),
            "hr" => _hr,
            "z" => _hr == null ? null : _zones.zoneFor(_hr as Number),
            "g" => _fuel.gelsTaken,
            "c" => _fuel.carbsTaken(),
            "asc" => _ascent,
            "spd" => _speed == null ? null : ((_speed as Float) * 3.6).toNumber()
        };
        var loc = info != null ? info.currentLocation : null;
        if (loc != null) {
            var deg = loc.toDegrees();
            snap["lat"] = deg[0].toFloat();
            snap["lon"] = deg[1].toFloat();
        }
        Application.Storage.setValue("live", snap);
        _lastSnapAt = System.getTimer();
    }

    // --- Drawing --------------------------------------------------------------

    function onUpdate(dc as Dc) as Void {
        // Gel due: the whole page is the alert until it's logged.
        if (_fuel.counting() && dc.getHeight() >= 300 && dc.getWidth() >= 200) {
            drawGelAlert(dc, _fuel.gelsTaken + 1, _fuel.plannedGels, _fuel.gelGrams,
                _fuel.carbsTaken(), _fuel.rate, _fuel.countdownSec(_timer));
            return;
        }
        drawScreen(dc);
    }

    hidden function drawScreen(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var night = getBackgroundColor() == Graphics.COLOR_BLACK;
        _bg = night ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
        _fg = night ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        _muted = night ? 0xAAAAAA : 0x555555;
        _line = night ? 0x555555 : 0xAAAAAA;

        dc.setColor(_fg, _bg);
        dc.clear();

        if (h < 300 || w < 200) {
            drawCompact(dc, w, h);
            return;
        }

        var s = h / 470.0;
        var hA = (112 * s).toNumber();
        var hB = (176 * s).toNumber();
        var hC = (140 * s).toNumber();
        drawHr(dc, 0, w, hA);
        drawGrid(dc, hA, w, hB);
        drawFuel(dc, hA + hB, w, hC);
        drawRoute(dc, hA + hB + hC, w, h - hA - hB - hC);
    }

    hidden function drawHr(dc as Dc, y as Number, w as Number, h as Number) as Void {
        label(dc, PAD, y + 6, "HEART RATE");
        var hr = _hr;
        // Smaller screens (Edge 840): the hot font would run into the label.
        // Number fonts carry ~8 px of empty space on top, hence the slack.
        var room = h - 30 - dc.getFontHeight(Graphics.FONT_XTINY) + 8;
        var hrFont = dc.getFontHeight(Graphics.FONT_NUMBER_HOT) <= room
            ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_MEDIUM;
        value(dc, PAD, y + h - 24, hrFont, hr == null ? "--" : hr.toString(), "bpm", _fg);

        var z = (hr == null) ? 0 : _zones.zoneFor(hr);
        if (z > 0) {
            var pillText = "Z" + z;
            var pf = Graphics.FONT_MEDIUM;
            var pw = dc.getTextWidthInPixels(pillText, pf) + 16;
            var ph = dc.getFontHeight(pf);
            dc.setColor(ZoneStyle.COLORS[z - 1], ZoneStyle.COLORS[z - 1]);
            dc.fillRectangle(w - PAD - pw, y + 8, pw, ph);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - PAD - pw / 2, y + 8, pf, pillText, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - PAD, y + 10 + ph, Graphics.FONT_XTINY,
                ZoneStyle.NAMES[z - 1] + " " + _zones.rangeText(z), Graphics.TEXT_JUSTIFY_RIGHT);
        }

        var gap = 3;
        var segW = (w - 2 * PAD - 4 * gap) / 5;
        var barY = y + h - 18;
        for (var i = 0; i < 5; i++) {
            var x = PAD + i * (segW + gap);
            if (i + 1 == z) {
                dc.setColor(ZoneStyle.COLORS[i], ZoneStyle.COLORS[i]);
                dc.fillRectangle(x, barY, segW, 14);
            } else {
                dc.setColor(_line, _line);
                dc.fillRectangle(x, barY + 8, segW, 6);
            }
        }
        hline(dc, y + h - 1, w);
    }

    hidden function drawGrid(dc as Dc, y as Number, w as Number, h as Number) as Void {
        var cw = w / 2;
        var ch = h / 2;
        if (_hasPower) {
            cell(dc, 0, y, cw, ch, "POWER 3s", powerText(), "W");
        } else {
            var a = _ascent;
            cell(dc, 0, y, cw, ch, "ASCENT", a == null ? "--" : a.toString(), "m");
        }
        cell(dc, cw, y, w - cw, ch, "SPEED", speedText(), "km/h");
        var cad = _cad;
        cell(dc, 0, y + ch, cw, h - ch, "CADENCE", cad == null ? "--" : cad.toString(), "rpm");
        cell(dc, cw, y + ch, w - cw, h - ch, "RIDE TIME", fmtDuration(_timer), null);

        dc.setColor(_line, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cw, y, cw, y + h);
        hline(dc, y + ch, w);
        hline(dc, y + h - 1, w);
    }

    hidden function drawFuel(dc as Dc, y as Number, w as Number, h as Number) as Void {
        if (!_fuel.enabled) {
            label(dc, PAD, y + 6, "FUEL");
            dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
            dc.drawText(PAD, y + h / 2, Graphics.FONT_SMALL, "No gels (route < 60 min)", Graphics.TEXT_JUSTIFY_LEFT);
            hline(dc, y + h - 1, w);
            return;
        }

        var ms = _fuel.msUntilNext(_timer);
        // During the alert's countdown: seconds until the gel is logged.
        var counting = _fuel.counting();
        label(dc, PAD, y + 6, counting ? "GEL NOW, LOGGED IN"
            : (_fuel.beforeStart(_timer) ? "FIRST GEL IN" : "NEXT GEL IN"));
        var night = _bg == Graphics.COLOR_BLACK;
        if (counting) {
            value(dc, PAD, y + (h * 0.60).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
                _fuel.countdownSec(_timer).toString(), "s", FUEL);
        } else {
            value(dc, PAD, y + (h * 0.60).toNumber(), Graphics.FONT_NUMBER_MEDIUM,
                ms < 0 ? "--" : fmtDuration(ms), "min", night ? FUEL : _fg);
        }

        // Carbs eaten so far and the current rate, top right.
        dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - PAD, y + 6, Graphics.FONT_XTINY,
            _fuel.rate > 0 ? "CARBS, " + _fuel.rate + " G/H" : "CARBS", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(_fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - PAD, y + 6 + dc.getFontHeight(Graphics.FONT_XTINY), Graphics.FONT_MEDIUM,
            _fuel.carbsTaken() + " g", Graphics.TEXT_JUSTIFY_RIGHT);

        // Progress towards the next gel.
        var barY = y + (h * 0.66).toNumber();
        var barW = w - 2 * PAD;
        dc.setColor(_line, _line);
        dc.fillRectangle(PAD, barY, barW, 8);
        dc.setColor(FUEL, FUEL);
        dc.fillRectangle(PAD, barY, (barW * _fuel.progress(_timer)).toNumber(), 8);

        // One dot per planned gel (or per gel so far + the next one).
        var taken = _fuel.gelsTaken;
        var planned = _fuel.plannedGels;
        var n = planned > 0 ? planned : taken + 1;
        if (n > 8) {
            n = 8;
        }
        var dotY = y + (h * 0.86).toNumber();
        for (var i = 0; i < n; i++) {
            var cx = PAD + 7 + i * 20;
            if (i < taken) {
                dc.setColor(FUEL, FUEL);
                dc.fillCircle(cx, dotY, 7);
            } else {
                dc.setColor(_line, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawCircle(cx, dotY, 6);
                dc.setPenWidth(1);
            }
        }
        dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
        var gelText = planned > 0 ? taken + " of " + planned + " gels" : taken + " gels";
        dc.drawText(w - PAD, dotY, Graphics.FONT_XTINY, gelText,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        hline(dc, y + h - 1, w);
    }

    hidden function drawRoute(dc as Dc, y as Number, w as Number, h as Number) as Void {
        var mid = y + h / 2;
        var d = _dist;
        var km = d == null ? "--" : (d / 1000.0).format("%.1f");
        dc.setColor(_fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(PAD, mid, Graphics.FONT_MEDIUM, km + " km", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var rest = _toDest;
        if (rest != null && rest > 0) {
            dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - PAD, mid, Graphics.FONT_XTINY, (rest / 1000.0).format("%.1f") + " km to go",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // Any field smaller than full screen: just the gel countdown.
    hidden function drawCompact(dc as Dc, w as Number, h as Number) as Void {
        dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 2, Graphics.FONT_XTINY, "GEL IN", Graphics.TEXT_JUSTIFY_CENTER);
        var ms = _fuel.msUntilNext(_timer);
        dc.setColor(_fuel.counting() ? FUEL : _fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 6, Graphics.FONT_NUMBER_MEDIUM, ms < 0 ? "--" : fmtDuration(ms),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --- Helpers --------------------------------------------------------------

    hidden function cell(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                         title as String, text as String, unit as String?) as Void {
        label(dc, x + PAD, y + 6, title);
        var font = fitFont(dc, text, w - 2 * PAD - (unit == null ? 0 : 30));
        value(dc, x + PAD, y + h - 6, font, text, unit, _fg);
    }

    hidden function fitFont(dc as Dc, text as String, maxW as Number) as Graphics.FontType {
        var fonts = [Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_MEDIUM];
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxW) {
                return fonts[i];
            }
        }
        return Graphics.FONT_SMALL;
    }

    hidden function label(dc as Dc, x as Number, y as Number, text as String) as Void {
        dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Value with its baseline area ending at yBottom, unit right after it.
    hidden function value(dc as Dc, x as Number, yBottom as Number, font as Graphics.FontType,
                          text as String, unit as String?, color as Number) as Void {
        var fh = dc.getFontHeight(font);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, yBottom - fh, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        if (unit != null) {
            var tw = dc.getTextWidthInPixels(text, font);
            var uh = dc.getFontHeight(Graphics.FONT_XTINY);
            dc.setColor(_muted, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + tw + 4, yBottom - uh - 4, Graphics.FONT_XTINY, unit, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    hidden function hline(dc as Dc, y as Number, w as Number) as Void {
        dc.setColor(_line, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, y, w, y);
    }

    hidden function powerText() as String {
        if (_pow.size() == 0) {
            return "--";
        }
        var sum = 0;
        for (var i = 0; i < _pow.size(); i++) {
            sum += _pow[i];
        }
        return (sum / _pow.size()).toString();
    }

    hidden function speedText() as String {
        var s = _speed;
        return s == null ? "--" : (s * 3.6).format("%.1f");
    }

    hidden function raiseGelAlert() as Void {
        if (WatchUi.DataField has :showAlert) {
            showAlert(new GelAlert(_fuel.gelsTaken + 1, _fuel.plannedGels, _fuel.gelGrams,
                _fuel.carbsTaken(), _fuel.rate));
        }
        // Muted in demo mode, the simulator loops the ride.
        if (!_demo && Attention has :playTone) {
            Attention.playTone(Attention.TONE_ALERT_HI);
        }
    }

    hidden function save() as Void {
        Application.Storage.setValue("fuel", _fuel.toArray());
    }

    hidden function writeFit() as Void {
        var c = _carbsField;
        var g = _gelsField;
        if (c != null) {
            c.setData(_fuel.carbsTaken());
        }
        if (g != null) {
            g.setData(_fuel.gelsTaken);
        }
    }

    hidden function numProp(key as String, dflt as Number) as Number {
        var v = Application.Properties.getValue(key);
        return (v instanceof Number) ? v : dflt;
    }

    hidden function strProp(key as String, dflt as String) as String {
        var v = Application.Properties.getValue(key);
        return (v instanceof String) ? v : dflt;
    }

    hidden function boolProp(key as String, dflt as Boolean) as Boolean {
        var v = Application.Properties.getValue(key);
        return (v instanceof Boolean) ? v : dflt;
    }
}

// "1:24:10" from 1h on, else "15:50".
function fmtDuration(ms as Number) as String {
    var s = ms / 1000;
    var h = s / 3600;
    var m = (s % 3600) / 60;
    var sec = s % 60;
    if (h > 0) {
        return Lang.format("$1$:$2$:$3$", [h, m.format("%02d"), sec.format("%02d")]);
    }
    return Lang.format("$1$:$2$", [m, sec.format("%02d")]);
}
