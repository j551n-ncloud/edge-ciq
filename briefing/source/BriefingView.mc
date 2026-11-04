import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Pre-ride brief from the glance proxy (GET /garmin-api/edge-brief), laid out
// like the design canvas at 282x470:
//   header 34 | readiness 124 | weather 62 | pack 76 | plan/fuel 52 | bike 40
// with the sections stretched evenly to the real height (no footer; a status
// shows in the header instead of the update time).
// The last brief is kept in Storage, so it still shows without the phone.
class BriefingView extends WatchUi.View {

    hidden var _brief as Dictionary? = null;
    hidden var _status as String? = "Loading...";

    function initialize() {
        View.initialize();
        var cached = Application.Storage.getValue("brief");
        if (cached instanceof Dictionary) {
            _brief = cached;
        }
    }

    function onShow() as Void {
        refresh();
    }

    function refresh() as Void {
        if (Application.Properties.getValue("demoMode") == true) {
            _brief = DemoBrief.sample();
            _status = null;
            WatchUi.requestUpdate();
            return;
        }
        _status = "Updating...";
        WatchUi.requestUpdate();
        Api.get("/garmin-api/edge-brief", method(:onBrief));
    }

    function onBrief(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary) {
            _brief = data;
            _status = null;
            Application.Storage.setValue("brief", data);
        } else {
            _status = Api.errorText(code, data) + (_brief != null ? " (old data)" : "");
            System.println("brief error " + code + ": " + _status);
        }
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

        var b = _brief;
        var st = _status;
        var right = st != null ? st : ((b != null && b["at"] instanceof String) ? "updated " + b["at"] : "");

        // Header; a status (error, "Updating...") takes the update time's place.
        var hH = (34 * s).toNumber();
        dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, hH / 2, Graphics.FONT_XTINY, "BEFORE THE RIDE", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(st != null ? Ui.WARN : Ui.MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - pad, hH / 2, Graphics.FONT_XTINY, Ui.fit(dc, right, Graphics.FONT_XTINY, w / 2),
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        Ui.hline(dc, hH - 1, w);

        var y = hH;
        if (b == null) {
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, "No brief yet", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            // The design's sections (354 px under the header) stretched to
            // the height that's left; bike takes the remainder.
            var k = (h - hH) / 354.0;
            y = drawReadiness(dc, b, y, w, (124 * k).toNumber());
            y = drawWeather(dc, b, y, w, (62 * k).toNumber());
            y = drawPack(dc, b, y, w, (76 * k).toNumber());
            y = drawPlan(dc, b, y, w, (52 * k).toNumber());
            drawBike(dc, b, y, w, h - y);
        }

    }

    hidden function drawReadiness(dc as Dc, b as Dictionary, y as Number, w as Number, h as Number) as Number {
        var r = b["ready"];
        if (r instanceof Dictionary) {
            var score = r["score"] instanceof Number ? r["score"] as Number : 0;
            // Ring sized to the section (36 px at the design's 124).
            var rr = h * 36 / 124;
            var cx = Ui.PAD + rr + 6;
            var cy = y + h / 2;
            var ringColor = score >= 70 ? Ui.OK : (score >= 45 ? Ui.AMBER : 0xFF0000);
            dc.setPenWidth(8);
            dc.setColor(Ui.LINE, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, rr);
            if (score > 0) {
                dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, rr, Graphics.ARC_CLOCKWISE, 90, 90 - (360 * score / 100));
            }
            dc.setPenWidth(1);
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_NUMBER_MILD, score.toString(), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            var tx = cx + rr + 18;
            var ty = y + 14;
            var rec = r["rec"] instanceof String ? r["rec"] as String : "";
            dc.drawText(tx, ty, Graphics.FONT_SMALL, Ui.fit(dc, rec, Graphics.FONT_SMALL, w - tx - Ui.PAD), Graphics.TEXT_JUSTIFY_LEFT);
            ty += dc.getFontHeight(Graphics.FONT_SMALL) + 2;
            var notes = r["notes"];
            if (notes instanceof Array) {
                dc.setColor(Ui.WARN, Graphics.COLOR_TRANSPARENT);
                for (var i = 0; i < notes.size() && i < 3; i++) {
                    dc.drawText(tx, ty, Graphics.FONT_XTINY, Ui.fit(dc, notes[i].toString(), Graphics.FONT_XTINY, w - tx - Ui.PAD), Graphics.TEXT_JUSTIFY_LEFT);
                    ty += dc.getFontHeight(Graphics.FONT_XTINY);
                }
            }
        } else {
            Ui.label(dc, Ui.PAD, y + 10, "READINESS");
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Ui.PAD, y + h / 2, Graphics.FONT_SMALL, "No data", Graphics.TEXT_JUSTIFY_LEFT);
        }
        Ui.hline(dc, y + h - 1, w);
        return y + h;
    }

    hidden function drawWeather(dc as Dc, b as Dictionary, y as Number, w as Number, h as Number) as Number {
        var x = b["wx"];
        if (x instanceof Dictionary) {
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Ui.PAD, y + 6, Graphics.FONT_MEDIUM, x["tmin"] + "-" + x["tmax"] + " C", Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            var line = x["text"] + " - wind " + x["wind"] + " - rain " + x["rain"] + " %";
            dc.drawText(Ui.PAD, y + h - 6 - dc.getFontHeight(Graphics.FONT_XTINY), Graphics.FONT_XTINY,
                Ui.fit(dc, line, Graphics.FONT_XTINY, w * 2 / 3), Graphics.TEXT_JUSTIFY_LEFT);
            if (x["sunset"] instanceof String) {
                var dark = x["dark"] == true;
                dc.drawText(w - Ui.PAD, y + 8, Graphics.FONT_XTINY, "DARK FROM", Graphics.TEXT_JUSTIFY_RIGHT);
                dc.setColor(dark ? Ui.WARN : Ui.INK, Graphics.COLOR_TRANSPARENT);
                dc.drawText(w - Ui.PAD, y + 8 + dc.getFontHeight(Graphics.FONT_XTINY), Graphics.FONT_MEDIUM,
                    x["sunset"] as String, Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }
        Ui.hline(dc, y + h - 1, w);
        return y + h;
    }

    // Packing list as wrapping chips; "Lights" filled.
    hidden function drawPack(dc as Dc, b as Dictionary, y as Number, w as Number, h as Number) as Number {
        Ui.label(dc, Ui.PAD, y + 6, "PACK");
        var pack = b["pack"];
        var font = Graphics.FONT_XTINY;
        var ch = dc.getFontHeight(font) + 4;
        var cx = Ui.PAD;
        var cy = y + 8 + dc.getFontHeight(font);
        if (pack instanceof Array && pack.size() > 0) {
            for (var i = 0; i < pack.size(); i++) {
                var t = pack[i].toString();
                var cw = dc.getTextWidthInPixels(t, font) + 12;
                if (cx + cw > w - Ui.PAD) {
                    cx = Ui.PAD;
                    cy += ch + 4;
                }
                if (cy + ch > y + h) {
                    break;
                }
                var strong = t.equals("Lights");
                if (strong) {
                    dc.setColor(Ui.INK, Ui.INK);
                    dc.fillRectangle(cx, cy, cw, ch);
                    dc.setColor(Ui.PAPER, Graphics.COLOR_TRANSPARENT);
                } else {
                    dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
                    dc.drawRectangle(cx, cy, cw, ch);
                }
                dc.drawText(cx + cw / 2, cy + ch / 2, font, t, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                cx += cw + 4;
            }
        } else {
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Ui.PAD, cy, font, "Nothing extra", Graphics.TEXT_JUSTIFY_LEFT);
        }
        Ui.hline(dc, y + h - 1, w);
        return y + h;
    }

    // Planned ride (when the brief has one) or just the gel rhythm.
    hidden function drawPlan(dc as Dc, b as Dictionary, y as Number, w as Number, h as Number) as Number {
        var plan = b["plan"];
        var fuel = b["fuel"];
        var every = (fuel instanceof Dictionary && fuel["everyMin"] instanceof Number) ? fuel["everyMin"] : 40;
        var gelG = (fuel instanceof Dictionary && fuel["gelG"] instanceof Number) ? fuel["gelG"] : 30;
        var first = (fuel instanceof Dictionary && fuel["firstMin"] instanceof Number) ? fuel["firstMin"] as Number : 0;
        var vy = y + 6 + dc.getFontHeight(Graphics.FONT_XTINY);
        if (plan instanceof Dictionary && plan["min"] instanceof Number && (plan["min"] as Number) > 0) {
            var min = plan["min"] as Number;
            var dest = plan["dest"] instanceof String ? "TO " + (plan["dest"] as String).toUpper() : "PLANNED";
            Ui.label(dc, Ui.PAD, y + 6, Ui.fit(dc, dest, Graphics.FONT_XTINY, w / 2 - Ui.PAD));
            var dur = (min / 60) + ":" + (min % 60).format("%02d") + " h";
            if (plan["km"] instanceof Number) {
                dur += " - " + plan["km"] + " km";
            }
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(Ui.PAD, vy, Graphics.FONT_SMALL, dur, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - Ui.PAD, y + 6, Graphics.FONT_XTINY, "FUEL", Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - Ui.PAD, vy, Graphics.FONT_SMALL, plan["gels"] + " gels - " + plan["carbs"] + " g", Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            Ui.label(dc, Ui.PAD, y + 6, "FUEL");
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            // No planned ride: the field's rule without a route.
            var line = first > 0
                ? gelG + " g gel after " + (first % 60 == 0 ? (first / 60) + " h" : first + " min") + ", then every " + every + " min"
                : "1 gel (" + gelG + " g) every " + every + " min";
            dc.drawText(Ui.PAD, vy, Graphics.FONT_SMALL, Ui.fit(dc, line, Graphics.FONT_SMALL, w - 2 * Ui.PAD), Graphics.TEXT_JUSTIFY_LEFT);
        }
        Ui.hline(dc, y + h - 1, w);
        return y + h;
    }

    hidden function drawBike(dc as Dc, b as Dictionary, y as Number, w as Number, h as Number) as Number {
        var bike = b["bike"];
        if (bike instanceof Dictionary) {
            var ok = bike["ok"] == true;
            var mid = y + h / 2;
            dc.setColor(ok ? Ui.OK : 0xFF0000, ok ? Ui.OK : 0xFF0000);
            dc.fillCircle(Ui.PAD + 5, mid, 5);
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            var text = (ok ? "Bike OK - " : "Bike: ") + bike["note"];
            dc.drawText(Ui.PAD + 16, mid, Graphics.FONT_XTINY, Ui.fit(dc, text, Graphics.FONT_XTINY, w - 2 * Ui.PAD - 16),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        return y + h;
    }
}
