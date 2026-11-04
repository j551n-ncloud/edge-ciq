import Toybox.BluetoothLowEnergy;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Lists the Bluetooth LE devices the Edge sees, strongest first. Marks Apple
// devices (manufacturer data with Apple's company id 0x004C) and any that
// advertise the Apple Media Service. Every new device goes to the log
// (GARMIN/Apps/LOGS/BLESCAN.TXT) with its raw advertising data.
class BleScanView extends WatchUi.View {
    const MAX = 40;
    const AMS = "89D3502B-0F36-433A-8EF4-C502AD55F8DC";

    // [ScanResult, name, rssi, apple, ams, appleType]
    hidden var _devs as Array<Array> = [] as Array<Array>;
    hidden var _state as String = "starting";

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
    }

    function onHide() as Void {
        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
    }

    function scanState(state as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        _state = (state == BluetoothLowEnergy.SCAN_STATE_SCANNING ? "scanning" : "off") + " (" + status + ")";
        System.println("scan state " + _state);
        WatchUi.requestUpdate();
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

        // Strongest first.
        var order = [] as Array<Number>;
        for (var i = 0; i < _devs.size(); i++) {
            var j = 0;
            while (j < order.size() && (_devs[order[j]][2] as Number) >= (_devs[i][2] as Number)) {
                j++;
            }
            order = order.slice(0, j).addAll([i]).addAll(order.slice(j, null));
        }
        var y = 10 + 2 * lh;
        for (var k = 0; k < order.size() && y + lh <= h; k++) {
            var d = _devs[order[k]];
            var n = d[1] != null ? d[1] as String : "(no name)";
            var tag = d[4] == true ? " AMS" : (d[3] == true ? " Apple " + (d[5] as Number).format("%02X") : "");
            dc.setColor(d[3] == true ? Ui.FUEL : Ui.INK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pad, y, f, Ui.fit(dc, n + tag, f, w - 2 * pad - 50), Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Ui.MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - pad, y, f, d[2] + " dBm", Graphics.TEXT_JUSTIFY_RIGHT);
            y += lh;
        }
    }
}
