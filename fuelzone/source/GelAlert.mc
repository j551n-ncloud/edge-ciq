import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Full-screen takeover when a gel is due. Nothing to press: the gel is
// logged by itself 5 s later (FuelState.tick), the ride screen shows the
// seconds left.
class GelAlert extends WatchUi.DataFieldAlert {
    hidden var _num as Number;
    hidden var _planned as Number;
    hidden var _grams as Number;
    hidden var _carbs as Number;
    hidden var _rate as Number;

    function initialize(num as Number, planned as Number, grams as Number, carbs as Number, rate as Number) {
        DataFieldAlert.initialize();
        _num = num;
        _planned = planned;
        _grams = grams;
        _carbs = carbs;
        _rate = rate;
    }

    function onUpdate(dc as Dc) as Void {
        drawGelAlert(dc, _num, _planned, _grams, _carbs, _rate, CONFIRM_SEC);
    }
}

// Also drawn by the ride screen itself during the countdown, so the page
// turns orange even where the system alert doesn't show. Layout and type
// (Barlow Condensed, fonts from scripts/fonts.py) follow docs/gel-alert.png;
// y positions are text tops as a share of the screen height.
function drawGelAlert(dc as Dc, num as Number, planned as Number, grams as Number,
                      carbs as Number, rate as Number, secs as Number) as Void {
    var w = dc.getWidth();
    var h = dc.getHeight();
    var cx = w / 2;
    var c = Graphics.TEXT_JUSTIFY_CENTER;

    dc.setColor(0xFF5500, 0xFF5500);
    dc.clear();
    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
    dc.drawText(cx, (h * 0.096).toNumber(), WatchUi.loadResource(Rez.Fonts.AlertLabel), "TIME FOR A", c);
    dc.drawText(cx, (h * 0.160).toNumber(), WatchUi.loadResource(Rez.Fonts.AlertBig), "GEL", c);
    var mid = WatchUi.loadResource(Rez.Fonts.AlertMid);
    var midY = (h * 0.392).toNumber();
    dc.drawText(cx, midY, mid,
        "#" + num + (planned > 0 ? " of " + planned : "") + ", " + grams + " g", c);
    // Right under it, the gap follows the font size per device.
    dc.drawText(cx, midY + dc.getFontHeight(mid) + (h * 0.02).toNumber(), WatchUi.loadResource(Rez.Fonts.AlertSmall),
        "Carbs " + carbs + " g, now " + rate + " g/h", c);

    var m = w * 12 / 282;
    var by = (h * 0.736).toNumber();
    var bh = (h * 0.179).toNumber();
    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
    dc.fillRectangle(m, by, w - 2 * m, bh);
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    var btn = WatchUi.loadResource(Rez.Fonts.AlertButton);
    dc.drawText(cx, by + (bh - dc.getFontHeight(btn)) / 2, btn, "LOGGED IN " + secs + " S", c);
}
