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
        Ams.register();
        return [v, new ScanInput(v)];
    }

    function onStop(state) as Void {
        Ams.disconnect();
    }
}

class ScanInput extends WatchUi.BehaviorDelegate {
    hidden var _view as BleScanView;

    function initialize(view as BleScanView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        _view.tapAt(xy[0], xy[1]);
        return true;
    }
}
