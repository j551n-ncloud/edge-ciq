import Toybox.BluetoothLowEnergy;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Experiment for iPhone music control over Apple Media Service (Ams.mc).
// Step 1: lists the Apple devices the Edge sees (manufacturer data with
// Apple's company id 0x004C), strongest first; every new device goes to the
// log (GARMIN/Apps/LOGS/BLESCAN.TXT) with its raw advertising data.
// Step 2: tap one to connect and pair; with AMS found, the button at the
// bottom sends play/pause to the phone. Only iPhone-like entries (Nearby
// 0x10, Handoff 0x0C) are offered, and a connect attempt is given up after
// CONNECT_MS: a hanging one blocked the Edge's link to the phone.
class BleScanView extends WatchUi.View {
    const MAX = 40;
    const CONNECT_MS = 10000;
    hidden var _connTimer as Timer.Timer = new Timer.Timer();
    hidden var _connected as Boolean = false;
    const AMS = "89D3502B-0F36-433A-8EF4-C502AD55F8DC";

    // [ScanResult, name, rssi, apple, ams, appleType]
    hidden var _devs as Array<Array> = [] as Array<Array>;
    hidden var _state as String = "starting";
    hidden var _note as String = "Tap the strongest entry to connect";
    // [y, index into _devs] per drawn row, and the play/pause button [y, h].
    hidden var _rows as Array<Array> = [] as Array<Array>;
    hidden var _btn as Array<Number>? = null;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function onHide() as Void {
        _connTimer.stop();
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        Ams.disconnect();
    }

    // From the delegate.
    function connectedState(on as Boolean) as Void {
        _connected = on;
        if (on) {
            _connTimer.stop();
        }
    }

    function connectTimeout() as Void {
        if (_connected) {
            return;
        }
        Ams.disconnect();
        note("no connection after 10 s, released");
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function scanState(state as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        _state = (state == BluetoothLowEnergy.SCAN_STATE_SCANNING ? "scanning" : "off") + " (" + status + ")";
        System.println("scan state " + _state);
        WatchUi.requestUpdate();
    }

    function note(s as String) as Void {
        _note = s;
        System.println("note: " + s);
        WatchUi.requestUpdate();
    }

    function tapAt(x as Number, y as Number) as Void {
        var b = _btn;
        if (b != null && y >= b[0] && y < b[0] + b[1]) {
            note(Ams.send(Ams.CMD_TOGGLE));
            return;
        }
        for (var i = 0; i < _rows.size(); i++) {
            var row = _rows[i];
            if (y >= (row[0] as Number) && y < (row[0] as Number) + (row[2] as Number)) {
                connect(row[1] as Number);
                return;
            }
        }
    }

    hidden function connect(i as Number) as Void {
        var d = _devs[i];
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
        Ams.disconnect();
        System.println("connect #" + i + " connections free: "
            + BluetoothLowEnergy.getAvailableConnectionCount());
        _connected = false;
        try {
            Ams.device = BluetoothLowEnergy.pairDevice(d[0] as BluetoothLowEnergy.ScanResult);
            if (Ams.device == null) {
                note("pair refused");
                BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
            } else {
                note("connecting #" + i + " (10 s)...");
                _connTimer.start(method(:connectTimeout), CONNECT_MS, false);
            }
        } catch (e) {
            note("pair failed: " + e.getErrorMessage());
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
        }
    }

    function seen(r as BluetoothLowEnergy.ScanResult) as Void {
        var rssi = r.getRssi();
        for (var i = 0; i < _devs.size(); i++) {
            var d = _devs[i];
            if ((d[0] as BluetoothLowEnergy.ScanResult).isSameDevice(r)) {
                d[2] = rssi;
                var n = r.getDeviceName();
                if (n != null && d[1] == null) {
                    d[1] = n;
                    System.println("name " + n + " for #" + i);
                }
                WatchUi.requestUpdate();
                return;
            }
        }
        if (_devs.size() >= MAX) {
            return;
        }
        var raw = r.getRawData();
        var appleType = appleSubtype(raw);
        var ams = false;
        var uuids = r.getServiceUuids();
        var us = "";
        for (var u = uuids.next(); u != null; u = uuids.next()) {
            var s = u.toString().toUpper();
            us += s + " ";
            if (s.equals(AMS)) {
                ams = true;
            }
        }
        var name = r.getDeviceName();
        _devs.add([r, name, rssi, appleType >= 0, ams, appleType]);
        System.println("dev #" + (_devs.size() - 1) + " name=" + name + " rssi=" + rssi
            + " apple=" + (appleType >= 0 ? appleType.format("%02X") : "-") + " ams=" + ams
            + " uuids=" + us + " raw=" + hex(raw));
        WatchUi.requestUpdate();
    }

    // Apple manufacturer data (AD type 0xFF, company 0x004C): the first byte
    // after the company id is the message type (0x10 Nearby, 0x0C Handoff,
    // 0x07 AirPods, ...). -1 when not Apple.
    hidden function appleSubtype(raw as ByteArray?) as Number {
        if (raw == null) {
            return -1;
        }
        var i = 0;
        while (i < raw.size()) {
            var len = raw[i];
            if (len == 0 || i + len >= raw.size() + 1) {
                break;
            }
            if (raw[i + 1] == 0xFF && len >= 4 && raw[i + 2] == 0x4C && raw[i + 3] == 0x00) {
                return len >= 5 ? raw[i + 4] : 0;
            }
            i += len + 1;
        }
        return -1;
    }

    hidden function hex(b as ByteArray?) as String {
        if (b == null) {
            return "";
        }
        var s = "";
        for (var i = 0; i < b.size(); i++) {
            s += b[i].format("%02X");
        }
        return s;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var pad = Ui.PAD;
        dc.setColor(Ui.INK, Ui.PAPER);
        dc.clear();

        var apple = 0;
        var ams = 0;
        for (var i = 0; i < _devs.size(); i++) {
            if (_devs[i][3] == true) {
                apple++;
            }
            if (_devs[i][4] == true) {
                ams++;
            }
        }
        var f = Graphics.FONT_XTINY;
        var lh = dc.getFontHeight(f);
        dc.drawText(pad, 4, f, "BLE SCAN - " + _state, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(pad, 4 + lh, f, _devs.size() + " devices, " + apple + " Apple, " + ams + " AMS", Graphics.TEXT_JUSTIFY_LEFT);
        Ui.hline(dc, 6 + 2 * lh, w);

        // iPhone-like Apple entries only (Nearby, Handoff), strongest first.
        var order = [] as Array<Number>;
        for (var i = 0; i < _devs.size(); i++) {
            if (_devs[i][3] != true || (_devs[i][5] != 0x10 && _devs[i][5] != 0x0C)) {
                continue;
            }
            var j = 0;
            while (j < order.size() && (_devs[order[j]][2] as Number) >= (_devs[i][2] as Number)) {
                j++;
            }
            order = order.slice(0, j).addAll([i]).addAll(order.slice(j, null));
        }
        var rh = dc.getFontHeight(Graphics.FONT_SMALL) + 8;
        var bh = h / 6;
        var noteY = h - bh - 2 * lh - 8;
        _rows = [] as Array<Array>;
        var y = 10 + 2 * lh;
        for (var k = 0; k < order.size() && y + rh <= noteY; k++) {
            var d = _devs[order[k]];
            var t = d[5] as Number;
            var kind = t == 0x10 ? "Nearby" : (t == 0x0C ? "Handoff" : (t == 0x09 ? "AirPlay"
                : (t == 0x12 ? "Find My" : (t == 0x07 ? "AirPods" : "type " + t.format("%02X")))));
            dc.setColor(Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawRectangle(pad, y, w - 2 * pad, rh - 4);
            dc.drawText(pad + 6, y + (rh - 4) / 2, Graphics.FONT_SMALL, "#" + order[k] + " " + kind,
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.drawText(w - pad - 6, y + (rh - 4) / 2, Graphics.FONT_SMALL, d[2] + " dBm",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            _rows.add([y, order[k], rh - 4]);
            y += rh;
        }

        // Status of the connect attempt, then the play/pause button once
        // AMS is there.
        Ui.hline(dc, noteY - 4, w);
        dc.setColor(Ui.WARN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(pad, noteY, f, Ui.fit(dc, _note, f, w - 2 * pad), Graphics.TEXT_JUSTIFY_LEFT);
        _btn = null;
        if (Ams.remoteCommand() != null) {
            var by = h - bh - 6;
            dc.setColor(Ui.INK, Ui.INK);
            dc.fillRectangle(pad, by, w - 2 * pad, bh);
            dc.setColor(Ui.PAPER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, by + bh / 2, Graphics.FONT_MEDIUM, "PLAY / PAUSE",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            _btn = [by, bh];
        }
    }
}
