import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;

class ScanDelegate extends BluetoothLowEnergy.BleDelegate {
    hidden var _view as BleScanView;

    function initialize(view as BleScanView) {
        BleDelegate.initialize();
        _view = view;
    }

    function onScanResults(results as BluetoothLowEnergy.Iterator) as Void {
        for (var r = results.next(); r != null; r = results.next()) {
            _view.seen(r as BluetoothLowEnergy.ScanResult);
        }
    }

    function onScanStateChange(state as BluetoothLowEnergy.ScanState, status as BluetoothLowEnergy.Status) as Void {
        _view.scanState(state, status);
    }

    function onProfileRegister(uuid as BluetoothLowEnergy.Uuid, status as BluetoothLowEnergy.Status) as Void {
        _view.note("profile " + (status == BluetoothLowEnergy.STATUS_SUCCESS ? "ok" : "failed " + status));
    }

    function onConnectedStateChanged(device as BluetoothLowEnergy.Device, state as BluetoothLowEnergy.ConnectionState) as Void {
        _view.connectedState(state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED);
        if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
            var svcs = "";
            var it = device.getServices();
            for (var s = it.next(); s != null; s = it.next()) {
                svcs += (s as BluetoothLowEnergy.Service).getUuid().toString() + " ";
            }
            System.println("connected, services: " + svcs);
            _view.note(Ams.remoteCommand() != null ? "connected, AMS found!" : "connected, no AMS");
        } else {
            _view.note("disconnected");
        }
    }

    function onCharacteristicWrite(ch as BluetoothLowEnergy.Characteristic, status as BluetoothLowEnergy.Status) as Void {
        _view.note("write " + (status == BluetoothLowEnergy.STATUS_SUCCESS ? "ok" : "status " + status));
    }
}
