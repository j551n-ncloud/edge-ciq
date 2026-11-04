import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

// Drawing helpers shared by the widgets.
module Ui {
    const PAD = 12;
    const INK = 0x000000;
    const PAPER = 0xFFFFFF;
    const MUTED = 0x555555;
    const LINE = 0xAAAAAA;
    const FUEL = 0xFF5500;
    const OK = 0x00AA00;
    const WARN = 0xAA5500;
    const AMBER = 0xFFAA00;

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
