import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Full-screen takeover when a gel is due. Nothing to press: the gel is
// logged by itself 3 s later (FuelState.tick), the ride screen shows the
// seconds left.
class GelAlert extends WatchUi.DataFieldAlert {
    hidden var _num as Number;
    hidden var _planned as Number;
    hidden var _grams as Number;
    hidden var _carbs as Number;
    hidden var _target as Number;

    function initialize(num as Number, planned as Number, grams as Number, carbs as Number, target as Number) {
        DataFieldAlert.initialize();
        _num = num;
        _planned = planned;
        _grams = grams;
        _carbs = carbs;
        _target = target;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Graphics.COLOR_BLACK, 0xFF5500);
        dc.clear();

        dc.drawText(cx, (h * 0.10).toNumber(), Graphics.FONT_SMALL, "TIME FOR A", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, (h * 0.17).toNumber(), Graphics.FONT_LARGE, "GEL", Graphics.TEXT_JUSTIFY_CENTER);

        var sub = "#" + _num + (_planned > 0 ? " of " + _planned : "") + ", " + _grams + " g";
        dc.drawText(cx, (h * 0.40).toNumber(), Graphics.FONT_MEDIUM, sub, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, (h * 0.52).toNumber(), Graphics.FONT_SMALL, "Carbs " + _carbs + " / " + _target + " g", Graphics.TEXT_JUSTIFY_CENTER);

        var by = (h * 0.70).toNumber();
        var bh = (h * 0.18).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(12, by, w - 24, bh);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, by + bh / 2, Graphics.FONT_MEDIUM, "LOGGED IN 3 S",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
