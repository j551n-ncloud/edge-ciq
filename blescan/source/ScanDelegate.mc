import Toybox.BluetoothLowEnergy;
import Toybox.Lang;

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
}
