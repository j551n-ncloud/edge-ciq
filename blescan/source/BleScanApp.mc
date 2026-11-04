import Toybox.Application;
import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.WatchUi;

class BleScanApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var v = new BleScanView();
        BluetoothLowEnergy.setDelegate(new ScanDelegate(v));
        return [v];
    }
}
