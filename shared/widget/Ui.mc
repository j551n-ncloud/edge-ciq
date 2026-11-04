import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

// Drawing helpers shared by the widgets.
module Ui {
    const PAD = 12;
    const FUEL = 0xFF5500;
    const OK = 0x00AA00;
    const AMBER = 0xFFAA00;
    // Theme colors, set by applyTheme(): black on white by day, white on
    // black from sunset to sunrise (widgets can't read the Edge's own night
    // mode, so they follow the sun the way its "Auto" color mode does).
    var INK = 0x000000;
    var PAPER = 0xFFFFFF;
    var MUTED = 0x555555;
    var LINE = 0xAAAAAA;
    var WARN = 0xAA5500;
    var dark = false;
    var _themeAt = -1;

    // Call at the start of onUpdate; re-checks at most once a minute.
    function applyTheme() as Void {
        var now = Time.now().value();
        if (_themeAt >= 0 && now - _themeAt < 60) {
            return;
        }
        _themeAt = now;
        dark = isDark();
        INK = dark ? 0xFFFFFF : 0x000000;
        PAPER = dark ? 0x000000 : 0xFFFFFF;
        MUTED = dark ? 0xAAAAAA : 0x555555;
        LINE = dark ? 0x555555 : 0xAAAAAA;
        WARN = dark ? 0xFFAA00 : 0xAA5500;
    }

    // Between sunset and sunrise at the weather's location (from the
    // phone); 19:00 to 07:00 when that's unknown.
    function isDark() as Boolean {
        try {
            if (Toybox has :Weather && Weather has :getSunset) {
                var cc = Weather.getCurrentConditions();
                var loc = cc != null ? cc.observationLocationPosition : null;
                if (loc != null) {
                    var now = Time.now();
                    var rise = Weather.getSunrise(loc, now);
                    var set = Weather.getSunset(loc, now);
                    if (rise != null && set != null) {
                        return now.lessThan(rise) || now.greaterThan(set);
                    }
                }
            }
        } catch (e) {
        }
        var h = System.getClockTime().hour;
        return h >= 19 || h < 7;
    }

    function label(dc as Dc, x as Number, y as Number, text as String) as Void {
        dc.setColor(MUTED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    function hline(dc as Dc, y as Number, w as Number) as Void {
        dc.setColor(LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, y, w, y);
    }

    // Text cut with "..." to fit maxW.
    function fit(dc as Dc, text as String, font as Graphics.FontType, maxW as Number) as String {
        if (dc.getTextWidthInPixels(text, font) <= maxW) {
            return text;
        }
        var s = text;
        while (s.length() > 1 && dc.getTextWidthInPixels(s + "...", font) > maxW) {
            s = s.substring(0, s.length() - 1) as String;
        }
        return s + "...";
    }


    // "1:42" from milliseconds.
    function mmss(ms as Number) as String {
        var s = ms / 1000;
        return (s / 60) + ":" + (s % 60).format("%02d");
    }
}
